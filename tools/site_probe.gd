extends SceneTree

## What the world-anchored spawn sites actually look like (charter §4).
## Density is the whole design: too sparse and the sky is the empty room the
## sites exist to fix; too dense and every direction is the same, which is the
## camera-ring failure with extra steps. This prints the real numbers — sites
## per band across the whole world, what sits near spawn, and how long a flight
## it is between them — and then boots the world and watches one site fill up.
##
##   godot --headless --path . --script tools/site_probe.gd

func _initialize() -> void:
	var scale := 8.0
	var cp := TerrainDB.CELL * scale
	var wr := IslandGen.WORLD_CELLS
	var world_rect := Rect2(Vector2(wr.position) * cp, Vector2(wr.size) * cp)
	var step := SpawnSites.LATTICE * scale
	print("world %.0f x %.0f px, lattice %.0f px -> %d x %d cells" % [
		world_rect.size.x, world_rect.size.y, step,
		int(world_rect.size.x / step), int(world_rect.size.y / step)])

	var counts := {}
	var total := 0
	var cols := int(world_rect.size.x / step)
	var rows := int(world_rect.size.y / step)
	for cy in rows:
		for cx in cols:
			var site := SpawnSites.site_at(Vector2i(cx, cy), 1234, world_rect, scale)
			if site.is_empty():
				continue
			total += 1
			var k := SpawnSites.kind_name(site["kind"])
			counts[k] = int(counts.get(k, 0)) + 1
	print("%d sites over %d cells (%.0f%% occupied)" % [
		total, cols * rows, 100.0 * total / float(cols * rows)])
	for k in counts:
		print("   %-14s %4d" % [k, counts[k]])

	# The neighbourhood: what a player at spawn could reach.
	var spawn := Vector2(0, -1200.0 * scale)
	for r in [9000.0, 40000.0, 150000.0]:
		var near := SpawnSites.near([spawn], r, 1234, world_rect, scale)
		var nearest := "-"
		var best := INF
		for site in near:
			var d: float = spawn.distance_to(site["pos"] as Vector2)
			if d < best:
				best = d
				nearest = "%s at %.0fk px" % [SpawnSites.kind_name(site["kind"]), d / 1000.0]
		print("within %6.0fk px of spawn: %d sites   nearest: %s"
			% [r / 1000.0, near.size(), nearest])

	# --- the live world ---------------------------------------------------
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 60:
		await process_frame
	var fleet = world.get("fleet")
	print("\nboot: %d ships" % (fleet.call("ships") as Array).size())

	# Put the player next to the nearest site and let it fill.
	var pl = world.get("player")
	var sites: Array = SpawnSites.near([pl.global_position], 400000.0,
		world.get("world_seed"), world.get("_world_rect"), 8.0)
	if sites.is_empty():
		print("no site within reach — density is too low")
		quit(1)
		return
	var target: Dictionary = sites[0]
	print("flying to the %s at %s" % [SpawnSites.kind_name(target["kind"]), target["pos"]])
	Tunables.set_value("site_regen_seconds", 5.0)
	pl.global_position = (target["pos"] as Vector2) + Vector2(0, -2000.0)
	for i in 60 * 45:
		await physics_frame
		if i % (60 * 5) == 0:
			var residents := 0
			for sh in (fleet.call("ships") as Array):
				if is_instance_valid(sh) and (sh as Ship).from_spawn_site:
					residents += 1
			print("  t=%2ds  ships=%d  site residents=%d  dormant=%s" % [
				i / 60, (fleet.call("ships") as Array).size(), residents,
				str(world.get("dormant_count"))])
	quit(0)
