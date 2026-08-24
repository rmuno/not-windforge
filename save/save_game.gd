class_name SaveGame
extends RefCounted

## USER-FACING SAVE / LOAD (Sprint 5 persistence). A player saves a session and
## loads it back, restoring the world and their progress. Built ON the proven
## serialization: ships travel as `Ship.to_payload()` (the same dict the wire and
## severing already round-trip), terrain as SEED + DIFFS, the player as its clean
## Stats/Wallet/Inventory/health fields.
##
## FORMAT — human-inspectable JSON under `user://saves/<name>.json`, with a
## versioned header (`format`, an int). Chosen over a Godot-native binary
## encoding because this is a DATA game: a save you can open and read is a debug
## and modding affordance, and JSON needs no schema resource to evolve. The cost
## — JSON numbers parse back as floats — is paid once, in the decode helpers
## below (every int is int()'d on the way in). The version header GATES
## migration: an unrecognised `format` is refused gracefully (never crashes,
## never half-loads), and a future format bump adds a migration branch here
## rather than breaking old saves silently.
##
## TERRAIN — SEED + DIFFS, not the whole grid. The world is deterministic from
## `world_seed` (IslandGen), so a fresh save is a few dozen bytes: the seed plus
## the cells the player has dug or placed since generation (Terrain.edit_diffs).
## Load regenerates from the seed (IslandGen + the fixed Cairn) and re-applies the
## diffs. Storing the full ~1 MiB grid would be faithful too, but wasteful and
## against the resident-world sparse philosophy — the diffs ARE the player's mark
## on the world, and nothing else changed.
##
## SCOPE (seams, see BACKLOG): a couple of working slots + name/timestamp/
## playtime/location metadata. No autosave, no slot-management UI polish, no
## cloud, no networked/host-side save authority, no encryption. Save/load is
## single-player / authority only (a client shares the host's world).

## Format-version of the on-disk save. Bump when the shape changes and add a
## migration branch in `restore`; `_supported` refuses anything else.
const FORMAT_VERSION := 1

## Where saves live. FileAccess/DirAccess understand the `user://` scheme.
const SAVE_DIR := "user://saves"
const SAVE_EXT := ".json"


# --- File I/O -------------------------------------------------------------

## Ensure the saves directory exists. Cheap and idempotent.
static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func _path_for(name: String) -> String:
	return "%s/%s%s" % [SAVE_DIR, name, SAVE_EXT]


## Write a save dict to `<name>.json` (pretty-printed, human-inspectable).
## Returns false if the file could not be opened — never throws.
static func save_to(name: String, data: Dictionary) -> bool:
	_ensure_dir()
	var f := FileAccess.open(_path_for(name), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Read and parse `<name>.json`. Returns {} on ANY failure — missing file, an
## unreadable handle, or malformed JSON — so a corrupt or absent save is a clean
## "nothing here", never a crash. Version gating happens in `restore`/`list_saves`.
static func load_from(name: String) -> Dictionary:
	var path := _path_for(name)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}  # corrupt / truncated file — refuse gracefully
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data as Dictionary


## True if a parsed save's header is one this build can load. A missing or
## unrecognised `format` is unsupported — the gate that makes an older/newer or
## corrupt file refuse rather than load garbage.
static func _supported(data: Dictionary) -> bool:
	return int(data.get("format", -1)) == FORMAT_VERSION


func delete_save(_name: String) -> void:
	# Deleting saved data is a destructive action left to the player / OS on
	# purpose (see the assistant safety rules and BACKLOG scope). Not implemented.
	pass


## Metadata for every save on disk, newest first, WITHOUT a full restore — the
## list a load panel draws. Each row: {name, timestamp, timestamp_str, playtime,
## location, valid}. `valid` is false for a file this build cannot load (corrupt
## or an unsupported format), so the panel can grey it out instead of offering a
## load that would fail.
static func list_saves() -> Array:
	_ensure_dir()
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(SAVE_EXT):
			continue
		var name := file.substr(0, file.length() - SAVE_EXT.length())
		var data := load_from(name)
		out.append({
			"name": name,
			"timestamp": int(data.get("timestamp", 0)),
			"timestamp_str": String(data.get("timestamp_str", "")),
			"playtime": float(data.get("playtime", 0.0)),
			"location": String(data.get("location", "Unknown")),
			"valid": not data.is_empty() and _supported(data),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["timestamp"]) > int(b["timestamp"]))
	return out


# --- Top-level capture / restore (the manager the world calls) ------------

## Capture the whole session as a save dict. Reads the world's public state:
## the seed, the terrain diffs, every ship via `to_payload()`, the player's
## progress, and metadata. `name` and `playtime` are supplied by the caller
## (the world owns the playtime clock and lets the player name the save).
static func capture(world: Object, name: String, playtime: float) -> Dictionary:
	var ships: Array = []
	if world.fleet != null:
		for ship in world.fleet.ships():
			if is_instance_valid(ship):
				ships.append(encode_ship(ship))

	var now := Time.get_unix_time_from_system()
	return {
		"format": FORMAT_VERSION,
		"name": name,
		"timestamp": int(now),
		"timestamp_str": Time.get_datetime_string_from_unix_time(int(now), true),
		"playtime": playtime,
		"location": location_label(world),
		"world_seed": int(world.world_seed),
		"terrain_diffs": encode_terrain_diffs(world.terrain),
		"ships": ships,
		"player": encode_player(world.player),
	}


## Rebuild the world from a save dict. Returns false — changing nothing — if the
## header is missing or unsupported (the migration gate). On success the terrain,
## every ship and the player are restored, and the world's seed is updated.
## Re-crewing hostiles and re-binding local references are the WORLD's job after
## this returns (they touch NPCs/camera, not the save format) — see world.load_game.
static func restore(world: Object, data: Dictionary) -> bool:
	if not _supported(data):
		return false
	# (No older formats exist yet. When FORMAT_VERSION grows, migrate `data`
	#  up to the current shape here before touching the world.)

	world.world_seed = int(data.get("world_seed", world.world_seed))

	# Terrain: regenerate deterministically from the seed, then re-apply diffs.
	# Mirrors world._build_generated_terrain's construction order (generate then
	# plant the Cairn) so the loaded world is bit-identical to a fresh one before
	# the player's edits go back on top.
	if world.terrain != null:
		world.terrain.clear_all()
		IslandGen.generate(world.terrain, world.world_seed)
		EasterEggs.plant_cairn(world.terrain)
		apply_terrain_diffs(world.terrain, data.get("terrain_diffs", []))

	# Ships: throw away the current fleet, respawn each from its payload.
	if world.fleet != null:
		for ship in world.fleet.ships():
			world.fleet.remove_child(ship)
			ship.queue_free()
		for sd in data.get("ships", []):
			spawn_ship_from_encoded(world.fleet, sd)

	if world.player != null:
		apply_player(world.player, data.get("player", {}))

	return true


# --- Metadata -------------------------------------------------------------

## A user-facing place name for where the player is (saves are user-facing
## objects, BACKLOG). Derived from the player's altitude over the world region —
## the airspace bands the world is built around (High / Middle / Deep), so a save
## reads "The Deep Reaches" rather than a coordinate.
static func location_label(world: Object) -> String:
	if world.player == null or not is_instance_valid(world.player):
		return "Adrift"
	var wr := IslandGen.WORLD_CELLS
	var cp := TerrainDB.CELL * float(world.world_scale)
	var top := float(wr.position.y) * cp
	var height := float(wr.size.y) * cp
	if height <= 0.0:
		return "Adrift"
	var frac := clampf((world.player.global_position.y - top) / height, 0.0, 1.0)
	if frac < 0.34:
		return "The High Airs"
	if frac < 0.67:
		return "The Middle Sky"
	return "The Deep Reaches"


# --- Terrain (seed + diffs) -----------------------------------------------

## The runtime terrain edits as a flat JSON array [x, y, type, ...] — three ints
## per changed cell. Compact and order-stable enough for a save; the world is
## everything ELSE, regenerated from the seed.
static func encode_terrain_diffs(terrain: Object) -> Array:
	var out: Array = []
	if terrain == null:
		return out
	var diffs: Dictionary = terrain.edit_diffs()
	for cell in diffs:
		out.append(cell.x)
		out.append(cell.y)
		out.append(int(diffs[cell]))
	return out


## Re-apply flat [x, y, type, ...] diffs onto a freshly generated terrain. This
## is the load step that puts the player's dug/placed cells back; skipping it is
## the break-the-fix (dug cells would still read solid after load).
static func apply_terrain_diffs(terrain: Object, flat: Array) -> void:
	if terrain == null:
		return
	var diffs := {}
	var i := 0
	while i + 2 < flat.size():
		diffs[Vector2i(int(flat[i]), int(flat[i + 1]))] = int(flat[i + 2])
		i += 3
	terrain.apply_diffs(diffs)


# --- Ships (via to_payload) ------------------------------------------------

## One ship as a JSON-safe dict. The canonical `to_payload()` carries everything
## a peer (and now a save) needs — grid, transform, velocity, faction, the whale
## shared-health pool, the blueprint, and the structural WALL layer — and
## `body_tint` is added alongside so the cosmetic ghost-whale tint (an easter egg)
## survives a load too (it is NOT in the wire payload, so it rides here rather
## than a wire-format change).
static func encode_ship(ship: Object) -> Dictionary:
	var p: Dictionary = ship.to_payload()
	return {
		"grid": _ints(p["grid"]),
		"pos": _enc_v2(p["pos"]),
		"rot": float(p["rot"]),
		"linvel": _enc_v2(p["linvel"]),
		"angvel": float(p["angvel"]),
		"assist": bool(p["assist"]),
		"pilot": int(p["pilot"]),
		"unit": float(p["unit"]),
		"faction": int(p["faction"]),
		"shared": float(p["shared"]),
		"shared_max": float(p["shared_max"]),
		"tame_level": int(p["tame_level"]),
		"ride_speed_mult": float(p["ride_speed_mult"]),
		"creature_kind": String(p["creature_kind"]),
		"blueprint": _ints(p["blueprint"]),
		"walls": _ints(p["walls"]),
		"balloons": _ints(p["balloons"]),
		"tint": _enc_color(ship.body_tint),
	}


## Rebuild a ship from an encoded dict THROUGH the Fleet spawner — the same
## construction path as the wire and severing (one path, so a loaded ship is
## identical to a spawned one). Post-spawn work mirrors world._spawn_whale: set
## the cosmetic tint, and REBUILD any living creature so it gets the coarse
## collider (from_data sets the health pool AFTER the first rebuild, when the
## whale still looks like a vessel — without this second rebuild the sandwich
## solves at ~76 ms, the coarse-collider bug the ordering fix exists for).
static func spawn_ship_from_encoded(fleet: Object, sd: Dictionary) -> Object:
	var payload := {
		"grid": _dec_ints(sd.get("grid", [])),
		"pos": _dec_v2(sd.get("pos", [0.0, 0.0])),
		"rot": float(sd.get("rot", 0.0)),
		"linvel": _dec_v2(sd.get("linvel", [0.0, 0.0])),
		"angvel": float(sd.get("angvel", 0.0)),
		"assist": bool(sd.get("assist", true)),
		"pilot": int(sd.get("pilot", 1)),
		"unit": float(sd.get("unit", 1.0)),
		"faction": int(sd.get("faction", 0)),
		"shared": float(sd.get("shared", 0.0)),
		"shared_max": float(sd.get("shared_max", 0.0)),
		# Creature identity (taming tier + ride nimbleness). Absent in a legacy
		# save → from_data defaults to a plain vessel's values, unchanged.
		"tame_level": int(sd.get("tame_level", 1)),
		"ride_speed_mult": float(sd.get("ride_speed_mult", 1.0)),
		# Which creature brain (a kraken keeps its two-ended KrakenAI + untameable
		# status). Absent in a legacy save → "" → a plain whale-brained creature.
		"creature_kind": String(sd.get("creature_kind", "")),
		"blueprint": _dec_ints(sd.get("blueprint", [])),
		# Absent in a pre-walls (legacy) save → empty → from_data derives walls
		# from the footprint, exactly as it always did. A modern save carries the
		# exact wall layer so a damaged/severed ship reloads with identical severability.
		"walls": _dec_ints(sd.get("walls", [])),
		# Tethered balloons (carcass-as-airship) — absent in a legacy save → none.
		"balloons": _dec_ints(sd.get("balloons", [])),
	}
	var ship: Object = fleet.spawn_ship(payload)
	if ship == null:
		return null
	ship.body_tint = _dec_color(sd.get("tint", [1.0, 1.0, 1.0, 1.0]))
	# A creature (living OR carcass) had its pool set after the collider was
	# first built; rebuild so the collider matches its state (coarse while alive,
	# precise once dead). A plain vessel needs no second rebuild.
	if ship.shared_health_max > 0.0:
		ship.rebuild()
	return ship


# --- Player ---------------------------------------------------------------

## The player's progress as a JSON-safe dict: position, the four stat levels,
## money, the inventory, and current health. All clean fields on Player — no
## node state, so a fresh Player restores identically. Stat and item keys are
## stringified (JSON object keys must be strings) and int()'d back on load.
static func encode_player(player: Object) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var stats := {}
	for stat in StatDB.names():
		stats[str(stat)] = player.stats.level_of(stat)
	var inv := {}
	for type in player.inventory.types():
		inv[str(type)] = player.inventory.count(type)
	return {
		"pos": _enc_v2(player.global_position),
		"stats": stats,
		"money": player.wallet.balance,
		"inventory": inv,
		"health": player.health,
	}


## Restore the player's progress from an encoded dict. Steps off the helm first
## (loading while piloting would fight the restored transform), then sets
## position, stat levels, money, inventory and health. Health is clamped to the
## restored max so a lower-GRIT reload cannot exceed the new pool.
static func apply_player(player: Object, pd: Dictionary) -> void:
	if player == null or not is_instance_valid(player) or pd.is_empty():
		return
	if player.is_piloting():
		player.disembark()
	player.velocity = Vector2.ZERO
	player.global_position = _dec_v2(pd.get("pos", [0.0, 0.0]))
	player.net_position = player.global_position  # so a replica doesn't glide in

	for key in pd.get("stats", {}):
		player.stats.set_level(int(key), int(pd["stats"][key]))

	player.wallet.balance = int(pd.get("money", 0))

	player.inventory.clear()
	for key in pd.get("inventory", {}):
		player.inventory.add(int(key), int(pd["inventory"][key]))

	player.max_health = player.stats.max_health()
	player.health = minf(player.max_health, float(pd.get("health", player.max_health)))


# --- JSON-safe encode / decode helpers ------------------------------------

static func _enc_v2(v: Vector2) -> Array:
	return [v.x, v.y]


static func _dec_v2(a: Variant) -> Vector2:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 2:
		return Vector2.ZERO
	return Vector2(float(a[0]), float(a[1]))


static func _enc_color(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _dec_color(a: Variant) -> Color:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 4:
		return Color.WHITE
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## PackedInt32Array -> a plain Array of ints (JSON encodes it as numbers).
static func _ints(packed: PackedInt32Array) -> Array:
	var out: Array = []
	for n in packed:
		out.append(n)
	return out


## A JSON array of numbers -> PackedInt32Array (round to int — JSON parses
## numbers as floats, and the grid format is strictly integer).
static func _dec_ints(a: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if typeof(a) != TYPE_ARRAY:
		return out
	for n in (a as Array):
		out.append(int(round(float(n))))
	return out
