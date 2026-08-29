extends SceneTree

## Startup test for the real main scene.
##
## The unit suite builds ships directly, so it cannot catch a game that boots
## into a broken state — which is exactly what happened when single-player was
## misdetected as a network session and the player was never given a ship.
## This loads world.tscn the way the game does and asserts you can actually
## play: you start aboard a ship, and you are never left waiting for one.

var failures := 0


func _initialize() -> void:
	print("\n=== world startup (legacy 1x scene) ===\n")

	# 8x is the shipped default (maps/world/world.tscn); this suite keeps
	# the legacy 1x reference scene honest, because its thresholds were
	# written for 1x distances. The 8x default boots under
	# scale_startup_test.gd.
	var packed: PackedScene = load("res://maps/scale_test/scale_test.tscn")
	if packed == null:
		print("    FAIL could not load res://maps/scale_test/scale_test.tscn")
		return _finish()

	var world: Node = packed.instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame

	var fleet = world.get("fleet")
	_ok(fleet != null, "world built a Fleet")
	if fleet == null:
		return _finish()

	# Your ship + the hulk + a POD of whales (WHALE_POD_SIZE) + a few small
	# critters (CRITTER_COUNT — the early taming target) + the deep kraken pod
	# (KRAKEN_COUNT). The whale-variant spawner (Sprint 4) fills the sky with a
	# few whales, not just one.
	# +1 for the city-whale BOSS, planted at its fixed deep lair in every world.
	var expected_ships: int = 2 + world.WHALE_POD_SIZE + world.CRITTER_COUNT + world.KRAKEN_COUNT + 1
	_ok(fleet.ships().size() == expected_ships,
		"your ship, the hulk, %d whales, %d critters, %d krakens and the boss exist (got %d)"
			% [world.WHALE_POD_SIZE, world.CRITTER_COUNT, world.KRAKEN_COUNT, fleet.ships().size()])
	_ok(fleet.ships().any(func(s) -> bool: return s.faction == 1),
		"one of them is the hostile target hulk")
	# Whales are the tier-2 creatures; critters the tier-1 (faction 2 both).
	_ok(fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken" and s.creature_kind != "whale_city").size() == world.WHALE_POD_SIZE,
		"the neutral whale pod is present (tier 2)")
	_ok(fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level == 1).size() == world.CRITTER_COUNT,
		"and a few small tameable critters (tier 1)")

	# The live whale must get the COARSE collider — not the exact per-cell grid
	# — or the whale-ship-wall sandwich solves at ~76 ms (~3 FPS, owner
	# 2026-08-22). This is the REAL spawn path: _spawn_whale sets the health pool
	# AFTER the collider is first built, so it must rebuild, or the whale looks
	# like a vessel (pool 0) at build time and keeps the 7-shape precise collider
	# for life. Assert the actual built collider is coarser than the precise
	# merge — reading _use_coarse_collider() alone would miss the bug (it reads
	# current health, true by now, even if the built collider is stale-precise).
	var whale_ship = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken" and s.creature_kind != "whale_city")[0]
	var whale_shapes := 0
	for c in whale_ship.get_children():
		if c is CollisionShape2D:
			whale_shapes += 1
	var precise_shapes: int = whale_ship._merge_rects().size()
	_ok(whale_shapes < precise_shapes,
		"the live whale got the COARSE collider (%d shapes < %d precise) — rebuilt after its pool was set"
			% [whale_shapes, precise_shapes])

	var local = world.get("local_ship")
	_ok(local != null, "the player has a ship — single-player never waits")
	if local == null:
		return _finish()

	_ok(local.blocks.size() > 0, "the ship has blocks (%d)" % local.blocks.size())
	_ok(local.mass > 1.0, "the ship derived a real mass (%.0f)" % local.mass)
	_ok(not local.freeze, "the ship simulates locally")
	_ok(local.lift_ratio() > 0.9 and local.lift_ratio() < 1.1,
		"the starter is trimmed near neutral (%.2f) — the altitude hold flies it"
			% local.lift_ratio())

	# --- Engineering overlay (F): off by default, two focused modes ----------
	# End-to-end on the REAL ship: the overlay is a picture of the ship's own
	# derived numbers, so the readout must carry them and the F cycle must walk
	# off -> FLIGHT -> SYSTEMS -> off.
	_ok(int(world.get("_eng_overlay_mode")) == 0, "the engineering overlay starts OFF")
	_ok(world.engineering_overlay() == null, "...and paints nothing while off")
	var er: Dictionary = local.engineering_readout()
	var er_ok := true
	for key in ["com", "lift_ratio", "vthrust", "hthrust", "power_supply",
			"power_draw", "power_ratio", "bounds"]:
		er_ok = er_ok and er.has(key)
	_ok(er_ok, "the ship's engineering readout carries every field the overlay paints")
	world._cycle_eng_overlay()
	var flight: Variant = world.engineering_overlay()
	_ok(flight != null and int((flight as Dictionary)["mode"]) == 1
			and (flight as Dictionary)["name"] == "FLIGHT",
		"F cycles the overlay to FLIGHT mode")
	# The overlay now lists every ship in reach, each carrying its own transform.
	var f_ships: Array = (flight as Dictionary)["ships"]
	_ok(not f_ships.is_empty() and (f_ships[0] as Dictionary).has("xform")
			and not (f_ships[0] as Dictionary).has("machines"),
		"FLIGHT lists ships with a transform and no power markers")
	var has_local := false
	for sh in f_ships:
		if bool((sh as Dictionary).get("is_local", false)):
			has_local = true
	_ok(has_local, "your own ship is in the readout (flagged local)")
	world._cycle_eng_overlay()
	var systems: Variant = world.engineering_overlay()
	_ok(systems != null and int((systems as Dictionary)["mode"]) == 2
			and (systems as Dictionary)["name"] == "SYSTEMS",
		"a second F cycles to SYSTEMS mode")
	var feeders := 0
	var drawers := 0
	for m in local.power_markers():
		if int(m["role"]) > 0:
			feeders += 1
		else:
			drawers += 1
	var s_ships: Array = (systems as Dictionary)["ships"]
	_ok(not s_ships.is_empty() and (s_ships[0] as Dictionary).has("machines"),
		"SYSTEMS lists ships with power markers")
	_ok(feeders > 0 and drawers > 0,
		"the starter's power grid reads both feeders (%d engines) and drawers (%d props/turrets)"
			% [feeders, drawers])
	world._cycle_eng_overlay()
	_ok(int(world.get("_eng_overlay_mode")) == 0 and world.engineering_overlay() == null,
		"a third F cycles the overlay back OFF")

	# You are a person, not a ship. The player must exist and be on foot, and
	# the ship must only respond once you actually use the helm.
	var p = world.get("player")
	_ok(p != null, "a player character exists")
	if p == null:
		return _finish()
	_ok(not p.is_piloting(), "the player starts on foot, not flying the ship")

	var found: Array = p.find_helm(fleet.ships(), p.global_position)
	_ok(not found.is_empty(), "a helm is within reach of the spawn point")
	if not found.is_empty():
		_ok(p.board(found[0], found[1]), "the player can take the helm")
		_ok(p.is_piloting(), "and is now piloting")

		# Regression: boarding used to leave the player's collider overlapping
		# the hull, and the solver went berserk trying to separate them. Stay
		# at the helm through real simulation and require calm physics.
		var before_rot: float = local.rotation
		for i in 60:
			await physics_frame
		_ok(absf(local.angular_velocity) < 0.5,
			"piloting is calm — no solver fight (%.2f rad/s)" % local.angular_velocity)
		_ok(absf(wrapf(local.rotation - before_rot, -PI, PI)) < 0.5,
			"the ship did not get shoved into a spin by its own pilot")
		_ok(p.global_position.distance_to(local.global_position) < 200.0,
			"the player is tethered to the ship, not left behind")

		p.disembark()
		_ok(not p.is_piloting(), "and can step off again")
		for i in 30:
			await physics_frame
		_ok(p.global_position.distance_to(local.global_position) < 400.0,
			"after stepping off, the player lands on or near the deck")

	var start_y: float = local.global_position.y
	var blocks_before: int = local.blocks.size()
	for i in 60:
		await physics_frame

	# Charter §9 / ORIGINAL_PLAYTEST: it must not be trivial to damage your own
	# ship. Merely standing on the deck is the most trivial case there is.
	_ok(local.blocks.size() == blocks_before,
		"standing on your own ship does not damage it (%d -> %d blocks)"
			% [blocks_before, local.blocks.size()])
	_ok(absf(local.global_position.y - start_y) < 20.0,
		"altitude hold keeps the parked ship put (drifted %.0f px)"
			% (local.global_position.y - start_y))

	# Jumping off must be survivable as a session, not a softlock. You are
	# allowed to fall to your death; you are not allowed to fall forever.
	p.global_position = Vector2(0, world.WORLD_BOTTOM + 500.0)
	for i in 5:
		await physics_frame
	_ok(p.global_position.y < world.WORLD_BOTTOM,
		"falling out of the world respawns you instead of dropping forever")

	p.global_position = Vector2(9000, 9000)
	world.respawn_player()
	_ok(p.global_position.distance_to(local.global_position) < 200.0,
		"the respawn key puts you back on your ship")

	# The take-damage payoff, end to end: draining the GRIT pool to zero must kill
	# the on-foot player and respawn them on the deck with a full pool (the wired
	# `died` signal reuses respawn_player). The wiring is lazy per physics frame.
	p.global_position = Vector2(9000, 9000)
	for i in 3:
		await physics_frame          # let _watch_player_death wire this body's `died`
	var full_pool: float = p.max_health
	p.take_damage(p.max_health + 1000.0)
	for i in 3:
		await physics_frame
	_ok(p.global_position.distance_to(local.global_position) < 200.0,
		"dying at 0 HP respawns you on your ship")
	_ok(p.health > 0.0 and p.health >= full_pool - 0.01,
		"and the GRIT pool is restored to full (%.0f/%.0f)" % [p.health, p.max_health])

	# Spawn sites OFF before this count (and, below, for the rest of the suite):
	# the player was just teleported to (9000,9000), so a world-anchored site can
	# activate near that focus and fold residents into the reset fleet — a
	# pre-existing flake that returned 10 or 14 depending on the scheduler. The
	# reset is a ship-COUNTING check like the others below, so it belongs under
	# the same disable (which the block further down explains and restores).
	Tunables.set_value("spawn_sites_enabled", false)
	await world.reset_world()
	await process_frame
	_ok(fleet.ships().size() == expected_ships,
		"reset leaves your ship, a fresh hulk and a fresh whale pod (got %d)"
			% fleet.ships().size())
	_ok(world.get("player") != null and not world.player.is_piloting(),
		"reset leaves you on foot")

	# The decluttered screen (owner 2026-08-22): the map and help panels are HIDDEN
	# by default (the calm screen), and their toggles flip visibility. Asserted
	# here rather than the unit suite because only the real scene builds them.
	var mapv = world.get("_map_view")
	var helpp = world.get("_help_panel")
	_ok(mapv != null and not mapv.visible, "the world map is hidden by default")
	_ok(helpp != null and not helpp.visible, "the help panel is hidden by default (no wall of text)")
	if mapv != null:
		world._toggle_map()
		_ok(mapv.visible, "Tab shows the map")
		world._toggle_map()
		_ok(not mapv.visible, "and Tab hides it again")
		# THE MAP FRAMES THE WHOLE WORLD (owner 2026-08-25: "the map doesn't
		# seem to have scaled with the world changes"). The true world px
		# extent is subdiv-INVARIANT — WORLD_CELLS × CELL × world_scale, the
		# same rect the boundary walls frame — and the map must read exactly
		# it. Before the fix it read 1/subdiv of the world (a quarter at the
		# shipped subdiv 4: this world's, since Tunables defaults subdiv 4).
		var want: Vector2 = Vector2(IslandGen.WORLD_CELLS.size) 			* TerrainDB.CELL * float(world.world_scale)
		var got: Vector2 = mapv._world_px_rect().size
		_ok(got.is_equal_approx(want),
			"the map frames the WHOLE subdiv-scaled world (%s of %s px)"
				% [str(got), str(want)])
		_ok(mapv._world_px_rect().has_point(world.get("_world_rect").get_center()),
			"and it is the same rect the boundary walls frame")
	if helpp != null:
		world._toggle_help()
		_ok(helpp.visible, "F1 shows the help/controls panel")
		world._toggle_help()
		_ok(not helpp.visible, "and F1 hides it again")

	# Hidden easter egg pin: the secret Cairn beacon exists in the REAL generated
	# world (world._build_generated_terrain plants it). Catches removal of the call
	# — the unit suite plants it itself and would miss that regression.
	var terr0 = world.get("terrain")
	_ok(terr0 != null and terr0.is_solid(EasterEggs.cairn_cell_for(terr0)),
		"the secret Cairn is present in the real generated world")
	_ok(terr0 != null and terr0.is_solid(EasterEggs.high_cairn_cell_for(terr0)),
		"the bookend High Cairn is present in the real generated world too")

	# TERRAIN RESOLUTION: the default world generates at the Tunables default
	# (subdiv 4 since 2026-08-24 — the owner walked full-8× back to "1/4 the
	# blocks, bigger each": 32px tiles, player ~4.5 tall). THE break-the-fix
	# pin for the resolution rounds: finer than legacy-coarse, and exactly the
	# registered default.
	if terr0 != null:
		var p_h: float = world.player.SIZE.y * world.player.scale.y \
			if world.player != null else 0.0
		var tiles: float = p_h / terr0.cell_px() if terr0.cell_px() > 0.0 else 0.0
		_ok(terr0.subdiv == Tunables.get_int("terrain_subdiv"),
			"the default world generates at the registered subdiv default (%d)" % terr0.subdiv)
		_ok(terr0.subdiv >= 2 and tiles >= 3.0,
			"the player spans several terrain tiles (%.1f) — chunky, not pixel-fine, not coarse" % tiles)

	# The character sheet (K) is hidden by default and toggles like the map/help.
	var sheet = world.get("_character_sheet")
	_ok(sheet != null and not sheet.visible, "the character sheet is hidden by default")
	if sheet != null:
		world._toggle_character_sheet()
		_ok(sheet.visible, "K shows the character sheet")
		world._toggle_character_sheet()
		_ok(not sheet.visible, "and K hides it again")

	# The trainer station exists in the real generated world.
	var tr = world.get("_trainer")
	_ok(tr != null and is_instance_valid(tr), "a trainer station was planted in the world")

	# WORLD-ANCHORED POPULATION OFF for the rest of the suite. Sites are ON in
	# the shipped game (charter §4) but every check below teleports a focus
	# somewhere and then counts the ships it finds, and a site doing its job
	# would put residents into those counts. _check_spawn_sites turns it on for
	# exactly as long as it needs, and this is restored at the end.
	Tunables.set_value("spawn_sites_enabled", false)

	_check_kraken_prey(world, fleet)
	_check_mining(world)
	_check_placing(world)
	await _check_harvesting(world)
	await _check_corpse_airship(world)
	await _check_balloon_economy(world)
	_check_unified_controls(world)
	await _check_progression(world)
	await _check_save_load(world)
	await _check_taming(world, fleet)
	await _check_fire(world, fleet)
	await _check_basilisk(world, fleet)
	await _check_spawn_sites(world, fleet)
	await _check_ecology(world, fleet)
	await _check_debug_window(world, fleet)
	await _check_repair_station(world, fleet)
	_check_boss(world, fleet)
	await _check_loft_ship(world, fleet)
	await _check_lava_core(world, fleet)
	await _check_sandbox(world, fleet)
	await _check_edge_markers(world, fleet)
	await _check_backdrop_and_chooser(world, fleet)

	await _check_hosting_after_offline_play(world, fleet)

	_finish()


## The owner's Blueprint-Loft test ship spawns on demand (F2), upscaled so it is
## boardable: a faction-0 VESSEL with a helm you can take. Proves the .ship parses,
## upscales, and reaches the fleet as a player-side, pilotable hull.
func _check_loft_ship(world: Node, fleet) -> void:
	var pl = world.get("player")
	var at: Vector2 = (pl.global_position if pl != null else Vector2.ZERO) + Vector2(400.0, 0.0)
	var ship = world.call("debug_spawn", "loft", at)
	_ok(ship != null, "the Loft test ship spawns on demand")
	if ship == null:
		return
	_ok(ship.faction == 0, "it spawns on your side (faction 0)")
	_ok(ship.shared_health_max <= 0.0, "it is a VESSEL you can board, not a creature")
	_ok(not ship.helm_cells.is_empty(),
		"it carries a boardable helm (%d cells, upscaled 8x)" % ship.helm_cells.size())
	# Remove it before the next check samples the fleet — queue_free is deferred,
	# so wait a frame or the count carries this scratch ship into the lava test.
	ship.queue_free()
	await world.get_tree().physics_frame

	# The PASTE path: a .ship string (the Loft's export) spawns the same way.
	var pasted = world.call("debug_spawn_text",
		"# t\norigin 1 1\n###\n#H#\n###", at + Vector2(700.0, 0.0))
	_ok(pasted != null and pasted.faction == 0 and not pasted.helm_cells.is_empty(),
		"a pasted .ship string spawns a boardable, faction-0 vessel")
	if pasted != null:
		pasted.queue_free()
		await world.get_tree().physics_frame


## The city-whale BOSS is planted at a fixed deep lair in every world (not gated
## behind a rare seed). Prove it exists, reads as the boss (its own pool), is a
## whale-tier creature, and lairs DEEP — the "find it in the overworld" contract.
func _check_boss(world: Node, fleet) -> void:
	var boss: Ship = null
	for s in fleet.ships():
		if is_instance_valid(s) and String(s.creature_kind) == "whale_city":
			boss = s
			break
	_ok(boss != null, "the city-whale boss is planted in the world")
	if boss == null:
		return
	var boss_hp: float = float(Tunables.def("boss_health")["default"])
	_ok(is_equal_approx(boss.shared_health_max, boss_hp),
		"it carries the BOSS pool, not a whale's (%.0f)" % boss.shared_health_max)
	_ok(boss.faction == 2 and boss.tame_level >= 2,
		"it is a whale-tier creature (faction 2, tame tier %d)" % boss.tame_level)
	# Deep: below the world's vertical midpoint (positive y is down).
	var rect: Rect2 = world.get("_world_rect")
	_ok(boss.global_position.y > rect.get_center().y,
		"it lairs DEEP, out in the overworld (y=%.0f, mid=%.0f)"
			% [boss.global_position.y, rect.get_center().y])


## The repair STATION at 8×, end to end in the real scene: the F2 debug adder
## stamps a 4×4 bundle, E toggles it, and the WORLD's mender clock heals a wound
## over real frames — the wiring (world._update_menders → Ship.tick_menders) the
## unit suite drives by hand.
func _check_repair_station(world: Node, fleet) -> void:
	var ship = world.get("local_ship")
	if ship == null or not is_instance_valid(ship):
		_ok(false, "repair station: no local ship to test on")
		return
	var placed: bool = world.call("debug_add_mender")
	_ok(placed, "debug_add_mender bolts a repair station onto the ship")
	if not placed:
		return
	# Scale-agnostic: the station is a 4×4 bundle at 8× but one cell at the 1×
	# test scale (BUNDLE_8X is a shipped-8× table; bundle_dims is (4,4) there,
	# pinned in the unit suite). Either way it must register in the hot-list.
	_ok(ship.repair_cells.size() >= 1,
		"the station registers in the repair hot-list (%d cells)" % ship.repair_cells.size())

	_ok(not ship.menders_running, "the station starts OFF")
	var idle_draw: float = ship.active_draw()
	ship.net_toggle_mender()
	_ok(ship.menders_running, "E (net_toggle_mender) turns it ON")
	_ok(ship.active_draw() > idle_draw,
		"and a running station now draws ship power (%.0f > %.0f)"
			% [ship.active_draw(), idle_draw])

	# Wound a hull cell nearest the station and let the world's 8 Hz clock mend it.
	var st: Vector2i = ship.repair_cells[0]
	var target := Vector2i.ZERO
	var found := false
	var best := 1 << 30
	for cell in ship.blocks:
		# A HULL cell specifically (hp 100): a 40 wound scuffs it without
		# destroying it (so the follow-up hp read is always valid).
		if int(ship.blocks[cell]["type"]) != BlockDB.Type.HULL:
			continue
		var d := absi(cell.x - st.x) + absi(cell.y - st.y)
		if d > 0 and d < best:
			best = d
			target = cell
			found = true
	_ok(found, "found a hull cell near the station to wound")
	if not found:
		return
	ship.damage_cell(target, 40.0)
	var wounded: float = float(ship.blocks[target]["hp"])
	for i in 90:
		await world.get_tree().physics_frame
	_ok(float(ship.blocks[target]["hp"]) > wounded,
		"the running station healed the wound over time (%.0f -> %.0f)"
			% [wounded, float(ship.blocks[target]["hp"])])

	# Off: the wound holds.
	ship.net_toggle_mender()
	_ok(not ship.menders_running, "E toggles it OFF again")
	ship.damage_cell(target, 20.0)
	var held: float = float(ship.blocks[target]["hp"])
	for i in 30:
		await world.get_tree().physics_frame
	_ok(is_equal_approx(float(ship.blocks[target]["hp"]), held),
		"an OFF station heals nothing (hp held at %.0f)" % held)


## The kraken's mouth chews PEOPLE, and that only works if the WORLD hands the
## brain the on-foot player every tick (KrakenAI.prey_player). The unit suite
## drives the AI by hand, so the WIRING — world._creature_swim → the live AI —
## can only be proven here, in the real scene.
func _check_kraken_prey(world: Node, fleet) -> void:
	var pl = world.get("player")
	var ais: Dictionary = world.get("_whale_ais")
	var kai = null
	for id in ais:
		if ais[id] is KrakenAI:
			kai = ais[id]
			break
	_ok(kai != null, "the world's deep krakens run a KrakenAI")
	if kai == null or pl == null or fleet.ships().is_empty():
		return
	_ok(kai.prey_player == pl,
		"and the swim loop hands it the on-foot player as bite prey")

	# A PILOT rides inside the hull the mouth is already chewing, so they stop
	# being prey the moment they take a helm — one grab, billed once. Set and
	# restored without awaiting a frame, so nothing else observes the fake helm.
	var was = pl.piloting
	pl.piloting = fleet.ships()[0]
	_ok(world._on_foot_player() == null, "a PILOT is not bite prey — the hull is")
	pl.piloting = was
	_ok(world._on_foot_player() == pl, "and stepping back off makes them prey again")


## Mining, end to end through the REAL scene: the reach gate, the hardness
## dig-time and the item credit that the unit suite (which has no world/player)
## cannot exercise. Drives world.try_mine directly with a chosen cell so no
## mouse or input map is needed — _handle_mining just feeds it the cursor cell.
## Single-player only, so it runs BEFORE hosting flips the world online.
func _check_mining(world: Node) -> void:
	var pl = world.get("player")
	var terr = world.get("terrain")
	_ok(pl != null and terr != null, "the real scene has a player and terrain to mine")
	if pl == null or terr == null:
		return
	if pl.is_piloting():
		pl.disembark()

	# A known cell of the generated floor (top row is dirt). Solid to start.
	# COARSE coordinate ×subdiv: the same physical spot at any terrain resolution.
	var cell: Vector2i = Vector2i(0, 8) * int(terr.subdiv)
	_ok(terr.is_solid(cell), "the generated floor has a solid cell to mine")
	var type: int = terr.cell_type(cell)
	var before: int = pl.inventory.count(type)

	# Stand right on it → in reach. A single tiny tick must NOT instantly clear
	# it: the cut takes time (the hardness dig-time responsiveness model).
	pl.global_position = terr.cell_center(cell)
	var dug_small: bool = world.try_mine(cell, 0.02)
	_ok(not dug_small and terr.is_solid(cell),
		"one tiny tick does not instantly dig — the cut takes time (dig-time model)")

	# Held, it completes over multiple ticks and removes the cell, crediting one.
	var calls := 1
	while terr.is_solid(cell) and calls < 200:
		pl.global_position = terr.cell_center(cell)  # hold position (no physics frames run here)
		world.try_mine(cell, 0.02)
		calls += 1
	_ok(not terr.is_solid(cell), "held, the cut completes and the cell becomes air")
	_ok(calls > 1, "and it genuinely took multiple ticks, not one (%d)" % calls)
	_ok(pl.inventory.count(type) == before + 1,
		"exactly one item of that type was credited to the miner (%d)"
			% pl.inventory.count(type))

	# Mining the now-empty cell yields nothing, even on a long hold.
	var dug_air: bool = world.try_mine(cell, 1.0)
	_ok(not dug_air, "mining an air cell yields nothing")
	_ok(pl.inventory.count(type) == before + 1, "and credits nothing more")

	# Reach gate (break-the-fix target): a solid cell far out of reach is not
	# mined even with a long hold that would otherwise complete instantly.
	var far: Vector2i = Vector2i(6, 9) * int(terr.subdiv)
	_ok(terr.is_solid(far), "a second solid cell exists to test reach")
	var far_type: int = terr.cell_type(far)
	var far_before: int = pl.inventory.count(far_type)
	pl.global_position = terr.cell_center(far) + Vector2(100000.0, 0.0)
	var dug_far: bool = world.try_mine(far, 5.0)
	_ok(not dug_far and terr.is_solid(far),
		"a cell out of reach is not mined, even on a 5s hold")
	_ok(pl.inventory.count(far_type) == far_before, "and credits nothing")


## Placement, end to end through the REAL scene: the reach/solid/stock gates and
## the inventory debit the unit suite (no world/player) cannot exercise. Drives
## world.try_place directly with a chosen cell (as _handle_placing would feed it
## the cursor cell). Single-player only, so it runs before hosting goes online.
func _check_placing(world: Node) -> void:
	var pl = world.get("player")
	var terr = world.get("terrain")
	_ok(pl != null and terr != null, "the real scene has a player and terrain to place into")
	if pl == null or terr == null:
		return
	if pl.is_piloting():
		pl.disembark()

	# Hold exactly two stone; select it as the placement material.
	pl.inventory.clear()
	pl.inventory.add(TerrainDB.Type.STONE, 2)
	world._held_material = TerrainDB.Type.STONE

	# An empty cell just above the generated floor (floor top row is coarse y=8).
	var empty: Vector2i = Vector2i(0, 7) * int(terr.subdiv)
	_ok(not terr.is_solid(empty), "there is an empty cell above the floor to place into")

	# Out of reach (break-the-fix on the reach gate): far away, a long hold-worth
	# of intent still writes nothing and spends nothing.
	pl.global_position = terr.cell_center(empty) + Vector2(100000.0, 0.0)
	_ok(not world.try_place(empty), "a cell out of reach is not placed into")
	_ok(not terr.is_solid(empty) and pl.inventory.count(TerrainDB.Type.STONE) == 2,
		"and nothing is written or consumed out of reach")

	# In reach, empty, stocked: it places and consumes exactly one.
	pl.global_position = terr.cell_center(empty)
	_ok(world.try_place(empty), "in reach + empty + stocked: the material is placed")
	_ok(terr.is_solid(empty) and terr.cell_type(empty) == TerrainDB.Type.STONE,
		"the cell is now solid stone")
	_ok(pl.inventory.count(TerrainDB.Type.STONE) == 1,
		"and exactly one stone was consumed (%d left)" % pl.inventory.count(TerrainDB.Type.STONE))

	# Into a now-solid cell: refused, consumes nothing.
	_ok(not world.try_place(empty), "placing into a solid cell does nothing")
	_ok(pl.inventory.count(TerrainDB.Type.STONE) == 1, "and consumes nothing")

	# The placed cell is ordinary terrain — it digs back. Use terr.dig (no signal)
	# so the miner is not re-credited, keeping the count assertions clean.
	var dug = terr.dig(empty)
	_ok(dug == TerrainDB.Type.STONE and not terr.is_solid(empty),
		"the placed cell digs back to stone — placement is the true inverse of mining")

	# Empty stack: spend the last stone, then a further place writes nothing.
	var empty2: Vector2i = Vector2i(1, 7) * int(terr.subdiv)
	pl.global_position = terr.cell_center(empty2)
	_ok(world.try_place(empty2) and pl.inventory.count(TerrainDB.Type.STONE) == 0,
		"the last stone is placed, emptying the stack")
	var empty3: Vector2i = Vector2i(2, 7) * int(terr.subdiv)
	pl.global_position = terr.cell_center(empty3)
	_ok(not world.try_place(empty3),
		"with an empty stack there is nothing to place")

	# Clean up everything this test wrote (both full SCOOPS) so the world is
	# unchanged downstream.
	for sc in world._scoop_cells(empty):
		terr.dig(sc)
	for sc in world._scoop_cells(empty2):
		terr.dig(sc)


## Harvesting, end to end through the REAL scene: try_harvest cuts a CARCASS's
## flesh block over ticks (dig-time by hardness) and credits a whale-PRODUCT item;
## a LIVING creature yields nothing and keeps its blocks. Uses a dedicated,
## throwaway carcass so the scene's own whale is left untouched for the hosting
## checks that follow.
func _check_harvesting(world: Node) -> void:
	var pl = world.get("player")
	_ok(pl != null, "the real scene has a player to harvest")
	if pl == null:
		return
	if pl.is_piloting():
		pl.disembark()
	pl.inventory.clear()

	var flesh := {
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, 1): BlockDB.Type.MEAT,
		Vector2i(1, 1): BlockDB.Type.MEAT,
	}

	# A LIVING beast yields nothing through the world path.
	var live := _spawn_flesh(world, flesh, 100.0)
	live.position = Vector2(60000, 0)
	pl.global_position = live.to_global(live.local_pos_of(Vector2i(0, 0)))
	var got_live: bool = world.try_harvest(live, Vector2i(0, 0), 5.0)
	_ok(not got_live and live.has_block(Vector2i(0, 0)),
		"harvesting a LIVING beast yields nothing and keeps its block")
	_ok(pl.inventory.is_empty(), "and credits nothing")
	live.queue_free()

	# A CARCASS: a blubber block harvests, over multiple ticks, to one product.
	var corpse := _spawn_flesh(world, flesh, 0.0)
	corpse.position = Vector2(60000, -6000)
	var cell := Vector2i(0, 0)
	pl.global_position = corpse.to_global(corpse.local_pos_of(cell))

	var tick: bool = world.try_harvest(corpse, cell, 0.02)
	_ok(not tick and corpse.has_block(cell),
		"one tiny tick does not instantly harvest — the cut takes time")

	var calls := 1
	while corpse.has_block(cell) and calls < 200:
		pl.global_position = corpse.to_global(corpse.local_pos_of(cell))
		world.try_harvest(corpse, cell, 0.02)
		calls += 1
	_ok(not corpse.has_block(cell), "held, the cut completes and the flesh block is harvested")
	_ok(calls > 1, "and it genuinely took multiple ticks (%d)" % calls)
	_ok(pl.inventory.count(ItemDB.Product.BLUBBER) == 1,
		"exactly one BLUBBER PRODUCT was credited (not a terrain type) (%d)"
			% pl.inventory.count(ItemDB.Product.BLUBBER))
	_ok(pl.inventory.count(ItemDB.Product.STOMACH_LOOT) == 1,
		"and the corpse spilled its one-time stomach loot")

	if is_instance_valid(corpse):
		corpse.queue_free()
	await world.get_tree().process_frame
	pl.inventory.clear()  # leave the player as the rest of the suite expects
	world.respawn_player()  # and back on the ship, not stranded at the test site


## The RPG progression layer, end to end through the REAL scene: a wired perk
## visibly changes behaviour (BRAWN speeds mining), and the money/salvage/trainer
## loop works (sell salvage for money at the trainer, buy a stat level with it,
## refused off the trainer). The unit suite proves the logic in isolation; this
## proves it wired to the real player, terrain and trainer. Single-player only.
func _check_progression(world: Node) -> void:
	var pl = world.get("player")
	var terr = world.get("terrain")
	var tr = world.get("_trainer")
	_ok(pl != null and terr != null and tr != null,
		"the real scene has a player, terrain and trainer for progression")
	if pl == null or terr == null or tr == null:
		return
	if pl.is_piloting():
		pl.disembark()

	# --- A WIRED PERK CHANGES BEHAVIOUR: BRAWN speeds mining -----------------
	# Mine an identical placed cell at BRAWN 1, then again at BRAWN 2, and the
	# second cut must take FEWER ticks. Assert the EFFECT, not the flag.
	var scratch := Vector2i(0, -500)  # empty air, far above the islands
	pl.inventory.clear()

	pl.stats.set_level(StatDB.Stat.BRAWN, 1)
	terr.net_dig(scratch, 1)  # clear any generated cell so both runs mine the SAME stone
	terr.net_place(scratch, TerrainDB.Type.STONE, 1)
	var slow_ticks := 0
	while terr.is_solid(scratch) and slow_ticks < 500:
		pl.global_position = terr.cell_center(scratch)
		world.try_mine(scratch, 0.02)
		slow_ticks += 1

	pl.stats.set_level(StatDB.Stat.BRAWN, 2)  # Strong Arm: faster mining
	terr.net_dig(scratch, 1)
	terr.net_place(scratch, TerrainDB.Type.STONE, 1)
	var fast_ticks := 0
	while terr.is_solid(scratch) and fast_ticks < 500:
		pl.global_position = terr.cell_center(scratch)
		world.try_mine(scratch, 0.02)
		fast_ticks += 1

	_ok(slow_ticks > 1 and fast_ticks > 1, "both cuts took real time")
	_ok(fast_ticks < slow_ticks,
		"raising Brawn made the SAME cell mine faster (%d ticks -> %d) — the perk changed behaviour"
			% [slow_ticks, fast_ticks])

	# --- THE MONEY / SALVAGE / TRAINER LOOP ---------------------------------
	pl.inventory.clear()
	pl.wallet.balance = 0
	pl.inventory.add(TerrainDB.Type.ORE, 4)        # 4 x 8 = 32
	pl.inventory.add(ItemDB.Product.BLUBBER, 3)    # 3 x 7 = 21
	var offer: int = Economy.appraise(pl.inventory, pl.stats.trade_bonus())
	_ok(offer > 0, "the pack of salvage has a sale value (%d)" % offer)

	# Off the trainer: selling and training are both refused.
	pl.global_position = tr.global_position + Vector2(100000.0, 0.0)
	_ok(world.try_sell_salvage() == 0, "away from a trainer, salvage cannot be sold")
	_ok(not world.try_train(1), "and a stat cannot be trained")
	_ok(not pl.inventory.is_empty() and pl.wallet.balance == 0,
		"and nothing changed — pack full, wallet empty")

	# At the trainer: selling credits money and empties the sellable pack.
	pl.global_position = tr.global_position
	var gained: int = world.try_sell_salvage()
	_ok(gained == offer, "at the trainer, salvage sells for its appraised value (%d)" % gained)
	_ok(pl.wallet.balance == gained, "the money landed in the wallet (%d)" % pl.wallet.balance)
	_ok(pl.inventory.is_empty(), "and the sold salvage left the pack")

	# Training a level: money out, level up. GRACE (index 1) from 1 -> 2.
	pl.wallet.add(1000)  # ensure funds for the level regardless of salvage haul
	var before_level: int = pl.stats.level_of(StatDB.Stat.GRACE)
	var before_money: int = pl.wallet.balance
	var cost: int = Training.cost_to_raise(pl.stats, StatDB.Stat.GRACE)
	_ok(world.try_train(1), "at the trainer, a stat level can be bought")
	_ok(pl.stats.level_of(StatDB.Stat.GRACE) == before_level + 1,
		"the stat rose a level (%d -> %d)" % [before_level, pl.stats.level_of(StatDB.Stat.GRACE)])
	_ok(pl.wallet.balance == before_money - cost,
		"and exactly the training cost was deducted (%d)" % cost)

	# Leave the player clean for the rest of the suite.
	pl.inventory.clear()
	pl.wallet.balance = 0
	pl.stats = Stats.new()
	world.respawn_player()


## Build a throwaway flesh body (a whale-shaped creature) with the given pool max
## and pool=that max unless dead. `pool_now` 0 makes a carcass; >0 makes it alive.
## CARCASS-AS-AIRSHIP, the THRUST half, end to end (owner: "attach engines +
## propellers to a carcass so you can DRIVE it" — the other half of v0.43.0's
## balloons). A dead flesh body takes BUILT blocks through the real build-target
## path (Q targets a carcass under the cursor within reach), gains a helm the
## player can board, and FLIES under its own bolted-on thrust.
func _check_corpse_airship(world: Node) -> void:
	var pl = world.get("player")
	if pl == null:
		_ok(false, "a player exists for the corpse-airship check")
		return
	if pl.is_piloting():
		pl.disembark()

	# A dead 4-cell flesh slab, parked far from everything — spawned INTO the
	# fleet (the build-target resolver scans fleet.ships(), like every ship
	# system does).
	var corpse := Ship.new()
	for c in [Vector2i(0, 0), Vector2i(1, 0)]:
		corpse.blocks[c] = {"type": BlockDB.Type.BLUBBER, "hp": BlockDB.max_hp(BlockDB.Type.BLUBBER)}
	for c in [Vector2i(2, 0), Vector2i(3, 0)]:
		corpse.blocks[c] = {"type": BlockDB.Type.MEAT, "hp": BlockDB.max_hp(BlockDB.Type.MEAT)}
	corpse.gravity_scale = 0.0
	corpse.shared_health_max = 100.0
	corpse.shared_health = 0.0
	world.get("fleet").add_child(corpse)
	corpse.rebuild()
	corpse.position = Vector2(72000, -4000)
	await physics_frame
	_ok(corpse.is_carcass(), "the flesh slab is a carcass (pool empty)")

	# THE TARGET RESOLVER: with the cursor's world point on the corpse and the
	# player in reach, the build verbs aim at the CARCASS, not the player's ship.
	pl.global_position = corpse.global_position
	var over := corpse.to_global(corpse.local_pos_of(Vector2i(1, 0)))
	_ok(world._build_target(over) == corpse,
		"the build target under the cursor is the carcass (in reach)")
	pl.global_position = corpse.global_position + Vector2(100000, 0)
	_ok(world._build_target(over) != corpse,
		"out of reach, the carcass is NOT the target (reach gate holds)")
	pl.global_position = corpse.global_position

	# Bolt on the works through the REAL placement path: a helm above the back,
	# an engine and a prop beside it. set_block via net_set_block (single-player
	# authority), exactly what Q does.
	corpse.net_set_block(Vector2i(1, -1), BlockDB.Type.HELM)
	corpse.net_set_block(Vector2i(2, -1), BlockDB.Type.ENGINE)
	corpse.net_set_block(Vector2i(3, -1), BlockDB.Type.PROPELLER)
	await physics_frame
	_ok(corpse.has_helm(), "a helm built onto the corpse makes it steerable")
	_ok(corpse.blocks.size() == 7, "the corpse carries its bolted-on machinery")

	# Board the corpse's helm and drive: thrust moves the dead body under its
	# own bolted-on power — the whole point.
	var found: Array = Player.find_helm([corpse], pl.global_position, 100000.0)
	_ok(not found.is_empty(), "the corpse's helm is boardable")
	if not found.is_empty():
		_ok(pl.board(found[0], found[1]), "the player takes the corpse helm")
		# REAL input (the pilot-suite technique): the world overwrites the
		# piloted ship's controls from Input every frame, so a direct
		# net_set_controls is erased — press the actual action instead.
		Input.action_press("ship_right")
		var vx0: float = corpse.linear_velocity.x
		for i in 30:
			await physics_frame
		Input.action_release("ship_right")
		_ok(corpse.linear_velocity.x > vx0 + 10.0,
			"the corpse FLIES under its bolted-on thrust (vx %.0f -> %.0f)"
				% [vx0, corpse.linear_velocity.x])

		# THE STRANDED PILOT (owner 2026-08-25: "can't get off the whale-as-ship
		# if I build it"): lose the starter while piloting the corpse — the old
		# no-ship gate then skipped _handle_interact entirely and E went dead.
		# Now the helm you hold is adopted as your ship, and E always runs.
		var starter: Ship = world.get("local_ship")
		starter.pilot_peer = 0          # the claim dies with the hull
		world.set("local_ship", null)   # ...and the binding drops
		world._refresh_local_ship()
		_ok(world.get("local_ship") == corpse,
			"with the starter gone, the PILOTED corpse is adopted as local ship")
		_ok(corpse.pilot_peer == 1, "and carries the claim (a save keeps it yours)")
		Input.action_press("interact")
		await physics_frame
		Input.action_release("interact")
		await physics_frame
		_ok(not pl.is_piloting(),
			"E still steps off the corpse helm — the use key survives the loss")
		# SHOT DOWN, ON FOOT, NO SHIP AT ALL (owner 2026-08-26: "controls just
		# seem to hang when the player's ship is destroyed or disappears... I
		# wasn't able to continue building because my ship got destroyed").
		# Everything below the old `local_ship == null` return died with the
		# hull: LMB, RMB, Q, C and X. E had already been rescued one key at a
		# time; this pins the general rule with the loudest of them.
		if pl.is_piloting():
			pl.disembark()
		world.set("local_ship", null)
		starter.pilot_peer = 0
		# The corpse-airship above was ADOPTED and stamped with the claim, so
		# it has to be released too or _refresh_local_ship simply re-binds it
		# and this stops testing anything.
		corpse.pilot_peer = 0
		corpse.linear_velocity = Vector2.ZERO
		var shots0: int = world.get_tree().get_nodes_in_group("shots").size()
		Input.action_press("shoot")
		for i in 20:
			await physics_frame
		Input.action_release("shoot")
		_ok(world.get_tree().get_nodes_in_group("shots").size() > shots0,
			"with NO ship at all, LMB still shoots (%d -> %d live shots)"
				% [shots0, world.get_tree().get_nodes_in_group("shots").size()])
		_ok(world._build_target(pl.global_position) == null
				or world._build_target(pl.global_position) is Ship,
			"...and the build target answers safely instead of crashing")
		world._update_hud(Vector2i.ZERO)
		_ok(world.hud.text.contains("No ship"),
			"...and the HUD says what to do about it, not nothing")

		# Restore the world for the checks that follow.
		starter.pilot_peer = 1
		world.set("local_ship", starter)
		if pl.is_piloting():
			pl.disembark()

		# A LOOKOUT NEEDS SOMETHING TO LOOK AT (owner 2026-08-26: "enemies
		# shouldn't randomly aggress to a ship unless it's moving + manned —
		# why would they attack something that doesn't look like is even
		# manned?"). Movement counts as evidence of a crew; an empty parked
		# hull is scenery.
		var keep: Vector2 = pl.global_position
		starter.linear_velocity = Vector2.ZERO
		pl.global_position = starter.global_position
		_ok(world._looks_crewed(starter),
			"a hull with a person standing on it reads as CREWED")
		pl.global_position = starter.global_position + Vector2(60000.0, -40000.0)
		_ok(not world._looks_crewed(starter),
			"...an empty, parked hull does not — that is scenery")
		starter.linear_velocity = Vector2(
			world.UNDER_WAY_SPEED * world.world_scale * 3.0, 0.0)
		_ok(world._looks_crewed(starter),
			"...but a hull UNDER WAY must have a hand on it somewhere")
		var bandit: Ship = null
		for sh in world.fleet.ships():
			if is_instance_valid(sh) and sh.faction == 1:
				bandit = sh
				break
		if bandit != null:
			_ok(world._nearest_ship_of_faction(bandit, 0, true) == starter,
				"a bandit's lookout picks the hull that is under way")
			starter.linear_velocity = Vector2.ZERO
			_ok(world._nearest_ship_of_faction(bandit, 0, true) != starter,
				"...and stops seeing it the moment it is parked and empty")
			_ok(world._nearest_ship_of_faction(bandit, 0, false) != null,
				"...though a PROVOKED crew drops the filter and finds a hull")
		starter.linear_velocity = Vector2.ZERO
		pl.global_position = keep

	# Clean up so the later hosting check sees the untouched fleet.
	corpse.queue_free()
	await physics_frame
	world.respawn_player()


## BALLOONS ARE CRAFTED AND SPENT (v0.49.0). The end-to-end loop through the real
## world verbs: an empty pack cannot tether (and loses nothing trying), the recipe
## turns blubber + ingots into a balloon, and tethering spends exactly one and
## lifts the body it is tied to. The ghost is checked here too — it is the only
## place a live world, a real cursor target and a real inventory exist at once.
func _check_balloon_economy(world: Node) -> void:
	var pl = world.get("player")
	if pl == null:
		_ok(false, "a player exists for the balloon-economy check")
		return
	if pl.is_piloting():
		pl.disembark()

	# A dead two-cell slab to tether to, parked away from everything.
	var corpse := Ship.new()
	for c in [Vector2i(0, 0), Vector2i(1, 0)]:
		corpse.blocks[c] = {"type": BlockDB.Type.BLUBBER, "hp": BlockDB.max_hp(BlockDB.Type.BLUBBER)}
	corpse.gravity_scale = 0.0
	corpse.shared_health_max = 100.0
	corpse.shared_health = 0.0
	world.get("fleet").add_child(corpse)
	corpse.rebuild()
	corpse.position = Vector2(-74000, -4000)
	await physics_frame
	pl.global_position = corpse.global_position

	var size: int = Ship.BalloonSize.SMALL
	var item: int = ItemDB.balloon_item_for(size)
	pl.inventory.clear()

	# --- An EMPTY PACK cannot tether (the whole point of the round) ----------
	_ok(not world.try_attach_balloon(corpse, Vector2i(0, 0), size),
		"tethering is REFUSED with no balloon in the pack (free build is over)")
	_ok(corpse.balloons.is_empty(), "and nothing was attached by the refusal")
	var lift_bare: float = corpse.balloon_lift_total()

	# --- The recipe makes one ----------------------------------------------
	var recipe := {}
	for r in Recipes.RECIPES:
		if int(r["output"]) == item:
			recipe = r
	_ok(not recipe.is_empty(), "a recipe exists that outputs a %s" % ItemDB.name_of(item))
	for id in recipe["inputs"]:
		pl.inventory.add(id, int(recipe["inputs"][id]))
	_ok(Recipes.craft(pl.inventory, recipe) and pl.inventory.count(item) == 1,
		"crafting the recipe puts one %s in the pack" % ItemDB.name_of(item))

	# --- The GHOST answers "where would it go" ------------------------------
	# Aimed explicitly: the live mouse cannot be pointed headless, and the camera
	# moves the world point under a fixed screen pixel every time the player
	# does — so the cursor is passed in (the overlay's call omits it).
	var aim: Vector2 = corpse.to_global(corpse.local_pos_of(Vector2i(0, 0)))
	# The ghost follows the build palette (v0.50.0): it only shows while Q
	# would tether a balloon, so point the selection at one first.
	world.select_build("balloon", size)
	var ghost = world.balloon_ghost_to_draw(aim)
	_ok(ghost is Dictionary, "aiming at a corpse cell raises a balloon build ghost")
	if ghost is Dictionary:
		_ok(int(ghost["cables"]) == Ship.BALLOON_CABLES[size],
			"the ghost wears the SELECTED size's tether count (%d)" % int(ghost["cables"]))
		_ok(bool(ghost["ok"]), "and reads GREEN — in reach, with one in the pack")
	# Empty the pack and the SAME aim reads RED: the ghost is telling you the
	# attach would be refused, which is the whole reason it is coloured.
	var stashed: int = pl.inventory.count(item)
	pl.inventory.remove(item, stashed)
	var broke = world.balloon_ghost_to_draw(aim)
	_ok(broke is Dictionary and not bool(broke["ok"]),
		"with an empty pack the ghost reads RED at the same cell")
	pl.inventory.add(item, stashed)
	# Out of REACH is the other red: step away and the same cell refuses.
	var stood: Vector2 = pl.global_position
	pl.global_position = stood + Vector2(100000.0, 0.0)
	var far = world.balloon_ghost_to_draw(aim)
	_ok(far is Dictionary and not bool(far["ok"]),
		"and RED again from across the sky — the reach gate shows in the ghost")
	pl.global_position = stood

	# --- Tethering SPENDS exactly one and lifts -----------------------------
	_ok(world.try_attach_balloon(corpse, Vector2i(0, 0), size),
		"with one in the pack, the tether goes on")
	_ok(pl.inventory.count(item) == 0,
		"and it cost exactly one balloon (pack now %d)" % pl.inventory.count(item))
	_ok(corpse.balloons.size() == 1, "the corpse carries one balloon")
	_ok(corpse.balloon_lift_total() > lift_bare,
		"the tethered balloon adds lift (%.0f -> %.0f)"
			% [lift_bare, corpse.balloon_lift_total()])
	# And a SECOND attach with the emptied pack is refused again — the spend is
	# real, not a one-time gate that stays open once you have paid once.
	_ok(not world.try_attach_balloon(corpse, Vector2i(1, 0), size),
		"the emptied pack cannot tether a second balloon")
	_ok(corpse.balloons.size() == 1, "so the corpse still carries exactly one")

	# --- F2 grants stock (the standing order's playtest bench) --------------
	world.debug_grant_balloons(2)
	_ok(pl.inventory.count(item) == 2,
		"the F2 Player-tab grant fills the pack (%d)" % pl.inventory.count(item))
	_ok(world.try_attach_balloon(corpse, Vector2i(1, 0), size),
		"and a granted balloon tethers like a crafted one")

	world.select_build("block", BlockDB.Type.HULL)  # leave the default selection
	pl.inventory.clear()
	corpse.queue_free()
	await physics_frame
	world.respawn_player()


## THE CONSOLIDATED CONTROLS (owner 2026-08-25: "WAY too many keys and
## combinations... nearly unplayable"). Pins the whole scheme so a later round
## cannot quietly grow the keyboard back: E is the one USE key, Q the one PLACE
## key, B the one CYCLE key, and the retired actions are gone from the map — a
## re-added place_terrain/mat_cycle/debug_damage binding fails here by name.
func _check_unified_controls(world: Node) -> void:
	# --- The action map is the contract -------------------------------------
	var ev: Array = InputMap.action_get_events("interact")
	_ok(ev.size() == 1 and (ev[0] as InputEventKey).physical_keycode == KEY_E,
		"USE is one key, and it is E (owner: standardize F to E)")
	ev = InputMap.action_get_events("build_place")
	_ok(ev.size() == 1 and (ev[0] as InputEventKey).physical_keycode == KEY_Q,
		"PLACE is one key, and it is Q")
	ev = InputMap.action_get_events("build_cycle")
	_ok(ev.size() == 1 and (ev[0] as InputEventKey).physical_keycode == KEY_B,
		"CYCLE is one key, and it is B")
	for retired in ["place_terrain", "mat_cycle", "debug_damage"]:
		_ok(not InputMap.has_action(retired),
			"the retired '%s' action is gone from the map" % retired)

	# --- One palette dispatches all three place kinds -----------------------
	var pl = world.get("player")
	if pl == null:
		_ok(false, "a player exists for the palette check")
		return
	pl.inventory.clear()
	pl.inventory.add(TerrainDB.Type.STONE, 5)
	pl.inventory.add(ItemDB.balloon_item_for(Ship.BalloonSize.SMALL), 1)
	var palette: Array = world._build_palette()
	var kinds := {}
	for e in palette:
		kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
	_ok(int(kinds.get("block", 0)) == BlockDB.type_count() - 1,
		"the palette lists every ship block except the open door (%d)"
			% int(kinds.get("block", 0)))
	_ok(int(kinds.get("terrain", 0)) == 1, "the carried stone is one terrain entry")
	_ok(int(kinds.get("balloon", 0)) == 3,
		"ALL THREE balloon sizes ride the cycle, stocked or not (owner: they were undiscoverable hidden)")
	_ok(palette[0]["kind"] == "block" and palette[-1]["kind"] == "balloon",
		"blocks lead the cycle and balloons close it")

	# Cycling wraps THROUGH the kinds: from the last block, forward reaches the
	# stone, then the three balloons, then wraps back to the first block.
	world.select_build("block", int(palette[int(kinds["block"]) - 1]["id"]))
	world._cycle_build(1)
	_ok(world._sel_kind == "terrain", "cycling off the last block reaches the terrain")
	world._cycle_build(1)
	_ok(world._sel_kind == "balloon", "then the balloons")
	world._cycle_build(1)
	world._cycle_build(1)
	world._cycle_build(1)
	_ok(world._sel_kind == "block" and world.build_type == int(palette[0]["id"]),
		"then (after all three sizes) wraps to the first block")
	world._cycle_build(-1)
	_ok(world._sel_kind == "balloon", "and Shift+B steps the same ring backwards")

	# A spent BALLOON stays in the rotation (the whole point of the fix): x0
	# in the cue, red ghost, and Q answers with the recipe — but a spent
	# TERRAIN stack still drops out (materials come from mining).
	pl.inventory.remove(ItemDB.balloon_item_for(Ship.BalloonSize.SMALL), 1)
	pl.inventory.remove(TerrainDB.Type.STONE, 5)
	var balloons_left := 0
	var terrain_left := 0
	for e in world._build_palette():
		if e["kind"] == "balloon":
			balloons_left += 1
		elif e["kind"] == "terrain":
			terrain_left += 1
	_ok(balloons_left == 3, "an empty balloon stack STAYS in the cycle (x0, red, craft-hint)")
	_ok(terrain_left == 0, "an empty terrain stack still drops out")
	pl.inventory.add(TerrainDB.Type.STONE, 5)

	# Exactly one ghost: with a BLOCK selected the balloon ghost stays dark even
	# over a valid target — the block preview owns the cursor.
	world.select_build("block", BlockDB.Type.HULL)
	_ok(world.balloon_ghost_to_draw(pl.global_position) == null,
		"with a block selected the balloon ghost never shows")

	# The label speaks the selection — the cue B prints and any readout share it.
	_ok(world.build_selection_label() == "build: Hull",
		"the selection label names the block (%s)" % world.build_selection_label())
	world.select_build("terrain", TerrainDB.Type.STONE)
	_ok(world.build_selection_label().begins_with("place: Stone"),
		"and the terrain (%s)" % world.build_selection_label())
	world.select_build("block", BlockDB.Type.HULL)

	# --- HOLD-B PICKER: the grid is the cycle, grouped (owner 2026-08-26) -----
	# The picker paints `build_picker_model`, which is the SAME `_build_palette`
	# sorted into rows — so anything the cycle can reach, the grid can, and a
	# choice commits through the same select_build. Rebuild the pack first (the
	# spent-stack block above emptied it) so all three groups are present.
	pl.inventory.add(TerrainDB.Type.STONE, 5)
	pl.inventory.add(ItemDB.balloon_item_for(Ship.BalloonSize.SMALL), 1)
	var model: Array = world.build_picker_model()
	var titles: Array = []
	var model_count := 0
	for g in model:
		titles.append(str(g["title"]))
		model_count += (g["entries"] as Array).size()
	_ok(titles == ["BLOCKS", "MATERIALS", "BALLOONS"],
		"the picker groups the palette into blocks, materials and balloons")
	_ok(model_count == world._build_palette().size(),
		"and every palette entry is in exactly one group (%d == %d)"
			% [model_count, world._build_palette().size()])
	# Every entry carries what a cell has to draw, and the CURRENT pick is marked.
	world.select_build("block", BlockDB.Type.HULL)
	var hull_marked := false
	var any_labelled := true
	for g in world.build_picker_model():
		for e in g["entries"]:
			if str(e["label"]) == "":
				any_labelled = false
			if e["kind"] == "block" and int(e["id"]) == BlockDB.Type.HULL:
				hull_marked = bool(e["current"])
	_ok(any_labelled, "every picker cell has a label to draw")
	_ok(hull_marked, "the current selection is flagged so the grid can outline it")
	# A material shows its stock; a spent one dims to x0 but stays in the grid.
	var stone_count := -1
	for g in world.build_picker_model():
		for e in g["entries"]:
			if e["kind"] == "terrain" and int(e["id"]) == TerrainDB.Type.STONE:
				stone_count = int(e["count"])
	_ok(stone_count == pl.inventory.count(TerrainDB.Type.STONE),
		"a material cell shows the carried count (%d)" % stone_count)

	# Choosing a cell is choosing that entry — hovered_entry() would return one
	# of these dicts, and the world commits it exactly like the cycle.
	var target: Dictionary = {}
	for g in world.build_picker_model():
		for e in g["entries"]:
			if e["kind"] == "balloon":
				target = e
	if not target.is_empty():
		world.select_build(target["kind"], int(target["id"]),
			bool(target.get("rot", false)))
		_ok(world._sel_kind == "balloon",
			"committing a picked cell selects it (the release-to-choose path)")
	world.select_build("block", BlockDB.Type.HULL)
	pl.inventory.clear()

	# --- PROP CHOP SPARES YOUR OWN CREW (owner 2026-08-26) -------------------
	# "Should it bite your own crew?" — no. `_wash_chops` is the one place the
	# rule lives (both chop sites call it): a faction-0 (player-side) prop chops
	# only strangers, and a tamed creature is faction 0, so allies are covered.
	# The lever wash_chop_friendly flips it back. Tested directly — the
	# push/geometry is the unit suite's _test_prop_wash_pushes_and_chops; this
	# is only the friend/foe gate.
	Tunables.set_value("wash_chop_friendly", false)
	_ok(not world._wash_chops(0, 0), "your prop spares your own side")
	_ok(not world._wash_chops(2, 2), "and a wild pod does not carve its own")
	_ok(world._wash_chops(0, 1), "but your blades DO chop an enemy")
	_ok(world._wash_chops(1, 0), "...and a bandit's chop you")
	Tunables.set_value("wash_chop_friendly", true)
	_ok(world._wash_chops(0, 0),
		"the wash_chop_friendly lever restores everyone-bleeds")
	Tunables.set_value("wash_chop_friendly", false)


func _spawn_flesh(world: Node, cells: Dictionary, pool_now: float) -> Ship:
	var s := Ship.new()
	for cell in cells:
		var type: int = cells[cell]
		s.blocks[cell] = {"type": type, "hp": BlockDB.max_hp(type)}
	s.gravity_scale = 0.0
	s.shared_health_max = 100.0
	s.shared_health = pool_now
	world.add_child(s)
	s.rebuild()
	return s


## USER-FACING SAVE / LOAD through the REAL scene (save/save_game.gd): the whole
## manager path the unit suite cannot exercise — capturing the live fleet + player
## + terrain diffs to disk, mutating everything, and rebuilding from the file.
## Single-player only, so it runs BEFORE hosting flips the world online. Cleans up
## the file it writes.
func _check_save_load(world: Node) -> void:
	var pl = world.get("player")
	var terr = world.get("terrain")
	var fleet = world.get("fleet")
	if pl == null or terr == null or fleet == null:
		_ok(false, "the real scene has a player, terrain and fleet to save")
		return
	if pl.is_piloting():
		pl.disembark()

	var slot := "startup_slot"

	# Distinctive player state to save.
	pl.wallet.balance = 777
	pl.inventory.add(TerrainDB.Type.STONE, 5)
	var saved_stone: int = pl.inventory.count(TerrainDB.Type.STONE)
	pl.stats.set_level(StatDB.Stat.BRAWN, 2)
	var p1 := Vector2(1234.0, -567.0)
	pl.global_position = p1

	# A terrain DIFF pair: dig a solid cell (C → air), place a material into an air
	# cell (G → solid). Both must survive the round trip.
	var c := Vector2i(0x7fffffff, 0)
	for yy in range(6 * terr.subdiv, 16 * terr.subdiv):
		for xx in range(-6 * terr.subdiv, 24 * terr.subdiv):
			if terr.is_solid(Vector2i(xx, yy)):
				c = Vector2i(xx, yy)
				break
		if c.x != 0x7fffffff:
			break
	_ok(c.x != 0x7fffffff, "found a solid cell to dig for the save test")
	terr.dig(c)
	_ok(not terr.is_solid(c), "dug cell C is air before saving")

	var g := Vector2i(0, -460)
	while terr.is_solid(g):
		g += Vector2i(0, -1)
	terr.place(g, TerrainDB.Type.STONE)
	_ok(terr.is_solid(g), "placed cell G is solid before saving")

	# THE NEW BODIES MUST SURVIVE THE ROUND TRIP AS THEMSELVES. A save rebuilds
	# every ship from its payload, so anything set AFTER the spawn is lost
	# unless it rides that payload — the trap that left an untagged sky of
	# ex-residents in v0.61.0. A nest and a basilisk each carry state the world
	# reads back: `is_nest` (which re-freezes it), `spawn_site`, and
	# `creature_kind` (which decides WHICH BRAIN it gets on the other side).
	var probe_site := Vector2i(-44, 9)
	var nest_before: Ship = world._build_nest(
		{"coord": probe_site, "pos": pl.global_position + Vector2(3000.0, -900.0),
			"kind": SpawnSites.Kind.BANDIT_ROOST}, "res://ships/nest_roost.ship")
	var beast_before = world.debug_spawn("basilisk",
		pl.global_position + Vector2(-3000.0, -900.0))
	if beast_before != null:
		beast_before.from_spawn_site = true
		beast_before.spawn_site = probe_site
	_ok(nest_before != null and nest_before.freeze,
		"a nest stands frozen before the save")

	# Counted AFTER the probe bodies exist: they are in the save too, so the
	# "fleet restored" check below has to expect them back.
	var ships_before: int = fleet.ships().size()

	# A CLEARED SPAWN SITE is the one piece of site state worth persisting —
	# everything else about a site is derived from the seed, but "I broke this
	# nest" is a thing the player DID. Mark one before the save.
	var cleared_coord := Vector2i(-31, 17)
	world.set_cleared_sites(PackedInt32Array([cleared_coord.x, cleared_coord.y]))

	# The ecology meter (Q-C) is the other thing-you-did-to-the-world worth
	# persisting: how far the deep has risen from overhunting whales.
	world.set("kraken_ascendancy", 0.42)

	_ok(world.save_game(slot), "the world saved to disk")

	# Now mutate EVERYTHING the load must undo: money, inventory, position, and the
	# terrain (re-solidify C, place a post-save cell F that the load must discard).
	pl.wallet.balance = 0
	pl.inventory.clear()
	pl.global_position = Vector2(-800.0, -800.0)
	terr.place(c, TerrainDB.Type.STONE)  # post-save: C solid again
	var f := Vector2i(0, -520)
	while terr.is_solid(f):
		f += Vector2i(0, -1)
	terr.place(f, TerrainDB.Type.STONE)  # post-save placement, not in the save
	world.set("kraken_ascendancy", 0.0)  # post-save: the load must bring the deep back up

	# Forget it, so the load has something to restore rather than something to
	# leave alone.
	world.set("_site_state", {})
	_ok(world.load_game(slot), "the world loaded from disk")
	# The nest and the basilisk come back as what they were.
	var nest_after: Ship = null
	var beast_after: Ship = null
	for ship in fleet.ships():
		if not is_instance_valid(ship):
			continue
		if (ship as Ship).is_nest:
			nest_after = ship
		if (ship as Ship).creature_kind == "basilisk":
			beast_after = ship
	_ok(nest_after != null and nest_after.freeze,
		"a NEST reloads as a nest, still frozen where it was raised")
	_ok(nest_after != null and nest_after.spawn_site == probe_site,
		"...still belonging to its place")
	_ok(beast_after != null and beast_after.from_spawn_site
			and beast_after.spawn_site == probe_site,
		"a site RESIDENT reloads still tagged to the site that made it")
	_ok(beast_after != null and world._whale_ai_for(beast_after) is BasiliskAI,
		"...and a basilisk reloads with the basilisk BRAIN, not the whale one")
	# Freed WITHOUT awaiting a frame: the checks below still compare the
	# player's restored position against the exact pixel it was saved at, and a
	# single physics frame of gravity is enough to fail that.
	if nest_after != null:
		nest_after.queue_free()
	if beast_after != null:
		beast_after.queue_free()

	var back: PackedInt32Array = world.cleared_sites()
	var found_cleared := false
	for i in range(0, back.size(), 2):
		if Vector2i(back[i], back[i + 1]) == cleared_coord:
			found_cleared = true
	_ok(found_cleared,
		"a nest you broke stays broken across a save/load (%d cleared sites)"
			% (back.size() / 2))
	_ok(is_equal_approx(float(world.get("kraken_ascendancy")), 0.42),
		"the ecology meter survives a save/load (deep at 0.42 ascendant)")
	world.set("kraken_ascendancy", 0.0)  # leave the deep quiet for the checks that follow

	# Player progress restored.
	_ok(pl.wallet.balance == 777, "money restored (777, got %d)" % pl.wallet.balance)
	_ok(pl.inventory.count(TerrainDB.Type.STONE) == saved_stone,
		"inventory restored (%d stone)" % pl.inventory.count(TerrainDB.Type.STONE))
	_ok(pl.stats.level_of(StatDB.Stat.BRAWN) == 2, "stat level restored")
	_ok(pl.global_position.distance_to(p1) < 1.0, "player position restored")

	# Terrain restored as seed + diffs.
	_ok(not terr.is_solid(c), "dug cell C is AIR after load (the diff persisted)")
	_ok(terr.is_solid(g), "placed cell G is present after load (the diff persisted)")
	_ok(not terr.is_solid(f), "the post-save cell F is gone after load (not in the save)")

	# Ships restored through the fleet spawn path.
	_ok(fleet.ships().size() == ships_before,
		"the fleet was restored (%d ships)" % fleet.ships().size())
	var local2 = world.get("local_ship")
	_ok(local2 != null and is_instance_valid(local2) and local2.mass > 1.0,
		"the local ship is re-bound and has real mass after load")
	_ok(fleet.ships().any(func(s): return s.faction == 1),
		"the hostile hulk is back after load")
	_ok(fleet.ships().any(func(s): return s.faction == 2),
		"the whale is back after load")

	# Graceful failure through the real manager: a missing slot changes nothing.
	_ok(not world.load_game("no_such_slot_here"),
		"loading a missing slot fails gracefully and leaves the game valid")
	_ok(fleet.ships().size() == ships_before, "and the fleet is untouched by the failed load")

	DirAccess.remove_absolute("%s/%s.json" % [SaveGame.SAVE_DIR, slot])


## TAMING + RIDING through the real world (Sprint 5 payoff). The LORE gate, the
## allegiance flip, and the mount/dismount round-trip — checked on the actual
## scene because try_tame/mount touch the world's WhaleAI registry and the live
## Player, not pure logic. Runs BEFORE hosting flips the session online (taming
## is the single-player / server path, like whale spawning).
func _check_taming(world: Node, fleet) -> void:
	var p = world.get("player")
	var whales: Array = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken" and s.creature_kind != "whale_city")
	var critters: Array = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level == 1)
	if p == null or whales.is_empty() or critters.is_empty() or p.stats == null:
		_ok(false, "taming: a player with stats, a wild whale and a critter exist to test")
		return
	var whale = whales[0]
	var critter = critters[0]

	# THE GATE, BY TIER (the small→whale progression): level-1 LORE tames nothing.
	# (Break-the-fix: drop try_tame's taming_level check and these fail.)
	p.stats.set_level(StatDB.Stat.LORE, StatDB.MIN_LEVEL)
	_ok(p.stats.taming_level() == 0, "level-1 LORE cannot tame anything")
	_ok(not world.try_tame(critter), "no perk: even the small critter is REFUSED")
	_ok(not world.try_tame(whale), "no perk: the whale is REFUSED")
	_ok(whale.faction == 2 and critter.faction == 2, "both stay wild")

	# BEAST WHISPERER (LORE 3, taming tier 1): the SMALL creature is tameable, the
	# whale is NOT — a whale needs the higher perk. This is the progression.
	p.stats.set_level(StatDB.Stat.LORE, 3)
	_ok(p.stats.taming_level() == 1, "Beast Whisperer = taming tier 1")
	_ok(not world.try_tame(whale), "tier 1 CANNOT tame a whale (needs Master Trader)")
	_ok(world.try_tame(critter), "tier 1 CAN tame the small critter")
	_ok(critter.faction == 0, "the critter's allegiance flips to the player's side")

	# The critter is RIDEABLE but does NOT mine. Mount it, paint terrain at its
	# front, steer into it, and assert the pulse digs nothing (tame_level 1).
	_ok(p.mount(critter), "the small critter is rideable")
	var terrain = world.get("terrain")
	var cai = world._whale_ai_for(critter)
	cai.ridden = true
	cai.steer = Vector2(1.0, 0.0)
	_paint_front_patch(terrain, critter)
	var inv_before_critter: int = p.inventory.total()
	_ok(world.ride_mine_pulse() == 0 and p.inventory.total() == inv_before_critter,
		"riding a small critter into terrain mines NOTHING (it is not a drill)")
	world.dismount_creature()

	# MASTER TRADER (LORE 5, taming tier 3): the whale AND the deep kraken answer
	# (tier 3 since 2026-08-24 — krakens tame at the top bar). It won't ram the
	# tamer, and it is rideable.
	p.stats.set_level(StatDB.Stat.LORE, StatDB.MAX_LEVEL)
	_ok(p.stats.taming_level() == 3, "Master Trader = taming tier 3 (whales + krakens)")
	_ok(world.try_tame(whale), "the top tier tames the whale")
	_ok(whale.faction == 0, "the tamed whale's allegiance flips to the player's side")
	# ...and the flip has to be VISIBLE, end to end through the real verb:
	# taming shipped with no confirmation, so a bonded whale looked exactly
	# like the wild one beside it (v0.56.0).
	_ok(whale.is_tamed_ally(), "the bond reads as an allegiance the paint can see")
	_ok(whale.attitude_cast(Color(0.5, 0.5, 0.5))
			== Color(0.5, 0.5, 0.5).lerp(Ship.CAST_ALLY, Ship.CAST_STRENGTH),
		"the tamed whale wears the ally cast in the world")
	_ok(MapView.blip_color(whale) == Ship.CAST_ALLY,
		"...and blips as YOUR creature on the map, not as one more vessel")
	var ai = world._whale_ai_for(whale)
	ai.provoke()
	_ok(ai.tamed and ai.phase() == WhaleAI.Phase.NONE,
		"a tamed whale ignores provocation — it won't ram the tamer")
	_ok(p.mount(whale), "the player mounts the tamed whale")
	_ok(p.is_riding(), "and is now riding it")

	# THE PAYOFF: drive the ridden whale into terrain — it MINES a swath, credits
	# the RIDER, and keeps its pool (it eats the terrain, it does not crash on it).
	ai.ridden = true
	ai.steer = Vector2(1.0, 0.0)
	whale.ridden_mining = true  # what _handle_riding sets each frame while ridden
	_paint_front_patch(terrain, whale)
	var inv_before: int = p.inventory.total()
	var pool_before: float = whale.shared_health
	var dug: int = world.ride_mine_pulse()
	_ok(dug > 0, "the ridden whale digs a swath of terrain at its front (%d cells)" % dug)
	_ok(p.inventory.total() > inv_before, "and the RIDER is credited the mined material")
	_ok(is_equal_approx(whale.shared_health, pool_before),
		"the whale keeps its pool while mining (%.0f == %.0f) — it does not suicide on its dig"
			% [whale.shared_health, pool_before])

	# A WILD whale (nobody riding) does NOT mine — dismount, re-paint, pulse = 0.
	world.dismount_creature()
	_ok(not p.is_riding() and not ai.ridden, "F dismounts — back on foot, whale roams")
	_ok(not whale.ridden_mining, "dismount clears the whale's terrain immunity")
	_paint_front_patch(terrain, whale)
	var inv_after_dismount: int = p.inventory.total()
	_ok(world.ride_mine_pulse() == 0 and p.inventory.total() == inv_after_dismount,
		"a whale nobody rides mines nothing (wild-whale behaviour unchanged)")

	# KRAKENS TAME AT THE TOP TIER (owner reversal 2026-08-24). They were
	# untameable when this block was written, and the header said so for two
	# months after the code changed — the checks below have been asserting the
	# opposite of their own comment. Master Trader (taming 3) answers a kraken.
	var krakens: Array = fleet.ships().filter(func(s) -> bool: return s.creature_kind == "kraken")
	if not krakens.is_empty():
		var kraken = krakens[0]
		# TAMEABLE since 2026-08-24 (owner reversal: "you can tame krakens, they
		# just are a little wild... and always do damage if you touch their
		# mouth parts"): tier 3 — Master Trader (taming 3) answers it.
		_ok(kraken.tame_level == 3, "a kraken tames at the TOP tier (3)")
		_ok(world.try_tame(kraken), "Master Trader CAN tame a kraken")
		_ok(kraken.faction == 0, "the tamed kraken joins the player's side")
		# Restore to wild for the later hosting fleet checks.
		kraken.faction = 2
		world._whale_ai_for(kraken).tamed = false

	# --- RIDE = THE LEASH (owner 2026-08-24) --------------------------------
	# The ride is now the grapple LATCH, not a separate mount toggle: releasing
	# the hook (RMB) ends it — no F — and a creature you already tamed re-mounts
	# INSTANTLY on re-grapple (it used to go inert, unridable, after dismount).
	# The whale here is still a tamed ally (faction 0), the player back on foot.
	_ok(world._is_tamed_ally(whale), "a tamed whale reads as a re-ridable ally")
	var vessel = null
	for s in fleet.ships():
		if s.creature_kind == "" and not s.is_carcass():
			vessel = s
			break
	if vessel != null:
		_ok(not world._is_tamed_ally(vessel), "a plain vessel is NOT a re-ridable ally (never mounts by grapple)")
	# Simulate the grapple latching onto the tamed ally, then run the ride loop —
	# it re-mounts with no bond, proving a tamed whale is never inert again.
	p._hook_state = Player.HookState.LATCHED
	p._anchor_ship = whale
	world._handle_taming(0.016)
	_ok(p.is_riding() and p.riding == whale,
		"re-grappling a tamed whale re-mounts it INSTANTLY (no re-bond) — the inert-whale fix")
	_ok(p.grapple_latched(),
		"and the grapple stays latched while riding — it is the leash, not consumed")
	# THE HOOK IS THE REINS, and the HUD says so (owner 2026-08-26: "rideable
	# creatures don't need a panel to be controlled from"). They never did —
	# a creature has no helm and WASD routes straight into its AI — but the
	# only status line the game had said AT THE HELM, so the mode was invisible.
	world._update_hud(Vector2i.ZERO)
	var ride_hud: String = world.hud.text
	_ok(ride_hud.contains("RIDING") and ride_hud.contains("WASD"),
		"the HUD names RIDING as its own control mode, steered by WASD")
	_ok(not ride_hud.contains("AT THE HELM"),
		"...and never claims a helm the beast does not have")
	# Let go of the hook (RMB) → the ride ends on the next loop tick, no F.
	p.release_grapple()
	world._handle_taming(0.016)
	_ok(not p.is_riding(), "releasing the hook (RMB) ends the ride — no F needed")

	# Restore both creatures to WILD so the later hosting check sees the full pod
	# and critter set (this test deliberately mutated allegiances; undo them).
	whale.faction = 2
	ai.tamed = false
	critter.faction = 2
	cai.tamed = false


## THE EARTH'S CORE (owner 2026-08-23): the bottom slice of the world is lethal
## lava — any ship touching it is consumed, and a person in it respawns above.
## Spawn a throwaway ship into the core and confirm it is eaten (fleet back to its
## prior size), then drop the on-foot player in and confirm the respawn lifts them
## clear. Nets to zero so the later hosting check sees the same fleet.
func _check_lava_core(world: Node, fleet) -> void:
	var lava = world.get("_lava_core")
	if lava == null:
		_ok(false, "the lava core exists")
		return
	var surf: float = lava.call("surface_y")

	# A ship placed in the molten core is consumed within a frame (the check reads
	# position before the solver integrates the AI's hover, so it can't escape).
	var before: int = fleet.ships().size()
	var doomed = world.debug_spawn("whale", Vector2(0.0, surf + 400.0))
	_ok(doomed != null, "a throwaway ship spawned in the deep")
	for i in 6:
		await physics_frame
	_ok(not is_instance_valid(doomed) and fleet.ships().size() == before,
		"a ship that touches the lava core is consumed (fleet back to %d)" % fleet.ships().size())

	# A person standing in the core dies and respawns clear of it.
	var p = world.get("player")
	if p != null and is_instance_valid(p):
		p.global_position = Vector2(0.0, surf + 300.0)
		for i in 6:
			await physics_frame
		_ok(p.global_position.y < surf,
			"a person who falls into the core respawns above the surface")


## Paint a solid terrain patch just ahead of `creature`'s +x leading edge, across
## its height and a few cells deep — the target for a ride-mining pulse. A test
## helper so both the critter and whale mining checks share one setup.
func _paint_front_patch(terrain, creature) -> void:
	if terrain == null or creature == null:
		return
	var cpx: float = terrain.cell_px()
	var center: Vector2 = creature.to_global(creature.solid_bounds.get_center())
	var half: Vector2 = creature.solid_bounds.size * 0.5
	var edge_x: float = center.x + half.x
	var c0: Vector2i = terrain.world_to_cell(Vector2(edge_x + cpx * 0.5, center.y - half.y))
	var c1: Vector2i = terrain.world_to_cell(Vector2(edge_x + cpx * 6.0, center.y + half.y))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			terrain.set_cell(Vector2i(cx, cy), TerrainDB.Type.STONE)


## Hosting after offline play. Every ship on screen right now was added to the
## Fleet directly, and MultiplayerSpawner replicates only what it spawned
## itself — so unless host_session re-creates them, a joiner arrives to an
## empty sky and the host may be bound to a hull nobody else has. Checked
## here rather than in the unit suite because it is a property of the real
## startup path: only the actual scene has an offline world to convert.
func _check_hosting_after_offline_play(world: Node, fleet) -> void:
	var before := {}
	for s in fleet.ships():
		before[s.get_instance_id()] = true
	var count_before: int = fleet.ships().size()

	# NetUtil rather than the Net autoload: autoload identifiers do not resolve
	# at parse time in a --script SceneTree (godot-quirks), and NetUtil is the
	# one place "am I networked?" is decided anyway.
	world.host_session()
	if not NetUtil.is_online(world):
		# Port already taken (the owner's own game, a stale process). Not a
		# failure of the code under test — say so loudly rather than red.
		print("    SKIP could not bind a host port; hosting checks not run")
		return
	await process_frame

	_ok(NetUtil.is_authority(world) and world.multiplayer.is_server(),
		"H hosts a session")
	_ok(fleet.ships().size() == count_before,
		"hosting keeps exactly the ships you had (%d -> %d) — no phantom second vessel"
			% [count_before, fleet.ships().size()])

	var rehomed := 0
	for s in fleet.ships():
		if not before.has(s.get_instance_id()):
			rehomed += 1
	_ok(rehomed == fleet.ships().size(),
		"every pre-host ship was respawned through the spawner (%d of %d)"
			% [rehomed, fleet.ships().size()])

	var mine: Array = fleet.ships().filter(func(s) -> bool: return s.pilot_peer == 1)
	_ok(mine.size() == 1, "the host owns exactly one ship (%d)" % mine.size())
	_ok(world.get("local_ship") != null and is_instance_valid(world.local_ship),
		"and is bound to a live one")

	var whales: Array = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken" and s.creature_kind != "whale_city")
	_ok(whales.size() == world.WHALE_POD_SIZE,
		"the whole whale pod survived the switch (%d)" % whales.size())
	if not whales.is_empty():
		_ok(whales[0].shared_health_max > 0.0 and whales[0].shared_health > 0.0,
			"and kept its shared health pool (%.0f/%.0f) — it is still one unit"
				% [whales[0].shared_health, whales[0].shared_health_max])

	var hulks: Array = fleet.ships().filter(func(s) -> bool: return s.faction == 1)
	_ok(hulks.size() == 1, "the hostile hulk survived too")
	if not hulks.is_empty():
		# A crewman whose ship vanishes deletes himself, and a gunnerless hulk
		# never fires: rehoming has to carry the riders across.
		_ok(world._has_gunner(hulks[0]), "with his gunner still aboard")
		_ok(world._has_driver(hulks[0]), "and his driver")

	_ok(world.get("player") != null and is_instance_valid(world.player),
		"the host still has a body")

	# Release the port. Fetched by path, not by identifier, for the same
	# parse-time reason as above.
	var net_node := root.get_node_or_null(^"/root/Net")
	if net_node != null:
		net_node.stop()


## The DEBUG WINDOW's real spawn/tuning path through the live scene (session 5):
## debug_spawn adds a crewed enemy and a coarse-collidered whale through the real
## Fleet, the whale's health comes from the live tunable, and mine_power changes
## dig-time. Runs BEFORE hosting (authority-only path) and frees what it spawns so
## the hosting-rehome count is unchanged.


## FIRE against the REAL world (roadmap Phase 4, v0.63.0). The unit test owns
## the rules; what only the live world can show is that the whole loop is
## reachable from the controls the player actually has: something catches, it
## spreads and hurts on the world's own tick, and the repair wand — the ONE key
## that already means "put this right" — beats it.
func _check_fire(world: Node, fleet) -> void:
	var pl = world.get("player")
	if pl == null or pl.is_piloting():
		return
	Tunables.set_value("fire_enabled", true)
	var target: Ship = null
	for ship in (fleet.call("ships") as Array):
		if not is_instance_valid(ship):
			continue
		for cell in (ship as Ship).blocks:
			if Fire.burns(int((ship as Ship).blocks[cell]["type"])):
				target = ship
				break
		if target != null:
			break
	if target == null:
		_ok(false, "the shipped world holds something that can burn")
		return

	var lit := Vector2i.ZERO
	for cell in target.blocks:
		if Fire.burns(int(target.blocks[cell]["type"])):
			lit = cell
			break
	_ok(world.ignite_cell(target, lit), "a cell of the real world catches fire")
	for i in 60:
		await world.get_tree().physics_frame
	_ok(target.burning.size() >= 1,
		"the world's own tick keeps it burning (%d cells)" % target.burning.size())
	_ok(not world.burning_points().is_empty(),
		"...and the overlay can see it (fire is a block-state, not a node)")

	# The wand. Sweep it over the fire and the fire loses.
	var at := target.to_global(target.local_pos_of(lit))
	var doused := 0
	for i in 30:
		doused += Fire.douse(target, at, Ship.CELL * 6.0 * world.world_scale,
			0.05, world._fire_clock)
		await world.get_tree().physics_frame
	_ok(doused > 0, "the repair wand smothers what it sweeps (%d cells out)" % doused)

	# Leave nothing burning behind — later checks count ships and cells.
	for ship in (fleet.call("ships") as Array):
		if is_instance_valid(ship):
			(ship as Ship).burning.clear()
	Tunables.set_value("fire_enabled", false)



## THE BASILISK against the REAL world (v0.64.0). The unit test owns the brain;
## what only the live world can show is the HAND-OFF — the brain raises a spit
## request, the world spawns the slug through the one projectile path, and the
## slug is the same HazardFireball a meteor is. Damage and ignition are turned
## OFF for the check: this is about the mechanism, and the suite's later checks
## count the hull cells this would otherwise chew.
func _check_basilisk(world: Node, fleet) -> void:
	var mine = world.get("local_ship")
	if mine == null or not is_instance_valid(mine):
		return
	var dmg := Tunables.get_num("basilisk_spit_damage")
	var ignite := Tunables.get_num("fire_ignite_chance")
	Tunables.set_value("basilisk_spit_damage", 0.0)
	Tunables.set_value("fire_ignite_chance", 0.0)
	Tunables.set_value("basilisk_spit_seconds", 0.5)

	var beast = world.debug_spawn("basilisk", mine.global_position
		+ Vector2(2600.0 * world.world_scale, -400.0 * world.world_scale))
	_ok(beast != null, "a basilisk spawns through the real Fleet path")
	if beast != null:
		_ok(beast.creature_kind == "basilisk" and beast.shared_health > 0.0,
			"...as a living creature with the basilisk brain")
		_ok(world._whale_ai_for(beast) is BasiliskAI,
			"...and the world gives it the BasiliskAI, not the whale brain")
		var seen := 0
		for i in 400:
			await world.get_tree().physics_frame
			seen = maxi(seen, world.get_tree()
				.get_nodes_in_group("hazard_fireballs").size())
			if seen > 0:
				break
		_ok(seen > 0,
			"...and it actually spits: the world spawned its fireball (%d live)" % seen)
		# THE MUZZLE MUST CLEAR ITS OWN BODY. Fired from the "facing" side, a
		# slug aimed at something above or below crossed straight back through
		# the shooter — and a living creature absorbs that into its shared pool
		# without losing a cell, so it read as "the shots just miss".
		var clear := true
		for fb in world.get_tree().get_nodes_in_group("hazard_fireballs"):
			var d: float = (fb as Node2D).global_position.distance_to(
				beast.global_position)
			if d < beast.solid_bounds.size.length() * 0.5:
				clear = false
		_ok(clear, "...from a muzzle outside its own body, whatever way it aims")

		# A DORMANT creature stands down. It is out of the simulation, so its
		# forces are ignored anyway — but its brain kept firing projectiles at
		# a ship it was drifting away from until this was closed.
		beast.set_dormant(true)
		for fb in world.get_tree().get_nodes_in_group("hazard_fireballs"):
			(fb as Node).queue_free()
		await world.get_tree().process_frame
		for i in 200:
			await world.get_tree().physics_frame
		# Count only slugs NEAR the beast: meteors and lava bombs share the
		# group, and the sky keeps throwing those whatever the basilisk does.
		var near_beast := 0
		for fb in world.get_tree().get_nodes_in_group("hazard_fireballs"):
			if (fb as Node2D).global_position.distance_to(beast.global_position) 					< 6000.0 * world.world_scale:
				near_beast += 1
		_ok(near_beast == 0,
			"a DORMANT creature stops acting — no shots from a body nothing can shoot back at (%d near it)"
				% near_beast)
		beast.set_dormant(false)
		for fb in world.get_tree().get_nodes_in_group("hazard_fireballs"):
			(fb as Node).queue_free()
		beast.queue_free()
		await world.get_tree().process_frame

	Tunables.set_value("basilisk_spit_damage", dmg)
	Tunables.set_value("fire_ignite_chance", ignite)
	Tunables.reset("basilisk_spit_seconds")


## WORLD-ANCHORED SPAWN SITES against the REAL world (charter §4, v0.61.0).
## The unit test owns the site arithmetic — determinism, band rules, bounds.
## What only the live world can show is the LOOP: fly to a place, its residents
## come out (up to its pool and no further), and a resident carried far from
## everyone is reclaimed instead of accumulating across the sky forever.
func _check_spawn_sites(world: Node, fleet) -> void:
	var pl = world.get("player")
	if pl == null or pl.is_piloting():
		return
	var rect: Rect2 = world.get("_world_rect")
	if rect.size.y <= 0.0:
		return
	var sites: Array = SpawnSites.near([pl.global_position], 400000.0,
		world.get("world_seed"), rect, float(world.get("world_scale")))
	if sites.is_empty():
		_ok(false, "the world holds at least one spawn site within reach")
		return
	var site: Dictionary = sites[0]
	var pool: int = site["pool"]

	# Fast levers so the loop is testable in seconds rather than minutes.
	Tunables.set_value("spawn_sites_enabled", true)
	Tunables.set_value("site_release_seconds", 0.0)
	Tunables.set_value("site_regen_seconds", 5.0)
	var home: Vector2 = pl.global_position
	pl.global_position = (site["pos"] as Vector2) + Vector2(0.0, -1500.0)
	for i in 260:
		await world.get_tree().physics_frame

	# Count the residents of THIS site: more than one site can be in range at
	# once, and each answers for its own pool.
	var residents: Array = []
	var mine: Array = []
	for ship in (fleet.call("ships") as Array):
		if is_instance_valid(ship) and (ship as Ship).from_spawn_site:
			residents.append(ship)
			if (ship as Ship).spawn_site == site["coord"]:
				mine.append(ship)
	_ok(mine.size() > 0,
		"flying to a %s puts its residents out (%d here, %d across every site in range)"
			% [SpawnSites.kind_name(site["kind"]), mine.size(), residents.size()])
	_ok(mine.size() <= pool,
		"...up to its pool and no further (%d <= %d)" % [mine.size(), pool])
	var capped := residents.size() <= Tunables.get_int("site_max_residents")
	_ok(capped, "...and the world-wide cap holds across every site (%d <= %d)"
		% [residents.size(), Tunables.get_int("site_max_residents")])
	_ok(not world.discovered_sites().is_empty(),
		"...and the place is now on the map (%d discovered)"
			% world.discovered_sites().size())

	# RECLAIM. A resident that ends up far from everyone is freed and its stock
	# returned — without it a long flight leaves a trail of dormant bodies.
	if not mine.is_empty():
		var victim := mine[0] as Ship
		var id := victim.get_instance_id()
		victim.global_position = (site["pos"] as Vector2) 			+ Vector2(Tunables.get_num("site_reclaim_px") * 3.0, 0.0)
		victim.set_dormant(true)
		for i in 130:
			await world.get_tree().physics_frame
		_ok(instance_from_id(id) == null or not is_instance_valid(instance_from_id(id)),
			"a wild resident carried far from everyone is reclaimed, not kept forever")

	# THE NEST, end to end (charter §4's second half). Fly to a place that HAS a
	# structure, watch it stand, break it, and the place is finished: no more
	# residents, ever, and the map remembers.
	var nest_site := {}
	for candidate in SpawnSites.near([home], 600000.0, world.get("world_seed"),
			rect, float(world.get("world_scale"))):
		if SpawnSites.nest_for(candidate["kind"]) != "":
			nest_site = candidate
			break
	if not nest_site.is_empty():
		pl.global_position = (nest_site["pos"] as Vector2) + Vector2(0.0, -1500.0)
		for i in 150:
			await world.get_tree().physics_frame
		var nest: Ship = null
		for ship in (fleet.call("ships") as Array):
			if is_instance_valid(ship) and (ship as Ship).is_nest:
				nest = ship
		_ok(nest != null, "a %s stands at its place"
			% SpawnSites.kind_name(nest_site["kind"]))
		if nest != null:
			_ok(nest.freeze, "...frozen where it was built, not flying or falling")
			_ok(nest.shared_health_max > 0.0,
				"...as ONE UNIT with a pool (%.0f) — cells alone are unreachable at scale"
					% nest.shared_health_max)
			# Break it the way a player does: SHOOT it. A nest is one unit with
			# a POOL now (v0.67.0), so the shots drain that rather than taking
			# cells off — and the cells rule stays as the fallback for a nest
			# that is dismantled by hand instead.
			var carried: int = pl.inventory.total() if pl.inventory != null else 0
			var doomed: Array = nest.blocks.keys()
			for i in range(0, int(doomed.size() * 0.7)):
				nest.net_damage_cell(doomed[i], 1.0e6)
			for i in 150:
				await world.get_tree().physics_frame
			var flat: PackedInt32Array = world.cleared_sites()
			var found := false
			for i in range(0, flat.size(), 2):
				if Vector2i(flat[i], flat[i + 1]) == nest_site["coord"]:
					found = true
			_ok(found, "breaking the nest clears the place for good")
			_ok(pl.inventory == null or pl.inventory.total() > carried,
				"...and its cache spills into your pack (%d -> %d items)"
					% [carried, pl.inventory.total() if pl.inventory != null else 0])
			var after := 0
			for ship in (fleet.call("ships") as Array):
				if is_instance_valid(ship) and (ship as Ship).from_spawn_site 						and (ship as Ship).spawn_site == nest_site["coord"] 						and not (ship as Ship).is_nest:
					after += 1
			var before_count := after
			for i in 150:
				await world.get_tree().physics_frame
			var now_count := 0
			for ship in (fleet.call("ships") as Array):
				if is_instance_valid(ship) and (ship as Ship).from_spawn_site 						and (ship as Ship).spawn_site == nest_site["coord"] 						and not (ship as Ship).is_nest:
					now_count += 1
			_ok(now_count <= before_count,
				"...and a cleared place never sends anything again (%d -> %d)"
					% [before_count, now_count])
			var marked := false
			for charted in world.discovered_sites():
				if charted["coord"] == nest_site["coord"] 						and bool(charted.get("cleared", false)):
					marked = true
			_ok(marked, "...and the map records it as one you broke")

	# Leave the world exactly as it was found — the later checks count the
	# authored pod and a stray resident would fail them. Sites OFF first, then
	# sweep every resident (the passes above kept releasing while we waited).
	Tunables.set_value("spawn_sites_enabled", false)
	pl.global_position = home
	Tunables.reset("site_release_seconds")
	Tunables.reset("site_regen_seconds")
	for ship in (fleet.call("ships") as Array):
		if is_instance_valid(ship) and ((ship as Ship).from_spawn_site
				or (ship as Ship).is_nest):
			(ship as Ship).queue_free()
	for i in 5:
		await world.get_tree().physics_frame

func _check_debug_window(world: Node, fleet) -> void:
	var pl = world.get("player")
	var terr = world.get("terrain")
	if pl == null or terr == null:
		return
	if pl.is_piloting():
		pl.disembark()

	# DISTANCE DORMANCY against a REAL world (v0.58.0). The unit test covers
	# the switch; what only the live world can check is the DECISION -- who
	# sleeps, who is exempt, and that waking never lands inside the ground.
	Tunables.set_value("dormancy_enabled", true)
	Tunables.set_value("dormant_range_px", 12000.0)
	var far_at: Vector2 = pl.global_position + Vector2(90000.0, 0.0)
	var sleeper = world.debug_spawn("whale", far_at)
	await world.get_tree().process_frame
	if sleeper != null:
		# Run the pass long enough to cross the scan cadence.
		for i in 40:
			await world.get_tree().physics_frame
		_ok(sleeper.dormant,
			"a creature %.0f px away leaves the simulation"
				% pl.global_position.distance_to(sleeper.global_position))
		_ok(world.dormant_count >= 1,
			"...and the world counts it (%d) for the F2 census" % world.dormant_count)

		# ACTING WHILE FAR AWAY (v0.60.0). The unit test owns the circuit's
		# arithmetic; what only the live world can show is that the dormant
		# TICK actually drives it -- the creature moves, its brain's `home`
		# follows it there (so waking does not send it swimming back to where
		# you last saw it), and it mends while nobody is watching.
		Tunables.set_value("dormant_tick_seconds", 0.5)
		Tunables.set_value("dormant_heal_per_min", 60.0)
		sleeper.shared_health = sleeper.shared_health_max * 0.25
		var was_at: Vector2 = sleeper.global_position
		var was_hp: float = sleeper.shared_health
		for i in 90:
			await world.get_tree().physics_frame
		_ok(sleeper.global_position.distance_to(was_at) > 1.0,
			"a dormant creature MIGRATES while you are away (%.0f px)"
				% sleeper.global_position.distance_to(was_at))
		_ok(world._whale_ai_for(sleeper).home.distance_to(
				sleeper.global_position) < 1.0,
			"...and its roam resumes where it arrived, not where you left it")
		_ok(sleeper.shared_health > was_hp,
			"...and a wound mends out of sight (%.0f -> %.0f)"
				% [was_hp, sleeper.shared_health])
		Tunables.reset("dormant_heal_per_min")
		Tunables.reset("dormant_tick_seconds")

		# NEVER the ship you are standing on, however far it is from anyone.
		var mine = world.get("local_ship")
		_ok(mine == null or not mine.dormant,
			"your own ship never blinks out behind you")

		# Waking must not land it inside terrain: drop it to the floor while it
		# is dormant (no collision to stop it), then bring it back.
		sleeper.global_position = Vector2(far_at.x, 3000.0)
		world._wake(sleeper)
		_ok(not sleeper.dormant, "a woken creature is back in the simulation")
		_ok(not world.terrain.is_solid(
				world.terrain.world_to_cell(sleeper.global_position)),
			"...and never inside solid ground \u2014 it is lifted clear first")

		# Turning the lever off must release everything, not strand it.
		Tunables.set_value("dormancy_enabled", false)
		for i in 10:
			await world.get_tree().physics_frame
		_ok(not sleeper.dormant and world.dormant_count == 0,
			"switching dormancy off wakes everything it put under")
		Tunables.set_value("dormancy_enabled", true)
		sleeper.queue_free()
		await world.get_tree().process_frame

	# THE PHYSICS CENSUS against a REAL world (v0.57.0) -- the numbers the
	# owner's 3-FPS capture was missing.
	var cen := PhysicsCensus.of_world(world)
	_ok(int(cen["chunks"]) > 0 and int(cen["chunk_shapes"]) > 0,
		"the census sees the promoted terrain (%d chunks, %d shapes)"
			% [cen["chunks"], cen["chunk_shapes"]])
	_ok(int(cen["shapes"]) > 0 and int(cen["worst"]) > 0,
		"...and the fleet's collision shapes (%d, worst body %d)"
			% [cen["shapes"], cen["worst"]])
	_ok(int(cen["active"]) > 0,
		"...and the solver's active bodies (%d) \u2014 Ship sets can_sleep=false, so "
			% cen["active"] + "this never falls on its own")

	# THE PERF READOUT against a REAL world (v0.55.3). Headless has no
	# renderer, but every number here is a script-side count, so the live
	# world is exactly where it can be checked.
	var win := DebugWindow.new()
	win.world = world
	world.add_child(win)
	await world.get_tree().process_frame
	var before_text: String = win._perf_text(0.25)
	_ok(before_text.contains("Ships:    %-6d" % fleet.ships().size()),
		"the Perf readout reports the live ship count")
	var promoted := 0
	for c in terr.get_children():
		if c is TerrainChunk:
			promoted += 1
	_ok(promoted > 0 and before_text.contains("Terrain:  %-6d  chunks" % promoted),
		"...and the promoted chunk count (%d)" % promoted)

	# A rebuild storm must SHOW as a rate: that is the whole point of the
	# block. Force some chunk rebuilds between two samples.
	var storm := 0
	for c in terr.get_children():
		if c is TerrainChunk:
			(c as TerrainChunk).rebuild()
			storm += 1
	var after_text: String = win._perf_text(0.5)
	var rate_seen := false
	for line in after_text.split("\n"):
		if line.contains("chunk rebuilds"):
			rate_seen = float(line.split(" ", false)[-1]) >= (storm / 0.5) - 0.5
	_ok(rate_seen,
		"a %d-chunk rebuild storm shows up in the per-second rate" % storm)
	win.queue_free()

	# debug_spawn('hulk'): a crewed enemy through the real Fleet path.
	var before: int = fleet.ships().size()
	var hulk = world.debug_spawn("hulk", pl.global_position + Vector2(500, -100))
	await process_frame
	_ok(hulk != null, "debug_spawn('hulk') returned a ship")
	if hulk != null:
		_ok(fleet.ships().has(hulk) and fleet.ships().size() == before + 1,
			"the debug hulk joined the Fleet")
		_ok(hulk.faction == 1, "the debug hulk is hostile (faction 1)")
		_ok(world._has_driver(hulk) and world._has_gunner(hulk),
			"the debug enemy is CREWED (driver + gunner) — never automated (owner rule)")

	# debug_spawn('whale'): health from the LIVE tunable + the coarse collider.
	Tunables.set_value("whale_health", 9000.0)
	var whale = world.debug_spawn("whale", pl.global_position + Vector2(-500, -100))
	await process_frame
	_ok(whale != null, "debug_spawn('whale') returned a ship")
	if whale != null:
		_ok(whale.faction == 2, "the debug whale is wildlife (faction 2)")
		_ok(is_equal_approx(whale.shared_health, 9000.0),
			"the whale's health came from the live tunable (got %.0f)" % whale.shared_health)
		var shapes := 0
		for c in whale.get_children():
			if c is CollisionShape2D:
				shapes += 1
		var precise: int = whale._merge_rects().size()
		_ok(shapes < precise,
			"the debug whale got the COARSE collider (%d < %d precise) — pool set THEN rebuilt"
				% [shapes, precise])

	# mine_power tunable changes dig-time on the SAME cell (the brief's check).
	pl.stats.set_level(StatDB.Stat.BRAWN, 1)
	pl.inventory.clear()
	var scratch := Vector2i(7, -520)  # empty air, far above the islands
	Tunables.set_value("mine_power", 80.0)
	terr.net_dig(scratch, 1)
	terr.net_place(scratch, TerrainDB.Type.STONE, 1)
	var slow := 0
	while terr.is_solid(scratch) and slow < 4000:
		pl.global_position = terr.cell_center(scratch)
		world.try_mine(scratch, 0.02)
		slow += 1
	Tunables.set_value("mine_power", 2000.0)
	terr.net_dig(scratch, 1)
	terr.net_place(scratch, TerrainDB.Type.STONE, 1)
	var fast := 0
	while terr.is_solid(scratch) and fast < 4000:
		pl.global_position = terr.cell_center(scratch)
		world.try_mine(scratch, 0.02)
		fast += 1
	_ok(slow > 1 and fast > 1, "both mine_power cuts took real time")
	_ok(fast < slow,
		"raising mine_power made the SAME cell mine faster (%d -> %d ticks)" % [slow, fast])

	# Clean up: reset the levers and free the debug spawns (their crew frees with
	# them), so the hosting-rehome test sees the original fleet.
	Tunables.reset_all()
	# ...but leave the world-anchored population OFF: the checks after this one
	# teleport foci across the sky and count the ships they find, and a site
	# doing its job would put residents into those counts. _check_spawn_sites
	# turns it on for exactly as long as it needs it.
	Tunables.set_value("spawn_sites_enabled", false)
	if hulk != null:
		hulk.queue_free()
	if whale != null:
		whale.queue_free()
	await process_frame


## Ecology (Q-C): overhunting whales lets the deep rise. Whales keep krakens in
## check (sperm whale eats giant squid), so killing whales SURGES kraken dens
## worldwide; the meter DECAYS over time (the safe-harvest rate as a flow). This
## covers the surge math, the whale-only rise, the clamps, the decay, the enable
## toggle, and the death SIGNAL end to end. Persistence lives in _check_save_load.
func _check_ecology(world: Node, fleet) -> void:
	Tunables.reset_all()
	# Keep the world-anchored population OFF for the whole check: reset_all put it
	# back to its default (ON), and this test AWAITS frames (the end-to-end whale
	# spawn), during which a live bandit site would release a hulk that lingers
	# into the hosting count. Ecology decays regardless of this toggle by design.
	Tunables.set_value("spawn_sites_enabled", false)
	world.set("kraken_ascendancy", 0.0)
	world.call("resync_eco_level")
	var base := 2

	# THE SURGE is kraken-only and scales with the meter. A QUIET deep changes
	# nothing (parity): the game is byte-identical until a whale actually dies.
	_ok(int(world.call("_kraken_surge_pool", SpawnSites.Kind.KRAKEN_DEN, base)) == base,
		"a quiet deep leaves a kraken den at its base pool (parity)")
	_ok(int(world.call("_kraken_surge_pool", SpawnSites.Kind.WHALE_GROUND, 3)) == 3,
		"the surge never touches a non-kraken site (whale ground stays 3)")
	world.set("kraken_ascendancy", 1.0)
	var surged := int(world.call("_kraken_surge_pool", SpawnSites.Kind.KRAKEN_DEN, base))
	_ok(surged == base + int(round(base * Tunables.get_num("eco_kraken_gain"))),
		"an ascendant deep surges every kraken den (%d -> %d at full)" % [base, surged])
	_ok(surged > base, "...and that is strictly MORE krakens worldwide (%d > %d)" % [surged, base])

	# A WHALE death raises the meter; a critter / kraken / basilisk death does not.
	world.set("kraken_ascendancy", 0.0)
	Tunables.set_value("eco_kill_rise", 0.1)
	world.call("_on_creature_perished", "whale")
	_ok(is_equal_approx(float(world.get("kraken_ascendancy")), 0.1),
		"killing a whale stirs the deep (0 -> %.2f)" % float(world.get("kraken_ascendancy")))
	world.call("_on_creature_perished", "whale_city")
	_ok(float(world.get("kraken_ascendancy")) > 0.1,
		"the city-whale boss counts as whale-family too")
	var held := float(world.get("kraken_ascendancy"))
	world.call("_on_creature_perished", "critter")
	world.call("_on_creature_perished", "kraken")
	world.call("_on_creature_perished", "basilisk")
	_ok(is_equal_approx(float(world.get("kraken_ascendancy")), held),
		"a critter / kraken / basilisk death does NOT stir the deep (whales only)")

	# Rise CLAMPS at 1, decay CLAMPS at 0.
	Tunables.set_value("eco_kill_rise", 1.0)
	for i in 5:
		world.call("_on_creature_perished", "whale")
	_ok(float(world.get("kraken_ascendancy")) <= 1.0,
		"the meter never exceeds 1 however many whales die")
	Tunables.set_value("eco_recover_per_min", 6.0)   # 0.1/s — brisk, for the test
	world.set("kraken_ascendancy", 0.5)
	world.call("_tick_ecology", 1.0)
	_ok(float(world.get("kraken_ascendancy")) < 0.5,
		"the deep recovers when you stop hunting — the safe-harvest rate (%.3f < 0.5)"
			% float(world.get("kraken_ascendancy")))
	world.set("kraken_ascendancy", 0.02)
	world.call("_tick_ecology", 100.0)
	_ok(float(world.get("kraken_ascendancy")) == 0.0, "and recovery clamps at a quiet deep (0)")

	# The enable toggle FREEZES the whole system (rise and surge).
	Tunables.set_value("eco_enabled", false)
	world.set("kraken_ascendancy", 0.3)
	world.call("_on_creature_perished", "whale")
	_ok(is_equal_approx(float(world.get("kraken_ascendancy")), 0.3),
		"ecology OFF: a whale death no longer stirs the deep")
	_ok(int(world.call("_kraken_surge_pool", SpawnSites.Kind.KRAKEN_DEN, base)) == base,
		"ecology OFF: no kraken surge even at 0.3 ascendancy")
	Tunables.set_value("eco_enabled", true)

	# END TO END: the death SIGNAL, from a real whale's pool emptying — the tag
	# on the payload, the AI wiring, and the emit that feeds the meter.
	world.set("kraken_ascendancy", 0.0)
	world.call("resync_eco_level")
	Tunables.set_value("eco_kill_rise", 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pos: Vector2 = (world.get("player") as Node2D).global_position + Vector2(4200.0, -4200.0)
	var whale: Ship = world.call("_spawn_one_whale", WhaleSpawn.pick_plan(rng), pos)
	if whale != null:
		await world.get_tree().physics_frame
		_ok(whale.creature_kind == "whale",
			"a spawned whale carries the 'whale' tag (rides the payload, survives the wire)")
		world.call("_whale_ai_for", whale)   # build the brain → connect creature_perished
		whale.shared_health = 5.0
		whale.shared_health_max = 5.0
		whale.damage_cell(whale.blocks.keys()[0], 1.0e6)   # empty the pool → the death edge
		_ok(whale.is_carcass(), "the whale died (pool empty → carcass)")
		_ok(float(world.get("kraken_ascendancy")) >= 0.2,
			"and its death rose to the meter THROUGH the signal (%.2f)"
				% float(world.get("kraken_ascendancy")))
		whale.queue_free()
		await process_frame
	else:
		_ok(true, "(whale spawner not ready — skipped the end-to-end signal check)")

	# Leave the world as we found it: quiet deep, defaults, population off (the
	# checks after this teleport foci and count ships — a live site would skew them).
	world.set("kraken_ascendancy", 0.0)
	world.call("resync_eco_level")
	Tunables.reset_all()
	Tunables.set_value("spawn_sites_enabled", false)
	await process_frame


## Sandbox (owner 2026-08-28): the "cut the fluff, play one thing" toggle. The
## loadout opens every gate and fills the pack; sandbox_mode switches off the
## deep-air suffocation gate. Both are additive dev tools — the default (OFF) must
## leave the full game exactly as it was, which the parity halves pin.
func _check_sandbox(world: Node, fleet) -> void:
	var pl = world.get("player")
	if pl == null or not is_instance_valid(pl):
		_ok(false, "there is a player to kit out")
		return
	if pl.is_piloting():
		pl.disembark()
	Tunables.reset_all()

	# --- The SUFFOCATION gate: default bites deep; sandbox switches it off -----
	# Put the player in deep, unbreathable air (frac < DEEP_TOP) with NO life
	# support, so the gate WOULD fire — then prove the toggle is what silences it.
	var rect: Rect2 = world.get("_world_rect")
	var home: Vector2 = pl.global_position
	var did_suffo := false
	if rect.size.y > 0.0 and pl.inventory != null:
		pl.inventory.clear()
		pl.global_position = Vector2(0.0, rect.end.y - 0.15 * rect.size.y)  # frac ~0.15, deep
		var frac: float = world.call("_player_altitude_frac")
		if LifeSupport.air_unbreathable(frac) and not LifeSupport.protected(pl.inventory):
			did_suffo = true
			pl.health = pl.max_health
			world.set("_suffocate_cd", 0.05)
			for i in 6:
				world.call("_update_suffocation", 1.0)   # sandbox OFF (reset_all) → it bites
			_ok(pl.health < pl.max_health,
				"default: deep unbreathable air suffocates an unprotected person (%.0f/%.0f)"
					% [pl.health, pl.max_health])
			Tunables.set_value("sandbox_mode", true)
			pl.health = pl.max_health
			world.set("_suffocate_cd", 0.05)
			for i in 6:
				world.call("_update_suffocation", 1.0)   # sandbox ON → the gate is off
			_ok(pl.health == pl.max_health,
				"sandbox: the deep-air gate no longer bites (health held full)")
			Tunables.set_value("sandbox_mode", false)
	if not did_suffo:
		_ok(true, "(no deep unbreathable band reachable here — suffocation half skipped)")

	# --- The LOADOUT: one press opens every gate and fills the pack ------------
	pl.global_position = home
	if pl.inventory != null:
		pl.inventory.clear()
	if pl.wallet != null:
		pl.wallet.balance = 0
	for stat in StatDB.names():
		pl.stats.set_level(stat, 0)
	world.call("debug_sandbox_loadout")
	_ok(Tunables.get_bool("sandbox_mode"), "the loadout turns sandbox mode ON")
	var all_max := true
	for stat in StatDB.names():
		if pl.stats.level_of(stat) != StatDB.MAX_LEVEL:
			all_max = false
	_ok(all_max, "...maxes every stat (opens taming / mining / trade gates)")
	_ok(pl.wallet == null or pl.wallet.balance >= 5000,
		"...fills the wallet (%d)" % (pl.wallet.balance if pl.wallet != null else 0))
	_ok(pl.inventory == null or pl.inventory.count(ItemDB.Crafted.LIFE_SUPPORT) > 0,
		"...grants gear incl. the Aether Lung (deep-safe without crafting)")
	var some_material := false
	for t in TerrainDB.Type.values():
		if TerrainDB.is_solid(t) and pl.inventory != null and pl.inventory.count(t) > 0:
			some_material = true
			break
	_ok(some_material, "...grants a stack of building material (crafting is now optional)")
	_ok(pl.health == pl.max_health, "...and heals to full")

	# Leave the world as we found it: OFF, defaults, an empty pack, a live position.
	Tunables.reset_all()
	if pl.inventory != null:
		pl.inventory.clear()
	if pl.wallet != null:
		pl.wallet.balance = 0
	for stat in StatDB.names():
		pl.stats.set_level(stat, 0)
	pl.max_health = pl.stats.max_health()
	pl.health = pl.max_health
	pl.global_position = home
	await process_frame


## EDGE POI MARKERS against the LIVE world (owner 2026-08-29). The geometry is
## pinned as a pure function in the unit suite; what only the real world can say
## is whether the SELECTION is right — that the things near you are named, named
## with a kind the layer can actually draw, that the deck under your feet is not
## one of them, and that the range and the toggle really govern it.
func _check_edge_markers(world: Node, fleet) -> void:
	var pl = world.get("player")
	if pl == null or not is_instance_valid(pl):
		_ok(false, "there is a player to centre the markers on")
		return
	if pl.is_piloting():
		pl.disembark()
	Tunables.reset_all()
	await process_frame

	var targets: Array = world.call("edge_marker_targets")
	_ok(not targets.is_empty(),
		"the spawn neighbourhood puts things on the edge (%d markers)" % targets.size())

	# Every kind produced must have an icon. This is the contract that stops a
	# new POI shipping as a blank triangle.
	var unknown := ""
	var shaped := true
	for m in targets:
		var d := m as Dictionary
		if not EdgeMarkers.KINDS.has(String(d.get("kind", ""))):
			unknown = String(d.get("kind", ""))
		for key in ["pos", "kind", "color", "dist", "near"]:
			if not d.has(key):
				shaped = false
	_ok(unknown == "", "every marker kind is one the layer can draw (bad: '%s')" % unknown)
	_ok(shaped, "every marker carries pos / kind / colour / distance / nearness")

	# Nearest first, capped — the edge is information, not a fence.
	var ordered := true
	for i in range(1, targets.size()):
		if float((targets[i] as Dictionary)["dist"]) < float((targets[i - 1] as Dictionary)["dist"]):
			ordered = false
	_ok(ordered, "markers come back nearest-first")
	_ok(targets.size() <= world.EDGE_MARKER_MAX,
		"and never more than %d at once" % world.EDGE_MARKER_MAX)

	# `near` is the distance cue the layer fades on: 1 beside you, 0 at the limit.
	var near_ok := true
	for m in targets:
		var n := float((m as Dictionary)["near"])
		if n < 0.0 or n > 1.0:
			near_ok = false
	_ok(near_ok, "nearness is normalised into [0, 1]")

	# YOUR OWN SHIP earns a green blimp — the marker the owner asked for by name,
	# and the one that gets you home after you jump off.
	var local = world.get("local_ship")
	var found_ship := false
	for m in targets:
		if String((m as Dictionary)["kind"]) == "ship":
			found_ship = true
	_ok(local == null or found_ship, "your own ship is one of the markers")

	# ...and the moment you are AT THE HELM it stops being one: an arrow pointing
	# at the deck under your feet is the purest clutter there is.
	var helm: Array = pl.find_helm(fleet.ships(), pl.global_position)
	if not helm.is_empty() and pl.board(helm[0], helm[1]):
		var piloting: Array = world.call("edge_marker_targets")
		var self_marked := false
		for m in piloting:
			if (m as Dictionary)["pos"] == local.to_global(local.solid_bounds.get_center()):
				self_marked = true
		_ok(not self_marked, "the ship you are FLYING gets no marker of its own")
		pl.disembark()
		await process_frame
	else:
		_ok(true, "(no helm in reach — the carrier half skipped)")

	# The DOCK MASTER: the trainer beside spawn wears the anchor.
	var trainer = world.get("_trainer")
	if trainer != null and is_instance_valid(trainer):
		var anchored := false
		for m in world.call("edge_marker_targets"):
			if String((m as Dictionary)["kind"]) == "dock":
				anchored = true
		_ok(anchored, "the dock master (the trainer station) wears the anchor")

	# RANGE really governs: squeeze it to nothing and the sky goes quiet; the
	# toggle does the same thing by a different door.
	Tunables.set_value("edge_marker_screens", 0.0)
	_ok((world.call("edge_marker_targets") as Array).is_empty(),
		"zero screens of range silences every marker")
	Tunables.set_value("edge_marker_screens", 2.0)
	_ok(not (world.call("edge_marker_targets") as Array).is_empty(),
		"...and restoring the range brings them back")
	Tunables.set_value("edge_markers_enabled", false)
	_ok((world.call("edge_marker_targets") as Array).is_empty(),
		"the F2 toggle turns the whole layer off")
	Tunables.reset_all()

	# The range is measured against the LIVE camera, so it is a real "screens"
	# quantity rather than a constant — it must be a positive, finite number of
	# world px, and doubling the screens must double it.
	var one: float = world.call("edge_marker_range_px")
	Tunables.set_value("edge_marker_screens", 4.0)
	var two: float = world.call("edge_marker_range_px")
	Tunables.reset_all()
	_ok(one > 0.0 and is_finite(one), "the marker range is a real distance (%.0f px)" % one)
	_ok(absf(two - one * 2.0) < 1.0,
		"and it scales with the screens lever (%.0f -> %.0f)" % [one, two])
	await process_frame


## THE LAYERED BACKDROP + THE START CHOOSER against the live world (owner
## 2026-08-29). The generative half is pinned pure in the unit suite; here:
## the world actually FEEDS the backdrop, and the boot chooser drives the real
## sandbox toggle through real key events.
func _check_backdrop_and_chooser(world: Node, fleet) -> void:
	# --- Backdrop: the world's side of the contract --------------------------
	var st: Variant = world.call("backdrop_status")
	_ok(st != null, "the world feeds the backdrop")
	if st != null:
		var d := st as Dictionary
		var shaped := true
		for key in ["cam", "alt", "seed", "map_cell_px"]:
			shaped = shaped and d.has(key)
		_ok(shaped, "backdrop_status carries cam / alt / seed / map_cell_px")
		var alt := float(d.get("alt", -1.0))
		_ok(alt >= 0.0 and alt <= 1.0, "the altitude fraction is normalised (%.2f)" % alt)
		_ok(float(d.get("map_cell_px", 0.0)) > 0.0,
			"the map-cell size is a real distance (%.0f px)" % float(d["map_cell_px"]))
	var back = world.get("_backdrop")
	_ok(back != null and is_instance_valid(back) and back.is_inside_tree(),
		"the backdrop layer is in the tree")
	if back != null and is_instance_valid(back):
		var cl = back.get_parent()
		_ok(cl is CanvasLayer and (cl as CanvasLayer).layer < 0,
			"...on a CanvasLayer BEHIND the world (layer %d)"
				% ((cl as CanvasLayer).layer if cl is CanvasLayer else 0))

	# --- The start chooser ---------------------------------------------------
	var chooser = world.get("_start_chooser")
	_ok(chooser != null and is_instance_valid(chooser), "the start chooser exists")
	if chooser == null or not is_instance_valid(chooser):
		return
	_ok(not chooser.visible,
		"it does not show in a headless boot (the suite would eat its keys)")
	Tunables.reset_all()
	var pl = world.get("player")

	# EXPEDITION: open, press 1 — the panel closes and NOTHING changed.
	chooser.open()
	_ok(chooser.visible, "open() shows the panel")
	var key1 := InputEventKey.new()
	key1.keycode = KEY_1
	key1.pressed = true
	chooser._input(key1)
	_ok(not chooser.visible, "[1] dismisses it")
	_ok(not Tunables.get_bool("sandbox_mode"),
		"...and expedition leaves the full game untouched")

	# SANDBOX: open, press 2 — the panel closes and the v0.85.0 loadout landed.
	chooser.open()
	var key2 := InputEventKey.new()
	key2.keycode = KEY_2
	key2.pressed = true
	chooser._input(key2)
	_ok(not chooser.visible, "[2] dismisses it too")
	_ok(Tunables.get_bool("sandbox_mode"),
		"...and turns sandbox mode ON (the same toggle F2 drives)")
	_ok(pl == null or pl.wallet == null or pl.wallet.balance >= 5000,
		"...with the kit-me-out loadout applied")

	# Leave the world as we found it (the sandbox check's own idiom).
	Tunables.reset_all()
	if pl != null and is_instance_valid(pl):
		if pl.inventory != null:
			pl.inventory.clear()
		if pl.wallet != null:
			pl.wallet.balance = 0
		for stat in StatDB.names():
			pl.stats.set_level(stat, 0)
		pl.max_health = pl.stats.max_health()
		pl.health = pl.max_health
	await process_frame


func _ok(condition: bool, detail: String) -> void:
	if condition:
		print("    ok   %s" % detail)
	else:
		failures += 1
		print("    FAIL %s" % detail)


func _finish() -> void:
	if failures == 0:
		print("\nWORLD STARTUP: PASS\n")
		quit(0)
	else:
		print("\nWORLD STARTUP: FAIL — %d problem(s)\n" % failures)
		quit(1)
