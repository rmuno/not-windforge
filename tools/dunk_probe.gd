extends SceneTree

## THE DUNK, MEASURED (DESIGN_KRAKEN §5.1 / §7 slice 5).
##
##   godot --headless --path . --script tools/dunk_probe.gd
##
## The design's headline piece of sharp knowledge is a claim about shipped code,
## not a feature: *"a kraken is held up by MUSCLE, not lift; your lift props blow
## DOWN at WASH_ACCEL 2,600 × 8 = 20,800 px/s² across an 8-cell jet — about
## 2.7 g. Hover directly over a kraken and it sinks under you at a net ~1.7 g;
## over the lava core it is consumed in a few seconds."* Nothing had ever
## measured it. This probe does, on the REAL 8× scene, with the REAL starter, the
## REAL rate controller and the REAL lava core:
##
##   1. THE DUNK. A hunter at the floor over open lava; the shipped starter
##      parked above it with the stick NEUTRAL — which under the rate controller
##      means the lift props are running to hold station, which means downwash.
##      Reported: how close you have to hover for the jet to bite at all, the
##      net downward acceleration it buys, and the SECONDS TO THE CORE.
##   2. THE ROOF. The same hover, over the den's slab. The boss must not sink:
##      that is what makes the dunk a decision instead of the default, and it is
##      the owner's "mini ceiling above it so that it doesn't just randomly die
##      to falling ships".
##
## The design's target is 3–6 SECONDS OF COMMITTED HOVERING — never instant. If
## the measurement comes in under that, `wash_push_mult` is the existing lever to
## turn down; if the jet never bites, that is a finding, not a licence to invent
## a new force.
##
## This is a PROBE, not a test: it measures and prints. The 8× startup suite
## carries the assertion that came out of it.
##
## Names no `class_name` as a TYPE annotation on purpose: a `--script` file that
## does compiles that class before the autoloads exist (CODEMAP §4).

const STEP := 1.0 / 60.0
## How long a single dunk is given before it is called a failure.
const DUNK_CAP_SECONDS := 40.0
## How long the roof is watched holding the boss up.
const ROOF_SECONDS := 10.0

var world: Node
var fleet
var pl


func _initialize() -> void:
	# The owner's real profile is not a fixture — a probe that boots the world
	# writes bestiary sightings like any session.
	Profile.path = "user://profile_dunk_probe.json"
	var packed: PackedScene = load("res://maps/world/world.tscn")
	world = packed.instantiate()
	root.add_child(world)
	for i in 40:
		await process_frame
	fleet = world.get("fleet")
	pl = world.get("player")
	print("\n=== THE DUNK — headless measurement (8x, the shipped scene) ===")

	world.call("begin_dive")
	await _frames(10)
	var hull = _nearest_hull()
	if hull == null:
		print("!! no candidate hull on the deck — nothing to hover with")
		return quit(1)
	pl.global_position = hull.to_global(hull.local_pos_of(hull.helm_cells[0]))
	await _frames(2)
	pl.board(hull, hull.helm_cells[0])
	await _frames(4)
	var run = world.get("dive")
	# THE FLOOR, for real: the rate controller's air floor, the leash and the
	# lava all read the run's depth, and the dunk is a depth-8 move.
	run.set("depth", DiveRun.DEPTHS)
	run.set("deepest", DiveRun.DEPTHS)
	print("hull: %d blocks, %s" % [hull.blocks.size(), _gear(hull)])

	await _measure_the_dunk()
	await _measure_the_roof()
	quit(0)


## --- 1. THE DUNK -----------------------------------------------------------

func _measure_the_dunk() -> void:
	var hull = world.get("local_ship")
	var lava := float((world.get("_lava_core") as Node).call("surface_y"))
	var floor_y: float = world.call("dive_altitude_y",
		DiveRun.depth_altitude(DiveRun.DEPTHS))
	print("\n--- 1. A HUNTER UNDER A HOVERING STARTER ---")
	print("the floor is y %.0f; the core's surface is y %.0f (%.0f px of air between)"
		% [floor_y, lava, lava - floor_y])

	# HOW CLOSE MUST YOU HOVER? The jet is `WASH_RANGE_CELLS` 8 cells long
	# (1,024 px at 8×) and the world samples it at the prey's ORIGIN
	# (`_apply_prop_wash` asks `body.global_position`), which is half a body
	# BELOW its own back. That is not a rhetorical question — it is the
	# difference between a move and a myth. Sampled as a pure function of the
	# hull, with no second body in the reading at all.
	var prop := _lift_prop(hull)
	print("\n  the jet, along its own axis (px below a lift prop's centre):")
	for along in [1100.0, 1024.0, 1000.0, 900.0, 700.0, 500.0, 300.0, 150.0]:
		var a: Vector2 = hull.wash_accel_at(hull.to_global(prop + Vector2(0.0, along))) \
			* Tunables.get_num("wash_push_mult")
		print("    %5.0f px down the jet -> %7.0f px/s^2 (%.2f g)"
			% [along, a.y, a.y / (980.0 * 8.0)])
	var below_prop: float = hull.solid_bounds.end.y - prop.y
	print("    the prop sits %.0f px above this hull's own keel, so a prey whose origin"
		% below_prop)
	print("    is H px under its own back leaves (1024 - %.0f - H) px of clear air."
		% below_prop)

	# THE PREY. Placed over OPEN LAVA, well off the landing column and well below
	# the rungs: a body dropped on a slab is ejected by it the moment terrain
	# streams in, and this probe spent two runs measuring that ejection instead
	# of the jet.
	# STILL AIR, on purpose. The ring's up/down draft is a real wind that lifts a
	# hull AND a kraken (v0.141.0's one-vector doctrine), and at the floor it was
	# measured carrying both of them upward at ~3,600 px/s — which is weather,
	# not the jet. `dive_zone_wind_mult` 0 takes it out of the reading; the roof
	# half below runs with it back on.
	Tunables.set_value("dive_zone_wind_mult", 0.0)
	# ...and the animal merely HOLDS STATION for the physics half of the
	# measurement (see the note printed below). Set before the spawn, or it dives
	# after you and finds the core on its own.
	Tunables.set_value("whale_push_accel", 0.0)
	Tunables.set_value("whale_align_accel", 0.0)
	Tunables.set_value("kraken_wildness", 0.0)
	var aim: Vector2 = world.call("dive_landing_pos", DiveRun.DEPTHS)
	var at := await _open_air(Vector2(aim.x + 14000.0, lava - 14000.0))
	pl.global_position = at + Vector2(0.0, -5000.0)
	hull.global_position = pl.global_position
	hull.linear_velocity = Vector2.ZERO
	for i in 120:     # terrain streams, the hull finds its hover
		await world.get_tree().physics_frame
		_hold_hull()
	hull = world.get("local_ship")
	if hull == null or not is_instance_valid(hull):
		print("!! the hull did not survive being parked over the core")
		return
	print("\n  parked at (%.0f, %.0f): hull vy %.0f, %.0f px above the core"
		% [hull.global_position.x, hull.global_position.y, hull.linear_velocity.y,
			lava - (hull.global_position.y + hull.solid_bounds.end.y)])
	var beast = world.call("_dive_spawn_picket", "kraken", at)
	if beast == null or not is_instance_valid(beast):
		print("!! could not spawn a hunter at the floor")
		return
	for i in 120:
		await world.get_tree().physics_frame
		_hold_hull()
		if not is_instance_valid(beast):
			break
	if not is_instance_valid(beast):
		print("!! the hunter did not survive the wait")
		return
	beast.linear_velocity = Vector2.ZERO
	var bh: float = beast.solid_bounds.size.y
	print("\n  the hunter: %d blocks, %.0f x %.0f px, origin %.0f px under its own back,"
		% [beast.blocks.size(), beast.solid_bounds.size.x, bh,
			-beast.solid_bounds.position.y])
	print("    %.0f px of air above the core, drifting %.0f px/s in the ring's own weather"
		% [lava - (beast.global_position.y + beast.solid_bounds.end.y),
			beast.linear_velocity.y])

	# --- THE DUNK, WITH THE ANIMAL MERELY HOLDING STATION --------------------
	# The design's claim is a PHYSICS claim — "it is held up by MUSCLE, not lift,
	# and your props push harder than its muscle holds" — so it is measured with
	# the fight taken out of the way: the heave, the align and the wander are
	# turned off by their own F2 levers and the swim bladder that cancels gravity
	# (the thing under test) is left running. Anything else measures a wrestle.
	print("\n  [the ring's draft, the heave, the align and the wander are levered to 0 —")
	print("   this is the physics claim on its own: muscle-vs-jet, not a wrestle]")
	await _run_the_dunk(beast, lava)
	Tunables.reset("whale_push_accel")
	Tunables.reset("whale_align_accel")
	Tunables.reset("kraken_wildness")
	Tunables.reset("dive_zone_wind_mult")
	if is_instance_valid(beast):
		beast.queue_free()
	await _frames(4)


## Commit to the hover and time the sink. The stick stays NEUTRAL — under the
## rate controller that is the props holding station, which is the downwash —
## and the only input is DOWN, pressed when the prey has fallen out of the jet
## and released when it is back in it. That is the "committed hovering" the
## design asks for, driven through the real input map.
func _run_the_dunk(beast, lava: float) -> void:
	var hull = world.get("local_ship")
	_park(hull, beast, 900.0)
	await _frames(4)
	var mult := Tunables.get_num("wash_push_mult")
	## Never chase closer than this much clear air: a starter that rams a hunter
	## at the rate stick's 1,920 px/s is not hovering over it, it is crashing
	## into it, and the crush walk then measures the crash instead of the jet.
	var keep_off := 350.0
	var t := 0.0
	var chasing := false
	var jet_frames := 0
	var accel_sum := 0.0
	var accel_n := 0
	var v_prev: float = beast.linear_velocity.y
	var fastest := 0.0
	var y0: float = beast.global_position.y
	var eaten := false
	var lost := ""
	var guard := int(DUNK_CAP_SECONDS * 60.0)
	while guard > 0:
		guard -= 1
		await world.get_tree().physics_frame
		t += STEP
		if not is_instance_valid(beast):
			eaten = true
			break
		var hull2 = world.get("local_ship")
		if hull2 == null or not is_instance_valid(hull2):
			lost = "the hull was destroyed at t=%.2f s — you cannot ride it down and live" % t
			break
		_hold_hull()
		var wash: Vector2 = hull2.wash_accel_at(beast.global_position) * mult
		if wash != Vector2.ZERO:
			jet_frames += 1
			# The NET acceleration the prey actually gets while the jet is on it:
			# the jet, minus the muscle that cancels gravity, minus drag. Measured
			# off the body, not computed from constants.
			accel_sum += (beast.linear_velocity.y - v_prev) / STEP
			accel_n += 1
		v_prev = beast.linear_velocity.y
		fastest = maxf(fastest, beast.linear_velocity.y)
		# THE CHASE — the "committed hovering". Neutral stick means the props are
		# holding station and blowing down; the only input is DOWN, pressed when
		# the prey has fallen out of the jet and released when it is back in it.
		var air: float = (beast.global_position.y + beast.solid_bounds.position.y) \
			- (hull2.global_position.y + hull2.solid_bounds.end.y)
		var want: bool = air > keep_off \
			and beast.global_position.y > hull2.global_position.y
		if want != chasing:
			chasing = want
			if chasing:
				Input.action_press("ship_down")
			else:
				Input.action_release("ship_down")
		if guard % 60 == 0:
			print("    t=%5.2f  beast y %8.0f vy %8.0f | hull y %8.0f vy %8.0f | air %7.0f | jet %6.0f%s"
				% [t, beast.global_position.y, beast.linear_velocity.y,
					hull2.global_position.y, hull2.linear_velocity.y, air, wash.y,
					"  DIVING" if chasing else ""])
		if bool(LavaCore.is_in_core(world.get("_world_rect") as Rect2,
				float((world.get("_lava_core") as Node).get("top_frac")),
				beast.global_position.y + beast.solid_bounds.end.y)):
			eaten = true
			break
	Input.action_release("ship_down")
	var fell: float = (beast.global_position.y - y0) if is_instance_valid(beast) else (lava - y0)
	print("\n  wash_push_mult %.2f   (the lever the design says to turn if this is too fast)" % mult)
	print("  net downward acceleration on the hunter WHILE THE JET IS ON IT: %.0f px/s^2 (%.2f g at 8x)"
		% [accel_sum / maxf(float(accel_n), 1.0),
			(accel_sum / maxf(float(accel_n), 1.0)) / (980.0 * 8.0)])
	print("  fastest sink %.0f px/s | %d of %d frames inside the jet"
		% [fastest, jet_frames, int(t * 60.0)])
	print("  SECONDS TO THE CORE: %s   (fell %.0f px of the %.0f it had)"
		% [("%.2f s" % t) if eaten else "NEVER, in %.0f s" % DUNK_CAP_SECONDS,
			fell, lava - y0])
	if eaten:
		var rate := fell / maxf(t, 0.001)
		print("  = %.0f px/s of dunking, so the Leviathan's own 23,593 px of air is %.0f s"
			% [rate, 23593.0 / maxf(rate, 1.0)])
	if lost != "":
		print("  !! %s" % lost)
	print("  the design wants 3-6 s of committed hovering, never instant.")


## Park the hull with a LIFT PROP directly over the prey's origin, `along` px up
## the jet. Both details are load-bearing and cost this probe two rewrites:
##
##   * `Ship.wash_accel_at` samples ONE point (the world's per-frame sweep asks
##     for `body.global_position`) and rejects it unless it is inside a prop's
##     own width band (`half_width × 1.5`, ~192 px at 8×). "Directly above it"
##     therefore means above a PROP, not above the hull — park by hull origin and
##     whether the jet bites at all is an accident of where starter.ship happens
##     to draw its lift columns.
##   * The jet is `WASH_RANGE_CELLS` 8 cells long — 1,024 px at 8× — measured
##     from the PROP's centre, and the prey's origin sits half a body below its
##     back. So the useful axis is distance-along-the-jet, not clear air.
##
## Velocity is zeroed on both: this measures the jet, not whatever the two were
## doing beforehand.
func _park(hull, beast, along: float) -> void:
	var prop := _lift_prop(hull)
	hull.global_position = Vector2(
		beast.global_position.x - prop.x,
		beast.global_position.y - along - prop.y)
	hull.linear_velocity = Vector2.ZERO
	beast.linear_velocity = Vector2.ZERO
	if pl != null and is_instance_valid(pl):
		pl.global_position = hull.global_position


## A point near `want` with a genuinely EMPTY column around it — the deep still
## has islands in it, and a hull teleported into one is fired out at 14,000 px/s
## (measured; this probe reported that ejection as a dunk for one run). Streams
## the terrain in around each candidate before asking, because an ungenerated
## chunk answers "not solid" to everything.
func _open_air(want: Vector2) -> Vector2:
	var terrain = world.get("terrain")
	if terrain == null:
		return want
	for step in 12:
		var at := want + Vector2(float(step) * 9000.0, 0.0)
		pl.global_position = at
		await _frames(20)
		var clear := true
		for dx in [-3000.0, -1500.0, 0.0, 1500.0, 3000.0]:
			for dy in [-7000.0, -5000.0, -3000.0, -1500.0, 0.0, 1500.0, 3000.0]:
				var p := at + Vector2(dx, dy)
				if bool(terrain.call("is_solid", terrain.call("world_to_cell", p))):
					clear = false
					break
			if not clear:
				break
		if clear:
			return at
	print("  !! no empty column found near the floor — measuring where we asked")
	return want


## The body-local centre of this hull's first LIFT prop (`PV` cluster), or the
## hull's own centre if it has none.
func _lift_prop(hull) -> Vector2:
	for p in (hull.get("_wash_props") as Array):
		if bool((p as Dictionary)["vertical"]):
			return (p as Dictionary)["center"] as Vector2
	return hull.solid_bounds.get_center()


## --- 2. THE ROOF -----------------------------------------------------------

func _measure_the_roof() -> void:
	print("\n--- 2. THE SAME HOVER, OVER THE DEN'S ROOF ---")
	var run = world.get("dive")
	var floor_y: float = world.call("dive_altitude_y",
		DiveRun.depth_altitude(DiveRun.DEPTHS))
	pl.global_position = Vector2(pl.global_position.x, floor_y)
	await _frames(2)
	world.call("_dive_wake_leviathan")
	await _frames(30)
	var boss = null
	for sid in (world.get("_dive_surged") as Array):
		var s = instance_from_id(sid)
		if s != null and is_instance_valid(s) and String(s.get("creature_kind")) == "kraken_leviathan":
			boss = s
	if boss == null:
		print("!! the floor did not wake a Leviathan")
		return
	var roof: Rect2 = world.get("_dive_den_roof") as Rect2
	if roof.size.x <= 0.0:
		print("!! no roof was cut over the den")
		return
	var hull = world.get("local_ship")
	if hull == null or not is_instance_valid(hull):
		print("!! no hull left to hover with")
		return
	# Stand ON the slab, over the middle of it, props running.
	hull.global_position = Vector2(roof.get_center().x,
		roof.position.y - hull.solid_bounds.end.y - 100.0)
	hull.linear_velocity = Vector2.ZERO
	pl.global_position = hull.global_position
	boss.linear_velocity = Vector2.ZERO
	await _frames(10)
	var y0: float = boss.global_position.y
	var jet := 0
	for i in int(ROOF_SECONDS * 60.0):
		await world.get_tree().physics_frame
		if not is_instance_valid(boss) or not is_instance_valid(hull):
			break
		if hull.wash_accel_at(boss.global_position) != Vector2.ZERO:
			jet += 1
	var moved: float = (boss.global_position.y - y0) if is_instance_valid(boss) else INF
	print("  slab %.0f x %.0f px; the boss's back sits %.0f px under it"
		% [roof.size.x, roof.size.y,
			(boss.global_position.y + boss.solid_bounds.position.y) - roof.end.y
				if is_instance_valid(boss) else 0.0])
	print("  after %.0f s of hovering on the roof the boss moved %.0f px (%s) and spent"
		% [ROOF_SECONDS, moved, "DOWN" if moved > 0.0 else "UP"])
	print("  %d of %d frames inside the jet" % [jet, int(ROOF_SECONDS * 60.0)])
	print("  THE ROOF %s the dunk." % ("PREVENTS" if jet == 0 and moved < 400.0
		else "DID NOT PREVENT"))


## --- plumbing ---------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await world.get_tree().physics_frame


## PROBE GOD-MODE, stated out loud: the run's integrity pool is refilled every
## frame. A hunter you are lying on top of rams you, and this probe measures the
## JET, not how long a starter survives a wrestle — the fight's own bill is
## `tools/dive_probe.gd`'s job.
func _hold_hull() -> void:
	var hull = world.get("local_ship")
	if hull != null and is_instance_valid(hull) and hull.hull_integrity_max > 0.0:
		hull.hull_integrity = hull.hull_integrity_max


func _gear(hull) -> String:
	if hull == null or not is_instance_valid(hull):
		return "no hull"
	return "thrust v=%.0f | power %.0f vs draw %.0f" % [
		hull.get("_total_vthrust"), hull.power_supply(), hull.active_draw()]


func _nearest_hull():
	var best = null
	var bd := INF
	for s in fleet.ships():
		if not is_instance_valid(s) or s.faction != 0 or s.creature_kind != "":
			continue
		if s.is_carcass() or not s.has_helm() or s.helm_cells.is_empty():
			continue
		var d: float = s.global_position.distance_to(pl.global_position)
		if d < bd:
			bd = d
			best = s
	return best
