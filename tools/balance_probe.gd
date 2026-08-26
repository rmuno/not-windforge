extends SceneTree

## HOW LONG DOES ANYTHING TAKE? (the numbers behind ROADMAP open question 0d.)
##
## An overnight session added a great deal of threat — spawn sites, nests,
## basilisks, fire, the propeller chop — and every constant in it was chosen by
## reasoning, then checked for CORRECTNESS by the suite. Correct is not the same
## as fair. What a player actually experiences is TIME: how long a whale takes
## to kill, how long a nest takes to break, how long a fire takes to eat a ship
## nobody fights, how long a person survives in the blades.
##
## So this fires the REAL turret path (`world._fire_turrets`, at the real
## cadence, with the real shell damage and the real per-cell hp) at the real
## bodies, and reports seconds. Nothing here is a formula: it is the same code
## the player's LMB drives, run against a stopwatch.
##
##   godot --headless --path . --script tools/balance_probe.gd

## RAW px, not scaled: this is a gunnery distance, and it has to stay INSIDE
## `dormant_range_px` (12,000). The first run of this probe stood the targets
## off at 1800 x world_scale = 14,400 px, where dormancy puts a body to sleep —
## a dormant body has no collision, so every shell flew through it and a
## 400-hp critter "survived" four minutes of continuous fire. The same units
## mistake the basilisk shipped with; it is worth naming twice.
## Far enough that a 1,900-px-wide body does not spawn INSIDE the gunner — the
## first held-still run had a basilisk "killed in 30 s with 0 volleys", which
## was the solver crushing two overlapping hulls, not gunnery.
const RANGE := 4000.0
const LIMIT_SECONDS := 90.0

## The headless main loop PACES physics at the tick rate, so 180 simulated
## seconds at 60 Hz costs 180 real ones and eight targets take half an hour.
## Raising the rate runs the same simulation faster than real time (delta stays
## small, so nothing about the solver changes) — 480 Hz is 8x, and the whole
## sweep lands in a couple of minutes.
const TICK_HZ := 480
const STEP := 1.0 / float(TICK_HZ)


func _initialize() -> void:
	Engine.physics_ticks_per_second = TICK_HZ
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 200:
		await process_frame
	# Nothing else may wander into the measurement.
	Tunables.set_value("spawn_sites_enabled", false)
	Tunables.set_value("meteor_interval", 600.0)
	Tunables.set_value("lava_interval", 600.0)

	var mine = world.get("local_ship")
	print("gunner: the starter, %d cells, turret damage %.0f, cooldown %.2fs\n"
		% [mine.blocks.size(), Tunables.get_num("turret_damage"),
			world.TURRET_COOLDOWN])
	print("%-22s %8s %9s %10s %s" % ["target", "cells", "pool", "seconds", "outcome"])
	print("(a volley that never fires means the guns could not BEAR — the arc)")

	for kind in ["whale", "critter", "kraken", "basilisk"]:
		await _shoot(world, mine, kind, "")
	for kind in [SpawnSites.Kind.BANDIT_ROOST, SpawnSites.Kind.CRITTER_MEADOW,
			SpawnSites.Kind.KRAKEN_DEN, SpawnSites.Kind.BASILISK_EYRIE]:
		await _shoot(world, mine, "", SpawnSites.nest_for(kind), kind)

	await _fire_alone(world, mine)
	quit(0)


## Spawn one target at RANGE and shoot it with the ship's own guns until it is
## dead (a creature) or half gone (a structure — the nest-broken rule), or the
## clock runs out.
func _shoot(world: Node, gunner: Ship, kind: String, nest_path: String,
		nest_kind := SpawnSites.Kind.NONE) -> void:
	var at: Vector2 = gunner.global_position + Vector2(RANGE, 0.0)
	var target: Ship = null
	var label := kind
	if nest_path != "":
		label = nest_path.get_file().get_basename()
		target = world._build_nest({"coord": Vector2i(0, 0), "pos": at,
			"kind": nest_kind}, nest_path)
	else:
		target = world.debug_spawn(kind, at)
	if target == null:
		print("%-22s   (could not spawn)" % label)
		return
	# HELD STILL, on purpose. A roaming whale spent 88% of the first run out of
	# the guns' arc, which measures the ARC, not the target: this probe is
	# asking how long a thing takes to break once you are actually hitting it,
	# and a stationary target is the floor that every real fight is worse than.
	target.freeze = true
	for i in 120:
		await physics_frame

	# WHICH SIDE CAN THE GUNS SEE? Turrets only fire within their 180 degree
	# mounting arc, so a target parked on the wrong beam is measured at zero
	# damage for reasons that have nothing to do with toughness. Try one volley
	# each way and keep the side that answers.
	if not world._fire_turrets(gunner, target.global_position):
		target.global_position = gunner.global_position + Vector2(-RANGE, 0.0)
		for i in 30:
			await physics_frame

	var cells0: int = target.blocks.size()
	var pool0: float = target.shared_health_max
	var half := cells0 / 2
	var t := 0.0
	var cooldown := 0.0
	var volleys := 0
	var outcome := "SURVIVED"
	while t < LIMIT_SECONDS:
		if not is_instance_valid(target):
			outcome = "destroyed outright"
			break
		cooldown -= STEP
		if cooldown <= 0.0:
			if world._fire_turrets(gunner, target.global_position):
				volleys += 1
			cooldown = world.TURRET_COOLDOWN
		await physics_frame
		t += STEP
		if nest_path == "" and target.shared_health_max > 0.0 				and target.shared_health <= 0.0:
			outcome = "killed"
			break
		if nest_path != "" and (target.blocks.size() <= half
				or (target.shared_health_max > 0.0 and target.shared_health <= 0.0)):
			outcome = "BROKEN"
			break
	var pool_left: float = target.shared_health if is_instance_valid(target) else 0.0
	print("%-22s %8d %9.0f %10.1f %-18s %4d volleys, %4d cells off, pool %.0f left" % [
		label, cells0, pool0, t, outcome, volleys,
		cells0 - (target.blocks.size() if is_instance_valid(target) else 0),
		pool_left])
	if is_instance_valid(target):
		target.queue_free()
	await process_frame


## And the threat that needs no shooter: a fire nobody fights.
func _fire_alone(world: Node, _gunner: Ship) -> void:
	print("")
	Tunables.set_value("fire_enabled", true)
	var at: Vector2 = Vector2(0.0, -20000.0 * world.world_scale)
	var hulk = world.debug_spawn("carcass", at)
	if hulk == null:
		return
	for i in 120:
		await physics_frame
	var cells0: int = hulk.blocks.size()
	var lit := 0
	for c in hulk.blocks:
		if Fire.burns(int(hulk.blocks[c]["type"])):
			lit = 1
			world.ignite_cell(hulk, c)
			break
	if lit == 0:
		print("nothing on the test body burns")
		return
	var t := 0.0
	var peak := 0
	while t < LIMIT_SECONDS and not hulk.burning.is_empty():
		await physics_frame
		peak = maxi(peak, hulk.burning.size())
		t += STEP
	print("a fire NOBODY FIGHTS, on a %d-cell carcass: %.0f s, peak %d cells alight, %d cells lost (%.0f%%)"
		% [cells0, t, peak, cells0 - hulk.blocks.size(),
			100.0 * (cells0 - hulk.blocks.size()) / maxf(float(cells0), 1.0)])
	hulk.queue_free()
	await process_frame
