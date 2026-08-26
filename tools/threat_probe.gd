extends SceneTree

## Does the night's chain actually COMPOSE? (v0.63–0.65.)
##
## Fire, the basilisk, hazard ignition and the prop wash were each built and
## tested on their own. Every one of those tests holds the other systems still
## — which is exactly how a set of individually-correct pieces ships a broken
## whole. The chain the player will actually meet is:
##
##   a basilisk rears → spits → the slug flies → it strikes a hull →
##   the strike rolls to IGNITE → the fire spreads through what burns →
##   the wand puts it out
##
## and nothing in the suite walks all of it. This does, in the real world
## scene, and prints where it stops if it stops.
##
##   godot --headless --path . --script tools/threat_probe.gd

func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame
	var fleet = world.get("fleet")
	var mine = world.get("local_ship")
	if fleet == null or mine == null:
		print("no world")
		quit(1)
		return

	# Pressure, not patience: a spit a second, and a certain ignition. Both are
	# levers precisely so the owner can do the opposite.
	Tunables.set_value("fire_enabled", true)
	Tunables.set_value("basilisk_spit_seconds", 1.0)
	Tunables.set_value("fire_ignite_chance", 1.0)
	Tunables.set_value("spawn_sites_enabled", false)

	var beast = world.call("debug_spawn", "basilisk",
		mine.global_position + Vector2(260.0 * world.world_scale, -200.0))
	if beast == null:
		print("no basilisk")
		quit(1)
		return
	print("basilisk %d cells vs a %d-cell hull, %.0f px apart\n" % [
		beast.blocks.size(), mine.blocks.size(),
		beast.global_position.distance_to(mine.global_position)])

	var slugs := 0
	var burning_peak := 0
	var lost := 0
	var cells0: int = mine.blocks.size()
	for i in 60 * 40:
		await physics_frame
		slugs = maxi(slugs, root.get_tree().get_nodes_in_group("hazard_fireballs").size())
		burning_peak = maxi(burning_peak, mine.burning.size())
		if i % (60 * 5) == 0:
			print("  t=%2ds  slugs live %d   hull %d   beast %d   burning %d+%d  gap %.0f  beast hp %.0f" % [
				i / 60, root.get_tree().get_nodes_in_group("hazard_fireballs").size(),
				mine.blocks.size(), beast.blocks.size(), mine.burning.size(),
				beast.burning.size(),
				beast.global_position.distance_to(mine.global_position),
				beast.shared_health])
		if burning_peak > 0 and i > 60 * 16:
			break
	lost = cells0 - mine.blocks.size()

	print("\nCHAIN")
	print("  spat         %s" % ("yes" if slugs > 0 else "NO — the brain never fired"))
	print("  struck       %s (%d hull cells gone)"
		% ["yes" if lost > 0 else "NO — nothing reached the hull", lost])
	print("  ignited      %s (peak %d cells alight)"
		% ["yes" if burning_peak > 0 else "NO — a strike never set anything alight",
			burning_peak])

	# ...and the wand ends it.
	if mine.burning.size() > 0:
		var at: Vector2 = mine.to_global(mine.local_pos_of(mine.burning.keys()[0]))
		var before: int = mine.burning.size()
		for i in 40:
			Fire.douse(mine, at, Ship.CELL * 8.0 * world.world_scale, 0.05,
				world._fire_clock)
			await physics_frame
		print("  doused       %s (%d -> %d cells)"
			% ["yes" if mine.burning.size() < before else "NO — the wand did nothing",
				before, mine.burning.size()])
	quit(0)
