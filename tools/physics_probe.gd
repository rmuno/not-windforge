extends SceneTree

## Headless PHYSICS-COST probe (owner 3-FPS capture, 2026-08-25).
##
## The whale_diag SUM lines from that session read:
##
##     proc=2.1-6.3 ms   phys=30-87 ms   draws=95   ships=11   contacts=0
##
## Script is ~2 ms and render is 95 draw calls, so the frame is the PHYSICS
## step -- and `contacts` was 0 in 2,207 of 2,376 rows, so it is NOT the
## multi-body penetration cliff v0.41.1 fixed. Something costs tens of
## milliseconds with nothing touching, which points at the BROADPHASE: Godot
## pairs bodies whose AABBs overlap and narrow-phases every pair every step,
## whether or not they end up in contact.
##
## So this counts what the physics server itself reports -- active bodies,
## collision PAIRS, islands -- as creatures are added one at a time, and
## prints the per-body shape counts that feed them.
##
##   godot --headless --path . --script tools/physics_probe.gd

const WHALES := 9
const SETTLE := 30
const SAMPLE := 40


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 60:
		await process_frame

	var fleet = world.get("fleet")
	var player = world.get("player")
	print("--- baseline (the shipped world, before any spawn) ---")
	await _report(world, fleet)

	# Match the owner's capture: a pod of whales in the neighbourhood.
	var at: Vector2 = player.global_position if player != null else Vector2.ZERO
	for i in WHALES:
		# Spread them out -- the log showed contacts=0, so they were NOT
		# piled up, and a pile-up would measure the already-known cliff
		# instead of whatever this is.
		var off := Vector2(2400.0 * ((i % 3) - 1), 1800.0 * ((i / 3) - 1))
		world.call("debug_spawn", "whale", at + off)
		for f in 6:
			await process_frame
	print("\n--- with %d more whales (the owner's ~11-ship scene) ---" % WHALES)
	await _report(world, fleet)
	quit(0)


func _report(world: Node, fleet) -> void:
	for i in SETTLE:
		await process_frame
	var phys := 0.0
	var pairs := 0.0
	var active := 0.0
	var islands := 0.0
	for i in SAMPLE:
		await process_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		pairs += Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
		active += Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
		islands += Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)

	var ships: Array = fleet.ships()
	var shapes := 0
	var biggest := 0
	var coarse := 0
	for s in ships:
		var n := 0
		for c in (s as Node).get_children():
			if c is CollisionShape2D:
				n += 1
		shapes += n
		biggest = maxi(biggest, n)
		if s.shared_health_max > 0.0 and s.shared_health > 0.0:
			coarse += 1

	var terrain = world.get("terrain")
	var chunk_shapes := 0
	var chunks := 0
	for c in (terrain as Node).get_children():
		if c is TerrainChunk:
			chunks += 1
			chunk_shapes += (c as TerrainChunk)._collider_rects.size()

	print("  phys frame     %8.3f ms" % (phys / SAMPLE))
	print("  collision pairs%8.1f      active bodies %.1f   islands %.1f"
		% [pairs / SAMPLE, active / SAMPLE, islands / SAMPLE])
	print("  ships %d (%d living/coarse)   %d shapes total, worst body %d"
		% [ships.size(), coarse, shapes, biggest])
	print("  terrain %d promoted chunks, %d static shapes" % [chunks, chunk_shapes])
