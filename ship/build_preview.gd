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


## What `ship.lift_ratio()` would read with `cells` more cells of `type`
## aboard (1 for a primitive block; a bundle passes its stamp size, so the
## readout prices the whole machine, not one sliver of it).
##
## Lift is per-cell (bulk blocks scale with their cell count), mass is a
## component RATING normalised by the true footprint — so the ship's own
## `_fp_norm` is used rather than re-derived: a second copy of that rule
## would silently drift the moment BlockDB.FOOTPRINT_8X changes, and the
## player would be shown a lie about their own ship.
static func ratio_with(ship: Ship, type: int, cells := 1) -> float:
	var def := BlockDB.get_def(type)
	var n := float(maxi(cells, 1))
	return ratio_of(
		ship._total_lift + float(def["lift"]) * n,
		ship.mass + float(def["mass"]) * ship._fp_norm(type) * n,
		ship.air_density_at(ship.global_position.y))


# --- Bundle stamps (owner 2026-08-25: machines place as rectangles) --------

## The cells a stamp of `type` covers with the cursor on `cell`: the
## BlockDB.bundle_dims rectangle centred on the cursor (a primitive is the
## one cursor cell). Pure geometry — validity is stamp_valid's job.
static func stamp_cells(ship: Ship, cell: Vector2i, type: int, rot := false) -> Array:
	var dims := BlockDB.bundle_dims(type, ship.scale_unit, rot)
	var origin := cell - dims / 2
	var out: Array = []
	for dy in dims.y:
		for dx in dims.x:
			out.append(origin + Vector2i(dx, dy))
	return out


## Can this whole stamp land? ALL-OR-NOTHING, which is the point of the rule:
## every cell must be empty (a machine is never half-embedded in hull), and
## the stamp must touch existing structure from outside itself — the same
## grow-off-a-neighbour law can_place_at enforces per cell — unless the ship
## has no blocks at all yet.
static func stamp_valid(ship: Ship, cells: Array) -> bool:
	if cells.is_empty():
		return false
	var inside := {}
	for c in cells:
		if ship.blocks.has(c):
			return false
		inside[c] = true
	if ship.blocks.is_empty():
		return true
	for c in cells:
		for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + n
			if not inside.has(nb) and ship.blocks.has(nb):
				return true
	return false


## An order for setting the stamp's cells such that every one lands legally:
## seeded on a cell with an occupied OUTSIDE neighbour (any cell on an empty
## ship), then breadth-first through the stamp — each later cell borders an
## earlier one, so per-cell can_place_at holds all the way. Empty when the
## stamp is invalid.
static func stamp_order(ship: Ship, cells: Array) -> Array:
	if not stamp_valid(ship, cells):
		return []
	var inside := {}
	for c in cells:
		inside[c] = true
	var seed_cell: Vector2i = cells[0]
	for c in cells:
		var anchored := false
		for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + n
			if not inside.has(nb) and ship.blocks.has(nb):
				anchored = true
		if anchored:
			seed_cell = c
			break
	var out: Array = [seed_cell]
	var seen := {seed_cell: true}
	var head := 0
	while head < out.size():
		var c: Vector2i = out[head]
		head += 1
		for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + n
			if inside.has(nb) and not seen.has(nb):
				seen[nb] = true
				out.append(nb)
	return out


## The whole MACHINE under `cell`: the 4-connected region of same-type cells.
## What C deconstructs when the type is a bundle — "an engine is never a
## single block" cuts both ways, so you cannot whittle one down to a sliver
## either. For an authored ship this is exactly one authored component.
static func machine_region(ship: Ship, cell: Vector2i) -> Array:
	if not ship.blocks.has(cell):
		return []
	var type: int = ship.blocks[cell]["type"]
	var out: Array = [cell]
	var seen := {cell: true}
	var head := 0
	while head < out.size():
		var c: Vector2i = out[head]
		head += 1
		for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + n
			if not seen.has(nb) and ship.blocks.has(nb) \
					and int(ship.blocks[nb]["type"]) == type:
				seen[nb] = true
				out.append(nb)
	return out


## "lift 1.29 -> 1.27" — the before/after in one glance, which is the
## entire feature. ASCII arrow on purpose: the readout is drawn with
## ThemeDB's fallback font, and a missing glyph reads as a tofu box.
static func readout(before: float, after: float) -> String:
	return "lift %.2f -> %.2f" % [before, after]
