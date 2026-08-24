class_name WhaleAI
extends RefCounted

## A sky whale (owner survey + the original): NEUTRAL, physics-heavy,
## and provoked only by damage. Three behaviours, deliberately minimal:
##   * roam — a lazy deterministic figure-eight around home. A WILD lift-less
##     creature (a kraken: shell + meat, NO blubber) also cancels gravity by
##     muscle here — the hover exception (owner 2026-08-23), so a living kraken
##     holds the deep and a carcass falls. A blubber whale floats, so the cancel
##     is 0 for it and its roam is unchanged;
##   * provoked — RAM the attacker's side. There is no attack code: the
##     whale simply throws itself at its target, and the existing collision
##     momentum plow does what forty thousand mass units at speed do
##     ("damage should come from physics" — WORLD_SPEC). It calms down
##     after a quiet stretch.
##   * carcass — below half its blueprint it stops swimming and drifts
##     on whatever buoyancy its remaining blubber provides; mine the
##     blubber and the whale sinks, emergently.
##   * tamed — Wisdom-gated payoff (LORE Beast Whisperer). A tamed whale
##     never rams (provoke is ignored) and roams calmly around home on the
##     player's side; when the player MOUNTS it, `ridden` flips and the
##     roam/ram AI steps aside so `steer` (player input) drives the swim
##     force directly. Dismount returns it to the calm allied roam. See
##     world.gd (the grapple-bond tame loop) and player.gd (mount/ride).
## Whales are Ships (grid, buoyancy, severing, mining all inherited);
## they swim by muscle — central force — since they have no props, no
## helm and no crew.

const ROAM_RADIUS := 220.0    ## unscaled px, ×scale_unit
const ROAM_ACCEL := 8.0       ## px/s² ×scale_unit — a drifting mountain
## Closing on the prey's ALTITUDE. This is positioning, not the attack:
## a leisurely climb/dive, and a crash during it is the whale's own
## clumsiness (no ram immunity — see below).
const ALIGN_ACCEL := 360.0    ## px/s² ×scale_unit
const ANGER_SECONDS := 30.0
const WANDER_FREQ := Vector2(0.13, 0.09)
## Vertical speed (unscaled ×scale_unit) at which the pitch pose reaches
## the full ±POSE_MAX (~30°, the source's observed range).
const TILT_AT_SPEED := 140.0
## The charge is SIDEWAYS (owner, from the original: whales strike
## broadside). Within this vertical band of the target the whale rams
## flat; outside it, it first swims to the target's altitude.
const ALIGN_BAND := 90.0      ## unscaled px, ×scale_unit
## The align must be able to END (owner 2026-08-22: a provoked whale
## "charges toward whatever attacked it but won't stop charging vertically
## — it'll endlessly push one down"). When the prey is the very thing in
## the whale's way — the whale directly above it, driving down to reach its
## altitude — the vertical shove keeps the target below the band forever and
## the align never converts to the broadside PUSH. So the align commits to
## the shove from the whale's CURRENT altitude after this long, turning a
## stuck vertical pin into the sideways ram + glide (which breaks the pin).
const ALIGN_MAX_SECONDS := 2.0

## --- The shove (owner 2026-08-21) ----------------------------------------
## "The whale AI is a bit clunk. It just charges and doesn't stop. The
## idea: apply X heavy force on the whale in a direction, and wait for
## about 1 second. A blunt PUSH, as opposed to a constant locomotive."
##
## So the attack is a two-beat: the whale HEAVES for PUSH_SECONDS, then
## cuts propulsion dead and GLIDES the rest of the way on momentum alone
## (drag is the only thing acting on it). The felt rhythm is
## PUSH … glide … crunch … re-align … PUSH, instead of an engine that
## pins the prey to a wall and keeps pushing.
##
## Tuning: the hull's linear_damp is 0.4, so a force held for t seconds
## from rest reaches (a/0.4)·(1 − e^(−0.4t)). At PUSH_ACCEL and a 1 s
## window that is ~907 unscaled px/s — **~7,250 px/s at the shipped 8×**,
## which is the old locomotive's terminal speed delivered in one second
## instead of a five-second run-up. The ram lands at least as hard as
## before; it just stops being a bulldozer afterwards.
##
## PUSH_ACCEL is THE feel knob: it alone sets how hard the ram hits.
## PUSH_SECONDS/GLIDE_MAX_SECONDS set the rhythm (how long the beats are),
## and GLIDE_END_SPEED decides how soon after a crunch the whale gives up
## on this pass and lines up the next one.
const PUSH_ACCEL := 1100.0      ## px/s² ×scale_unit — the heave itself
const PUSH_SECONDS := 1.0       ## how long the heave lasts
## Ballistic phase caps: the glide ends on impact (speed killed), on the
## whale simply running out of steam, or on this timeout so a miss cannot
## sail off the map still wearing its ram immunity.
const GLIDE_MAX_SECONDS := 3.0
const GLIDE_END_SPEED := 120.0  ## unscaled px/s ×scale_unit — ~13% of peak
## Regression floor, not a knob: the speed the push MUST have bought by
## the end of its window at 1× (tests pin this, so re-tuning PUSH_ACCEL
## downward can never quietly turn the ram back into a nudge).
const PUSH_PEAK_FLOOR := 700.0  ## unscaled px/s

## --- Riding (the tamed-and-mounted payoff) --------------------------------
## A ridden whale swims where the rider points: a steady central force in the
## steer direction (a fraction of the ram's heave, so it cruises rather than
## bulldozes). With the hull's 0.4 linear_damp, RIDE_ACCEL gives a terminal
## cruise of ~RIDE_ACCEL/0.4 unscaled px/s — brisk but controllable.
const RIDE_ACCEL := 620.0       ## px/s² ×scale_unit — the rider's throttle
## A ridden/tamed whale TREADS WATER instead of sinking out of the thin upper air
## (owner 2026-08-23: "I'd tame a whale several layers up only for it to
## immediately start sinking... could their AI keep them level?"). When the rider
## is not actively climbing/diving the whale swims to hold altitude — it counters
## the unsupported weight (buoyancy can't, up high) and damps vertical drift, so a
## tamed whale is a living thing holding its station, not a brick with a saddle.
## `RIDE_HOLD_DAMP` is the drift-damping gain (per second); the dead-zone below is
## how much vertical steer counts as "the rider is driving" and suspends the hold.
const RIDE_HOLD_DAMP := 2.4
const RIDE_STEER_DEADZONE := 0.15

enum Phase {
	NONE,   ## roaming, or provoked-and-aligning: no attack in progress
	PUSH,   ## heaving horizontally; ram immunity on
	GLIDE,  ## no propulsion, coasting into the target; ram immunity still on
}

var whale: Ship
var home := Vector2.ZERO
## Allegiance/tame state (the LORE payoff). `tamed` flips the creature to a
## calm, unprovokable ally; `ridden` hands the swim over to `steer` (the
## rider's input, each axis −1..1). Both default off — a wild whale.
var tamed := false
var ridden := false
var steer := Vector2.ZERO
var _provoked_until := -1.0e12
var _t := 0.0
## Attack state. `_push_dir` is latched when the shove starts: the glide
## keeps riding it, so the immunity covers the whole attack even after the
## target has drifted (and a re-aim only happens on the NEXT shove).
var _phase: Phase = Phase.NONE
var _phase_t := 0.0
var _push_dir := Vector2.ZERO
## Time spent in the current align (Phase.NONE, provoked, off the band).
## Reset whenever alignment is not active so a fresh provoke aligns clean.
var _align_t := 0.0


## Instance id of the thing that last attacked this creature — the RETALIATION
## target (owner 2026-08-24: "they should target whatever tried to attack it";
## before this, a provoked whale always rammed the nearest player-side SHIP, so
## shooting it on foot sent it at your parked ship). An id, not a ref, so a
## freed attacker never dangles; 0 = unknown → tick falls back to the caller's
## nearest-ship target, the old behaviour.
var _attacker_id := 0


func provoke(attacker: Node2D = null) -> void:
	# A tamed whale is an ally: it does not turn on the hand that tamed it,
	# so damage never provokes it into a ram. This is the "won't ram you"
	# half of the taming contract.
	if tamed:
		return
	# Latch WHO to retaliate against. Only overwrite on a real attribution, so
	# an unattributed re-provoke (terrain crush, a hazard) keeps the whale angry
	# at the last known assailant instead of forgetting them.
	if attacker != null and is_instance_valid(attacker):
		_attacker_id = attacker.get_instance_id()
	_provoked_until = Time.get_ticks_msec() \
		+ Tunables.get_num("whale_anger_seconds") * 1000.0


## The live attacker node, or null if none was ever attributed / it is gone
## (freed, despawned). Position-bearing only — the ram doctrine needs nothing
## more, so the target can be a Ship OR the on-foot Player alike.
func _attacker() -> Node2D:
	if _attacker_id == 0:
		return null
	var node := instance_from_id(_attacker_id) as Node2D
	if node == null or not is_instance_valid(node):
		_attacker_id = 0  # gone for good — forget it
		return null
	return node


## Tame the creature (the world calls this once the LORE gate passes and the
## bond completes). Ends any attack in flight and makes it a calm ally.
func tame() -> void:
	tamed = true
	_provoked_until = -1.0e12
	_attacker_id = 0  # all is forgiven
	_end_attack()


## The rider climbs on: player input (`steer`) now drives the swim.
func mount() -> void:
	ridden = true
	_end_attack()


## The rider steps off: back to the calm allied roam (still tamed).
func dismount() -> void:
	ridden = false
	steer = Vector2.ZERO


## The attack in progress, for tests and debug read-out.
func phase() -> Phase:
	return _phase


func _end_attack() -> void:
	_phase = Phase.NONE
	_phase_t = 0.0
	_push_dir = Vector2.ZERO
	_align_t = 0.0


## Upward acceleration (up is −y) that exactly cancels the whale's unsupported
## weight at its current altitude — muscle standing in for the buoyancy the thin
## upper air can't provide, so the creature is neutrally buoyant instead of
## sinking. 0 where buoyancy already floats it (dense air), so this never lifts.
func _gravity_cancel_accel() -> float:
	if whale == null or not is_instance_valid(whale):
		return 0.0
	return -whale.unsupported_weight() / maxf(whale.mass, 0.001)


## Vertical acceleration that HOLDS altitude: cancel the unsupported weight and
## damp residual vertical drift toward zero. The ridden whale uses this on the
## vertical axis whenever the rider is coasting (not actively climbing/diving).
func _altitude_hold_accel() -> float:
	if whale == null or not is_instance_valid(whale):
		return 0.0
	return _gravity_cancel_accel() - whale.linear_velocity.y * RIDE_HOLD_DAMP


## `target` is the caller's FALLBACK prey (the nearest player-side ship) — used
## only when no attacker was ever attributed. Node2D, not Ship: the retaliation
## target can be the on-foot PLAYER (shoot a whale from the ground and it comes
## for YOU, not your parked ship — owner 2026-08-24).
func tick(delta: float, target: Node2D) -> void:
	if whale == null or not is_instance_valid(whale):
		return
	# Carcass check by BLOCK COUNT, not blueprint_completion(): that
	# helper walks the whole blueprint (5,888 entries at 8×) and this
	# runs every physics frame — it alone cost 6.1 ms/frame, the owner's
	# "FPS dropped when the whale appeared". Counting surviving blocks
	# against the (cached) blueprint map is O(1) and answers the only
	# question asked: is more than half the whale still there?
	var dead: bool = (whale.shared_health_max > 0.0 and whale.shared_health <= 0.0) \
		or whale.blocks.size() * 2 < whale.blueprint_map().size()
	if dead:
		whale.set_pose_tilt(0.0)  # a dead whale settles flat
		whale.ram_immunity_dir = Vector2.ZERO
		_end_attack()  # a carcass is not mid-attack
		return  # and swims nowhere
	_t += delta
	var u := whale.scale_unit
	var accel := Vector2.ZERO
	whale.ram_immunity_dir = Vector2.ZERO
	if ridden:
		# THE RIDE: the roam/ram AI steps aside — the rider's input is the
		# whole of the whale's will. A steady central force in the steer
		# direction (capped to unit so a diagonal is not √2 faster). A small
		# critter rides NIMBLER via its ride_speed_mult (1.0 for a whale, so a
		# whale is unchanged). Terrain ram-immunity while mining is granted on the
		# Ship (ridden_mining), not here — the swim force itself is the same.
		var throttle := Tunables.get_num("whale_ride_accel") * u * whale.ride_speed_mult
		var s := steer.limit_length(1.0)
		accel = s * throttle
		# Tread water: when the rider is NOT driving vertically, the whale holds
		# altitude by muscle instead of sinking (RIDE_HOLD_DAMP). Horizontal steer
		# is untouched; the hold takes over only the vertical axis.
		if absf(s.y) < RIDE_STEER_DEADZONE:
			accel.y = _altitude_hold_accel()
	elif tamed:
		# A calm ally: never rams, never provoked — just the lazy roam around
		# home, exactly as a peaceful wild whale drifts (below), so a tamed
		# whale you dismount goes back to loitering instead of hunting.
		_end_attack()
		var desired := home + Vector2(sin(_t * WANDER_FREQ.x),
			0.6 * sin(_t * WANDER_FREQ.y)) * ROAM_RADIUS * u
		var to := desired - whale.global_position
		if to.length() > 30.0 * u:
			accel = to.normalized() * ROAM_ACCEL * u
		# A tamed ally holds its band too, so one you dismount high up does not
		# quietly sink out of the thin air while it loiters. Just cancel the
		# unsupported weight — no drift damping, so the lazy roam stays lazy.
		accel.y += _gravity_cancel_accel()
	elif Time.get_ticks_msec() < _provoked_until \
			and (_attacker() != null or (target != null and is_instance_valid(target))):
		# RETALIATION: the prey is the ATTACKER when we know who hit us (a ship
		# or the on-foot player alike); the caller's nearest-ship target is only
		# the fallback for unattributed anger (a terrain crush, a legacy path).
		var prey: Node2D = _attacker()
		if prey == null:
			prey = target
		# Broadside doctrine: get level with the prey, THEN shove flat.
		var to := prey.global_position - whale.global_position
		if _phase == Phase.NONE:
			# Commit to the shove when level with the prey, OR when the align
			# has run too long (a stuck vertical drive — the prey itself is in
			# the way — must convert to the sideways ram instead of pushing
			# down forever), OR when already TOUCHING the prey (close enough to
			# ram from here). The colliding-bodies probe is the last `or`, so
			# it runs at most once per tick and only while genuinely aligning.
			if absf(to.y) <= ALIGN_BAND * u \
					or _align_t >= ALIGN_MAX_SECONDS \
					or whale.get_colliding_bodies().has(prey):
				# Level with its prey (or out of patience, or already on it):
				# wind up and heave from the CURRENT altitude. The direction is
				# latched now and held for the whole attack.
				var sx := signf(to.x)
				_push_dir = Vector2(sx if sx != 0.0 else 1.0, 0.0)
				_phase = Phase.PUSH
				_phase_t = 0.0
				_align_t = 0.0
			else:
				# Aligning: mostly vertical, drifting into position. No
				# immunity here — bumping something while manoeuvring is
				# clumsiness, not an attack, and it hurts. Clock the time so a
				# vertical drive that can never get level times out (above).
				_align_t += delta
				accel = Vector2(signf(to.x) * 0.3, signf(to.y)).normalized() \
					* Tunables.get_num("whale_align_accel") * u
				# Hold station against gravity while manoeuvring (the hover
				# exception): 0 for a buoyant whale, real muscle for a lift-less
				# kraken that would otherwise sink out of the deep as it aligns.
				accel.y += _gravity_cancel_accel()
		if _phase == Phase.PUSH:
			_phase_t += delta
			# One heavy horizontal force, purely sideways — as with the
			# source; drag bleeds off any leftover vertical drift.
			accel = _push_dir * Tunables.get_num("whale_push_accel") * u
			whale.ram_immunity_dir = _push_dir
			if _phase_t >= PUSH_SECONDS:
				_phase = Phase.GLIDE
				_phase_t = 0.0
		elif _phase == Phase.GLIDE:
			_phase_t += delta
			# THE POINT of the redesign: nothing is applied here. The whale
			# is a thrown rock now, coasting on the momentum the shove
			# bought and bleeding it to drag.
			accel = Vector2.ZERO
			# The ram is the attack, and the attack is push AND glide: the
			# crunch usually lands during the coast, so immunity has to
			# span both or the whale would pay full price for its own hit.
			# (Bullets are unaffected — they damage via the shot path, not
			# contacts. Owner spec.)
			whale.ram_immunity_dir = _push_dir
			# Resolve on impact (a crunch kills the speed), on running out
			# of steam, or on the timeout for a clean miss. Then it is free
			# to re-align and shove again while the anger lasts.
			if _phase_t >= GLIDE_MAX_SECONDS \
					or whale.linear_velocity.length() < GLIDE_END_SPEED * u:
				_end_attack()
	else:
		_end_attack()  # calm again: no attack is in flight, no immunity
		var desired := home + Vector2(sin(_t * WANDER_FREQ.x),
			0.6 * sin(_t * WANDER_FREQ.y)) * ROAM_RADIUS * u
		var to := desired - whale.global_position
		if to.length() > 30.0 * u:
			accel = to.normalized() * ROAM_ACCEL * u
		# THE HOVER EXCEPTION (owner 2026-08-23): a WILD lift-less creature holds
		# its band by muscle instead of sinking — a living kraken swims the deep,
		# a carcass (early-out above) falls. `_gravity_cancel_accel` is 0 wherever
		# buoyancy already floats the body, so a blubber whale is UNCHANGED.
		accel.y += _gravity_cancel_accel()
	if accel != Vector2.ZERO:
		whale.apply_central_force(accel * whale.mass)

	# Pitch into the motion (owner-approved; pose, not physics — the
	# solver still cannot spin it). Head is authored +x.
	#
	# The facing MULTIPLY stays after the Q10 reversal (owner 2026-08-21,
	# collider now mirrors with the skin). The pose tilt is a real eased node
	# rotation, and a body REFLECTED about x needs the OPPOSITE rotation sign
	# for its nose to read as pitched into the motion — dive left with the
	# right-facing sign and the whale visibly swims tail-first down the slope.
	# Multiplying by the facing makes a whale diving left tip its nose down
	# exactly as one diving right does. The change from the draw-only days:
	# the collider is reflected the same way now, so it pitches to AGREE with
	# the drawing (nose-into-motion for both) instead of tilting the "wrong"
	# way — the reflection and this sign are two halves of one transform.
	whale.set_pose_tilt(
		clampf(whale.linear_velocity.y / (TILT_AT_SPEED * u), -1.0, 1.0)
		* Ship.POSE_MAX * float(whale.visual_facing))
