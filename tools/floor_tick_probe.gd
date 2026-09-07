extends SceneTree

## WHAT DOES A PHYSICS TICK COST AT THE DIVE FLOOR, AND WHO SPENT IT?
##
## The owner's 2026-09-07 capture (whale_diag.log, 663 lines) was taken at the
## deep end of a run: the Leviathan (28,096 cells) plus seven 10k-cell kraken
## bodies, 11 ships, 56 live shots, `fps=1-2 ticks=7-8` — physics falling so far
## behind that Godot ran its catch-up ceiling of eight steps per drawn frame,
## each of them costing what a whole frame is allowed to. `SYS total` was 5-6.7
## ms of it. The other ~95% had never been measured, because nothing measured it:
## `tick_probe` times the world's own systems and stops there.
##
## So this probe stands the FLOOR population up headless and times the tick with
## an attribution that adds up:
##
##     wall per tick  =  world (SYS + its tail)  +  every Ship's callbacks
##                       +  the player  +  the shots  +  the solver
##
## The first four are stopwatched from inside the callbacks (`debug/tick_perf.gd`);
## the solver is the remainder, which is the only honest way to get it — the
## physics server is C++ and has no per-step script hook.
##
##   godot --headless --path . --script tools/floor_tick_probe.gd
##   godot --headless --path . --script tools/floor_tick_probe.gd -- --seed 892583619
##   godot --headless --path . --script tools/floor_tick_probe.gd -- --shots 0
##
## HEADLESS IS A FLOOR, NOT THE OWNER'S NUMBER: no renderer, no camera. A cost
## that is already here is here everywhere, and the rendered-frame estimate at
## the bottom (ticks × the catch-up ceiling) is what the owner sees.
##
## Names no `class_name` as a type on purpose (CODEMAP §4): a --script file that
## does compiles that class before the autoloads exist.

const WARMUP := 90       ## ticks to settle after the population stands up
const SAMPLE := 240      ## ticks measured

var world: Node = null
var fleet = null
var pl = null


func _arg(name: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == name and i + 1 < args.size():
			return int(String(args[i + 1]))
	return fallback


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	var perf: GDScript = load("res://debug/tick_perf.gd")
	world = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 40:
		await process_frame
	fleet = world.get("fleet")
	pl = world.get("player")

	var pinned := _arg("--seed", 0)
	if pinned != 0:
		world.call("pin_dive_seed", pinned)
	world.call("begin_dive")
	await _frames(10)

	# --- Take a hull the way a player does ---------------------------------
	var hull = _nearest_hull()
	if hull == null:
		print("!! no candidate hull on the deck")
		return quit(1)
	pl.global_position = hull.to_global(hull.local_pos_of(hull.helm_cells[0]))
	await _frames(2)
	pl.board(hull, hull.helm_cells[0])
	await _frames(4)
	var run: Object = world.get("dive") as Object
	print("\n=== THE DIVE FLOOR — what one physics tick costs (8x, the shipped scene) ===")
	print("SEED %d   committed %s" % [int(run.get("seed_v")), str(run.get("committed"))])

	# --- DROP TO THE FLOOR --------------------------------------------------
	# Not flown: `dive.advance` reads the player's altitude fraction, so putting
	# the body (and its hull) at depth-8 altitude IS arriving there — the run
	# fires its own "depth" and "leviathan" events, cuts the landing, wakes the
	# boss and materializes the rung's garrison through the world's own code.
	# Flying down takes minutes of wall clock and lands somewhere different every
	# seed; the population is what this probe is measuring, not the descent.
	var floor_at: Vector2 = world.call("dive_landing_pos", 8)
	world.call("_cut_landing", 8)
	var hull_now = world.get("local_ship")
	hull_now.global_position = floor_at + Vector2(0.0, -1200.0)
	hull_now.linear_velocity = Vector2.ZERO
	pl.global_position = hull_now.to_global(hull_now.local_pos_of(hull_now.helm_cells[0]))
	await _frames(30)
	print("at the floor: depth %d   leviathan awake: %s"
		% [int(run.get("depth")), str(_count_kind("leviathan") > 0)])

	# --- STAND THE RESIDENTS UP --------------------------------------------
	# The capture had eight creature bodies at the floor. The garrison
	# materializes on its own clock and the dens are a place you fly PAST, so the
	# probe spawns the rest through the world's own `_spawn_one_kraken` — the same
	# call the dens use, the same pool-then-rebuild ordering, the same coarse
	# collider — spread around the landing so they do not stack into one island.
	# `world.KRAKEN_PLANS` verbatim — a const is not reachable through `get()`.
	var plans := ["res://ships/kraken_c.ship", "res://ships/kraken_b.ship",
		"res://ships/kraken_nautilus.ship", "res://ships/kraken_angler.ship",
		"res://ships/kraken_urchin.ship"]
	var want := _arg("--krakens", 7)
	for i in want:
		var at := floor_at + Vector2(-6000.0 + 1800.0 * float(i), -2600.0 - 400.0 * float(i % 3))
		var k = world.call("_spawn_one_kraken", String(plans[i % plans.size()]), at)
		if k != null and is_instance_valid(k):
			# Listed like the boss, so the dormancy scan cannot put them to sleep
			# where they stand and quietly measure an empty sky (see
			# `_dive_wake_leviathan`'s note on exactly that trap).
			(world.get("_dive_surged") as Array).append(k.get_instance_id())
	await _frames(20)

	# --- AND THE SHOT SWARM -------------------------------------------------
	# 56 live Shot nodes in the capture. Fired from the hull's own turrets would
	# take a minute of aiming; the population is the point, so they are placed
	# directly — same class, same group, same per-tick work.
	var shots := _arg("--shots", 56)
	_seed_shots(shots, floor_at)
	await _frames(WARMUP)

	# --- MEASURE ------------------------------------------------------------
	print("\npopulation: %s" % _population_line())
	print(PhysicsCensus.line(world))

	world.set("sys_timing_forced", true)
	world.call("take_system_ms")           # drop the warm-up
	perf.reset()
	perf.on = true
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_physics_frames()
	var d0 := Engine.get_process_frames()
	for i in SAMPLE:
		await physics_frame
		# The swarm dies as it flies (rock is close at the floor). Keep the
		# population the capture had, or the second half of the sample measures a
		# quieter world than the first.
		if (i % 20) == 0:
			# Billed, and NOT to the solver: instancing nodes is the probe's own
			# work, and an unbilled cost inside the sample loop would land in the
			# remainder and be read as physics.
			var t_seed := Time.get_ticks_usec()
			_seed_shots(shots - get_nodes_in_group("shots").size(), floor_at)
			perf.bill("probe: reseed shots", t_seed)
	var ticks := int(Engine.get_physics_frames() - f0)
	var drawn := maxi(int(Engine.get_process_frames() - d0), 1)
	var wall := float(Time.get_ticks_usec() - t0) * 0.001 / float(maxi(ticks, 1))
	perf.on = false
	var sys: Dictionary = world.call("take_system_ms")
	world.set("sys_timing_forced", false)

	# --- REPORT -------------------------------------------------------------
	# The physics side and the IDLE side are separate budgets and must not be
	# added up as if they were one: a saturated loop runs several physics steps
	# per drawn frame, so a millisecond of `_process` is amortised across all of
	# them while a millisecond of `_physics_process` is paid by every one. Idle
	# rows are reported per DRAWN FRAME and folded into the per-tick remainder at
	# their true share, which is what makes the columns add up.
	var phys_ms := 0.0
	var idle_ms := 0.0
	var probe_ms := 0.0
	var phys_rows: Array = []
	var idle_rows: Array = []
	for r in perf.rows(ticks):
		if String(r[0]).begins_with("probe: "):
			probe_ms += float(r[1])
			continue
		if String(r[0]).begins_with("idle: "):
			idle_rows.append(r)
			idle_ms += float(r[1])
		else:
			phys_rows.append(r)
			phys_ms += float(r[1])
	print("\n--- WHO SPENT THE TICK (%d ticks / %d drawn frames sampled) ---"
		% [ticks, drawn])
	print("%-34s %9s %9s" % ["callback", "ms/tick", "calls"])
	for r in phys_rows:
		if float(r[1]) < 0.005:
			continue
		print("%-34s %9.3f %9.1f" % [String(r[0]), float(r[1]), float(r[2])])
	print("%-34s %9.3f" % ["  physics-side script", phys_ms])
	print("%-34s %9.3f   (%.3f ms per IDLE frame)"
		% ["  idle-side script, amortised", idle_ms,
			idle_ms * float(ticks) / float(drawn)])
	print("%-34s %9.3f   <- the harness's own node churn, not the game"
		% ["  the probe itself", probe_ms])
	print("%-34s %9.3f   <- the physics server itself (2D solver + broadphase)"
		% ["  servers + engine (remainder)",
			maxf(wall - phys_ms - idle_ms - probe_ms, 0.0)])
	print("%-34s %9.3f" % ["WALL PER TICK", wall])
	if not idle_rows.is_empty():
		print("\n--- ...and the IDLE frame (ms per idle frame) ---")
		for r in idle_rows:
			var per_frame := float(r[1]) * float(ticks) / float(drawn)
			if per_frame < 0.005:
				continue
			print("%-34s %9.3f" % [String(r[0]), per_frame])

	print("\n--- ...and inside `world` (the SYS line's systems) ---")
	var sys_rows: Array = []
	var sys_total := 0.0
	for key in sys:
		var ms: float = float(sys[key]) / float(maxi(ticks, 1))
		sys_total += ms
		sys_rows.append([key, ms])
	sys_rows.sort_custom(func(a, b) -> bool: return float(a[1]) > float(b[1]))
	for r in sys_rows:
		if float(r[1]) < 0.005:
			continue
		print("%-34s %9.3f" % [String(r[0]), float(r[1])])
	print("%-34s %9.3f" % ["SYS TOTAL", sys_total])

	# THE NUMBER THE OWNER SEES. Godot runs up to `max_physics_steps_per_frame`
	# catch-up steps per drawn frame; once a tick overruns its budget the frame
	# costs all of them, which is the spiral the capture recorded.
	var ceiling := int(ProjectSettings.get_setting(
		"physics/common/max_physics_steps_per_frame", 8))
	var steps := 1 if wall <= 1000.0 / 60.0 else ceiling
	print("\nRENDERED FRAME ESTIMATE: %.1f ms/tick x %d catch-up steps = %.0f ms/frame"
		% [wall, steps, wall * float(steps)])
	print("  ~%.1f fps before the renderer has drawn anything (budget: 16.7 ms/tick)"
		% (1000.0 / maxf(wall * float(steps), 0.001)))
	quit(0)


## Every live body, biggest first — so a reader can see the population the
## numbers above were measured against without trusting this file's arithmetic.
func _population_line() -> String:
	var rows: Array = []
	for s in (fleet.call("ships") as Array):
		if not is_instance_valid(s):
			continue
		rows.append([(s as Ship).perf_label(), (s as Ship).blocks.size()])
	rows.sort_custom(func(a, b) -> bool: return int(a[1]) > int(b[1]))
	var names: Array = []
	var total := 0
	for r in rows:
		names.append(String(r[0]))
		total += int(r[1])
	return "%d ships, %d cells, %d shots — %s" % [rows.size(), total,
		get_nodes_in_group("shots").size(), ", ".join(names)]


func _count_kind(kind: String) -> int:
	var n := 0
	for s in (fleet.call("ships") as Array):
		if is_instance_valid(s) and (s as Ship).creature_kind == kind:
			n += 1
	return n


## Put `n` live shells in the air around the floor, aimed nowhere in particular.
## A Shot is a plain Node2D with its own `_physics_process`; what it costs does
## not depend on who fired it.
func _seed_shots(n: int, at: Vector2) -> void:
	if n <= 0:
		return
	var shot_scene: GDScript = load("res://combat/shot.gd")
	for i in n:
		var s = shot_scene.new()
		s.position = at + Vector2(-4000.0 + 140.0 * float(i), -3000.0 - 30.0 * float(i % 17))
		s.velocity = Vector2(600.0 if (i % 2) == 0 else -600.0, -200.0)
		s.faction = 1
		s.add_to_group("shots")
		world.add_child(s)


func _nearest_hull():
	var best = null
	var best_d := INF
	for s in (fleet.call("ships") as Array):
		var ship := s as Ship
		if ship == null or not is_instance_valid(ship) or ship.is_nest:
			continue
		if ship.creature_kind != "" or not ship.has_helm():
			continue
		var d: float = ship.global_position.distance_to(pl.global_position)
		if d < best_d:
			best_d = d
			best = ship
	return best
