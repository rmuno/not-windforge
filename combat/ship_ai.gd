class_name ShipAI
extends RefCounted

## Rudimentary crewed-ship piloting (owner 2026-08-20): a DRIVER at a
## live helm (a) steers clear of obstacles, (b) in combat flies toward a
## spot its guns can fire FROM — re-derived from the live grid every
## time, so losing the gun changes the answer — and (c) otherwise
## potters about a small patch of sky around home. Deliberately dumb;
## Sprint 4's real NPCs replace this.
##
## The caches this leans on (turret arcs in _glyph_clusters, the
## solid-bounds AABB) are rebuilt with the grid exactly once per
## structural change — that is the "cache the computations" the owner
## asked for. They live with the LIVE grid, not the blueprint: the
## blueprint is the intended ship, combat reshapes the real one.

const WANDER_RADIUS := 150.0    ## unscaled px, ×scale_unit
const WANDER_INPUT := 0.08      ## idle throttle fraction — potter, don't cruise
const ARRIVE_RADIUS := 60.0     ## unscaled: close enough — let the hover hold
const SLOW_RADIUS := 300.0      ## unscaled: combat proportional-approach band
const STANDOFF_FRACTION := 0.6  ## of aggro range: firing-position distance
const AVOID_LOOKAHEAD := 1.2    ## seconds of current flight probed ahead
## FLEE (ROADMAP Phase 4: the original's bandits were "comically fearless";
## ours run when losing). A bandit is OUTMATCHED — and disengages, flying
## flat-out AWAY from the threat instead of closing — when it has no gun
## left to answer with, when its hull is chewed below FLEE_HULL_FRACTION of
## its blueprint, or when the caller reports it outnumbered. A healthy,
## armed, un-outnumbered bandit still engages exactly as before.
const FLEE_HULL_FRACTION := 0.45  ## hull cells below this fraction of the blueprint → run
## Wander is a deterministic figure-eight (no RNG — headless tests replay
## it exactly). Ships sharing a phase would dance in sync; fine while
## enemies are rare, revisit with fleets.
const WANDER_FREQ := Vector2(0.31, 0.17)

var ship: Ship
var home := Vector2.ZERO
var _t := 0.0


## One tick of piloting. `target` is null outside combat. `outnumbered` lets
## the caller fold in a headcount it can see and the AI cannot (fleet vs
## fleet) — a reason to flee on top of the hull/gun checks the AI makes for
## itself. All vector math below is in screen coordinates (+y down); only the
## very last line translates to helm controls (+v is up).
func tick(delta: float, target: Ship, aggro_range: float, outnumbered := false) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.has_helm():
		return  # no panel, no piloting — same rule as the player
	_t += delta
	var u := ship.scale_unit

	var desired := Vector2.INF
	var combat := false
	var fleeing := false
	if target != null and is_instance_valid(target):
		if _is_outmatched(outnumbered):
			# LOSING: break off and run. Head directly away from the threat at
			# full throttle — disengaging, not standing to be whittled down.
			var away := ship.global_position - target.global_position
			if away.length() < 1.0:
				away = Vector2.RIGHT
			desired = ship.global_position + away.normalized() * SLOW_RADIUS * u
			fleeing = true
		else:
			var offset := _firing_offset(aggro_range)
			if offset != Vector2.INF:
				desired = target.global_position + offset
				combat = true
	if desired == Vector2.INF:
		# Peacetime — or nothing left to shoot with, which is a reason to
		# stop closing, not to keep charging: drift the little figure-
		# eight around home.
		desired = home + Vector2(sin(_t * WANDER_FREQ.x),
			0.6 * sin(_t * WANDER_FREQ.y)) * WANDER_RADIUS * u

	# THE VERTICAL AXIS IS A RATE COMMAND, NOT A SHOVE (DESIGN_DIVE_REVIEW §2.1).
	# The old code fed a small non-zero `y` on EVERY tick, including while
	# pottering, and `Ship._physics_process` engages the altitude hold only at
	# dead neutral — so an idling picket had the assist switched off every frame
	# and sank out of the sky it was supposed to be guarding. Wander is now
	# horizontal only (`y = 0`, the hold takes the altitude), and in combat or
	# flight the axis asks for a vertical SPEED proportional to how far off the
	# desired altitude it is. Inside the arrive radius it is 0: close enough,
	# let the hold hold.
	var to := desired - ship.global_position
	var input := Vector2.ZERO
	if fleeing:
		# Flat-out retreat: full throttle down the escape vector (bypasses the
		# arrive dead-zone — you never "arrive" while running). Its `y` is
		# already a unit-scaled rate command away from the threat.
		input = to.normalized()
	elif to.length() > ARRIVE_RADIUS * u:
		if combat:
			input = (to / (SLOW_RADIUS * u)).limit_length(1.0)
			# Per-axis for the vertical, so closing horizontally never dilutes
			# the altitude the guns need.
			input.y = clampf(to.y / (SLOW_RADIUS * u), -1.0, 1.0)
		else:
			# Potter HORIZONTALLY. The figure-eight still decides where, and it
			# is still deterministic; the sky is the hold's job.
			input = Vector2(to.normalized().x * WANDER_INPUT, 0.0)
	input = _avoid(input)
	ship.net_set_controls(input.x, -input.y)


## Is the bandit outmatched — a reason to flee rather than fight? True when it
## has no working gun (the caller's `_firing_offset` twin), when its hull is
## chewed below FLEE_HULL_FRACTION of the blueprint, or when the caller says
## it is outnumbered. Any one is enough; a whole, armed, even fight is not
## outmatched and it engages normally.
func _is_outmatched(outnumbered: bool) -> bool:
	if outnumbered:
		return true
	if not _has_gun():
		return true
	var bp := ship.blueprint_map()
	if bp.size() > 0 and float(ship.blocks.size()) \
			< Tunables.get_num("flee_hull_fraction") * bp.size():
		return true
	return false


## Does any turret survive on the live grid? Guns-gone is the clearest
## "stop closing and run" signal — you cannot win a fight you can no longer
## return fire in.
func _has_gun() -> bool:
	for cluster in ship._glyph_clusters:
		if cluster["key"] == "T":
			return true
	return false


## Where to sit relative to the target so a live gun bears: opposite the
## first surviving turret's facing, at standoff — a belly gun wants the
## sky above its prey. INF when no gun remains.
func _firing_offset(aggro_range: float) -> Vector2:
	for cluster in ship._glyph_clusters:
		if cluster["key"] != "T":
			continue
		var facing: Vector2 = ship.transform.basis_xform(cluster["facing"])
		return -facing * aggro_range * STANDOFF_FRACTION
	return Vector2.INF


## One ray ahead of the hull's motion: on a hit, cancel the into-obstacle
## component of the input and push off along the surface normal. Crude,
## and honest about it — it stops rams and wall-grinding, nothing more.
func _avoid(input: Vector2) -> Vector2:
	var probe := ship.linear_velocity * AVOID_LOOKAHEAD
	var dirp := Vector2.ZERO
	if probe.length() > 1.0:
		dirp = probe.normalized()
	elif input.length() > 0.001:
		dirp = input.normalized()
	if dirp == Vector2.ZERO:
		return input
	var reach := maxf(probe.length(), 3.0 * Ship.CELL * ship.scale_unit) \
		+ ship.solid_bounds.size.length() * 0.5
	var space := ship.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(ship.global_position,
		ship.global_position + dirp * reach, 1, [ship.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return input
	var n: Vector2 = hit["normal"]
	var into := maxf(0.0, input.dot(-n))
	return input + n * (into + 0.3)


## Where should a gun at `muzzle` with 180° arc around `facing` aim to
## hit `target`? The old code aimed at the target's ORIGIN and a belly
## gun refused level targets whose lower hull was perfectly reachable
## (owner screenshot). Probe the target's solid AABB — centre, corners,
## edge midpoints — keep the candidates inside the arc, and aim at the
## one nearest the centre (into the meat, not a grazing tip). Null when
## the whole ship is genuinely out of the arc.
static func arc_aim_point(muzzle: Vector2, facing: Vector2, target: Ship) -> Variant:
	if target == null or not is_instance_valid(target):
		return null
	var b := target.solid_bounds
	if b.size == Vector2.ZERO:
		return null
	# Rotation is locked at 0 (the upright rule), so the global box is
	# just the local one carried to the ship's position.
	var rect := Rect2(target.to_global(b.position), b.size)
	var center := rect.get_center()
	var best: Variant = null
	var best_d := INF
	for fx in [0.0, 0.5, 1.0]:
		for fy in [0.0, 0.5, 1.0]:
			var c: Vector2 = rect.position + rect.size * Vector2(fx, fy)
			var dir := c - muzzle
			# Small margin over 0 so shots never graze exactly along the
			# arc's horizon.
			if dir.length() < 1.0 or dir.normalized().dot(facing) <= 0.05:
				continue
			var d := c.distance_squared_to(center)
			if d < best_d:
				best_d = d
				best = c
	return best
