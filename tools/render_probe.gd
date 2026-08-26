extends SceneTree

## WHAT DOES THE RENDERED FRAME COST? (the owner's 2026-08-26 capture, part 2.)
##
## The capture's physics census ruled the solver out (`pairs=4 shapes=45`) and
## the per-system stopwatch (tools/tick_probe.gd) prices the world's whole tick
## at well under a millisecond. `proc` was 3 ms and `phys` 33-50 ms of a ~250 ms
## frame at 4 FPS, so most of that frame was going somewhere neither monitor
## could see — and the only render number in the log was `draws`, which is the
## BATCHED total and says nothing about how much geometry went into it.
##
## This runs WITH A RENDERER (no --headless — it opens a window on purpose) and
## reads debug/frame_census.gd before and after a big creature is parked in
## front of the camera, which is the owner's repro: a whale pressed against the
## hull, filling the view.
##
##   godot --path . --script tools/render_probe.gd

const SETTLE := 240
const SAMPLE := 240


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in SETTLE:
		await process_frame
	await _report(world, "the world as it starts")

	# The repro: something large, right where the camera is looking.
	var cam: Variant = world.get("camera")
	var at: Vector2 = (cam as Camera2D).get_screen_center_position() if cam != null \
		else Vector2.ZERO
	var big: Ship = world.call("debug_spawn", "kraken", at + Vector2(600.0, 0.0))
	if big != null:
		big.freeze = true
	for i in SAMPLE:
		await process_frame
	await _report(world, "with a kraken parked in the view")

	# And the same body's skin after it has been SHOT UP, which is what
	# fragments the greedy merge — the render-side twin of the collider bug.
	if big != null:
		var n := 0
		for c in big.blocks.keys():
			if n % 7 == 0:
				big.call("damage_cell", c, 100000.0)
			n += 1
		big.call("rebuild")
	for i in SAMPLE:
		await process_frame
	await _report(world, "...and after it is holed")
	quit(0)


func _report(world: Node, what: String) -> void:
	print("\n%s" % what)
	print("  %s" % FrameCensus.line(world))
	print("  %s" % PhysicsCensus.line(world))
	await process_frame
