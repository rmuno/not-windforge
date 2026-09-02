class_name ScrapField
extends RefCounted

## SCRAP — the Dive's XP, made physical (owner 2026-09-02).
##
## The owner's rulings, in their own words:
##
##   * XP should be "separate, a la vampire survivors" from coins;
##   * it "should FLOAT midair, no collision with anything other than the
##     player's absorption radius";
##   * "we have to get somewhat close … to all exp drops";
##   * "If a kraken kills an enemy ship, I guess the player can still get that
##     exp".
##
## That last one is the load-bearing half: XP ATTRIBUTION IS SPATIAL NOW. Coins
## still ride `DiveRun.credit_kill` and still ask `world._dive_kill_is_yours`
## (an enemy that flew itself into a cliff pays you nothing), but the XP channel
## left the kill entirely — it hangs in the air where the thing died, for
## whoever flies through it. A kraken-killed gunboat, a picket that crashed, the
## Leviathan: every death in a run leaves scrap, and collecting it is the reward.
##
## THIS CLASS IS PURE. No nodes, no physics, no collision — a mote is a position,
## a value and a bob phase, and the world ticks the whole field once a frame
## against the player foci. That is exactly why it is "no collision with
## anything": there is no body to collide WITH. It also means a whole absorption
## sequence is drivable in a headless test with a for-loop, which is the same
## bargain `PickupFloats` and `DamageNumbers` already make (and, like them, it
## carries `shift_x` so a ring wrap takes the field with it).
##
## The WORLD decides (radius from the F2 lever, when to drop, when to cull) and
## the WorldOverlay paints `world.dive_scrap_marks()`.

## How much XP one shard is worth, roughly — the value is cut into this many
## pieces, capped. VS-style: a kill should scatter a small handful you sweep up
## in one pass, not a single pellet and not confetti. At the shipped coin table
## a critter (8) drops one mote, a gunboat (35) two, a kraken (60) four.
const SHARD_PER_VALUE := 20
const SHARD_MAX := 4

## How far shards scatter from the death point, px at scale 1.
const SPREAD_PX := 26.0
## The idle bob: amplitude in px at scale 1, and its rate. Motion is what makes a
## static mote read as loot rather than as scenery, and it costs one sin() each.
const BOB_PX := 7.0
const BOB_HZ := 0.5

## THE MAGNET. Once a mote is inside the absorption radius it is COMMITTED (it
## does not drop out again if you drift back off), and it closes on an
## exponential ease with a floor under the speed — a pure lerp asymptotes and a
## shard would hang a hand's breadth from you forever.
const MAGNET_EASE := 5.5
## The floor, px/s at scale 1 — brisk enough that the last few hundred px of an
## 8x pull do not read as a stall.
const MAGNET_MIN_PX := 90.0
## How close counts as absorbed: a fraction of the radius, never less than this
## many px at scale 1 (so a tiny radius still terminates).
const GRAB_FRACTION := 0.06
const GRAB_PX := 14.0

## Each mote: {"pos", "home", "value", "phase", "age", "locked"}.
## `home` is the bob ANCHOR — `pos` is where it is drawn, and once locked the
## bob stops and `pos` is driven by the magnet alone.
var _motes: Array[Dictionary] = []
## How many clouds this field has dropped. Only used to rotate the scatter so two
## kills at the same spot do not stamp identical shard rosettes — deterministic
## on purpose (no RNG), which keeps a test's geometry reproducible.
var _clouds := 0


## Cut `value` XP into whole shards that sum to EXACTLY `value` (the remainder is
## spread over the first few, so nothing is lost to integer division — the owner's
## "keep the XP VALUES the same as today's" is an arithmetic promise, not a
## rounding hope). Pure, so the split is pinned without a field.
static func shard_split(value: int) -> Array:
	var out: Array = []
	if value <= 0:
		return out
	var n := clampi(1 + value / SHARD_PER_VALUE, 1, SHARD_MAX)
	var base := value / n
	var rem := value % n
	for i in n:
		out.append(base + (1 if i < rem else 0))
	return out


## Drop a cloud worth `value` XP at `at`. `scale` is the world scale (the spread
## and the bob are authored at 1x). Returns how many motes were made.
func spawn(at: Vector2, value: int, scale := 1.0) -> int:
	var parts := shard_split(value)
	if parts.is_empty():
		return 0
	var n := parts.size()
	var turn := float(_clouds) * 0.7
	_clouds += 1
	for i in n:
		# A rosette, not a random puff: even angles keep the shards visually
		# separated at any count, and a single shard sits exactly on the corpse.
		var ang := TAU * (float(i) + 0.5) / float(n) + turn
		var reach := 0.0 if n <= 1 else SPREAD_PX * scale
		var home := at + Vector2(cos(ang), sin(ang)) * reach
		_motes.append({
			"pos": home,
			"home": home,
			"value": int(parts[i]),
			"phase": ang,
			"age": 0.0,
			"locked": false,
		})
	return n


## One frame. Every mote measures the NEAREST focus (the multiplayer idiom —
## `world.dive_player_foci`, all active bodies, not "the" player); inside
## `radius` it locks on and flies in, and on arrival it pays out. Returns the XP
## absorbed this frame, which the world hands to the run.
##
## Nothing here collides, raycasts or touches the physics server: a mote is a
## point, and "absorption radius" is the only geometry the feature has.
func update(delta: float, foci: Array, radius: float, scale := 1.0) -> int:
	if _motes.is_empty() or foci.is_empty() or delta <= 0.0:
		return 0
	var grab := maxf(radius * GRAB_FRACTION, GRAB_PX * scale)
	var ease := 1.0 - exp(-MAGNET_EASE * delta)
	var floor_step := MAGNET_MIN_PX * scale * delta
	var gained := 0
	var kept: Array[Dictionary] = []
	for m in _motes:
		m["age"] = float(m["age"]) + delta
		var pos := m["pos"] as Vector2
		var target := _nearest_point(pos, foci)
		var d := pos.distance_to(target)
		if not bool(m["locked"]):
			if d > radius:
				# Idle: bob about the anchor. Cosmetic, and the only motion an
				# uncollected mote ever has.
				var t := float(m["age"]) * BOB_HZ * TAU + float(m["phase"])
				m["pos"] = (m["home"] as Vector2) + Vector2(0.0, sin(t) * BOB_PX * scale)
				kept.append(m)
				continue
			m["locked"] = true
		if d <= grab:
			gained += int(m["value"])
			continue   # absorbed: the mote is gone
		# Eased pull with a speed floor, so the last stretch never stalls.
		var step := maxf(d * ease, floor_step)
		m["pos"] = pos.move_toward(target, step)
		kept.append(m)
	_motes = kept
	return gained


## Free every mote further than `far` from the nearest focus — the wake cull's
## idiom (world._dive_cull_the_wake), applied to litter with no body. A mote
## already locked onto somebody is never culled: it is mid-flight to a player, so
## by definition it is not far from one. Returns how many were dropped.
func cull(foci: Array, far: float) -> int:
	if _motes.is_empty() or foci.is_empty() or far <= 0.0:
		return 0
	var kept: Array[Dictionary] = []
	var dropped := 0
	for m in _motes:
		if bool(m["locked"]) \
				or _nearest_point(m["pos"] as Vector2, foci).distance_to(m["pos"] as Vector2) < far:
			kept.append(m)
		else:
			dropped += 1
	_motes = kept
	return dropped


## The live motes, for the world's data-provider to shape. Not a copy —
## read-only by contract, exactly like `PickupFloats.active`.
func active() -> Array[Dictionary]:
	return _motes


func count() -> int:
	return _motes.size()


## The XP still hanging in the air — what a run would gain by sweeping the sky.
func pending_value() -> int:
	var n := 0
	for m in _motes:
		n += int(m["value"])
	return n


## Everything goes with the run (`world.end_dive`).
func clear() -> void:
	_motes.clear()
	_clouds = 0


## Carry the whole field across a ring wrap — see `PickupFloats.shift_x`: a
## world-anchored mark has to move with the world or it is left on the far side
## of the seam.
func shift_x(dx: float) -> void:
	for m in _motes:
		m["pos"] = (m["pos"] as Vector2) + Vector2(dx, 0.0)
		m["home"] = (m["home"] as Vector2) + Vector2(dx, 0.0)


static func _nearest_point(pos: Vector2, foci: Array) -> Vector2:
	var best := pos
	var best_d := INF
	for p in foci:
		var d := pos.distance_squared_to(p as Vector2)
		if d < best_d:
			best_d = d
			best = p as Vector2
	return best
