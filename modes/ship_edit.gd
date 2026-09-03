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

## THE BLUEPRINT’S HEADERS (`ShipLayout.META_KEYS`): name, kind, health, tame,
## tint, role, bounty, notes — plus any key a later version of the game writes,
## which round-trips untouched. Empty for a fresh sheet, which is exactly what a
## headerless stock file parses to, so "the table did not add anything" and "the
## file said nothing" are the same state.
##
## This is what makes the table a CREATURE editor and not just a hull editor: a
## whale’s pool, taming tier and tint were code constants keyed off the file’s
## PATH until now, so a new body plan could be drawn but never finished.
var meta := {}

## WHICH FILE IS OPEN — static, because TRY IT changes scenes and the table has
## to come back to the same file when the player walks back through the WORKSHOP
## door. `carry_text` is the unsaved sheet that went out to be flown: without it,
## trying a design you have not saved yet would silently throw it away.
static var last_path := ""
static var carry_text := ""


## Paint-both-sides (the Loft’s mirror-X): a paint/erase at x also lands at
## width-1-x. A toggle, not a postprocess, so asymmetric touches stay possible.
var mirror_x := false


## The paintable palette, in display order: every type with a `.ship` glyph —
## what can be authored is exactly what can be saved. (The REPAIR station joins
## the format this round: the Dive bolts one on when a blueprint lacks it, and
## an authored one is strictly better information.)
##
## NO STRUT (owner 2026-09-01: "do we need the 'strut' part? i think it can be
## simplified to just not have it"): the strut stays a TYPE — the nests, the
## hulk and the launch deck are authored with it, its pass-through behaviour is
## test-pinned, and the block enum is append-only because it rides the wire/save
## format — but it leaves the player-facing surface. A loaded blueprint that
## carries one still edits and round-trips fine; nobody can paint a new one.
static func palette() -> Array:
	return [
		BlockDB.Type.HULL, BlockDB.Type.GASBAG, BlockDB.Type.ENGINE,
		BlockDB.Type.PROPELLER, BlockDB.Type.HELM, BlockDB.Type.BALLAST,
		BlockDB.Type.TURRET, BlockDB.Type.DOOR_CLOSED, BlockDB.Type.REPAIR,
		BlockDB.Type.PLATFORM, BlockDB.Type.BLUBBER,
		BlockDB.Type.MEAT, BlockDB.Type.SHELL,
	]


## THE CREATURE PALETTE: what the authored creature files actually use — W
## blubber, M meat, K shell, plus hull and platform for the hard parts (checked
## against every `ships/whale*.ship`, `kraken_*.ship`, `basilisk.ship`,
## `critter.ship`). Offering the vessel palette here was the old table’s way of
## saying "this is a boat with the wrong glyphs in it": an engine inside a whale
## is not a design, it is a mis-click.
static func creature_palette() -> Array:
	return [
		BlockDB.Type.BLUBBER, BlockDB.Type.MEAT, BlockDB.Type.SHELL,
		BlockDB.Type.HULL, BlockDB.Type.PLATFORM,
	]


## THE NEST PALETTE, likewise read off the four authored `nest_*.ship` files: a
## roost is a hull deck under gasbags with a turret and a door, a den is shell
## and meat, an eyrie and a hive hang off STRUTS. The strut left the VESSEL
## palette (owner 2026-09-01) and has to be here, because it is load-bearing in
## exactly these files and this is the screen the owner reviews them on.
static func nest_palette() -> Array:
	return [
		BlockDB.Type.HULL, BlockDB.Type.PLATFORM, BlockDB.Type.STRUT,
		BlockDB.Type.GASBAG, BlockDB.Type.TURRET, BlockDB.Type.DOOR_CLOSED,
		BlockDB.Type.SHELL, BlockDB.Type.MEAT, BlockDB.Type.BLUBBER,
	]


## WHICH PALETTE A `kind` HEADER ASKS FOR. Unknown text falls through to the
## vessel palette, which is the same fallback the spawn code makes (a `kind` it
## does not recognise is not a creature).
static func palette_for(kind: String) -> Array:
	match kind:
		"whale", "whale_city", "kraken", "basilisk", "critter":
			return creature_palette()
		"nest":
			return nest_palette()
	return palette()


## Is this `kind` a living body rather than a vessel or a structure? The one
## predicate the palette, the FYI panel and TRY IT all branch on.
static func is_creature_kind(kind: String) -> bool:
	return kind in ["whale", "whale_city", "kraken", "basilisk", "critter"]


## The open sheet’s kind, defaulting to `vessel` — a file with no `kind` header
## is a vessel, which is what every stock ship file is.
func kind() -> String:
	var k := String(meta.get("kind", "vessel"))
	return k if k != "" else "vessel"


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
	return ShipLayout.serialize(cells, 1, meta)


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
	# The headers come with the grid. Read BEFORE the early returns above would
	# matter and after them in the file, so a refused load never half-applies.
	meta = ShipLayout.parse_meta(text)
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
##
## KIND-AWARE since Q-T: a whale has no engines, no power budget and no helm, so
## printing "no helm — nobody can fly it" over a body plan was the panel lying in
## a new way. `stats_text` DISPATCHES; the vessel text below is unchanged.
func stats_text() -> String:
	if is_creature_kind(kind()) or kind() == "nest":
		return creature_stats_text()
	return vessel_stats_text()


func vessel_stats_text() -> String:
	var s := stats()
	var lines: Array[String] = []
	lines.append("blocks   %d  (%d flown at 8x)" % [int(s["blocks"]), int(s["shipped_blocks"])])
	lines.append("mass     %.0f" % float(s["mass"]))
	lines.append("trim     %.2f  %s" % [float(s["trim"]),
		"(floats)" if float(s["trim"]) >= 1.0 else "(sinks — props must hold it)"])
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
		lines.append("no helm — nobody can fly it")
	lines.append("")
	var counts: Dictionary = s["counts"]
	var names: Array = counts.keys()
	names.sort()
	for n in names:
		lines.append("  %-14s %d" % [n, int(counts[n])])
	return "\n".join(lines)


# --- Creature / nest FYI ------------------------------------------------------
#
# A body plan is not a boat, so the panel asks different questions of it. What a
# creature actually needs to be right (world.gd's `_spawn_one_*`): does it float
# on its own blubber, how big is its pool, and IS IT ONE PIECE — a disconnected
# body is a bug the game cannot spawn, because `Ship` severs on rebuild and the
# stray limb becomes a second body nobody's brain is driving.

## How many CONNECTED PIECES the grid is, 4-neighbour (the same adjacency
## `Ship` severs on). 1 is a whole creature; 0 is an empty sheet; more than 1
## means the thing would come apart the instant it spawned.
func piece_count() -> int:
	var seen := {}
	var pieces := 0
	for start in cells:
		if seen.has(start):
			continue
		pieces += 1
		var queue: Array = [start]
		seen[start] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
	return pieces


## The creature panel's plain values. Shares `stats()`'s arithmetic (the SHIPPED
## 8× upscale at density 1) so "floats" here means the same thing it means for a
## hull — buoyancy against weight, the one number that decides whether a body
## plan hangs in the sky or falls out of it.
func creature_stats() -> Dictionary:
	var s := stats()
	var out := s.duplicate()
	out["pieces"] = piece_count()
	out["health"] = float(meta.get("health", 0.0))
	out["floats"] = float(s["trim"]) >= 1.0
	return out


func creature_stats_text() -> String:
	var s := creature_stats()
	var lines: Array[String] = []
	lines.append("cells    %d  (%d spawned at 8x)"
		% [int(s["blocks"]), int(s["shipped_blocks"])])
	lines.append("mass     %.0f" % float(s["mass"]))
	# Buoyancy vs weight, the creature question. Named in both directions because
	# a sinking creature is legal (a kraken is held aloft by the wild-creature
	# hover exception) — FYI, never a gate.
	lines.append("buoyancy %.2f x weight  %s" % [float(s["trim"]),
		"(floats)" if bool(s["floats"]) else "(sinks — the sky must hold it)"])
	var hp := float(s["health"])
	lines.append("health   %s" % ("%.0f" % hp if hp > 0.0
		else "— (no header; the spawn code's own constant)"))
	var pieces := int(s["pieces"])
	if pieces == 1:
		lines.append("body     one connected piece")
	elif pieces == 0:
		lines.append("body     empty sheet")
	else:
		lines.append("body     %d SEPARATE PIECES — the game cannot spawn this"
			% pieces)
	lines.append("")
	var counts: Dictionary = s["counts"]
	var names: Array = counts.keys()
	names.sort()
	for n in names:
		lines.append("  %-14s %d" % [n, int(counts[n])])
	return "\n".join(lines)


# --- The file list, and saving ------------------------------------------------
#
# The table opens ANY .ship now (owner, Q-T: "this is just for players to design
# their own ships if they want, and for me to manually review/modify anything
# else we've created"). Two shelves: the repo's own `res://ships` — every stock
# hull, creature, nest and the launch deck, `drafts/` included — and the player's
# `ShipLayout.user_dir`, which is also where SAVE AS writes and where the Dive's
# launch deck looks for candidates.

const RES_SHIP_DIR := "res://ships"


## Every `.ship` under `dir_path`, recursively, sorted. An unopenable directory
## is an empty list, never an error: `user://ships` does not exist until the
## first save, and a fresh player must not meet a warning for that.
static func ship_files(dir_path: String) -> Array:
	var out: Array = []
	_scan_ships(dir_path, out)
	out.sort()
	return out


static func _scan_ships(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		# A leading underscore marks a SCRATCH file: `_try.ship` is what TRY IT
		# writes on its way out of this screen, and it is neither something to
		# open from the list nor a hull the Dive should moor. One convention,
		# both readers.
		if entry.begins_with(".") or entry.begins_with("_"):
			pass
		elif d.current_is_dir():
			_scan_ships(dir_path.path_join(entry), out)
		elif entry.to_lower().ends_with(".ship"):
			out.append(dir_path.path_join(entry))
		entry = d.get_next()
	d.list_dir_end()


## One row per openable file: `{path, name, kind, source, label}`. The name is
## the file's own `name` header when it has one and its basename when it does
## not, so the stock files (which have neither, by design — the owner adds
## headers on the table, not in a code round) still read as themselves.
static func file_rows() -> Array:
	var rows: Array = []
	for path in ship_files(RES_SHIP_DIR):
		rows.append(row_for(String(path), "res"))
	for path in ship_files(ShipLayout.user_dir):
		rows.append(row_for(String(path), "user"))
	return rows


static func row_for(path: String, source: String) -> Dictionary:
	var m := ShipLayout.load_meta(path)
	var nm := String(m.get("name", ""))
	if nm == "":
		nm = path.get_file().get_basename()
	var k := String(m.get("kind", "vessel"))
	if k == "":
		k = "vessel"
	return {"path": path, "name": nm, "kind": k, "source": source,
		"label": "%s  [%s]" % [nm, k]}


## A file name the OS will actually accept, out of whatever the player typed.
## Spaces become underscores; anything else outside `[A-Za-z0-9_-]` is dropped,
## because a `.ship` path ends up in warnings, test output and the launch deck's
## ordering, and none of those want a quote mark in them.
static func safe_basename(name: String) -> String:
	var out := ""
	for i in name.length():
		var ch := name[i]
		if ch == " ":
			out += "_"
		elif (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \
				or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out if out != "" else "untitled"


static func user_path_for(name: String) -> String:
	return ShipLayout.user_dir.path_join("%s.ship" % safe_basename(name))


## Write the sheet (grid + headers) to `path`, creating the directory if it is
## not there yet. Remembers it as the open file. False on an empty sheet or a
## directory that will not take a write (the web export's res://).
## `remember` is false for the scratch file TRY IT writes: the sheet that goes
## out to be flown must not become "the file that is open", or coming back from
## the world would rename the player’s design to `_try`.
func save_to(path: String, remember := true) -> bool:
	var text := to_text()
	if text.is_empty():
		return false
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if remember:
		last_path = path
	return true


## Where TRY IT parks the sheet on its way out to a world. Under `user_dir` so
## the suites’ redirect covers it too.
static func try_file() -> String:
	return ShipLayout.user_dir.path_join("_try.ship")


## Open `path` onto the sheet. False (and nothing changed) if it will not open or
## will not parse — a player's half-written file must never empty the table.
func load_path(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	if not from_text(text):
		return false
	last_path = path
	return true
