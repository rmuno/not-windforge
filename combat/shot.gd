class_name Shot
extends Node2D

## A physical projectile (owner 2026-08-20: "all projectiles should be
## driven by physics — mass, force, direction"). A shot is a dense slug:
## its muzzle velocity is impulse / mass, gravity bends its flight into a
## real ballistic arc, and on impact its momentum (mass × velocity) shoves
## the ship it hits. No ammo cost — weapons are damage + cooldown +
## upgrades (DECISIONS 2026-08-18).
##
## Deliberately NOT a RigidBody2D: the flight is integrated by hand and
## the path is ray-stepped every frame, which is tunnel-proof at any
## speed — a physics body needs CCD and still misses thin walls at shell
## velocities. The dynamics are real; only the integrator is ours.
##
## Faction rule (owner): a shot never DAMAGES a ship of its own faction,
## but every hull still STOPS it — you cannot shoot through your own (or
## anyone's) infrastructure, you just cannot hurt your own side with it.
## (It still shoves: momentum has no allegiance, and the nudge from a
## friendly shell is harmless.) Terrain stops everything.
##
## Multiplayer status: shots are local visuals + authority-routed damage
## (net_damage_cell), so remote peers see the damage but not the tracer
## or the shove. Tracer replication is queued in BACKLOG with
## interpolation polish.

## Ballistic density knob: shells are small and dense, so they fall on a
## shallower arc than the hulking ships around them — full arena gravity
## at these muzzle speeds would cap a shell's reach at about one screen
## (range = v²/g) and turn every gun into a mortar. At 0.05 an enemy
## shell lobs visibly (~780 px drop across its old aggro radius at 8×)
## while a gun's hold-over stays shallow enough to clear its own hull.
## The arc is real and the knob is data; tune freely.
const GRAVITY_FACTOR := 0.05

var velocity := Vector2.ZERO
var faction := 0
var damage := 8.0
## Who fired this shell (instance id of the player body or the ship — 0 for an
## unattributed source like a hazard). Stamped onto the struck ship's
## `last_attacker_id` so a creature's retaliation targets the actual shooter.
var shooter_id := 0
## Seconds a shell stays in the air — and therefore THE range limit, for
## every shooter alike (owner 2026-08-21: "bullets should all be able to
## travel about 10x their current distance... perhaps up the time limit
## to 30 or 60 seconds"). Distance is purely time-based here: nothing
## counts metres (`_travelled` only sizes the tracer tail), so lifetime
## IS reach. What actually stops a shot first is geometry — terrain and
## hulls end it on contact — and the arc: at GRAVITY_FACTOR the shell
## keeps falling, so a level shot usually finds the ground long before
## 30 s. This number is the ceiling on a shot fired into open sky, not a
## typical flight time.
var life := 30.0
## Hard ceiling on PATH LENGTH (scaled px), the distance twin of `life`.
## The 30 s lifetime was meant as REACH (owner 2026-08-21: "travel about
## 10x their current distance") — but a shot fired into open sky keeps
## running, and each live shot costs a raycast AND a sweep of every ship's
## prop wash EVERY frame (O(live_shots × ships)). Thirty seconds of missed
## fire piles up hundreds of shots that are long off-screen yet still
## billing that per-frame cost — the engine-wide FPS sag the owner saw
## "at one point" after grapple-and-shooting. So we keep the felt range but
## free a shot once it has flown PAST it: a slug that has already crossed
## many screens can never hit anything you can see, so its remaining flight
## is pure compute. INF by default (a bare Shot is uncapped — the v0.13.0
## range pin fires one in empty sky and expects it to keep going); the
## spawner sets a real value from world scale (world._spawn_shot).
var max_travel := INF
## Slug mass, in the same units as block mass. Sets both the momentum
## delivered on impact and (at the muzzle) the speed a given force buys.
var mass := 1.0
## World vertical acceleration for this shot, set by the spawner as
## 980 × world scale × GRAVITY_FACTOR. Down is +y.
var gravity := 980.0 * GRAVITY_FACTOR
## Draw size multiplier — the world-scale experiment passes its unit so
## tracers stay visible on a big ship.
var visual_scale := 1.0

## The firing ship's own hull is NOT excluded (owner: a turret must never
## shoot through its own ship) — own infrastructure stops the shot
## harmlessly like any friendly hull. Rays that START inside a collider
## don't collide with it (hit_from_inside is false), so a muzzle inside
## the turret slab still clears its own gun.
var _travelled := 0.0


## Joined so anything that needs the live-shot population can COUNT it in O(1)
## — today the whale diagnostic, which logs the swarm size behind an FPS drop
## the old whale-only log could never see. Membership clears itself on free.
func _enter_tree() -> void:
	add_to_group("shots")


## Muzzle velocity from an impulse, like any physical launch: v = J / m,
## PLUS whatever the gun itself was already doing — a shell leaves its
## barrel at muzzle speed *relative to the barrel*, not to the sky.
## (Owner 2026-08-21: "if you're moving in the direction the ship is
## shooting, the projectile collides with the turret immediately" — a ship
## faster than its own world-absolute shells simply overran them.) The
## default keeps every stationary-platform number exactly as it was.
## Callers that think in speeds can keep setting `velocity` directly.
func fire(impulse: Vector2, platform_velocity := Vector2.ZERO) -> void:
	velocity = impulse / maxf(mass, 0.001) + platform_velocity
	# One physics frame of barrel travel on the SPAWN POINT. Enemy fire is
	# spawned from _physics_process (world._enemy_fire), where node poses
	# are one integrate old: by the time this shot's first ray runs, the
	# gun has moved on, and a gun moving WITH the shot has overtaken the
	# stale muzzle point — the first ray then strikes the turret's rear
	# face from OUTSIDE (hit_from_inside only protects a start inside the
	# shape) and the shell dies at its own gun. Riding the spawn forward
	# one step re-aligns the epochs. Player fire comes from _process,
	# where spawn pose and first-ray pose already agree — there this term
	# is a harmless ≤1-frame nudge along the flight line. Callers must set
	# `position` (the muzzle point) BEFORE calling fire().
	position += platform_velocity / float(Engine.physics_ticks_per_second)


## Did this step's flight segment [from, to] strike a tethered balloon? Damages
## the whole placeable if so (Ship.damage_balloon — one pool, pops entirely) and
## returns true, so the shell stops there. Faction rule as for hulls: a friendly
## shell passes harmlessly through its own side's balloons.
func _hit_a_balloon(from: Vector2, to: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("ships"):
		var ship := node as Ship
		if ship == null or ship.balloons.is_empty() or ship.faction == faction:
			continue
		for i in ship.balloons.size():
			var c := ship.balloon_center(i)
			var r: float = Ship.BALLOON_RADIUS_CELLS[int(ship.balloons[i]["size"])] \
				* Ship.CELL * ship.scale_unit
			# Distance from the bulb centre to the segment this step covers.
			var seg := to - from
			var t := 0.0 if seg.length_squared() < 0.0001 \
				else clampf((c - from).dot(seg) / seg.length_squared(), 0.0, 1.0)
			if (from + seg * t).distance_to(c) <= r:
				ship.net_damage_balloon(i, damage)
				return true
	return false


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta  # the arc is real
	# Prop wash bends the flight (owner survey: the original's props
	# visibly deflect slow shells; machine-gun rounds barely notice —
	# emergent here, because deflection is dwell time in the jet).
	for ship in get_tree().get_nodes_in_group("ships"):
		velocity += (ship as Ship).wash_accel_at(position) * delta
	var to := position + velocity * delta
	_travelled += velocity.length() * delta
	# BALLOONS FIRST: a tethered balloon is a rendered placeable with no physics
	# body (its lift is applied at its anchor), so the raycast below cannot see
	# it. Test this step's segment against every balloon bulb — a hit ANYWHERE on
	# one damages the WHOLE placeable (owner's rule), and a burst drops the lift
	# it was providing. Cheap: ships carry no balloons in the common case.
	if _hit_a_balloon(position, to):
		queue_free()
		return
	var space := get_world_2d().direct_space_state
	# Mask layers 1|2|4: hulls, terrain, shield furniture (the control panel and
	# closed doors block bullets), AND characters (layer 2) — so hostile fire can
	# hit a person on foot. Platform strips (3) are not shot geometry.
	var query := PhysicsRayQueryParameters2D.create(position, to, 1 | 2 | 8)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var body: Object = hit["collider"]
		# Characters (layer 2) obey the faction rule: a HOSTILE shell drains the
		# person's GRIT pool, a FRIENDLY one is stopped harmlessly like a friendly
		# hull (a shot never damages its own side — the player's own sidearm can't
		# hurt them). The shooter's own body is never the first hit: the muzzle
		# spawns just outside it, aimed away (world._handle_shooting).
		var person := body as Player
		if person != null:
			if faction != person.faction:
				person.take_damage(damage)
			queue_free()
			return
		var ship := body as Ship
		if ship == null and body is Node:
			# Shield bodies are children of their ship.
			ship = (body as Node).get_parent() as Ship
		if ship != null:
			# Momentum transfer: the slug's mass × velocity shoves whatever
			# stopped it, friend or foe. (Authority-side ships only — a
			# frozen client replica ignores impulses, which matches shots
			# being local visuals in multiplayer.)
			ship.apply_central_impulse(velocity * mass)
			if ship.faction != faction:
				# Attribute the hit before the damage lands: the `damaged`
				# signal fires inside net_damage_cell, and the world's provoke
				# wiring reads last_attacker_id in that handler — stamping
				# after would be one hit late.
				if shooter_id != 0:
					ship.last_attacker_id = shooter_id
				# Nudge inward along the flight line so face/corner contacts
				# resolve into the struck cell, not its empty neighbour, then snap
				# to the nearest real block — a LIVING creature collides as one
				# coarse AABB whose corners are empty cells, and a shot landing
				# there used to hit air and deal nothing (the "immune whale"). A
				# vessel's exact collider already lands on a solid cell, so the
				# snap is a no-op there. See Ship.nearest_solid_cell.
				var cell := ship.nearest_solid_cell(
					(hit["position"] as Vector2) + velocity.normalized() * Ship.CELL * 0.4)
				ship.net_damage_cell(cell, damage)
		queue_free()
		return
	position = to
	life -= delta
	# Two ceilings, whichever comes first: the 30 s clock and the distance it
	# stands for. A shot that has out-flown its felt range is off-screen dead
	# weight — free it now rather than pay its per-frame raycast + prop-wash
	# sweep for the rest of the half-minute (see max_travel).
	if life <= 0.0 or _travelled >= max_travel:
		queue_free()
	queue_redraw()


func _draw() -> void:
	# The tail never reaches back past the muzzle: on the first frames a
	# full-length tail stuck out BEHIND the shooter and read as the shot
	# spawning on the wrong side (owner report). It trails the (curving)
	# velocity, so an arcing shell reads as arcing.
	var tail_len := minf(10.0 * visual_scale, _travelled)
	if tail_len > 0.5:
		var tail := -velocity.normalized() * tail_len
		draw_line(tail, Vector2.ZERO, Color(1.0, 0.9, 0.5), 2.0 * visual_scale)
	draw_circle(Vector2.ZERO, 1.6 * visual_scale, Color(1.0, 0.98, 0.8))
