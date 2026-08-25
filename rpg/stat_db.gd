class_name StatDB
extends RefCounted

## The static, data-driven RPG stat + perk table (Sprint 5, the progression
## layer). This is to `Stats` what `ItemDB` is to `Inventory`: the mutable
## per-player state lives in rpg/stats.gd; the SHAPE of the system — which stats
## exist, what each level unlocks, and what each perk DOES — is fixed here and
## nowhere else, so tuning the ladder never touches game code.
##
## THE RULING (ROADMAP Q4, owner 2026-08-20): four stats, levels 1–5 FLAT, and
## our level N == the source's perk N. The source's 20/40/60/80/100 thresholds
## collapse exactly onto levels 1..5. A stat starts at level 1 (perk 1 already
## granted) and tops out at level 5 (all five perks). Stats are raised by paying
## trainers — money, not grind-XP (rpg/training.gd).
##
## CLEAN-ROOM: the stat names and all perk names/flavour are OURS. The source's
## Strength/Agility/Vitality/Wisdom trees are the STRUCTURE we rebuilt; none of
## its expression ships. Our four, and the shape each is modelled on:
##   BRAWN  (might-shaped)   — labour and load: mining/harvesting speed + reach.
##   GRACE  (agility-shaped) — movement: run speed, double jump.
##   GRIT   (vitality-shaped)— body: hit points and regeneration.
##   LORE   (wisdom-shaped)  — mind: trade prices, taming, craft quality.
##
## Each perk carries an `effect` dict the effects layer (Stats) reads. WIRED
## effects change real behaviour today; STUB effects are documented seams for
## systems that do not exist yet (the perk still unlocks — its effect is inert
## until the system lands). Absent keys mean "no effect of that kind".

enum Stat { BRAWN, GRACE, GRIT, LORE }

const MIN_LEVEL := 1
const MAX_LEVEL := 5

## The baselines the effect multipliers/pools build on — an un-invested character
## (every stat at level 1) plays exactly like the pre-RPG game, so the layer is
## additive, never a nerf to the old feel.
const BASE_MINE_MULT := 1.0
const BASE_MOVE_MULT := 1.0
const BASE_HEALTH := 100.0
const BASE_CARRY := 100.0

## The four ladders. `perks` is ordered perk 1..5; perk i (1-based) unlocks at
## stat level i. Level 1's perk is the neutral baseline where it can be, so the
## first purchase (1→2) is the first real change.
const STATS := {
	Stat.BRAWN: {
		"name": "Brawn",
		"blurb": "Muscle. Dig faster, reach further, haul more.",
		"perks": [
			{"name": "Calloused Hands", "desc": "Hardened enough to work the rock.", "effect": {}},
			{"name": "Strong Arm", "desc": "Mining and harvesting come much faster.", "effect": {"mine_mult": 1.8}},
			{"name": "Long Reach", "desc": "Cut terrain and carcasses from further off.", "effect": {"mine_reach": 2.0}},
			{"name": "Quarryman", "desc": "Faster still through stone and flesh.", "effect": {"mine_mult": 2.6}},
			{"name": "Juggernaut", "desc": "Tear through anything you can touch.", "effect": {"mine_mult": 4.0, "carry": 200.0}},
		],
	},
	Stat.GRACE: {
		"name": "Grace",
		"blurb": "Footwork and quick hands. Move quicker, shoot quicker, stay off the ground longer.",
		"perks": [
			{"name": "Light Step", "desc": "Sure-footed on any deck.", "effect": {}},
			{"name": "Fleet Foot", "desc": "You run noticeably faster — and your trigger hand keeps pace.", "effect": {"move_mult": 1.25, "fire_rate": 1.25}},
			{"name": "Double Jump", "desc": "A second leap in mid-air.", "effect": {"double_jump": true}},
			{"name": "Wall Kick", "desc": "Kick off a wall to climb it. [STUB: wall-jump not built]", "effect": {}},
			{"name": "Sprinter", "desc": "Full pace, on foot and on the trigger.", "effect": {"move_mult": 1.6, "fire_rate": 1.6}},
		],
	},
	Stat.GRIT: {
		"name": "Grit",
		"blurb": "Toughness. More hit points, and wounds that close on their own.",
		"perks": [
			{"name": "Hardy", "desc": "A body that takes a knock.", "effect": {}},
			{"name": "Toughened", "desc": "More hit points.", "effect": {"max_health": 50.0}},
			{"name": "Second Wind", "desc": "Light wounds heal on their own.", "effect": {"regen": 2.0}},
			{"name": "Ironhide", "desc": "Many more hit points.", "effect": {"max_health": 100.0}},
			{"name": "Undying", "desc": "You mend fast.", "effect": {"regen": 6.0}},
		],
	},
	Stat.LORE: {
		"name": "Lore",
		"blurb": "Wits. Better prices, a way with beasts, finer craft.",
		"perks": [
			{"name": "Curious", "desc": "You pay attention.", "effect": {}},
			{"name": "Haggler", "desc": "Salvage sells for more.", "effect": {"trade_bonus": 0.25}},
			{"name": "Beast Whisperer", "desc": "You can tame small beasts — grapple, hold, and ride them.", "effect": {"taming": 1}},
			{"name": "Artisan", "desc": "Your craft comes out finer. [STUB: craft quality not built]", "effect": {}},
			{"name": "Master Trader", "desc": "The best prices in the sky — and the great whales, even the deep krakens, answer you.", "effect": {"trade_bonus": 0.6, "taming": 3}},
		],
	},
}


static func names() -> Array:
	## The stat ids in a stable display order (enum order).
	return [Stat.BRAWN, Stat.GRACE, Stat.GRIT, Stat.LORE]


static func def(stat: int) -> Dictionary:
	return STATS.get(stat, STATS[Stat.BRAWN])


static func stat_name(stat: int) -> String:
	return def(stat)["name"]


static func blurb(stat: int) -> String:
	return def(stat)["blurb"]


## The perk dict for `stat`'s perk `n` (1-based, 1..5), or an empty dict if out
## of range. Callers read ["name"]/["desc"]/["effect"].
static func perk(stat: int, n: int) -> Dictionary:
	var perks: Array = def(stat)["perks"]
	if n < 1 or n > perks.size():
		return {}
	return perks[n - 1]


static func perk_name(stat: int, n: int) -> String:
	return perk(stat, n).get("name", "")
