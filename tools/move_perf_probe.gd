extends SceneTree

## Headless repro for "considerable FPS drop from just moving slowly"
## (owner F3 recording 2026-08-25: TIME_PHYSICS_PROCESS ~1.75 -> ~175 per
## 30-frame window once movement starts; draws/nodes flat). Boots the real
## 8x world, holds still, then walks the player slowly; samples the physics
## frame time and the live-chunk population either side.

func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var pl = world.get("player")
	var terr = world.get("terrain")
	# settle + drain the spawn neighbourhood
	for i in 240:
		await physics_frame

	var phases := [
		["still           ", 0.0, true],
		["move,physOFF    ", 900.0, false],  # foci move, no kinematic sim
		["move,physON     ", 900.0, true],   # the real slow walk
		["still2          ", 0.0, true],
	]
	for ph in phases:
		pl.set_physics_process(bool(ph[2]))
		var t_sum := 0.0
		var t_max := 0.0
		var frames := 300
		for i in frames:
			if float(ph[1]) > 0.0:
				pl.global_position.x += float(ph[1]) / 60.0
			await physics_frame
			var t := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			t_sum += t
			t_max = maxf(t_max, t)
		print("%s phys avg %6.2f ms  max %6.2f ms   live chunks %4d" % [
			ph[0], t_sum / frames, t_max, terr.live_chunk_count()])
	quit(0)
