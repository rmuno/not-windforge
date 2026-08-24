class_name Training
extends RefCounted

## Buying stat levels from a trainer (Sprint 5). The whole engine is three static
## functions over a `Stats` and a `Wallet` — both RefCounted — so raising a stat
## for money is unit-testable without a trainer node or a scene, exactly like
## `Recipes.craft` is testable without a crafting station.
##
## Money-not-grind (charter §6): a level costs money, full stop — no XP. The cost
## RISES with the level, the source's "~+$100 per level" (owner memory), mapped
## onto our compressed 1..5: raising from level L to L+1 costs BASE_COST × L, so
## 1→2 is 100, 2→3 is 200 ... 4→5 is 400. Trainers cap at level 5 (the source's
## master trainers to 100; our flat 5).

const BASE_COST := 100


## What it costs to raise `stat` one level from where it is now, or -1 if the stat
## is already maxed (nothing to buy). Rising: BASE_COST × the current level.
static func cost_to_raise(stats: Stats, stat: int) -> int:
	if stats == null or not stats.can_raise(stat):
		return -1
	return BASE_COST * stats.level_of(stat)


## Can this be bought right now — not maxed, and affordable?
static func can_train(stats: Stats, wallet: Wallet, stat: int) -> bool:
	if stats == null or wallet == null:
		return false
	var cost := cost_to_raise(stats, stat)
	return cost >= 0 and wallet.can_afford(cost)


## Buy one level of `stat`: on success, deduct the money AND raise the level
## (granting the next perk), returning true. Refused — and NOTHING changes, no
## money spent, no level gained — if the stat is maxed or the wallet is short.
## The check-then-apply order guarantees no half-spend.
static func train(stats: Stats, wallet: Wallet, stat: int) -> bool:
	if not can_train(stats, wallet, stat):
		return false
	var cost := cost_to_raise(stats, stat)
	# can_train already proved affordability and that the stat can rise, so
	# neither of these can fail here — but they are the real mutations, ordered
	# money-then-level so a maxed guard could never leave money spent for nothing.
	if not wallet.spend(cost):
		return false
	return stats.raise_level(stat)
