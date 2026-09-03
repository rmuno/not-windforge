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
		await _check_dive_seam_is_seamless(w, pl, rect, ring_w, cx, terrain)
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
				w.call("dive_weather_at", hull2.global_position)):
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
				w.call("dive_weather_at", pl.global_position)),
			"an enemy hull at YOUR position feels your weather exactly (%s)"
				% moved_one.extra_wind)

	await _check_dive_garrison_materializes(w, pl, run, cx)
	# LAST, deliberately: this one runs six real seconds of world, which would
	# advance the run out from under the garrison checks above (they measure a
	# live world with nothing awaited between the set-up and the assertion).
	await _check_dive_picket_holds_its_rung(w, pl, cx)

	w.queue_free()
	await process_frame


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
