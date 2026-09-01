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

	# ...and LAST OF ALL, a SECOND, SEPARATE boot: the Dive's own scene. It
	# cannot share the world above, because the whole point of it is the world
	# that world is NOT.
	world.queue_free()
	await process_frame
	await _check_dive_scene_boots()

	_finish()


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
		pl.velocity = Vector2.ZERO
		pl.global_position = Vector2(cx + ring_w * 0.5 + tile_w * 0.2,
			pl.global_position.y)
		w.call("_dive_hold_the_ring", 0.016)
		_ok(pl.global_position.x < cx,
			"crossing the seam still arrives from the other side (x-cx %.0f)"
				% (pl.global_position.x - cx))
		_ok(rect.has_point(Vector2(pl.global_position.x, rect.get_center().y)),
			"...and lands INSIDE the world, not through a wall")
		pl.global_position = Vector2(cx, pl.global_position.y)
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

	await _check_dive_garrison_materializes(w, pl, run, cx)

	w.queue_free()
	await process_frame


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
	pl.global_position = Vector2(cx,
		float(w.call("dive_altitude_y", DiveRun.depth_altitude(depth))))
	run.set("depth", depth)

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
			for g in DiveRun.tile_garrison(sv, tile, d2):
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

	# --- 4b. A CLEARED SKY STAYS CLEARED -----------------------------------
	# The wake cull frees a picket you left behind. That entry must NOT come back
	# the next time you fly through: it is spent, for the rest of the run.
	var was_marked: Dictionary = (run.get("garrison_spawned") as Dictionary).duplicate()
	for sid5 in (w.get("_dive_surged") as Array):
		var pk4 := instance_from_id(sid5) as Ship
		if pk4 != null and is_instance_valid(pk4):
			pk4.global_position = pl.global_position + Vector2(0.0, 400000.0)
	w.call("_dive_cull_the_wake", 2.0)
	_ok((w.get("_dive_surged") as Array).is_empty(),
		"the wake cull clears what the run left behind (%d left)"
			% (w.get("_dive_surged") as Array).size())
	var unmarked := 0
	for key2 in was_marked:
		if not bool(run.call("garrison_is_spawned", String(key2))):
			unmarked += 1
	_ok(unmarked == 0,
		"...without un-marking a single entry it freed (%d forgotten)" % unmarked)
	w.call("_dive_materialize_garrison", 10.0)
	var ghosts := 0
	for sid6 in (w.get("_dive_surged") as Array):
		var pk5 := instance_from_id(sid6) as Ship
		if pk5 == null or not is_instance_valid(pk5):
			continue
		for key3 in was_marked:
			if pk5.global_position.distance_to(places[key3] as Vector2) < 1.0:
				ghosts += 1
	_ok(ghosts == 0,
		"...so nothing you already cleared is ever reborn there (%d ghosts)" % ghosts)


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
	# THE STARTER CAN ACTUALLY FLY THE MODE (owner 2026-08-31: "can you use
	# the default starter ship in dive mode in a test? It's impossible to move
	# sideways"). Board the NON-Loft candidate — the starter — and hold full
	# right for three real seconds: it must cover ground and must not brown-out
	# doing it. The native-8× file measured 94 px/s peak here; the 1×-authored,
	# upscaled, upgraded ship measures ~500.
	var loft = world.get("_dive_loft")
	var starter = null
	for s2 in fleet.ships():
		if not is_instance_valid(s2) or s2.faction != 0 or s2.creature_kind != "" 				or s2.is_carcass() or s2.is_nest or s2 == loft or not s2.has_helm():
			continue
		starter = s2
		break
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
		# was dive_thrust_density_floor strangling the props in the thin start air
		# (0.15). Raised to 0.40, the same hull covers ~9,500 px here (peak
		# ~4,000 px/s, a ring tile in ~4 s). This bound GUARDS the floor — drop it
		# back toward 0.15 and this reddens instead of the owner finding out in play.
		_ok(dx > 4000.0,
			"four seconds of full right moves the starter briskly (%.0f px)" % dx)
		_ok(starter.power_supply() >= starter.active_draw() * 0.95,
			"...without browning out (supply %.0f vs draw %.0f)"
				% [starter.power_supply(), starter.active_draw()])
		pl.disembark()
	world.call("end_dive")
	await world.get_tree().physics_frame


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
