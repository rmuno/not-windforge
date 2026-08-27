extends SceneTree

## The WHALE-SANDWICH probe (owner 2026-08-27): does a silhouette-tracing living-
## creature collider reintroduce the FPS cliff the single AABB box was fixing?
##
## The cliff (Ship._coarse_creature_rects): the 2D solver's cost under deep
## penetration scales with overlapping shape PAIRS (~O(whale_shapes ×
## other_shapes) per substep), not cell count — a provoked pod piling onto the
## player near terrain measured ~36 ms avg / ~206 ms peak with per-cell shapes,
## and one box per creature collapsed it to a few ms. This probe recreates that
## pile-up (whales spawned deeply overlapping ON the player's ship, which stays
## AWAKE because it is the focus) and measures TIME_PHYSICS_PROCESS + broadphase
## pairs for a range of collider detail levels, so the new default is chosen on
## numbers, not hope.
##
##   godot --headless --path . --script tools/collider_probe.gd

const PILE := 5          # whales heaped onto the player
const SETTLE := 2        # frames before sampling (start measuring while deeply overlapped)
const SAMPLE := 34       # frames averaged
## Super-cell sizes to compare. 400 ≈ the OLD single AABB (the whole body folds
## into ~1 box); the rest trace the silhouette at finer and finer detail.
const FACTORS := [400, 20, 12, 8, 6]


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 60:
		await process_frame
	var player = world.get("player")
	var pile: Vector2 = player.global_position if player != null else Vector2.ZERO
	print("--- whale sandwich: %d whales heaped on the player's ship ---" % PILE)
	print("cells/box |  phys ms |  pairs | active | shapes tot/worst  (400 ≈ old single box)")
	for d in FACTORS:
		Tunables.set_value("creature_coarse_cells", d)
		var whales: Array = []
		for i in PILE:
			# Tiny offsets → the bodies spawn DEEPLY overlapped, the worst case.
			var off := Vector2(float(i - 2) * 12.0, float(i - 2) * 9.0)
			var w = world.call("debug_spawn", "whale", pile + off)
			if w != null:
				whales.append(w)
		for f in SETTLE:
			await process_frame
		var phys := 0.0
		var pairs := 0.0
		var active := 0.0
		for f in SAMPLE:
			await process_frame
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			pairs += Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
			active += Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
		var shapes := 0
		var worst := 0
		for w in whales:
			if not is_instance_valid(w):
				continue
			var n := 0
			for ch in w.get_children():
				if ch is CollisionShape2D:
					n += 1
			shapes += n
			worst = maxi(worst, n)
		print("%9d | %8.1f | %6.0f | %6.0f | %d / %d"
			% [d, phys / SAMPLE, pairs / SAMPLE, active / SAMPLE, shapes, worst])
		for w in whales:
			if is_instance_valid(w):
				w.queue_free()
		for f in 12:
			await process_frame
	print("--- done ---")
	quit(0)
