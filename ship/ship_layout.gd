class_name ShipLayout
extends RefCounted

## Parses .ship blueprint files — ASCII grids where one character is one
## block. The starter lives at res://ships/starter.ship; the world and the
## test suites all load the same file, so a layout edit propagates everywhere
## (including breaking tests whose thresholds assumed the old shape — that is
## the point, not a bug).

const CHARS := {
	"#": BlockDB.Type.HULL,
	"G": BlockDB.Type.GASBAG,
	"E": BlockDB.Type.ENGINE,
	# One propeller block; its axis derives from mounting. All of these are
	# accepted so blueprints can *draw* the intended facing.
	"P": BlockDB.Type.PROPELLER,
	"V": BlockDB.Type.PROPELLER,
	"^": BlockDB.Type.PROPELLER,
	"v": BlockDB.Type.PROPELLER,
	"<": BlockDB.Type.PROPELLER,
	">": BlockDB.Type.PROPELLER,
	"H": BlockDB.Type.HELM,
	"B": BlockDB.Type.BALLAST,
	"T": BlockDB.Type.TURRET,
	# Doors spawn CLOSED (owner 2026-08-20): a parked ship is sealed. F
	# opens them in play; the open state is never authored.
	"D": BlockDB.Type.DOOR_CLOSED,
	# Whale blocks: buoyant blubber and dense meat (owner survey
	# 2026-08-20). Creatures are authored in the same .ship format as
	# vessels — ships/whale.ship is a body plan, not a boat.
	"W": BlockDB.Type.BLUBBER,
	"M": BlockDB.Type.MEAT,
	# Kraken shell: the armored material (lightweight, extremely hard — high
	# collision_resist). Authors the armored nose/tip of a kraken body plan.
	"K": BlockDB.Type.SHELL,
	"-": BlockDB.Type.PLATFORM,
	"|": BlockDB.Type.STRUT,
	# Repair station (joined the format 2026-09-01, with the drafting table):
	# the Dive bolts one on when a blueprint lacks it, so an AUTHORED one is
	# strictly better information — and a glyphless type could not round-trip
	# through the editor at all.
	"R": BlockDB.Type.REPAIR,
}


## Returns {Vector2i cell: BlockDB.Type}, or an empty Dictionary on error.
static func parse(text: String) -> Dictionary:
	var origin := Vector2i.ZERO
	var rows: Array[String] = []

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges(false, true)  # keep leading dots aligned
		# A comment is "# " (hash-space) or a bare "#". It must NOT be
		# "anything starting with #": '#' is also the HULL character, and
		# that rule silently ate the hulk's `#E#H#` hull row — the enemy
		# spawned as a blimp with no floor, no engine and no helm, and the
		# rows below collapsed upward (owner report, session 3). A grid row
		# never contains a space (empty is '.'), so hash-space is unambiguous.
		if line == "#" or line.begins_with("# "):
			continue
		if line.begins_with("scale"):
			# Grid granularity metadata (see file_scale) — not a grid row.
			continue
		if line.begins_with("origin"):
			var parts := line.split(" ", false)
			if parts.size() >= 3:
				origin = Vector2i(int(parts[1]), int(parts[2]))
			continue
		if line.strip_edges() == "":
			continue
		rows.append(line)

	var cells := {}
	for r in rows.size():
		for c in rows[r].length():
			var ch := rows[r][c]
			if CHARS.has(ch):
				cells[Vector2i(c - origin.x, r - origin.y)] = CHARS[ch]
	return cells


## One canonical glyph per authored type — the reverse of CHARS, for
## `serialize`. Propellers write "P" (the axis derives from mounting, so the
## directional variants are drawing sugar); an OPEN door serializes as the
## authored CLOSED one (the open state is never authored).
const GLYPHS := {
	BlockDB.Type.HULL: "#",
	BlockDB.Type.GASBAG: "G",
	BlockDB.Type.ENGINE: "E",
	BlockDB.Type.PROPELLER: "P",
	BlockDB.Type.HELM: "H",
	BlockDB.Type.BALLAST: "B",
	BlockDB.Type.TURRET: "T",
	BlockDB.Type.DOOR_CLOSED: "D",
	BlockDB.Type.DOOR: "D",
	BlockDB.Type.BLUBBER: "W",
	BlockDB.Type.MEAT: "M",
	BlockDB.Type.SHELL: "K",
	BlockDB.Type.PLATFORM: "-",
	BlockDB.Type.STRUT: "|",
	BlockDB.Type.REPAIR: "R",
}


## Shift a grid so its bounding-box CENTRE sits at cell (0,0) — the canonical
## authored form. Every hand-authored file centres its grid on the origin
## (`origin 6 5` and friends), and the WORLD assumes it: ground is prepared,
## berths sized and spacing measured around the SHIP NODE, which sits at the
## grid's (0,0). The drafting table's canvas keeps cells at (0..width) instead,
## and the owner's third export proved what that does uncentred: the hull spawned
## ~2,800 px from its own node, half off the prepared floor, and fell away from
## the freshly-berthed pilot. Integer shift; empty grids pass through.
static func recentre(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return cells
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in cells:
		var c: Vector2i = cell
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var shift := Vector2i((lo.x + hi.x) / 2, (lo.y + hi.y) / 2)
	if shift == Vector2i.ZERO:
		return cells
	var out := {}
	for cell in cells:
		out[(cell as Vector2i) - shift] = cells[cell]
	return out


## How far off-centre (in grid cells, either axis) a parsed blueprint may sit
## before the LOADER recentres it. Already-saved uncentred exports (the owner's
## drafts predate the centred serializer below) must load right TODAY; but the
## stock authored files sit within a cell of centre by convention and are left
## byte-identical — the 1x pilot fixture's walk contract is written in exact
## ship-relative coordinates.
const RECENTRE_THRESHOLD := 4


## Recentre a parsed grid only when it is WILDLY off-origin (past the threshold
## on either axis) — the load-time safety net under `recentre`'s export-time fix.
static func recentre_if_askew(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return cells
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in cells:
		var c: Vector2i = cell
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var centre := Vector2i((lo.x + hi.x) / 2, (lo.y + hi.y) / 2)
	if absi(centre.x) <= RECENTRE_THRESHOLD and absi(centre.y) <= RECENTRE_THRESHOLD:
		return cells
	return recentre(cells)


## The missing half of the round-trip (the Loft always had it; the game did
## not): {Vector2i: type} -> the .ship ASCII `parse` reads back. CANONICAL, not
## verbatim: the grid is RECENTRED first (see `recentre` — an export must be a
## well-formed authored file, and authored files centre on the origin), so
## `parse(serialize(x)) == recentre(x)`. `scale` records the grid's granularity
## (a ship exported from the 8x world is an 8x-granularity grid); 1 writes no
## line, matching every authored file. A type with no glyph serializes as empty —
## honest loss, printed nowhere better.
static func serialize(cells: Dictionary, scale := 1) -> String:
	if cells.is_empty():
		return ""
	var centred := recentre(cells)
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in centred:
		var c: Vector2i = cell
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var lines: Array[String] = []
	lines.append("# exported from the game (workshop shipyard)")
	if scale > 1:
		lines.append("scale %d" % scale)
	lines.append("origin %d %d" % [-lo.x, -lo.y])
	lines.append("")
	for r in range(lo.y, hi.y + 1):
		var row := ""
		for c in range(lo.x, hi.x + 1):
			var cell := Vector2i(c, r)
			row += String(GLYPHS.get(centred.get(cell, -1), "."))
		lines.append(row)
	return "\n".join(lines) + "\n"


## The `scale N` header of an exported file (1 when absent — every hand-authored
## file). Spawn paths use it so an 8x-granularity export is never upscaled x8
## again (the eightfold-bug family).
static func file_scale(text: String) -> int:
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("scale"):
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				return maxi(1, int(parts[1]))
	return 1


static func load_cells(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ShipLayout: cannot open %s" % path)
		return {}
	return parse(file.get_as_text())


## World-scale experiment: blow a blueprint up by an integer factor — every
## cell becomes an s×s block of the same type, so proportions, rooms and
## component placement survive while granularity multiplies. One exception
## keeps gameplay semantics instead of geometry: PLATFORM stays one row
## (the top of its old cell) — a hatch is a surface you drop through per
## storey, not an s-deep stack of planks. Doors replicate naively on
## purpose: door cells ARE the wall, so the s-deep opening is simply the
## upscaled wall's thickness, matching the original's 1-thick × 8-tall
## doors (WORLD_SPEC.md) at any wall depth.
static func upscale_cells(cells: Dictionary, s: int) -> Dictionary:
	if s <= 1:
		return cells
	var out := {}
	for cell in cells:
		var type: int = cells[cell]
		var base: Vector2i = cell * s
		for dy in s:
			for dx in s:
				if type == BlockDB.Type.PLATFORM and dy != 0:
					continue
				out[base + Vector2i(dx, dy)] = type
	return out
