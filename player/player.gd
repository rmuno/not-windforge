class_name Player
extends CharacterBody2D

## You are a person, not a ship.
##
## The ship is something you stand on, build, repair and — via a helm block —
## pilot. Piloting is a *state the player enters*, not the default mode. This
## mirrors the original: you walk up to the control panel and use it.
##
## Deliberately snappy. The charter is explicit that a person and a 200-tonne
## airship must not share a control curve — reviews of the original called out
## character inertia separately from ship inertia. Ground acceleration is high
## enough to reach full speed in ~0.1s, so the character never feels like it is
## sliding on ice while the ship it stands on legitimately does.

signal boarded(ship: Ship)
signal disembarked(ship: Ship)
## The player took `amount` of damage — a hook for a hit cue and the
## damage-number feed (world listens if it wants a floating number).
signal hurt(amount: float)
## The GRIT pool reached zero. The world reuses respawn_player to put the body
## back on the deck with a full pool (see world._on_player_died); nothing here
## decides the consequence, so the death path stays the world's to own.
signal died()

## Movement and reach tuning. `var` rather than `const` so the world-scale
## experiment can multiply the whole set uniformly (see apply_scale); the
## defaults below ARE the shipped feel — nothing else may mutate them.
var SIZE := Vector2(10.0, 18.0)
var SPEED := 210.0
var GROUND_ACCEL := 2400.0
var AIR_ACCEL := 900.0     ## less authority mid-air, but not zero
var JUMP_VELOCITY := -380.0
var GRAVITY := 980.0
var MAX_FALL := 900.0

## How close you must be to a helm block to use it.
var HELM_REACH := 46.0

## Auto-step: walking into an obstruction no taller than this steps over it.
## Exists because co-planar floors on *separate bodies* (hull vs platform
## strips) misalign by sub-pixels and corner-catch the walk — and because
## stepping over small ledges is simply good platforming manners.
var STEP_HEIGHT := 6.0
var STEP_PROBE := 4.0

## How long a dropped-through platform row stays excepted. Generous is safe:
## the exception covers only that one row's body — every other platform (the
## storey below included) keeps colliding for the whole window.
const DROP_THROUGH_TIME := 0.35

## --- Grapple (spec from the original, via the owner's playtest notes) -----
## RMB launches the hook. It latches onto whatever it touches, on the way out
## OR on the way back. W/S reel the rope in and out. Jumping while latched
## leaps up + held direction and unlatches (the original's awkwardness,
## preserved on purpose) — deliberately chainable.
var HOOK_SPEED := 900.0
var HOOK_MAX_RANGE := 420.0
var REEL_SPEED := 260.0
var ROPE_MIN := 12.0

## The rope is a real rope: it bends around corners (pivot points), pulling
## reels you to the bend and then past it, and the pull is applied as
## velocity — never as teleportation — so it can drag you along a surface but
## not through one.
const ROPE_STIFFNESS := 14.0   ## inward px/s per px of stretch (scale-free ratio)
var ROPE_MAX_PULL := 700.0     ## cap on correction speed
## Proportional drag while hanging from the rope (fraction of velocity per
## second). Proportional, never constant-rate: a constant brake kills slow
## motion dead and stalls the swing off vertical (the previous bug); a
## fraction decays it exponentially — swings through vertical every time,
## amplitude shrinking. Note the physics: velocity drag halves pendulum
## AMPLITUDE at gamma/2, so 0.7 ≈ 2s amplitude half-life — settled in a few
## swings. Deliberate swinging survives: held A/D steers at AIR_ACCEL (900),
## which overpowers this easily.
const ROPE_ATTRITION := 0.7
var PIVOT_EPS := 2.5           ## pivots sit this far off the surface
const MAX_PIVOTS := 16

enum HookState { IDLE, FLYING, RETRACTING, LATCHED }

## The peer who owns this body. 1 (the server id) doubles as the
## single-player default. Movement authority follows this — the owning
## peer simulates their own character and everyone else follows the
## replicated transform, because walking must answer input instantly.
var peer_id := 1

## Combat allegiance, mirroring Ship.faction. The player is faction 0 — as are
## their ships — so a hostile shell (faction != this) drains the GRIT pool while
## a friendly one is stopped harmlessly like a friendly hull, and the player's
## own sidearm can never hurt them (the faction rule; see combat/shot.gd).
var faction := 0

var piloting: Ship = null

## The tamed creature this person is RIDING (Sprint 5 taming payoff), or null.
## Mounting rides the creature's frame exactly as piloting rides a helm — the
## collider is disabled and the body is glued to a point on the creature's back
## every frame — but the STEERING is not here: the world routes movement input
## to the creature's WhaleAI (a whale has no helm to take). See mount/dismount.
var riding: Ship = null
## Where on the creature (creature-local px) the rider sits — top-centre of its
## solid bounds, recomputed at mount so it fits whatever body plan was tamed.
var _ride_creature_local := Vector2.ZERO

## What this person is carrying. Mining a terrain cell credits one item of the
## dug type here (player/inventory.gd) — the payoff of Sprint 2's terrain. A
## clean type->count map; crafting and the economy build on it later. Each body
## owns its own, so the item always credits the miner (see world._on_terrain_dug).
var inventory := Inventory.new()

## The RPG progression this character has bought (Sprint 5). Four stats, levels
## 1–5, each granting perks that change real behaviour — move speed and the
## double jump here in the body, mining speed/reach in the world's mine path.
## Levels are raised by paying a trainer (rpg/training.gd) with `wallet`. Both are
## per-body and local (never on the wire — no replication-config change); a
## respawn/host resets them, which is fine until save/load of stats lands (the
## next slice — a documented seam).
var stats := Stats.new()

## The character's money — the salvage economy's currency. Salvage sells into it
## (rpg/economy.gd) and trainers spend it (rpg/training.gd).
var wallet := Wallet.new()

## Hit points, driven by GRIT (stats.max_health / stats.regen_rate). A REAL, live
## pool: hostile fire and hazards drain it (take_damage), GRIT regen mends it
## between hits (_physics_process), and at 0 the body dies and respawns whole.
## Higher GRIT = a bigger pool + faster regen, so a tougher character measurably
## survives more (proven by test).
var max_health := StatDB.BASE_HEALTH
var health := StatDB.BASE_HEALTH

## Air jumps spent since last touching the floor. The double-jump perk (GRACE)
## allows exactly one; reset on landing. `can_air_jump()` is the real predicate
## the jump uses — perk unlocked AND a jump still in the budget.
var _air_jumps := 0
const MAX_AIR_JUMPS := 1

## --- Jump FEEL (theme 3: crisp modern-platformer response) ----------------
## Three affordances the fixed-impulse jump lacked, each an F2 lever (group
## "Player") so the owner tunes them live; all three are TIMES/RATIOS, hence
## scale-invariant (scale_body leaves them alone — the feel is identical at 1x
## and 8x). Zeroing coyote+buffer and setting jump_cut=1.0 restores the exact
## old behaviour, which is what their parity comments in tunables.gd promise.
##
## Coyote time: seconds after walking off a ledge during which a GROUND jump is
## still allowed — forgives the frame-perfect edge jump every platformer needs.
var _coyote := 0.0
## Jump buffer: seconds a jump press is remembered, so pressing a hair before
## you land still jumps on the landing frame instead of being eaten.
var _jump_buffer := 0.0
## Variable height: a ground/coyote/air jump that is still RISING when jump is
## released has its upward velocity multiplied by `jump_cut` — tap for a hop,
## hold for the full arc. True only while such a jump is cuttable; the grapple
## sling deliberately never sets it (its awkward full arc is "preserved on
## purpose"), and it clears at the apex so a later fall+release cuts nothing.
var _jumping := false

var _collider: CollisionShape2D
## Platform bodies currently excepted by a drop-through, with time remaining.
var _drop_exceptions: Array[Dictionary] = []

var _scale_mult := 1.0

var _hook_state := HookState.IDLE
var _hook_pos := Vector2.ZERO      ## global, while flying or retracting
var _hook_dir := Vector2.ZERO
var _rope_len := 0.0               ## total rope paid out (wrapped + active)
var _anchor_ship: Ship = null      ## hook end latched to a ship: rides with it
## Rope path from hook to player: [0] is the hook anchor, the last entry is
## the pivot the player currently hangs from. Each is {"ship": Ship|null,
## "point": Vector2} — ship-local when attached to a ship, global otherwise.
var _pivots: Array[Dictionary] = []


## Replication wiring happens in _enter_tree, never _ready — _ready can be
## deferred, and a body whose synchroniser does not exist yet silently
## drops the packets addressed to it (godot-quirks, paid for by Fleet).
func _enter_tree() -> void:
	if NetUtil.is_online(self):
		set_multiplayer_authority(peer_id)
		if not has_node("Sync"):
			_setup_replication()


## --- Remote-body smoothing ------------------------------------------------
## Ship's rule, applied to people (BACKLOG: "remote bodies snap"). The wire
## carries a shadow pose that only the owning peer writes, and every other
## machine eases its replica onto it — so a crewmate walking the deck walks
## instead of stepping through a slideshow. Presentation only: the owner's
## own body never touches this path, and a replica always converges on the
## pose it was sent.
const NET_SMOOTH_RATE := 22.0  ## e-folds per second; a person corrects faster
                               ## than a ship — there is no mass to sell.
## Error that means "teleport, do not glide": respawn, or joining a session.
## `var` because scale_body multiplies every linear quantity.
var NET_SNAP_DISTANCE := 200.0

## This body's pose as its owner published it. Written by the owning peer,
## read by everyone else.
var net_position := Vector2.ZERO


func _setup_replication() -> void:
	var config := SceneReplicationConfig.new()
	config.add_property(^".:net_position")
	config.add_property(^".:velocity")

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"  # deterministic path across peers
	sync.replication_config = config
	add_child(sync)


## True when this machine drives this body: always in single-player, and
## on the owning peer online. Everyone else renders a replica.
func is_locally_controlled() -> bool:
	return not NetUtil.is_online(self) or multiplayer.get_unique_id() == peer_id


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	_collider = CollisionShape2D.new()
	_collider.shape = shape
	add_child(_collider)

	# One-way collision: the player stands on ships (mask sees layer 1), but
	# ships never see the player (nothing masks layer 2). To a rigid body a
	# kinematic character is an immovable obstacle — without this split, a
	# climbing ship is capped by its own crew standing on the deck.
	# Layer 3 is platform strips — masked off briefly to drop through them.
	collision_layer = 2
	collision_mask = 1
	set_collision_mask_value(3, true)

	# Snap to the deck when walking over the seams between a ship's merged
	# collider rectangles, instead of catching on them.
	floor_snap_length = 8.0 * _scale_mult
	floor_max_angle = deg_to_rad(50.0)

	# Seed the shadow pose so a replica never eases in from the origin during
	# the frame or two before its first sync packet lands.
	net_position = global_position


## The world-scale experiment: multiply every linear quantity by m, leaving
## every time and every ratio alone — so distances scale but the *timing* of
## a jump, a reel or a sprint-to-speed is pixel-for-pixel the same feel.
## GRAVITY scales with the rest for exactly that reason: height ∝ v²/g, and
## scaling v by m alone would stretch airtime by √m and read as floaty.
## Call before adding to the tree (the collider is built in _ready).
## (Named scale_body because apply_scale is a native Node2D method — the
## same shadowing trap as class_name Sky; see the godot-quirks skill.)
func scale_body(m: float) -> void:
	_scale_mult = m
	SIZE *= m
	SPEED *= m
	GROUND_ACCEL *= m
	AIR_ACCEL *= m
	JUMP_VELOCITY *= m
	GRAVITY *= m
	MAX_FALL *= m
	HELM_REACH *= m
	STEP_HEIGHT *= m
	STEP_PROBE *= m
	HOOK_SPEED *= m
	HOOK_MAX_RANGE *= m
	REEL_SPEED *= m
	ROPE_MIN *= m
	ROPE_MAX_PULL *= m
	PIVOT_EPS *= m
	NET_SNAP_DISTANCE *= m
	if _collider != null:
		(_collider.shape as RectangleShape2D).size = SIZE
		floor_snap_length = 8.0 * m


## Ease a replica onto the pose its owner published. A teleport — respawning,
## falling out of the world, being placed aboard a ship on join — must never
## be smoothed, or the body visibly slides the length of the map, so anything
## past NET_SNAP_DISTANCE is simply placed.
func _follow_net_pose(delta: float) -> void:
	var drift := net_position - global_position
	if drift.length_squared() > NET_SNAP_DISTANCE * NET_SNAP_DISTANCE:
		global_position = net_position
		return
	# Framerate-independent exponential approach, as on Ship.
	global_position += drift * (1.0 - exp(-NET_SMOOTH_RATE * delta))


func is_piloting() -> bool:
	return piloting != null and is_instance_valid(piloting)


func is_riding() -> bool:
	return riding != null and is_instance_valid(riding)


## The ship the grapple is currently latched onto (its far end), or null when
## the hook is not latched. The taming loop reads this: hold the hook on a
## tameable creature to bond with it (world._handle_taming).
func grapple_target() -> Ship:
	return _anchor_ship if grapple_latched() else null


## Climb onto a tamed creature and ride it. Returns false if already piloting/
## riding or the creature is gone. The rider sits on top of its solid bounds.
## The grapple STAYS latched — it is the LEASH (owner 2026-08-24: riding is "a
## strong suggestion, not a full system replacement"): you keep holding the hook
## while you ride, and releasing it (RMB) is what lets go. So mount does NOT
## release the grapple; the world ends the ride the moment the hook is no longer
## latched onto this creature (world._handle_taming).
func mount(creature: Ship) -> bool:
	if is_piloting() or is_riding() or creature == null or not is_instance_valid(creature):
		return false
	riding = creature
	var b := creature.solid_bounds
	_ride_creature_local = Vector2(b.get_center().x, b.position.y - SIZE.y * 0.5)
	return true


## Step off the creature you are riding (the world returns it to a calm allied
## roam). No-op if you are not riding.
func dismount() -> void:
	if not is_riding():
		return
	riding = null
	# Drop the leash on the way off, so the hook is not still latched onto the
	# (tamed) creature — otherwise the ride loop would re-mount instantly next
	# frame (the grapple is the ride's on/off switch now).
	release_grapple()
	rotation = 0.0
	# At rest relative to the world when you hop off; the fall (if any) takes
	# over next frame with the collider back on.
	velocity = Vector2.ZERO


## Effective walk speed: the base feel times the GRACE move-speed perk (1.0 with
## no perk, so an un-invested character walks exactly as before).
func _move_speed() -> float:
	return SPEED * (stats.move_speed_mult() if stats != null else 1.0)


## Can the player start an AIR jump right now? Only when the double-jump perk
## (GRACE) is unlocked AND an air jump remains in the budget. This is the actual
## gate the jump path uses — so it asserts the PERK'S EFFECT, not merely the flag.
func can_air_jump() -> bool:
	return stats != null and stats.double_jump_enabled() and _air_jumps < MAX_AIR_JUMPS


## Jump-feel levers, read live from the F2 "Player" group each frame so the owner
## tunes them without a reboot. Times (coyote/buffer) and a ratio (cut), so none
## scale with world size — the feel is identical at 1x and 8x. Tunables is a
## static store that works headless (godot-quirks), so these are safe in tests too.
func _coyote_time() -> float:
	return Tunables.get_num("coyote_time")


func _jump_buffer_time() -> float:
	return Tunables.get_num("jump_buffer_time")


func _jump_cut() -> float:
	return Tunables.get_num("jump_cut")


## Take `amount` of damage into the GRIT pool. Drains it, fires `hurt` (a hit cue
## / the damage-number feed can listen), and at 0 HP fires `died` — the world
## respawns the body with a full pool and the pack kept (on-death loot drop is a
## documented seam). No-op for a non-positive amount or an already-dead body, so
## a double-hit in one frame cannot re-fire `died`. Regen (GRIT) mends the pool
## between hits in _physics_process, exactly as before.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	hurt.emit(amount)
	if health <= 0.0:
		died.emit()


## The personal fire-rate multiplier: 1.0 baseline, raised by the GRACE quickness
## perk (quicker hands, a shorter interval between sidearm shots). This is the
## PERSON's weapon speed; the ship's turret cadence is the ship's (turret_interval
## below). Pure, so the upgrade is unit-testable without a scene.
func fire_rate_mult() -> float:
	return stats.fire_rate_mult() if stats != null else 1.0


## Effective seconds between sidearm shots: `base` cadence shortened by the
## fire-rate multiplier (the GRACE perk) times `extra_mult` (the F2 `fire_rate_mult`
## lever). A higher product => a shorter interval => faster fire. The maxf floors
## the divisor so a zeroed lever can never divide by zero.
func sidearm_interval(base: float, extra_mult := 1.0) -> float:
	return base / maxf(fire_rate_mult() * extra_mult, 0.05)


## Turret volley interval: the ship's `base` cadence STRETCHED by brownout (an
## underpowered ship fires proportionally slower — power_ratio < 1, the graceful-
## degradation rule) and SHORTENED by the global fire-rate lever. The turret is the
## SHIP's weapon, so the personal GRACE perk does NOT apply — only the lever. Static
## + pure so the brownout × lever interaction is testable without a live ship.
static func turret_interval(base: float, power_ratio: float, rate_mult := 1.0) -> float:
	return base / maxf(power_ratio, 0.05) / maxf(rate_mult, 0.05)


func _physics_process(delta: float) -> void:
	# Collision state is DERIVED every frame, never toggled and trusted. The
	# stateful version leaked: a ship freed while you piloted it skipped the
	# disembark path and left the collider off forever (owner: "the player's
	# collision sometimes is completely gone"). Riding a creature disables it
	# for the same reason piloting does — a kinematic body glued into the
	# creature's hull every frame would fight the solver.
	_collider.set_deferred("disabled", is_piloting() or is_riding())

	# Replicas do not simulate: no gravity, no input, no move_and_slide —
	# the owning peer's synchroniser drives the pose, and we ease onto it.
	if not is_locally_controlled():
		_follow_net_pose(delta)
		return

	# Publish this body's pose for the synchroniser. Cheap, and it keeps the
	# shadow honest for every path that moves the body — walking, riding a
	# helm, grappling, respawning.
	net_position = global_position

	# GRIT: keep the pool sized to the current stat and mend it toward full at the
	# perk's rate. Runs BEFORE the piloting/riding early-returns below — your body
	# mends wherever you are (on foot, at the helm, riding a whale). It used to sit
	# beneath those returns, so wounds taken while flying — which is most of them,
	# since combat happens at the helm — never healed (owner 2026-08-23: "the hp
	# regen traits aren't working"). Regen still needs the GRIT perk (Second Wind at
	# GRIT 3, Undying at 5); a level-1 body has 0 regen by design.
	max_health = stats.max_health() if stats != null else StatDB.BASE_HEALTH
	health = minf(max_health, health + (stats.regen_rate() if stats != null else 0.0) * delta)

	if is_piloting():
		# Using the console keeps you exactly where you were standing when you
		# pressed F — no snap onto the helm block. You ride the ship's frame
		# from that spot; collision is off so following it frame-by-frame
		# cannot fight the ship's physics.
		global_position = piloting.to_global(_ride_local)
		rotation = piloting.rotation
		velocity = piloting.linear_velocity
		return

	if is_riding():
		# Glued to the creature's back (top-centre of its solid bounds), riding
		# its frame — pose tilt included, so the rider leans as the whale
		# pitches. Steering is the world's job (input → the creature's WhaleAI);
		# here the body just goes where the creature goes.
		global_position = riding.to_global(_ride_creature_local)
		rotation = riding.rotation
		velocity = riding.linear_velocity
		return

	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# Landing refills the air-jump budget (the double-jump perk, GRACE) and the
	# coyote grace; leaving the floor by any means starts the coyote countdown,
	# so a jump pressed within coyote_time of a ledge still leaves the ground.
	if is_on_floor():
		_air_jumps = 0
		_coyote = _coyote_time()
	else:
		_coyote = maxf(0.0, _coyote - delta)

	_tick_drop_exceptions(delta)

	# Platforms exist only for a *falling* (or standing) player. While moving
	# upward they are fully intangible — one-way collision alone lets the
	# solver graze the strip edges on the way up, which reads as jitter
	# (owner report).
	set_collision_mask_value(3, velocity.y >= -1.0)

	_update_hook(delta)

	# Walking is DECK-RELATIVE: move_and_slide glues you to a moving floor
	# positionally, so `velocity` must contain only your own motion. Adding
	# get_platform_velocity() into the target carried you twice — standing on
	# a moving ship slid you deck-forward at ~ship speed, and walking against
	# it could not win (owner: "double the desired velocity").
	var dir := Input.get_axis("move_left", "move_right")
	var walk := _move_speed()  # base feel × the GRACE move-speed perk
	if is_on_floor():
		velocity.x = move_toward(velocity.x, dir * walk, GROUND_ACCEL * delta)
	elif not is_zero_approx(dir):
		velocity.x = move_toward(velocity.x, dir * walk, AIR_ACCEL * delta)
	# Airborne with no input: momentum is preserved. Braking toward zero in
	# mid-air was an invisible 900 px/s² air-brake — it stalled rope pendulums
	# a few degrees off vertical (swing speed near the bottom is almost purely
	# horizontal, so the brake ate exactly what gravity supplied — owner
	# report), and it had been quietly bleeding grapple slings all along.

	# Jump buffer: a press is remembered for jump_buffer_time so pressing a hair
	# before you land still jumps on the landing frame instead of being eaten.
	# The grapple sling (below) is the one jump kept strictly on-the-frame.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = _jump_buffer_time()
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	if Input.is_action_just_pressed("jump") and grapple_latched():
		# The grapple jump, original-style awkwardness preserved (owner's
		# call): jumping while hooked leaps UP plus your held direction —
		# never toward the anchor. Immediate on the press (never buffered),
		# and its full arc is deliberately NOT cuttable (does not arm
		# _jumping). Chains: latch, jump, latch, jump — the original's
		# endless-jump tech, kept.
		velocity = Vector2(velocity.x * 0.5 + dir * SPEED, JUMP_VELOCITY)
		release_grapple()
		_jump_buffer = 0.0
	elif _jump_buffer > 0.0 and not grapple_latched():
		if is_on_floor() or _coyote > 0.0:
			if is_on_floor() and Input.is_action_pressed("move_down"):
				# Drop through the platform underfoot rather than jump (a no-op
				# on solid hull, exactly as before). Not a jump: no cut arms.
				_start_drop_through()
			else:
				# A ground jump, or a coyote jump within the grace of a ledge.
				# No carrier term: leaving the floor makes the engine add the
				# platform's velocity to ours (PLATFORM_ON_LEAVE default).
				velocity.y = JUMP_VELOCITY
				_jumping = true
			_coyote = 0.0
			_jump_buffer = 0.0
		elif can_air_jump():
			# The double-jump perk (GRACE): one more leap in mid-air. Held-direction
			# steering already lives in the walk block above, so this is a clean
			# vertical impulse plus spending the air-jump budget.
			velocity.y = JUMP_VELOCITY
			_air_jumps += 1
			_jumping = true
			_jump_buffer = 0.0

	# Variable jump height: releasing jump while a jump is still RISING multiplies
	# its climb by jump_cut — a tap is a hop, a hold is the full arc. Cleared at
	# the apex so a later fall + release cuts nothing (and jump_cut = 1.0 makes
	# release a no-op, restoring the old fixed-impulse jump).
	if _jumping and velocity.y >= 0.0:
		_jumping = false
	elif _jumping and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= _jump_cut()
		_jumping = false

	if grapple_latched():
		if Input.is_action_pressed("reel_in"):
			_rope_len = maxf(ROPE_MIN, _rope_len - REEL_SPEED * delta)
		elif Input.is_action_pressed("move_down"):
			_rope_len = minf(HOOK_MAX_RANGE, _rope_len + REEL_SPEED * delta)
		_apply_rope_constraint()
		# Rope attrition AFTER the constraint: this is not a spinning simulator
		# (owner). Proportional (see ROPE_ATTRITION note), and ordered after
		# the spring so its per-frame corrections are damped too — damping
		# before it left a sustained ~20px micro-swing limit cycle where the
		# undamped spring input balanced the attrition.
		velocity *= maxf(0.0, 1.0 - ROPE_ATTRITION * delta)

	var stride := velocity.x
	move_and_slide()

	if is_on_wall() and is_on_floor() and not is_zero_approx(dir):
		_try_step_up(dir, stride)


## Drop-through discards collisions with exactly the platform bodies under
## the player's feet — every other platform in the world keeps colliding.
## (Ship platforms are one body per deck row, so "this storey" is a body.)
## The previous layer-wide mask-off assumed the player would behave for the
## masked window; they did not (owner report: fell through storeys below).
func _start_drop_through() -> void:
	var dropped := false
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is AnimatableBody2D and (collider as AnimatableBody2D).get_collision_layer_value(3):
			add_collision_exception_with(collider)
			_drop_exceptions.append({"body": collider, "time": DROP_THROUGH_TIME})
			dropped = true
	if not dropped:
		return  # standing on solid hull or ground: nothing to drop through


func _tick_drop_exceptions(delta: float) -> void:
	for i in range(_drop_exceptions.size() - 1, -1, -1):
		_drop_exceptions[i]["time"] -= delta
		if _drop_exceptions[i]["time"] <= 0.0:
			var body: Object = _drop_exceptions[i]["body"]
			if is_instance_valid(body):
				remove_collision_exception_with(body)
			_drop_exceptions.remove_at(i)


## Walking into something no taller than STEP_HEIGHT lifts you over it and
## restores your stride (the wall hit already zeroed velocity.x). test_move
## first checks headroom, then whether the path clears at the raised height —
## a real wall fails the second probe and stays a wall.
func _try_step_up(dir: float, restore_vx: float) -> void:
	var up := Vector2(0.0, -STEP_HEIGHT)
	if test_move(global_transform, up):
		return  # no headroom
	var raised := global_transform.translated(up)
	var forward := Vector2(signf(dir) * STEP_PROBE, 0.0)
	if test_move(raised, forward):
		return  # still blocked at step height: a genuine wall
	global_position += up + forward
	velocity.x = restore_vx


var _helm_cell := Vector2i.ZERO
var _ride_local := Vector2.ZERO  ## where you stood when you took the helm


## Take the helm of `ship` at `cell`. Returns false if that is not a helm.
##
## The tether: while at the helm the player's collider is disabled entirely.
## A kinematic body teleported to the panel every frame would otherwise sit in
## permanent overlap with the hull, and the solver's attempts to resolve that
## shove the ship around — boarding used to send the physics berserk.
func board(ship: Ship, cell: Vector2i) -> bool:
	if is_piloting() or is_riding() or ship == null or not ship.has_block(cell):
		return false
	if not BlockDB.get_def(ship.blocks[cell]["type"])["is_core"]:
		return false
	release_grapple()
	piloting = ship
	_helm_cell = cell
	_ride_local = ship.to_local(global_position)
	boarded.emit(ship)
	return true


func disembark() -> void:
	if not is_piloting():
		return
	var ship := piloting
	piloting = null
	rotation = 0.0
	# You step off exactly where you were riding, at rest RELATIVE TO THE
	# DECK — own velocity zero; the floor's positional carry does the riding.
	# Carrying ship.linear_velocity here made sense when walking was
	# world-relative; after the deck-relative change it double-counted and
	# launched the player on dismount (owner regression report).
	velocity = Vector2.ZERO
	ship.thrust_input = Vector2.ZERO
	disembarked.emit(ship)


# --- Grapple ---------------------------------------------------------------

func fire_grapple(dir: Vector2) -> void:
	if _hook_state != HookState.IDLE or is_piloting() or is_riding() or dir == Vector2.ZERO:
		return
	_hook_state = HookState.FLYING
	_hook_pos = global_position
	_hook_dir = dir.normalized()


func release_grapple() -> void:
	_hook_state = HookState.IDLE
	_anchor_ship = null
	_pivots.clear()


func grapple_latched() -> bool:
	return _hook_state == HookState.LATCHED


func hook_active() -> bool:
	return _hook_state != HookState.IDLE


func _pivot_pos(p: Dictionary) -> Vector2:
	var ship: Ship = p["ship"]
	if ship != null and is_instance_valid(ship):
		return ship.to_global(p["point"])
	return p["point"]


## The point the player actually hangs from: the last bend, or the hook.
func _anchor_global() -> Vector2:
	return _pivot_pos(_pivots[-1])


func _make_pivot(collider: Object, point: Vector2) -> Dictionary:
	var ship: Ship = null
	if collider is Ship:
		ship = collider
	elif collider is AnimatableBody2D and collider.get_parent() is Ship:
		ship = collider.get_parent()
	if ship != null:
		return {"ship": ship, "point": ship.to_local(point)}
	return {"ship": null, "point": point}


## Rope already spent on wrapped segments between bends.
func _wrapped_len() -> float:
	var total := 0.0
	for i in range(1, _pivots.size()):
		total += _pivot_pos(_pivots[i - 1]).distance_to(_pivot_pos(_pivots[i]))
	return total


func _update_hook(delta: float) -> void:
	match _hook_state:
		HookState.FLYING:
			var next := _hook_pos + _hook_dir * HOOK_SPEED * delta
			if _try_latch(_hook_pos, next):
				return
			_hook_pos = next
			if _hook_pos.distance_to(global_position) >= HOOK_MAX_RANGE:
				_hook_state = HookState.RETRACTING
		HookState.RETRACTING:
			# The hook latches on the way back too — original behaviour, and
			# it makes sloppy shots forgiving.
			var back := global_position - _hook_pos
			if back.length() <= HOOK_SPEED * delta * 1.5:
				_hook_state = HookState.IDLE
				return
			var next := _hook_pos + back.normalized() * HOOK_SPEED * delta
			if _try_latch(_hook_pos, next):
				return
			_hook_pos = next
		HookState.LATCHED:
			for p in _pivots:
				if p["ship"] != null and not is_instance_valid(p["ship"]):
					release_grapple()  # something the rope ran over is gone
					return
			_update_rope_wrap()


func _try_latch(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1 | 4)  # world + platforms
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	_hook_state = HookState.LATCHED
	var collider: Object = hit["collider"]
	var pos: Vector2 = hit["position"]
	# Anchoring to a ship stores the point in ship-local space, so the tether
	# rides along — hooking your drifting ship and reeling in is the point.
	var anchor := _make_pivot(collider, pos)
	_anchor_ship = anchor["ship"]
	_pivots = [anchor]
	_rope_len = global_position.distance_to(pos)
	return true


## Rope wrapping. Each frame: if the line to the current bend is blocked, a
## new bend forms at the obstruction (nudged off the surface); if the line to
## the *previous* bend has come clear, the rope unwraps past the current one.
## Pulling therefore reels you to the bend, and then past it — like a rope.
func _update_rope_wrap() -> void:
	# A fast swing can sweep past several corners in ONE frame; adding a
	# single bend per frame left the rope visibly embedded through blocks
	# until wrapping caught up (owner report). Iterate until stable.
	for _pass in 4:
		if not _update_rope_wrap_step():
			break


## One unwrap+wrap pass. Returns true if it changed the pivot list.
func _update_rope_wrap_step() -> bool:
	# Unwrap FIRST, and by *winding*, not just line-of-sight. Each bend stores
	# which way the rope wraps around it ("side", a cross-product sign). When
	# the player pendulates back and the rope straightens past the corner, the
	# sign flips — that is the physical release condition, and it fires even
	# while the corner still blocks the sightline (the owner's stuck-rope
	# report: LOS alone never releases a bend you have swung around).
	var changed := false
	while _pivots.size() > 1:
		var last := _pivots[-1]
		var prev_pos := _pivot_pos(_pivots[_pivots.size() - 2])
		var last_pos := _pivot_pos(last)
		var incoming := last_pos - prev_pos
		var outgoing := global_position - last_pos
		# Right at the pivot the outgoing direction is all noise — judge the
		# winding only from a readable distance, and lean on the sightline
		# check when hugging the corner.
		if outgoing.length() > 6.0 and incoming.cross(outgoing) * float(last["side"]) < 0.0:
			_pivots.pop_back()  # rope straightened past this corner
			changed = true
			continue
		if _solid_ray(global_position, prev_pos).is_empty():
			_pivots.pop_back()  # clear line straight past the bend
			changed = true
			continue
		break

	# Then wrap: a blocked line to the active pivot means a new bend forms.
	var active := _anchor_global()
	var hit := _solid_ray(global_position, active)
	if not hit.is_empty():
		var point: Vector2 = hit["position"] + hit["normal"] * PIVOT_EPS
		if point.distance_to(active) > 2.5 and _pivots.size() < MAX_PIVOTS:
			var pivot := _make_pivot(hit["collider"], point)
			var incoming := point - active
			var outgoing := global_position - point
			pivot["side"] = signf(incoming.cross(outgoing))
			_pivots.append(pivot)
			changed = true
	return changed


## Bends form on solid geometry AND platform strips (layers 1|4): visually a
## plank is a solid bar, and a rope passing through it read as a glitch
## (owner report). One-way-ness applies to bodies standing on it, not ropes.
func _solid_ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1 | 4)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query)


## Rope constraint against the active bend, applied as velocity only — the
## pull can drag you along surfaces but never teleport you through one,
## because move_and_slide still owns all actual movement.
func _apply_rope_constraint() -> void:
	var anchor := _anchor_global()
	var active_len := maxf(ROPE_MIN * 0.5, _rope_len - _wrapped_len())
	var offset := global_position - anchor
	var dist := offset.length()
	if dist <= active_len or dist == 0.0:
		return
	var n := offset / dist
	var outward := velocity.dot(n)
	if outward > 0.0:
		velocity -= n * outward
	var stretch := dist - active_len
	velocity -= n * minf(stretch * ROPE_STIFFNESS, ROPE_MAX_PULL)


func _process(_delta: float) -> void:
	# Redraw unconditionally. Gating on hook_active() left the rope's final
	# frame painted forever after unlatching — _draw only runs when asked, and
	# a released grapple never asked again. One tiny rect per frame is cheap;
	# a stale tether painted across the screen is not.
	queue_redraw()


## Nearest usable helm across every ship, or null. Returned as
## [ship, cell] so the caller does not have to search twice. The default
## reach matches the unscaled HELM_REACH; scaled callers pass their own
## (a static function cannot read the instance var).
## Nearest door cell (open or closed) within reach — same contract as
## find_helm below. The world's interact key picks whichever interactable
## is nearer, so standing in a doorway near the helm toggles the door
## rather than boarding the panel. Both finders walk the ships' rebuild-
## time hot-lists (helm_cells / door_cells), never the full grid — the
## every-block scan was ~6 ms per frame at 8× (owner: 22 FPS).
static func find_door(ships: Array, from: Vector2, reach := 46.0) -> Array:
	return _find_station(ships, from, reach, "door")


static func find_helm(ships: Array, from: Vector2, reach := 46.0) -> Array:
	return _find_station(ships, from, reach, "helm")


## Nearest repair-station cell within reach — same [ship, cell] contract as the
## helm/door finders, so the world's interact key can pick the nearest of the
## three. Walks each ship's rebuild-time repair_cells hot-list, never the grid.
static func find_mender(ships: Array, from: Vector2, reach := 46.0) -> Array:
	return _find_station(ships, from, reach, "mender")


static func _find_station(ships: Array, from: Vector2, reach: float,
		kind: String) -> Array:
	var best: Array = []
	var best_dist := reach
	for ship in ships:
		if not is_instance_valid(ship):
			continue
		# Coarse cull: a ship whose whole hull is out of reach contributes
		# nothing — the distant hulk costs one distance check, not 300.
		if ship.solid_bounds.size != Vector2.ZERO and from.distance_to(
				ship.to_global(ship.solid_bounds.get_center())) \
				> reach + ship.solid_bounds.size.length() * 0.5:
			continue
		var cells: Array[Vector2i] = ship.helm_cells
		if kind == "door":
			cells = ship.door_cells
		elif kind == "mender":
			cells = ship.repair_cells
		for cell in cells:
			var d := from.distance_to(ship.to_global(ship.local_pos_of(cell)))
			if d < best_dist:
				best_dist = d
				best = [ship, cell]
	return best


func _draw() -> void:
	var rect := Rect2(-SIZE * 0.5, SIZE)
	var color := Color(0.90, 0.83, 0.55) if not is_piloting() else Color(0.55, 0.85, 0.95)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.4), false, 1.0)

	# Rope and hook drawing scale with the body (owner: too thin at 8×).
	var w := 1.5 * _scale_mult
	var hook_half := 2.5 * _scale_mult
	if _hook_state == HookState.LATCHED:
		# Draw the whole rope path, bends included, player back to the hook.
		var rope_color := Color(0.85, 0.75, 0.5)
		var prev := Vector2.ZERO  # local: the player
		for i in range(_pivots.size() - 1, -1, -1):
			var pt := to_local(_pivot_pos(_pivots[i]))
			draw_line(prev, pt, rope_color, w)
			prev = pt
		draw_rect(Rect2(prev - Vector2.ONE * hook_half, Vector2.ONE * hook_half * 2.0), rope_color)
	elif hook_active():
		var local_tip := to_local(_hook_pos)
		var rope_color := Color(0.6, 0.6, 0.6)
		draw_line(Vector2.ZERO, local_tip, rope_color, w)
		draw_rect(Rect2(local_tip - Vector2.ONE * hook_half, Vector2.ONE * hook_half * 2.0), rope_color)
