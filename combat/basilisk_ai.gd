class_name BasiliskAI
extends WhaleAI

## The BASILISK (owner survey 2026-08-18, from the source): "flying
## snake-looking things that spam fireballs — even the small ones. Good damage;
## small ones take much longer to destroy ship parts, but THE FIRE IS THE MAIN
## PROBLEM."
##
## It is a WhaleAI at heart, so it inherits the roam, the buoyancy hold, the
## facing and the pose, and it replaces exactly one thing: how it attacks. A
## whale rams, a kraken grabs, and a basilisk STANDS OFF and spits — which is
## why it is the creature fire was built for (v0.63.0). Its fireballs are the
## same hazard slug meteors and lava use, so they damage through the same path
## and roll to set what they hit alight through the same rule.
##
## THREE THINGS THE SOURCE GOT WRONG, and the choices that answer them:
##
##   1. "Spams fireballs." Ours has a CADENCE and a TELEGRAPH: it rears —
##      holding still, nose to the target — for WINDUP_SECONDS before every
##      spit. Charter §5 ("telegraphed enemy attacks") is the difference
##      between a fight and weather, and a ranged attacker with no wind-up is
##      pure weather.
##   2. "The fire is the main problem." That is a compliment to the idea and a
##      complaint about the tuning. Ours spits ONE slug per cadence, and the
##      fire it starts is the v0.63.0 fire: it spreads at the perimeter, it can
##      be doused with the wand you already carry, and it burns out.
##   3. Nothing to do about it but leave. A basilisk holds a PREFERRED RANGE:
##      close and it backs off, far and it closes. So the counter-play is to
##      get inside its stand-off distance, which is a thing the player can
##      actually do, rather than a stat check.
##
## The world owns spawning, as it does for every projectile: this brain raises
## `spit_request` and `world._creature_swim` takes it. An AI that could add
## nodes to the scene would be a second spawn path, and this project has one.

## How far it likes to sit from its target, in UNSCALED px (× scale_unit), so
## compare it against WhaleAI.ROAM_RADIUS (220), not against a screen distance.
## Inside RANGE_SLACK of this it holds; outside, it closes or backs away.
##
## 250 is ~2,000 px at the shipped 8×, which is inside the camera's view. The
## first draft said 1,500 — 12,000 px — and `tools/threat_probe.gd` showed what
## that means in practice: the beast sat OFF-SCREEN plinking at a ship it could
## barely reach, at exactly the distance where dormancy puts a body to sleep
## (`dormant_range_px` is 12,000 raw px). A ranged attacker you cannot see has
## no telegraph, whatever its wind-up does.
const PREFERRED_RANGE := 250.0
const RANGE_SLACK := 60.0

## How hard it swims to hold that range — gentler than a whale's charge; a
## basilisk repositions, it does not lunge.
const STANDOFF_ACCEL := 220.0

## Seconds between spits, and how long it rears before each one. The rear is
## the tell: it stops moving and holds its nose on you.
const SPIT_INTERVAL := 3.4
const WINDUP_SECONDS := 0.9

## Vertical damping (per second) while it holds station. A basilisk's body is
## BUOYANT — lift/weight ~1.5 — so without this it rises out of its own fight:
## `tools/threat_probe.gd` watched one drift from 12,800 px to 22,200 px away
## while its slugs fell short behind it, and every unit test missed it because
## a unit test holds the world still. A whale is authored near-neutral and a
## kraken cancels its own weight by muscle; this is the same idea for a body
## that floats.
const HOVER_DAMP := 2.2

## Beyond this it does not bother — it goes back to roaming rather than
## chasing a ship across the sky. Comfortably inside the dormancy range, so a
## basilisk that gives up is still a body that is being simulated.
const GIVE_UP_RANGE := 900.0

## Raised when a spit is due. The world reads it, spawns the slug, and clears
## it — see world._creature_swim.
var spit_request := Vector2.ZERO
var spitting := false

## Starts part-way through a cadence, not at zero: a cooldown of 0 makes the
## brain rear on its very first tick, before it has manoeuvred at all, and a
## creature that opens with its tell already showing has no tell. (Caught by the
## stand-off test — the beast closed 2 px in 40 ticks because it spent every one
## of them winding up.)
var _cooldown := SPIT_INTERVAL * 0.5
var _windup := 0.0


## Whether the creature is REARING right now — the telegraph. The world's
## drawing does not read this yet (a reared pose belongs with the art pass), but
## the AI has to own the state for the test to pin the tell at all.
func is_rearing() -> bool:
	return _windup > 0.0


func tick(delta: float, target: Node2D) -> void:
	if whale == null or not is_instance_valid(whale):
		return
	var dead: bool = whale.shared_health_max > 0.0 and whale.shared_health <= 0.0
	if dead or tamed or ridden or target == null or not is_instance_valid(target):
		# A corpse, an ally, a mount, or nothing to shoot at: fall through to
		# the inherited brain, which roams (and steers, when ridden).
		_windup = 0.0
		super.tick(delta, target)
		return

	var to: Vector2 = target.global_position - whale.global_position
	var dist := to.length()
	if dist > GIVE_UP_RANGE * whale.scale_unit:
		_windup = 0.0
		super.tick(delta, target)   # out of its business: go back to roaming
		return

	# --- hold the stand-off range ----------------------------------------
	var u := whale.scale_unit
	var want := PREFERRED_RANGE * u
	var slack := RANGE_SLACK * u
	var accel := Vector2.ZERO
	if _windup <= 0.0:
		# It only manoeuvres between spits: the rear is a commitment, and a
		# creature that keeps sliding while it winds up has no tell at all.
		if dist > want + slack:
			accel = to.normalized() * STANDOFF_ACCEL * u
		elif dist < want - slack:
			accel = -to.normalized() * STANDOFF_ACCEL * u
	accel.y += _gravity_cancel_accel()
	# Hold the altitude it is fighting at, buoyant body or not.
	accel.y -= whale.linear_velocity.y * HOVER_DAMP
	if accel != Vector2.ZERO:
		whale.apply_central_force(accel * whale.mass)
	whale.set_pose_tilt(0.0)
	whale.ram_immunity_dir = Vector2.ZERO

	# --- the cadence ------------------------------------------------------
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			spit_request = target.global_position
			spitting = true
			_cooldown = _interval()
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_windup = WINDUP_SECONDS


## The cadence, through the F2 lever so the owner can tune the pressure live.
func _interval() -> float:
	return maxf(0.2, Tunables.get_num("basilisk_spit_seconds"))


## The world takes the pending spit (and clears it). Returns Vector2.INF when
## there is nothing to fire — a plain "no", so the caller needs no second flag.
func take_spit() -> Vector2:
	if not spitting:
		return Vector2.INF
	spitting = false
	var at := spit_request
	spit_request = Vector2.ZERO
	return at
