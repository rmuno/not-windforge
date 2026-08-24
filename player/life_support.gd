class_name LifeSupport
extends RefCounted

## The DEPTH survival gate (WORLD_SPEC: the deep band's unbreathable air; ROADMAP
## Phase 2 "depth hazard"). Below the deep-band threshold the air is unbreathable;
## an unprotected person SUFFOCATES — periodic damage into the GRIT pool
## (Player.take_damage) — unless they carry the craftable life-support item. This
## is the depth half of "equipment gates altitude in both directions": life-support
## to go DOWN. (The UP gate — thin air / ship quality up top — is a separate, later
## slice; a documented seam.)
##
## GATE MODEL — POSSESSION (owner-recommended; see DECISIONS): holding ONE
## life-support item protects you anywhere in the deep. Clean, testable, and it
## extends (tiers, durability) without reshaping callers. A depleting air SUPPLY
## (a consumable timer that refills at breathable altitude) is the documented
## alternative, left as a seam — nothing here forecloses it.
##
## ON-FOOT vs SHIP: this is the PERSON'S air. It reads the player's own position,
## so it bites on foot, at the helm, AND while riding a creature — a hull is not a
## pressurised cabin in this model, so you cannot cheat the deep by sitting at the
## controls. Only the item protects. (A sealed-ship shelter is a documented seam.)
##
## Pure decision + a small stateful tick, no nodes of its own: the band question
## delegates to Airspace (the one band authority), possession reads the Inventory,
## and the world drives the damage tick each frame from the local player's
## altitude. Tests exercise the whole thing without a live world.

## The item that protects (ItemDB CRAFTED range). Crafted from copper ingot +
## blubber — gear you assemble in the breathable bands before you descend
## (items/recipes.gd). Possession of ONE is the whole gate.
const ITEM := ItemDB.Crafted.LIFE_SUPPORT


## Is the air at altitude fraction `a` (0 = floor, 1 = ceiling) unbreathable?
## Delegates to Airspace so the band model stays the single source of truth. A
## negative `a` means "no sky mapped" (e.g. the Sprint-1 arena) and reads as
## breathable — the deep gate never fires where there is no deep band.
static func air_unbreathable(a: float) -> bool:
	return a >= 0.0 and Airspace.is_unbreathable_frac(a)


## Does a person carrying `inv` have depth protection? Possession of one
## life-support item is the whole gate.
static func protected(inv: Inventory) -> bool:
	return inv != null and inv.count(ITEM) > 0


## Does the deep air bite this person right now? Unbreathable air AND unprotected.
## The pure decision behind both the damage tick and the HUD warning.
static func suffocating(a: float, inv: Inventory) -> bool:
	return air_unbreathable(a) and not protected(inv)


## Advance one frame of deep-air suffocation for `who` at altitude fraction `a`,
## carrying the cooldown `cd` between calls (the world owns it), and return the new
## cooldown. OFF-COST: with the person safe (breathable air, or protected) it
## re-arms the timer and returns at once, so nothing runs and no damage lands away
## from the deep — the resident-world discipline the hazards use. Suffocating, it
## counts `cd` down by `delta` and, each time it elapses, drains one tick of the
## GRIT pool through Player.take_damage (the same sink hostile fire and hazards
## use — death and respawn already flow from it). Rate/damage are the F2 tunables.
static func tick(who: Player, a: float, delta: float, cd: float) -> float:
	if who == null or not is_instance_valid(who):
		return cd
	if not suffocating(a, who.inventory):
		# Safe: re-arm so a fresh descent gets a full interval of grace before the
		# first bite (and the warning cue) rather than an instant hit.
		return Tunables.get_num("suffocate_interval")
	cd -= delta
	if cd <= 0.0:
		cd = maxf(0.05, Tunables.get_num("suffocate_interval"))
		who.take_damage(Tunables.get_num("suffocate_damage"))
	return cd
