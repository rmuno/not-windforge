extends SceneTree

## Does the world stay BOUNDED over a long flight? (v0.61–0.63.)
##
## Three features landed in one night that all add bodies to the sky: spawn
## sites put residents out, nests stand where they are raised, and fire eats
## what it stands on. Each is bounded by its own rule — a global resident cap,
## reclaim-and-refund past 45k px, dormancy past 12k — but "each is bounded"
## and "the sum is bounded" are different claims, and the second one is the one
## the player experiences.
##
## So: fly a focus in a straight line across the world for several simulated
## minutes and watch what accumulates. Ships, nodes, residents, nests, dormant
## bodies and the per-tick physics cost — the numbers that would show a leak as
## a slope instead of a spike.
##
##   godot --headless --path . --script tools/long_flight_probe.gd

## Flight speed in px per physics tick, and how long to fly. 900 px/tick at
## 60 Hz is ~54,000 px/s — far faster than a ship flies, on purpose: this is a
## stress pass over a lot of world, not a playthrough.
const SPEED := 900.0
const MINUTES := 4.0
const SAMPLE_EVERY := 600  # ticks (10 s at 60 Hz)


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame
	var fleet = world.get("fleet")
	var pl = world.get("player")
	if fleet == null or pl == null:
		print("no world")
		quit(1)
		return

	print("flying %.0f px/tick for %.0f simulated minutes\n" % [SPEED, MINUTES])
	print("%6s %7s %7s %8s %7s %8s %9s %9s" % [
		"t (s)", "ships", "resid", "nests", "dormant", "nodes", "burning", "ms/tick"])

	var ticks := int(MINUTES * 60.0 * 60.0)
	var t0 := Time.get_ticks_usec()
	var window := 0
	for i in ticks:
		pl.global_position.x += SPEED
		await physics_frame
		window += 1
		if window >= SAMPLE_EVERY:
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / window
			t0 = Time.get_ticks_usec()
			window = 0
			_report(world, fleet, i / 60.0, ms)
	quit(0)


func _report(world: Node, fleet, secs: float, ms: float) -> void:
	var ships := 0
	var residents := 0
	var nests := 0
	var burning := 0
	for s in (fleet.call("ships") as Array):
		if not is_instance_valid(s):
			continue
		var ship := s as Ship
		ships += 1
		if ship.from_spawn_site:
			residents += 1
		if ship.is_nest:
			nests += 1
		burning += ship.burning.size()
	print("%6.0f %7d %7d %8d %7s %8d %9d %9.2f" % [
		secs, ships, residents, nests, str(world.get("dormant_count")),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		burning, ms])
