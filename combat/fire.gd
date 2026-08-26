class_name Fire
extends RefCounted

## FIRE, as a grid BLOCK-STATE (roadmap Phase 4; DESIGN charter §5).
##
## The source's fire was its main threat multiplier and its buggiest system, so
## the spec for ours was written before a line of it existed: "a grid
## block-state (spread/douse cell-by-cell, never a free physics object; a
## fight, not a verdict)". Every word of that is a constraint:
##
##   * A GRID BLOCK-STATE. Fire lives in a dictionary of burning cells on the
##     Ship, next to `blocks` and `walls`. It is not a node, not a particle, not
##     a body — nothing to collide, nothing to spawn, nothing to leak.
##   * SPREAD AND DOUSE CELL BY CELL. It moves to NEIGHBOURS, one at a time, at
##     a rate set by what the neighbour is made of. Blubber and gasbag catch
##     fast, hull barely, shell and stone never. So a firebreak is a real tactic:
##     deconstruct a row of hull and the fire has nowhere to go.
##   * A FIGHT, NOT A VERDICT. It must be losable AND winnable. The repair wand
##     (X) puts fire out — no new key, no new tool (the owner's one-key-per-verb
##     standing order), and it is already the "get back from a bad moment" verb.
##     Fire burns OUT on its own too, so a fire in a corner of the hull is not a
##     death sentence for an unarmed player.
##
## WHAT BURNS. Flammability is a BlockDB property, so a new block type declares
## its own behaviour and this file never grows a type switch (the project's
## "block behaviour is data" rule).
##
## The whole model is pure functions over (ship, burning set, dt) plus a small
## amount of state on the Ship, so it is testable headless without a world, a
## renderer or a physics step.

## Damage per second a burning cell takes. Slow on purpose: a fire that eats a
## hull in two seconds is a verdict.
const BURN_DPS := 12.0

## Seconds a cell burns before it goes out by itself, if nothing else stops it.
const BURN_SECONDS := 12.0

## Chance per second that a burning cell lights ONE flammable neighbour, before
## that neighbour's own flammability multiplies it.
const SPREAD_PER_SECOND := 1.0

## Seconds of wand contact to put one cell out. Under a second: dousing has to
## feel like sweeping, not like grinding.
const DOUSE_SECONDS := 0.35

## Cells whose fire has burned out are ASH for this long — they cannot re-light,
## so a fire cannot oscillate forever over the same cell while its neighbours
## keep re-igniting it.
const ASH_SECONDS := 20.0


## How readily a block type catches, as a multiplier on SPREAD_PER_SECOND.
## 0 means it never burns at all: fire simply does not cross it.
static func flammability(type: int) -> float:
	return float(BlockDB.get_def(type).get("flammable", 0.0))


static func burns(type: int) -> bool:
	return flammability(type) > 0.0


## Can this cell of this ship catch fire right now? Everything the caller needs
## to know in one place: the cell exists, its material burns, it is not already
## alight, and it is not still ash from the last fire.
static func can_ignite(ship: Ship, cell: Vector2i, now: float) -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.blocks.has(cell):
		return false
	if ship.burning.has(cell):
		return false
	if float(ship.burn_ash.get(cell, -1.0e12)) > now - ASH_SECONDS:
		return false
	return burns(int(ship.blocks[cell]["type"]))


## Light a cell. Returns whether anything caught — callers use it to decide
## whether to say so out loud.
static func ignite(ship: Ship, cell: Vector2i, now: float) -> bool:
	if not can_ignite(ship, cell, now):
		return false
	ship.burning[cell] = now
	return true


## The four neighbours a fire can reach. Diagonals deliberately excluded: fire
## that crosses corners jumps gaps a player would read as a firebreak, and the
## firebreak is the tactic this whole system exists to reward.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]


## One step of a ship's fire. Returns a report: how many cells burned, how many
## caught, how many went out. `rng` is passed in so the caller owns determinism
## — the same seed gives the same fire, which is what makes it testable.
##
## Damage goes through `net_damage_cell`, the SHOT path, so a burning ship uses
## the incremental combat machinery (no per-cell rebuild storm) and floats its
## damage numbers like any other hit.
static func step(ship: Ship, dt: float, now: float,
		rng: RandomNumberGenerator) -> Dictionary:
	var report := {"burning": 0, "caught": 0, "out": 0, "damage": 0.0}
	if ship == null or not is_instance_valid(ship) or ship.burning.is_empty():
		return report
	var lit: Array[Vector2i] = []
	var doused: Array[Vector2i] = []
	for cell in ship.burning:
		var started := float(ship.burning[cell])
		# Gone: the cell was destroyed (by this fire or anything else), or it
		# has burned its time out.
		if not ship.blocks.has(cell) or now - started >= BURN_SECONDS:
			doused.append(cell)
			continue
		report["burning"] = int(report["burning"]) + 1
		report["damage"] = float(report["damage"]) + BURN_DPS * dt
		ship.net_damage_cell(cell, BURN_DPS * dt)
		# Spread to ONE neighbour at a time. Picking a single candidate per
		# step (rather than rolling all four) keeps a fire's growth linear in
		# its perimeter instead of exploding, which is the difference between a
		# fight and a verdict.
		var target: Vector2i = cell + NEIGHBOURS[rng.randi_range(0, 3)]
		if can_ignite(ship, target, now):
			var chance := SPREAD_PER_SECOND * flammability(
				int(ship.blocks[target]["type"])) * dt
			if rng.randf() < chance:
				lit.append(target)
	for cell in doused:
		ship.burning.erase(cell)
		ship.burn_ash[cell] = now
		report["out"] = int(report["out"]) + 1
	for cell in lit:
		if ignite(ship, cell, now):
			report["caught"] = int(report["caught"]) + 1
	return report


## Put out every burning cell within `radius` px of a world point, charging
## `dt` seconds of effort against each. Returns how many went out — the repair
## wand's fire half (world._handle_repair), so the same sweep that mends a hull
## smothers what is burning on it.
static func douse(ship: Ship, world_point: Vector2, radius: float, dt: float,
		now: float) -> int:
	if ship == null or not is_instance_valid(ship) or ship.burning.is_empty():
		return 0
	var out := 0
	var done: Array[Vector2i] = []
	for cell in ship.burning:
		if ship.to_global(ship.local_pos_of(cell)).distance_to(world_point) > radius:
			continue
		# Effort accumulates in the same dictionary the fire lives in: a cell
		# under the wand has its start time pushed BACK, ageing the fire toward
		# its own burnout. DOUSE_SECONDS of sweeping ages it the full
		# BURN_SECONDS, so the wand beats a fresh fire in about a third of a
		# second and there is no second clock to keep in sync.
		var aged := float(ship.burning[cell]) - dt * (BURN_SECONDS / DOUSE_SECONDS)
		if now - aged >= BURN_SECONDS:
			done.append(cell)
		else:
			ship.burning[cell] = aged
	for cell in done:
		ship.burning.erase(cell)
		ship.burn_ash[cell] = now
		out += 1
	return out
