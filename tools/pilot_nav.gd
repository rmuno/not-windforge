class_name PilotNav
extends RefCounted

## THE PROBE PILOT'S NAVIGATION ARITHMETIC, on its own so it can be TESTED.
##
## `tools/dive_probe.gd` flies the shipped starter down the shipped ladder with
## the shipped controls, and every number the Dive is tuned against past depth 2
## depends on it not flying into rock. Until this file the flying rules were
## inline constants inside a `--script` probe, which nothing in the suite could
## reach: a sign error in a ray fan or a stopping distance that is half what the
## hull needs prints as "the deep is unreachable", and the design conclusion
## drawn from that is about the GAME rather than about the autopilot.
##
## Pure and dependency-free ON PURPOSE, exactly like `tools/combat_score.gd`: no
## autoloads, no other `class_name` as a type, no engine state. That is what lets
## the probe `preload()` it inside a `--script` file without dragging a compile
## of the autoload graph in behind it (CODEMAP §4), and what lets the suite call
## it with plain numbers and plain rectangles.
##
## Nothing here knows about ships, terrain or the Dive. It answers three
## questions:
##
##   1. HOW MUCH ROOM DOES THIS SPEED NEED? (`stopping_distance`)
##   2. HOW FAST MAY I GO WITH THIS MUCH ROOM? (`safe_speed` — its exact inverse)
##   3. WHERE DO I POINT THE RAYS? (`fan_dirs`, `fan_origins`)
##
## ...and one tie-breaker, `heading_score`, which ranks the candidate headings a
## fan measured.


## The braking model is CONSTANT DECELERATION after a REACTION delay. Both halves
## are needed and both are honest about the real controller:
##
##   * the reaction term is not politeness, it is the truth about a bang-bang
##     stick — the pilot decides on one physics frame, the input is read on the
##     next, and the props spend a frame or two overcoming the descent's own
##     momentum before the sign of `vy` even changes;
##   * the constant-decel term is the hull's MEASURED authority (the probe reads
##     the largest deceleration it has actually achieved this run and takes a
##     margin off it), not a constant from a design document — a shot-off prop
##     bank halves it, and thin air halves it again.
##
## Returns 0 for a stationary hull and for a hull with no authority at all (the
## caller must then read "no room is enough" from the clearance test, not from a
## division by zero).
static func stopping_distance(speed: float, decel: float, reaction: float) -> float:
	if speed <= 0.0:
		return 0.0
	if decel <= 0.0:
		return INF
	return speed * maxf(reaction, 0.0) + speed * speed / (2.0 * decel)


## The exact inverse: the fastest this hull may travel with `room` px of air in
## front of it. Solving `v·r + v²/2a = room` for v gives
## `v = a·(√(r² + 2·room/a) − r)`, which is the whole of the pilot's speed rule —
## a clear column asks for full stick and a closing one asks for less,
## continuously, with no thresholds anywhere.
##
## Zero room is zero speed, so a keel already buried in rock (a ray that reports
## zero clearance because `hit_from_inside` is on) commands a full stop rather
## than the smallest of steps onward.
static func safe_speed(room: float, decel: float, reaction: float) -> float:
	if room <= 0.0 or decel <= 0.0:
		return 0.0
	var r := maxf(reaction, 0.0)
	return decel * (sqrt(r * r + 2.0 * room / decel) - r)


## `count` unit headings spread symmetrically about `base`, spanning `spread`
## radians to EITHER side. One ray is `base` itself; an even count straddles it.
##
## This is the fan that replaced the probe's single centre-line ray along the
## velocity. A 1,536 px-wide hull travelling diagonally at 1,400 px/s meets rock
## with its SHOULDER, and a ray down the middle of it passes through the gap the
## shoulder does not fit through — measured as five runs in six ending
## `terrain 100 %`.
##
## A zero-length `base` answers straight down: the pilot's default question is
## always "may I keep descending".
static func fan_dirs(base: Vector2, count: int, spread: float) -> Array:
	var b := base.normalized() if base.length() > 0.0 else Vector2.DOWN
	var n := maxi(count, 1)
	if n == 1:
		return [b]
	var out: Array = []
	for i in n:
		var f := -1.0 + 2.0 * float(i) / float(n - 1)
		out.append(b.rotated(f * spread))
	return out


## `count` ray ORIGINS across the face of `bounds` that points along `dir`,
## spread over that face's full width and pushed out to the box's surface.
##
## Rays are cast from the HULL'S SKIN, not from its centre: a clearance measured
## from the centre of a 1,536 × 1,152 px body is three-quarters of a hull too
## optimistic in every direction at once, and that error is the same size as the
## pad the pilot is trying to keep.
##
## `inset` pulls the outermost origins in from the corners (1.0 = the corners
## themselves). A ray started exactly on a corner of a body resting against rock
## reads the rock it is already touching, so the fan's edges live slightly
## inboard and the pad carries the rest.
static func fan_origins(bounds: Rect2, dir: Vector2, count: int, inset: float) -> Array:
	var d := dir.normalized() if dir.length() > 0.0 else Vector2.DOWN
	var perp := Vector2(-d.y, d.x)
	var size: Vector2 = bounds.size
	# The box's support distance along each axis — half the box as projected on
	# that direction, which is what makes this work for a diagonal `dir` too.
	var face := 0.5 * (absf(d.x) * size.x + absf(d.y) * size.y)
	var half := 0.5 * (absf(perp.x) * size.x + absf(perp.y) * size.y) * clampf(inset, 0.0, 1.0)
	var c: Vector2 = bounds.get_center() + d * face
	var n := maxi(count, 1)
	if n == 1:
		return [c]
	var out: Array = []
	for i in n:
		var f := -1.0 + 2.0 * float(i) / float(n - 1)
		out.append(c + perp * (f * half))
	return out


## How much closer to the lane one `horizon` of travel along `dir_x` would bring
## us, as a fraction in [-1, 1]. Positive is progress; negative is away.
##
## `lane_off` is signed: where the lane is, relative to the hull.
static func lane_gain(lane_off: float, dir_x: float, horizon: float) -> float:
	if horizon <= 0.0:
		return 0.0
	var before := absf(lane_off)
	var after := absf(lane_off - dir_x * horizon)
	return clampf((before - after) / horizon, -1.0, 1.0)


## RANK ONE CANDIDATE HEADING. `clear` is how far the fan saw down it, `horizon`
## is how far it looked, `dir` the unit heading and `gain` the lane term above.
##
## Room MULTIPLIES rather than adds, which is the whole point: a blocked heading
## scores zero however well it is aimed, so the pilot can never talk itself into
## a wall because the wall happens to lie toward the next rung. Among headings
## with room, going DOWN wins (this is a dive), and the lane breaks the tie.
static func heading_score(clear: float, horizon: float, dir: Vector2, gain: float,
		down_weight: float, lane_weight: float) -> float:
	if horizon <= 0.0:
		return 0.0
	var room := clampf(clear / horizon, 0.0, 1.0)
	var d := dir.normalized() if dir.length() > 0.0 else Vector2.DOWN
	return room * maxf(1.0 + down_weight * d.y + lane_weight * clampf(gain, -1.0, 1.0), 0.0)


## Which way to push the stick to close `offset`, with a dead band so a hull
## sitting on its target does not chatter left/right every frame.
static func steer_sign(offset: float, deadband: float) -> int:
	if absf(offset) <= maxf(deadband, 0.0):
		return 0
	return 1 if offset > 0.0 else -1
