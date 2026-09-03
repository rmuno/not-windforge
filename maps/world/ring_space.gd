class_name RingSpace
extends RefCounted

## THE WORLD THAT LOOPS, as one shared fact (owner 2026-09-01: *"Looping around
## through the world seems to make such a mess - it literally teleports the
## player. could it be a bit more seamless?"*).
##
## The Dive's sky is a RING: fly far enough left or right and you come back to
## where you started. Before this file that was ONE `if` in
## `world._dive_hold_the_ring` which moved the player and their hull by a
## circumference and told everything else nothing — so the terrain changed, the
## backdrop lurched, and anything you were riding stayed behind (the owner's
## bug: *"if you tame a creature and go to the edges, you'll get a spam of
## messages but not actually teleport"* — the rider was snapped back onto the
## creature that had not moved, and the wrap fired again, every frame).
##
## A wrap can only be INVISIBLE if the world is genuinely periodic: the ground
## at x must be the same ground as at x ± period, so translating everything you
## can see by exactly one circumference changes nothing on screen. That is what
## this class exists to state, in ONE place, to everyone who needs it:
##
##   * `IslandGen` — generates the ground from a lattice index; reducing the
##     index modulo the ring makes the terrain repeat exactly.
##   * `world._dive_hold_the_ring` — moves the player AND everything in frame
##     by the same circumference in the same frame.
##   * `world.dive_garrison_pos` / `_dive_cull_the_wake` — a body's distance is its
##     distance THE SHORT WAY ROUND, not across the whole world.
##
## PURE AND STATIC, the way `Airspace` is: no node, no autoload, so the suite
## can set a ring up in two lines and assert on it. `period` 0 means "this world
## does not loop" and every function below is then the identity — an expedition
## is unaffected by every line of this file.

## The circumference in world px. 0 = no ring (the default, and every
## non-dive scene).
static var period := 0.0

## The world x the ring is centred on — the run's centre line. The ring covers
## [centre - period/2, centre + period/2); the seam is at both ends of that.
static var centre := 0.0


static func active() -> bool:
	return period > 1.0


## Clear the ring. Called by any world that is not one, so a leftover from a
## previous scene (or a previous test) can never leak into the next.
static func clear() -> void:
	period = 0.0
	centre = 0.0


static func set_ring(circumference: float, at_x: float) -> void:
	period = maxf(circumference, 0.0)
	centre = at_x


## THE SHORT WAY ROUND, over an EXPLICIT circumference. Pure — and the reason it
## takes the circumference rather than reading the static one is that a ring's
## DISTANCES and a ring's TERRAIN are two different claims: an F2 dive inside an
## expedition loops the run without the expedition's ground being periodic, so
## it folds distances (with its own live ring width) while `period` stays 0.
static func fold(d: float, circumference: float) -> float:
	if circumference <= 1.0:
		return d
	return wrapf(d + circumference * 0.5, 0.0, circumference) - circumference * 0.5


## The short way round over THIS world's ring. The one function everything that
## measures a distance in a looping world should use — two bodies either side of
## the seam are neighbours, not a world apart.
static func dx(d: float) -> float:
	return fold(d, period) if active() else d


## The same, as a vector (y is never wrapped — the sky has a floor and a
## ceiling, only the compass loops).
static func delta(from: Vector2, to: Vector2) -> Vector2:
	return Vector2(dx(to.x - from.x), to.y - from.y)


## Distance the short way round.
static func distance(a: Vector2, b: Vector2) -> float:
	return delta(a, b).length()


## `x` folded into the ring's own span, [centre - period/2, centre + period/2).
static func wrap_x(x: float) -> float:
	if not active():
		return x
	return centre + dx(x - centre)


## The copy of `x` nearest to `near_x` — the same point on the ring, expressed
## in the image that is closest to where the answer is wanted.
static func nearest_x(x: float, near_x: float) -> float:
	if not active():
		return x
	return near_x + dx(x - near_x)


## HOW MANY GENERATOR CELLS THE RING IS ACROSS. The ground is generated from a
## lattice of candidate island sites `lattice_px` apart, so the terrain can only
## repeat exactly if the circumference is a WHOLE NUMBER of them — which is why
## `world.dive_nominal_tile_w` snaps the tile width to make it one. Returns 0
## when there is no ring, or when the numbers do not divide (in which case the
## generator stays aperiodic rather than producing a visible mismatch).
static func lattice_regions(lattice_px: float) -> int:
	if not active() or lattice_px <= 0.0:
		return 0
	var k := roundi(period / lattice_px)
	if k < 2:
		return 0
	if absf(float(k) * lattice_px - period) > 0.5:
		return 0   # not a whole number of regions: not periodic, do not pretend
	return k


## A lattice index folded into ONE lap, centred on 0 — so index i and index
## i ± k are the same candidate site and generate the identical island. Centred
## rather than [0, k) so the canonical position of a reduced index is near the
## middle of the world, where the generator's own x-dependent keep-outs (the
## spawn clearing, the wind columns) mean what they were written to mean.
static func reduce_index(i: int, k: int) -> int:
	if k < 2:
		return i
	var half := k / 2
	return posmod(i + half, k) - half
