extends SceneTree

## Headless script-cost probe for the hot per-frame paths. Frame pacing
## makes wall-clock frame timing useless headless, so this times direct
## calls to the suspects instead — good before/after numbers for perf
## rounds. (Rendering cost is invisible here; that part is judged in the
## editor with the FPS counter.)
##
##   godot --headless --path . --script tools/perf_probe.gd

const REPS := 120


func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	var world: Node = packed.instantiate()
	root.add_child(world)
	for i in 20:
		await process_frame

	var fleet = world.get("fleet")
	var ships: Array = fleet.ships()
	var player = world.get("player")
	var total_blocks := 0
	for s in ships:
		total_blocks += s.blocks.size()
	print("%d ships, %d blocks total" % [ships.size(), total_blocks])

	var t0 := Time.get_ticks_usec()
	for i in REPS:
		for s in ships:
			s._physics_process(1.0 / 60.0)
	_report("Ship._physics_process (all ships)", t0)

	t0 = Time.get_ticks_usec()
	for i in REPS:
		Player.find_helm(ships, player.global_position, player.HELM_REACH)
	_report("Player.find_helm", t0)

	t0 = Time.get_ticks_usec()
	for i in REPS:
		Player.find_door(ships, player.global_position, 192.0)
	_report("Player.find_door", t0)

	t0 = Time.get_ticks_usec()
	for i in REPS:
		world.call("_creature_swim", 1.0 / 60.0)
	_report("world._creature_swim (whales)", t0)

	quit(0)


func _report(label: String, t0: int) -> void:
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("%-38s %7.3f ms/frame" % [label, ms / REPS])
