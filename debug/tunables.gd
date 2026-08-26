class_name Tunables
extends RefCounted

## Live-editable gameplay LEVERS (owner tool, session 5). The debug window
## (maps/world/debug_window.gd, F2) edits these while the game runs; the systems
## READ them instead of their hardcoded consts, so the owner can tune whale
## health, ram strength, hazard rates, mining power and the rest without editing
## source and rebooting (we hand-edited these constants all sprint — this hands
## over the dials).
##
## WHY A STATIC STORE, not an autoload: GDScript `const` cannot be mutated at
## runtime, so the levers need a mutable home. A static class needs no autoload
## registration, which means it works under the headless `--script` test harness
## (autoloads don't exist there — godot-quirks) exactly as it does in play. Every
## read site is `Tunables.get_num("id")`; there is no instance to pass around.
##
## PARITY: each lever's `default` mirrors the origin constant it replaced (named
## in the comment on its row), so behaviour is byte-identical until a value is
## touched. The whale / hazard / ram / pilot / startup suites all exercise the
## DEFAULTS, so a mistyped default fails a parity test loudly rather than shipping
## a silent balance change.
##
## EXTENSIBLE: adding a lever is TWO lines — one registry row in `_REGISTRY`
## below, and one `Tunables.get_num("id")` at the site that used the const. The
## window builds its rows from the registry automatically, so a new lever appears
## in its group's tab with no UI work.
##
## SCOPE (seams, see docs/BACKLOG.md): overrides are NOT persisted to save files,
## NOT replicated over the network (the window is host/single-player dev-facing),
## and this is a curated registry, not a reflection auto-UI over every const.

## kind tags: what control the window draws and how a value is coerced.
const KIND_FLOAT := "float"
const KIND_INT := "int"
const KIND_BOOL := "bool"

## The lever table. Ordered — the window renders groups and rows in this order.
## Each row: id, label, group (== tab), kind, default, min, max, step, and an
## optional `note` ("next spawn") for levers a rebuild/respawn applies (per-cell
## hp, pod count). `min`/`max`/`step` are ignored for bools.
const _REGISTRY := [
	# --- Whale (owner-named first: health, pod count, ram, impact) -----------
	{"id": "whale_health", "label": "Whale health", "group": "Whale",
		"kind": KIND_FLOAT, "default": 15000.0, "min": 100.0, "max": 60000.0, "step": 100.0,
		"note": "next spawn"},                                    # world.WHALE_HEALTH
	{"id": "whale_pod_size", "label": "Pod count", "group": "Whale",
		"kind": KIND_INT, "default": 3, "min": 1, "max": 8, "step": 1,
		"note": "next spawn"},                                    # world.WHALE_POD_SIZE
	{"id": "whale_push_accel", "label": "Ram strength (push accel)", "group": "Whale",
		"kind": KIND_FLOAT, "default": 1100.0, "min": 0.0, "max": 4000.0, "step": 25.0},  # WhaleAI.PUSH_ACCEL
	{"id": "whale_ride_accel", "label": "Ride throttle", "group": "Whale",
		"kind": KIND_FLOAT, "default": 620.0, "min": 0.0, "max": 2000.0, "step": 20.0},   # WhaleAI.RIDE_ACCEL
	{"id": "whale_align_accel", "label": "Align accel", "group": "Whale",
		"kind": KIND_FLOAT, "default": 360.0, "min": 0.0, "max": 1500.0, "step": 20.0},   # WhaleAI.ALIGN_ACCEL
	{"id": "whale_anger_seconds", "label": "Anger duration (s)", "group": "Whale",
		"kind": KIND_FLOAT, "default": 30.0, "min": 0.0, "max": 120.0, "step": 1.0},      # WhaleAI.ANGER_SECONDS
	{"id": "creature_impact_factor", "label": "Creature ram-damage factor", "group": "Whale",
		"kind": KIND_FLOAT, "default": 0.05, "min": 0.0, "max": 1.0, "step": 0.01},       # Ship.CREATURE_IMPACT_FACTOR
	{"id": "creature_terrain_impact_factor", "label": "Creature terrain-crash factor", "group": "Whale",
		"kind": KIND_FLOAT, "default": 0.02, "min": 0.0, "max": 1.0, "step": 0.01},       # Ship.CREATURE_TERRAIN_IMPACT_FACTOR
	{"id": "whale_mine_interval", "label": "Ridden-mine pulse interval (s)", "group": "Whale",
		"kind": KIND_FLOAT, "default": 0.15, "min": 0.02, "max": 2.0, "step": 0.01},      # world ride-mining RATE
	{"id": "whale_mine_reach", "label": "Ridden-mine depth (cells)", "group": "Whale",
		"kind": KIND_INT, "default": 1, "min": 1, "max": 8, "step": 1},                   # world ride-mining REACH (1 = dig at the contact face, not ahead — owner 2026-08-23)
	{"id": "whale_mine_breadth", "label": "Ridden-mine breadth (+cells/side)", "group": "Whale",
		"kind": KIND_INT, "default": 1, "min": 0, "max": 8, "step": 1},                   # world ride-mining BREADTH

	# --- Combat --------------------------------------------------------------
	{"id": "sidearm_damage", "label": "Sidearm damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 4.0, "min": 0.0, "max": 200.0, "step": 1.0},       # world._handle_shooting literal
	{"id": "turret_damage", "label": "Turret damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 20.0, "min": 0.0, "max": 500.0, "step": 1.0},      # world._fire_turrets* literal
	{"id": "fire_rate_mult", "label": "Fire-rate x (all weapons)", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.25, "max": 5.0, "step": 0.05},       # world sidearm+turret cadence
	{"id": "shot_max_range", "label": "Shot max range (unscaled px)", "group": "Combat",
		"kind": KIND_FLOAT, "default": 11000.0, "min": 1000.0, "max": 40000.0, "step": 500.0},  # world.SHOT_MAX_RANGE
	{"id": "enemy_aggro_range", "label": "Enemy aggro range", "group": "Combat",
		"kind": KIND_FLOAT, "default": 700.0, "min": 0.0, "max": 4000.0, "step": 50.0},   # world.enemy_aggro_range
	{"id": "enemy_deaggro_range", "label": "Enemy de-aggro range", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1100.0, "min": 0.0, "max": 6000.0, "step": 50.0},  # world.enemy_deaggro_range
	{"id": "enemy_shot_speed_mult", "label": "Enemy shot speed x", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.5, "min": 0.1, "max": 3.0, "step": 0.05},        # world.enemy_shot_speed_mult
	{"id": "enemy_fire_cooldown", "label": "Enemy fire cooldown (s)", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1.2, "min": 0.1, "max": 5.0, "step": 0.1},         # world.ENEMY_FIRE_COOLDOWN
	{"id": "flee_hull_fraction", "label": "Bandit flee hull fraction", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.45, "min": 0.0, "max": 1.0, "step": 0.05},       # ShipAI.FLEE_HULL_FRACTION
	{"id": "kraken_wildness", "label": "Kraken wildness (wander accel)", "group": "Combat",
		"kind": KIND_FLOAT, "default": 150.0, "min": 0.0, "max": 600.0, "step": 10.0},  # KrakenAI tamed/wild jitter — "a little wild in their movement" (owner)
	{"id": "kraken_grab_dps", "label": "Kraken mouth-grab DPS", "group": "Combat",
		"kind": KIND_FLOAT, "default": 120.0, "min": 0.0, "max": 1000.0, "step": 5.0},    # KrakenAI.GRAB_DPS
	{"id": "kraken_grab_reach", "label": "Kraken mouth-grab reach (unscaled px)", "group": "Combat",
		"kind": KIND_FLOAT, "default": 70.0, "min": 0.0, "max": 600.0, "step": 5.0},      # KrakenAI.GRAB_REACH
	{"id": "impact_damage_threshold", "label": "Impact damage threshold", "group": "Combat",
		"kind": KIND_FLOAT, "default": 20000.0, "min": 0.0, "max": 100000.0, "step": 1000.0},  # Ship.IMPACT_DAMAGE_THRESHOLD
	{"id": "impact_damage_scale", "label": "Impact damage scale", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.01, "min": 0.0, "max": 0.2, "step": 0.005},      # Ship.IMPACT_DAMAGE_SCALE
	{"id": "gasbag_collision_resist", "label": "Gasbag collision resist", "group": "Combat",
		"kind": KIND_FLOAT, "default": 10.0, "min": 1.0, "max": 50.0, "step": 1.0},       # BlockDB gasbag collision_resist
	{"id": "ship_restitution", "label": "Collision bounciness (0=putty, 1=pool ball)", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.35, "min": 0.0, "max": 1.0, "step": 0.05,
		"note": "next spawn"},                                    # Ship physics_material_override.bounce

	# --- World (hazards, mining, repair) -------------------------------------
	{"id": "terrain_subdiv", "label": "Terrain resolution (x finer; R regenerates)", "group": "World",
		"kind": KIND_INT, "default": 4, "min": 1, "max": 8, "step": 1,
		"note": "on world reset"},  # Terrain.subdiv — 4 (32px tiles, ~1/4 the cells of full-8x) per owner 2026-08-24: "WAY too many blocks... 1/4 or 1/8 the count, blocks bigger each". 8 = the too-fine full-8x; 1 = legacy coarse. Read at world BUILD only.
	# --- Dormancy (owner 2026-08-25: let more things exist while far away) ---
	{"id": "dormancy_enabled", "label": "Distance dormancy (far bodies leave physics)",
		"group": "World", "kind": KIND_BOOL, "default": true},   # world._update_dormancy
	{"id": "dormant_range_px", "label": "Dormancy range (px; wakes at 80%)",
		"group": "World", "kind": KIND_FLOAT, "default": 12000.0,
		"min": 2000.0, "max": 60000.0, "step": 500.0},           # world._update_dormancy
	{"id": "dormant_tick_seconds", "label": "Dormant tick (s)", "group": "World",
		"kind": KIND_FLOAT, "default": 3.0, "min": 0.5, "max": 30.0, "step": 0.5},
	# --- Spawn sites (charter §4: population lives in the world) -------------
	{"id": "spawn_sites_enabled", "label": "World spawn sites (danger has a place)",
		"group": "World", "kind": KIND_BOOL, "default": true},   # world._update_spawn_sites
	{"id": "site_activate_px", "label": "Site activation range (px)",
		"group": "World", "kind": KIND_FLOAT, "default": 9000.0, "min": 1000.0,
		"max": 40000.0, "step": 500.0},   # inside dormancy's wake range on purpose
	{"id": "site_max_residents", "label": "Site residents alive at once (cap)",
		"group": "World", "kind": KIND_INT, "default": 12, "min": 0, "max": 60,
		"step": 1},   # world._resident_count — the safety net under the pools
	{"id": "site_release_seconds", "label": "Site releases one resident every (s)",
		"group": "World", "kind": KIND_FLOAT, "default": 12.0, "min": 0.0,
		"max": 120.0, "step": 1.0},   # world._tick_site — a site fills up, never dumps
	{"id": "site_regen_seconds", "label": "Site regrows one resident (s)",
		"group": "World", "kind": KIND_FLOAT, "default": 240.0, "min": 5.0,
		"max": 1800.0, "step": 5.0},
	{"id": "site_reclaim_px", "label": "Reclaim a far resident (px)",
		"group": "World", "kind": KIND_FLOAT, "default": 45000.0, "min": 15000.0,
		"max": 200000.0, "step": 5000.0},
	{"id": "dormant_drift_mult", "label": "Far migration speed (0 = hold still)",
		"group": "World", "kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 5.0,
		"step": 0.1},   # world._migrate_dormant × Dormancy.MIGRATE_SPEED
	{"id": "dormant_heal_per_min", "label": "Far creature mending (pool frac/min)",
		"group": "World", "kind": KIND_FLOAT, "default": 0.05, "min": 0.0, "max": 1.0,
		"step": 0.01},  # world._migrate_dormant — a wounded creature mends out of sight
	{"id": "mine_power", "label": "Mining power (hp/s)", "group": "World",
		"kind": KIND_FLOAT, "default": 240.0, "min": 10.0, "max": 2000.0, "step": 10.0},  # world.MINE_POWER
	{"id": "mine_reach_cells", "label": "Mining reach (cells)", "group": "World",
		"kind": KIND_FLOAT, "default": 4.5, "min": 1.0, "max": 20.0, "step": 0.5},        # world.MINE_REACH_CELLS
	{"id": "repair_rate", "label": "Repair rate (hp/s)", "group": "World",
		"kind": KIND_FLOAT, "default": 45.0, "min": 1.0, "max": 500.0, "step": 5.0},      # world.REPAIR_RATE
	{"id": "meteor_interval", "label": "Meteor interval (s)", "group": "World",
		"kind": KIND_FLOAT, "default": 3.5, "min": 0.2, "max": 30.0, "step": 0.1},        # Hazards.METEOR_INTERVAL
	{"id": "meteor_damage", "label": "Meteor damage", "group": "World",
		"kind": KIND_FLOAT, "default": 60.0, "min": 0.0, "max": 500.0, "step": 5.0},      # Hazards.METEOR_DAMAGE
	{"id": "meteor_speed", "label": "Meteor speed", "group": "World",
		"kind": KIND_FLOAT, "default": 95.0, "min": 10.0, "max": 600.0, "step": 5.0},     # Hazards.METEOR_SPEED
	{"id": "lava_interval", "label": "Lava interval (s)", "group": "World",
		"kind": KIND_FLOAT, "default": 2.2, "min": 0.2, "max": 30.0, "step": 0.1},        # Hazards.LAVA_INTERVAL
	{"id": "lava_damage", "label": "Lava damage", "group": "World",
		"kind": KIND_FLOAT, "default": 80.0, "min": 0.0, "max": 500.0, "step": 5.0},      # Hazards.LAVA_DAMAGE
	{"id": "lava_speed", "label": "Lava launch speed", "group": "World",
		"kind": KIND_FLOAT, "default": 560.0, "min": 50.0, "max": 1500.0, "step": 10.0},  # Hazards.LAVA_SPEED
	{"id": "suffocate_interval", "label": "Suffocation interval (s)", "group": "World",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.1, "max": 10.0, "step": 0.1},        # LifeSupport.tick cadence
	{"id": "suffocate_damage", "label": "Suffocation damage", "group": "World",
		"kind": KIND_FLOAT, "default": 10.0, "min": 0.0, "max": 200.0, "step": 1.0},      # LifeSupport.tick per-tick
]

## Lazily-built state. Static vars persist for the process lifetime, which is
## exactly the scope we want (a running game / one test process).
static var _seeded := false
static var _by_id := {}      ## id -> the registry row (Dictionary)
static var _values := {}     ## id -> current value (float/int/bool)
static var _groups := []     ## group names, in first-appearance order


## Build the lookup maps once, on first access. Idempotent.
static func _ensure() -> void:
	if _seeded:
		return
	for row in _REGISTRY:
		var id: String = row["id"]
		_by_id[id] = row
		_values[id] = row["default"]
		var g: String = row["group"]
		if not _groups.has(g):
			_groups.append(g)
	_seeded = true


## The ordered registry rows (for the window to render). Read-only — callers must
## not mutate the rows.
static func defs() -> Array:
	_ensure()
	return _REGISTRY


## The group names in registry order (one tab per group).
static func groups() -> Array:
	_ensure()
	return _groups.duplicate()


## The registry rows in `group`, in order.
static func in_group(group: String) -> Array:
	_ensure()
	var out: Array = []
	for row in _REGISTRY:
		if row["group"] == group:
			out.append(row)
	return out


## Does a lever with this id exist?
static func has(id: String) -> bool:
	_ensure()
	return _by_id.has(id)


static func def(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


## The current value as a float. The universal read for float levers; int/bool
## levers coerce cleanly too (a bool reads 0.0/1.0).
static func get_num(id: String) -> float:
	_ensure()
	var v: Variant = _values.get(id, 0.0)
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


static func get_int(id: String) -> int:
	return roundi(get_num(id))


static func get_bool(id: String) -> bool:
	_ensure()
	return bool(_values.get(id, false))


## Set a lever, CLAMPED to its [min, max] and coerced to its kind (int levers
## round, bool levers coerce to true/false). No-op for an unknown id. Returns the
## value actually stored (post-clamp) so callers/UI can reflect it.
static func set_value(id: String, value: Variant) -> Variant:
	_ensure()
	if not _by_id.has(id):
		return null
	var row: Dictionary = _by_id[id]
	match row["kind"]:
		KIND_BOOL:
			_values[id] = bool(value)
		KIND_INT:
			var iv := clampi(roundi(float(value)), int(row["min"]), int(row["max"]))
			_values[id] = iv
		_:
			var fv := clampf(float(value), float(row["min"]), float(row["max"]))
			_values[id] = fv
	return _values[id]


## Restore one lever to its default.
static func reset(id: String) -> void:
	_ensure()
	if _by_id.has(id):
		_values[id] = _by_id[id]["default"]


## Restore EVERY lever to its default. Tests that mutate a lever call this so a
## change never leaks into a later test in the same process.
static func reset_all() -> void:
	_ensure()
	for id in _by_id:
		_values[id] = _by_id[id]["default"]
