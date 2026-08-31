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

	_finish()


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
	_ok(rots == 2 and blocks_listed == BlockDB.type_count(),
		"the 8× palette offers both propeller mountings (%d block entries)"
			% blocks_listed)
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
