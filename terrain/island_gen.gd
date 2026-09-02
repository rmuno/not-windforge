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
const WORLD_CELLS := Rect2i(-3072, -2304, 6144, 4608)  # halved 2026-08-26 (owner: "the world now feels way too large... cut the dimensions in half, map included"). Was (-6144,-4608,12288,9216).

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


## The world cell rect at a given terrain SUBDIV. At subdiv=1 this is WORLD_CELLS
## (the coarse world). At subdiv=S it is S× bigger in CELLS but the SAME PX extent
## (cell_px shrinks by S), so the world occupies the same space at finer detail.
## world.gd frames its boundary walls with this so the wall px never move.
static func world_cells(sub: int) -> Rect2i:
	var s := maxi(sub, 1)
	return Rect2i(WORLD_CELLS.position * s, WORLD_CELLS.size * s)


## LAZY, REGION-AT-A-TIME GENERATION (2026-08-24 — the ×4 world). The candidate
## lattice is anchored at cell 0 in ABSOLUTE index space: candidate (i, j) sits
## at cell (i·SPACING·sub, j·SPACING·sub) and draws its OWN RandomNumberGenerator
## seeded hash([seed, i, j]) — deterministic regardless of generation ORDER, and
## invariant under both terrain SUBDIV (indices don't scale) and future world
## EXTENT changes (growing the rect adds rim candidates without moving existing
## ones). This replaced the single serial RNG stream because a ×4-linear world
## made eager generation a ~25 s boot stall ("no loading screens ever" — the
## charter): now the world generates region by region as foci approach
## (ensure_generated, driven from world._stream_terrain), and world build only
## plants the spawn floor (prime). NOTE: the RNG change means a given seed makes
## a DIFFERENT world than pre-v0.45.1 builds — the save format gates this.

## Prime a fresh world: the guaranteed spawn floor only (islands arrive lazily
## via ensure_generated). Kept within the old hand-placed floor's footprint so
## the startup/mining checks keep their known solid cells.
static func prime(terrain: Terrain) -> void:
	_spawn_floor(terrain, maxi(terrain.subdiv, 1))


## Generate every not-yet-generated lattice region whose island could reach
## within `radius_px` of any of `centers` (world px), up to `budget` regions per
## call (amortization — a region is a bounded one-island paint, ~2-10 ms).
## Returns how many regions were generated. Regions are remembered on the
## terrain (gen_regions), so this is cheap when everything nearby exists.
## After generating, RE-APPLIES the terrain's recorded edits — a loaded save's
## diffs (or a late-join client's) may predate the region, and the island paint
## must never clobber a player's recorded dig/place.
static func ensure_generated(terrain: Terrain, seed_value: int,
		centers: Array, radius_px: float, budget: int = 2) -> int:
	var sub := maxi(terrain.subdiv, 1)
	var world := world_cells(sub)
	var spacing := SPACING * sub
	var cp := terrain.cell_px()
	# An island can reach (JITTER + R_MAX) cells from its lattice point.
	var reach_cells := (JITTER + R_MAX) * sub
	var margin_px := float(reach_cells) * cp + radius_px
	var made := 0
	for c in centers:
		if made >= budget:
			break
		var centre_cell := terrain.world_to_cell(c)
		# Index box: lattice points within margin_px of the focus.
		var lo_i := floori((float(centre_cell.x) * cp - margin_px) / (spacing * cp))
		var hi_i := floori((float(centre_cell.x) * cp + margin_px) / (spacing * cp))
		var lo_j := floori((float(centre_cell.y) * cp - margin_px) / (spacing * cp))
		var hi_j := floori((float(centre_cell.y) * cp + margin_px) / (spacing * cp))
		for j in range(lo_j, hi_j + 1):
			for i in range(lo_i, hi_i + 1):
				if made >= budget:
					break
				var key := Vector2i(i, j)
				if terrain.gen_regions.has(key):
					continue
				# Outside the world rect there is nothing to make — mark it so
				# the rim never re-scans.
				var px := i * spacing
				var py := j * spacing
				if px < world.position.x or px >= world.end.x \
						or py < world.position.y or py >= world.end.y:
					terrain.gen_regions[key] = true
					continue
				terrain.gen_regions[key] = true
				if _generate_region(terrain, seed_value, i, j, world, sub, cp):
					made += 1
	if made > 0:
		terrain.reapply_all_edits()
	return made


## Fill `terrain` with the seeded, banded world EAGERLY — every lattice region
## covering `world` (defaults to the subdiv-scaled WORLD_CELLS) plus the spawn
## floor. The test/tool path (and small explicit windows); the live world uses
## prime + ensure_generated instead, because the full ×4 world is ~25 s of
## painting. Cell-identical to the lazy path: both call _generate_region per
## absolute lattice index.
static func generate(terrain: Terrain, seed_value: int = DEFAULT_SEED,
		world: Rect2i = Rect2i()) -> void:
	var sub := maxi(terrain.subdiv, 1)
	if world.size == Vector2i.ZERO:
		world = world_cells(sub)
	var spacing := SPACING * sub
	var cp := terrain.cell_px()
	_spawn_floor(terrain, sub)
	var lo_i := int(ceil(float(world.position.x) / spacing))
	var hi_i := int(floor(float(world.end.x - 1) / spacing))
	var lo_j := int(ceil(float(world.position.y) / spacing))
	var hi_j := int(floor(float(world.end.y - 1) / spacing))
	for j in range(lo_j, hi_j + 1):
		for i in range(lo_i, hi_i + 1):
			terrain.gen_regions[Vector2i(i, j)] = true
			_generate_region(terrain, seed_value, i, j, world, sub, cp)


## ONE lattice candidate: its own order-independent RNG, the same keep-outs and
## banded density as ever, painting CLIPPED to the world rect (owner 2026-08-24:
## "generated terrain appears out of bounds of the map" — an island centred near
## the rim used to spill past the boundary walls). Returns whether an island was
## actually placed. Sets/restores Airspace.bounds around the band query so it is
## correct whether or not the live world keeps bounds active.
## PERIODIC IN X WHEN THE WORLD LOOPS (2026-09-01). `RingSpace` says how many
## lattice regions one lap of the Dive's ring is; the RNG is then seeded from
## the REDUCED index, so candidate i and candidate i ± k are the same island —
## same jitter, same radius, same shape, same placement roll — a full
## circumference apart. That is what makes shifting everything by one
## circumference invisible: the ground you land on is byte-identical to the
## ground you left. The x-dependent keep-outs (the spawn clearing, the wind
## columns) are asked about the CANONICAL position for the same reason: a gate
## that answered differently for two images of one island would put ground on
## one side of the seam and sky on the other.
static func _generate_region(terrain: Terrain, seed_value: int, i: int, j: int,
		world: Rect2i, sub: int, cp: float) -> bool:
	var spacing := SPACING * sub
	var ri := i
	var k := RingSpace.lattice_regions(float(spacing) * cp)
	if k > 0:
		ri = RingSpace.reduce_index(i, k)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, ri, j])
	var jx := rng.randi_range(-JITTER * sub, JITTER * sub)
	var cx := i * spacing + jx
	var cy := j * spacing + rng.randi_range(-JITTER * sub, JITTER * sub)
	var place_roll := rng.randf()
	var radius := rng.randi_range(R_MIN * sub, R_MAX * sub)
	var shape_seed := rng.randi()
	# The x every PLACEMENT DECISION is taken at: the canonical image of this
	# candidate, so every image of it decides alike. Identical to `cx` when the
	# world does not loop.
	var gx := ri * spacing + jx

	# Spawn keep-out: leave the starting neighbourhood as clear sky.
	if maxi(absi(gx), absi(cy)) <= SPAWN_CLEAR * sub:
		return false
	var prev_bounds := Airspace.bounds
	Airspace.bounds = Rect2(Vector2(world.position) * cp, Vector2(world.size) * cp)
	var placed := false
	# NONE in the vertical wind columns — and never let a body spill in.
	if not _touches_wind_column(gx, radius, cp):
		var band := Airspace.band_at(Vector2(cx, cy) * cp)
		if place_roll <= _band_density(band):
			_place_island(terrain, Vector2i(cx, cy), radius, band, shape_seed, sub, world)
			placed = true
	Airspace.bounds = prev_bounds
	return placed


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
		band: int, shape_seed: int, sub: int = 1,
		clip: Rect2i = Rect2i(-(1 << 29), -(1 << 29), 1 << 30, 1 << 30)) -> void:
	var mats := TerrainDB.band_materials(band)
	var rx := radius
	var ry := maxi(3 * sub, int(round(radius * 0.7)))   # flatter than wide — an island
	var body: int = mats["body"]

	# BODY: every cell inside the ellipse. A little deterministic edge wobble
	# (from shape_seed) roughens the outline without ever breaking the interior.
	#
	# ROW SPANS, exact (the SUBDIV-8 fast path): the wobble is bounded ±0.10, so
	# a cell with n² ≤ 0.9 is inside for EVERY wobble value and one with n² > 1.1
	# is outside for every wobble value. Each row fills its guaranteed-interior
	# run in one fill_row (no per-cell chunk lookups — at subdiv 8 the body is
	# ~64× more cells and per-cell set_cell made world build a multi-second
	# stall) and walks ONLY the thin wobble band per cell. The produced cell set
	# is IDENTICAL to the per-cell rule.
	for dy in range(-ry, ry + 1):
		# CLIP to the world rect (owner: islands used to spill past the
		# boundary walls above/below/beside the map).
		if centre.y + dy < clip.position.y or centre.y + dy >= clip.end.y:
			continue
		var ny := float(dy) / float(ry)
		var ny2 := ny * ny
		if ny2 > 1.1:
			continue  # the whole row is guaranteed outside
		var dx_in := int(floor(float(rx) * sqrt(maxf(0.0, 0.9 - ny2))))
		var dx_out := mini(rx, int(floor(float(rx) * sqrt(maxf(0.0, 1.1 - ny2)))))
		if dx_in > 0:
			terrain.fill_row(maxi(centre.x - dx_in, clip.position.x),
				mini(centre.x + dx_in, clip.end.x - 1), centre.y + dy, body)
		# The wobble band: the exact per-cell test, both signs of dx (dx=0 only
		# when there is no interior run at all, so it is never written twice).
		for adx in range(dx_in + 1 if dx_in > 0 else 0, dx_out + 1):
			var signs: Array = [adx, -adx] if adx > 0 else [0]
			for sdx in signs:
				var dx := int(sdx)
				if centre.x + dx < clip.position.x or centre.x + dx >= clip.end.x:
					continue
				var nx := float(dx) / float(rx)
				var wobble := 0.10 * sin(float(shape_seed % 17) + float(dx) * 0.7 + float(dy) * 0.9)
				if nx * nx + ny2 <= 1.0 - wobble:
					terrain.set_cell(centre + Vector2i(dx, dy), body)

	# CAP: the top row(s) of each column get the surface material (topsoil look).
	# Per-column vertical runs through overwrite_col_where_solid — one chunk
	# lookup per run instead of an is_solid+set_cell pair per cell (the cap was
	# the second-largest cost of subdiv-8 generation). Same cells, same result:
	# only already-solid body cells are overwritten, so the wobbled edge is
	# respected exactly as before.
	var cap: int = mats["cap"]
	var cap_rows := (2 if radius >= 9 * sub else 1) * sub
	for dx in range(-rx, rx + 1):
		if centre.x + dx < clip.position.x or centre.x + dx >= clip.end.x:
			continue
		var nx := float(dx) / float(rx)
		if absf(nx) > 1.0:
			continue
		var top := int(floor(float(ry) * sqrt(maxf(0.0, 1.0 - nx * nx))))
		terrain.overwrite_col_where_solid(centre.x + dx,
			maxi(centre.y - top, clip.position.y),
			mini(centre.y - top + cap_rows - 1, clip.end.y - 1), cap)

	# POCKET: the ore/exotic core, buried below the island's midline so it is
	# genuinely enclosed by the body (a reason to dig in). Row spans, and no
	# per-cell is_solid: the pocket's whole disc lies within the body's
	# GUARANTEED interior (worst-case normalized extent (0.42)² + (0.30+0.42)²
	# ≈ 0.69 < 0.9, inside for every wobble), so the body cell always exists.
	var pocket: int = mats["pocket"]
	var pr := maxi(1, int(round(minf(rx, ry) * POCKET_FRAC)))
	var pcentre := centre + Vector2i(0, int(round(ry * 0.3)))
	for dy in range(-pr, pr + 1):
		if pcentre.y + dy < clip.position.y or pcentre.y + dy >= clip.end.y:
			continue
		var half := int(floor(sqrt(float(pr * pr - dy * dy))))
		terrain.fill_row(maxi(pcentre.x - half, clip.position.x),
			mini(pcentre.x + half, clip.end.x - 1), pcentre.y + dy, pocket)


## Guaranteed starting ground under SHIP_START (~origin). A strict SUBSET of the
## old hand-placed floor's footprint (same top row, narrower) so the existing
## pilot/startup/mining checks keep their known solid cells: (0,8) is dirt,
## (6,9) is solid, and the belly-drop lands on it. Dirt cap over a stone body,
## with a starter ore pocket to dig.
static func _spawn_floor(terrain: Terrain, sub: int = 1) -> void:
	terrain.fill_rect(Rect2i(-96 * sub, 8 * sub, 192 * sub, 12 * sub), TerrainDB.Type.STONE)
	terrain.fill_rect(Rect2i(-96 * sub, 8 * sub, 192 * sub, 2 * sub), TerrainDB.Type.DIRT)
	terrain.fill_rect(Rect2i(-6 * sub, 13 * sub, 12 * sub, 4 * sub), TerrainDB.Type.ORE)
