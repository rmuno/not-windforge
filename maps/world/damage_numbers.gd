class_name DamageNumbers
extends RefCounted

## Floating collision-damage numbers, coalesced per source (owner 2026-08-22:
## "small damage numbers at the point of collision, adding up multiple within
## the same ~0.5s window if more keep coming from the same source").
##
## A number is placed in WORLD space at the impact point and floats there — it
## follows nothing, because the hit happened at a fixed spot in the world, not
## on the moving hull. The world listens to every ship's `collision_damage`
## signal and feeds add() here; a world overlay draws active() each frame.
##
## COALESCING KEY — (source ship + a small spatial bucket of the impact point).
## We cannot tell WHICH shot/ram from `collision_damage` alone, so "same source"
## is approximated as: the same ship, hitting at roughly the same place, within
## the window. A sustained crush pins a ship against one wall spot, so every
## step lands in the same bucket and accumulates into ONE growing number instead
## of a spray of dozens. Two different ships (or one ship crushing at two
## clearly separate spots) get separate numbers. The bucket is sized in CELLS
## and multiplied by the world scale, so the keying is scale-invariant.
##
## This class is pure logic (no nodes, no rendering) so the coalescing and
## expiry are unit-testable directly — see tests/run_tests.gd.

## Same-source hits within this many seconds of the live number ADD to it and
## reset its clock. Past it, a new hit starts a fresh number.
const COALESCE_WINDOW := 0.5
## A number rises and fades over this long, measured from its LAST hit — so a
## number being fed keeps living, and only starts dying once the hits stop.
##
## CALMED 2026-08-30 (owner: *"text flies off too fast when getting money or
## going a new level. Maybe 25% slower and less height"*). The animation now runs
## a quarter longer and rises 30% less, which together cut the apparent rise
## speed roughly in half — the number reads as a label that lifts off the hit
## rather than a spark leaving it. `PickupFloats` carries the same pair and they
## are meant to move together; they are the two halves of one idiom.
const LIFETIME := 0.95
## How far a number drifts upward over its life, in cells (× world scale).
const RISE_CELLS := 1.0
## Spatial bucket edge for the coalescing key, in cells (× world scale). Four
## cells is generous enough that a crush "at roughly one spot" stays one number.
const BUCKET_CELLS := 4.0
## Hits below this contribute nothing worth a number (owner: skip negligible).
const MIN_AMOUNT := 1.0

## Each: {"key": String, "pos": Vector2, "total": float, "age": float,
##        "scale": float}. `age` is seconds since the last contributing hit.
var _numbers: Array[Dictionary] = []


## Record a collision hit. Coalesces into a live number with the same key whose
## window has not lapsed; otherwise spawns a new one. `source_id` is typically
## the damaged ship's instance id.
func add(source_id: int, world_pos: Vector2, amount: float, world_scale := 1.0) -> void:
	if amount < MIN_AMOUNT:
		return
	var key := _key(source_id, world_pos, world_scale)
	for n in _numbers:
		if n["key"] == key and n["age"] < COALESCE_WINDOW:
			n["total"] += amount
			n["age"] = 0.0        # refresh the window AND the fade
			n["pos"] = world_pos  # track the latest contact spot
			return
	_numbers.append({
		"key": key,
		"pos": world_pos,
		"total": amount,
		"age": 0.0,
		"scale": world_scale,
	})


## Advance every number by dt and free any past its lifetime. Cheap; call once
## per frame. No node lifetime to leak — a number is a dict dropped from the
## array, so an expired number is simply gone.
func update(dt: float) -> void:
	var kept: Array[Dictionary] = []
	for n in _numbers:
		n["age"] += dt
		if n["age"] < LIFETIME:
			kept.append(n)
	_numbers = kept


## The live numbers, for the overlay to draw. Not a copy — read-only by contract.
func active() -> Array[Dictionary]:
	return _numbers


func count() -> int:
	return _numbers.size()


## Bucketed key: same ship + same coarse world cell. floori (not truncation) so
## negative coordinates bucket consistently on both sides of the origin.
func _key(source_id: int, world_pos: Vector2, world_scale: float) -> String:
	var b := maxf(BUCKET_CELLS * Ship.CELL * world_scale, 1.0)
	return "%d:%d:%d" % [source_id, floori(world_pos.x / b), floori(world_pos.y / b)]
