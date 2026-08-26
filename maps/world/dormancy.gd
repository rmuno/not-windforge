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
