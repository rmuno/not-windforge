class_name IslandGen
extends RefCounted

## Deterministic, SEEDED procedural floating-island generation (Sprint 2 payoff:
## "make the world worth flying to"). Populates a `Terrain`'s resident data grid
## with coherent island blobs scattered across a real, generous world region,
## banded by altitude per docs/WORLD_SPEC.md.
##
## DATA-ONLY. Generation writes cells (Terrain.set_cell / fill_rect) — no nodes,
## no colliders, no rendering. Chunks stay inert until streaming promotes them
## near a focus (the whole resident-world guarantee, DECISIONS 2026-08-18). It
## runs ONCE at world build, so there is zero per-frame cost.
##
## DETERMINISTIC. A fixed seed produces a byte-identical world: one seeded
## RandomNumberGenerator drives a fixed candidate lattice in a fixed order, so
## tests can pin the world and play is reproducible. Change the seed → a
## different world.
##
## BANDED (WORLD_SPEC / owner survey). Density is a property of altitude band:
##   * NORMAL inside the three bands (top / mid / deep);
##   * VERY SPARSE in the two horizontal band gaps;
##   * NONE in the vertical wind columns (the edge downdrafts and the centre
##     updraft) — those are the free-fall / free-climb travel routes and must
##     stay clear sky;
##   * NONE in the lava floor band.
## Per-band MATERIALS come from TerrainDB.band_materials (common/lighter high,
## exotic/valuable deep).
##
## AIRSPACE, GENERATION-ONLY. Banding queries reuse the tested Airspace band
## model by setting `Airspace.bounds` to the world rect for the duration of
## generation, then RESTORING it. This round the band model shapes PLACEMENT
## only; it is deliberately NOT left active on ships (that would turn wind, the
## lighter-top gravity and the hard ceiling on mid-flight — a surprise feel
## change flagged for its own round). See docs/DECISIONS.md.

## The world, in CELL coordinates (scale-agnostic — px extent follows cell_px at
## whatever world_scale). Centred on the origin so SHIP_START (~origin) lands in
## the MID band. 96×72 chunks of 32 cells = 3072×2304 cells.
##   Memory: sparse-by-chunk (DECISIONS 2026-08-22). Fully solid it would be
##   96×72 = 6912 chunks × 1 KiB = ~6.75 MiB resident; but the sky is mostly air,
##   realistic banded coverage is well under 15% of chunks, so the real cost is
##   ~1 MiB — trivial against the desktop budget (DECISIONS 2026-08-18 sizes the
##   full 29×18-square original at a few hundred MB worst case). Empty sky costs
##   nothing because an all-air chunk has no dictionary entry at all.
const WORLD_CELLS := Rect2i(-1536, -1152, 3072, 2304)

## The default world seed — a fixed number gives a fixed world. Exposed through
## world.gd's `world_seed` export so the owner can reroll.
const DEFAULT_SEED := 20260822

## Candidate island centres sit on a lattice of this spacing (cells), each
## jittered by ±JITTER so the world does not read as a grid.
const SPACING := 96
const JITTER := 38

## Island body radius range (cells). Bodies are ellipses (flatter than wide) so
## they read as islands with a surface, not spheres. R_MIN keeps every placed
## island a real coherent cluster (never a stray single cell).
const R_MIN := 4
const R_MAX := 15

## Pocket radius as a fraction of the (smaller) body radius — the ore/exotic core.
const POCKET_FRAC := 0.42

## Keep-out (cells, Chebyshev from origin): the starting neighbourhood. The
## starter ship, the enemy hulk and the whale all spawn within ~95 cells of the
## origin; generated islands are excluded from this box so nothing spawns embedded
## in terrain and the immediate spawn sky stays as it was. The guaranteed spawn
## floor is placed here explicitly (below), as the deliberate exception.
const SPAWN_CLEAR := 220


## Fill `terrain` with the seeded, banded world. `world` is the cell rect to
## populate (defaults to WORLD_CELLS); `seed` selects the world.
static func generate(terrain: Terrain, seed_value: int = DEFAULT_SEED,
		world: Rect2i = WORLD_CELLS) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Activate the band model over the world rect FOR PLACEMENT, in px so it is
	# correct if this is ever left active on ships. Restored at the end — this
	# round is generation-only (no wind/gravity/ceiling change in flight).
	var prev_bounds := Airspace.bounds
	var cp := terrain.cell_px()
	Airspace.bounds = Rect2(Vector2(world.position) * cp, Vector2(world.size) * cp)

	# Guaranteed solid ground under SHIP_START (origin), placed first so nothing
	# below overwrites it. Kept within the old hand-placed floor's footprint so
	# the startup/mining checks keep their known solid cells.
	_spawn_floor(terrain)

	# Walk the candidate lattice in a fixed order. Every candidate draws the SAME
	# number of RNG values whether or not it ends up placing an island, so the
	# stream stays aligned and the world is reproducible.
	var gx := world.position.x
	while gx < world.end.x:
		var gy := world.position.y
		while gy < world.end.y:
			var cx := gx + rng.randi_range(-JITTER, JITTER)
			var cy := gy + rng.randi_range(-JITTER, JITTER)
			var place_roll := rng.randf()
			var radius := rng.randi_range(R_MIN, R_MAX)
			var shape_seed := rng.randi()
			gy += SPACING

			var centre := Vector2i(cx, cy)
			# Spawn keep-out: leave the starting neighbourhood as clear sky.
			if maxi(absi(cx), absi(cy)) <= SPAWN_CLEAR:
				continue
			# NONE in the vertical wind columns — and never let a body spill in.
			if _touches_wind_column(cx, radius, cp):
				continue
			var band := Airspace.band_at(Vector2(centre) * cp)
			if place_roll > _band_density(band):
				continue
			_place_island(terrain, centre, radius, band, shape_seed)
		gx += SPACING

	Airspace.bounds = prev_bounds


## Placement probability per band: normal in the three bands, very sparse in the
## gaps, none in the lava floor / inactive. This is THE banding knob — forcing it
## to a constant (the break-the-fix) collapses the density difference the tests
## assert.
static func _band_density(band: int) -> float:
	match band:
		Airspace.Band.TOP:
			return 0.72   # the rich, hostile height — islands (and whales) frequent
		Airspace.Band.MID:
			return 0.58   # home
		Airspace.Band.DEEP:
			return 0.62   # the deep — many islands, the exotic ore
		Airspace.Band.GAP_LOW, Airspace.Band.GAP_HIGH:
			return 0.10   # VERY SPARSE — occasional landfall on the wind route
	return 0.0            # LAVA / NONE — clear


## True if an island of the given radius centred at cell-x `cx` would touch a
## vertical wind column (either edge downdraft or the centre updraft). Checked in
## x-fraction of the world so it tracks the Airspace geometry exactly; the body's
## full x-extent is tested (and centre-straddle caught) so no cell ever enters a
## column — the "downdraft columns are empty" guarantee.
static func _touches_wind_column(cx: int, radius: int, cp: float) -> bool:
	var left := Airspace.x_frac(float(cx - radius) * cp)
	var right := Airspace.x_frac(float(cx + radius) * cp)
	for fx in [left, right]:
		if fx <= Airspace.EDGE_W or fx >= 1.0 - Airspace.EDGE_W:
			return true
		if absf(fx - 0.5) <= Airspace.CENTRE_HALF_W:
			return true
	# The body spans across the centre column even if neither edge sits inside it.
	return left < 0.5 and right > 0.5


## Paint one coherent island: an elliptical BODY of the band's body material, a
## thin surface CAP on its top, and an ore/exotic POCKET buried in its lower
## centre. The ellipse guarantees a single connected cluster (coherent, not
## per-cell noise); cap and pocket only overwrite interior body cells, so
## connectivity is preserved.
static func _place_island(terrain: Terrain, centre: Vector2i, radius: int,
		band: int, shape_seed: int) -> void:
	var mats := TerrainDB.band_materials(band)
	var rx := radius
	var ry := maxi(3, int(round(radius * 0.7)))   # flatter than wide — an island
	var body: int = mats["body"]

	# BODY: every cell inside the ellipse. A little deterministic edge wobble
	# (from shape_seed) roughens the outline without ever breaking the interior.
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			var nx := float(dx) / float(rx)
			var ny := float(dy) / float(ry)
			var wobble := 0.10 * sin(float(shape_seed % 17) + float(dx) * 0.7 + float(dy) * 0.9)
			if nx * nx + ny * ny <= 1.0 - wobble:
				terrain.set_cell(centre + Vector2i(dx, dy), body)

	# CAP: the top row(s) of each column get the surface material (topsoil look).
	var cap: int = mats["cap"]
	var cap_rows := 2 if radius >= 9 else 1
	for dx in range(-rx, rx + 1):
		var nx := float(dx) / float(rx)
		if absf(nx) > 1.0:
			continue
		var top := int(floor(float(ry) * sqrt(maxf(0.0, 1.0 - nx * nx))))
		for k in cap_rows:
			var c := centre + Vector2i(dx, -top + k)
			if terrain.is_solid(c):
				terrain.set_cell(c, cap)

	# POCKET: the ore/exotic core, buried below the island's midline so it is
	# genuinely enclosed by the body (a reason to dig in).
	var pocket: int = mats["pocket"]
	var pr := maxi(1, int(round(minf(rx, ry) * POCKET_FRAC)))
	var pcentre := centre + Vector2i(0, int(round(ry * 0.3)))
	for dy in range(-pr, pr + 1):
		for dx in range(-pr, pr + 1):
			if dx * dx + dy * dy <= pr * pr:
				var c := pcentre + Vector2i(dx, dy)
				if terrain.is_solid(c):   # only carve pocket where the body exists
					terrain.set_cell(c, pocket)


## Guaranteed starting ground under SHIP_START (~origin). A strict SUBSET of the
## old hand-placed floor's footprint (same top row, narrower) so the existing
## pilot/startup/mining checks keep their known solid cells: (0,8) is dirt,
## (6,9) is solid, and the belly-drop lands on it. Dirt cap over a stone body,
## with a starter ore pocket to dig.
static func _spawn_floor(terrain: Terrain) -> void:
	terrain.fill_rect(Rect2i(-96, 8, 192, 12), TerrainDB.Type.STONE)
	terrain.fill_rect(Rect2i(-96, 8, 192, 2), TerrainDB.Type.DIRT)
	terrain.fill_rect(Rect2i(-6, 13, 12, 4), TerrainDB.Type.ORE)
