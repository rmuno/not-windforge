extends SceneTree

## WHERE DOES THE PHYSICS TICK GO? (the owner's 2026-08-26 capture.)
##
## That capture ruled the solver out — `pairs=4 active=13 shapes=45`, a physics
## world with essentially nothing in it — while `phys` read 33-50 ms. What is
## left inside a physics frame is OUR OWN SCRIPT: the world's systems, every
## Ship's `_physics_process`, and the player's. This prints the first of those
## three, per system, in milliseconds per tick, using the same stopwatch the F3
## capture's SYS line uses.
##
## Headless is a FLOOR, not the owner's number: no camera, no renderer, and a
## fresh world has none of what a played session accumulates. A system that is
## already hot HERE is hot everywhere.
##
##   godot --headless --path . --script tools/tick_probe.gd

const WARMUP := 180
const SAMPLE := 600


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in WARMUP:
		await physics_frame
	print("world: %d ships, scale %d" % [
		(world.get("fleet").call("ships") as Array).size(), world.get("world_scale")])
	print(PhysicsCensus.line(world))

	world.set("sys_timing_forced", true)
	world.call("take_system_ms")  # drop the warm-up
	var t0 := Time.get_ticks_usec()
	for i in SAMPLE:
		await physics_frame
	var wall := float(Time.get_ticks_usec() - t0) * 0.001 / float(SAMPLE)
	var acc: Dictionary = world.call("take_system_ms")
	world.set("sys_timing_forced", false)

	var rows: Array = []
	var total := 0.0
	for key in acc:
		var ms: float = float(acc[key]) / float(SAMPLE)
		total += ms
		rows.append([key, ms])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	print("\n%-14s %10s" % ["system", "ms/tick"])
	for r in rows:
		if float(r[1]) < 0.001:
			continue
		print("%-14s %10.3f" % [r[0], r[1]])
	print("%-14s %10.3f" % ["TOTAL", total])
	print("\nwall clock per frame: %.3f ms (paced at 60 Hz — the loop SLEEPS," % wall)
	print("so this is not a load figure; the per-system numbers above are.)")
	quit(0)
