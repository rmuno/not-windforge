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
