extends SceneTree

## World-TRAVERSAL probe (owner 2026-08-27: "how long to go from one end to the
## other" — is the halved world an expedition or a commute?). Flies the shipped
## starter at FULL thrust in open sky until its speed plateaus (drag balances
## thrust), then reports the world's extent, the ship's top speed on each axis,
## and the end-to-end crossing time at that speed.
##
##   godot --headless --path . --script tools/traverse_probe.gd

const RUN_SECONDS := 25.0


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame
	var ship = world.get("local_ship")
	var rect: Rect2 = world.get("_world_rect")
	var scale := maxf(float(world.get("world_scale")), 1.0)
	var cell_px := Ship.CELL * scale

	var top_h := await _plateau(world, ship, rect, Vector2(1.0, 0.0), true)
	var top_v := await _plateau(world, ship, rect, Vector2(0.0, -1.0), false)

	var w := rect.size.x
	var h := rect.size.y
	print("\n================ WORLD TRAVERSAL ================")
	print("World extent : %.0f x %.0f px   (%.0f x %.0f coarse cells, cell %.0f px, %.0fx)"
		% [w, h, w / cell_px, h / cell_px, cell_px, scale])
	print("Starter top  : %.0f px/s across   %.0f px/s vertical" % [top_h, top_v])
	if top_h > 1.0:
		print("Cross WIDTH  : %.1f min  (%.0f s) at full horizontal thrust" % [w / top_h / 60.0, w / top_h])
	if top_v > 1.0:
		print("Cross HEIGHT : %.1f min  (%.0f s) at full vertical thrust" % [h / top_v / 60.0, h / top_v])
	print("(Real trips are slower: wind, terrain, and turning all cost time.)")
	print("================================================")
	quit(0)


## Accelerate `ship` at `dir` thrust from a clear spot until its speed on the
## relevant axis stops rising, and return that plateau speed (px/s).
func _plateau(world: Node, ship, rect: Rect2, dir: Vector2, horizontal: bool) -> float:
	# Park it high and central — open sky, clear of most terrain.
	ship.set("global_position", Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.14))
	ship.set("linear_velocity", Vector2.ZERO)
	ship.set("angular_velocity", 0.0)
	for i in 30:
		await process_frame
	var top := 0.0
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < RUN_SECONDS:
		ship.set("thrust_input", dir)
		await physics_frame
		t += dt
		var v: Vector2 = ship.get("linear_velocity")
		top = maxf(top, absf(v.x) if horizontal else absf(v.y))
	ship.set("thrust_input", Vector2.ZERO)
	return top
