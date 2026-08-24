class_name Stats
extends RefCounted

## A character's four RPG stat LEVELS and the behaviour they buy (Sprint 5, the
## progression layer). This is the mutable per-player state — `StatDB` holds the
## static ladder and effects, exactly as `Inventory` holds counts against
## `ItemDB`'s item space. Pure logic (a RefCounted, no tree), so the whole
## progression is unit-testable without a scene.
##
## Levels are 1..5 flat (the ROADMAP ruling); level N means perks 1..N are
## unlocked. Effects are DERIVED from the unlocked perks — never stored — so the
## table is the single source of truth and the getters can never drift from it.
## Raising a level is `raise_level`; buying it (money, trainer) is rpg/training.gd.

## Stat -> level (int). Absent == MIN_LEVEL (1), so a fresh Stats is a valid
## level-1-everywhere character with no entries.
var _levels := {}


func level_of(stat: int) -> int:
	return int(_levels.get(stat, StatDB.MIN_LEVEL))


func set_level(stat: int, level: int) -> void:
	_levels[stat] = clampi(level, StatDB.MIN_LEVEL, StatDB.MAX_LEVEL)


func can_raise(stat: int) -> bool:
	return level_of(stat) < StatDB.MAX_LEVEL


## Raise `stat` by one level (granting the next perk). Returns false — and changes
## nothing — if already at MAX_LEVEL, so callers never overshoot the cap.
func raise_level(stat: int) -> bool:
	if not can_raise(stat):
		return false
	_levels[stat] = level_of(stat) + 1
	return true


## Is perk `n` (1-based) of `stat` unlocked? Perk N unlocks at level N, so this is
## simply level >= n — the whole "level == perk" ruling in one line.
func has_perk(stat: int, n: int) -> bool:
	return level_of(stat) >= n


# --- Effects: derived from the unlocked perks ------------------------------
#
# Each effect key appears in exactly one ladder today, but the aggregation scans
# ALL unlocked perks — so a future cross-stat effect (or a re-homed perk) just
# works, and no getter hard-codes which stat owns which effect.

## Every unlocked perk's `effect` dict, across all four stats.
func _unlocked_effects() -> Array:
	var out: Array = []
	for stat in StatDB.STATS:
		var perks: Array = StatDB.STATS[stat]["perks"]
		var top := mini(level_of(stat), perks.size())
		for i in top:
			out.append(perks[i]["effect"])
	return out


## The largest value of `key` among unlocked perks, or `base` if none set it.
## Used where perks SUPERSEDE (a stronger mining multiplier replaces a weaker).
func _max_effect(key: String, base: float) -> float:
	var best := base
	for eff in _unlocked_effects():
		if eff.has(key):
			best = maxf(best, float(eff[key]))
	return best


## The sum of `key` across unlocked perks (0 if none). Used where perks STACK
## (each health perk adds its own bonus).
func _sum_effect(key: String) -> float:
	var total := 0.0
	for eff in _unlocked_effects():
		if eff.has(key):
			total += float(eff[key])
	return total


## True if any unlocked perk sets `key` truthy. Used for boolean gates.
func _any_effect(key: String) -> bool:
	for eff in _unlocked_effects():
		if bool(eff.get(key, false)):
			return true
	return false


## Multiplier on mining / harvesting speed (BRAWN). 1.0 baseline.
func mine_power_mult() -> float:
	return _max_effect("mine_mult", StatDB.BASE_MINE_MULT)


## Extra mining / harvesting reach in CELLS (BRAWN). 0 baseline.
func mine_reach_bonus() -> float:
	return _max_effect("mine_reach", 0.0)


## Multiplier on on-foot movement speed (GRACE). 1.0 baseline.
func move_speed_mult() -> float:
	return _max_effect("move_mult", StatDB.BASE_MOVE_MULT)


## Is the mid-air second jump unlocked (GRACE)?
func double_jump_enabled() -> bool:
	return _any_effect("double_jump")


## Multiplier on weapon fire-rate (GRACE quickness — the same reflexes that buy
## foot speed buy a quicker trigger). 1.0 baseline; a higher value shortens the
## interval between shots (see Player.sidearm_interval). Perks SUPERSEDE, so the
## strongest unlocked quickness wins.
func fire_rate_mult() -> float:
	return _max_effect("fire_rate", 1.0)


## The character's maximum hit points (GRIT): the base pool plus every unlocked
## health bonus. Hostile fire and hazards now drain this pool (Player.take_damage)
## and GRIT regen mends it, so a higher GRIT measurably survives more.
func max_health() -> float:
	return StatDB.BASE_HEALTH + _sum_effect("max_health")


## Hit points regenerated per second (GRIT). 0 baseline (no regen until a perk).
func regen_rate() -> float:
	return _max_effect("regen", 0.0)


## The taming TIER this character can handle (LORE): 0 = cannot tame, 1 = small
## beasts (Beast Whisperer), 2 = the great whales (Master Trader). The gate is
## `taming_level() >= creature.tame_level` (world.try_tame), so a whale needs the
## higher perk and a critter the lower one — the small→whale progression (WIKI).
func taming_level() -> int:
	return int(_max_effect("taming", 0.0))


## Is ANY taming unlocked (LORE)? Kept as the coarse "can this character tame at
## all" gate (HUD cue, the refused-message path); the per-creature gate is
## taming_level() vs the creature's tame_level. Wisdom-gated, exactly as the source.
func taming_enabled() -> bool:
	return taming_level() > 0


## Fractional bonus to salvage sale prices (LORE): 0.25 == +25%. 0 baseline.
func trade_bonus() -> float:
	return _max_effect("trade_bonus", 0.0)


## Carry capacity (BRAWN). NOTE (seam): the inventory has no weight/stack cap
## today, so this is an exposed number nothing enforces yet — the hook the item
## economy grows on (BACKLOG: stack limits). Base + the largest unlocked bonus.
func carry_capacity() -> float:
	return StatDB.BASE_CARRY + _max_effect("carry", 0.0)
