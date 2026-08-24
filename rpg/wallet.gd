class_name Wallet
extends RefCounted

## A character's money (Sprint 5, the economy). Deliberately a thin RefCounted —
## the sibling of `Inventory` — so the whole money/salvage/trainer loop is pure
## logic and unit-testable without a scene. Currency is a single integer balance;
## salvage credits it (rpg/economy.gd) and trainers spend it (rpg/training.gd).
##
## Money-not-grind (charter §6, ROADMAP ruling): stat levels are BOUGHT with this,
## never earned by an XP treadmill. So the whole progression economy is: mine and
## harvest -> sell salvage for money -> buy stat levels from a trainer.

var balance := 0


## Credit `amount` (ignored if <= 0 — you cannot gain nothing).
func add(amount: int) -> void:
	if amount > 0:
		balance += amount


func can_afford(amount: int) -> bool:
	return balance >= amount


## Spend `amount`; returns true only if it was affordable (and then deducts it).
## A refused spend changes nothing — no going into debt, no partial charge.
func spend(amount: int) -> bool:
	if amount < 0 or balance < amount:
		return false
	balance -= amount
	return true
