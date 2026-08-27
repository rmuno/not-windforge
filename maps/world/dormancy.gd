class_name Dormancy
extends RefCounted

## DISTANCE DORMANCY (owner 2026-08-25): "perhaps already-generated content
## should be hidden/stopped so they don't consume CPU? Maybe they can then use
## CPU every few seconds or ticks, so as to allow for more things to exist,
## persevere, and act while far away."
##
## The measurement redirected the mechanism. The owner's 3-FPS capture had
## `proc` (ALL game script) at ~2 ms and `phys` at 30-87 ms, so ticking less
## often buys almost nothing -- the script was never the cost. What costs is
## being IN THE PHYSICS SIMULATION: every body is broadphased against every
## other whose AABB overlaps it, every step, contact or not, and
## `Ship.can_sleep = false` (the upright rule) means nothing ever drops out on
## its own. So dormancy here means LEAVING THE SIMULATION, and the slow tick
## is what keeps a dormant thing alive while it is out.
##
## The switch is `process_mode = PROCESS_MODE_DISABLED` on the ship. That one
## property does all three jobs at once and does them to the WHOLE subtree --
## the body itself, its Shield child and its one-way platform strips, which
## are separate CollisionObject2Ds that would otherwise stay in the broadphase
## after the hull left it. Measured on the isolation ladder that produced this
## design: freezing the bodies left 16 broadphase pairs, disabling them left
## 1. Nothing else in Godot gives a whole subtree that in one assignment.
##
## What a dormant body still does, because "exist and persevere" is the point:
## it holds its grid, its damage, its loot flags and its allegiance -- it is
## the same node, merely not simulated -- and `tick()` advances it on a slow
## schedule so it drifts and its AI clock keeps running. What it does NOT do
## is collide, fall, or be shot.
##
## Dormancy is DERIVED, never stored: it is a function of distance from the
## foci this frame. A save therefore needs no new field and a loaded world
## sorts itself out on the first pass -- the same reasoning that keeps the
## cavity map out of the save format.

## Never dormant, whatever the distance: something a person is inside or on.
## Checked by identity, not by faction, so a captured hulk or a tamed whale
## the player is riding is as safe as the starter.
static func is_exempt(ship: Ship, world: Node) -> bool:
	if ship == null or not is_instance_valid(ship):
		return true
	if world == null or not is_instance_valid(world):
		return true
	if ship == world.get("local_ship"):
		return true  # your own ship is home; it never blinks out behind you
	var p: Variant = world.get("player")
	if p != null and is_instance_valid(p):
		var pl := p as Node
		if pl.get("piloting") == ship or pl.get("riding") == ship:
			return true
	# In multiplayer every crew member counts, not just the local body.
	var crew: Variant = world.get("crew")
	if crew != null and is_instance_valid(crew):
		for other in (crew.call("players") as Array):
			if other == null or not is_instance_valid(other):
				continue
			if other.get("piloting") == ship or other.get("riding") == ship:
				return true
	return false


## The points the world is "near". Terrain streams off the same idea, but the
## sets differ on purpose: terrain promotes around EVERY ship (a whale needs
## ground under it), while dormancy must not, or a pod of whales would hold
## each other awake forever in an empty corner of the sky.
static func foci(world: Node) -> Array:
	var out: Array = []
	var crew: Variant = world.get("crew")
	if crew != null and is_instance_valid(crew):
		for p in (crew.call("players") as Array):
			if p != null and is_instance_valid(p):
				out.append((p as Node2D).global_position)
	if out.is_empty():
		var p: Variant = world.get("player")
		if p != null and is_instance_valid(p):
			out.append((p as Node2D).global_position)
	var ls: Variant = world.get("local_ship")
	if ls != null and is_instance_valid(ls):
		out.append((ls as Node2D).global_position)
	return out


## Distance from the nearest focus, or INF when there is nobody to be far
## from (in which case nothing sleeps -- a world with no observer is a world
## mid-teardown, and blinking it all out would be a surprise, not a saving).
static func distance_to_nearest(pos: Vector2, points: Array) -> float:
	if points.is_empty():
		return -1.0
	var best := INF
	for p in points:
		best = minf(best, pos.distance_to(p as Vector2))
	return best


# --- Acting while far away (v0.60.0) ----------------------------------------
#
# The owner asked for things that "exist, persevere, and act while far away".
# v0.58.0 delivered exist and persevere: a dormant body keeps its grid, its
# damage and its allegiance, and coasts to a stop on the slow tick. That is
# where "act" was missing — everything you flew away from was holding its
# breath until you came back, which is the same still life the feature was
# meant to end.
#
# So a dormant LIVING creature MIGRATES. Three properties it has to have, and
# each one is why the shape below is what it is:
#
#   * It must not depopulate the sky. A straight heading empties the
#     neighbourhood over a long session and never refills it, so the heading
#     TURNS at a constant rate: the creature walks a slow circuit and stays in
#     its region of the world. Radius is speed x period / TAU -- about 14k px
#     at the shipped 8x, roughly the dormancy range itself.
#   * A POD has to stay a pod. The phase comes from the ANCHOR quantised to a
#     coarse grid, so creatures that went under together share a circuit and
#     are still together when you return. (The anchor is the position at sleep,
#     kept on the Ship, precisely so the circuit does not degrade into a random
#     walk as the body moves.)
#   * It must not migrate somewhere it could never swim. The vertical component
#     is flattened -- whales roam sideways, they do not porpoise across bands --
#     and the altitude is clamped clear of the lava floor and the ceiling.
#
# Deterministic in (anchor, t): no RNG state to save, no divergence between
# peers, and a test can assert the exact position after an hour of absence.

## Cruise speed, unscaled px/s (x scale_unit) -- a drifting mountain.
const MIGRATE_SPEED := 26.0
## Seconds for one full circuit of the heading.
const MIGRATE_PERIOD := 420.0
## Vertical component of the circuit, as a fraction of the horizontal.
const MIGRATE_FLATTEN := 0.25
## Altitude fractions a migration will not carry a creature past (0 = floor).
## Below the first is the lava band; above the second is the hard ceiling.
const MIGRATE_FLOOR_FRAC := 0.10
const MIGRATE_CEIL_FRAC := 0.95
## How coarse "the same pod" is, in px. Anything that went under within one
## cell of this grid shares a circuit.
const POD_GRID := 6000.0


## Does this body migrate while dormant? A LIVING creature does. A carcass, a
## wreck and an abandoned vessel do not -- they are objects, and an object that
## wandered off while you were away is a lost object, not a living world.
static func migrates(ship: Ship) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.is_nest:
		return false  # a NEST is the place itself; a place that wanders is not one
	return ship.shared_health_max > 0.0 and ship.shared_health > 0.0


## The phase of the circuit a body anchored here walks. Quantised so a pod
## shares one.
static func pod_phase(anchor: Vector2) -> float:
	var q := Vector2i(floori(anchor.x / POD_GRID), floori(anchor.y / POD_GRID))
	return float(absi(hash(q)) % 3600) / 3600.0 * TAU


## The velocity of a dormant creature anchored at `anchor`, `t` seconds into
## the world's dormant clock.
static func migrate_velocity(anchor: Vector2, t: float, scale_unit: float) -> Vector2:
	var a := pod_phase(anchor) + TAU * t / MIGRATE_PERIOD
	return Vector2(cos(a), sin(a) * MIGRATE_FLATTEN) * MIGRATE_SPEED * maxf(scale_unit, 1.0)


## Keep a migrating body inside the sky it belongs to. Without a sky (the
## Sprint-1 arena, and every test that does not build one) this is identity.
static func keep_in_world(pos: Vector2) -> Vector2:
	if not Airspace.active():
		return pos
	var b: Rect2 = Airspace.bounds
	var margin: float = minf(b.size.x, b.size.y) * 0.01
	return Vector2(
		clampf(pos.x, b.position.x + margin, b.end.x - margin),
		clampf(pos.y,
			b.end.y - MIGRATE_CEIL_FRAC * b.size.y,
			b.end.y - MIGRATE_FLOOR_FRAC * b.size.y))


## THE AWAKE BUDGET (owner 2026-08-26: prioritise the vicinity — "it might be a
## lot though"). Distance dormancy bounds how FAR a simulated body can be, not
## how MANY: a crowded neighbourhood could still put dozens in the physics space
## at once. Given the awake candidates as [distance, item] pairs and a budget,
## this returns the items to force dormant — everything beyond the NEAREST
## `budget`. A budget <= 0 caps nothing (returns empty). Pure and total, so it
## is unit-tested without a world; world._update_dormancy passes real ships.
static func beyond_budget(awake: Array, budget: int) -> Array:
	if budget <= 0 or awake.size() <= budget:
		return []
	var sorted := awake.duplicate()
	sorted.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in range(budget, sorted.size()):
		out.append(sorted[i][1])
	return out
