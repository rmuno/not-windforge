class_name Airspace
extends RefCounted

## The sky's vertical structure — bands, winds, gravity, ceiling.
##
## Spec: docs/WORLD_SPEC.md (owner's survey of the original, 2026-08-18).
## The world is three stacked bands (deep / mid / top) separated by
## in-between gaps, over a lava floor, under a hard ceiling. TWO stacked
## convection cells move the air, and the wind lives ONLY on the frame's spine
## and its horizontal DIVIDING rows — NOT filling any band (owner 2026-08-23):
##   * the CENTRE column blows UP (the whole height);
##   * the two EDGE columns blow DOWN (the whole height);
##   * the four horizontal DIVIDER rows, top to bottom, alternate:
##       - ceiling (very top):            OUTWARD   `v <<< ^ >>> v`
##       - blue/green gap (GAP_HIGH):     INWARD    `v >>> ^ <<< v`
##       - green/red gap (GAP_LOW):       OUTWARD   `v <<< ^ >>> v`  [OURS — see
##         docs/DEVIATIONS.md: the source leaves this gap calm; we mirror the
##         other cell so both convection loops are symmetric]
##       - floor (very bottom):           INWARD    `v >>> ^ <<< v`
##   * EVERYTHING else is CALM.
## The shape is the same regardless of how many cells the world has. Riding the
## loop is free travel; fighting it costs thrust.
##
## Everything here is static and pure — position in, answer out — so the
## same model serves ships, creatures, spawn tables and tests without
## instancing. Geometry is expressed as fractions of `bounds`, so the model
## survives the world-scale decision unchanged.

## World extents the sky maps onto (position.y = ceiling, end.y = floor).
## Empty means "no sky": zero wind, normal gravity, no ceiling — the
## Sprint-1 arena predates the sky and must not inherit weather that its
## closed box could never justify. The real world sets this once at load.
static var bounds := Rect2()

enum Band { NONE, LAVA, DEEP, GAP_LOW, MID, GAP_HIGH, TOP }

## Band tops as fractions of world height (0 = floor, 1 = ceiling).
## Thirds-with-gaps, eyeballed from the original's painted map; the exact
## split is tuning, the ordering is spec.
const LAVA_TOP := 0.05
const DEEP_TOP := 0.34
const GAP_LOW_TOP := 0.40
const MID_TOP := 0.62
const GAP_HIGH_TOP := 0.68

## Circulation-cell geometry, fractions of world extent. The centre column and
## the two edge columns are the VERTICAL limbs (full height); the top and bottom
## rows are the HORIZONTAL connectors (full width). Only these thin edge/spine
## lanes carry wind — the interior between them is calm — so the loop is the same
## shape at any world size (owner 2026-08-23). CENTRE/EDGE are width fractions;
## EDGE_H is the height fraction of the top and bottom connector rows.
const CENTRE_HALF_W := 0.03
const EDGE_W := 0.04
const EDGE_H := 0.06

## Airstream speeds, px/s — the wind's own velocity, which drag pulls a
## hull toward (see Ship._physics_process). Ship top speed is ~340 px/s,
## so the loop matters without ever dominating a powered ship.
const CENTRE_UP_SPEED := 260.0
const EDGE_DOWN_SPEED := 220.0
const TOP_OUT_SPEED := 180.0
const BOTTOM_IN_SPEED := 160.0

## Owner: "gravity is a little different (maybe up to 10%)" in the top band.
const TOP_GRAVITY := 0.9


static func active() -> bool:
	return bounds.size.y > 0.0


## 0 at the floor, 1 at the ceiling.
static func altitude_frac(y: float) -> float:
	return clampf((bounds.end.y - y) / bounds.size.y, 0.0, 1.0)


static func x_frac(x: float) -> float:
	return clampf((x - bounds.position.x) / bounds.size.x, 0.0, 1.0)


## The band at an altitude fraction (0 = floor, 1 = ceiling), independent of
## bounds. This is the pure core; band_at reads a live position through it. The
## map draws bands this way too, since bounds is empty at runtime.
static func band_at_frac(a: float) -> Band:
	if a < LAVA_TOP:
		return Band.LAVA
	if a < DEEP_TOP:
		return Band.DEEP
	if a < GAP_LOW_TOP:
		return Band.GAP_LOW
	if a < MID_TOP:
		return Band.MID
	if a < GAP_HIGH_TOP:
		return Band.GAP_HIGH
	return Band.TOP


static func band_at(pos: Vector2) -> Band:
	if not active():
		return Band.NONE
	return band_at_frac(altitude_frac(pos.y))


## The wind's velocity at a point. Only the frame's spine (centre column, UP) and
## rim (edge columns DOWN, top row OUTWARD, bottom row INWARD) carry wind; the
## interior between is calm. The vertical limbs take precedence at the corners, so
## an edge column blows straight down even where it meets the top/bottom row —
## matching `v <<<< ^ >>>> v`. NOT per band (owner 2026-08-23).
static func wind_at(pos: Vector2) -> Vector2:
	if not active():
		return Vector2.ZERO
	return _wind(x_frac(pos.x), altitude_frac(pos.y),
		CENTRE_UP_SPEED, EDGE_DOWN_SPEED, TOP_OUT_SPEED, BOTTOM_IN_SPEED)


## The wind's DIRECTION at a fractional position — fx across the width
## (0 = left edge, 1 = right edge), a up the height (0 = floor, 1 = ceiling).
## The pure, bounds-free twin of wind_at: same lanes, same fraction constants,
## but a UNIT direction rather than a placed velocity, so the map (which has no
## live bounds) and the sim read one circulation model. Returns axis-aligned
## units — UP centre, DOWN edges, ±x outward along the TOP row, ∓x inward along
## the BOTTOM row — or ZERO in the calm interior.
static func wind_dir_at(fx: float, a: float) -> Vector2:
	return _wind(fx, a, 1.0, 1.0, 1.0, 1.0)


## The shared circulation-lane logic, at unit magnitudes 1 (directions) or real
## speeds (velocities). Precedence: centre spine, then edges, then the horizontal
## divider rows (ceiling / the two band gaps / floor), else calm. up_s is applied
## as −y (up is −y in screen space). The gap rows use band_at_frac so they track
## the band constants exactly — the wind's ONLY dependence on the band model.
static func _wind(fx: float, a: float, up_s: float, down_s: float,
		out_s: float, in_s: float) -> Vector2:
	if absf(fx - 0.5) <= CENTRE_HALF_W:
		return Vector2(0.0, -up_s)
	if fx <= EDGE_W or fx >= 1.0 - EDGE_W:
		return Vector2(0.0, down_s)
	var outward := signf(fx - 0.5)
	# The horizontal divider rows, top to bottom (see the class header):
	if a >= 1.0 - EDGE_H:
		return Vector2(outward * out_s, 0.0)       # ceiling: OUTWARD
	if a <= EDGE_H:
		return Vector2(-outward * in_s, 0.0)       # floor: INWARD
	match band_at_frac(a):
		Band.GAP_HIGH:
			return Vector2(-outward * in_s, 0.0)   # blue/green gap: INWARD
		Band.GAP_LOW:
			return Vector2(outward * out_s, 0.0)   # green/red gap: OUTWARD [OURS]
	return Vector2.ZERO                              # the calm band interiors


static func gravity_scale_at(pos: Vector2) -> float:
	return TOP_GRAVITY if band_at(pos) == Band.TOP else 1.0


## Below the deep band's top the air is UNBREATHABLE (WORLD_SPEC: the deep band's
## unbreathable air — the depth hazard). `a` is an altitude fraction (0 = floor,
## 1 = ceiling), so this is the pure, bounds-free twin the sim and tests share —
## it covers the whole DEEP band and the lava floor beneath it. DEEP_TOP is the
## single depth threshold; the survival gate (player/life_support.gd) reads it.
static func is_unbreathable_frac(a: float) -> bool:
	return a < DEEP_TOP


## Is the air at `pos` unbreathable? Live-position twin of is_unbreathable_frac.
## Inert (breathable) when no sky is mapped, exactly like band_at.
static func is_unbreathable(pos: Vector2) -> bool:
	return active() and is_unbreathable_frac(altitude_frac(pos.y))


## The sky simply ends here. No damage, no bounce — climb stops (owner:
## "cannot go past the topmost layer, just unable to go further up").
static func ceiling_y() -> float:
	return bounds.position.y
