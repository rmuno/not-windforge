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


## WHERE A `user://` BLUEPRINT LIVES. A `static var` so the SUITES can point it
## at a scratch directory — the same idiom `Profile.path` uses, and for the same
## reason: the drafting table's "save as" and the Dive's launch deck both read
## and write this directory, and a full test run must never touch the ships the
## owner actually saved. The game never reassigns it.
static var user_dir := "user://ships"


## THE HEADER VOCABULARY (owner arc Q-T, 2026-09-02: the drafting table opens
## and saves any `.ship`, creatures included). A creature is already a `.ship`
## file; what was NOT in the file is everything the spawn code set afterwards —
## its pool, its taming tier, its tint, which brain it gets. These `key value`
## lines carry that, so a body plan is a whole creature rather than a silhouette
## the code has to recognise by path.
##
## Order here IS the order `serialize` writes them in. Values are TYPED on the
## way in (health/tame/bounty/tint), so a spawn site reads
## `meta.get("health", <today's constant>)` and gets a number, not a string.
const META_KEYS := ["name", "kind", "health", "tame", "tint", "role", "bounty", "notes"]

## The kinds a `kind` header may name: `vessel` plus every `creature_kind` the
## world spawns, plus `nest` for a site's structure. Free text is not refused — a
## file naming something else round-trips and spawns as a vessel — but this is
## the list the drafting table offers and the spawn code branches on.
const META_KINDS := ["vessel", "whale", "whale_city", "kraken", "basilisk",
	"critter", "nest"]

## Header keys the FORMAT owns, and which `parse_meta` therefore never hands out:
## `origin` and `scale` are geometry, read by `parse`/`file_scale` and written by
## `serialize` itself. Putting them in the meta dictionary would mean two writers
## for one line.
const RESERVED_KEYS := ["origin", "scale"]


## IS THIS LINE A HEADER RATHER THAN A GRID ROW? The single classifier, shared by
## `parse` (which skips them) and `parse_meta` (which reads them) — they cannot
## disagree about what a header is, which is the whole point of it existing.
##
## THE SCAR THIS GUARDS: the comment rule used to be "anything starting with #",
## and '#' is also the HULL glyph — it ate the hulk's `#E#H#` row and the enemy
## spawned with no floor, no engine and no helm. The same trap is one careless
## `begins_with` away here, so the rule is narrow and structural instead:
##
##   a header is `key<space>value`, where key is `[a-z][a-z0-9_]*`.
##
## A GRID ROW NEVER CONTAINS A SPACE (empty is '.', which is why the parser keeps
## leading characters rather than stripping them), and every grid glyph but 'v'
## is uppercase or punctuation — so no row of blocks can be read as a header, and
## a header can never be read as a row. Verified against every stock file.
##
## Returns ["key", "value"], or empty for a grid row / comment / blank line.
static func meta_split(line: String) -> PackedStringArray:
	var sp := line.find(" ")
	if sp <= 0:
		return PackedStringArray()
	var key := line.substr(0, sp)
	for i in key.length():
		var ch := key[i]
		var lower := ch >= "a" and ch <= "z"
		var digit := ch >= "0" and ch <= "9"
		if not (lower or digit or ch == "_"):
			return PackedStringArray()
	if key[0] < "a" or key[0] > "z":
		return PackedStringArray()
	return PackedStringArray([key, line.substr(sp + 1).strip_edges()])


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
		# EVERY header line is skipped here, known key or not, through the one
		# classifier — so an unknown key the game does not understand still
		# cannot become a row of blocks. `scale` is read by `file_scale` and the
		# rest by `parse_meta`; `origin` is the one this function needs itself.
		var kv := meta_split(line)
		if not kv.is_empty():
			if kv[0] == "origin":
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


## THE HEADERS OF A `.ship`, typed. Known keys come back as the type the spawn
## code wants (`health` float, `tame`/`bounty` int, `tint` Color); everything
## else — including keys this build has never heard of — comes back as its raw
## text, so a file authored by a later version of the game round-trips through
## this one without losing anything.
##
## An empty Dictionary is the honest answer for a file with no headers, and that
## is what makes the override layer safe: every spawn site reads
## `meta.get(key, <today's constant>)`, so a headerless stock file spawns
## byte-identically to how it did before headers existed.
static func parse_meta(text: String) -> Dictionary:
	var meta := {}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges(false, true)
		if line == "#" or line.begins_with("# "):
			continue
		var kv := meta_split(line)
		if kv.is_empty() or RESERVED_KEYS.has(kv[0]):
			continue
		var key := kv[0]
		var value := kv[1]
		match key:
			"health":
				meta[key] = float(value)
			"tame", "bounty":
				meta[key] = int(value)
			"tint":
				var parts := value.split(" ", false)
				if parts.size() >= 3:
					meta[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
			_:
				meta[key] = value
	return meta


## The `tint` header as a Color, or `fallback` when the file did not name one.
## A typed reader because `meta.get("tint", c)` hands back a Variant, and every
## spawn site assigns it straight onto `Ship.body_tint`.
static func meta_tint(meta: Dictionary, fallback: Color) -> Color:
	var v: Variant = meta.get("tint")
	return v if typeof(v) == TYPE_COLOR else fallback


## `parse_meta` for a file on disk. Empty (not an error) when the file will not
## open — a spawn site that cannot read the headers still spawns the defaults.
static func load_meta(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	return parse_meta(file.get_as_text())


## One header line's text. Floats print as integers when they are integers
## (`health 1234`, not `health 1234.000`) because these files are hand-edited.
static func _meta_line(key: String, value: Variant) -> String:
	match typeof(value):
		TYPE_COLOR:
			var c: Color = value
			return "%s %.3f %.3f %.3f" % [key, c.r, c.g, c.b]
		TYPE_FLOAT:
			var f: float = value
			if is_equal_approx(f, roundf(f)):
				return "%s %d" % [key, int(roundf(f))]
			return "%s %s" % [key, String.num(f, 4)]
		TYPE_INT:
			return "%s %d" % [key, int(value)]
	return "%s %s" % [key, str(value)]


## The header block for `meta`, in canonical order: the known vocabulary first
## (META_KEYS order), then anything else alphabetically. Empty values are
## dropped — a blank `name ` line is noise, not information.
## A PackedStringArray and not an Array, so `serialize` can append the lines
## straight into its typed `Array[String]` without a per-line String() cast —
## which is not even legal on a value that is already a String (Godot 4: "Invalid
## call 'String' constructor").
static func meta_lines(meta: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if meta.is_empty():
		return out
	for key in META_KEYS:
		# `str`, never `String(...)`: the values here are Variants of several
		# types, and the String() CONSTRUCTOR refuses some of them at runtime
		# (Godot 4: "Invalid call 'String' constructor"). str() converts anything.
		if meta.has(key) and str(meta[key]) != "":
			out.append(_meta_line(key, meta[key]))
	var extra: Array = []
	for key in meta:
		var k := String(key)
		if META_KEYS.has(k) or RESERVED_KEYS.has(k):
			continue
		extra.append(k)
	extra.sort()
	for k in extra:
		out.append(_meta_line(k, meta[k]))
	return out


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
##
## `meta` is the HEADER VOCABULARY (see META_KEYS) — what a creature file needs
## beyond its silhouette. It is the THIRD parameter and not the second on
## purpose: `scale` predates it and has live callers (the world's own
## export_ship writes an 8× file), and reordering them to match a prettier
## signature would have been a silent argument swap in exactly the place the
## eightfold family lives.
static func serialize(cells: Dictionary, scale := 1, meta := {}) -> String:
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
	for line in meta_lines(meta):
		lines.append(str(line))
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
