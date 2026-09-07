extends SceneTree

## Startup test for the world-scale experiment scene (scale_test.tscn).
##
## Same contract as world_startup_test.gd but at 8×: the upscaled starter
## must boot playable — you spawn as a (now 8-cell-tall) person beside the
## helm, can take it, and the physics stays calm. This is the gate that
## lets the owner's feel test start at "does it fly" instead of "does it
## boot".

var failures := 0


func _initialize() -> void:
	# THE OWNER'S REAL PROFILE IS NOT A FIXTURE: every suite writes through
	# the profile (creature sightings, the F2 forget buttons, card takes), and
	# a full run used to wipe the real bestiary + card gallery. Redirect first,
	# before anything can touch disk.
	Profile.path = "user://profile_test.json"
	# ...and the SAVED SHIPS shelf (Q-T). This suite is the one that actually
	# SEEDS it: a saved vessel is a launch-deck candidate now, and the deck is 8×
	# geometry, which the legacy 1× suite structurally cannot see (CODEMAP §2).
	ShipLayout.user_dir = "user://ships_test_scale"
	_seed_saved_ships()
	print("\n=== 8x default startup ===\n")

	# 8x IS the main scene now (owner verdict 2026-08-18); this boots the
	# real default the player gets on F5.
	var packed: PackedScene = load("res://maps/world/world.tscn")
	if packed == null:
		print("    FAIL could not load res://maps/world/world.tscn")
		return _finish()

	var world: Node = packed.instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame

	_ok(world.get("world_scale") == 8, "the scene declares 8x")

	var fleet = world.get("fleet")
	_ok(fleet != null, "world built a Fleet")
	if fleet == null:
		return _finish()
	# Your ship + the hulk + a POD of whales (WHALE_POD_SIZE) + a few small
	# critters (CRITTER_COUNT) — the variant spawner and the small-creature
	# taming target both fill the sky.
	# +1 for the city-whale BOSS, planted at its fixed deep lair in every world.
	_ok(fleet.ships().size() == 2 + world.WHALE_POD_SIZE + world.CRITTER_COUNT + world.KRAKEN_COUNT + 1,
		"your ship, the hulk, a pod of %d whales, %d critters and the boss exist (got %d)"
			% [world.WHALE_POD_SIZE, world.CRITTER_COUNT, fleet.ships().size()])

	var local = world.get("local_ship")
	_ok(local != null, "the player has a ship")
	if local == null:
		return _finish()
	_ok(local.blocks.size() > 1000,
		"the ship is genuinely 8x (%d blocks)" % local.blocks.size())
	_ok(local.lift_ratio() > 0.9 and local.lift_ratio() < 1.4,
		"the 8x starter keeps its trim (%.2f)" % local.lift_ratio())
	# THE OTHER TWO MODES KEEP THEIR PHYSICS (the standing owner ruling). The
	# rate controller and the air floor are the DIVE's flight model, stamped by
	# `_tick_dive` and cleared by `end_dive`; an expedition hull flies the
	# shipped binary hover in the shipped air, which is what the legacy suites
	# pin. If either of these is ever true at boot, every one of them is lying.
	_ok(not local.rate_control,
		"outside a run the vertical stick is raw thrust, as it always was")
	_ok(is_zero_approx(local.air_density_floor),
		"...and the sky is the sky (no air floor)")

	var p = world.get("player")
	_ok(p != null, "a player character exists")
	if p == null:
		return _finish()
	_ok(absf(p.SIZE.y - 8.0 * 16.0) < 0.5,
		"the player stands 8 cells tall (%.0f px)" % p.SIZE.y)
	_ok(not p.is_piloting(), "and starts on foot")

	var found: Array = p.find_helm(fleet.ships(), p.global_position, p.HELM_REACH)
	_ok(not found.is_empty(), "a helm is within (scaled) reach of the spawn point")
	if not found.is_empty():
		_ok(p.board(found[0], found[1]), "the player can take the helm")
		var before_rot: float = local.rotation
		for i in 60:
			await physics_frame
		_ok(absf(local.angular_velocity) < 0.5,
			"piloting is calm at 8x (%.2f rad/s)" % local.angular_velocity)
		_ok(absf(wrapf(local.rotation - before_rot, -PI, PI)) < 0.5,
			"no pilot-induced spin at 8x")

		# The regression the owner reported: "can't move up or down at 8x,
		# EXTREMELY slow." Full up-throttle must actually climb the ship.
		# Driven through the real input map — the world harness re-reads
		# Input every frame and would clobber a direct net_set_controls.
		var y0: float = local.global_position.y
		Input.action_press("ship_up")
		for i in 120:
			await physics_frame
		Input.action_release("ship_up")
		_ok(local.global_position.y < y0 - 400.0,
			"full throttle climbs the 8x ship (rose %.0f px in 2s)"
				% (y0 - local.global_position.y))

		p.disembark()
		for i in 30:
			await physics_frame
		_ok(p.global_position.distance_to(local.global_position) < 3200.0,
			"after stepping off, the player is on or near the (big) deck")

	# Standing on your own 8x ship must not damage it either.
	var blocks_before: int = local.blocks.size()
	for i in 60:
		await physics_frame
	_ok(local.blocks.size() == blocks_before,
		"standing on the 8x ship does not damage it (%d -> %d)"
			% [blocks_before, local.blocks.size()])

	world.respawn_player()
	_ok(p.global_position.distance_to(local.global_position) < 1600.0,
		"respawn puts you back aboard at 8x")

	# Provocation (owner 2026-08-20): hitting a crewed hostile makes it
	# react, even from beyond aggro range. The hulk spawns well outside
	# even the doubled aggro radius — quiet until poked, then it shoots.
	var hulk: Ship = null
	for ship in fleet.ships():
		if ship.faction == 1:  # the whale is faction 2 — not this test's target
			hulk = ship
	_ok(hulk != null, "the hostile hulk is present to provoke")
	if hulk != null:
		_ok(not _enemy_shot_exists(world), "unprovoked, the hulk holds its fire")

		# The driver patrols: a crewed ship with a live helm potters about
		# a small patch of sky around its post (ShipAI wander). Sampled as
		# max displacement, so any motion registers regardless of where in
		# its figure-eight the ship happens to be.
		var h0: Vector2 = hulk.global_position
		var roamed := 0.0
		for i in 300:
			await physics_frame
			roamed = maxf(roamed, hulk.global_position.distance_to(h0))
		_ok(roamed > 100.0, "the crewed hulk patrols its post (moved %.0f px)" % roamed)
		# Spawn point per world._spawn_enemy_hulk: SHIP_START + (1100,-80)*8.
		_ok(hulk.global_position.distance_to(Vector2(8800.0, -840.0)) < 2500.0,
			"and stays near it")

		# Provocation + reachable aim, the owner's screenshot case in one:
		# the ships sit at comparable altitude, the player's ship's ORIGIN
		# is above the belly gun's horizon, but its lower hull is not —
		# hit from beyond aggro range, the crew must find that and fire
		# (and the AI starts repositioning, which covers the geometry if
		# the wander left the gun momentarily blind).
		hulk.damage_cell(hulk.blocks.keys()[0], 1.0)
		var fired := false
		for i in 600:
			await physics_frame
			if _enemy_shot_exists(world):
				fired = true
				break
		_ok(fired, "hit from beyond aggro range, the crew returns fire")

	# Owner 2026-08-21 (twice): "turret's bullets get deleted when shot in
	# the direction of motion." End-to-end regression through the REAL
	# volley path: the boarded ship at combat speed in clear sky fires at
	# a point ahead; every shell must be alive and clear of the ship after
	# a quarter second. Pins velocity inheritance AND spawn-epoch clearance
	# in the shipped scene, not a synthetic fixture.
	if p != null and local != null:
		local.global_position = Vector2(-12000.0, -8000.0)  # clear sky
		local.linear_velocity = Vector2(2400.0, 0.0)
		await physics_frame
		var volley_aim: Vector2 = local.global_position + Vector2(1500.0, 0.0)
		var pre: Array = []
		for child in world.get_children():
			if child is Shot:
				pre.append(child)
		var fired_own: bool = world._fire_turrets(local, volley_aim)
		var own_shots: Array = []
		for child in world.get_children():
			if child is Shot and not pre.has(child):
				own_shots.append(child)
		_ok(fired_own and not own_shots.is_empty(),
			"a gun bears on a target ahead at speed (%d shell[s])" % own_shots.size())
		for i in 15:
			await physics_frame
		var survivors := 0
		var clear := true
		for s2 in own_shots:
			if is_instance_valid(s2):
				survivors += 1
				clear = clear and not local.solid_bounds.grow(64.0).has_point(
					local.to_local((s2 as Node2D).position))
				(s2 as Node).queue_free()
		_ok(survivors == own_shots.size(),
			"no shell fired along the motion is eaten (%d of %d survive)"
				% [survivors, own_shots.size()])
		_ok(clear, "and every survivor is clear of its own ship")
		local.linear_velocity = Vector2.ZERO

	# Hosting after offline play re-creates every ship through the spawner.
	# Checked at 8× as well as 1× because THIS is where the payloads are real:
	# an 11k-block hull is ~176 KB of spawn data, and a rehoming that the
	# transport silently refused would leave joiners staring at empty sky.
	# (The 1× startup test asserts the crew/whale/one-ship-each properties;
	# here the question is only whether it survives at full size.)
	await _check_machine_bundles(world, local)

	var before_count: int = fleet.ships().size()
	var before_blocks: int = fleet.ships().reduce(
		func(acc: int, s) -> int: return acc + s.blocks.size(), 0)
	world.host_session()
	if not NetUtil.is_online(world):
		print("    SKIP could not bind a host port; hosting checks not run")
	else:
		await process_frame
		_ok(fleet.ships().size() == before_count,
			"hosting an 8x world keeps its %d ships (got %d)"
				% [before_count, fleet.ships().size()])
		var after_blocks: int = fleet.ships().reduce(
			func(acc: int, s) -> int: return acc + s.blocks.size(), 0)
		_ok(after_blocks == before_blocks,
			"and every block came with them (%d -> %d)" % [before_blocks, after_blocks])
		# Fetched by path: autoload identifiers do not resolve at parse time
		# in a --script SceneTree (godot-quirks).
		var net_node := root.get_node_or_null(^"/root/Net")
		if net_node != null:
			net_node.stop()

	# LAST: a dive un-claims your hull, stamps terrain and moves every candidate,
	# so every check above it would otherwise be counting a world it rearranged.
	await _check_dive_deck_at_8x(world)

	# ...and AFTER even that, because it is the most destructive check in the file:
	# it generates ground across a whole max-zoom frame and runs the dormancy scan
	# by hand. Nothing above it would survive being measured afterwards.
	await _check_max_zoom_reaches_the_frame(world)

	# ...and LAST OF ALL, a SECOND, SEPARATE boot: the Dive's own scene. It
	# cannot share the world above, because the whole point of it is the world
	# that world is NOT.
	world.queue_free()
	await process_frame
	await _check_dive_scene_boots()

	# ...and then, with no world left in the tree at all, the one measurement
	# that needs an empty sky: can a kraken catch a hull that is falling?
	await _check_the_heave_catches_a_diving_hull()
	await _check_the_crown_grabs_and_the_maw_shelters()
	# ...and in the same empty sky, the shipped starter's CANOPY under fire and
	# under a graze — the two symptoms dive_probe measured at v0.149.0.
	await _check_the_canopy_is_not_one_unit()
	# ...and the contact that killed the pilot at depth 4 once the canopy was
	# fixed: one crush bill against the whole integrity pool.
	await _check_one_contact_bills_the_pool_once()
	# ...and the thing the v0.157.0 scorecard said none of the above could do:
	# kill a picket with the gun.
	await _check_a_picket_dies_to_a_few_volleys()

	_finish()


## CAN A KRAKEN CATCH YOU? (v0.147.0, DESIGN_KRAKEN §1.5 / jam #3 designer C's
## arithmetic.) The owner's complaint was that krakens are easy to avoid, and
## the reason is pure geometry at 8×: the inherited heave is HORIZONTAL-only
## while the Dive's whole verb is DOWN, so one 4-second attack is thrown at a
## line a hull falling at the rate stick's 1,920 px/s left in the first half
## second — C's cycle nets the hull +7,222 px, every cycle, forever.
##
## HERE and not in the 1× suite for the standing reason (CODEMAP §2): every
## number in it — the dive rate, the align band, the grab reach, the heave's
## peak — is a screen-scale distance, and at scale 1 the whole disagreement is
## eight times smaller than the constants that make it.
##
## Run twice against the same start: once with the shipped levers, and once with
## `kraken_push_vertical` 1.0 / `kraken_lead_seconds` 0 / `kraken_coil_seconds` 0,
## which is exactly the brain that shipped before this slice. The second number
## is the bug, measured; the first is the fix, measured; and the pair IS the
## break-the-fix, because three levers put the old behaviour back.
func _check_the_heave_catches_a_diving_hull() -> void:
	print("\n=== the heave finds a diving hull (8x) ===\n")
	# A sky, so the lead point's lava clamp is live, and an arena far from
	# anything either boot above left behind.
	var kept_bounds := Airspace.bounds
	Airspace.bounds = Rect2(Vector2(-400000.0, -600000.0),
		Vector2(800000.0, 600000.0))
	var dive_rate: float = Tunables.get_num("dive_dive_rate") * 8.0
	var now := await _time_to_contact(dive_rate)
	Tunables.set_value("kraken_push_vertical", 1.0)
	Tunables.set_value("kraken_lead_seconds", 0.0)
	Tunables.set_value("kraken_coil_seconds", 0.0)
	var before := await _time_to_contact(dive_rate)
	Tunables.reset_all()
	Airspace.bounds = kept_bounds
	print("    TIME TO CONTACT: shipped %s | the old horizontal-only ram %s (cap %.0f s)"
		% [("%.1f s" % now) if now > 0.0 else "never",
			("%.1f s" % before) if before > 0.0 else "never", CATCH_SECONDS])
	# A BOUND, not the measurement: a number pinned tight would redden on every
	# tuning pass, and a number not pinned at all is not a test. Measured at
	# 3.9 s the day this was written, against C's target of under 25 s in a real
	# descent; CATCH_BOUND leaves three times that headroom and would still
	# catch the heave going flat again.
	_ok(now > 0.0 and now <= CATCH_BOUND,
		"a kraken above a hull diving at the stick's %.0f px/s reaches it inside %.0f s (%s)"
			% [dive_rate, CATCH_BOUND, ("%.1f s" % now) if now > 0.0 else "NEVER"])
	_ok(before <= 0.0 or before > now * 1.5,
		"...where the horizontal-only ram it replaced could not (%s)"
			% [("%.1f s" % before) if before > 0.0
				else "never, in %.0f s" % CATCH_SECONDS])


## MOUTHS ARE CLUSTERS, AT 8× (DESIGN_KRAKEN §1.2 / §5.4, v0.148.0).
##
## The 1× suite pins the anatomy off the `.ship` files (`meat_clusters`,
## `throat_index`, an arm's own pool). What only 8× can answer is the GEOMETRY
## the fight is made of, because every distance in it is a screen-scale one:
## `kraken_grab_reach` 70 × 8 = 560 px against a 6,656-px body.
##
## Two claims, and they are the two halves of D's fight:
##   * THE CROWN GRABS. A hull that touches an ARM's reach and nothing else is
##     grabbed. Before this slice the boss had exactly one bite bubble and six
##     decorative arms.
##   * THE MAW SHELTERS. A hull parked in the jaws is inside the boss and out of
##     every site's reach — the accident both judges ruled to KEEP, and the
##     reason the throat's site is still the pinned derived centroid rather than
##     the throat cluster's own middle (see `KrakenAI`'s header, decision 3).
func _check_the_crown_grabs_and_the_maw_shelters() -> void:
	print("\n=== the crown grabs, the maw shelters (8x) ===\n")
	var boss := _arena_ship(ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/kraken_leviathan.ship"), 8))
	boss.faction = 2
	boss.creature_kind = "kraken_leviathan"
	boss.shared_health_max = 3600.0
	boss.shared_health = boss.shared_health_max
	boss.position = Vector2(0.0, -420000.0)
	await process_frame
	var ai := KrakenAI.new()
	ai.whale = boss
	ai.home = boss.global_position
	var sites := ai.site_worlds()
	var reach := Tunables.get_num("kraken_grab_reach") * 8.0
	_ok(sites.size() == 7,
		"the boss brings seven grab sites to the fight: a throat and six arms (%d)"
			% sites.size())
	if sites.size() < 7:
		boss.queue_free()
		return
	# A HULL ON AN ARM, and nowhere near the throat's own bubble.
	var arm: Vector2 = sites[1]
	_ok(arm.distance_to(sites[0]) > reach,
		"...and arm 1 reaches %.0f px from the throat's bite, well past its %.0f px"
			% [arm.distance_to(sites[0]), reach])
	var hull := _arena_ship({
		Vector2i(0, 0): BlockDB.Type.HULL, Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL, Vector2i(1, 1): BlockDB.Type.HULL,
	})
	hull.faction = 0
	hull.gravity_scale = 0.0
	hull.global_position = arm
	await process_frame
	var hp0 := 0.0
	for cell in hull.blocks:
		hp0 += float(hull.blocks[cell]["hp"])
	ai.tick(1.0 / 60.0, hull)
	var hp1 := 0.0
	for cell in hull.blocks:
		hp1 += float(hull.blocks[cell]["hp"])
	_ok(ai.grabbing and ai.grab_sites_latched >= 1,
		"a hull touching an ARM's reach and not the throat's IS grabbed (%d site(s))"
			% ai.grab_sites_latched)
	_ok(hp1 < hp0, "...and the arm chews it (%.0f -> %.0f hp)" % [hp0, hp1])

	# THE MAW. The throat's flesh, where the jaws close — and 1,000+ px from the
	# derived bite, which sits out among the crown.
	var maw := boss.to_global(boss._mirror_point(
		KrakenAI.cluster_centroid(ai.throat_cells()) * Ship.CELL))
	hull.global_position = maw
	await process_frame
	var nearest := INF
	for s in sites:
		nearest = minf(nearest, maw.distance_to(s))
	ai.grabbing = false
	ai.tick(1.0 / 60.0, hull)
	_ok(not ai.grabbing and ai.grab_sites_latched == 0,
		"a hull parked IN THE MAW is out of every site's reach (nearest %.0f px, reach %.0f)"
			% [nearest, reach])
	print("    ~ the throat's flesh is %.0f px from the derived bite; the bite's bubble"
		% maw.distance_to(sites[0]))
	print("      stops short of the aperture, which is what makes the jaws a shelter")
	hull.queue_free()
	boss.queue_free()
	ai.whale = null
	await process_frame


## THE CANOPY IS NOT ONE UNIT (v0.151.0). `tools/dive_probe.gd` measured both
## symptoms at v0.149.0 on the shipped starter at 8×: the 24 authored gasbag
## cells upscale into ONE contiguous 1,536-cell "G" cluster, `damage_cell` hits
## every cell of the struck cluster, and so
##   * two 20-hp turret shells popped the ENTIRE lift (a gasbag cell has 35 hp),
##   * one terrain GRAZE deleted all 1,536 blocks in a single crush walk.
## Balloons cluster by the `scale_unit` tile an authored cell became now, so a
## unit is 64 cells and the canopy is 24 of them.
##
## HERE and not in the 1× suite for the standing reason (CODEMAP §2): at scale 1
## the tile is the cell and the bug does not exist — the whole disagreement is
## `upscale_cells`, which the legacy suite never runs on the starter. Measured on
## fresh arena copies of the shipped file, in the empty sky the checks above
## leave behind, so nothing else in this suite is counting a canopy we shot.
func _check_the_canopy_is_not_one_unit() -> void:
	print("\n=== the canopy is 24 balloons, not one 1,536-cell unit (8x) ===\n")
	var cells: Dictionary = ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/starter.ship"), 8)
	var canopy := _arena_ship(cells)
	canopy.gravity_scale = 0.0
	canopy.global_position = Vector2.ZERO  # sea level: lift_ratio reads real air
	# ARMED, exactly as a run arms your hull — the pool is the other half of what
	# a shell into the canopy used to cost.
	canopy.hull_integrity_max = Tunables.get_num("dive_ship_integrity")
	canopy.hull_integrity = canopy.hull_integrity_max
	await process_frame

	var bags := _bag_cells(canopy)
	_ok(bags.size() == 1536,
		"the shipped starter's canopy is %d cells at 8x" % bags.size())
	if bags.is_empty():
		canopy.queue_free()
		return
	var floats_before := canopy.lift_ratio()
	var mass_before := canopy.mass

	# (a) ONE SHELL REACHES ONE BALLOON. 20 hp into a canopy cell: 64 cells hurt
	# (its 8×8 tile), 1,472 pristine. Before: all 1,536, and the pool billed once
	# for the lot (v0.149.0) but every block still took the hit.
	var aim: Vector2i = bags[bags.size() / 2]
	var full := BlockDB.max_hp(BlockDB.Type.GASBAG)
	var pool_before := canopy.hull_integrity
	canopy.damage_cell(aim, 20.0)
	var hurt := 0
	for c in bags:
		if canopy.has_block(c) and float(canopy.blocks[c]["hp"]) < full - 0.01:
			hurt += 1
	_ok(hurt == 64,
		"one 20-hp shell damages exactly its own balloon — 64 cells, not 1,536 (%d)"
			% hurt)
	_ok(absf((pool_before - canopy.hull_integrity) - 20.0) < 0.01,
		"...and bills the integrity pool 20 (%.0f of %.0f left)"
			% [canopy.hull_integrity, canopy.hull_integrity_max])

	# The SECOND shell kills that balloon (35 hp a cell, 40 taken) — the pair that
	# used to pop the whole canopy. One tile goes; the other 23 hold the ship up.
	canopy.damage_cell(aim, 20.0)
	await process_frame
	await process_frame
	var left := _bag_cells(canopy).size()
	_ok(left == 1472,
		"two shells cost ONE balloon: %d canopy cells left of 1,536 (was 0)" % left)

	# (c) AND IT STILL FLOATS. Before, two shells took every gasbag with them and
	# the hull became a brick — the run over on a picket's second round.
	var floats_after := canopy.lift_ratio()
	_ok(floats_after > 1.0,
		"the shot hull still lifts its own weight (ratio %.3f, was %.3f before the hit)"
			% [floats_after, floats_before])
	print("    ~ mass %.0f -> %.0f, lift ratio %.3f -> %.3f"
		% [mass_before, canopy.mass, floats_before, floats_after])

	# The CONTRAST, measured rather than asserted from memory: the same hull with
	# the whole canopy gone — what the old rule handed you — cannot hold itself up.
	var bald := _arena_ship(cells)
	bald.gravity_scale = 0.0
	bald.global_position = Vector2.ZERO
	await process_frame
	for c in _bag_cells(bald):
		bald.blocks.erase(c)
	bald.rebuild()
	_ok(bald.lift_ratio() < 1.0,
		"...where a hull that lost the WHOLE canopy is a brick (ratio %.3f)"
			% bald.lift_ratio())
	bald.queue_free()
	canopy.queue_free()
	await process_frame

	# (b) THE GRAZE. A crush budget of 600,000 — the size dive_probe billed per
	# crash (1,765,755 over three) — driven into the canopy from above through the
	# real _process walk, not arithmetic. The walk kills the tile it entered and
	# then finds its next step already gone, so it stops: a few balloons at worst,
	# never the lift.
	var grazed := _arena_ship(cells)
	grazed.gravity_scale = 0.0
	grazed.global_position = Vector2.ZERO
	await process_frame
	var before_bags := _bag_cells(grazed).size()
	var top: Vector2i = _bag_cells(grazed)[0]
	# Solve the budget back through _process's conversion at 8×:
	#   available = (impulse - THRESHOLD * unit³) * SCALE / unit²
	var impulse: float = Tunables.get_num("impact_damage_threshold") * 512.0 \
		+ 600000.0 * 64.0 / Tunables.get_num("impact_damage_scale")
	grazed._pending_impacts.append({
		"pos": grazed.local_pos_of(top) + Vector2(0.0, -Ship.CELL * 0.5),
		"impulse": impulse,
		"normal": Vector2.DOWN,   # the ground pushing INTO the canopy from above
		"immune": false,
	})
	await process_frame
	await process_frame
	var after_bags := _bag_cells(grazed).size()
	var lost := before_bags - after_bags
	_ok(lost > 0, "the graze really bit the canopy (%d cells)" % lost)
	_ok(lost <= 192,
		"...a few balloons at most — %d cells lost, bound 192 (three tiles), not 1,536"
			% lost)
	_ok(grazed.lift_ratio() > 1.0,
		"and the grazed hull still flies home (ratio %.3f)" % grazed.lift_ratio())
	print("    ~ a 600,000 crush budget into the canopy: %d of %d cells lost"
		% [lost, before_bags])
	grazed.queue_free()
	await process_frame


## ONE CONTACT, ONE POOL BILL (v0.155.0). `tools/dive_probe.gd` at v0.151.0 lost
## the hull at depth 4 to a SINGLE neutral-whale ram — `HULL BILL: ram 199891
## (99%, 1 contact)`, 814 blocks gone, the grid nowhere near ground down — and at
## seed 565218463 the same shape killed it as one TERRAIN crash billed 237,391.
## The cause is not the ram: the crush walk destroys cell after cell inward and
## `damage_cell` billed the integrity pool for EVERY one, so a contact's real
## price was "hp along the whole inward line". A crush budget is momentum-sized
## (hundreds of thousands at 8×) and a hull cell is 100 hp, so thirty cells of
## walk IS a 3,000 pool — one touch, whatever the touch was.
##
## The fix caps the POOL bill per contact at `dive_crush_pool_cap` × the hull's
## own max; the BLOCKS are untouched, which is the half this check has to prove
## as loudly as the other. And the check breaks the fix on purpose (the lever at
## 1.0) so it is a regression test that has been SEEN to fail.
##
## HERE and not in the 1× suite for the standing reason (CODEMAP §2): the whole
## disagreement is the eightfold — at scale 1 a crush budget is 64× smaller and a
## walk that reaches thirty cells does not exist on a starter eight cells tall.
func _check_one_contact_bills_the_pool_once() -> void:
	print("\n=== one crush contact bills the integrity pool once, capped (8x) ===\n")
	var cells: Dictionary = ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/starter.ship"), 8)
	var pool: float = Tunables.get_num("dive_ship_integrity")
	var share: float = Tunables.get_num("dive_crush_pool_cap")

	# A WHALE-SIZED RAM, driven through the real `_process` walk rather than
	# arithmetic. Solve the budget back through the conversion at 8× — the same
	# idiom the graze check uses — and let the creature multiplier do its work:
	#   available = (impulse - THRESHOLD·unit³) · SCALE / unit², then × ram_mult.
	const RAM_BUDGET := 200000.0
	var ram_mult: float = Tunables.get_num("creature_ram_damage")
	var impulse: float = Tunables.get_num("impact_damage_threshold") * 512.0 \
		+ RAM_BUDGET / ram_mult * 64.0 / Tunables.get_num("impact_damage_scale")

	var billed := 0.0
	var lost := 0
	var alive := 0.0
	for capped in [true, false]:
		# The second pass is the fix BROKEN on purpose: cap 1.0 is the old
		# uncapped bill, and it must still empty the pool.
		Tunables.set_value("dive_crush_pool_cap", share if capped else 1.0)
		var hull := _arena_ship(cells)
		hull.gravity_scale = 0.0
		hull.global_position = Vector2.ZERO
		hull.hull_integrity_max = pool
		hull.hull_integrity = pool
		await process_frame
		var before := hull.blocks.size()
		# Struck on the beam, along the ship's widest row, so the walk has the
		# most hull it can possibly find in front of it — the worst case, which
		# is exactly the case that emptied the pool.
		var aim := _widest_row_entry(hull)
		hull._pending_impacts.append({
			"pos": hull.local_pos_of(aim) + Vector2(-Ship.CELL * 0.5, 0.0),
			"impulse": impulse,
			"normal": Vector2.RIGHT,   # a body shouldering INTO the hull's flank
			"immune": false,
			"creature": true,          # ...and it is a creature, so ×ram_mult
		})
		await process_frame
		await process_frame
		if capped:
			billed = pool - hull.hull_integrity
			lost = before - hull.blocks.size()
			alive = hull.hull_integrity
		else:
			_ok(hull.hull_integrity <= 0.0,
				"the same contact with the cap OFF (1.0) still empties the pool"
					+ " (%.0f left) — the bug this pins" % hull.hull_integrity)
		hull.queue_free()
		await process_frame
	Tunables.set_value("dive_crush_pool_cap", share)

	var cap := share * pool
	_ok(absf(billed - cap) < 0.01,
		"a %.0f-budget ram bills the pool %.0f, its whole-contact cap (%.0f%% of %.0f)"
			% [RAM_BUDGET, billed, 100.0 * share, pool])
	_ok(alive > 0.0,
		"...and the hull is still flying afterwards (%.0f of %.0f integrity left)"
			% [alive, pool])
	_ok(lost >= 20,
		"...while the blocks STILL come off: %d cells crushed out of the hull" % lost)
	print("    ~ before the fix this one contact billed the pool the hp of its whole")
	print("      inward walk — %.0f of a %.0f pool, the run over in one touch"
		% [pool, pool])

	# THE ENGINE BANK, the next biggest single unit a hit can reach now that the
	# canopy is 24 balloons (v0.151.0's "found on the way"). It is one contiguous
	# "E" cluster of 192 cells at 8×, so every one of them takes a shell's amount
	# — but the POOL is billed once, which is the v0.149.0 fix holding on the
	# biggest unit left. Measured here so the number is on the record.
	var bank := _arena_ship(cells)
	bank.gravity_scale = 0.0
	bank.global_position = Vector2.ZERO
	bank.hull_integrity_max = pool
	bank.hull_integrity = pool
	await process_frame
	var engines: Array[Vector2i] = []
	for c in bank.blocks:
		if int(bank.blocks[c]["type"]) == BlockDB.Type.ENGINE:
			engines.append(c)
	engines.sort()
	if engines.is_empty():
		_ok(false, "the shipped starter has an engine bank to shoot")
		bank.queue_free()
		return
	var unit: Array = bank._component_members(engines[engines.size() / 2])
	var e_pool := bank.hull_integrity
	bank.damage_cell(engines[engines.size() / 2], 20.0)
	var e_billed := e_pool - bank.hull_integrity
	_ok(absf(e_billed - 20.0) < 0.01,
		"a 20-hp shell into the %d-cell ENGINE bank bills the pool 20, not %d × 20 (%.0f)"
			% [unit.size(), unit.size(), e_billed])
	print("    ~ the bank is %d cells of the starter's %d; every cell still takes the"
		% [unit.size(), engines.size()])
	print("      hit as one unit (%d hp each, so four shells cost the whole bank in"
		% int(BlockDB.max_hp(BlockDB.Type.ENGINE)))
	print("      BLOCKS) — the canopy's problem an order smaller, and pool-safe")
	bank.queue_free()
	await process_frame


## A SHELL HAS TO BE WORTH SOMETHING (v0.159.0, off the v0.157.0 scorecard).
##
## Three seeds at 8× fired ~1,400 shells and killed NOTHING: a picket's 600 pool
## against a 20-damage shell was 30 landed hits, at about one shell a second,
## spread over the 22 bodies a descent meets. Two dials answer it — a shell bills
## the pool `dive_shell_worth` times its damage (blocks untouched), and a picket
## dies at `dive_picket_integrity` — and this is the check that says how many
## landed volleys that actually is, on the REAL native-8× hulk, through the real
## `net_damage_cell` path a `Shot` takes.
##
## HERE and not in the 1× suite for the standing reason (CODEMAP §2): the whole
## finding is the eightfold. At scale 1 a hulk is 56 cells wide and its
## components are one cell each, so neither the component bill nor the 8× cell
## count that made a shell worthless exists to measure.
func _check_a_picket_dies_to_a_few_volleys() -> void:
	print("\n=== a picket dies to a few landed volleys (8x) ===\n")
	var pool: float = Tunables.get_num("dive_picket_integrity")
	var shell: float = Tunables.get_num("turret_damage")
	var worth: float = Tunables.get_num("dive_shell_worth")
	# The shipped hulk is authored NATIVE 8× — `_spawn_hulk_at` does not upscale
	# it, so neither does this.
	var cells: Dictionary = ShipLayout.load_cells("res://ships/hulk.ship")
	var picket := _arena_ship(cells)
	picket.gravity_scale = 0.0
	picket.global_position = Vector2.ZERO
	picket.faction = 1
	picket.hull_integrity_max = pool
	picket.hull_integrity = pool
	await process_frame

	# Where an enemy gunner's shell actually lands: the outer plating on the beam.
	# Walked forward hit by hit like real fire, never the same cell twice, so no
	# shot is billing a cell a previous shot had already worn down.
	var skin: Array[Vector2i] = []
	for c in picket.blocks:
		if int(picket.blocks[c]["type"]) == BlockDB.Type.HULL:
			skin.append(c)
	skin.sort()
	_ok(skin.size() > 64, "the hulk has plating to shoot (%d hull cells)" % skin.size())
	var landed := 0
	while picket.hull_integrity > 0.0 and landed < skin.size() and landed < 400:
		# The exact call `Shot` makes when a shell finds a hull.
		picket.net_damage_cell(skin[landed], shell, worth)
		landed += 1
	_ok(picket.hull_integrity <= 0.0,
		"%d landed shells empty a picket's %.0f pool" % [landed, pool])
	# The starter's two turrets face opposite ways (its `T` glyphs sit on the
	# port and starboard edges), so one bears on a target and a volley is ONE
	# shell — landed shells and landed volleys are the same number here.
	_ok(landed >= 3 and landed <= 8,
		"...which is %d landed volleys from the starter's helm (was %.0f)"
			% [landed, 600.0 / shell])
	# AND THE BLOCKS ARE UNTOUCHED BY THE LEVER — the worth scales the run's life,
	# not the visible bite. Same shell, same plating, with the lever at 1.
	var plain := _arena_ship(cells)
	plain.gravity_scale = 0.0
	plain.global_position = Vector2.ZERO
	plain.hull_integrity_max = pool
	plain.hull_integrity = pool
	await process_frame
	var full := BlockDB.max_hp(BlockDB.Type.HULL)
	plain.net_damage_cell(skin[0], shell, 1.0)
	var hp_at_one: float = plain.blocks[skin[0]]["hp"] if plain.has_block(skin[0]) else 0.0
	var billed_at_one := pool - plain.hull_integrity
	plain.hull_integrity = pool
	plain.net_damage_cell(skin[1], shell, worth)
	var hp_at_worth: float = plain.blocks[skin[1]]["hp"] if plain.has_block(skin[1]) else 0.0
	var billed_at_worth := pool - plain.hull_integrity
	_ok(absf(hp_at_one - hp_at_worth) < 0.01
			and absf(hp_at_one - (full - shell)) < 0.01,
		"the same shell takes the same %.0f hp off a cell at either worth (%.0f / %.0f)"
			% [shell, full - hp_at_one, full - hp_at_worth])
	_ok(absf(billed_at_worth - billed_at_one * worth) < 0.01,
		"...while the POOL bill is %.0f at worth 1 and %.0f at worth %.2f"
			% [billed_at_one, billed_at_worth, worth])
	# BREAK IT ON PURPOSE: put BOTH dials back where v0.157.0 measured zero kills
	# — a 600 pool and a shell worth its face value — and fire the same volleys
	# into the same plating. BOTH, because either one alone restores the old
	# fight (that is what makes them the owner's two sliders), so a check that
	# reverted only the worth would pass for the wrong reason once the pool came
	# down far enough to die to eight face-value shells anyway.
	var old_pool := 600.0
	plain.hull_integrity_max = old_pool
	plain.hull_integrity = old_pool
	var old_landed := 0
	while plain.hull_integrity > 0.0 and old_landed < 8:
		plain.net_damage_cell(skin[old_landed], shell, 1.0)
		old_landed += 1
	_ok(plain.hull_integrity > 0.0,
		"...and at the OLD dials (pool %.0f, worth 1) it still flies after 8 volleys (%.0f left)"
			% [old_pool, plain.hull_integrity])
	print("    ~ pool %.0f, shell %.0f x worth %.2f = %.0f a landed volley"
		% [pool, shell, worth, shell * worth])
	picket.queue_free()
	plain.queue_free()
	await process_frame


## The leftmost HULL cell of the row with the most hull in it: where a beam-on
## contact enters the longest run of plain, cell-by-cell structure. HULL and not
## "any block" on purpose — a gasbag or a machine is a COMPONENT, so the first
## bite erases the whole unit including the walk's own next step and the crush
## stops after one cell (which is what the canopy check measures). The hull band
## is the case that emptied the pool.
func _widest_row_entry(s: Ship) -> Vector2i:
	var rows := {}
	for c in s.blocks:
		if int(s.blocks[c]["type"]) != BlockDB.Type.HULL:
			continue
		rows[c.y] = int(rows.get(c.y, 0)) + 1
	var best_row := 0
	var best_n := -1
	for y in rows:
		if int(rows[y]) > best_n:
			best_n = int(rows[y])
			best_row = int(y)
	var best_x := 1 << 30
	for c in s.blocks:
		if c.y == best_row and int(s.blocks[c]["type"]) == BlockDB.Type.HULL:
			best_x = mini(best_x, c.x)
	return Vector2i(best_x, best_row)


## Every GASBAG cell of a ship, in a stable order.
func _bag_cells(s: Ship) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in s.blocks:
		if int(s.blocks[c]["type"]) == BlockDB.Type.GASBAG:
			out.append(c)
	out.sort()
	return out


## How long the hunt is given before it is called a miss, and how far above and
## across the kraken starts — inside a max-zoom frame (~16,432 px half-diagonal),
## so this is a hunter you can WATCH fail to reach you, not one out of range.
const CATCH_SECONDS := 25.0
const CATCH_BOUND := 12.0
const CATCH_START := Vector2(4000.0, -6000.0)


## Seconds until a kraken started at CATCH_START has hold of the hull or is
## standing on it; -1 if it never does inside CATCH_SECONDS. The hull's velocity
## is written every frame because that IS the rate stick (`Ship.rate_control`
## drives toward a RATE, not a force) — and it stops mattering the instant the
## measurement ends, which is the first frame of contact.
func _time_to_contact(dive_rate: float) -> float:
	var hull := _arena_ship(ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/starter.ship"), 8))
	hull.faction = 0
	hull.position = Vector2(0.0, -300000.0)
	var kraken := _arena_ship(ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/kraken_c.ship"), 8))
	kraken.faction = 2
	kraken.creature_kind = "kraken"
	kraken.shared_health_max = 1200.0 * 8.0
	kraken.shared_health = kraken.shared_health_max
	kraken.position = hull.position + CATCH_START
	await process_frame
	var ai := KrakenAI.new()
	ai.whale = kraken
	ai.home = kraken.global_position
	var t := -1.0
	for i in int(CATCH_SECONDS * 60.0):
		hull.linear_velocity = Vector2(0.0, dive_rate)
		ai.tick(1.0 / 60.0, hull)
		await physics_frame
		if ai.grabbing or hull.get_colliding_bodies().has(kraken):
			t = float(i) / 60.0
			break
	hull.queue_free()
	kraken.queue_free()
	await process_frame
	return t


## A ship in the empty arena: 8× granularity, real gravity, nothing else.
func _arena_ship(cells: Dictionary) -> Ship:
	var s := Ship.new()
	for cell in cells:
		var type: int = cells[cell]
		s.blocks[cell] = {"type": type, "hp": BlockDB.max_hp(type)}
	root.add_child(s)
	s.scale_unit = 8.0
	s.gravity_scale = 8.0
	s.rebuild()
	return s


## "AS IF THEY WERE USING A SHIP'S MAX ZOOM" (the standing owner rule since
## v0.128.0), applied to the two radii that never learned it — owner 2026-09-02:
## *"The 'max zoom as if on ship' doesn't seem to be fully recognized - if I zoom
## out as much as possible I can see that creatures toward the edge of the screen
## are updating super slow (per the 'far away, delay updates' process). But this
## also causes terrain to load in half way on the screen."*
##
## Both numbers were authored before the rule and both were SHORTER than the
## frame they have to cover:
##   * dormancy slept at `dormant_range_px` = 12,000 px, against a max-zoom
##     half-diagonal of ~16,432 — bodies in plain sight left the simulation and
##     moved on the 3 s dormant tick;
##   * terrain's promote radius capped at `20 * subdiv / 8` chunks = 10,240 px at
##     subdiv 4, against a max-zoom half-WIDTH of ~14,321 — the ground stopped
##     ~70% of the way to the screen edge.
##
## Here rather than in the 1× suite for the usual reason: every number in it is a
## screen-scale distance (CODEMAP §2), and at scale 1 the frame is 8× smaller
## than the constants and both bugs are invisible.
func _check_max_zoom_reaches_the_frame(w: Node) -> void:
	var terrain = w.get("terrain")
	var pl = w.get("player")
	if terrain == null or pl == null or not is_instance_valid(pl):
		_ok(false, "a world with a player and terrain to measure")
		return
	var half_w: float = float(w.call("max_view_width_px")) * 0.5
	var horizon: float = float(w.call("max_view_horizon_px"))
	var cpx: float = float(terrain.call("chunk_px"))
	print("    ~ max-zoom frame: half-width %.0f px, half-diagonal %.0f px, chunk %.0f px"
		% [half_w, horizon, cpx])
	Tunables.reset_all()

	# --- DORMANCY: nothing inside the widest frame may sleep ----------------
	var at: Vector2 = pl.global_position
	var probe: Ship = w.call("debug_spawn", "critter",
		at + Vector2(half_w * 0.9, 0.0))
	_ok(probe != null, "a creature at 0.9 x the max-zoom half-width (%.0f px out)"
		% (half_w * 0.9))
	if probe != null and is_instance_valid(probe):
		probe.freeze = true
		# The decision scan runs on its own cadence; give it several periods.
		for i in 4:
			w.call("_update_dormancy", 0.5)
		_ok(not probe.dormant,
			"...is STILL SIMULATED, not ticking every 3 s (dormancy's floor is the frame)")
		# ...and the feature still works: well outside the frame, it sleeps.
		probe.global_position = at + Vector2(horizon * 3.0, 0.0)
		for i in 4:
			w.call("_update_dormancy", 0.5)
		_ok(probe.dormant,
			"...while three horizons out it sleeps, so the feature still pays for itself")
		probe.queue_free()
		await process_frame

	# --- TERRAIN: the ground reaches the frame's edge ------------------------
	# `primary_range_px` is stamped here rather than by winding the camera, because
	# the camera is hard-locked and re-derives its zoom every frame. This IS the
	# number `_stream_terrain` writes at max zoom-out: half the widest frame.
	var target_x := at.x + half_w * 0.9
	IslandGen.ensure_generated(terrain, int(w.get("world_seed")),
		[at, Vector2(target_x, at.y), Vector2(target_x, at.y - half_w),
			Vector2(target_x, at.y + half_w)], half_w, 4096)
	# MOST OF THIS WORLD IS SKY, and where an island happens to fall is the
	# generator's business — so the probe is PLANTED rather than hunted for: a
	# patch of stone exactly 12 chunks out, in the band between the old cap
	# (10 chunks = 10,240 px) and the max-zoom frame's edge (14,322 px). That band
	# IS the bug, and this makes the measurement independent of the world seed.
	# `set_cell` is a generation write, not a dig: it is not recorded as an edit.
	var home: Vector2i = terrain.call("chunk_of_cell",
		terrain.call("world_to_cell", at))
	var ground := home + Vector2i(12, 0)
	var cell0 := ground * Terrain.CHUNK + Vector2i(4, 4)
	terrain.call("fill_rect", Rect2i(cell0, Vector2i(8, 8)), TerrainDB.Type.STONE)
	terrain.call("flush_rebuilds")
	_ok((terrain.get("_chunks") as Dictionary).has(ground),
		"a probe chunk of ground %.0f px out — past the old cap, inside the frame"
			% (12.0 * cpx))
	# Measured from that chunk's own altitude, so the only distance in play is the
	# horizontal one the report is about.
	var focus := Vector2(at.x, (float(ground.y) + 0.5) * cpx)

	var old_live := await _drain_streaming(terrain, 0.0, focus, half_w)
	var old_r: int = int(terrain.call("_primary_promote_r"))
	var old_has: bool = (terrain.get("_live") as Dictionary).has(ground)
	var new_live := await _drain_streaming(terrain, horizon + cpx, focus, half_w)
	var new_r: int = int(terrain.call("_primary_promote_r"))
	var new_has: bool = (terrain.get("_live") as Dictionary).has(ground)
	print("    ~ live chunks at max zoom-out: %d (old cap r=%d = %.0f px) -> %d (max-zoom cap r=%d = %.0f px)"
		% [old_live, old_r, float(old_r) * cpx, new_live, new_r, float(new_r) * cpx])
	_ok(float(new_r) * cpx >= half_w,
		"the promote radius now reaches the frame's own edge (%.0f px vs half-width %.0f)"
			% [float(new_r) * cpx, half_w])
	_ok(float(old_r) * cpx < half_w,
		"...which the old %d-chunk cap did not (%.0f px - the owner's 'half way on the screen')"
			% [old_r, float(old_r) * cpx])
	_ok(new_has,
		"A CHUNK WITH GROUND IN IT AT 0.9 x THE HALF-WIDTH IS LIVE after the drain")
	_ok(not old_has,
		"...and was NOT under the old cap, which is the report, reproduced")
	_ok(new_live < 900,
		"...and the live set is still a set, not the world (%d chunks)" % new_live)
	Tunables.reset_all()


## Run the streamer at a given `primary_cap_px` until its queue drains, and
## report how many chunks ended up live. `update_streaming` promotes inside the
## call, so this costs iterations, not seconds.
func _drain_streaming(terrain, cap_px: float, focus: Vector2,
		range_px: float) -> int:
	for i in 2000:
		# Re-stamped every pass: the world's own `_stream_terrain` runs on the
		# frames this awaits and would put the live camera's numbers straight back.
		terrain.set("primary_cap_px", cap_px)
		terrain.set("primary_range_px", range_px)
		var before: int = (terrain.get("_live") as Dictionary).size()
		terrain.call("update_streaming", [focus], [])
		if (terrain.get("_live") as Dictionary).size() == before \
				and bool(terrain.get("_last_scan_drained")):
			break
		if i % 120 == 119:
			await process_frame
	return (terrain.get("_live") as Dictionary).size()


## THE DIVE'S OWN SCENE (owner 2026-09-01: "we just keep reusing the same world
## with the same awkward configs and it's a mess … I'm also wondering why this
## isn't its own scene").
##
## `maps/dive/dive.tscn` is the same `world.gd` with `dive_native = true`, and
## this is the contract that flag buys: a world that opens straight into a run,
## rolls its own sky, and is only as wide as the WIND RING instead of the
## expedition's ×4 span. Here rather than in the 1× suite because every number
## below is a SCREEN-SCALE distance, and the legacy scene cannot see those
## (CODEMAP: geometry that matters at 8× belongs in a scale-aware suite).
func _check_dive_scene_boots() -> void:
	var packed: PackedScene = load("res://maps/dive/dive.tscn")
	_ok(packed != null, "res://maps/dive/dive.tscn loads")
	if packed == null:
		return
	# NOTHING PENDING. A dive-native scene is the mode; it must not need to be
	# told, which is the difference between "its own scene" and "the same world
	# with a flag passed to it".
	GameMode.pending = GameMode.EXPEDITION
	var w: Node = packed.instantiate()
	root.add_child(w)
	for i in 20:
		await process_frame

	_ok(bool(w.get("dive_native")), "the scene declares itself the Dive's own")
	_ok(w.get("world_scale") == 8, "...at the shipped 8×")
	_ok(w.get("dive") != null,
		"it boots STRAIGHT into a run, with no GameMode.pending handshake")
	var fleet = w.get("fleet")
	if fleet == null:
		_ok(false, "the dive scene built a Fleet")
		w.queue_free()
		return

	# THE STREAMLINED BOOT, still: the mode brings its own threats.
	var wild := 0
	var hostile := 0
	var candidates := 0
	var blocks := 0
	for s in (fleet.call("ships") as Array):
		if not is_instance_valid(s):
			continue
		var ship := s as Ship
		blocks += ship.blocks.size()
		if ship.creature_kind != "":
			wild += 1
		if ship.faction == 1:
			hostile += 1
		if ship.faction == 0 and not ship.is_nest and ship.creature_kind == "" \
				and not ship.is_carcass() and ship.has_helm():
			candidates += 1
	_ok(wild == 0, "no wildlife at boot (%d)" % wild)
	_ok(hostile == 0, "...and no hostile ecology either (%d)" % hostile)
	_ok(candidates >= 2,
		"...but the launch deck's candidates are moored (%d hulls, %d blocks)"
			% [candidates, blocks])
	_ok(w.get("_dive_deck") != null and is_instance_valid(w.get("_dive_deck")),
		"the deck itself is raised")
	var pl = w.get("player")
	_ok(pl != null and is_instance_valid(pl), "and a body is standing on it")

	# THE NARROW WORLD. The ring's circumference and the world's width come from
	# ONE number (`world.dive_nominal_tile_w`), so the wrap can never land
	# outside the walls that were built for it.
	var rect: Rect2 = w.get("_world_rect")
	var ring_w: float = w.call("dive_ring_width")
	var margin: float = rect.size.x / maxf(ring_w, 1.0)
	_ok(is_equal_approx(ring_w, float(w.call("dive_nominal_ring_width"))),
		"the live ring IS the ring the world was built for (%.0f px)" % ring_w)
	_ok(margin > 1.0 and margin < 1.25,
		"the world is the ring plus a modest margin (×%.3f — %.0f px wide, ring %.0f)"
			% [margin, rect.size.x, ring_w])
	_ok(rect.size.x > ring_w, "...so the wrap line sits INSIDE the walls")
	# ...and it is genuinely narrower than the expedition's, which is the win.
	var full_w := float(IslandGen.WORLD_CELLS.size.x) * TerrainDB.CELL * 8.0
	_ok(rect.size.x < full_w * 0.7,
		"...and far narrower than an expedition's %.0f px (%.0f)" % [full_w, rect.size.x])
	_ok(is_equal_approx(rect.size.y,
			float(IslandGen.WORLD_CELLS.size.y) * TerrainDB.CELL * 8.0),
		"the HEIGHT is untouched — the ladder and the bands are fractions of it")
	_ok(is_zero_approx(rect.get_center().x),
		"and it is still centred on the run's centre line")

	# A FRESH SKY EVERY RUN: the dive's own scene rolls a seed, the expedition's
	# fixed one is left alone.
	_ok(int(w.get("world_seed")) != IslandGen.DEFAULT_SEED,
		"the dive rolled its own world seed (%d)" % int(w.get("world_seed")))

	# THE BANDS SURVIVE THE NARROWING. They are altitude fractions of the world
	# rect, so a narrower world must paint exactly the same sky — depth 1 in
	# breathable air, the floor below the line, and the backdrop reading a band.
	var top_a: float = DiveRun.depth_altitude(1)
	var floor_a: float = DiveRun.depth_altitude(DiveRun.DEPTHS)
	_ok(Airspace.band_at_frac(top_a) == Airspace.Band.TOP,
		"depth 1 is still in the TOP band")
	_ok(Airspace.is_unbreathable_frac(floor_a),
		"...and the floor's air still kills you")
	if pl != null and is_instance_valid(pl):
		var stood: Vector2 = pl.global_position
		pl.global_position = Vector2(stood.x, float(w.call("dive_altitude_y", floor_a)))
		await w.get_tree().physics_frame
		_ok(absf(float(w.call("_player_altitude_frac")) - floor_a) < 0.02,
			"the narrow world reads the floor's altitude back correctly (%.3f)"
				% float(w.call("_player_altitude_frac")))
		var deep_sky: Array = Backdrop.band_palette(floor_a)
		var high_sky: Array = Backdrop.band_palette(top_a)
		_ok((deep_sky[0] as Color) != (high_sky[0] as Color),
			"...and the backdrop still paints two different skies over it")
		pl.global_position = stood
		await w.get_tree().physics_frame

	# THE ROCKS HAVE ROCKS IN THEM: walk into a flank tile and its floating land
	# is cut, as terrain, where the model said it would be.
	var run = w.get("dive")
	var cx: float = rect.get_center().x
	var tile_w: float = w.call("_dive_tile_w")
	var terrain = w.get("terrain")
	if pl != null and is_instance_valid(pl) and run != null and terrain != null:
		var tile := 2   # a rock tile, five tiles short of the seam
		var depth := 3
		run.set("depth", depth)
		pl.global_position = Vector2(cx + DiveRun.zone_offset(tile) * tile_w,
			float(w.call("dive_altitude_y", DiveRun.depth_altitude(depth))))
		_ok(int(w.call("dive_zone")) == tile,
			"standing a few tiles out puts you in rock tile %d" % tile)
		w.call("_dive_hold_the_ring", 0.016)
		var rows: Array = DiveRun.tile_chunks(int(run.get("seed_v")), tile, depth)
		_ok(not rows.is_empty(), "the model furnishes it (%d slabs)" % rows.size())
		var solid := 0
		for r in rows:
			var row := r as Dictionary
			var at := Vector2(cx + (DiveRun.zone_offset(tile) + float(row["x"])) * tile_w,
				float(w.call("dive_altitude_y", float(row["alt"]))))
			if terrain.call("is_solid", terrain.call("world_to_cell", at)):
				solid += 1
		_ok(solid == rows.size(),
			"...and every one of them is REAL STONE in the world (%d/%d)"
				% [solid, rows.size()])
		# Asked once: a tile already grown is never re-stamped (it would fight
		# the player's own digging).
		w.call("_dive_hold_the_ring", 0.016)
		_ok((w.get("_dive_chunks_cut") as Dictionary).size() >= 1,
			"a grown tile is remembered, so it is never cut twice")

	# THE RUN'S OWN CONTRACTS still hold in the narrow world: the loop closes,
	# and a surge is born hostile and mortal.
	if pl != null and is_instance_valid(pl):
		await _check_dive_seam_is_seamless(w, pl, rect, ring_w, cx, terrain)
		await _check_dive_seam_prewarms_the_mirror(w, pl, ring_w, cx, terrain)
		_check_dive_draft_spans_the_seam(w, pl, tile_w, cx)
		pl.global_position = Vector2(cx, pl.global_position.y)
		pl.velocity = Vector2.ZERO
	w.call("_dive_surge")
	var born := 0
	var armed := 0
	for sid in (w.get("_dive_surged") as Array):
		var picket := instance_from_id(sid) as Ship
		if picket == null or not is_instance_valid(picket) or picket.faction != 1:
			continue
		born += 1
		if picket.hull_integrity_max > 0.0:
			armed += 1
	_ok(born > 0, "a surge still garrisons the narrow world (%d pickets)" % born)
	_ok(armed == born, "...and every picket is born mortal (%d of %d)" % [armed, born])

	# THE ENEMY HULLS BREATHE THE SAME AIR (owner: "enemies drop so fast it's
	# not even funny"). The thin-air floor was stamped on the player's hull
	# alone; a picket's props were strangled by the real density and it simply
	# fell. The dive tick now stamps every listed VESSEL — give it a tick, then
	# every surged vessel must carry the same floor the player's hull gets, AND
	# the same rate-controlled stick (which is what replaced the pursuit's
	# velocity write — DESIGN_DIVE_REVIEW §2.2).
	for i in 3:
		await w.get_tree().physics_frame
	var floored := 0
	var sticked := 0
	var vessels := 0
	for sid in (w.get("_dive_surged") as Array):
		var hull := instance_from_id(sid) as Ship
		if hull == null or not is_instance_valid(hull) or hull.creature_kind != "":
			continue
		vessels += 1
		if is_equal_approx(hull.air_density_floor,
				Tunables.get_num("dive_air_floor")):
			floored += 1
		if hull.rate_control and is_equal_approx(hull.dive_rate_max,
				Tunables.get_num("dive_dive_rate") * 8.0):
			sticked += 1
	_ok(vessels > 0 and floored == vessels,
		"every surged vessel breathes the floored air (%d of %d)" % [floored, vessels])
	_ok(vessels > 0 and sticked == vessels,
		"...and flies the same rate-controlled stick you do (%d of %d)"
			% [sticked, vessels])
	# ...AND BREATHES THE SAME WEATHER (v0.141.0, DESCENT §0 call 7 "symmetric").
	# Every body the run put in the sky is stamped `extra_wind` for ITS OWN
	# position, so a picket in a downdraft rides it exactly as you do — the sky is
	# a place, not a debuff on the player. Checked against the world's own
	# `dive_weather_at`, which is the one site the model meets coordinates.
	# Stamped THIS instant, with nothing awaited between the stamp and the read:
	# a picket flies, and a hull that crossed a tile line since the last live tick
	# would honestly be carrying the weather of the tile it came from.
	w.call("_dive_weather", 0.0)
	var winded := 0
	var listed := 0
	var moved_one: Ship = null
	for sid in (w.get("_dive_surged") as Array):
		var hull2 := instance_from_id(sid) as Ship
		if hull2 == null or not is_instance_valid(hull2):
			continue
		listed += 1
		if hull2.extra_wind.is_equal_approx(
				w.call("dive_weather_for", hull2.global_position,
					w.call("dive_beta_of", hull2),
					DiveRun.key_depth(hull2.garrison_key))):
			winded += 1
		if moved_one == null and hull2.creature_kind == "":
			moved_one = hull2
	_ok(listed > 0 and winded == listed,
		"every listed hull feels the weather where IT is (%d of %d)" % [winded, listed])
	# ...and the same weather YOU do, when it is where you are. Stated separately
	# because "each body reads its own position" and "the two agree at one point"
	# are different bugs.
	if moved_one != null and pl != null and is_instance_valid(pl):
		moved_one.global_position = pl.global_position
		w.call("_dive_weather", 0.0)
		_ok(moved_one.extra_wind.is_equal_approx(
				w.call("dive_weather_for", pl.global_position,
					w.call("dive_beta_of", moved_one),
					DiveRun.key_depth(moved_one.garrison_key))),
			"an enemy hull at YOUR position feels your weather exactly (%s)"
				% moved_one.extra_wind)

	await _check_dive_garrison_materializes(w, pl, run, cx)
	# LAST, deliberately: this one runs six real seconds of world, which would
	# advance the run out from under the garrison checks above (they measure a
	# live world with nothing awaited between the set-up and the assertion).
	await _check_dive_picket_holds_its_rung(w, pl, cx)
	# THE DUNK, above the Leviathan on purpose: a picket spawn refuses a finished
	# run, and the check below is the whole of §5.1's sharp knowledge.
	await _check_the_dunk(w, pl, terrain)
	# THE SEAL, between them, and the order is load-bearing in both directions.
	# ABOVE the Leviathan because waking the boss ends the run in triumph and a
	# finished run has no live bands. BELOW the dunk because the dunk holds the
	# body in unbreathable air for twenty seconds and it comes out at 12 of 100
	# hp — the seal check ends by mending the person (its own toll would otherwise
	# be a debt), so running it here hands the Leviathan a WHOLE body instead of a
	# nearly dead one.
	print("    ~ post-dunk: outcome '%s', hp %.0f/%.0f, piloting %s, frac %.3f"
		% [String(run.get("outcome")), pl.health, pl.max_health,
			str(pl.is_piloting()), float(w.call("_player_altitude_frac"))])
	await _check_dive_seal(w, pl, run, terrain, cx)
	await _check_the_leviathan(w, pl, run, cx, terrain)
	# ...and after all of it: opening runs is destructive, so the seed check goes
	# last of all.
	await _check_dive_reseeds_the_ring(w, terrain)

	w.queue_free()
	await process_frame


## A FRESH SEED EACH RUN — THE GROUND, NOT JUST THE LADDER (owner 2026-08-30,
## built v0.154.0).
##
## `DiveRun.seed_v` has varied per run since v0.93.0, but it only moved the
## ladder's slalom, the outposts and the garrison: the ISLANDS came from
## `world_seed`, rolled once per boot, so two runs in one sitting flew the same
## sky. In the Dive's own scene the run's seed IS the world's now, and
## `begin_dive` re-seeds the ring whenever the two disagree.
##
## This check needs the dive-native 8× world and can live nowhere else — the
## legacy suite's world has no ring to re-seed, so it asserts the SHAPE half of
## the same ruling instead (`_check_dive_run_scope`).
func _check_dive_reseeds_the_ring(w: Node, terrain) -> void:
	print("\n--- A FRESH SEED EACH RUN: the ring is regenerated, not repositioned ---")
	if not w.has_method("begin_dive") or terrain == null:
		_ok(false, "a dive-native world to re-seed")
		return
	w.call("end_dive")
	w.call("begin_dive")
	await w.get_tree().physics_frame
	var run_a = w.get("dive")
	var seed_a: int = int(run_a.get("seed_v"))
	_ok(seed_a == int(w.get("world_seed")),
		"the run's seed IS the sky's, so there is one number to quote (%d)" % seed_a)
	var ground_a := await _ring_ground(w, terrain)

	# A MARK THE NEXT RUN MUST NOT INHERIT: one stone cell deep under the ring,
	# far below the burst of generation a new run fires around its launch deck.
	# If it survives, the wipe did not happen and the "new" sky is the old one
	# with fresh stamps on top of it.
	var deep: Vector2 = w.call("dive_landing_pos", 1)
	deep.y = w.call("dive_altitude_y", DiveRun.depth_altitude(6))
	var mark: Vector2i = terrain.world_to_cell(deep)
	terrain.set_cell(mark, TerrainDB.Type.STONE)
	_ok(terrain.is_solid(mark), "a mark is planted in the run's ground")

	w.call("begin_dive")
	await w.get_tree().physics_frame
	var seed_b: int = int((w.get("dive") as Object).get("seed_v"))
	var status: Dictionary = w.call("dive_status")
	_ok(seed_b != seed_a,
		"the next run rolls a different seed (%d -> %d)" % [seed_a, seed_b])
	_ok(int(w.get("world_seed")) == seed_b, "...and the sky is re-seeded with it")
	_ok(not terrain.is_solid(mark),
		"...the previous run's ground is GONE, not built over")
	var diff_b := _ring_diff(await _ring_ground(w, terrain), ground_a)
	_ok(int(diff_b[0]) >= 4 and int(diff_b[1]) > 0,
		"...so the islands a run flies through are a different set (%d of %d shared GROUND chunks changed)"
			% [int(diff_b[1]), int(diff_b[0])])
	_ok(DiveRun.garrison_all(seed_a, 3.0).hash()
			!= DiveRun.garrison_all(seed_b, 3.0).hash(),
		"...with a different garrison standing in it")
	# THE HITCH. Re-seeding is a wipe, a prime and ONE bounded burst around the
	# deck; everything else streams in the way it does at boot. Measured at
	# 2-3 ms on the owner's machine (`tools/dive_seed_probe.gd`), and the bound
	# here is loose on purpose — what it guards against is somebody putting an
	# EAGER world generation back in front of the word "dive".
	var ms := float(status.get("regen_ms", -1.0))
	_ok(ms > 0.0, "re-seeding is what happened, and the run says so (%.1f ms)" % ms)
	_ok(ms < 250.0, "...and it costs a fraction of a second, not a loading screen")

	# THE PIN: the same sky twice, which is the only way a change can be A/B'd
	# against one dive (and what `dive_probe --seed N` exists for).
	w.call("pin_dive_seed", seed_a)
	w.call("begin_dive")
	await w.get_tree().physics_frame
	_ok(int((w.get("dive") as Object).get("seed_v")) == seed_a
			and int(w.get("world_seed")) == seed_a,
		"a pinned seed re-opens that run's sky")
	# ...AND THE GROUND IS THE SAME GROUND, chunk by chunk over everything both
	# readings hold. The shared count is asserted too, so a pin that happened to
	# leave nothing loaded cannot pass this by comparing an empty set.
	#
	# NOT "ZERO DISAGREE", and the allowance is named rather than fudged: an
	# island is painted as a lattice REGION, so a chunk on the EDGE of what has
	# been generated is finished in the reading that streamed past it and
	# half-painted in the one that stopped there. Two readings of the same seed
	# differ there with nothing wrong (measured: 2 of 94). Filtering those out by
	# requiring four resident neighbours was tried and starves the sample to
	# nothing, so the claim is stated as what it is — the same ground everywhere
	# but the generation frontier, over a sample big enough to mean it.
	var diff_c := _ring_diff(await _ring_ground(w, terrain), ground_a)
	_ok(int(diff_c[0]) >= 32 and int(diff_c[1]) * 10 <= int(diff_c[0]),
		"...with the same islands in the same places, cell for cell (%d shared GROUND chunks, %d disagree at the generation frontier)"
			% [int(diff_c[0]), int(diff_c[1])])
	w.call("end_dive")
	await w.get_tree().physics_frame


## WHAT THE GROUND ACTUALLY IS, PER PLACE: {chunk coord -> hash of that chunk's
## cells}. Sampling cells around the launch deck was tried first and is worthless
## — depth 1 sits in the ring's updraft column, which the generator deliberately
## keeps clear, so every seed fingerprints as the same empty air.
##
## PER CHUNK, AND NOT ONE NUMBER FOR THE WHOLE SKY, because the sky is STREAMED.
## The first shape of this was `hash([resident chunk coords, total_solid_cells])`,
## and that fingerprints the STREAMER as much as the ground: the same seed,
## re-pinned, reported "123 chunks / 68,420 solid" against the original's "92 /
## 53,108" — identical ground, more of it loaded, because two dives and a flight
## across the ring had happened in between. Any check that flies further than the
## one that wrote it would have failed it, which is how this was found. Comparing
## chunk BY chunk, over the ones both readings hold, is the claim the check
## actually makes: the same islands, in the same places, cell for cell.
## A reading of the run's ISLANDS, taken at the same places every time.
##
## THE FINGERPRINT ALONE IS NOT ENOUGH, and the reason is the sharpest thing this
## check knows: one physics frame after `begin_dive`, the only ground loaded is
## the burst around the LAUNCH DECK — and the deck is a stamped shelf, identical
## under every seed. Comparing two runs there compares the one part of the sky
## that cannot differ. Measured: a fresh seed changed **0 of 56 shared ground
## chunks**, and the check passed anyway for years' worth of rounds, because the
## signature it used also hashed which chunks happened to be RESIDENT and that
## always moved. So each reading first STREAMS THE SAME FIXED DEEP PLACES —
## seed-independent world coordinates, three rungs' worth, well off the deck —
## and only then fingerprints. Now "a different set of islands" is a claim about
## islands: it went from 0 of 56 shared ground chunks changed to 6 of 62.
const RING_PROBE_PX := 14000.0


func _ring_ground(w: Node, terrain) -> Dictionary:
	var x0: float = (w.call("dive_landing_pos", 1) as Vector2).x
	# FIVE SPOTS, not three: the sample has to be wide enough that "a different
	# seed moved the islands" cannot come down to a couple of chunks. Three gave
	# 2 of 58 changed on one boot, which is true but is one unlucky seed away
	# from a check that reports nothing.
	var spots := [
		Vector2(x0 + 60000.0, w.call("dive_altitude_y", DiveRun.depth_altitude(2))),
		Vector2(x0 - 60000.0, w.call("dive_altitude_y", DiveRun.depth_altitude(3))),
		Vector2(x0 + 30000.0, w.call("dive_altitude_y", DiveRun.depth_altitude(4))),
		Vector2(x0 - 30000.0, w.call("dive_altitude_y", DiveRun.depth_altitude(5))),
		Vector2(x0 + 90000.0, w.call("dive_altitude_y", DiveRun.depth_altitude(6))),
	]
	# GENERATE, THEN STREAM, and in that order — draining alone was the third
	# thing this helper got wrong. `update_streaming` only makes RESIDENT what has
	# already been PAINTED: it loads regions, it does not create them. Five deep
	# drains therefore added nothing an unvisited sky had not already got, and the
	# reading stayed the deck's (measured: still 56 shared ground chunks, 0
	# changed, exactly the deck-only number). `IslandGen.ensure_generated` is what
	# paints, and it is budgeted per call, so it is called until it stops making
	# anything — the same idiom the picket check uses to guarantee itself clear
	# air (DECISIONS 2026-08-30: generate first, and only then touch the ground).
	var seed_now := int(w.get("world_seed"))
	for pass_i in 40:
		if IslandGen.ensure_generated(terrain, seed_now, spots, RING_PROBE_PX, 24) == 0:
			break
		if pass_i % 8 == 7:
			await process_frame
	for spot in spots:
		await _drain_streaming(terrain, RING_PROBE_PX, spot, RING_PROBE_PX)
	return _ring_fingerprint(terrain)


func _ring_fingerprint(terrain) -> Dictionary:
	var out := {}
	for c in (terrain.chunk_coords() as Array):
		var bytes := terrain.chunk_bytes(c as Vector2i) as PackedByteArray
		var solid := 0
		for b in bytes:
			if b != 0:   # TerrainDB.Type.AIR is 0 and must stay 0 (terrain_db.gd)
				solid += 1
		out[c as Vector2i] = [hash(bytes), solid]
	return out


## Compare two fingerprints over the chunks they BOTH hold **that actually
## contain ground**, as [shared chunks with ground, how many of those disagree].
##
## THE "WITH GROUND" IS THE WHOLE POINT. Most of a dive sky is air, and an air
## chunk is byte-identical under every seed — so comparing all shared chunks
## answers "is the sky still mostly empty" (yes, always) instead of "is this a
## different set of islands". Measured while rewriting this: a fresh seed left
## `0 of 56 shared chunks changed`, and all 56 were empty. The old signature hid
## that behind a residency term that happened to differ, which is to say it
## passed the "a new run is a new sky" claim for the wrong reason.
func _ring_diff(a: Dictionary, b: Dictionary) -> Array:
	var shared := 0
	var differ := 0
	for k in a:
		if not b.has(k):
			continue
		var ra := a[k] as Array
		var rb := b[k] as Array
		if int(ra[1]) == 0 and int(rb[1]) == 0:
			continue   # air on both sides — identical under every seed
		shared += 1
		if int(ra[0]) != int(rb[0]):
			differ += 1
	return [shared, differ]




## THE DUNK (DESIGN_KRAKEN §5.1, measured by `tools/dunk_probe.gd`, v0.148.0).
##
## The design's headline piece of sharp knowledge is a claim about SHIPPED code:
## a kraken is held up by muscle alone, your lift props blow down, so hovering
## over one where there is no roof sinks it into the core. Nothing had ever run
## it. The probe did, and the numbers are the reason this check is shaped the
## way it is:
##
##   * THE JET IS SHORT AND IT IS SAMPLED AT THE PREY'S ORIGIN. 8 cells =
##     1,024 px from the prop's centre (`Ship.WASH_RANGE_CELLS`), and
##     `world._apply_prop_wash` asks `body.global_position` — half a body BELOW
##     its own back. On the shipped starter that leaves ~440 px of clear air at
##     0.32 g and ~240 px at 0.84 g. You hover almost ON it, or not at all.
##   * SO THE DUNK IS A RIDE, NOT A SHOVE. The animal falls out of the jet in
##     under a second, and getting it back means diving after it — during which
##     the props blow the other way (`wash_accel_at` reads the stick's sign), so
##     the jet is off. The measured descent is a stutter at ~1,200 px/s, which is
##     under the hull's own 1,920 px/s dive rate. It is 3–6 s of committed
##     hovering per ~5,000 px, exactly what §5.1 asked for, and it is nowhere
##     near instant — so `wash_push_mult` was NOT turned down (see the report).
##   * AND THE ROOF ANSWERS IT. Over the den's slab the jet never reaches the
##     boss at all.
##
## The pilot here is a stick, not a teleport: the hull flies the same rate
## controller the run stamps on every listed hull, and the only input is the
## neutral/down toggle a chasing player makes. The bound is twice the measured
## time — tight enough to catch the jet going flat, loose enough to survive a
## tuning pass.
const DUNK_DROP_PX := 6000.0     ## how much air the prey starts with over the core
const DUNK_BOUND_SECONDS := 18.0 ## 2x the measured 8.2 s over that drop
const DUNK_KEEP_OFF := 350.0     ## clear air the chase refuses to close (a crash is not a hover)


func _check_the_dunk(w: Node, pl, terrain) -> void:
	if pl == null or not is_instance_valid(pl) or terrain == null:
		return
	print("\n=== the dunk: a hunter under a hovering starter (8x) ===\n")
	# STILL AIR AND A STILL ANIMAL. The ring's up/down draft lifts a hull AND a
	# kraken (v0.141.0's one-vector doctrine — measured carrying both upward at
	# ~3,600 px/s at the floor), and a hunting kraken heaves away. Both are real,
	# and both are somebody else's measurement: this one is muscle-versus-jet.
	Tunables.set_value("dive_zone_wind_mult", 0.0)
	Tunables.set_value("whale_push_accel", 0.0)
	Tunables.set_value("whale_align_accel", 0.0)
	Tunables.set_value("kraken_wildness", 0.0)
	var lava: float = LavaCore.surface_y_for(w.get("_world_rect") as Rect2,
		float((w.get("_lava_core") as Node).get("top_frac")))
	var at := await _open_air(w, terrain, pl, Vector2(
		pl.global_position.x + 14000.0, lava - DUNK_DROP_PX))
	# THE BODY IS OUT OF THIS. Twenty seconds of world run below, and the deep
	# has no floor but the core — so the person is held far above and aside for
	# the duration and put back afterwards. (The run ends in LOSS otherwise, and
	# the Leviathan's own check, which follows, has nothing left to win.)
	var body_was: Vector2 = pl.global_position
	var body_safe := Vector2(at.x - 30000.0, lava - 60000.0)
	_hold_body(pl, body_safe)
	# ONE BODY PLAN, PINNED. `_dive_spawn_picket("kraken")` rolls one of five
	# varieties per boot, and a different silhouette puts the origin the wash is
	# sampled at a different distance under the jet — the check read 7.2 s on one
	# plan and NEVER on another in the same merged suite. The dunk is a claim
	# about the jet versus muscle, not about which kraken you met, so it is
	# measured on the ammonite; the variety spread is the dunk probe's job.
	var beast: Ship = w.call("_spawn_one_kraken", "res://ships/kraken_c.ship", at)
	if beast != null and is_instance_valid(beast):
		(w.get("_dive_surged") as Array).append(beast.get_instance_id())
	_ok(beast != null and is_instance_valid(beast), "a hunter is at the floor over open lava")
	if beast == null or not is_instance_valid(beast):
		return _reset_dunk_levers()
	for i in 60:
		await w.get_tree().physics_frame
		_hold_body(pl, body_safe)
		if not is_instance_valid(beast):
			break
	if not is_instance_valid(beast):
		_ok(false, "...and it survived long enough to be dunked")
		return _reset_dunk_levers()
	beast.linear_velocity = Vector2.ZERO
	var drop: float = lava - (beast.global_position.y + beast.solid_bounds.end.y)
	_ok(drop > 1000.0, "it holds the deep by MUSCLE, %.0f px of air under its keel" % drop)

	# The hull: the shipped starter, flying the run's own rate controller (the
	# world stamps that on everything in `_dive_surged`, so listing it is all
	# this needs).
	var hull: Ship = w.get("fleet").call("spawn_ship_from_cells",
		ShipLayout.upscale_cells(ShipLayout.load_cells("res://ships/starter.ship"), 8),
		beast.global_position + Vector2(0.0, -6000.0), 0, 0.0,
		float(w.get("world_scale")), 0)
	_ok(hull != null and is_instance_valid(hull), "a starter is above it")
	if hull == null or not is_instance_valid(hull):
		return _reset_dunk_levers()
	(w.get("_dive_surged") as Array).append(hull.get_instance_id())
	await w.get_tree().physics_frame
	var prop := Vector2.ZERO
	for p in (hull.get("_wash_props") as Array):
		if bool((p as Dictionary)["vertical"]):
			prop = (p as Dictionary)["center"] as Vector2
			break
	_ok(prop != Vector2.ZERO, "...with lift props to blow with")
	# Park a prop 700 px down its own jet — 0.84 g at the prey's origin, and
	# ~240 px of clear air. "Directly above it" means above a PROP: the wash is
	# rejected outside a prop's own width band.
	hull.global_position = Vector2(beast.global_position.x - prop.x,
		beast.global_position.y - 700.0 - prop.y)
	hull.linear_velocity = Vector2.ZERO
	hull.thrust_input = Vector2.ZERO
	await w.get_tree().physics_frame

	var t := 0.0
	var eaten := false
	var jet_frames := 0
	var chasing := 0.0
	for i in int(DUNK_BOUND_SECONDS * 60.0):
		if not is_instance_valid(beast) or not is_instance_valid(hull):
			break
		# THE STICK, and nothing else: neutral is the hover (which IS the
		# downwash), DOWN is the chase. Written every frame because the run
		# stamps the rest of the flight envelope every frame too.
		var air: float = (beast.global_position.y + beast.solid_bounds.position.y) \
			- (hull.global_position.y + hull.solid_bounds.end.y)
		hull.thrust_input = Vector2(0.0, -1.0 if air > DUNK_KEEP_OFF else 0.0)
		if air > DUNK_KEEP_OFF:
			chasing += 1.0 / 60.0
		# Counted AT THE SAMPLE POINT the sweep itself uses — the animal's back
		# since the sample-point fix, not its origin — or the instrumentation
		# reports a jet the physics is not applying (it read 7 frames of 1,080
		# while the dunk was working).
		if hull.wash_accel_at(beast.wash_sample_toward(
				hull.nearest_wash_prop(beast.global_position))) != Vector2.ZERO:
			jet_frames += 1
		await w.get_tree().physics_frame
		_hold_body(pl, body_safe)
		t += 1.0 / 60.0
		if not is_instance_valid(beast):
			eaten = true
			break
		if LavaCore.is_in_core(w.get("_world_rect") as Rect2,
				float((w.get("_lava_core") as Node).get("top_frac")),
				beast.global_position.y + beast.solid_bounds.end.y):
			eaten = true
			break
	if is_instance_valid(hull):
		hull.thrust_input = Vector2.ZERO
	print("    ~ the dunk: %.1f s over %.0f px (%.0f px/s), %d frames of jet, %.1f s of chasing"
		% [t, drop, drop / maxf(t, 0.001), jet_frames, chasing])
	_ok(eaten and t <= DUNK_BOUND_SECONDS,
		"a hunter under a hovering starter sinks into the core in %s (bound %.0f s)"
			% [("%.1f s" % t) if eaten else "NEVER", DUNK_BOUND_SECONDS])
	_ok(t >= 1.0,
		"...and it is never instant — the design's committed hovering, not a button (%.1f s)" % t)
	if is_instance_valid(beast):
		beast.queue_free()
	if is_instance_valid(hull):
		(w.get("_dive_surged") as Array).erase(hull.get_instance_id())
		hull.queue_free()
	_reset_dunk_levers()
	pl.global_position = body_was
	pl.velocity = Vector2.ZERO
	await w.get_tree().physics_frame


## Every live scrap mote's value, summed.
func _scrap_value(field) -> int:
	var total := 0
	if field == null:
		return total
	for m in (field.call("active") as Array):
		total += int(m["value"])
	return total


## Keep the person out of the measurement (and out of the core).
func _hold_body(pl, at: Vector2) -> void:
	if pl != null and is_instance_valid(pl):
		pl.global_position = at
		pl.velocity = Vector2.ZERO


func _reset_dunk_levers() -> void:
	Tunables.reset("dive_zone_wind_mult")
	Tunables.reset("whale_push_accel")
	Tunables.reset("whale_align_accel")
	Tunables.reset("kraken_wildness")


## A point near `want` with a genuinely EMPTY column around it. The deep still
## has islands in it, and a body teleported into one is fired out at 14,000 px/s
## (measured — the probe reported that ejection as a dunk for one run). The
## player is moved to each candidate first, because an ungenerated chunk answers
## "not solid" to everything.
func _open_air(w: Node, terrain, pl, want: Vector2) -> Vector2:
	for step in 12:
		var at := want + Vector2(float(step) * 9000.0, 0.0)
		# Streamed by draining the streamer AT the candidate rather than by
		# standing the player there: the deep has no ground, and a body parked
		# over the core for the seconds this takes simply falls into it (which
		# is how this check first reported the run as LOST).
		await _drain_streaming(terrain, 9000.0, at, 9000.0)
		var clear := true
		for dx in [-3000.0, -1500.0, 0.0, 1500.0, 3000.0]:
			for dy in [-8000.0, -6000.0, -4000.0, -2000.0, 0.0, 2000.0]:
				if bool(terrain.call("is_solid",
						terrain.call("world_to_cell", at + Vector2(dx, dy)))):
					clear = false
					break
			if not clear:
				break
		if clear:
			return at
	return want


## THE FLOOR HAS A KRAKEN, AND KILLING IT WINS (DESIGN_KRAKEN §7 slice 1).
##
## Here rather than in the 1× suite because every claim below is 8× GEOMETRY —
## the den's altitude against the lava, a 6,656-px body, a roof measured in body
## widths, and a hull dropped onto it (CODEMAP: `solid_bounds` is already world
## px, and the legacy suite cannot see an eightfold error).
##
## Five things, in the order the round built them: the body, its collider against
## the authored crown (judge 1's risk 2 — a boxed crown would delete the maw's
## 1.6-cell shelter margin), the ROOF, the cull's exemption, and the WIN.
func _check_the_leviathan(w: Node, pl, run, cx: float, terrain) -> void:
	if pl == null or not is_instance_valid(pl) or run == null or terrain == null:
		return
	var floor_y: float = w.call("dive_altitude_y",
		DiveRun.depth_altitude(DiveRun.DEPTHS))
	run.set("depth", DiveRun.DEPTHS)
	run.set("deepest", DiveRun.DEPTHS)
	pl.global_position = Vector2(cx, floor_y)
	pl.velocity = Vector2.ZERO
	await w.get_tree().physics_frame

	# --- 1. THE BODY -------------------------------------------------------
	w.call("_dive_wake_leviathan")
	var boss: Ship = null
	for sid in (w.get("_dive_surged") as Array):
		var s := instance_from_id(sid) as Ship
		if s != null and is_instance_valid(s) and s.creature_kind == "kraken_leviathan":
			boss = s
	_ok(boss != null, "waking the floor spawns a kraken_leviathan, not a city-whale")
	if boss == null:
		return
	_ok(is_equal_approx(boss.shared_health_max, 3600.0),
		"its pool is the file's own `health 3600` (%.0f)" % boss.shared_health_max)
	_ok(boss.tame_level == 9,
		"`tame 9` puts it above the perk ceiling — untameable (%d)" % boss.tame_level)
	_ok(boss.bounty == 900, "`bounty 900` rides on the body (%d)" % boss.bounty)
	_ok(boss.variety == "kraken_leviathan", "...and the bestiary tag came off the path")
	_ok(w.call("_whale_ai_for", boss) is KrakenAI,
		"its kind chose the KRAKEN brain (ram + mouth grab), not a whale's")
	_ok(bool(w.call("_dive_is_the_boss", boss)),
		"the ONE predicate reads it as the run's destination")
	_ok(String(w.call("_edge_marker_kind", boss)) == "boss",
		"...so it wears the crown marker")
	var stand_in := false
	for s2 in (w.get("fleet").call("ships") as Array):
		if is_instance_valid(s2) and (s2 as Ship).creature_kind == "whale_city":
			stand_in = true
	_ok(not stand_in, "and no city-whale stand-in was spawned into the run")

	var bounds: Rect2 = boss.solid_bounds
	print("    ~ the Leviathan: %d blocks, solid_bounds %.0f x %.0f px"
		% [boss.blocks.size(), bounds.size.x, bounds.size.y])
	_ok(absf(boss.global_position.x - cx) < bounds.size.x,
		"it comes up at YOUR x (%.0f px off the line)" % absf(boss.global_position.x - cx))
	var lava_y: float = LavaCore.surface_y_for(w.get("_world_rect") as Rect2,
		float((w.get("_lava_core") as Node).get("top_frac")))
	var keel := boss.global_position.y + bounds.end.y
	_ok(keel < lava_y,
		"the den keeps it out of the core, with %.0f px of clear air under its keel"
			% (lava_y - keel))
	# THE BODY STANDS CLEAR. Since v0.147.0 the boss HUNTS — it leads your line
	# and heaves with a vertical share — and a kraken's mouth chews an on-foot
	# body at 120 hp/s (KrakenAI.prey_player). This check is PLUMBING (identity,
	# the roof, the cull, the win), not the fight: the body watches from a rung
	# up and far to one side, or the run is lost to a grab before step 5 asks
	# whether killing the boss wins it. The fight itself is measured by
	# `_check_the_heave_catches_a_diving_hull` and by `tools/dive_probe.gd`.
	var stand_off := absf(float(w.call("dive_altitude_y", DiveRun.depth_altitude(2)))
		- float(w.call("dive_altitude_y", DiveRun.depth_altitude(1))))
	pl.global_position = Vector2(cx + 20000.0, floor_y - stand_off)
	pl.velocity = Vector2.ZERO

	# --- 2. THE COLLIDER AGAINST THE AUTHORED CROWN -------------------------
	# The crown is 72 authored MEAT cells in the trailing twelve columns (4,608
	# blocks at 8×), and D's whole risk/reward rests on them being reachable —
	# both as the thing that grabs you and as the thing you shoot. A living
	# creature collides off DOWNSAMPLED super-cells (`creature_coarse_cells`), so
	# this asks the collider itself rather than the grid.
	var rects: Array = boss.call("_coarse_creature_rects")
	var xmin := 1 << 30
	for cell in boss.blocks:
		xmin = mini(xmin, (cell as Vector2i).x)
	var crown_x := xmin + 12 * 8      # the trailing twelve AUTHORED columns, at 8×
	var arms: Array[Vector2i] = []
	for cell in boss.blocks:
		var c := cell as Vector2i
		if c.x < crown_x and int(boss.blocks[c]["type"]) == BlockDB.Type.MEAT:
			arms.append(c)
	var uncovered: Array[Vector2i] = []
	for c in arms:
		var hit := false
		for r in rects:
			if (r as Rect2i).has_point(c):
				hit = true
				break
		if not hit:
			uncovered.append(c)
	_ok(arms.size() == 72 * 64,
		"the crown is the authored 72 cells, upscaled (%d blocks)" % arms.size())
	_ok(uncovered.is_empty(),
		"every arm block is inside the living collider (%d boxes, %d arm blocks%s)"
			% [rects.size(), arms.size(), "" if uncovered.is_empty()
				else " — MISSED %d, first at %s" % [uncovered.size(), uncovered[0]]])
	# ...and the OTHER half of judge 1's risk, as a measurement rather than an
	# assertion: how much EMPTY air inside the crown's own footprint the boxes
	# swallow. 0 % is a crown you can fly between; 100 % is a slab.
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in arms:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var air := 0
	var boxed := 0
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c2 := Vector2i(x, y)
			if boss.blocks.has(c2):
				continue
			air += 1
			for r in rects:
				if (r as Rect2i).has_point(c2):
					boxed += 1
					break
	print("    ~ the crown's footprint: %d air blocks, %d boxed by the coarse collider (%.1f%%)"
		% [air, boxed, 100.0 * float(boxed) / maxf(1.0, float(air))])

	# --- 3. THE ROOF -------------------------------------------------------
	var roof: Rect2 = w.get("_dive_den_roof")
	_ok(roof.size.x > 0.0, "waking it cut a roof over the den")
	if roof.size.x <= 0.0:
		return
	print("    ~ the den's roof: %.0f x %.0f px at (%.0f, %.0f)"
		% [roof.size.x, roof.size.y, roof.position.x, roof.position.y])
	_ok(roof.size.x >= bounds.size.x * 2.0,
		"it is at least two body widths (%.0f px vs %.0f)"
			% [roof.size.x, bounds.size.x * 2.0])
	var cpx: float = terrain.call("cell_px")
	_ok(roof.size.y >= 4.0 * cpx,
		"...and at least four terrain cells thick, so nothing tunnels (%.0f px, cell %.0f)"
			% [roof.size.y, cpx])
	var body_top := boss.global_position.y + bounds.position.y
	_ok(roof.end.y <= body_top,
		"its underside is ABOVE the body (%.0f px of headroom)" % (body_top - roof.end.y))
	# REAL STONE, all the way across — five samples through the middle of the slab.
	var stone := 0
	for i in 5:
		var at := Vector2(roof.position.x + roof.size.x * (0.1 + 0.2 * float(i)),
			roof.get_center().y)
		if bool(terrain.call("is_solid", terrain.call("world_to_cell", at))):
			stone += 1
	_ok(stone == 5, "the slab is real terrain across its width (%d/5 samples)" % stone)
	# ...and the LAVA IS OPEN EITHER SIDE (owner call 2: no walls, or phase 3 is
	# a siege). One body width out from each end, at the body's own altitude.
	var open_sides := 0
	for dir in [-1.0, 1.0]:
		var at2 := Vector2(roof.get_center().x
			+ dir * (roof.size.x * 0.5 + bounds.size.x), boss.global_position.y)
		if not bool(terrain.call("is_solid", terrain.call("world_to_cell", at2))):
			open_sides += 1
	_ok(open_sides == 2, "and the sky is open on both flanks (%d/2)" % open_sides)

	# A HULL DROPPED ON THE DEN LANDS ON THE ROOF, not on the boss — which is the
	# whole point of it (a falling husk was killing the fight by accident).
	await _drain_streaming(terrain, roof.size.x, roof.get_center(), roof.size.x)
	var drop_cells := {}
	for x in 8:
		for y in 8:
			drop_cells[Vector2i(x, y)] = BlockDB.Type.HULL
	var drop_at := Vector2(roof.get_center().x, roof.position.y - 2000.0)
	var husk: Ship = w.get("fleet").call("spawn_ship_from_cells",
		drop_cells, drop_at, 0, 0.0, float(w.get("world_scale")), 0)
	_ok(husk != null, "a hull is dropped over the den")
	if husk != null:
		var settled := 0
		for i in 600:
			await w.get_tree().physics_frame
			if not is_instance_valid(husk):
				break
			if absf(husk.linear_velocity.y) < 20.0:
				settled += 1
				if settled > 30:
					break
			else:
				settled = 0
		if is_instance_valid(husk):
			var rested := husk.global_position.y + husk.solid_bounds.end.y
			_ok(rested <= roof.end.y + 4.0 * cpx,
				"...and it comes to rest ON the roof (keel %.0f, slab %.0f..%.0f)"
					% [rested, roof.position.y, roof.end.y])
			_ok(rested < body_top,
				"...never on the boss (%.0f px above its back)" % (body_top - rested))
			husk.queue_free()
		else:
			_ok(false, "...and it fell straight through the roof into the core")
		await w.get_tree().physics_frame

	# --- 4. THE CULL KEEPS IT ----------------------------------------------
	# A rung and a half is the wake's leash; the boss is the run's DESTINATION and
	# is never litter, however far you climb. Proved against a picket at the same
	# distance, which IS litter — otherwise the exemption could be doing nothing.
	var rung := absf(float(w.call("dive_altitude_y", DiveRun.depth_altitude(2)))
		- float(w.call("dive_altitude_y", DiveRun.depth_altitude(1))))
	var high: Vector2 = pl.global_position + Vector2(0.0, -2.0 * rung)
	boss.global_position = high
	var decoy = w.call("_dive_spawn_picket", "hulk", high + Vector2(4000.0, 0.0))
	var decoy_id: int = decoy.get_instance_id() if decoy != null else 0
	w.call("_dive_cull_the_wake", 2.0)
	var surged: Array = w.get("_dive_surged") as Array
	_ok(surged.has(boss.get_instance_id()),
		"the cull keeps the boss two rungs away (%.0f px, leash %.0f)"
			% [2.0 * rung, 1.5 * rung])
	_ok(decoy_id == 0 or not surged.has(decoy_id),
		"...and freed an ordinary VESSEL picket at the same distance (the exemption is real)")
	# AND NO LIVING HUNTER IS EVER CULLED (DESIGN_KRAKEN §1.4 / DESCENT call 4).
	# The pair is the point: a live kraken two rungs off is still coming for you;
	# its CARCASS at the same distance is litter like any other.
	var live_kraken = w.call("_dive_spawn_picket", "kraken",
		high + Vector2(-7000.0, 0.0))
	var dead_kraken = w.call("_dive_spawn_picket", "kraken",
		high + Vector2(-14000.0, 0.0))
	var dead_id: int = dead_kraken.get_instance_id() if dead_kraken != null else 0
	if dead_kraken != null:
		dead_kraken.shared_health = 0.0
		dead_kraken.rebuild()
	w.call("_dive_cull_the_wake", 2.0)
	surged = w.get("_dive_surged") as Array
	if live_kraken != null and is_instance_valid(live_kraken):
		_ok(surged.has(live_kraken.get_instance_id()),
			"a LIVING kraken two rungs off is never culled (%s)" % live_kraken.variety)
	else:
		_ok(false, "a LIVING kraken two rungs off is never culled")
	# `queue_free` is deferred, so the honest question is whether the cull
	# STRUCK it off the run's books — not whether the node is gone this frame.
	_ok(dead_id == 0 or not surged.has(dead_id),
		"...and its carcass at the same distance IS litter")
	if live_kraken != null and is_instance_valid(live_kraken):
		live_kraken.queue_free()
	boss.global_position = Vector2(cx, floor_y)
	await w.get_tree().physics_frame

	# --- 4b. THE BREATH ----------------------------------------------------
	await _check_the_breath(w, pl, boss, roof, cpx)

	# --- 5. THE WIN --------------------------------------------------------
	# Through the REAL damage path: `damage_cell` is what a shell calls, it is
	# what drains a living creature's shared pool, and it is what emits
	# `creature_perished` — the signal the triumph now hangs off.
	var wallet = pl.get("wallet")
	var wallet_before: int = int(wallet.get("balance")) if wallet != null else 0
	var pot_before: int = int(run.get("pot"))
	_ok(String(run.get("outcome")) == "",
		"the run is still live before the kill (outcome '%s')" % String(run.get("outcome")))
	# ON THE THROAT. Since v0.147.0 a shot on SHELL drains the pool at a quarter
	# (`creature_shell_resist`) — the design's whole point — so a kill has to land
	# on MEAT, exactly as a player's must. The first meat cell in the grid will do:
	# the pool is one number, and which meat cell takes the hit does not matter.
	var meat_cell: Vector2i = boss.blocks.keys()[0]
	for c in boss.blocks:
		if int(boss.blocks[c]["type"]) == BlockDB.Type.MEAT:
			meat_cell = c
			break
	# THE HOARD (DESIGN_KRAKEN §4, v0.148.0). A dead kraken's SEALED CAVITY —
	# the loot pocket every plan is drawn with, latched at spawn — spills a
	# SECOND scrap cloud worth `kraken_hoard_mult` × the kill's own, hanging at
	# the cavity rather than at the body's origin. Measured off the field's own
	# motes, because that is where the reward actually is.
	var field = w.get("_dive_scrap")
	var scrap_before := _scrap_value(field)
	var cavity: Dictionary = boss.cavity_cells()
	var hoard_at := Vector2.ZERO
	for cell in cavity:
		hoard_at += boss.local_pos_of(cell as Vector2i)
	hoard_at = boss.to_global(boss._mirror_point(hoard_at / maxf(float(cavity.size()), 1.0)))
	_ok(not cavity.is_empty(),
		"the boss carries a sealed cavity to spill (%d cells)" % cavity.size())
	boss.damage_cell(meat_cell, boss.shared_health_max + 1.0)
	await w.get_tree().physics_frame
	var base: int = DiveRun.scrap_for("kraken_leviathan", int(run.get("depth")), 900)
	var want: int = base + int(round(float(base) * Tunables.get_num("kraken_hoard_mult")))
	_ok(_scrap_value(field) - scrap_before == want,
		"death drops the kill's scrap AND a %.1fx hoard (%d + %d = %d, got %d)"
			% [Tunables.get_num("kraken_hoard_mult"), base, want - base, want,
				_scrap_value(field) - scrap_before])
	var near := INF
	for m in (field.call("active") as Array):
		near = minf(near, (m["pos"] as Vector2).distance_to(hoard_at))
	_ok(near < ScrapField.SPREAD_PX * float(w.get("world_scale")) * 2.0,
		"...and the second cloud hangs at the CAVITY, not at the body's origin (%.0f px off)"
			% near)
	_ok(String(run.get("outcome")) == "triumph",
		"killing it ends the run in TRIUMPH (outcome '%s')" % String(run.get("outcome")))
	_ok(int(run.get("banked")) > 0,
		"...and the pot is BANKED at the floor's premium plus the bonus (%d, pot was %d)"
			% [int(run.get("banked")), pot_before])
	_ok(int(run.get("banked")) >= DiveRun.TRIUMPH_BONUS,
		"...which is never less than TRIUMPH_BONUS itself (%d)" % DiveRun.TRIUMPH_BONUS)
	if wallet != null:
		_ok(int(wallet.get("balance")) > wallet_before,
			"...and it reached the permanent wallet (%d -> %d)"
				% [wallet_before, int(wallet.get("balance"))])


## THE BREATH, MEASURED ON THE REAL HULL (DESIGN_KRAKEN §7 slice 6; acceptance:
## "stick authority inside the breath ≥ 25 %").
##
## `run_tests._test_the_breath` pins the model — the phases, the tell, the field,
## the compose rule and the arithmetic of the acceptance. This is the half that
## can only be answered at 8× with the shipped starter: what a FULL CLIMB
## actually buys you inside a full inhale, through the rate controller, the air
## density floor and the drag, none of which the arithmetic knows about.
##
## Everything the fight would otherwise contribute is levered off — the ring's
## draft, the heave, the align, the wander and the grab — because a hull being
## rammed measures a wrestle, and the wrestle is `tools/dive_probe.gd`'s job.
func _check_the_breath(w: Node, pl, boss: Ship, roof: Rect2, cpx: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	print("\n    ~ THE BREATH (slice 6) ~")
	# THE RUN HAS TO BE LIVE OR NONE OF THIS MEANS ANYTHING. `_tick_dive` returns
	# on the first line when `outcome != ""`, so a run that ended earlier in this
	# check stops stamping weather entirely and EVERY field reading below comes
	# back 0 — six failures that all say "the breath does not blow" and none that
	# say why. Named here so the cascade can never be mistaken for the model.
	var run_now = w.get("dive")
	_ok(run_now != null and String(run_now.get("outcome")) == "",
		"the run is live when the breath is measured (outcome '%s')"
			% (String(run_now.get("outcome")) if run_now != null else "no run"))
	var ai = w.call("_whale_ai_for", boss)
	_ok(ai is KrakenAI and bool(ai.get("breathes")),
		"the floor's resident is armed to breathe (an ordinary hunter is not)")
	if not (ai is KrakenAI):
		return
	var kai := ai as KrakenAI
	Tunables.set_value("dive_zone_wind_mult", 0.0)
	Tunables.set_value("whale_push_accel", 0.0)
	Tunables.set_value("whale_align_accel", 0.0)
	Tunables.set_value("kraken_wildness", 0.0)
	Tunables.set_value("kraken_grab_dps", 0.0)
	# THE BODY IS OUT OF THIS but NOT far out of it, and both halves are load-
	# bearing. Several seconds of world run follow and the deep has no floor but
	# the core, so a person left to stand at the floor falls out of the world and
	# takes the run with them (`world._dive_perish`) — hence the re-stamp in
	# every loop below. And the wake cull frees a listed hull a rung and a half
	# from the PLAYER, so parking the body in the safe air at the top would cull
	# the very hull this check is flying (it did; the measurement came back
	# holding a freed node).
	var body_was: Vector2 = pl.global_position
	var safe := boss.global_position + Vector2(-14000.0, -6000.0)
	_hold_body(pl, safe)

	# --- P1: no breath while it still has its blood ------------------------
	boss.shared_health = boss.shared_health_max
	_ok(kai.breath_phase() == 1 and is_zero_approx(kai.breath_pull()),
		"at a full pool it is the hunter and nothing is inhaling")

	# --- P2: the tell, then the pull ---------------------------------------
	boss.shared_health = boss.shared_health_max * 0.5
	await w.get_tree().physics_frame
	_ok(kai.breath_phase() == 2, "half its pool puts it in P2, the breath")
	kai.set("_breath_t", 0.05)
	_ok(kai.breath_telling() and is_zero_approx(kai.breath_pull()),
		"the cycle opens REARING, with no pull behind it yet")
	# Between attacks the rear is what the body holds (a heave in flight still
	# wins the pose — see KrakenAI._pose_tilt_target), so the attack in progress
	# is ended before the pose is read.
	kai.call("_end_attack")
	_ok(is_equal_approx(absf(kai._pose_tilt_target()), Ship.POSE_MAX),
		"...and the rear is a HELD pose at the full %.2f rad, not a velocity read"
			% Ship.POSE_MAX)
	kai.set("_breath_t",
		DiveRun.BREATH_TELL_SECONDS + DiveRun.BREATH_RAMP + 0.1)
	_ok(not kai.breath_telling() and is_equal_approx(kai.breath_pull(), 1.0),
		"and once the rear is over it inhales at full strength")

	# --- THE FIELD, in world coordinates -----------------------------------
	var maw: Vector2 = kai.maw_world()
	var scale := float(w.get("world_scale"))
	var full := DiveRun.BREATH_SPEED * scale
	var below := maw + Vector2(0.0, 6000.0)
	await w.get_tree().physics_frame       # let _dive_weather see this tick's pull
	var air: Vector2 = w.call("dive_weather_at", below, 0)
	_ok(air.y < 0.0 and is_equal_approx(air.length(), full),
		"6,000 px under the maw the air runs UP toward it at %.0f px/s (full is %.0f)"
			% [air.length(), full])
	var far: Vector2 = w.call("dive_weather_at",
		maw + Vector2(0.0, DiveRun.BREATH_REACH * scale + 1000.0), 0)
	_ok(far.is_equal_approx(Vector2.ZERO),
		"past the %.0f px reach there is no breath at all (%.0f px/s)"
			% [DiveRun.BREATH_REACH * scale, far.length()])
	# IT DOES NOT INHALE ITSELF (designer A). The same point, asked FOR the boss.
	var selfward: Vector2 = w.call("dive_weather_at", below, boss.get_instance_id())
	_ok(selfward.is_equal_approx(Vector2.ZERO),
		"the source is excluded from its own breath — a maw cannot swallow itself")
	# SYMMETRIC: the depth's own pickets ride it, because the run stamps the
	# weather on every body it is flying and the breath is now part of that.
	var picket = w.call("_dive_spawn_picket", "hulk", maw + Vector2(3000.0, 6000.0))
	if picket != null and is_instance_valid(picket):
		for i in 4:
			await w.get_tree().physics_frame
			_hold_body(pl, safe)
		# ONE INSTANT, BOTH READINGS. `maw` above is four frames old, the picket
		# has been falling and being pulled the whole time, and `extra_wind` is
		# LAST tick's stamp -- so the direction the wind had and the direction the
		# maw is in were measured at different moments, and near the maw that
		# angle moves fast. It failed on roughly every other run of this suite
		# (267, 294 and 528 px/s of perfectly good breath, pointing a few degrees
		# stale) and passed on the ones in between, which is a race, not a bug in
		# the breath. Ask the boss where its maw is NOW, re-stamp the weather at
		# the positions everything is at NOW, then compare the two.
		var maw_now: Vector2 = kai.maw_world()
		w.call("_dive_weather", 0.0)
		var toward: Vector2 = (maw_now - picket.global_position).normalized()
		var wind: Vector2 = picket.get("extra_wind")
		_ok(wind.length() > 0.0 and wind.normalized().dot(toward) > 0.9,
			"a picket in the breath is stamped with it too (%.0f px/s toward the maw)"
				% wind.length())
		picket.queue_free()
	else:
		_ok(false, "a picket could be put in the breath")

	# --- THE ACCEPTANCE: ≥ 25 % STICK AUTHORITY ----------------------------
	# The shipped starter, listed in the run so the weather reaches it, holding a
	# FULL CLIMB from the same spot twice: once in the inhale, once with the F2
	# lever off. The ratio is the authority the design asks for.
	#
	# THE WORST CASE IS A MAW BELOW YOU — the inhale then pulls exactly against
	# the stick, and any other geometry only spends part of itself on the
	# vertical. The den has a roof one body height over it, so for this
	# measurement alone the boss is dropped into the open air BELOW the den
	# (there is 21,937 px of it) and put back afterwards; a hull parked over the
	# den itself would be measuring a climb into stone.
	#
	# The period goes to its "continuous" position too (a cycle no longer than
	# the tell): a rear arriving mid-measurement would read as a lull in the
	# wind, and the rhythm is pinned by `run_tests._test_the_breath` already.
	var den_was := boss.global_position
	Tunables.set_value("dive_breath_period", DiveRun.BREATH_TELL_SECONDS)
	boss.global_position = den_was + Vector2(0.0, 9000.0)
	boss.linear_velocity = Vector2.ZERO
	await w.get_tree().physics_frame
	maw = kai.maw_world()
	var over_maw := maw - Vector2(0.0, 6000.0)
	var hull: Ship = w.get("fleet").call("spawn_ship_from_cells",
		ShipLayout.upscale_cells(ShipLayout.load_cells("res://ships/starter.ship"), 8),
		over_maw, 0, 0.0, scale, 0)
	if hull == null or not is_instance_valid(hull):
		_ok(false, "a starter could be flown into the breath")
		boss.global_position = den_was
		return _reset_breath_levers()
	(w.get("_dive_surged") as Array).append(hull.get_instance_id())
	var taxed := await _climb_in_the_breath(w, pl, safe, hull, over_maw)
	Tunables.set_value("dive_breath", false)
	await w.get_tree().physics_frame
	var free_climb := await _climb_in_the_breath(w, pl, safe, hull, over_maw)
	Tunables.set_value("dive_breath", true)
	Tunables.reset("dive_breath_period")
	boss.global_position = den_was
	boss.linear_velocity = Vector2.ZERO
	var authority := taxed / maxf(free_climb, 0.001)
	print("      ~ a full climb: %.0f px/s in still air, %.0f px/s inside the inhale"
		% [free_climb, taxed])
	_ok(free_climb > 0.0 and authority >= 0.25,
		"STICK AUTHORITY INSIDE THE BREATH: %.0f %% of a free climb (the design asks >= 25 %%)"
			% (authority * 100.0))
	_ok(authority < 1.0,
		"...and the inhale is a real tax, not decoration (%.0f px/s of climb lost)"
			% (free_climb - taxed))
	(w.get("_dive_surged") as Array).erase(hull.get_instance_id())
	hull.queue_free()
	await w.get_tree().physics_frame

	# --- P3: THE SINK UNDER THE ROOF ---------------------------------------
	boss.shared_health = boss.shared_health_max * 0.2
	_ok(kai.breath_phase() == 3 and is_zero_approx(kai.breath_pull()),
		"under 30 % it stops inhaling — P3 is the sink, and the throat is the door")
	var den: Vector2 = kai.den_anchor
	_ok(den != Vector2.INF, "it knows where its den is")
	# Displaced out from under the slab and BELOW it — where a boss that came up
	# to hunt you actually is. (Never above: the roof is up there, and dropping
	# 28,096 blocks into stone measures a crush, not a withdrawal.)
	boss.global_position = den + Vector2(8000.0, 6000.0)
	boss.linear_velocity = Vector2.ZERO
	var was := boss.global_position.distance_to(den)
	for i in 90:
		await w.get_tree().physics_frame
		_hold_body(pl, safe)
		if not is_instance_valid(boss):
			break
	if is_instance_valid(boss):
		var now := boss.global_position.distance_to(den)
		_ok(now < was,
			"...and it withdraws to the den under its roof (%.0f -> %.0f px)"
				% [was, now])
		boss.global_position = den
		boss.linear_velocity = Vector2.ZERO
	else:
		_ok(false, "...and it withdraws to the den under its roof")

	# --- THE ROOF STILL STOPS THE DUNK -------------------------------------
	# What changed this round is WHERE the wash is sampled (the victim's surface,
	# not its origin), which moves the jet's bite HALF A BODY closer — so the
	# roof's clearance is re-asserted against the back rather than the origin.
	var jet := Ship.WASH_RANGE_CELLS * Ship.CELL * scale
	var back := boss.global_position.y + boss.solid_bounds.position.y
	var from_slab := back - roof.position.y   # a keel resting ON the slab's top
	_ok(from_slab > jet,
		"a hull standing on the roof is %.0f px from the boss's BACK — past the %.0f px jet"
			% [from_slab, jet])
	_ok(roof.size.y >= 4.0 * cpx and from_slab > jet + roof.size.y * 0.5,
		"...with the slab itself (%.0f px) inside that gap, so the dunk stays a decision"
			% roof.size.y)
	boss.shared_health = boss.shared_health_max
	_reset_breath_levers()
	_hold_body(pl, body_was)
	await w.get_tree().physics_frame


## Hold a full CLIMB for a second and a half from `at`, and report the vertical
## speed it settles at (px/s up). Re-parked each time so the two readings start
## from the same place in the field; the person is held clear throughout, as
## everywhere else in this check.
func _climb_in_the_breath(w: Node, pl, safe: Vector2, hull: Ship,
		at: Vector2) -> float:
	hull.global_position = at
	hull.linear_velocity = Vector2.ZERO
	await w.get_tree().physics_frame
	var sum := 0.0
	var n := 0
	for i in 90:
		hull.thrust_input = Vector2(0.0, 1.0)   # a full climb, every frame
		await w.get_tree().physics_frame
		_hold_body(pl, safe)
		if not is_instance_valid(hull):
			return 0.0
		if i >= 60:                              # the last half second only
			sum += -hull.linear_velocity.y
			n += 1
	hull.thrust_input = Vector2.ZERO
	return sum / maxf(float(n), 1.0)


func _reset_breath_levers() -> void:
	Tunables.reset("dive_zone_wind_mult")
	Tunables.reset("whale_push_accel")
	Tunables.reset("whale_align_accel")
	Tunables.reset("kraken_wildness")
	Tunables.reset("kraken_grab_dps")
	Tunables.reset("dive_breath")


## THE GROUND IS ALREADY THERE WHEN YOU ARRIVE (owner 2026-09-02: *"the borders
## that make the world look like it loops are nearly there - it just glitches out
## for a moment when traversing the threshold"*).
##
## The wrap was never the problem: `_check_dive_seam_is_seamless` above proves
## every visible thing moves by one circumference in one frame and that the
## ground repeats exactly. What glitched was the TERRAIN STREAMER — chunks are
## nodes and colliders, promoted ONE per frame nearest-first, so after the shift
## nothing on the far side was live and the ground filled in over tens of frames.
##
## The fix is to start earlier, not to promote faster: within a carry-width of
## the seam, a focus's MIRROR one circumference away is a primary focus too. This
## is the check that it pays — the far side is live BEFORE the crossing, and
## still live the frame after it.
func _check_dive_seam_prewarms_the_mirror(w: Node, pl, ring_w: float, cx: float,
		terrain) -> void:
	var carry: float = float(w.call("_dive_wrap_carry_px"))
	var y: float = pl.global_position.y
	# THE BAND ITSELF: half a carry-width short of the seam is already inside it.
	var mid: Array = w.call("_ring_mirror_foci",
		[Vector2(cx + ring_w * 0.5 - carry * 0.5, y)])
	_ok(mid.size() == 1
			and is_equal_approx((mid[0] as Vector2).x,
				cx + ring_w * 0.5 - carry * 0.5 - ring_w),
		"a body half a carry-width from the seam asks for the far side too (%.0f px away)"
			% ring_w)
	# ...and the measurement itself is taken on the approach, a few hundred px
	# short of the wrap line, so the ground it pre-warms is the ground it lands on.
	var stand := Vector2(cx + ring_w * 0.5 - 600.0, y)
	var mirrors: Array = w.call("_ring_mirror_foci", [stand])
	_ok(mirrors.size() == 1
			and is_equal_approx((mirrors[0] as Vector2).x, stand.x - ring_w),
		"...and so does one on the very lip of the seam")
	_ok((w.call("_ring_mirror_foci", [Vector2(cx, y)]) as Array).is_empty(),
		"...and a body at the ring's centre asks for nothing extra")

	# The mirror neighbourhood has to exist as DATA before it can be promoted —
	# the same lazy generation the streamer's own pass does, run to completion here
	# so the measurement is about PROMOTION, not about generation.
	var mirror_x := stand.x - ring_w
	IslandGen.ensure_generated(terrain, int(w.get("world_seed")),
		[stand, Vector2(mirror_x, y)], carry, 4096)
	# ...and the ground itself is PLANTED rather than hunted for. The dive rolls a
	# fresh seed every run, so whether an island happens to fall at the seam at the
	# altitude the body is standing at is a coin toss — and this check is about
	# PROMOTION, not about where islands land (the ground's periodicity is proved
	# by `_check_dive_seam_is_seamless` above). A strip of stone either side of the
	# wrap line, one circumference apart, so the world stays periodic while it is
	# measured. `fill_rect` is a generation write: it is not recorded as a dig.
	var cpx: float = float(terrain.call("chunk_px"))
	var lap := roundi(ring_w / cpx)
	_ok(absf(float(lap) * cpx - ring_w) < 1.0,
		"the circumference is a whole number of chunks (%d × %.0f px)" % [lap, cpx])
	var ground: Vector2i = terrain.call("chunk_of_cell",
		terrain.call("world_to_cell", Vector2(mirror_x, y)))
	for k in 3:
		var c := ground + Vector2i(k - 1, 0)
		for side in [0, lap]:
			var cell0 := Vector2i(c.x + side, c.y) * Terrain.CHUNK + Vector2i(4, 4)
			terrain.call("fill_rect", Rect2i(cell0, Vector2i(8, 8)),
				TerrainDB.Type.STONE)
	terrain.call("flush_rebuilds")
	var fly_y := (float(ground.y) + 0.5) * cpx
	stand.y = fly_y
	var mirror := Vector2(mirror_x, fly_y)

	# Now run the world's REAL focus tick until the queue drains, and count what
	# the MIRROR pre-warmed: chunks holding data within the primary radius of it.
	var before_live: int = (terrain.get("_live") as Dictionary).size()
	var cam = w.get("camera")
	for i in 1200:
		# Re-seated each pass: the body is a live CharacterBody2D and this is a
		# claim about where the streamer looks, not about where gravity takes it.
		pl.global_position = stand
		pl.velocity = Vector2.ZERO
		if cam != null and is_instance_valid(cam):
			cam.global_position = stand
		w.call("_stream_terrain")
		if bool(terrain.get("_last_scan_drained")):
			break
		if i % 120 == 119:
			await process_frame
	var warmed := _live_chunks_near(terrain, mirror)
	_ok(int(warmed["data"]) > 0,
		"there is ground within a promote radius of the mirror point (%d chunks)"
			% int(warmed["data"]))
	_ok(int(warmed["live"]) == int(warmed["data"]),
		"THE FAR SIDE IS LIVE BEFORE THE WRAP: %d of %d mirror chunks promoted"
			% [int(warmed["live"]), int(warmed["data"])])
	print("    ~ the mirror pre-warms %d chunks (world live %d -> %d)"
		% [int(warmed["live"]), before_live,
			(terrain.get("_live") as Dictionary).size()])
	# The scan-skip cache must survive the extra focus: with the queue drained and
	# nothing moving, a frame near the seam is still a no-op. Otherwise the mirror
	# would have bought a smooth crossing with a permanent per-frame scan.
	var scans_before: int = int(terrain.get("scan_count"))
	for i in 5:
		pl.global_position = stand
		w.call("_stream_terrain")
	_ok(int(terrain.get("scan_count")) - scans_before <= 1,
		"...and a still world near the seam still skips its scans (%d in 5 frames)"
			% (int(terrain.get("scan_count")) - scans_before))

	# ...and CROSS. The frame after the wrap the same ground is under you and
	# still live — which is exactly the frame that used to show bare sky.
	pl.global_position = Vector2(cx + ring_w * 0.5 + 600.0, fly_y)
	if cam != null and is_instance_valid(cam):
		cam.global_position = pl.global_position
	w.call("_dive_hold_the_ring", 0.016)
	_ok(pl.global_position.x < cx, "the body crossed the seam")
	w.call("_stream_terrain")
	# Two chunks in from the promote radius: the OUTERMOST ring always streams in
	# as you keep flying — that is the streamer working, at one chunk a frame, on
	# ground that is off screen. The claim the owner's report is about is the
	# ground you are actually over, and that has to be there already.
	var after := _live_chunks_near(terrain, pl.global_position, -2)
	_ok(int(after["data"]) > 0 and int(after["live"]) == int(after["data"]),
		"...and the ground around it is STILL LIVE the very next frame (%d of %d)"
			% [int(after["live"]), int(after["data"])])


## Chunks within the primary promote radius of `at` that hold data, and how many
## of those are live. The two numbers the pre-warm claim is made of.
func _live_chunks_near(terrain, at: Vector2, grow: int = 0) -> Dictionary:
	var r: int = maxi(int(terrain.call("_primary_promote_r")) + grow, 1)
	var cell: Vector2i = terrain.call("world_to_cell", at)
	var home: Vector2i = terrain.call("chunk_of_cell", cell)
	var chunks := terrain.get("_chunks") as Dictionary
	var live_set := terrain.get("_live") as Dictionary
	var data := 0
	var live := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := home + Vector2i(dx, dy)
			if not chunks.has(c):
				continue
			data += 1
			if live_set.has(c):
				live += 1
	return {"data": data, "live": live}


## THE DRAFT SPANS THE CROSSING (owner 2026-09-02: *"the vertical wind bands
## could be a bit wider ... The hope was that the expanse of this wind draft
## could semi camouflage the teleporting bit"*).
##
## The pure half lives in `run_tests._test_dive_draft_band`; this is the claim in
## REAL PIXELS, which is why it is here: a hull a whole ring tile past the
## downdraft's centre — standing in the next tile along — feels the draft at the
## shipped band of 2.0 and feels nothing at 1.0.
func _check_dive_draft_spans_the_seam(w: Node, pl, tile_w: float, cx: float) -> void:
	var run = w.get("dive")
	if run == null:
		return
	var was_deepest: int = int(run.get("deepest"))
	run.set("deepest", 2)   # the ring is only the sky once you have been down
	var seam := cx + tile_w * float(DiveRun.RING.size()) * 0.5
	var y: float = pl.global_position.y
	var at_centre: Vector2 = w.call("dive_weather_at", Vector2(seam, y))
	_ok(at_centre.y > 0.0,
		"the downdraft at the seam pushes DOWN (%.0f px/s)" % at_centre.y)

	var one_tile_out := Vector2(seam - tile_w, y)
	Tunables.set_value("dive_draft_band_tiles", 2.0)
	var wide: Vector2 = w.call("dive_weather_at", one_tile_out)
	Tunables.set_value("dive_draft_band_tiles", 1.0)
	var narrow: Vector2 = w.call("dive_weather_at", one_tile_out)
	Tunables.set_value("dive_draft_band_tiles", 2.0)
	_ok(wide.y > 0.0,
		"a hull a WHOLE TILE past its centre (%.0f px, the next tile along) still feels it at band 2.0 (%.0f px/s)"
			% [tile_w, wide.y])
	_ok(is_zero_approx(narrow.y),
		"...and feels nothing at band 1.0 — which is exactly the old hard tile edge")
	# The felt width, in the pixels the owner actually flies through.
	var reach := (1.0 + DiveRun.DRAFT_BLEND_TILES) * 2.0 * tile_w
	print("    ~ ring tile %.0f px; draft support band 2.0 = %.0f px (+/-%.0f), band 1.0 = %.0f px"
		% [tile_w, reach, reach * 0.5,
			(0.5 + DiveRun.DRAFT_BLEND_TILES) * 2.0 * tile_w])
	# ...and the SEAM itself is inside the band from both sides, which is the
	# camouflage the owner asked for: you cross while the wind is already on you.
	var just_before: Vector2 = w.call("dive_weather_at",
		Vector2(seam - tile_w * 0.6, y))
	var just_after: Vector2 = w.call("dive_weather_at",
		Vector2(seam - tile_w * 0.6 - tile_w * float(DiveRun.RING.size()), y))
	_ok(just_before.y > 0.0 and just_before.is_equal_approx(just_after),
		"the wind either side of the wrap line is the same wind (%.0f px/s)"
			% just_before.y)
	run.set("deepest", was_deepest)

## THE SEAM YOU CANNOT SEE (owner 2026-09-01: *"Looping around through the world
## seems to make such a mess - it literally teleports the player. could it be a
## bit more seamless? The world entirely could be fully rollover and we only see
## a 3x3 centered at our location"*).
##
## Every number below is a SCREEN-SCALE distance, which is why this lives here
## and not in the 1× suite. Four claims, and the wrap is only invisible if all
## four hold:
##
##   1. the circumference is a WHOLE number of terrain-generator regions, so the
##      ground can repeat over it at all;
##   2. the world's margin outside the ring is wider than half a max-zoom frame,
##      which is what pays for carrying everything you can see across the seam;
##   3. the GROUND one circumference apart is the same ground, sampled over a
##      whole frame either side of the wrap line;
##   4. crossing moves the body, what it is RIDING, and the camera by exactly one
##      circumference and nothing else — silently, once, with the far side of the
##      ring left where it stands.
##
## (4) is the owner's bug in its own words: *"if you tame a creature and go to
## the edges, you'll get a spam of messages but not actually teleport"* — the old
## wrap moved the player and their hull and nothing else, so a rider was snapped
## straight back onto the creature that stayed behind, every frame, forever.
func _check_dive_seam_is_seamless(w: Node, pl, rect: Rect2, ring_w: float,
		cx: float, terrain) -> void:
	# --- 1. THE RING SITS ON THE GROUND'S OWN GRAIN ------------------------
	var lattice: float = w.call("dive_gen_lattice_px")
	var regions := ring_w / maxf(lattice, 1.0)
	_ok(absf(regions - round(regions)) < 0.001,
		"the ring is a whole number of generator regions (%.4f × %.0f px)"
			% [regions, lattice])
	_ok(RingSpace.active() and is_equal_approx(RingSpace.period, ring_w)
			and absf(RingSpace.centre - cx) < 1.0,
		"...and the world DECLARES itself a ring, so the generator repeats on it")

	# --- 2. THE MARGIN PAYS FOR THE CARRY ----------------------------------
	var view: float = w.call("max_view_width_px")
	var carry: float = w.call("_dive_wrap_carry_px")
	_ok(carry >= view * 0.5 - 1.0,
		"the wrap carries at least everything on screen (%.0f px vs half-frame %.0f)"
			% [carry, view * 0.5])
	_ok(ring_w * 0.5 + carry <= rect.size.x * 0.5 + 1.0,
		"...and never past the walls (%.0f px carried into %.0f px of margin)"
			% [carry, (rect.size.x - ring_w) * 0.5])

	# --- 3. THE GROUND ONE LAP AWAY IS THE SAME GROUND ----------------------
	# Sampled over a whole max-zoom frame either side of the wrap line, because
	# that is exactly what a player standing at the seam can see.
	var y: float = pl.global_position.y
	var seam := Vector2(cx + ring_w * 0.5, y)
	IslandGen.ensure_generated(terrain, int(w.get("world_seed")),
		[seam, Vector2(seam.x - ring_w, y)], view * 1.5, 4096)
	var cp: float = terrain.call("cell_px")
	var step := int(maxf(round(256.0 / maxf(cp, 1.0)), 1.0))
	var half_cells := int(view * 0.5 / maxf(cp, 1.0))
	# A tall band, not a stripe: the sky is mostly sky, and a probe that happened
	# to fall between two islands would pass while proving nothing.
	var tall_cells := int(40000.0 / maxf(cp, 1.0))
	var origin: Vector2i = terrain.call("world_to_cell", seam)
	var probes := 0
	var solid := 0
	var mismatches := 0
	var lap_cells := int(round(ring_w / maxf(cp, 1.0)))
	for dx in range(-half_cells, half_cells + 1, step):
		for dy in range(-tall_cells, tall_cells + 1, step):
			var here: int = terrain.call("cell_type",
				Vector2i(origin.x + dx, origin.y + dy))
			var there: int = terrain.call("cell_type",
				Vector2i(origin.x + dx - lap_cells, origin.y + dy))
			probes += 1
			if here != TerrainDB.Type.AIR:
				solid += 1
			if here != there:
				mismatches += 1
	_ok(solid > 0,
		"there is real ground within a frame of the seam (%d of %d samples)"
			% [solid, probes])
	_ok(mismatches == 0,
		"...and every cell of it repeats exactly one circumference away (%d/%d differ)"
			% [mismatches, probes])

	# --- 4. THE CROSSING ITSELF --------------------------------------------
	# A creature to ride over the seam (the owner's case) and one parked on the
	# ring's far side, which must NOT be dragged along.
	var mount_at := Vector2(seam.x + 400.0, y)
	var ridden: Ship = w.call("debug_spawn", "critter", mount_at)
	var parked: Ship = w.call("debug_spawn", "critter", Vector2(cx, y))
	_ok(ridden != null and parked != null, "two creatures for the seam test")
	if ridden == null or parked == null:
		return
	ridden.freeze = true          # hold it still: this is about the WRAP, not swimming
	parked.freeze = true
	# A whisker past the wrap line, riding, with the camera where the run put it.
	# No physics frame between the mount and the wrap: `_handle_taming` ends a
	# ride the moment the hook is not on the creature, and this test is about the
	# WRAP, not the leash.
	var overshoot := 600.0
	pl.global_position = Vector2(seam.x + overshoot, y)
	pl.velocity = Vector2(2400.0, -180.0)
	ridden.global_position = pl.global_position
	_ok(pl.mount(ridden), "the body climbs onto it (the tamed-creature case)")
	var cam = w.get("camera")
	cam.global_position = pl.global_position
	var pickups = w.get("_pickups")
	var said_before: int = pickups.call("count")
	var before_body: Vector2 = pl.global_position
	var before_vel: Vector2 = pl.velocity
	var before_ridden: Vector2 = ridden.global_position
	var before_parked: Vector2 = parked.global_position
	var before_cam: Vector2 = cam.global_position
	var before_zone: int = w.call("dive_zone")
	w.call("_dive_hold_the_ring", 0.016)

	_ok(is_equal_approx(pl.global_position.x, before_body.x - ring_w)
			and is_equal_approx(pl.global_position.y, before_body.y),
		"the body arrives from the other side, exactly one circumference over (%.0f px)"
			% (pl.global_position.x - before_body.x))
	# The wrap is a change of FRAME, not of motion. (The tick's own tile wind is
	# applied in the same call and legitimately leans on `y` — the seam tile is
	# the downdraft — so the claim the wrap owns is the x component and that `y`
	# only ever moved by a wind's worth.)
	_ok(is_equal_approx(pl.velocity.x, before_vel.x)
			and absf(pl.velocity.y - before_vel.y) < 50.0,
		"...carrying its velocity untouched (%.0f, %.0f — was %.0f, %.0f)"
			% [pl.velocity.x, pl.velocity.y, before_vel.x, before_vel.y])
	_ok(rect.has_point(Vector2(pl.global_position.x, rect.get_center().y)),
		"...and lands INSIDE the world, not through a wall")
	_ok(is_equal_approx(ridden.global_position.x, before_ridden.x - ring_w),
		"THE CREATURE IT IS RIDING COMES TOO — the owner's bug, gone")
	_ok(is_equal_approx(
			pl.global_position.distance_to(ridden.global_position),
			before_body.distance_to(before_ridden)),
		"...with the two of them exactly as far apart as they were")
	_ok(is_equal_approx(cam.global_position.x, before_cam.x - ring_w),
		"the camera crosses in the same frame, so the view never moves")
	_ok(parked.global_position.is_equal_approx(before_parked),
		"...while the far side of the ring stays where the ring says it is")
	_ok(int(pickups.call("count")) == said_before,
		"and NOTHING is announced: a seamless wrap has nothing to report")
	_ok(int(w.call("dive_zone")) == before_zone,
		"the run's own bookkeeping never notices (tile %d either side)" % before_zone)

	# NO OSCILLATION — the other half of the owner's bug. The old wrap fired EVERY
	# FRAME at the seam (and said so every frame) because the rider was snapped
	# straight back onto a creature that had not moved. So: run the real mode for
	# a while and count circumference-sized jumps. There must be none.
	var jumps := 0
	var last_x: float = pl.global_position.x
	for i in 12:
		await w.get_tree().physics_frame
		if absf(pl.global_position.x - last_x) > ring_w * 0.4:
			jumps += 1
		last_x = pl.global_position.x
	_ok(jumps == 0,
		"no spam at the edge: the seam is crossed ONCE, not every frame (%d re-wraps)"
			% jumps)
	_ok(absf(pl.global_position.x - cx) <= ring_w * 0.5 + 1.0,
		"...and it is still on this side of the seam (%.0f px from the centre line)"
			% (pl.global_position.x - cx))

	pl.dismount()
	ridden.queue_free()
	parked.queue_free()
	await w.get_tree().physics_frame


## THE PREGENERATED GARRISON, AT THE SCALE THE OWNER PLAYS (owner 2026-09-01:
## "I don't really like how enemies just suddenly APPEAR ... only spawn things as
## the player is close enough, perhaps 2 screens away: this would necessarily
## have to be computed based on whatever the ship's MAX ZOOM is. note that we've
## changed the max zoom").
##
## Every number here is a SCREEN-SCALE distance, so this is the only suite that
## can see any of it. Four things are pinned, and each of them is a bug that has
## either shipped once or is one arithmetic slip away:
##
##   1. the view's own arithmetic, computed the OTHER way round from the same
##      three constants — so a future zoom pass cannot move the camera and leave
##      the spawn distances behind;
##   2. near entries get bodies, far ones stay pending, and NOTHING is born
##      inside a frame (the pop the owner reported);
##   3. a materialized picket 40,000 px out is still AWAKE — the v0.118.0
##      sleeping-hunters trap, which cost a whole version and would come straight
##      back the moment the garrison stopped going through `_dive_spawn_picket`;
##   4. the wake cull does not un-mark what it freed: a cleared sky stays
##      cleared, and the surge itself is born beyond the horizon now.
## A PICKET WHOSE DRIVER IS DEAD MUST STILL SIT IN THE SKY (owner: "enemy
## turrets just fall to their deaths"; DESIGN_DIVE_REVIEW §2.3 + §1.3).
##
## Two of the three causes meet here, and only an 8x run can see either. A hull
## with no driver stops being ticked by `_enemy_pilot`, but `thrust_input` keeps
## whatever the AI last asked for — forever — so a crewman shot at the panel
## used to leave the ship pushing in that direction until it hit something. And
## even centred, a picket at depth 2 was holding itself up on props and balloons
## in air of density 0.23, which it structurally cannot do.
##
## So: jam the stick the way a dying driver did, take the driver away, and give
## it three real seconds at depth 2 with nobody near it. The run's own stamps
## (the air floor, the rate-controlled stick) are the only thing holding it up.
func _check_dive_picket_holds_its_rung(w: Node, pl, cx: float) -> void:
	var picket: Ship = null
	for sid in (w.get("_dive_surged") as Array):
		var hull := instance_from_id(sid) as Ship
		if hull == null or not is_instance_valid(hull) or hull.faction != 1 				or hull.creature_kind != "" or not hull.has_helm():
			continue
		picket = hull
		break
	if picket == null:
		# ...and if the run's own population has none, ASK for one. Since
		# v0.141.0 a depth's garrison is `surge_count(d)` pickets around its
		# landing column (owner call 3), and at some depths every one of them is
		# a kraken — so leaning on "there will happen to be a crewed vessel in
		# the sky" makes this check a lottery. `_dive_spawn_picket` is the run's
		# own spawn path, shared by the garrison and the F2 surge alike, so a
		# hulk from it is the same body the sky would have stood there.
		picket = w.call("_dive_spawn_picket", "hulk",
			pl.global_position + Vector2(9000.0, 0.0)) as Ship
		await w.get_tree().physics_frame
	_ok(picket != null and is_instance_valid(picket) and picket.has_helm(),
		"a crewed picket to leave alone at depth 2")
	if picket == null:
		return
	# MEASURED, and it is the round's one uncomfortable number: at the SHIPPED
	# air floor of 0.5 (the review's first number) neither the starter nor a picket could hold a rung — they are
	# balloon ships, and half density leaves their buoyancy at roughly half their
	# weight while their lift props are worth a sixth of it. The engines were
	# deliberately not retuned (owner's call), so the STICK is measured in air a
	# hull can actually fly in, and the shortfall is reported as a number instead
	# of being tuned away in the dark. Reset at the end of the check.
	Tunables.set_value("dive_air_floor", 0.85)
	# Depth 2's altitude, a long way from the body — this is the review's own
	# one-minute check ("spawn a hulk at depth 2 with no player nearby").
	var rung_y: float = float(w.call("dive_altitude_y", DiveRun.depth_altitude(2)))
	var spot := Vector2(cx + 9000.0, rung_y)
	# CLEAR AIR, GUARANTEED (2026-09-02). This spot is a fixed offset from the
	# centre line, and whether an island is generated there depends on where the
	# run put its landings — so the check flaked the moment anything changed the
	# deck's geometry (a saved candidate, Q-T), measuring a hull resting on rock
	# instead of a hull holding a rung. Generate the neighbourhood, THEN carve it:
	# a region generated afterwards is repainted under the body (DECISIONS
	# 2026-08-30, the landing-shelf bug).
	var terr = w.get("terrain")
	if terr != null:
		IslandGen.ensure_generated(terr, int(w.get("world_seed")), [spot], 14000.0, 64)
		var cp: float = maxf(terr.cell_px(), 1.0)
		var half := 12000.0
		terr.fill_rect(Rect2i(terr.world_to_cell(spot - Vector2(half, half)),
			Vector2i(int(half * 2.0 / cp), int(half * 2.0 / cp))), TerrainDB.Type.AIR)
		terr.flush_rebuilds()
	picket.global_position = spot
	picket.linear_velocity = Vector2.ZERO
	await w.get_tree().physics_frame
	# JAM THE STICK, then kill the driver: exactly the sequence a shell through
	# the panel produces.
	picket.net_set_controls(0.4, -1.0)
	_ok(not is_zero_approx(picket.thrust_input.y),
		"its stick is jammed hard down, the way a dying driver left it")
	for npc in (w.get("_npcs") as Array):
		if npc != null and is_instance_valid(npc) and npc.get("ship") == picket:
			npc.queue_free()
	var y0: float = picket.global_position.y
	for i in 180:
		await w.get_tree().physics_frame
	var centred_fall: float = picket.global_position.y - y0
	_ok(is_zero_approx(picket.thrust_input.y),
		"a dead driver leaves the stick CENTRED, not frozen (%.2f)"
			% picket.thrust_input.y)
	# THE COUNTERFACTUAL, on the same hull, from the same spot. The world centres
	# a driverless stick exactly ONCE (the guard in `_enemy_pilot`), so jamming
	# it again here reproduces the old behaviour without touching the code — and
	# the comparison is honest whatever this seed's picket is trimmed like, which
	# an absolute "it must not sink" number would not be.
	picket.global_position = Vector2(spot.x, rung_y)
	picket.linear_velocity = Vector2.ZERO
	picket.net_set_controls(0.4, -1.0)
	await w.get_tree().physics_frame
	_ok(not is_zero_approx(picket.thrust_input.y),
		"...and the world does not fight a stick set on purpose (one centring, not a loop)")
	for i in 180:
		await w.get_tree().physics_frame
	var jammed_fall: float = picket.global_position.y - rung_y
	_ok(centred_fall < jammed_fall * 0.7,
		"a centred picket keeps its rung far better than a jammed one (%.0f px vs %.0f in 3 s)"
			% [centred_fall, jammed_fall])
	_ok(picket.air_density_at(picket.global_position.y) >= Tunables.get_num("dive_air_floor") - 0.001,
		"...in the run's floored air (%.2f at depth 2, real air 0.23)"
			% picket.air_density_at(picket.global_position.y))
	Tunables.reset_all()


## THE DESCENT SEAL, in a real sky (DESIGN_DESCENT.md, owner rulings §0).
##
## Only an 8× run can see any of this: the band is 4,483 px of a 64,038 px rung,
## and the whole ruling turns on how a rate-controlled hull behaves inside an
## airstream measured against `dive_dive_rate`. Four claims, and the seal is only
## the gate the owner asked for if all four hold:
##
##   1. a NEUTRAL stick inside a live band is CARRIED OUT of the top — drifting
##      into a seal warns you, it does not kill you (DESCENT §4.4);
##   2. a FULL DOWN stick crosses, in the time `SEAL_AIR_SPEED` was tuned for
##      (≈ 30 % of `dive_ship_integrity` at 300 hp/s — DESCENT §3.3);
##   3. a garrison hull feels nothing inside ITS OWN depth's band and the full
##      stream inside anyone else's (§0 call 7, "symmetric with one exception");
##   4. the band DIES when the world reports its last key killed — and a CULL is
##      not a kill (§2.4).
##
## Run at the same air floor as `_check_dive_picket_holds_its_rung` and for the
## same measured reason: at the shipped floor a balloon ship cannot hold a rung
## at all, and a crossing time measured on a hull that is falling anyway would be
## measuring gravity.
func _check_dive_seal(w: Node, pl, run, terrain, cx: float) -> void:
	if pl == null or not is_instance_valid(pl) or run == null or terrain == null:
		_ok(false, "a body, a run and terrain to seal")
		return
	# WHERE THE PERSON WAS STANDING WHEN THIS CHECK STARTED. Everything after this
	# one (the dunk, the Leviathan) holds the body somewhere of its own choosing
	# and assumes it is ON FOOT — so this check gives the helm back and puts them
	# down where it found them. Leaving the person PILOTING was the subtlest
	# failure of the round: the dunk's own `_hold_body` cannot move a pilot, so
	# the body rode the parked hull for twenty seconds, took 88 of its 100 hp, and
	# the run was lost inside a Leviathan check that says nothing about seals.
	var body_was: Vector2 = pl.global_position
	# PUT BACK WHAT WAS HERE, NOT WHAT THE DEFAULTS SAY. This check used to end on
	# `Tunables.reset_all()`, and that is a hammer in the middle of a suite whose
	# checks hand each other a world: the DUNK, immediately above, sets
	# `dive_zone_wind_mult` to 0 and never restores it, so everything after it —
	# the Leviathan's breath check included — is written against a sky with the
	# ring's wind off. `reset_all` turned it back on, the breath check's picket was
	# then stamped with breath PLUS a ring draft, and its "the wind points at the
	# maw" direction test failed on a round that has nothing to do with seals.
	# (Seen twice; it passed on the run in between, which is what a suite-order
	# coupling looks like from the outside.) So: save exactly what this check
	# touches, restore exactly that.
	var levers := {}
	for lever in ["dive_air_floor", "dive_ceiling_mult", "dive_seal_grind",
			"fall_damage"]:
		levers[lever] = Tunables.get_num(lever)
	for lever in ["dive_zones_enabled", "dive_assistant"]:
		levers[lever] = Tunables.get_bool(lever)
	Tunables.set_value("dive_air_floor", 0.85)
	# THE SEAL ALONE. The ring's drafts and the closing sky are ±600 px/s of the
	# same axis at 8×, and that they STACK with a band is the design's own ruling
	# (DESCENT §2.5 — it is why the far side of the ring is the puncher's tile).
	# But a crossing TIME measured with them on is measuring three winds, so the
	# other two are switched off for the duration and restored at the end.
	Tunables.set_value("dive_zones_enabled", false)
	Tunables.set_value("dive_ceiling_mult", 0.0)
	var band := DiveRun.seal_band(2)
	var top_y: float = float(w.call("dive_altitude_y", float(band[0])))
	var bot_y: float = float(w.call("dive_altitude_y", float(band[1])))
	var band_px := bot_y - top_y
	_ok(band_px > 0.0, "depth 2's band is %.0f px of air at 8×" % band_px)
	# AN EMPTY COLUMN TO FLY IT IN. The dive world has islands at every altitude —
	# that is the whole point of the shadow rule — and a hull parked inside one is
	# measuring stone, not wind. (This cost the first run of this check: the hull
	# "rose 1,088 px in 15 s" because it was sitting on a rock.)
	var band_at: Vector2 = await _open_air(w, terrain, pl,
		Vector2(cx, (top_y + bot_y) * 0.5))
	var band_x := band_at.x

	# THE HULL: the run's own COMMITTED starter, flown from the helm through the
	# real input map. Nothing here is a stand-in — a candidate hull sitting on the
	# deck has no driver and no power, so its props deliver nothing and every number
	# measured on one would be measuring gravity. Board it, let `_tick_dive` commit
	# the run (which thaws it, arms its integrity pool and stamps the rate-controlled
	# stick on it), and fly.
	var cand: Ship = null
	for s2 in (w.get("fleet").call("ships") as Array):
		var c2 := s2 as Ship
		if c2 == null or not is_instance_valid(c2):
			continue
		if c2.faction == 0 and c2.creature_kind == "" and c2.has_helm() \
				and not c2.is_nest and not c2.is_carcass():
			cand = c2
			break
	_ok(cand != null, "a stock starter on the deck to fly at the seal")
	if cand == null:
		_restore_levers(levers)
		return
	pl.global_position = cand.to_global(cand.local_pos_of(cand.helm_cells[0]))
	await w.get_tree().physics_frame
	_ok(pl.board(cand, cand.helm_cells[0]), "...and the player takes its helm")
	for i in 6:
		await w.get_tree().physics_frame
	var hull := w.get("local_ship") as Ship
	_ok(hull != null and is_instance_valid(hull) and bool(run.get("committed")),
		"the run is COMMITTED to it — pool armed, rate stick stamped")
	if hull == null or not is_instance_valid(hull):
		_restore_levers(levers)
		return
	run.garrison_killed.clear()

	var beta: float = float(w.call("dive_beta_of", hull))
	_ok(absf(beta - DiveRun.BETA_REF) < DiveRun.BETA_REF * 0.15,
		"the committed starter's β is %.2f — BETA_REF is %.2f (mass %.0f, beam %.0f px)"
			% [beta, DiveRun.BETA_REF, hull.mass, hull.solid_bounds.size.x])

	# --- 1. A DRIFTER IS EJECTED -------------------------------------------
	# Parked dead centre with the stick neutral. The rate controller station-keeps
	# relative to the AIR (`Ship._physics_process`, `v_up` measured against
	# `wind.y`), so "hold still" inside a rising band means "ride it up".
	#
	# GRIND OFF for this one measurement, and for a stated reason: a drifter is
	# ejected in a handful of seconds and the toll would take a third of the pool
	# doing it, which is the DESIGN — but it would also leave nothing to measure
	# the crossing's real bill with two sections down. The toll gets its own
	# section, at the shipped rate, on a full pool.
	Tunables.set_value("dive_seal_grind", 0.0)
	_park_at(hull, pl, Vector2(band_x, (top_y + bot_y) * 0.5))
	await w.get_tree().physics_frame
	var y0 := hull.global_position.y
	var lift_s := -1.0
	for i in 900:
		await w.get_tree().physics_frame
		if hull.global_position.y < top_y:
			lift_s = float(i + 1) / 60.0
			break
	_ok(lift_s > 0.0,
		"a neutral stick is carried UP out of a live band in %.1f s (drift %.0f px, wind %.0f) — you must MEAN a crossing"
			% [lift_s, hull.global_position.y - y0, hull.extra_wind.y])

	# --- 2. ...AND A COMMITTED DIVE CROSSES, AND IS BILLED FOR IT ----------
	# From the top lip, stick hard down, until the bottom lip, at the SHIPPED
	# grind — so the number this prints is the bill the owner actually pays, not
	# arithmetic about one. `SEAL_AIR_SPEED` is tuned against exactly this: the
	# crossing must land near 30 % of `dive_ship_integrity` (DESCENT §3.3).
	# Driven through the real input map — `Input.action_press` works headless
	# (godot-quirks), and a piloted hull reads the map, not `net_set_controls`.
	#
	# THE POOL IS DELIBERATELY DEEPENED FOR THE MEASUREMENT and the bill is
	# reported against the SHIPPED figure: at 300 hp/s a crossing that goes wrong
	# empties a 3,000 pool in ten seconds, the hull explodes, and the run is lost
	# out from under every check that follows this one (the dunk, the Leviathan).
	# A measurement must not be able to end the thing it is measuring.
	Tunables.set_value("dive_seal_grind", levers["dive_seal_grind"])
	var pool := Tunables.get_num("dive_ship_integrity")
	_park_at(hull, pl, Vector2(band_x, top_y + 4.0))
	hull.hull_integrity_max = pool * 20.0
	hull.hull_integrity = hull.hull_integrity_max
	await w.get_tree().physics_frame
	var before := hull.hull_integrity
	Input.action_press("ship_down")
	var cross_s := -1.0
	for i in 900:
		await w.get_tree().physics_frame
		if not is_instance_valid(hull):
			break
		if hull.global_position.y > bot_y:
			cross_s = float(i + 1) / 60.0
			break
	Input.action_release("ship_down")
	_ok(is_instance_valid(hull), "the crossing did not destroy the hull outright")
	if not is_instance_valid(hull):
		_restore_levers(levers)
		return
	var sites := DiveRun.seal_sites(hull.solid_bounds.size.x, DiveRun.BEAM_REF)
	var paid := before - hull.hull_integrity
	print("    ~ the seal: band %.0f px, crossing %.2f s at %.0f px/s, %d sites, %.0f hp (%.0f%% of %.0f)"
		% [band_px, cross_s, band_px / maxf(cross_s, 0.001), sites, paid,
			paid / pool * 100.0, pool])
	_ok(cross_s > 0.0, "a full DOWN stick crosses the band in %.2f s" % cross_s)
	_ok(paid > 0.0, "...and the grind BILLED it (%.0f hp of structure)" % paid)
	_ok(paid / pool > 0.15 and paid / pool < 0.55,
		"...for %.0f%% of the hull's pool at %d sites (target ≈ 30 %%)"
			% [paid / pool * 100.0, sites])

	# --- 2b. THE GRIND'S OWN RATE ------------------------------------------
	# The grind is `rate × time` and nothing else, so a second parked in a band
	# costs `sites × dive_seal_grind` whichever way the hull is pointing. Measured
	# over two seconds rather than asserted from the constants, because the site
	# count is derived from a live beam and the tick is a 4 Hz accumulator.
	#
	# THE ASSISTANT IS SENT AWAY FOR THIS ONE MEASUREMENT. A run posts a crewman
	# at the repair station and `repair_cell` refunds mended structure into the
	# integrity pool (v0.140.0), which is ~150 hp/s of the 300 the seal takes —
	# that is why the crossing above bills 22 % of the pool net where the gross
	# grind is 44 %. Both numbers are real; this one is the seal's.
	Tunables.set_value("dive_assistant", false)
	hull.menders_running = false
	_park_at(hull, pl, Vector2(band_x, (top_y + bot_y) * 0.5))
	hull.hull_integrity = hull.hull_integrity_max
	await w.get_tree().physics_frame
	var hov0 := hull.hull_integrity
	for i in 120:
		await w.get_tree().physics_frame
		if not is_instance_valid(hull):
			break
	var per_s := (hov0 - hull.hull_integrity) / 2.0 if is_instance_valid(hull) else 0.0
	var want_s := float(sites) * Tunables.get_num("dive_seal_grind")
	_ok(per_s > want_s * 0.7 and per_s < want_s * 1.3,
		"parked in a live band, unmended, the hull sheds %.0f hp/s — %d sites × %.0f (%.0f expected, %.1f s to kill a %.0f pool)"
			% [per_s, sites, Tunables.get_num("dive_seal_grind"), want_s,
				pool / maxf(per_s, 1.0), pool])
	Tunables.set_value("dive_assistant", true)
	if is_instance_valid(hull):
		hull.hull_integrity = hull.hull_integrity_max

	# --- 2c. A BODY CANNOT CROSS (§3.5) ------------------------------------
	# Dropped into the band from above at a real falling speed. The band must
	# THROW IT BACK OUT OF THE TOP — a shipless run does not get past a live seal
	# — and charge it on the way. The person is stepped off the helm for this and
	# put straight back after.
	if pl.is_piloting():
		pl.disembark()
	await w.get_tree().physics_frame
	# NEAR THE TOP LIP, and deliberately: a body pays 18 hp/s of ONE life, so a
	# climb from the band's centre spends most of a run's health proving a point
	# the first few hundred pixels already prove. (Propping the pool up instead
	# does not work — `Player` clamps health to its max, so the loop ran the
	# person to death and lost the run under every check that followed.)
	#
	# THE PERSON IS MENDED TO FULL FIRST, AND PUT BACK AFTER. A run has ONE life:
	# a body that walked into this check already hurt by the picket checks above
	# can be killed by four seconds of toll, and a run lost HERE fails the dunk
	# and the Leviathan several minutes later with nothing pointing back. (It did,
	# on one seed in five.) The pool is restored below, so the check still costs
	# the run exactly nothing.
	Tunables.set_value("fall_damage", 0.0)
	var hp0: float = pl.health
	pl.health = pl.max_health
	var entry := top_y + band_px * 0.15
	pl.global_position = Vector2(band_x, entry)
	pl.velocity = Vector2.ZERO
	var thrown := false
	for i in 120:
		await w.get_tree().physics_frame
		pl.velocity.x = 0.0
		if pl.global_position.y < top_y:
			thrown = true
			break
	var body_paid: float = pl.max_health - pl.health
	pl.health = pl.max_health
	_ok(thrown,
		"a body standing in a live band is thrown OUT of the top (%.0f px up, %.1f hp paid)"
			% [entry - pl.global_position.y, body_paid])
	_ok(body_paid > 1.0,
		"...and it paid %.1f hp for the attempt (toll %.0f/s)"
			% [body_paid, DiveRun.SEAL_BODY_TOLL])
	# ...and one DROPPED into it at speed never reaches the far side. The band's
	# net acceleration on a body is upward everywhere inside it, so the deepest a
	# fall can reach is `v² / 2a` — a fraction of a 4,483 px band.
	#
	# LANDINGS ARE OFF for this drop: a body thrown in at 8,000 px/s that finds a
	# rock under the band dies of the LANDING, not of the seal, and that ends the
	# run under every check downstream. This measures how deep the wind lets a
	# fall get; `fall_damage` is somebody else's lever and it goes straight back.
	Tunables.set_value("fall_damage", 0.0)
	pl.global_position = Vector2(band_x, top_y + 4.0)
	pl.velocity = Vector2(0.0, 8000.0)
	var deepest_y: float = pl.global_position.y
	for i in 90:
		await w.get_tree().physics_frame
		pl.velocity.x = 0.0
		deepest_y = maxf(deepest_y, pl.global_position.y)
		if pl.global_position.y < top_y:
			break
	_ok(deepest_y < bot_y,
		"a body dropped into it only reaches %.0f px of %.0f — a shipless run cannot pass a live seal"
			% [deepest_y - top_y, band_px])
	# ...and the person is put back WHOLE, not back to the number they walked in
	# with. This check spends twenty-odd seconds of world, and GRIT regen would
	# have mended them over that time anyway — clamping the pool back down to the
	# entry number is not neutral, it is a debt handed to the next check, and it
	# is what made the dunk's twenty seconds of deep air fatal on some seeds.
	Tunables.set_value("fall_damage", levers["fall_damage"])
	pl.health = pl.max_health
	if hp0 < pl.max_health:
		print("    ~ the body walked in at %.0f hp and leaves mended (regen would have)"
			% hp0)
	_ok(String(run.get("outcome")) == "",
		"the body's toll never spent the run's one life (outcome '%s', %.0f hp)"
			% [String(run.get("outcome")), pl.health])
	pl.global_position = hull.to_global(hull.local_pos_of(hull.helm_cells[0]))
	pl.velocity = Vector2.ZERO
	await w.get_tree().physics_frame
	pl.board(hull, hull.helm_cells[0])
	for i in 3:
		await w.get_tree().physics_frame
	if is_instance_valid(hull):
		hull.hull_integrity = hull.hull_integrity_max

	# --- 3. SYMMETRIC, WITH ONE EXCEPTION (§0 call 7) ---------------------
	var mid := Vector2(band_x, (top_y + bot_y) * 0.5)
	var stream: float = float(w.call("dive_seal_speed_at", mid, beta, 0))
	_ok(stream > 0.0, "the live band at depth 2 blows %.0f px/s upward" % stream)
	_ok(is_zero_approx(float(w.call("dive_seal_speed_at", mid, beta, 2))),
		"...but depth 2's OWN garrison feels nothing in it — the band is its house")
	_ok(is_equal_approx(float(w.call("dive_seal_speed_at", mid, beta, 3)), stream),
		"...while a picket from depth 3 caught in it pays the full stream")
	# MASS BEATS IT, in the world rather than on paper.
	var dart: float = float(w.call("dive_seal_speed_at", mid, beta * 6.0, 0))
	_ok(dart < stream * 0.3,
		"a dart 6× as dense per beam feels %.0f px/s, not %.0f — ruling 3, measured"
			% [dart, stream])

	# --- 4. THE LOCK ------------------------------------------------------
	var tw := Tunables.get_num("dive_zone_tile_widths")
	for k in DiveRun.depth_keys(run.seed_v, 2, tw):
		run.mark_garrison_killed(String(k))
	_ok(run.seal_open(run.seed_v, 2, tw)
			and is_zero_approx(float(w.call("dive_seal_speed_at", mid, beta, 0))),
		"kill depth 2's last standing picket and the band stops blowing — for good")
	run.garrison_killed.clear()

	# THE KEY RIDES THE BODY, and a death writes it down.
	var key := String(DiveRun.depth_keys(run.seed_v, 4, tw)[0])
	var marked := w.call("_dive_spawn_picket", "hulk",
		pl.global_position + Vector2(12000.0, 0.0), key) as Ship
	await w.get_tree().physics_frame
	_ok(marked != null and marked.garrison_key == key,
		"a materialized picket carries its roster key (%s)" % key)
	if marked != null:
		w.call("_dive_explode_ship", marked)
		_ok(run.garrison_is_killed(key), "...and its death marks that key KILLED")

	# ...BUT A CULL IS NOT A KILL (§2.4). The survivor goes back to PENDING, which
	# is the whole reason a half-fought seal can never deadlock.
	var key2 := String(DiveRun.depth_keys(run.seed_v, 4, tw)[0])
	run.garrison_killed.erase(key2)
	run.mark_garrison_spawned(key2)
	var doomed := w.call("_dive_spawn_picket", "hulk",
		pl.global_position + Vector2(12000.0, 0.0), key2) as Ship
	await w.get_tree().physics_frame
	# ...and then flown away from. Moved rather than born out there: a spawn
	# point past the world's own edge is not a spawn at all.
	if doomed != null and is_instance_valid(doomed):
		doomed.global_position = pl.global_position + Vector2(0.0, 400000.0)
	w.call("_dive_cull_the_wake", 2.0)
	_ok(not run.garrison_is_spawned(key2),
		"the wake cull hands a culled entry back to PENDING")
	_ok(not run.garrison_is_killed(key2), "...and never counts it as dead")
	if doomed != null and is_instance_valid(doomed):
		doomed.queue_free()

	# --- 5. WHAT THE PAINTER IS HANDED (slice 7's data half) ---------------
	# `SealBands` holds no logic, so the only testable seam is the provider: plain
	# Rects, bools and counts, and only the bands the camera could see.
	_park_at(hull, pl, Vector2(band_x, (top_y + bot_y) * 0.5))
	await w.get_tree().physics_frame
	var rows: Array = w.call("seal_bands")
	var here: Dictionary = {}
	for r_v in rows:
		var r := r_v as Dictionary
		if int(r.get("depth", 0)) == 2:
			here = r
	_ok(not here.is_empty(),
		"the painter is handed the band it is looking at (%d visible)" % rows.size())
	if not here.is_empty():
		var rr := here.get("rect", Rect2()) as Rect2
		_ok(absf(rr.size.y - band_px) < 2.0,
			"...as a world-space rect of the right height (%.0f px vs %.0f)"
				% [rr.size.y, band_px])
		_ok(rr.position.y <= top_y + 1.0 and rr.end.y >= bot_y - 1.0,
			"...spanning the band's own lips")
		_ok(bool(here.get("live", false)) and int(here.get("of", 0)) > 0,
			"...marked LIVE with a count on it (%d of %d left)"
				% [int(here.get("left", 0)), int(here.get("of", 0))])
	# ...and a cleared band still reaches the painter, marked dead, so the layer
	# can draw the reward instead of simply losing the band.
	for k5 in DiveRun.depth_keys(run.seed_v, 2, tw):
		run.mark_garrison_killed(String(k5))
	var dead_rows: Array = w.call("seal_bands")
	var dead_here := false
	for r_v2 in dead_rows:
		var r2 := r_v2 as Dictionary
		if int(r2.get("depth", 0)) == 2 and not bool(r2.get("live", true)):
			dead_here = true
	_ok(dead_here, "a cleared band is still handed over, marked dead")
	# ...and the status row the HUD counts down carries the same answer.
	run.set("depth", 2)
	var st := w.call("dive_status") as Dictionary
	var seal_row := st.get("seal", {}) as Dictionary
	_ok(not seal_row.is_empty() and not bool(seal_row.get("live", true))
			and int(seal_row.get("left", -1)) == 0,
		"dive_status agrees with it (%s)" % seal_row)
	# ...AND LEAVE THE SKY OPEN BEHIND IT. Every band of this run is marked dead
	# on the way out, deliberately, because the checks that follow fly this same
	# hull for another twenty seconds with nobody at the stick: a hull left
	# hovering near a live band SINKS into it (measured: 0.708 → 0.657 of the
	# world's height in one dunk), is ground apart at 300 hp/s, and takes the
	# person at its helm down with the husk — 88 hp, then a lost run, in a check
	# five minutes away that says nothing about seals. The seal has been measured
	# by here; what the rest of the suite needs from it is that it is not in the
	# way. (Parking higher was tried first and only moved the seed at which it
	# happens.)
	var tw_all := Tunables.get_num("dive_zone_tile_widths")
	for d_all in range(2, DiveRun.DEPTHS):
		for k_all in DiveRun.depth_keys(run.seed_v, d_all, tw_all):
			run.mark_garrison_killed(String(k_all))
	# HAND THE RUN BACK OTHERWISE AS IT WAS FOUND. The dunk runs twenty seconds of
	# world after this and the Leviathan check needs a live run at the end of it.
	# Leaving the committed hull PARKED IN A LIVE BAND fails both: at 300 hp/s it
	# grinds through a 3,000 pool in ten seconds, explodes, and drops the person
	# aboard — a lost run, on some seeds, several checks later, with nothing
	# pointing back here. So the hull goes back to open air, with a full pool and
	# the levers reset.
	#
	# ABOVE the band rather than at the rung's own altitude, which was the first
	# fix and was worse: the rung IS the landing shelf, so parking there dropped
	# the hull onto stone and twenty seconds of grinding contact took 88 hp off
	# the person at its helm — half the seeds then lost the run inside the dunk.
	# This altitude is inside the empty column `_open_air` already certified.
	if is_instance_valid(hull):
		hull.hull_integrity_max = pool
		hull.hull_integrity = pool
		_park_at(hull, pl, Vector2(band_x, (top_y + bot_y) * 0.5 - band_px * 1.4))
		await w.get_tree().physics_frame
	var still_live := 0
	for d_live in range(2, DiveRun.DEPTHS):
		if bool(w.call("dive_seal_live", d_live)):
			still_live += 1
	_ok(still_live == 0,
		"...and the run is handed on with every band dead (%d still blowing)"
			% still_live)
	# The helm goes back and the person goes back to their own feet.
	if pl.is_piloting():
		pl.disembark()
	pl.global_position = body_was
	pl.velocity = Vector2.ZERO
	await w.get_tree().physics_frame
	print("    ~ after the seal: outcome '%s', body %.0f hp, altitude %.3f, piloting %s"
		% [String(run.get("outcome")), pl.health,
			float(w.call("_player_altitude_frac")), str(pl.is_piloting())])
	_ok(String(run.get("outcome")) == "" and not pl.is_piloting(),
		"the seal check hands the run back alive, with the person on their own feet")
	_restore_levers(levers)


## Put back exactly the levers a check borrowed, at the values it found them at.
##
## NOT `Tunables.reset_all()`: the checks in this file hand each other a live
## world, and several of them leave a lever set on purpose for everything that
## follows (the dunk parks `dive_zone_wind_mult` at 0 so the sky above the
## Leviathan is still). Resetting to DEFAULTS silently un-does those, and the
## round that pays for it is whichever one runs next.
func _restore_levers(levers: Dictionary) -> void:
	for lever in levers:
		Tunables.set_value(String(lever), levers[lever])


## Put the committed hull (and the body riding it) at `at`, stopped. The player
## is AT THE HELM for every seal measurement, which is what keeps the wake cull
## (measured from the nearest player) from freeing the hull mid-run and what
## stops a body left in mid-air falling into the lava and ending the run.
func _park_at(hull: Ship, pl, at: Vector2) -> void:
	hull.global_position = at
	hull.linear_velocity = Vector2.ZERO
	hull.angular_velocity = 0.0
	if pl != null and is_instance_valid(pl):
		pl.global_position = at
		pl.velocity = Vector2.ZERO


func _check_dive_garrison_materializes(w: Node, pl, run, cx: float) -> void:
	if pl == null or not is_instance_valid(pl) or run == null:
		_ok(false, "a body and a run to garrison around")
		return

	# --- 1. THE VIEW, MEASURED BOTH WAYS -----------------------------------
	# The helm view is `camera_zoom / pilot_zoom_out`; the wheel's far end is a
	# flat multiplier on top. Computed here from the scene's own exported
	# numbers and the script's own constants, so this reddens if the two halves
	# ever stop being the same product.
	var consts: Dictionary = (w.get_script() as GDScript).get_script_constant_map()
	var zmin := float(consts["ZOOM_USER_MIN"])
	var vp: Vector2 = w.call("_viewport_px")
	var cz := float(w.get("camera_zoom"))
	var pz := float(w.get("pilot_zoom_out"))
	var helm_w := vp.x / (cz / pz)
	var maxw := float(w.call("max_view_width_px"))
	_ok(maxw >= helm_w - 1.0,
		"the widest possible view is at least the helm's (%.0f px vs %.0f)"
			% [maxw, helm_w])
	_ok(is_equal_approx(maxw, helm_w / zmin),
		"...and it IS the helm view wound all the way out (×%.2f)" % (1.0 / zmin))
	_ok(is_equal_approx(float(w.call("min_camera_zoom")), cz * zmin / pz),
		"the smallest reachable zoom is the same product read backwards (%.5f)"
			% float(w.call("min_camera_zoom")))
	var horizon := float(w.call("max_view_horizon_px"))
	_ok(horizon > maxw * 0.5 and horizon < maxw,
		"the no-pop bubble is the frame's far CORNER, not its edge (%.0f px)" % horizon)
	var reach := float(w.call("dive_materialize_px"))
	_ok(is_equal_approx(reach, Tunables.get_num("dive_spawn_screens") * maxw),
		"the materialize radius is %.2f of those screens (%.0f px)"
			% [Tunables.get_num("dive_spawn_screens"), reach])
	_ok(reach > horizon * 2.0,
		"...comfortably outside the bubble, so two screens is never a pop-in")

	# --- 2. BODIES ONLY WHEN YOU ARE NEAR ----------------------------------
	# Clear the surge's litter first: the picket cap is one budget over both, and
	# a spent cap would make "nothing materialized" pass for the wrong reason.
	var surged: Array = w.get("_dive_surged")
	for sid in surged.duplicate():
		var s3 := instance_from_id(sid) as Ship
		if s3 != null and is_instance_valid(s3):
			s3.queue_free()
	surged.clear()

	# From here on nothing awaits until the assertions are made: the world is
	# LIVE, its own `_tick_dive` re-reads the altitude every frame, and a yield
	# in the middle would let the run advance out from under the check.
	var depth := 3
	pl.velocity = Vector2.ZERO
	# ON THIS DEPTH'S LANDING COLUMN, not on the ring's centre line. Since
	# v0.141.0 a depth's whole garrison stands in the three tiles around its own
	# landing (owner call 3), so "the ring's centre" is a tile that usually keeps
	# NOBODY — and a check standing there would pass or fail on where this run's
	# seed happened to put its ladder. Standing on the landing tile, the garrison
	# in its two NEIGHBOURS is a tile away: outside everybody's frame, inside the
	# two-screen reach, which is exactly the band a body is handed out in.
	var land_tile := DiveRun.landing_tile(int(run.get("seed_v")), depth,
		Tunables.get_num("dive_zone_tile_widths"))
	pl.global_position = Vector2(
		cx + DiveRun.zone_offset(land_tile) * float(w.call("_dive_tile_w")),
		float(w.call("dive_altitude_y", DiveRun.depth_altitude(depth))))
	run.set("depth", depth)

	# FORGET WHAT THE LIVE WORLD ALREADY WOKE. The ticks that ran while this suite
	# was flying around have been marking entries spawned all along, and since
	# v0.141.0 a depth is worth 2-5 pickets in total (owner call 3) rather than
	# 48 — so "there will be leftovers near the player for the explicit call to
	# find" stopped being true, and this check went from reliable to a coin flip.
	# Both books are cleared together, because the assertion below compares them.
	run.set("garrison_spawned", {})
	w.set("_dive_materialized", 0)

	# THE DOCK IS SAFE UNTIL YOU HAVE BEEN DOWN, so a run that has never left the
	# top rung wakes nothing at all — the same gate the den's clock rides, and
	# the reason the dive scene's boot above finds an empty sky.
	run.set("deepest", 1)
	var marked_at_deck: int = (run.get("garrison_spawned") as Dictionary).size()
	w.call("_dive_materialize_garrison", 10.0)
	_ok((run.get("garrison_spawned") as Dictionary).size() == marked_at_deck
			and (w.get("_dive_surged") as Array).is_empty(),
		"a run that has never left the deck wakes nothing (%d marks, %d bodies)"
			% [marked_at_deck, (w.get("_dive_surged") as Array).size()])

	run.set("deepest", depth)
	var marked_before: Dictionary = (run.get("garrison_spawned") as Dictionary).duplicate()
	w.call("_dive_materialize_garrison", 10.0)
	var marks: Dictionary = run.get("garrison_spawned")
	_ok(marks.size() > marked_before.size(),
		"...and once you HAVE been down, the garrison around you wakes (%d entries)"
			% (marks.size() - marked_before.size()))
	_ok(int(w.get("_dive_materialized")) == marks.size(),
		"one mark per body handed out, and no body without a mark (%d / %d)"
			% [int(w.get("_dive_materialized")), marks.size()])
	_ok(int(w.get("_dive_held_in_view")) >= 0,
		"...and the run counts what it held back for being too close (%d)"
			% int(w.get("_dive_held_in_view")))

	# Where the model says every entry of this run stands, keyed. Used three
	# times below, so it is built once.
	var sv: int = int(run.get("seed_v"))
	var places := {}
	for tile in DiveRun.RING.size():
		for d2 in range(2, DiveRun.DEPTHS + 1):
			for g in DiveRun.tile_garrison(sv, tile, d2,
					Tunables.get_num("dive_zone_tile_widths")):
				var grow := g as Dictionary
				places[String(grow["key"])] = w.call("dive_garrison_pos",
					grow, pl.global_position)

	var far_marked := 0
	var pending := 0
	for key in places:
		if marked_before.has(key):
			continue   # marked on an earlier pass, from somewhere else
		var d3: float = (places[key] as Vector2).distance_to(pl.global_position)
		if not marks.has(key):
			pending += 1
			continue
		if d3 > reach:
			far_marked += 1
	_ok(far_marked == 0,
		"nothing beyond %.0f px was given a body (%d strays)" % [reach, far_marked])
	_ok(pending > 0,
		"...and the rest of the sky is still waiting to be flown at (%d pending)"
			% pending)

	# NOTHING WAS BORN ON SCREEN. The bubble is the max-zoom frame's far corner;
	# the live frame is tighter still, and both are asserted because the live one
	# is what the owner actually sees.
	var live_half := float(w.call("view_half_width_px"))
	var inside_bubble := 0
	var inside_frame := 0
	var too_far := 0
	var lit: Array = w.get("_dive_surged")
	for sid2 in lit:
		var pk := instance_from_id(sid2) as Ship
		if pk == null or not is_instance_valid(pk):
			continue
		var d4: float = pk.global_position.distance_to(pl.global_position)
		if d4 <= horizon:
			inside_bubble += 1
		if d4 <= live_half:
			inside_frame += 1
		if d4 > reach:
			too_far += 1
	_ok(inside_frame == 0,
		"no picket was born inside the live frame (half-width %.0f px, %d inside)"
			% [live_half, inside_frame])
	_ok(inside_bubble == 0,
		"...nor inside a MAX-zoom one (%.0f px, %d inside)" % [horizon, inside_bubble])
	_ok(too_far == 0, "...and none of them beyond the radius either (%d)" % too_far)
	_ok(lit.size() <= Tunables.get_int("dive_picket_cap"),
		"the picket cap still bounds the live population (%d of %d)"
			% [lit.size(), Tunables.get_int("dive_picket_cap")])
	_ok(lit.size() < Tunables.get_int("dive_picket_cap"),
		"...with room left for the den's pulse (garrison share %.2f)"
			% Tunables.get_num("dive_garrison_share"))

	# --- 3. THE SLEEPING-HUNTERS TRAP (v0.118.0, do NOT let it back in) -----
	# A materialized picket is tens of thousands of px out — far outside the
	# 12,000 px dormancy range — so without the `_dive_surged` exemption it is put
	# to sleep on the next scan and its brain never runs. That bug ate a whole
	# version and fired ZERO shells across a 21-surge run.
	var was_dorm := Tunables.get_bool("dormancy_enabled")
	Tunables.set_value("dormancy_enabled", true)
	w.call("_update_dormancy", 60.0)
	var slept := 0
	var unexempt := 0
	var frozen := 0
	var hunting := 0
	var hostiles := 0
	var farthest := 0.0
	var aggro: Dictionary = w.get("_enemy_aggro")
	for sid3 in (w.get("_dive_surged") as Array):
		var pk2 := instance_from_id(sid3) as Ship
		if pk2 == null or not is_instance_valid(pk2):
			continue
		farthest = maxf(farthest, pk2.global_position.distance_to(pl.global_position))
		if pk2.dormant:
			slept += 1
		if not Dormancy.is_exempt(pk2, w):
			unexempt += 1
		if pk2.process_mode == Node.PROCESS_MODE_DISABLED:
			frozen += 1
		if pk2.faction == 1:
			hostiles += 1
			if bool(aggro.get(sid3, false)) and bool(w.call("_is_provoked", sid3)):
				hunting += 1
	_ok(slept == 0,
		"a materialized picket %.0f px out is NEVER put to sleep (%d slept)"
			% [farthest, slept])
	_ok(unexempt == 0, "...every one of them is dormancy-exempt (%d were not)" % unexempt)
	_ok(frozen == 0,
		"...and its brain is actually running — nothing left the process tree (%d did)"
			% frozen)
	_ok(hostiles > 0 and hunting == hostiles,
		"...and a crewed one is born hunting, like a surge picket (%d of %d)"
			% [hunting, hostiles])
	Tunables.set_value("dormancy_enabled", was_dorm)

	# --- 4a. THE SURGE IS BORN BEYOND THE HORIZON --------------------------
	# It used to be clamped to 1,800..5,600 px, which is INSIDE the helm view —
	# the pop the owner reported. The floor is the max-zoom frame's far corner
	# plus a margin now, so a surge flies in from the edge instead of appearing.
	var pre: Array = (w.get("_dive_surged") as Array).duplicate()
	w.call("_dive_surge")
	var surge_min := INF
	var surge_max := 0.0
	var surge_born := 0
	for sid4 in (w.get("_dive_surged") as Array):
		if pre.has(sid4):
			continue
		var pk3 := instance_from_id(sid4) as Ship
		if pk3 == null or not is_instance_valid(pk3):
			continue
		surge_born += 1
		var d5: float = pk3.global_position.distance_to(pl.global_position)
		surge_min = minf(surge_min, d5)
		surge_max = maxf(surge_max, d5)
	if surge_born > 0:
		_ok(surge_min > live_half,
			"a surge picket is born past the live horizon (nearest %.0f px vs %.0f)"
				% [surge_min, live_half])
		_ok(surge_min >= horizon,
			"...past a MAX-zoom one too (%.0f px vs %.0f)" % [surge_min, horizon])
		_ok(surge_max < horizon * 4.0,
			"...but near enough to actually arrive (farthest %.0f px)" % surge_max)
	else:
		_ok(true, "the cap was full, so this surge added nothing (correct)")

	# --- 4b. A *KILLED* SKY STAYS CLEARED ----------------------------------
	# THIS CLAIM WAS INVERTED BY THE DESCENT SEAL (DESCENT §2.4 / §10.4, owner
	# call 4). It used to read "a cleared sky stays cleared": the wake cull
	# CONSUMED an entry, so a picket you flew away from never came back. With a
	# seal locked to the standing garrison that rule locks the door forever — the
	# survivors of a half-fought rung would be marked spawned, gone, and not dead,
	# and the band could never open. So the cull now UNMARKS: `garrison_spawned`
	# means "has a body right now", and only a KILL is permanent.
	var was_marked: Dictionary = (run.get("garrison_spawned") as Dictionary).duplicate()
	for sid5 in (w.get("_dive_surged") as Array):
		var pk4 := instance_from_id(sid5) as Ship
		if pk4 != null and is_instance_valid(pk4):
			pk4.global_position = pl.global_position + Vector2(0.0, 400000.0)
	w.call("_dive_cull_the_wake", 2.0)
	_ok((w.get("_dive_surged") as Array).is_empty(),
		"the wake cull clears what the run left behind (%d left)"
			% (w.get("_dive_surged") as Array).size())
	var still_marked := 0
	var wrongly_killed := 0
	for key2 in was_marked:
		if bool(run.call("garrison_is_spawned", String(key2))):
			still_marked += 1
		if bool(run.call("garrison_is_killed", String(key2))):
			wrongly_killed += 1
	_ok(was_marked.size() > 0 and still_marked == 0,
		"...handing every entry it freed back to PENDING (%d of %d still held)"
			% [still_marked, was_marked.size()])
	_ok(wrongly_killed == 0,
		"...and counting none of them dead — a cull is not a kill (%d)" % wrongly_killed)
	w.call("_dive_materialize_garrison", 10.0)
	var returned := 0
	for sid6 in (w.get("_dive_surged") as Array):
		var pk5 := instance_from_id(sid6) as Ship
		if pk5 == null or not is_instance_valid(pk5):
			continue
		for key3 in was_marked:
			if pk5.global_position.distance_to(places[key3] as Vector2) < 1.0:
				returned += 1
	_ok(returned > 0,
		"...so a garrison you left alive is standing there again when you come back (%d)"
			% returned)


## MACHINES PLACE AS BUNDLES at 8× (owner 2026-08-25: "an engine will never
## be a single block, but a rectangle or square"). The real 8× world is the
## only place this is observable — at 1× every bundle collapses to one cell
## by design — so the whole verb path runs here: stamp on, all-or-nothing,
## deconstruct whole, primitives untouched.
func _check_machine_bundles(world: Node, local) -> void:
	# A spot where a 4×4 engine fits: scan for an aim cell whose stamp is
	# all-empty and touches the hull (the deck top guarantees candidates).
	var aim := Vector2i.ZERO
	var found_spot := false
	for b in local.blocks:
		var c: Vector2i = b + Vector2i(0, -2)
		if BuildPreview.stamp_valid(local,
				BuildPreview.stamp_cells(local, c, BlockDB.Type.ENGINE)):
			aim = c
			found_spot = true
			break
	_ok(found_spot, "a 4×4 engine stamp fits somewhere against the hull")
	if not found_spot:
		return

	var before: int = local.blocks.size()
	world.select_build("block", BlockDB.Type.ENGINE)
	_ok(world.build_selection_label() == "build: Engine 4×4",
		"the cycle cue names the engine's shape (%s)" % world.build_selection_label())
	_ok(world.try_build_block(local, aim), "Q stamps the engine")
	_ok(local.blocks.size() == before + 16,
		"and the WHOLE 4×4 lands — 16 cells, never a single block (%d -> %d)"
			% [before, local.blocks.size()])
	var all_engine := true
	var engine_cell := Vector2i.ZERO
	for c in BuildPreview.stamp_cells(local, aim, BlockDB.Type.ENGINE):
		if not local.has_block(c) or int(local.blocks[c]["type"]) != BlockDB.Type.ENGINE:
			all_engine = false
		else:
			engine_cell = c
	_ok(all_engine, "every stamped cell is an engine cell")

	# ALL-OR-NOTHING still holds UNDERNEATH the magnet: the raw stamp over the
	# standing machine is illegal — the snap (checked further down) is what
	# finds a seat beside it, never a partial overlap.
	_ok(not BuildPreview.stamp_valid(local,
			BuildPreview.stamp_cells(local, aim, BlockDB.Type.ENGINE)),
		"the raw stamp over the standing machine stays refused (all-or-nothing)")
	_ok(local.blocks.size() == before + 16, "and probing placed nothing")

	# DECONSTRUCT WHOLE: C on any engine cell removes the machine, not a sliver.
	_ok(world.try_remove_block(local, engine_cell),
		"C on one engine cell deconstructs")
	_ok(local.blocks.size() == before,
		"...the WHOLE machine — all 16 cells gone (%d)" % local.blocks.size())

	# THE MAGNET (owner 2026-08-25: "almost impossible to place... it does not
	# snap"): aim 3 cells above the seat that worked — the centred stamp
	# floats there, which the old all-or-nothing simply refused — and the
	# snap slides it to the nearest legal seat instead.
	world.select_build("block", BlockDB.Type.ENGINE)
	var seat: Array = BuildPreview.snapped_stamp(
		local, aim + Vector2i(0, -3), BlockDB.Type.ENGINE)
	_ok(not seat.is_empty(), "the snap finds a legal seat for the floating aim")
	_ok(world.try_build_block(local, aim + Vector2i(0, -3)),
		"and Q places there — no pixel-perfect hover needed")
	_ok(local.blocks.size() == before + 16, "...the whole machine, as ever")
	# Clean up the exact seat directly (the starter carries AUTHORED engines,
	# so a scan-for-any-engine-cell would risk deleting one of those). Bulk:
	# per-cell removal paid a full 194k-cell rebuild SIXTEEN times here.
	local.net_remove_blocks(seat)
	_ok(local.blocks.size() == before, "the snapped machine cleans up exactly")

	# PRIMITIVES are untouched: hull still places and removes cell by cell.
	world.select_build("block", BlockDB.Type.HULL)
	var hull_at := aim + Vector2i(0, 1)  # right against the deck block the scan anchored on
	_ok(world.try_build_block(local, hull_at), "a hull block still places")
	_ok(local.blocks.size() == before + 1, "...as ONE cell (freeform sculpting)")
	_ok(world.try_remove_block(local, hull_at) and local.blocks.size() == before,
		"and C takes back exactly that one cell")

	# The 8× palette lists the propeller twice — both mountings, chosen by
	# the cycle key, no new binding.
	var rots := 0
	var blocks_listed := 0
	for e in world._build_palette():
		if e["kind"] == "block":
			blocks_listed += 1
			if int(e["id"]) == BlockDB.Type.PROPELLER:
				rots += 1
	# type_count() − 1: the STRUT left the player-facing palette (owner
	# 2026-09-01) — the type survives for the authored nests/hulk/deck, but
	# neither B nor the drafting table offers it. (DOOR-open out, rotated
	# propeller in: those two still cancel.)
	_ok(rots == 2 and blocks_listed == BlockDB.type_count() - 1,
		"the 8× palette offers both propeller mountings and no strut (%d block entries)"
			% blocks_listed)
	var strut_listed := false
	for e2 in world._build_palette():
		if e2["kind"] == "block" and int(e2["id"]) == BlockDB.Type.STRUT:
			strut_listed = true
	_ok(not strut_listed, "the strut is not offered by the build palette")

	# SPAWN FINDS THE HELM (owner drafts 1 and 2 both moved the helm and both
	# broke boot on the old constant spawn cell). The fixture is the owner's own
	# first drafting-table export: the berth the world derives for it must land
	# inside ITS helm bundle — not at the constant — and a helmless grid must
	# fall back to the constant rather than crash.
	var draft: Dictionary = ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/drafts/starter_owner_draft_1.ship"), 8)
	if draft.is_empty():
		_ok(false, "the owner-draft spawn fixture loads")
	else:
		var off: Vector2 = world._spawn_offset_for_cells(draft)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for hc in draft:
			if int(draft[hc]) == BlockDB.Type.HELM:
				lo = Vector2(minf(lo.x, hc.x), minf(lo.y, hc.y))
				hi = Vector2(maxf(hi.x, hc.x), maxf(hi.y, hc.y))
		var helm_px := Rect2(lo * Ship.CELL, (hi - lo + Vector2.ONE) * Ship.CELL)
		_ok(helm_px.grow(Ship.CELL * 2.0).has_point(off),
			"a moved helm moves the spawn with it (off %s)" % str(off))
		_ok(off != Vector2(world.PLAYER_SPAWN_CELL) * Ship.CELL * world.world_scale,
			"...and it is derived, not the constant")
		var helmless := {Vector2i(0, 0): BlockDB.Type.HULL}
		_ok(world._spawn_offset_for_cells(helmless)
				== Vector2(world.PLAYER_SPAWN_CELL) * Ship.CELL * world.world_scale,
			"a helmless blueprint falls back to the constant")
	world.select_build("block", BlockDB.Type.PROPELLER, true)
	_ok(world.build_selection_label() == "build: Propeller 2×6",
		"the rotated propeller reads 2×6 (%s)" % world.build_selection_label())
	world.select_build("block", BlockDB.Type.HULL)
	await process_frame


func _enemy_shot_exists(world: Node) -> bool:
	for child in world.get_children():
		if child is Shot and (child as Shot).faction != 0:
			return true
	return false


## THE LAUNCH DECK, AT THE SCALE THE OWNER PLAYS. Everything about the Dive's
## deck is geometry against a body 144 px tall in a world where a hull is twelve
## thousand px wide, and the legacy suite — which is where the deck was checked
## until now — runs at scale 1, where a stray ×world_scale is ×1 and invisible.
## Four rewrites of this deck passed that suite while the shipped game had the
## ships a hundred thousand pixels away. So the reachability numbers are asserted
## HERE, in the world the owner actually boots.
func _check_dive_deck_at_8x(world: Node) -> void:
	if not world.has_method("begin_dive"):
		_ok(false, "the 8x world can start a dive")
		return
	world.call("begin_dive")
	await world.get_tree().physics_frame
	var pl = world.get("player")
	var fleet = world.get("fleet")
	if pl == null or not is_instance_valid(pl) or fleet == null:
		_ok(false, "a body on the launch deck")
		return
	# A screen at the on-foot zoom is about 6,500 x 3,600 px at 8x. A candidate
	# has to be inside roughly that, or it is the report the owner filed twice:
	# "they're not even visible - you have to jump down and hope to land near
	# one".
	var seen := 0
	var nearest := INF
	var top_gap := INF
	for hull in fleet.ships():
		# ...not the DECK, which is faction 0 and a structure. Counting it read
		# as "nearest hull 0 px away", which is true and useless.
		if not is_instance_valid(hull) or hull.faction != 0 or hull.is_nest 				or hull.creature_kind != "" or hull.is_carcass():
			continue
		var dx: float = absf(hull.global_position.x - pl.global_position.x)
		var dy: float = hull.global_position.y - pl.global_position.y
		nearest = minf(nearest, dx)
		if dy > 0.0:
			top_gap = minf(top_gap,
				hull.global_position.y - hull.solid_bounds.size.y * 0.5
					- pl.global_position.y)
		if dx < 14000.0 and dy > 0.0 and dy < 12000.0:
			seen += 1
	# The numbers were written against the pre-0.110.0 SCREEN (~6,500 px wide on
	# foot); the 2026-08-31 flat 40% zoom-out widened the view to ~12,400 px, so
	# these thresholds are now CONSERVATIVE — a berth inside 14,000 px is barely
	# more than one screen of walking, and a hull top 2,000 px down is well in
	# frame. Kept as-is on purpose: they still pin "visible from the deck", just
	# with margin.
	_ok(seen >= 2,
		"at 8x, two hulls are berthed within sight and below (%d; nearest %.0f px)"
			% [seen, nearest])
	_ok(nearest < 14000.0,
		"...and the closest berth is about a screen away (%.0f px)" % nearest)
	_ok(top_gap < 2000.0,
		"...with its deck visible below your feet, not off-screen (%.0f px down)"
			% top_gap)

	# A SAVED SHIP IS A CANDIDATE (Q-T). `_seed_saved_ships` wrote Test_Skiff.ship
	# into the redirected `user://ships` before this world booted; the deck must
	# have moored it under a hatch, with its helm takeable, and must have ignored
	# the garbage file sitting beside it.
	var saved: Ship = null
	for hull in fleet.ships():
		if is_instance_valid(hull) and (hull as Ship).bounty == 4242:
			saved = hull as Ship
	_ok(saved != null, "the player’s saved ship is moored on the launch deck")
	if saved != null:
		_ok(saved.faction == 0 and not saved.is_nest and saved.has_helm(),
			"...as a faction-0 hull with a helm")
		# AT ITS TRUE SIZE. The fixture is 8 authored cells across, so at 8x it is
		# 8 x Ship.CELL x 8 = 1024 px. Upscaling a file that is ALREADY at the
		# world's granularity (an F2 `export_ship`, which carries a `scale`
		# header) would put an 8192 px hull here instead - the eightfold family,
		# in the one directory a player can drop any file into.
		_ok(absf(saved.solid_bounds.size.x - 8.0 * Ship.CELL * 8.0) < Ship.CELL * 8.0,
			"...at its authored granularity, not upscaled twice (%.0f px beam)"
				% saved.solid_bounds.size.x)
		# UNDER A HATCH, not merely nearby: the hull’s own centre lines up with a
		# berth centre. That is the whole geometry the deck exists for, and it is
		# the number four rewrites of it got wrong.
		var mid := saved.global_position.x + saved.solid_bounds.position.x \
			+ saved.solid_bounds.size.x * 0.5
		var best := INF
		for b in (world.call("dive_berth_positions") as Array):
			best = minf(best, absf(float((b as Dictionary)["pos"].x) - mid))
		_ok(best < Ship.CELL * 8.0 * 2.0,
			"...centred under a hatch (%.0f px off the berth centre)" % best)
		_ok(saved.global_position.y > pl.global_position.y,
			"...and below the walkway, where you drop through to it")
		# BOARDABLE — the point of the whole feature is diving with the ship you
		# designed, and a candidate you cannot take the helm of is scenery.
		var was: Vector2 = pl.global_position
		pl.global_position = saved.to_global(saved.local_pos_of(saved.helm_cells[0]))
		await world.get_tree().physics_frame
		_ok(pl.board(saved, saved.helm_cells[0]), "...and its helm is boardable")
		pl.disembark()
		pl.global_position = was
		await world.get_tree().physics_frame
	# The garbage file cost a candidate and nothing else: with both berths taken
	# by the starter and the saved skiff, the Loft was never needed.
	var helmed := 0
	for hull in fleet.ships():
		var h := hull as Ship
		if is_instance_valid(h) and h.faction == 0 and not h.is_nest \
				and h.creature_kind == "" and not h.is_carcass() and h.has_helm():
			helmed += 1
	_ok(helmed == 2,
		"an unparseable file in user://ships is skipped in silence (%d candidates, not 3)"
			% helmed)
	# THE STARTER CAN ACTUALLY FLY THE MODE (owner 2026-08-31: "can you use
	# the default starter ship in dive mode in a test? It's impossible to move
	# sideways"). Board the NON-Loft candidate — the starter — and hold full
	# right for three real seconds: it must cover ground and must not brown-out
	# doing it. The native-8× file measured 94 px/s peak here; the 1×-authored,
	# upscaled, upgraded ship measures ~500.
	# THE BIGGEST CANDIDATE IS THE STARTER. It used to be "the first one that is
	# not the Loft", which stopped being an identification the moment a PLAYER’S
	# saved ship could be moored beside it (Q-T) — and the failure would have been
	# the flight numbers below quietly measuring somebody’s eight-cell skiff.
	var starter = null
	for s2 in fleet.ships():
		if not is_instance_valid(s2) or s2.faction != 0 or s2.creature_kind != "" 				or s2.is_carcass() or s2.is_nest or not s2.has_helm():
			continue
		if starter == null or s2.blocks.size() > starter.blocks.size():
			starter = s2
	_ok(starter != null, "the starter is moored on the deck")
	if starter != null and pl != null and is_instance_valid(pl):
		pl.global_position = starter.to_global(starter.local_pos_of(starter.helm_cells[0]))
		await world.get_tree().physics_frame
		_ok(pl.board(starter, starter.helm_cells[0]), "boarded the starter at its helm")
		await world.get_tree().physics_frame
		var x0: float = starter.global_position.x
		Input.action_press("ship_right")
		for i in 240:
			await world.get_tree().physics_frame
		Input.action_release("ship_right")
		var dx: float = starter.global_position.x - x0
		# 800 -> 4000 (owner 2026-09-01, "extremely slow in every way"): the root
		# was the air the props breathe, strangled in the thin start air (0.15).
		# The floor is `dive_air_floor` now (0.85, and LIFT feels it too), and the
		# same hull covers ~11,700 px here — `tools/lateral_probe.gd` measures
		# 5,030 px/s peak, a ring tile in 3 s. This bound GUARDS the floor: drop
		# it back toward 0.15 and this reddens instead of the owner finding out
		# in play.
		_ok(dx > 4000.0,
			"four seconds of full right moves the starter briskly (%.0f px)" % dx)
		_ok(starter.power_supply() >= starter.active_draw() * 0.95,
			"...without browning out (supply %.0f vs draw %.0f)"
				% [starter.power_supply(), starter.active_draw()])

		# THE AIR FLOOR IS REAL AUTHORITY (DESIGN_DIVE_REVIEW §1.3). Measured on
		# this hull at the deck: weight 501,652,476, buoyancy at the shipped
		# floor 264,929,280 — so a neutral stick with the floor OFF is a very
		# different fall from one with it on. This is the whole of slice 2 in
		# one comparison, and it is scale-only: at 1x the deck does not exist.
		var floored_sink := await _neutral_sink(world, starter, Tunables.get_num("dive_air_floor"))
		var vacuum_sink := await _neutral_sink(world, starter, 0.0)
		_ok(floored_sink < vacuum_sink * 0.8,
			"the air floor buys real altitude authority (sinks %.0f px/s vs %.0f in the vacuum)"
				% [floored_sink, vacuum_sink])

		# THE VERTICAL STICK COMMANDS A SPEED (DESIGN_DIVE_REVIEW §3.2). Three
		# claims about the hull the owner actually flies, inside a run.
		#
		# MEASURED FIRST, per the round's brief: at the review's first floor (0.5) the
		# starter could not hover at the deck at all, and no controller could make
		# it. It is a balloon ship — buoyancy 264,929,280 against a weight of
		# 501,652,476 leaves its lift props a deficit of 236,723,196 to find,
		# and at full deflection they produce 81,920,000: 35% of it. The stick
		# saturates and the hull sinks. Break-even for this hull is a floor of
		# 0.72; a comfortable hover wants ~0.8 — which is why the SHIPPED default is
		# 0.85. The engines were deliberately NOT retuned (owner's call); the
		# controller is measured at the shipped floor, set explicitly so an F2 edit
		# cannot leak in.
		_ok(starter.rate_control,
			"in a run the starter's vertical stick commands a rate")
		Tunables.set_value("dive_air_floor", 0.85)
		# ...IN STILL AIR. Since v0.141.0 the run's weather is an AIRSTREAM the
		# hull rides (`Ship.extra_wind`), and the stick commands a speed RELATIVE
		# to it — so a rate measured in the updraft would be the rate plus the
		# tile, and this block is about the controller. The weather has its own
		# block right below, where the composition is the thing being measured.
		Tunables.set_value("dive_zone_wind_mult", 0.0)
		Tunables.set_value("dive_ceiling_mult", 0.0)
		var want_down: float = Tunables.get_num("dive_dive_rate") * 8.0
		var want_up: float = Tunables.get_num("dive_climb_rate") * 8.0
		# Linear damping takes its cut of any commanded rate: at HOVER_DAMP 2.0
		# against the hull's damp of 0.4 the controller settles at 2/2.4 of what
		# it was asked for, which is why these bounds are a third rather than a
		# tenth. The number in the message is the one that matters.
		Input.action_press("ship_down")
		for i in 180:
			await world.get_tree().physics_frame
		var vy_down: float = starter.linear_velocity.y
		Input.action_release("ship_down")
		# The retired `dive_descent_max` was 240 px/s at 1x and this is the same
		# number — the felt cap survived; it is the stick's own scale now rather
		# than a per-tick write into `linear_velocity`.
		_ok(absf(vy_down - want_down) < want_down * 0.35,
			"holding DOWN settles at the rate it asks for (%.0f px/s, asked %.0f)"
				% [vy_down, want_down])
		# NEUTRAL: the controller's v_target is 0, which is term-for-term the
		# hover that has always shipped.
		for i in 90:
			await world.get_tree().physics_frame
		var hold_y0: float = starter.global_position.y
		for i in 120:
			await world.get_tree().physics_frame
		var drift: float = absf(starter.global_position.y - hold_y0)
		_ok(drift < 900.0,
			"a NEUTRAL stick holds altitude for two seconds (drifted %.0f px)" % drift)
		# UP: a real climb, at the rate the lever names.
		var up_y0: float = starter.global_position.y
		Input.action_press("ship_up")
		for i in 180:
			await world.get_tree().physics_frame
		var vy_up: float = starter.linear_velocity.y
		Input.action_release("ship_up")
		_ok(starter.global_position.y < up_y0 - 1000.0,
			"holding UP actually climbs (rose %.0f px in 3 s)"
				% (up_y0 - starter.global_position.y))
		_ok(absf(-vy_up - want_up) < want_up * 0.35,
			"...at the rate it asks for (%.0f px/s, asked %.0f)" % [-vy_up, want_up])

		# --- THE CLOSING SKY IS A LEASH, ON THE REAL HULL -------------------
		# (owner call 2, review §3.3 — v0.141.0.) The arithmetic is pinned pure in
		# `run_tests._test_dive_weather`; what only 8x can say is whether the
		# SHIPPED starter, at the shipped rates, actually loses the climb one rung
		# over the line and wins it a quarter rung over. Nothing is teleported —
		# the CEILING is moved to the hull by setting the run's low-water mark, so
		# the body never leaves the helm it is flying from.
		var wrun = world.get("dive")
		Tunables.set_value("dive_ceiling_mult", 1.0)
		if wrun != null:
			wrun.deepest = maxi(int(wrun.deepest), 3)
			var here_frac: float = float(world.call("_player_altitude_frac"))
			# A FULL RUNG over the line: the air runs down at 1,200 px/s against a
			# 960 px/s climb, so full UP is a fall you are slowing. No commuting.
			wrun.low_frac = here_frac - 1.75 * DiveRun.rung_frac()
			starter.linear_velocity = Vector2.ZERO
			Input.action_press("ship_up")
			for i in 150:
				await world.get_tree().physics_frame
			var vy_leash: float = starter.linear_velocity.y
			Input.action_release("ship_up")
			_ok(vy_leash > 0.0,
				"a rung above the closed sky, full UP still DESCENDS (vy %.0f)" % vy_leash)
			_ok(starter.extra_wind.y > 0.0,
				"...because the air itself is running down past it (%.0f px/s)"
					% starter.extra_wind.y)
			# A QUARTER rung over: 300 px/s down against the same 960 — you pop up
			# to the ledge. This is the half of the ruling a rail could never do.
			var here2: float = float(world.call("_player_altitude_frac"))
			wrun.low_frac = here2 - 1.0 * DiveRun.rung_frac()
			starter.linear_velocity = Vector2.ZERO
			Input.action_press("ship_up")
			for i in 150:
				await world.get_tree().physics_frame
			var vy_pop: float = starter.linear_velocity.y
			Input.action_release("ship_up")
			_ok(vy_pop < 0.0,
				"a quarter rung over, the same stick CLIMBS through it (vy %.0f)" % vy_pop)
		Tunables.reset_all()
		pl.disembark()
	world.call("end_dive")
	await world.get_tree().physics_frame


## Neutral-stick sink rate, px/s, with the run's air floor set to `floor_v`.
## Two seconds is enough: the hull is at terminal within one. Leaves the lever
## where it found it is the CALLER's job — both uses here are followed by an
## explicit set or a reset_all.
func _neutral_sink(world: Node, hull, floor_v: float) -> float:
	Tunables.set_value("dive_air_floor", floor_v)
	hull.linear_velocity = Vector2.ZERO
	for i in 120:
		await world.get_tree().physics_frame
	return hull.linear_velocity.y


## THE PLAYER’S SAVED SHIPS, as the Dive will find them (Q-T). Two files:
##
##   Test_Skiff.ship — a small, legal vessel with a helm. `bounty 4242` is its
##     FINGERPRINT: a saved hull has no name on the body, and finding it by block
##     count would be a test that passes for the wrong reason the first time
##     somebody edits the starter. The bounty header rides to `Ship.bounty`, so
##     one number both identifies the hull and proves a header survived mooring.
##
##   broken.ship — garbage. `user://ships` is a directory a player can put
##     anything in, and the boot of a run is the worst place to raise it: it must
##     cost a candidate, never the run.
##
## Written fresh every time, into the redirected directory, so a stale file from
## an earlier run can never change what this suite measures.
func _seed_saved_ships() -> void:
	var dir := ShipLayout.user_dir
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var entry := d.get_next()
		while entry != "":
			if not d.current_is_dir():
				DirAccess.remove_absolute(
					ProjectSettings.globalize_path(dir.path_join(entry)))
			entry = d.get_next()
		d.list_dir_end()
	_write_user_ship("Test_Skiff.ship",
		"# a suite fixture, not shipped content\n"
		+ "name Test Skiff\nkind vessel\nbounty 4242\norigin 4 1\n\n"
		+ "GGGGGGGG\n##H##E##\n")
	_write_user_ship("broken.ship", "{\"not\": \"a ship\"}\nnothing here\n")


func _write_user_ship(basename: String, body: String) -> void:
	var f := FileAccess.open(ShipLayout.user_dir.path_join(basename), FileAccess.WRITE)
	if f == null:
		print("    FAIL could not seed %s" % basename)
		return
	f.store_string(body)
	f.close()


func _ok(condition: bool, detail: String) -> void:
	if condition:
		print("    ok   %s" % detail)
	else:
		failures += 1
		print("    FAIL %s" % detail)


func _finish() -> void:
	if failures == 0:
		print("\nSCALE STARTUP: PASS\n")
		quit(0)
	else:
		print("\nSCALE STARTUP: FAIL — %d problem(s)\n" % failures)
		quit(1)
