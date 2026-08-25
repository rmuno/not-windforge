extends SceneTree

## Scratch repro for "krakens fall endlessly" (owner 2026-08-25). Boots the
## legacy 1x world, debug-spawns a kraken high in the air, and logs its
## altitude + AI phase for a few seconds of physics.

func _initialize() -> void:
	var packed: PackedScene = load("res://maps/scale_test/scale_test.tscn") \
		if false else load(ProjectSettings.get_setting("application/run/main_scene"))
	var world: Node = packed.instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var at: Vector2 = world.get("SHIP_START") + Vector2(4000.0, -2000.0) * world.get("world_scale")
	var kraken = world.debug_spawn("kraken", at)
	if kraken == null:
		print("SPAWN FAILED"); quit(1); return
	print("spawned at y=%.0f  mass=%.0f  lift=%.1f  unsupported=%.0f" % [
		kraken.global_position.y, kraken.mass, kraken._total_lift, kraken.unsupported_weight()])
	for sec in 12:
		for i in 60:
			await physics_frame
		if not is_instance_valid(kraken):
			print("kraken freed"); break
		print("t=%2ds  y=%8.0f  vy=%7.0f" % [sec + 1, kraken.global_position.y, kraken.linear_velocity.y])
	quit(0)
