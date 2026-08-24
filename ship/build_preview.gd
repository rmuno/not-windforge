class_name BuildPreview
extends RefCounted

## What a block WOULD do to a ship, computed before it is placed.
##
## The build ghost is a purely LOCAL visual: nothing here mutates
## `ship.blocks`, sends an RPC, or touches any state — it reads the totals
## `Ship.rebuild()` already cached and does the arithmetic a placement
## would have done. That is the whole trick behind showing the
## consequence of a block for free, every frame.
##
## It lives beside block_db.gd rather than inside world.gd because the
## HUD, the world overlay and the test suite all want the same number,
## and because a number the player makes decisions on deserves coverage.


## Lift-to-weight for a hypothetical (lift units, mass) pair at a given air
## density. Deliberately the same expression as `Ship.lift_ratio()` — fed
## explicit numbers instead of the ship's own totals — because a readout
## that drifts from the real ratio is worse than no readout.
static func ratio_of(lift_units: float, total_mass: float, density: float) -> float:
	var weight := total_mass * 980.0
	if weight <= 0.0:
		return 0.0
	return (lift_units * BlockDB.LIFT_PER_MASS * density) / weight


## What `ship.lift_ratio()` would read with ONE more cell of `type` aboard.
##
## Lift is per-cell (bulk blocks scale with their cell count), mass is a
## component RATING normalised by the true footprint — so the ship's own
## `_fp_norm` is used rather than re-derived: a second copy of that rule
## would silently drift the moment BlockDB.FOOTPRINT_8X changes, and the
## player would be shown a lie about their own ship.
static func ratio_with(ship: Ship, type: int) -> float:
	var def := BlockDB.get_def(type)
	return ratio_of(
		ship._total_lift + float(def["lift"]),
		ship.mass + float(def["mass"]) * ship._fp_norm(type),
		ship.air_density_at(ship.global_position.y))


## "lift 1.29 -> 1.27" — the before/after in one glance, which is the
## entire feature. ASCII arrow on purpose: the readout is drawn with
## ThemeDB's fallback font, and a missing glyph reads as a tofu box.
static func readout(before: float, after: float) -> String:
	return "lift %.2f -> %.2f" % [before, after]
