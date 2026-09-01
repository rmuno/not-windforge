class_name ShipEdit
extends RefCounted

## THE DRAFTING TABLE'S MODEL (owner arc Q-Q, 2026-09-01: "modify the starter
## via an in-game interface … it'd need an export feature so we can make it the
## default and not just game-state" + "the midair shipyard is ridiculous").
##
## A .ship blueprint being edited: a {Vector2i: BlockDB.Type} grid at AUTHORED 1×
## granularity — the one scale a default may be written at. The mid-air Shipyard
## edited the live 8× world and its export was an 8× file; pasted over
## `ships/starter.ship` that resurrects the retired native-8× bug ("impossible
## to move sideways", 94 px/s — see DECISIONS 2026-08-31). This model cannot
## make that mistake: it never sees the world, only the authored grid, and its
## text is `ShipLayout.serialize(cells)` — scale 1, no header, exactly what the
## repo's authored files are.
##
## Pure and node-free on purpose (the DiveRun/DiveCards idiom): the editor SCENE
## paints this and forwards clicks; every rule — painting, mirroring, undo, the
## stats arithmetic — is assertable headless. The stats mirror `Ship`'s own
## rebuild/physics at scale 1 (footprint norm is 1 there), so the FYI panel says
## what the game will actually do. FYI is the whole contract (owner: "it's fine
## to let a player design a super heavy ship that just sinks — why not") — the
## model VALIDATES NOTHING. It informs.

## The canvas. Cells live in [0, width) × [0, height); painting outside is
## refused (a fixed sheet of paper, like the Loft's grid). Sized to fit a loaded
## ship with margin — see `from_text`.
var width := 64
var height := 40
var cells := {}

## Undo: whole-grid snapshots, pushed once per STROKE (the scene calls
## `begin_stroke()` on mouse-down, then paints every dragged cell). Grids are a
## few hundred entries, so a deep stack is nothing.
var _undo: Array = []
const UNDO_CAP := 64

## Paint-both-sides (the Loft's mirror-X): a paint/erase at x also lands at
## width-1-x. A toggle, not a postprocess, so asymmetric touches stay possible.
var mirror_x := false


## The paintable palette, in display order: every type with a `.ship` glyph —
## what can be authored is exactly what can be saved. (The REPAIR station joins
## the format this round: the Dive bolts one on when a blueprint lacks it, and
## an authored one is strictly better information.)
static func palette() -> Array:
	return [
		BlockDB.Type.HULL, BlockDB.Type.GASBAG, BlockDB.Type.ENGINE,
		BlockDB.Type.PROPELLER, BlockDB.Type.HELM, BlockDB.Type.BALLAST,
		BlockDB.Type.TURRET, BlockDB.Type.DOOR_CLOSED, BlockDB.Type.REPAIR,
		BlockDB.Type.PLATFORM, BlockDB.Type.STRUT, BlockDB.Type.BLUBBER,
		BlockDB.Type.MEAT, BlockDB.Type.SHELL,
	]


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


## One stroke's opening bell: snapshot for undo. The scene calls this on
## mouse-down; every painted cell until mouse-up is one undo step.
func begin_stroke() -> void:
	_undo.append(cells.duplicate())
	while _undo.size() > UNDO_CAP:
		_undo.pop_front()


func undo() -> bool:
	if _undo.is_empty():
		return false
	cells = _undo.pop_back()
	return true


## Paint `type` at `c` (and its mirror twin when mirror_x). -1 erases. Returns
## whether anything changed, so the scene repaints only when needed.
func paint(c: Vector2i, type: int) -> bool:
	var changed := _put(c, type)
	if mirror_x:
		changed = _put(Vector2i(width - 1 - c.x, c.y), type) or changed
	return changed


func _put(c: Vector2i, type: int) -> bool:
	if not in_bounds(c):
		return false
	if type < 0:
		if not cells.has(c):
			return false
		cells.erase(c)
		return true
	if cells.get(c, -1) == type:
		return false
	cells[c] = type
	return true


func clear() -> void:
	begin_stroke()
	cells = {}


# --- .ship round-trip -------------------------------------------------------

## The authored text — scale 1, no header: byte-compatible with every file in
## `res://ships/`. This IS the export; there is no other serializer.
func to_text() -> String:
	return ShipLayout.serialize(cells)


## Load blueprint text onto the canvas: parsed, REBASED to non-negative cells
## (parse returns origin-relative coordinates), the canvas grown to fit with a
## margin of empty sheet to grow the design into. Returns false on empty/garbage.
##
## REFUSES an upscaled export (`scale N` header > 1) rather than editing it: an
## 8×-granularity grid saved as a default is the eightfold family — the round-trip
## for those is the Loft/paste-spawn path, not the drafting table.
func from_text(text: String) -> bool:
	if ShipLayout.file_scale(text) > 1:
		return false
	var parsed := ShipLayout.parse(text)
	if parsed.is_empty():
		return false
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in parsed:
		var v: Vector2i = c
		lo = Vector2i(mini(lo.x, v.x), mini(lo.y, v.y))
		hi = Vector2i(maxi(hi.x, v.x), maxi(hi.y, v.y))
	const MARGIN := 8
	var size := hi - lo + Vector2i.ONE
	width = maxi(48, size.x + MARGIN * 2)
	height = maxi(32, size.y + MARGIN * 2)
	# Centred on the sheet, so mirror-X folds around the design's own middle.
	var base := Vector2i((width - size.x) / 2, (height - size.y) / 2)
	cells = {}
	for c in parsed:
		cells[(c as Vector2i) - lo + base] = parsed[c]
	_undo = []
	return true


# --- The FYI stats (world-decides… except here the MODEL decides, because the
# whole point is telling the truth about a ship that does not exist yet) -------

## Propeller cells that will fly the VERTICAL axis, by the game's own mounting
## rule (Ship._derive_prop_axes, reproduced): contiguous prop clusters mounted
## only above/below a non-prop block are lift props; any side mount makes the
## cluster a pusher. Kept verbatim so the panel never lies about an axis. The
## canvas asks about the AUTHORED grid (the lift-prop markers); `stats` asks
## about the upscale — the rule is grid-agnostic, so it takes the grid.
func vertical_prop_cells() -> Dictionary:
	return _vertical_cells_of(cells)


static func _vertical_cells_of(grid: Dictionary) -> Dictionary:
	var vertical := {}
	var visited := {}
	for cell in grid:
		if visited.has(cell) or BlockDB.get_def(grid[cell])["thrust"] <= 0.0:
			continue
		var cluster: Array = []
		var queue: Array = [cell]
		visited[cell] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			cluster.append(c)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if not visited.has(n) and grid.has(n) \
						and BlockDB.get_def(grid[n])["thrust"] > 0.0:
					visited[n] = true
					queue.append(n)
		var side_mounted := false
		var hung := false
		for c in cluster:
			side_mounted = side_mounted or _grid_mount(grid, c + Vector2i.LEFT) \
				or _grid_mount(grid, c + Vector2i.RIGHT)
			hung = hung or _grid_mount(grid, c + Vector2i.UP) \
				or _grid_mount(grid, c + Vector2i.DOWN)
		if hung and not side_mounted:
			for c in cluster:
				vertical[c] = true
	return vertical


static func _grid_mount(grid: Dictionary, c: Vector2i) -> bool:
	return grid.has(c) and BlockDB.get_def(grid[c])["thrust"] <= 0.0


## The world scale the panel models. The sheet is authored 1× but the GAME FLIES
## THE 8× UPSCALE — and the two are not proportional: `upscale_cells` grows every
## authored cell into an 8×8 slab while footprint normalisation re-rates machine
## mass and output (BlockDB.FOOTPRINT_8X), so 1× arithmetic printed trim 2.02 for
## a ship that boots at 1.08. The FYI panel's one job is telling the truth about
## the ship the player will fly, so stats are computed ON THE UPSCALE.
const SHIPPED_SCALE := 8

## Everything the panel prints, as plain values — the SHIPPED (8×) ship's
## numbers, mirroring Ship's own rebuild + _physics_process at density 1.0 (the
## thick low sky; thin air scales lift and thrust down together, so the ratios
## hold at altitude):
##   trim        — lift capacity / weight. ≥1 floats (the game clamps at neutral,
##                 never lifts); <1 sinks and props must make up the deficit.
##   accel_h     — pusher force × power ratio / mass, px/s²: the sideways answer.
##   climb       — (lift prop force × ratio − unsupported weight) / mass: the
##                 UPWARD answer with the stick held. Negative = cannot climb.
##   power_ratio — supply / worst-case draw (both axes + turrets), capped at 1.
##                 Below 1 is the brownout: everything powered degrades together.
func stats() -> Dictionary:
	var su := float(SHIPPED_SCALE)
	var up := ShipLayout.upscale_cells(cells, SHIPPED_SCALE)
	var vertical := _vertical_cells_of(up)
	var mass := 0.0
	var lift := 0.0
	var power := 0.0
	var hthrust := 0.0   # forces, after footprint norm and the scale term —
	var vthrust := 0.0   # exactly what apply_central_force sees at density 1
	var draw := 0.0
	var com := Vector2.ZERO
	for cell in up:
		var type: int = up[cell]
		var def := BlockDB.get_def(type)
		# fp_norm, verbatim from Ship: su²/footprint — 1.0 for bulk blocks.
		var fp := su * su / BlockDB.footprint_cells(type, su)
		var m: float = def["mass"] * fp
		mass += m
		com += Vector2(cell) * m
		lift += def["lift"]
		power += def["power"] * fp
		draw += def["draw"] * fp
		if def["thrust"] > 0.0:
			if vertical.has(cell):
				vthrust += def["thrust"] * fp * su
			else:
				hthrust += def["thrust"] * fp * su
	if mass > 0.0:
		com /= mass
	var ratio := 1.0
	if draw > 0.0:
		ratio = clampf(power / draw, 0.0, 1.0)
	# Weight and lift both carry ×su (gravity_scale and the lift force's scale
	# term), so it cancels in trim — but NOT against thrust, which is why the
	# accel figures divide the su-carrying forces by the su-free mass ratio'd
	# against su-carrying weight. Mirrors _physics_process exactly.
	var weight := mass * 980.0 * su
	var lift_capacity := lift * BlockDB.LIFT_PER_MASS * su   # density 1
	var unsupported := maxf(0.0, weight - lift_capacity)
	# Authored per-type counts — the sheet's own census, friendlier than the
	# upscale's (nobody thinks of the starter as 4,672 blocks while drawing it).
	var counts := {}
	for cell in cells:
		var label: String = BlockDB.get_def(cells[cell])["name"]
		counts[label] = int(counts.get(label, 0)) + 1
	# How many authored props fly each axis — the panel names counts, not raw
	# force sums (327,680,000 newtons of push means nothing to a person; "4
	# pushers, ~5,200 px/s²" is the same fact in the player's own units).
	var authored_vertical := vertical_prop_cells()
	var pushers := 0
	var lifters := 0
	for cell in cells:
		if BlockDB.get_def(cells[cell])["thrust"] > 0.0:
			if authored_vertical.has(cell):
				lifters += 1
			else:
				pushers += 1
	return {
		"blocks": cells.size(),
		"shipped_blocks": up.size(),
		"pushers": pushers,
		"lifters": lifters,
		"mass": mass,
		"lift": lift,
		"trim": (lift_capacity / weight) if weight > 0.0 else 0.0,
		"hthrust": hthrust,
		"vthrust": vthrust,
		"power": power,
		"draw": draw,
		"power_ratio": ratio,
		"accel_h": (hthrust * ratio / mass) if mass > 0.0 else 0.0,
		"climb": ((vthrust * ratio - unsupported) / mass) if mass > 0.0 else 0.0,
		"com": com,
		"counts": counts,
		"has_helm": counts.has("Helm"),
	}


## The panel's text — one place, so the suite can pin what the owner reads.
## Pure information, zero judgement: a ship with trim 0.3 and no props prints
## its numbers like any other (owner: a super heavy ship that just sinks is a
## legal design — "it's just an FYI panel").
func stats_text() -> String:
	var s := stats()
	var lines: Array[String] = []
	lines.append("blocks   %d  (%d flown at 8x)" % [int(s["blocks"]), int(s["shipped_blocks"])])
	lines.append("mass     %.0f" % float(s["mass"]))
	lines.append("trim     %.2f  %s" % [float(s["trim"]),
		"(floats)" if float(s["trim"]) >= 1.0 else "(sinks — props must hold her)"])
	lines.append("")
	lines.append("pushers  %d  (~%.0f px/s² sideways)"
		% [int(s["pushers"]), float(s["accel_h"])])
	var climb := float(s["climb"])
	lines.append("lift props %d  (climb %s%.0f px/s²)"
		% [int(s["lifters"]), "+" if climb >= 0.0 else "", climb])
	var ratio := float(s["power_ratio"])
	lines.append("power    %.0f / draw %.0f  %s"
		% [float(s["power"]), float(s["draw"]),
			"(ok)" if ratio >= 1.0 else "(BROWNOUT at %d%%)" % int(round(ratio * 100.0))])
	if not bool(s["has_helm"]):
		lines.append("")
		lines.append("no helm — nobody can fly her")
	lines.append("")
	var counts: Dictionary = s["counts"]
	var names: Array = counts.keys()
	names.sort()
	for n in names:
		lines.append("  %-14s %d" % [n, int(counts[n])])
	return "\n".join(lines)
