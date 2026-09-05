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
##
## LABEL and TIP (owner 2026-09-05: "TOO MUCH INFORMATION EVERYWHERE… use a
## tooltip for the TMI bits, but keep it ALL brief"). `label` is what the row
## shows: a noun phrase, <= 28 characters, no parentheses and no units unless the
## number is meaningless without them. `tip` is what the row's tooltip says: one
## or two sentences carrying the unit, what 0/off means, and whatever the old
## long label used to spell out. Both are required, and run_tests enforces the
## length, the emptiness and the uniqueness-within-a-group.
##
## Each row: id, label, tip, group (== tab), kind, default, min, max, step, and an
## optional `note` ("next spawn") for levers a rebuild/respawn applies (per-cell
## hp, pod count) — the window paints it as a dim suffix, never inside the label.
## `min`/`max`/`step` are ignored for bools.
const _REGISTRY := [
	# --- Player feel (theme 3: crisp, Terraria/Celeste-responsive movement) --
	# Times and ratios, so they are scale-invariant: identical feel at 1x and 8x.
	{"id": "coyote_time", "label": "Coyote time", "group": "Player",
		"kind": KIND_FLOAT, "default": 0.10, "min": 0.0, "max": 0.3, "step": 0.01,
		"tip": "Seconds after walking off a ledge that a jump still works. 0 restores the old off-the-ledge, no-jump rule."},   # Player._coyote
	{"id": "jump_buffer_time", "label": "Jump buffer", "group": "Player",
		"kind": KIND_FLOAT, "default": 0.10, "min": 0.0, "max": 0.3, "step": 0.01,
		"tip": "Seconds before landing that a jump press still counts. 0 means the press has to land on the frame."},   # Player._jump_buffer
	{"id": "jump_cut", "label": "Jump cut on release", "group": "Player",
		"kind": KIND_FLOAT, "default": 0.45, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "Share of rising speed kept when the jump key is released early. 1 is the old fixed-height jump, 0 a hard stop."},   # Player release-while-rising
	{"id": "fall_damage", "label": "Fall damage", "group": "Player",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 3.0, "step": 0.25,
		"tip": "Multiplier on what a landing costs: 0 is off, 1 shipped, 2 double. The curve itself is Player.fall_damage_for."},   # Player.fall_damage_for

	# --- THE DIVE (Q-G, the roguelite mode) — its own tab: the owner playtests
	# the dive, and 19 dive levers buried in World were unfindable. Flight first,
	# then the ring and the sky, then the population, then damage and loot.
	# THE DIVE IS FLOWN IN AIR (DESIGN_DIVE_REVIEW §1.3): the run starts where
	# real density is 0.05, so without a floor every hull — yours and theirs —
	# falls. 0.85 is where a trimmed hull actually hovers (scale_startup measures
	# it); 0.5 was the review's first number and measured short.
	{"id": "dive_air_floor", "label": "Air density floor", "group": "Dive",
		"kind": KIND_FLOAT, "default": 0.85, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "Thinnest air a hull in a run ever feels — it drives balloon lift AND prop thrust, so 0.85 is where a trimmed hull hovers on a neutral stick. 0 = off, real density."},   # Ship.air_density_floor
	{"id": "dive_rate_control", "label": "Stick commands a speed", "group": "Dive",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, the vertical stick asks for a climb or descent RATE and the hull holds it. Off restores the binary hover the other two modes fly."},   # Ship.rate_control
	{"id": "dive_climb_rate", "label": "Climb rate asked for", "group": "Dive",
		"kind": KIND_FLOAT, "default": 120.0, "min": 0.0, "max": 900.0, "step": 10.0,
		"tip": "What full up-stick asks for, px/s at scale 1 (x8 in the shipped world)."},   # Ship.climb_rate_max
	{"id": "dive_dive_rate", "label": "Descent rate asked for", "group": "Dive",
		"kind": KIND_FLOAT, "default": 240.0, "min": 0.0, "max": 900.0, "step": 10.0,
		"tip": "What full down-stick asks for, px/s at scale 1. 240 was the retired descent cap, so the felt limit survived as the stick's own scale."},   # Ship.dive_rate_max
	{"id": "dive_hull_friction", "label": "Hull keel friction", "group": "Dive",
		"kind": KIND_FLOAT, "default": 0.1, "min": 0.0, "max": 1.0, "step": 0.05,
		"note": "next commit",
		"tip": "Friction under a run's hull. Low slides off slabs; 1.0 restores the stock keel that pinned a hull holding DOWN on a landing."},   # world._tick_dive commit branch
	# The wind ring (owner experiment 2026-08-31): the run's sky loops.
	{"id": "dive_zones_enabled", "label": "The wind ring", "group": "Dive",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, the run's sky loops: updraft at the centre, rocks on the flanks, downdraft on the far side. Off restores the straight corridor."},   # world._dive_hold_the_ring
	{"id": "dive_zone_tile_widths", "label": "Ring tile width", "group": "Dive",
		"kind": KIND_FLOAT, "default": 3.0, "min": 1.0, "max": 40.0, "step": 1.0,
		"tip": "Width of one ring tile in shelf-widths. 3 is about 33 s of lateral travel; 12 measured 133 s — a ring nobody would cross."},   # world._dive_tile_w
	{"id": "dive_zone_wind_mult", "label": "Zone wind strength", "group": "Dive",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.1,
		"tip": "Multiplier on the ring's zone winds. 1 is shipped, 0 stills them."},   # world._dive_weather
	{"id": "dive_draft_band_tiles", "label": "Draft band width", "group": "Dive",
		"kind": KIND_FLOAT, "default": 2.0, "min": 1.0, "max": 6.0, "step": 0.5,
		"tip": "How wide an up/down draft is, in ring tiles. 2 carries the wind a full tile past the seam, so the wrap happens inside it."},   # world.dive_draft_at
	# The closing sky is a DOWNDRAFT, not a rail (owner call 2): a leash you can
	# climb out of near the rung and cannot fight two rungs over.
	{"id": "dive_ceiling_mult", "label": "Closing-sky leash", "group": "Dive",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.1,
		"tip": "Strength of the downdraft holding you under the deepest rung you reached. 1 is shipped, 0 turns the closing sky off."},   # world._dive_weather
	# The pregenerated garrison (owner 2026-09-01: nothing may just APPEAR).
	{"id": "dive_spawn_screens", "label": "Garrison wake distance", "group": "Dive",
		"kind": KIND_FLOAT, "default": 2.0, "min": 0.5, "max": 8.0, "step": 0.25,
		"tip": "Screens of max zoom-out before a standing picket gets a body. Derived from the live camera constants, so a zoom pass moves it too."},   # world.dive_materialize_px
	{"id": "dive_garrison_share", "label": "Garrison share of cap", "group": "Dive",
		"kind": KIND_FLOAT, "default": 0.7, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "Fraction of the picket cap the standing garrison may fill. 1 gives it the whole cap; 0 turns the garrison off for A/B play."},   # world._dive_garrison_budget
	{"id": "dive_picket_cap", "label": "Max live pickets", "group": "Dive",
		"kind": KIND_INT, "default": 9, "min": 3, "max": 30, "step": 1,
		"tip": "Ceiling on live hostile pickets in a run, carcasses excluded — 9 is a real siege, bounded so a parked run cannot accumulate a fleet."},   # world._dive_surge
	{"id": "dive_surge_lead", "label": "Surge lead time", "group": "Dive",
		"kind": KIND_FLOAT, "default": 4.0, "min": 0.5, "max": 15.0, "step": 0.5,
		"tip": "How far ahead of you an F2 surge arrives, in seconds of your current travel. A picket spawned abeam is scenery."},   # world._dive_surge
	# Hull integrity (owner rulings 2026-08-31): a run's vessels die as UNITS.
	{"id": "dive_ship_integrity", "label": "Your hull's integrity", "group": "Dive",
		"kind": KIND_FLOAT, "default": 3000.0, "min": 200.0, "max": 60000.0, "step": 100.0,
		"note": "next commit",
		"tip": "Integrity pool your hull dies as a unit at. A siege deals roughly 100 hp/s of structure, so 3000 is about half a minute undefended."},   # world._tick_dive commit branch
	{"id": "dive_picket_integrity", "label": "Picket integrity", "group": "Dive",
		"kind": KIND_FLOAT, "default": 600.0, "min": 50.0, "max": 20000.0, "step": 50.0,
		"note": "next spawn",
		"tip": "Integrity pool a hostile picket dies at. 600 is about 15 s of focused starter fire — the 30-second ceiling's spirit."},   # world._dive_surge
	{"id": "dive_explosion_damage", "label": "Dying-ship blast", "group": "Dive",
		"kind": KIND_FLOAT, "default": 25.0, "min": 0.0, "max": 500.0, "step": 5.0,
		"tip": "Damage to anyone aboard a ship that explodes. It hurts but must not execute the player; jumping off avoids even that. 0 = harmless."},   # world._dive_explode_ship
	{"id": "dive_scrap_radius", "label": "Scrap pickup radius", "group": "Dive",
		"kind": KIND_FLOAT, "default": 120.0, "min": 0.0, "max": 600.0, "step": 10.0,
		"tip": "How close scrap (the run's physical XP drop) is absorbed, px at scale 1 — 120 is 960 px at the shipped 8x. 0 = no magnet."},   # world.dive_scrap_radius
	{"id": "dive_assistant", "label": "Assistant mans repairs", "group": "Dive",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, a run posts an assistant at the repair station. Off means no station and no crew — the X wand is the only mend."},   # world._dive_post_the_assistant

	# --- Combat --------------------------------------------------------------
	{"id": "sidearm_damage", "label": "Sidearm damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 4.0, "min": 0.0, "max": 200.0, "step": 1.0,
		"tip": "Damage one sidearm shot deals on foot."},   # world._handle_shooting literal
	{"id": "turret_damage", "label": "Turret damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 20.0, "min": 0.0, "max": 500.0, "step": 1.0,
		"tip": "Damage one turret shot deals in a helm volley."},   # world._fire_turrets* literal
	{"id": "fire_rate_mult", "label": "Fire rate", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.25, "max": 5.0, "step": 0.05,
		"tip": "Multiplier on the cadence of every weapon, sidearm and turret alike. 1 is shipped."},   # world sidearm+turret cadence
	{"id": "shot_max_range", "label": "Shot range", "group": "Combat",
		"kind": KIND_FLOAT, "default": 11000.0, "min": 1000.0, "max": 40000.0, "step": 500.0,
		"tip": "How far a shot flies before it expires, in px at scale 1."},   # world.SHOT_MAX_RANGE
	{"id": "enemy_aggro_range", "label": "Enemy aggro range", "group": "Combat",
		"kind": KIND_FLOAT, "default": 700.0, "min": 0.0, "max": 4000.0, "step": 50.0,
		"tip": "How close you must come, in px, before a hostile picks you as its target."},   # world.enemy_aggro_range
	{"id": "enemy_deaggro_range", "label": "Enemy de-aggro range", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1100.0, "min": 0.0, "max": 6000.0, "step": 50.0,
		"tip": "How far you must get, in px, before a hostile gives up the chase. Above the aggro range on purpose, so it cannot flicker."},   # world.enemy_deaggro_range
	{"id": "enemy_shot_speed_mult", "label": "Enemy shot speed", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.5, "min": 0.1, "max": 3.0, "step": 0.05,
		"tip": "Multiplier on the speed of shots fired at you. Below 1 makes them dodgeable."},   # world.enemy_shot_speed_mult
	{"id": "enemy_fire_cooldown", "label": "Enemy fire cooldown", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1.2, "min": 0.1, "max": 5.0, "step": 0.1,
		"tip": "Seconds an enemy waits between its shots."},   # world.ENEMY_FIRE_COOLDOWN
	{"id": "flee_hull_fraction", "label": "Bandit flee threshold", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.45, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "Fraction of hull left at which a bandit breaks off and runs. 0 makes it fight to the wreck."},   # ShipAI.FLEE_HULL_FRACTION
	{"id": "kraken_wildness", "label": "Kraken wildness", "group": "Combat",
		"kind": KIND_FLOAT, "default": 150.0, "min": 0.0, "max": 600.0, "step": 10.0,
		"tip": "Wander acceleration that keeps a kraken, tamed or wild, a little wild in its movement. 0 makes it fly on rails."},   # KrakenAI jitter
	{"id": "kraken_grab_dps", "label": "Kraken grab damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 120.0, "min": 0.0, "max": 1000.0, "step": 5.0,
		"tip": "Damage per second a kraken's mouth-grab deals while it holds on."},   # KrakenAI.GRAB_DPS
	{"id": "kraken_grab_reach", "label": "Kraken grab reach", "group": "Combat",
		"kind": KIND_FLOAT, "default": 70.0, "min": 0.0, "max": 600.0, "step": 5.0,
		"tip": "How far a kraken's mouth-grab reaches, in px at scale 1. 0 disarms the grab."},   # KrakenAI.GRAB_REACH
	{"id": "impact_damage_threshold", "label": "Impact damage floor", "group": "Combat",
		"kind": KIND_FLOAT, "default": 20000.0, "min": 0.0, "max": 100000.0, "step": 1000.0,
		"tip": "Collision energy a ship absorbs for free. Below it a crash costs nothing at all."},   # Ship.IMPACT_DAMAGE_THRESHOLD
	{"id": "impact_damage_scale", "label": "Impact damage scale", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.01, "min": 0.0, "max": 0.2, "step": 0.005,
		"tip": "Damage per unit of collision energy past the free floor. 0 turns crash damage off."},   # Ship.IMPACT_DAMAGE_SCALE
	{"id": "gasbag_collision_resist", "label": "Gasbag collision resist", "group": "Combat",
		"kind": KIND_FLOAT, "default": 10.0, "min": 1.0, "max": 50.0, "step": 1.0,
		"tip": "How many times better a gasbag survives a collision than plain hull. 1 makes balloons as brittle as anything else."},   # BlockDB gasbag collision_resist
	{"id": "ship_restitution", "label": "Collision bounciness", "group": "Combat",
		"kind": KIND_FLOAT, "default": 0.35, "min": 0.0, "max": 1.0, "step": 0.05,
		"note": "next spawn",
		"tip": "Bounce on a ship's physics material: 0 is putty, 1 is a pool ball."},   # Ship physics_material_override.bounce
	{"id": "wash_push_mult", "label": "Prop wash push", "group": "Combat",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 4.0, "step": 0.1,
		"tip": "How hard a running propeller shoves bodies caught in its jet. 0 turns the push off."},   # world._apply_prop_wash
	{"id": "wash_chop_dps", "label": "Prop wash chop damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 45.0, "min": 0.0, "max": 400.0, "step": 5.0,
		"tip": "Damage per second the near jet deals to whatever stands in the blades. 0 leaves props harmless."},   # world._apply_prop_wash
	{"id": "wash_chop_friendly", "label": "Prop chop hits your crew", "group": "Combat",
		"kind": KIND_BOOL, "default": false,
		"tip": "On, your own blades bite your own side too. Off, they spare it."},   # world._apply_prop_wash
	{"id": "basilisk_spit_seconds", "label": "Basilisk spit interval", "group": "Combat",
		"kind": KIND_FLOAT, "default": 3.4, "min": 0.5, "max": 20.0, "step": 0.1,
		"tip": "Seconds between a basilisk's fireballs."},   # BasiliskAI._interval
	{"id": "basilisk_spit_damage", "label": "Basilisk fireball damage", "group": "Combat",
		"kind": KIND_FLOAT, "default": 55.0, "min": 0.0, "max": 400.0, "step": 5.0,
		"tip": "Damage one basilisk fireball deals where it lands."},   # BasiliskAI
	{"id": "basilisk_spit_speed", "label": "Basilisk fireball speed", "group": "Combat",
		"kind": KIND_FLOAT, "default": 900.0, "min": 100.0, "max": 4000.0, "step": 50.0,
		"tip": "How fast a basilisk's fireball travels, in px/s at scale 1."},   # BasiliskAI

	# --- World (terrain, dormancy, sites, hazards, mining, repair) ------------
	{"id": "terrain_subdiv", "label": "Terrain resolution", "group": "World",
		"kind": KIND_INT, "default": 4, "min": 1, "max": 8, "step": 1,
		"note": "on world reset",
		"tip": "How finely terrain is cut: 4 gives 32-px tiles, 8 the too-fine full-8x grid, 1 the legacy coarse one. Read at world build only."},   # Terrain.subdiv
	# Dormancy (owner 2026-08-25: let more things exist while far away).
	{"id": "dormancy_enabled", "label": "Distance dormancy", "group": "World",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, bodies far from every player leave the physics simulation and coast. Off simulates everything, everywhere."},   # world._update_dormancy
	{"id": "dormant_range_px", "label": "Dormancy range", "group": "World",
		"kind": KIND_FLOAT, "default": 12000.0, "min": 2000.0, "max": 60000.0, "step": 500.0,
		"tip": "Distance in px at which a body sleeps; it wakes again at 80% of it. Floored at the max-zoom horizon, so this can only RAISE it — nothing inside a max-zoom frame may sleep."},   # world._update_dormancy
	{"id": "dormant_tick_seconds", "label": "Dormant tick", "group": "World",
		"kind": KIND_FLOAT, "default": 3.0, "min": 0.5, "max": 30.0, "step": 0.5,
		"tip": "Seconds between updates of a sleeping body — how coarsely the far world keeps moving."},   # world._update_dormancy
	{"id": "dormant_max_awake", "label": "Max bodies simulated", "group": "World",
		"kind": KIND_INT, "default": 24, "min": 0, "max": 200, "step": 1,
		"tip": "The nearest N bodies stay in the simulation and the rest sleep, so the vicinity gets the frame budget. 0 = no cap."},   # world._update_dormancy
	{"id": "dormant_drift_mult", "label": "Far migration speed", "group": "World",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 5.0, "step": 0.1,
		"tip": "Multiplier on how fast sleeping creatures migrate about the world. 0 holds them still."},   # world._migrate_dormant
	{"id": "dormant_heal_per_min", "label": "Far creature mending", "group": "World",
		"kind": KIND_FLOAT, "default": 0.05, "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Fraction of its pool a wounded creature mends per minute while out of sight. 0 means nothing heals off screen."},   # world._migrate_dormant
	{"id": "creature_log_range", "label": "Bestiary sighting range", "group": "World",
		"kind": KIND_FLOAT, "default": 1500.0, "min": 200.0, "max": 20000.0, "step": 100.0,
		"tip": "How close, in px at scale 1, counts as having MET a creature for the title bestiary — roughly on-screen at the shipped 8x."},   # world._tick_creature_log
	# Fire (roadmap Phase 4: a fight, not a verdict).
	{"id": "fire_enabled", "label": "Fire", "group": "World",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, fire is a block state that spreads cell to cell through what burns and is doused with the X wand."},   # world._update_fires
	{"id": "fire_rate_scale", "label": "Fire speed", "group": "World",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 5.0, "step": 0.1,
		"tip": "Multiplier on how fast fire spreads and burns. 1 is shipped, 0 freezes it where it stands."},   # scales the dt handed to Fire.step
	{"id": "fire_ignite_chance", "label": "Hazard sets fire", "group": "World",
		"kind": KIND_FLOAT, "default": 0.35, "min": 0.0, "max": 1.0, "step": 0.05,
		"tip": "Chance that a meteor or lava strike ignites what it hits. 0 means hazards never start fires."},   # world.hazard_ignite
	# Spawn sites (charter §4: population lives in the world, not around you).
	{"id": "spawn_sites_enabled", "label": "World spawn sites", "group": "World",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, population lives at world-anchored sites — whale grounds, roosts, kraken dens — so danger has a place. Off empties them."},   # world._update_spawn_sites
	{"id": "site_activate_px", "label": "Site activation range", "group": "World",
		"kind": KIND_FLOAT, "default": 9000.0, "min": 1000.0, "max": 40000.0, "step": 500.0,
		"tip": "How close, in px, a site must be before it puts residents into the world. Inside the dormancy wake range on purpose."},   # world._update_spawn_sites
	{"id": "site_max_residents", "label": "Site residents cap", "group": "World",
		"kind": KIND_INT, "default": 12, "min": 0, "max": 60, "step": 1,
		"tip": "How many site-spawned bodies may be alive at once worldwide — the safety net under the pools. 0 empties the sky."},   # world._resident_count
	{"id": "site_release_seconds", "label": "Site release interval", "group": "World",
		"kind": KIND_FLOAT, "default": 12.0, "min": 0.0, "max": 120.0, "step": 1.0,
		"tip": "Seconds between one site letting out one resident, so a place fills up instead of dumping its pool at you."},   # world._tick_site
	{"id": "site_regen_seconds", "label": "Site regrow interval", "group": "World",
		"kind": KIND_FLOAT, "default": 240.0, "min": 5.0, "max": 1800.0, "step": 5.0,
		"tip": "Seconds a site takes to regrow one resident. Slow on purpose: a place can be hunted out."},   # world._tick_site
	{"id": "site_reclaim_px", "label": "Resident reclaim range", "group": "World",
		"kind": KIND_FLOAT, "default": 45000.0, "min": 15000.0, "max": 200000.0, "step": 5000.0,
		"tip": "How far, in px, a resident may wander before its site takes the body back."},   # world._tick_site
	# Sandbox (owner 2026-08-28): a play/dev toggle that removes the GATES, so a
	# single system can be felt without the grind. Not new game scope.
	{"id": "sandbox_mode", "label": "Sandbox", "group": "World",
		"kind": KIND_BOOL, "default": false,
		"tip": "On, the gates open: no deep-air suffocation and nothing scarce. The Player tab's kit-me-out button flips this on and grants the loadout."},   # world._update_suffocation
	# Edge POI markers (owner 2026-08-29): measured against the LIVE camera, so
	# "two screens" stays two screens on foot or pulled back at the helm.
	{"id": "edge_markers_enabled", "label": "Edge POI markers", "group": "World",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, triangles at the screen edge point at points of interest you cannot see yet."},   # world.edge_marker_targets
	{"id": "edge_marker_screens", "label": "Edge marker range", "group": "World",
		"kind": KIND_FLOAT, "default": 2.0, "min": 0.0, "max": 8.0, "step": 0.25,
		"tip": "How far a point of interest may be, in screens of the live camera, and still get a marker. 0 silences them like the toggle."},   # world.edge_marker_range_px
	{"id": "backdrop_enabled", "label": "Layered background", "group": "World",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, parallax silhouettes sit behind the world. Off leaves the plain clear colour."},   # Backdrop._draw
	{"id": "backdrop_parallax", "label": "Backdrop parallax", "group": "World",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How much the backdrop moves: 0 pins it still as pure scenery, 1 is the shipped calm, above 1 walks back toward the dizzy first cut."},   # Backdrop.layer_scroll
	{"id": "backdrop_opacity", "label": "Backdrop opacity", "group": "World",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.0, "max": 3.0, "step": 0.05,
		"tip": "How solid the backdrop silhouettes are. 0 leaves the band sky and drops every silhouette."},   # Backdrop.feature_alpha
	{"id": "creature_ram_damage", "label": "Creature ram damage", "group": "World",
		"kind": KIND_FLOAT, "default": 4.0, "min": 1.0, "max": 12.0, "step": 0.5,
		"tip": "Multiplier on the impact bite a VESSEL takes from a creature's body — creature-on-creature keeps the ecology's own factors. 1 restores the old scratch."},   # Ship._apply_pending_impacts
	# Ecology (Q-C): overhunt whales and nothing holds the deep in check.
	{"id": "eco_enabled", "label": "Ecology", "group": "World",
		"kind": KIND_BOOL, "default": true,
		"tip": "On, killing whales lets the krakens rise: an ascendancy meter drives kraken den surges worldwide."},   # world._tick_ecology
	{"id": "eco_kill_rise", "label": "Ascendancy per whale", "group": "World",
		"kind": KIND_FLOAT, "default": 0.05, "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "How far up the 0..1 ascendancy meter each whale-family death pushes the deep."},   # world._on_creature_perished
	{"id": "eco_recover_per_min", "label": "Deep recovery rate", "group": "World",
		"kind": KIND_FLOAT, "default": 0.03, "min": 0.0, "max": 1.0, "step": 0.01,
		"tip": "Ascendancy the deep sheds per minute — this IS the safe harvest rate. 0 means overhunting never heals."},   # world._tick_ecology
	{"id": "eco_kraken_gain", "label": "Kraken den surge gain", "group": "World",
		"kind": KIND_FLOAT, "default": 2.0, "min": 0.0, "max": 6.0, "step": 0.25,
		"tip": "Multiplier on what a kraken den fields at full ascendancy: a base pool of 2 rising to 6."},   # world._kraken_surge_pool
	{"id": "mine_power", "label": "Mining power", "group": "World",
		"kind": KIND_FLOAT, "default": 240.0, "min": 10.0, "max": 2000.0, "step": 10.0,
		"tip": "Hp per second the mining beam takes out of terrain."},   # world.MINE_POWER
	{"id": "mine_reach_cells", "label": "Mining reach", "group": "World",
		"kind": KIND_FLOAT, "default": 4.5, "min": 1.0, "max": 20.0, "step": 0.5,
		"tip": "How far the mining beam reaches, in terrain cells."},   # world.MINE_REACH_CELLS
	{"id": "repair_rate", "label": "Repair wand rate", "group": "World",
		"kind": KIND_FLOAT, "default": 45.0, "min": 1.0, "max": 500.0, "step": 5.0,
		"tip": "Hp per second the X wand restores toward the blueprint."},   # world.REPAIR_RATE
	{"id": "repair_station_rate", "label": "Repair station rate", "group": "World",
		"kind": KIND_FLOAT, "default": 30.0, "min": 1.0, "max": 500.0, "step": 5.0,
		"tip": "Hp per second a manned repair station heals, scaled by the ship's power ratio. Slow and radial by design."},   # Ship.tick_menders
	{"id": "meteor_interval", "label": "Meteor interval", "group": "World",
		"kind": KIND_FLOAT, "default": 3.5, "min": 0.2, "max": 30.0, "step": 0.1,
		"tip": "Seconds between meteor strikes in the hazard band."},   # Hazards.METEOR_INTERVAL
	{"id": "meteor_damage", "label": "Meteor damage", "group": "World",
		"kind": KIND_FLOAT, "default": 60.0, "min": 0.0, "max": 500.0, "step": 5.0,
		"tip": "Damage one meteor deals where it lands."},   # Hazards.METEOR_DAMAGE
	{"id": "meteor_speed", "label": "Meteor speed", "group": "World",
		"kind": KIND_FLOAT, "default": 95.0, "min": 10.0, "max": 600.0, "step": 5.0,
		"tip": "How fast a meteor falls, in px/s at scale 1."},   # Hazards.METEOR_SPEED
	{"id": "lava_interval", "label": "Lava interval", "group": "World",
		"kind": KIND_FLOAT, "default": 2.2, "min": 0.2, "max": 30.0, "step": 0.1,
		"tip": "Seconds between lava launches out of the deep."},   # Hazards.LAVA_INTERVAL
	{"id": "lava_damage", "label": "Lava damage", "group": "World",
		"kind": KIND_FLOAT, "default": 80.0, "min": 0.0, "max": 500.0, "step": 5.0,
		"tip": "Damage one lava bomb deals on a hit."},   # Hazards.LAVA_DAMAGE
	{"id": "lava_speed", "label": "Lava launch speed", "group": "World",
		"kind": KIND_FLOAT, "default": 560.0, "min": 50.0, "max": 1500.0, "step": 10.0,
		"tip": "How fast a lava bomb is thrown, in px/s at scale 1."},   # Hazards.LAVA_SPEED
	{"id": "suffocate_interval", "label": "Suffocation interval", "group": "World",
		"kind": KIND_FLOAT, "default": 1.0, "min": 0.1, "max": 10.0, "step": 0.1,
		"tip": "Seconds between suffocation ticks in air too deep to breathe."},   # LifeSupport.tick cadence
	{"id": "suffocate_damage", "label": "Suffocation damage", "group": "World",
		"kind": KIND_FLOAT, "default": 10.0, "min": 0.0, "max": 200.0, "step": 1.0,
		"tip": "Damage each suffocation tick deals to a body without life support."},   # LifeSupport.tick per-tick

	# --- Whale and the rest of the ecology's bodies ---------------------------
	{"id": "whale_health", "label": "Whale health", "group": "Whale",
		"kind": KIND_FLOAT, "default": 1000.0, "min": 50.0, "max": 60000.0, "step": 50.0,
		"note": "next spawn",
		"tip": "A whale's health pool. 1000 is roughly 25 s of starter fire, under the owner's 30-second kill ceiling."},   # world.WHALE_HEALTH
	{"id": "whale_pod_size", "label": "Pod count", "group": "Whale",
		"kind": KIND_INT, "default": 3, "min": 1, "max": 8, "step": 1,
		"note": "next spawn",
		"tip": "How many whales a pod spawns with."},   # world.WHALE_POD_SIZE
	{"id": "boss_health", "label": "City-whale boss health", "group": "Whale",
		"kind": KIND_FLOAT, "default": 1200.0, "min": 50.0, "max": 60000.0, "step": 50.0,
		"note": "next spawn",
		"tip": "The Leviathan Arcology's pool. 1200 is the 30-second ceiling's maximum; raising it past that is a deliberate boss exception."},   # world._spawn_boss
	{"id": "basilisk_health", "label": "Basilisk health", "group": "Whale",
		"kind": KIND_FLOAT, "default": 700.0, "min": 50.0, "max": 30000.0, "step": 50.0,
		"tip": "The top-band fire-spitter's pool. 700 is roughly 18 s of starter fire."},   # world._spawn_one_basilisk
	{"id": "creature_coarse_cells", "label": "Creature collider detail", "group": "Whale",
		"kind": KIND_INT, "default": 12, "min": 2, "max": 400, "step": 1,
		"note": "next rebuild",
		"tip": "Cells per collider box: small traces the silhouette at a physics cost, huge collapses the creature to one old-style AABB."},   # Ship._coarse_creature_rects
	{"id": "whale_push_accel", "label": "Ram strength", "group": "Whale",
		"kind": KIND_FLOAT, "default": 1100.0, "min": 0.0, "max": 4000.0, "step": 25.0,
		"tip": "Acceleration a whale rams with once it decides to push."},   # WhaleAI.PUSH_ACCEL
	{"id": "whale_ride_accel", "label": "Ride throttle", "group": "Whale",
		"kind": KIND_FLOAT, "default": 620.0, "min": 0.0, "max": 2000.0, "step": 20.0,
		"tip": "Acceleration a ridden whale answers your steering with."},   # WhaleAI.RIDE_ACCEL
	{"id": "whale_align_accel", "label": "Align accel", "group": "Whale",
		"kind": KIND_FLOAT, "default": 360.0, "min": 0.0, "max": 1500.0, "step": 20.0,
		"tip": "How hard a whale turns its body to line up with where it is going."},   # WhaleAI.ALIGN_ACCEL
	{"id": "whale_anger_seconds", "label": "Anger duration", "group": "Whale",
		"kind": KIND_FLOAT, "default": 30.0, "min": 0.0, "max": 120.0, "step": 1.0,
		"tip": "Seconds a provoked whale stays angry before it settles again."},   # WhaleAI.ANGER_SECONDS
	# Both impact factors were divided by 15 with WHALE_HEALTH, so a crash costs
	# the same PERCENT of the pool it did before the 30-second ceiling.
	{"id": "creature_impact_factor", "label": "Creature ram factor", "group": "Whale",
		"kind": KIND_FLOAT, "default": 0.0033, "min": 0.0, "max": 1.0, "step": 0.0005,
		"tip": "Share of collision energy a creature's own ram turns into damage to what it hit."},   # Ship.CREATURE_IMPACT_FACTOR
	{"id": "creature_terrain_impact_factor", "label": "Creature crash factor", "group": "Whale",
		"kind": KIND_FLOAT, "default": 0.0013, "min": 0.0, "max": 1.0, "step": 0.0005,
		"tip": "Share of collision energy a creature loses to itself when it flies into terrain."},   # Ship.CREATURE_TERRAIN_IMPACT_FACTOR
	{"id": "whale_mine_interval", "label": "Ridden-mine pulse", "group": "Whale",
		"kind": KIND_FLOAT, "default": 0.15, "min": 0.02, "max": 2.0, "step": 0.01,
		"tip": "Seconds between digs while you ride a whale into terrain."},   # world ride-mining RATE
	{"id": "whale_mine_reach", "label": "Ridden-mine depth", "group": "Whale",
		"kind": KIND_INT, "default": 1, "min": 1, "max": 8, "step": 1,
		"tip": "How many cells deep one ridden-mine pulse digs. 1 digs at the contact face rather than ahead of it."},   # world ride-mining REACH
	{"id": "whale_mine_breadth", "label": "Ridden-mine breadth", "group": "Whale",
		"kind": KIND_INT, "default": 1, "min": 0, "max": 8, "step": 1,
		"tip": "Extra cells dug either side of the contact point."},   # world ride-mining BREADTH
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


## The one-or-two-sentence tooltip for a lever ("" for an unknown id). The window
## paints it on both the row's label and its control.
static func tip(id: String) -> String:
	_ensure()
	return str(def(id).get("tip", ""))


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
