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
	var expected_ships: int = 2 + world.WHALE_POD_SIZE + world.CRITTER_COUNT + world.KRAKEN_COUNT
	_ok(fleet.ships().size() == expected_ships,
		"your ship, the hulk, %d whales, %d critters and %d krakens exist (got %d)"
			% [world.WHALE_POD_SIZE, world.CRITTER_COUNT, world.KRAKEN_COUNT, fleet.ships().size()])
	_ok(fleet.ships().any(func(s) -> bool: return s.faction == 1),
		"one of them is the hostile target hulk")
	# Whales are the tier-2 creatures; critters the tier-1 (faction 2 both).
	_ok(fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken").size() == world.WHALE_POD_SIZE,
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
	var whale_ship = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken")[0]
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
	await _check_debug_window(world, fleet)
	await _check_lava_core(world, fleet)

	await _check_hosting_after_offline_play(world, fleet)

	_finish()


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
		# Restore the world for the checks that follow.
		starter.pilot_peer = 1
		world.set("local_ship", starter)
		if pl.is_piloting():
			pl.disembark()

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
	pl.inventory.clear()


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

	var ships_before: int = fleet.ships().size()

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

	_ok(world.load_game(slot), "the world loaded from disk")

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
	var whales: Array = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken")
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

	# KRAKENS ARE UNTAMEABLE (owner build order): even Master Trader (the highest
	# taming tier, set above) cannot tame a deep kraken — try_tame refuses it by
	# creature_kind, and its allegiance never flips.
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

	var whales: Array = fleet.ships().filter(func(s) -> bool: return s.faction == 2 and s.tame_level >= 2 and s.creature_kind != "kraken")
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
func _check_debug_window(world: Node, fleet) -> void:
	var pl = world.get("player")
	var terr = world.get("terrain")
	if pl == null or terr == null:
		return
	if pl.is_piloting():
		pl.disembark()

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
	if hulk != null:
		hulk.queue_free()
	if whale != null:
		whale.queue_free()
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
