class_name Inventory
extends RefCounted

## What a player is carrying — the payoff of mining (Sprint 2). Deliberately a
## thin, clean data structure: a map of item type -> count, with add/remove/count.
## Future crafting, the economy and item stacks build ON this rather than beside
## it, so it carries no rendering, no nodes and no game rules of its own.
##
## Item types are TerrainDB.Type ints today (dirt/stone/ore — what you dig). The
## structure is type-agnostic: any int key works, so when items grow past terrain
## (whale products, crafted parts) they slot in without a schema change. It is
## pure logic (a RefCounted, no tree) so the counting is unit-testable directly.

## type (int) -> count (int). A type with a zero count is dropped entirely, so
## `_counts` only ever holds present items — `is_empty()` and `types()` stay honest.
var _counts := {}


## Add `amount` of `type`. Amounts < 1 are ignored (you cannot gain nothing).
## Mining credits exactly one cell per dig, but the API takes an amount so
## stacks and crafting yields land in one call.
func add(type: int, amount := 1) -> void:
	if amount < 1:
		return
	_counts[type] = int(_counts.get(type, 0)) + amount


## Remove up to `amount` of `type`; returns how many were ACTUALLY removed (you
## cannot remove what you do not carry). A type driven to zero is erased so the
## map only ever lists what you hold.
func remove(type: int, amount := 1) -> int:
	if amount < 1:
		return 0
	var have := int(_counts.get(type, 0))
	var taken := mini(have, amount)
	if taken <= 0:
		return 0
	var left := have - taken
	if left <= 0:
		_counts.erase(type)
	else:
		_counts[type] = left
	return taken


## How many of `type` are carried (0 if none).
func count(type: int) -> int:
	return int(_counts.get(type, 0))


## Total items across every type — the "how full am I" number.
func total() -> int:
	var n := 0
	for t in _counts:
		n += int(_counts[t])
	return n


## The item types currently held, sorted for a stable HUD order (so the readout
## does not reshuffle as counts change).
func types() -> Array:
	var out: Array = _counts.keys()
	out.sort()
	return out


func is_empty() -> bool:
	return _counts.is_empty()


func clear() -> void:
	_counts.clear()
