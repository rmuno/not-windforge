class_name HazardFireball
extends Node2D

## A hand-integrated, ray-stepped hazard projectile. The meteor (top band) and
## the lava fireball (floor) are the SAME slug with different launch and gravity,
## so both hazards share one tunnel-proof projectile.
##
## It mirrors combat/shot.gd's integrator on purpose: the flight is stepped by a
## raycast every frame, so it CANNOT tunnel a thin hull the way a RigidBody2D
## would at speed (the owner's projectile rule — the dynamics are real, only the
## integrator is ours). Hazards carry NO faction — they damage whatever they
## strike (any ship via Ship.net_damage_cell, ground via Terrain.net_dig), then
## die. Damage reuses the existing paths; nothing here invents a new model.
##
## Hazards also burn PEOPLE: the ray masks characters (layer 2), and a strike on
## a person drains their GRIT pool (Player.take_damage). Hazards carry no faction,
## so a meteor or lava gout hits whoever it touches — structures and crew alike.

enum Kind { METEOR, LAVA }

var velocity := Vector2.ZERO
## Down is +y. Meteors fall on a shallow arc; lava rises then falls back.
var gravity := 0.0
var damage := 60.0
## Slug mass — the momentum (mass × velocity) it shoves the struck ship with,
## same rule as a shell. Momentum has no allegiance; the nudge is harmless.
var mass := 3.0
## Seconds it stays live before fizzling — the reach limit, like Shot.life.
var life := 20.0
var kind := Kind.METEOR
var visual_scale := 1.0
## Terrain to dig when the slug strikes ground (net_dig — the mining seam). Null
## in unit tests that only fire at a ship, or when there is no resident terrain.
var terrain: Terrain = null

var _travelled := 0.0


## Joined so the hazard system (and tests) can COUNT the live population in O(1).
## Membership clears itself on free.
func _enter_tree() -> void:
	add_to_group("hazard_fireballs")


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta       # the arc is real (lava rises then falls)
	var to := position + velocity * delta
	_travelled += velocity.length() * delta
	var space := get_world_2d().direct_space_state
	# Mask layers 1|2: hulls AND terrain (layer 1), AND characters (layer 2) — a
	# hazard burns crew it strikes. Platform strips (3) are not hazard geometry. A
	# ray that STARTS inside a collider does not hit it (hit_from_inside defaults
	# false), so a lava fireball erupting from inside deep terrain still clears it.
	var query := PhysicsRayQueryParameters2D.create(position, to, 1 | 2)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit)
		return
	position = to
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	queue_redraw()


func _impact(hit: Dictionary) -> void:
	var body: Object = hit["collider"]
	# A person struck by the hazard: burn their GRIT pool, then die. Hazards carry
	# no faction, so there is no friendly case — a meteor or lava gout hits anyone.
	var person := body as Player
	if person != null:
		person.take_damage(damage)
		queue_free()
		return
	var ship := body as Ship
	if ship == null and body is Node:
		# Shield/furniture bodies are children of their ship.
		ship = (body as Node).get_parent() as Ship
	var at := hit["position"] as Vector2
	var into := velocity.normalized()
	if ship != null:
		# Momentum has no allegiance (same rule as a shell): the slug shoves what
		# it hits, then damages the struck cell through the existing damage path.
		ship.apply_central_impulse(velocity * mass)
		# Nudge inward along the flight line so a face/corner contact resolves into
		# the struck cell, not its empty neighbour (Ship contact-rounding lesson).
		var cell := ship.cell_at_global(at + into * Ship.CELL * 0.4)
		ship.net_damage_cell(cell, damage)
		# A burning rock sets things alight (roadmap: fire is the hazard's real
		# threat multiplier). The world owns the roll and the rule — a hull that
		# cannot burn simply declines.
		var w := get_parent()
		while w != null and not w.has_method("hazard_ignite"):
			w = w.get_parent()
		if w != null:
			w.call("hazard_ignite", ship, cell)
	elif terrain != null:
		# Ground: dig the struck COARSE-CELL crater through the mining seam
		# (net_dig — authority owns terrain edits). At terrain subdiv S the
		# struck fine cell is 1/S² of the old crater, so the strike clears the
		# whole coarse footprint containing it — the same pixel crater at any
		# resolution (one fine cell at subdiv 1, the old behaviour). The inward
		# nudge lands the contact in the solid cell.
		var cell := terrain.world_to_cell(at + into * terrain.cell_px() * 0.4)
		var s: int = maxi(terrain.subdiv, 1)
		var o := Vector2i(floori(float(cell.x) / s) * s, floori(float(cell.y) / s) * s)
		for dy in s:
			for dx in s:
				var c := o + Vector2i(dx, dy)
				if terrain.is_solid(c):
					terrain.net_dig(c)
	queue_free()


func _draw() -> void:
	var s := visual_scale
	# The bright streak IS the telegraph (cheap): meteors are slow and spawn a
	# screen or more above you, so the trailing warning line is visible long
	# before impact — the "you can see it coming and plan around it" the hazard
	# rule demands, with no separate warning system to maintain.
	var tail_len := minf((28.0 if kind == Kind.METEOR else 14.0) * s, _travelled)
	if tail_len > 0.5 and velocity.length() > 1.0:
		var tail := -velocity.normalized() * tail_len
		draw_line(tail, Vector2.ZERO, Color(1.0, 0.5, 0.15, 0.85), 2.5 * s)
	draw_circle(Vector2.ZERO, 4.0 * s, Color(1.0, 0.72, 0.28))
	draw_circle(Vector2.ZERO, 2.0 * s, Color(1.0, 0.97, 0.85))
