extends SceneTree

## THE STARTER'S SIDEWAYS LEGS, measured in a live run (owner 2026-08-31:
## "It's impossible to move sideways"). Boards THE STARTER specifically (never
## the Loft candidate), holds full lateral throttle in open air, and prints the
## speed curve, the distance covered, and — the number that matters — how long
## one WIND-RING tile takes to cross at that speed.
##
## Names no class_name as a type (CODEMAP §4).

const STEP := 1.0 / 60.0

func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	var world = packed.instantiate()
	root.add_child(world)
	for i in 40:
		await process_frame
	var fleet = world.get("fleet")
	var pl = world.get("player")
	print("\n=== LATERAL PROBE (the starter, in a run) ===")
	# ONE BINARY, ONE SKY, TWO DIAL SETS — the dive_probe idiom (v0.160.0)
	# brought here, so a thrust A/B is two runs of one build rather than two
	# checkouts whose other differences ride along in the numbers:
	#   -- --seed 565218463 --lever prop_strength=1.0
	var pinned := _int_arg("--seed")
	if pinned != 0:
		world.call("pin_dive_seed", pinned)
	_apply_lever_args()
	world.call("begin_dive")
	for i in 10:
		await world.get_tree().physics_frame
	# THE STARTER, not whichever hull is nearest: the loft candidate is the
	# world's `_dive_loft`; the boot hull the run un-claimed is the other one.
	var loft = world.get("_dive_loft")
	var starter = null
	for s in fleet.ships():
		if not is_instance_valid(s) or s.faction != 0 or s.creature_kind != "":
			continue
		if s.is_carcass() or not s.has_helm() or s == loft or s.is_nest:
			continue
		starter = s
		break
	if starter == null:
		print("!! no starter candidate found")
		return quit()
	print("starter: %d blocks, %.0f px wide, mass %.0f" % [starter.blocks.size(),
		starter.solid_bounds.size.x, starter.mass])
	pl.global_position = starter.to_global(starter.local_pos_of(starter.helm_cells[0]))
	await world.get_tree().physics_frame
	var took: bool = pl.board(starter, starter.helm_cells[0])
	await world.get_tree().physics_frame
	print("boarded: %s  committed: %s" % [str(took),
		str((world.get("dive") as Object).get("committed"))])
	# Clear air: hover in place a moment, then full RIGHT for eight seconds.
	Input.action_press("ship_right")
	var t := 0.0
	var x0: float = starter.global_position.x
	var peak := 0.0
	var last_x := x0
	while t < 8.0:
		await world.get_tree().physics_frame
		t += STEP
		# The hull can DIE mid-burn now (integrity + a wall) — a freed ref must
		# end the measurement loudly, never crash-loop the probe.
		if not is_instance_valid(starter):
			print("  !! the starter was DESTROYED at t=%.1f (last x %.0f) — the burn ended in a wall" % [t, last_x - x0])
			break
		last_x = starter.global_position.x
		peak = maxf(peak, absf(starter.linear_velocity.x))
		if int(t * 60.0) % 60 == 0:
			print("  t=%.0f  vx=%.0f  dx=%.0f" % [t, starter.linear_velocity.x,
				starter.global_position.x - x0])
	Input.action_release("ship_right")
	if not is_instance_valid(starter):
		print("RESULT: destroyed mid-burn — see above")
		return quit()
	var dx: float = starter.global_position.x - x0
	print("RESULT: 8 s of full right = %.0f px, peak vx %.0f px/s" % [dx, peak])
	var tile_w: float = world.call("_dive_tile_w")
	var ring_w: float = world.call("dive_ring_width")
	var rect: Rect2 = world.get("_world_rect")
	print("RING:   tile %.0f px | ring %.0f px | world width %.0f px" % [
		tile_w, ring_w, rect.size.x])
	if peak > 1.0:
		print("        one tile at peak speed = %.0f s" % (tile_w / peak))
	var g: String = "thrust h=%.0f v=%.0f | power %.0f vs draw %.0f" % [
		starter.get("_total_hthrust"), starter.get("_total_vthrust"),
		starter.power_supply(), starter.active_draw()]
	print("GEAR:   %s" % g)
	print("DAMP:   linear_damp %.2f | mass %.0f | accel(first s) est from curve above" % [
		starter.linear_damp, starter.mass])
	# THE COMPARISON HULL: the Loft ship, same throttle, same air — is the
	# starter authored weak, or is lateral flight itself the bottleneck?
	if loft != null and is_instance_valid(loft):
		pl.disembark()
		await world.get_tree().physics_frame
		pl.global_position = loft.to_global(loft.local_pos_of(loft.helm_cells[0]))
		await world.get_tree().physics_frame
		var took2: bool = pl.board(loft, loft.helm_cells[0])
		await world.get_tree().physics_frame
		print("
LOFT:   %d blocks, %.0f px wide, mass %.0f (boarded %s)" % [
			loft.blocks.size(), loft.solid_bounds.size.x, loft.mass, str(took2)])
		Input.action_press("ship_right")
		var t2 := 0.0
		var lx0: float = loft.global_position.x
		var peak2 := 0.0
		while t2 < 8.0:
			await world.get_tree().physics_frame
			t2 += STEP
			peak2 = maxf(peak2, absf(loft.linear_velocity.x))
		Input.action_release("ship_right")
		print("LOFT RESULT: 8 s = %.0f px, peak vx %.0f px/s | thrust h=%.0f | damp %.2f" % [
			loft.global_position.x - lx0, peak2,
			loft.get("_total_hthrust"), loft.linear_damp])
	quit()


## `--seed N` — user args survive `--script` after a bare `--`.
func _int_arg(name: String) -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return int(args[i + 1]) if i >= 0 and i + 1 < args.size() else 0


## `--lever id=value`, repeatable: set F2 levers before the run opens. Prints
## what it set — a probe run is only quotable with its conditions printed.
func _apply_lever_args() -> void:
	var args := OS.get_cmdline_user_args()
	var set_line := ""
	for i in args.size():
		if String(args[i]) != "--lever" or i + 1 >= args.size():
			continue
		var pair := String(args[i + 1]).split("=", true, 1)
		if pair.size() != 2:
			continue
		var id := pair[0]
		if Tunables.def(id).is_empty():
			print("LEVERS: no such lever '%s' — ignored" % id)
			continue
		var value: Variant = pair[1].to_lower() in ["1", "true", "on"] \
			if String(Tunables.def(id)["kind"]) == "bool" else float(pair[1])
		set_line += "%s=%s " % [id, str(Tunables.set_value(id, value))]
	if set_line != "":
		print("LEVERS: %s(everything else at its shipped default)" % set_line)
