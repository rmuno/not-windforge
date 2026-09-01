extends SceneTree

## POP-IN FORENSICS (owner 2026-09-01: "enemies still hella pop in, and so do
## their markers"). Boots the REAL dive scene, commits to the starter, drives
## DOWN for a while, and logs EVERY ship that enters the fleet: its distance to
## the player at the spawn frame, the current live-view half-diagonal, the
## max-zoom bubble, and whether it was inside either. Names the guilty spawn
## path instead of guessing at it.

const STEP := 1.0 / 60.0

func _initialize() -> void:
	var packed: PackedScene = load("res://maps/dive/dive.tscn")
	var world = packed.instantiate()
	root.add_child(world)
	for i in 40:
		await process_frame
	var fleet = world.get("fleet")
	var pl = world.get("player")
	print("\n=== POP-IN PROBE (dive.tscn) ===")
	var seen := {}
	for s in fleet.ships():
		seen[s.get_instance_id()] = true
	# Board the first candidate and commit.
	var starter = null
	for s in fleet.ships():
		if not is_instance_valid(s) or s.faction != 0 or s.creature_kind != "":
			continue
		if s.is_carcass() or not s.has_helm() or s.is_nest:
			continue
		starter = s
		break
	if starter == null:
		print("!! no candidate")
		return quit()
	pl.global_position = starter.to_global(starter.local_pos_of(starter.helm_cells[0]))
	await world.get_tree().physics_frame
	pl.board(starter, starter.helm_cells[0])
	await world.get_tree().physics_frame
	print("committed: %s" % str((world.get("dive") as Object).get("committed")))
	var cam: Camera2D = world.get("camera")
	var bubble: float = world.call("max_view_horizon_px") if world.has_method("max_view_horizon_px") else -1.0
	print("max-zoom bubble: %.0f px" % bubble)
	Input.action_press("ship_down")
	var t := 0.0
	var popins := 0
	var spawns := 0
	while t < 150.0:
		await world.get_tree().physics_frame
		t += STEP
		if not is_instance_valid(starter):
			print("t=%.0f hull destroyed — continuing on foot" % t)
			starter = null
			break
		for s in fleet.ships():
			if not is_instance_valid(s):
				continue
			var iid: int = s.get_instance_id()
			if seen.has(iid):
				continue
			seen[iid] = true
			spawns += 1
			var d: float = pl.global_position.distance_to(s.global_position)
			# The LIVE view: what is actually on screen right now.
			var vp_size: Vector2 = root.get_viewport().get_visible_rect().size
			var z: float = cam.zoom.x if cam != null and is_instance_valid(cam) else 1.0
			var live_half: float = (vp_size / z).length() * 0.5
			var verdict := "ok"
			if d < live_half:
				verdict = "!!! IN LIVE VIEW"
				popins += 1
			elif bubble > 0.0 and d < bubble:
				verdict = "!! inside max-zoom bubble"
				popins += 1
			print("t=%5.1f  SPAWN %-10s faction=%d  dist=%7.0f  live_half=%6.0f  %s" % [
				t, s.creature_kind if s.creature_kind != "" else "vessel",
				s.faction, d, live_half, verdict])
	Input.action_release("ship_down")
	print("RESULT: %d spawns, %d inside a view (live or bubble)" % [spawns, popins])
	quit()
