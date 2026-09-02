class_name PickupFloats
extends RefCounted

## Floating "+1 Stone" pickup numbers that pop when you mine a cell — the
## immediate, tactile feedback the mining slice is judged on (Terraria feel,
## MARKET.md §3). The dug cell vanishing is the primary confirmation; this is
## the satisfying flourish on top.
##
## Same float-and-fade idiom as DamageNumbers (a hit rises and fades over its
## life), but SIMPLER: pickups are discrete events, one per dig, so there is no
## coalescing — each dig is its own small text. Pure logic (no nodes, no
## rendering) so it is unit-testable directly; the WorldOverlay draws active().

## How long a pickup float lives (rise + fade), in seconds. Short — it is a
## confirmation, not a message to read... except that `world._notify` reuses this
## class for its one-line messages, so it is also the only thing that shows a
## run's "IT IS YOURS" or a new depth.
##
## CALMED 2026-08-30 (owner: *"text flies off too fast when getting money or
## going a new level. Maybe 25% slower and less height"*) — a quarter longer,
## 30% less rise. "Going a new level" IS this class, not a separate path: the
## Dive's depth notices come through `_notify`. `DamageNumbers` carries the same
## pair and the two move together.
const LIFETIME := 1.15
## How far it drifts upward over its life, in cells (× world scale).
const RISE_CELLS := 1.1

## Each: {"pos": Vector2, "text": String, "age": float, "scale": float}.
var _floats: Array[Dictionary] = []


## Record a pickup at `world_pos`. `text` is the label ("+1 Stone"); `world_scale`
## sizes both the font and the rise so it stays legible at any scale.
func add(world_pos: Vector2, text: String, world_scale := 1.0) -> void:
	_floats.append({
		"pos": world_pos,
		"text": text,
		"age": 0.0,
		"scale": world_scale,
	})


## Advance every float and drop the expired ones. Cheap; call once per frame.
func update(dt: float) -> void:
	var kept: Array[Dictionary] = []
	for f in _floats:
		f["age"] += dt
		if f["age"] < LIFETIME:
			kept.append(f)
	_floats = kept


## The live floats, for the overlay to draw. Not a copy — read-only by contract.
func active() -> Array[Dictionary]:
	return _floats


func count() -> int:
	return _floats.size()


## Carry every live float across a ring wrap (`world._dive_wrap_ring`) — see
## DamageNumbers.shift_x for why a world-anchored mark has to move with the
## world.
func shift_x(dx: float) -> void:
	for f in _floats:
		f["pos"] = (f["pos"] as Vector2) + Vector2(dx, 0.0)
