class_name DiveCards
extends RefCounted

## THE DIVE'S CARD CATALOG (owner arc Q-L, 2026-08-31). A run-scoped upgrade draft:
## defeat things on the way down and you draw cards that make THIS run stronger —
## the roguelite power curve the Dive was missing between landings. Banked coins
## stay the META reward; cards are the in-run build, and they burn with the run.
##
## THE COHESION THE OWNER ASKED FOR ("lots of systems, little cohesion"): a card is
## not a new mechanic. It is EITHER a passive MULTIPLIER on a dial that already
## exists (weapon damage, turret damage, fire rate, mending) OR a PROC wired to an
## in-game EVENT that already fires (onKill, onHit, onLand). So adding a card is a
## DATA ROW here, and the world's existing combat/kill/landing sites just ask "what
## do my cards do on this event?". Nothing new to maintain; the scattered systems
## get tied together under one draft.
##
## Pure data + logic, no autoloads — the model (`DiveRun`) holds which cards are
## held and answers `modifier(key)` / `procs_for(event)` from this catalog; the
## WORLD reads those and acts (world-decides/layer-paints, same split the bestiary
## used). Safe to name as a type in a test.
##
## EFFECT VOCABULARY, so a card row stays declarative and the world's interpreter
## stays a small closed set:
##   mods:  {dial_key: multiplier}          — multiplied into an existing number
##     dials wired today: "weapon_damage" (player sidearm), "turret_damage" (your
##     ship's guns), "fire_rate" (sidearm interval — <1 is FASTER), "hull_repair"
##     (the Dive assistant's mend rate), "thrust" (your hull's propeller force —
##     `Ship.thrust_mult`, stamped on the local ship each dive tick, reset by
##     end_dive). STAGED (model supports, world not yet): "grapple", "ride".
##   procs: [{on, effect, amount}]           — fired when the world emits `on`
##     events wired today: "kill" (a creature died to you), "hit" (your shot landed
##     on an enemy), "land" (you reached a new depth). STAGED: "attack", "hurt".
##     effects wired today: "coins" (+amount to the pot), "heal" (+amount HP to the
##     player), "lifesteal" (heal amount× the damage dealt).

## The deck. Order is display order within the draft. Weights bias the draw (a
## common card is offered more often than a run-defining one). Keep procs' effect/
## amount in the closed vocabulary above, or the world silently ignores them and
## `_test_dive_cards` reddens on the parity check.
const CATALOG := [
	{"id": "honed_edge", "name": "Honed Edge", "weight": 10,
		"desc": "Your sidearm hits 35% harder.",
		"mods": {"weapon_damage": 1.35}, "procs": []},
	{"id": "heavy_shells", "name": "Heavy Shells", "weight": 10,
		"desc": "Your ship's guns hit 35% harder.",
		"mods": {"turret_damage": 1.35}, "procs": []},
	{"id": "quick_hands", "name": "Quick Hands", "weight": 8,
		"desc": "Your sidearm fires 25% faster.",
		"mods": {"fire_rate": 0.80}, "procs": []},
	{"id": "field_medic", "name": "Field Medic", "weight": 7,
		"desc": "Your repair station mends 60% faster.",
		"mods": {"hull_repair": 1.60}, "procs": []},
	{"id": "vampiric_rounds", "name": "Vampiric Rounds", "weight": 6,
		"desc": "Landing a hit heals you for 8% of the damage.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.08}]},
	{"id": "bounty_hunter", "name": "Bounty Hunter", "weight": 8,
		"desc": "Every kill drops 10 extra coins.",
		"mods": {}, "procs": [{"on": "kill", "effect": "coins", "amount": 10}]},
	{"id": "second_wind", "name": "Second Wind", "weight": 6,
		"desc": "Reaching a new depth heals you 40 HP.",
		"mods": {}, "procs": [{"on": "land", "effect": "heal", "amount": 40}]},
	{"id": "trimmed_sails", "name": "Trimmed Sails", "weight": 8,
		"desc": "Your ship's propellers push 30% harder.",
		"mods": {"thrust": 1.30}, "procs": []},
]

## The events a proc may hook, and the effects the world knows how to apply. A card
## naming anything outside these is a bug the suite catches — the world's
## interpreter is deliberately a closed set.
const EVENTS := ["kill", "hit", "land", "attack", "hurt"]
const EFFECTS := ["coins", "heal", "lifesteal"]
## Dial keys a `mods` entry may name (mirrors the world's `_dive_mod` call sites).
const DIALS := ["weapon_damage", "turret_damage", "fire_rate", "hull_repair",
	"thrust", "grapple", "ride"]


## THE CARD CODEX — the whole deck as a page for the title's WORKSHOP (owner
## 2026-08-31: "the workshop should have a card viewer perhaps as with
## bestiary"). Unlike the bestiary there is nothing to hide: the deck is the
## run's toolbox, and knowing it is strategy, not a spoiler.
static func codex_text() -> String:
	var lines: Array = [
		"",
		"  T H E   C A R D S  ",
		"",
		"  %d cards. A draft of three at the start line;" % CATALOG.size(),
		"  after that, only kills fill the bar.  ",
		"",
	]
	for c in CATALOG:
		var cd := c as Dictionary
		lines.append("  %s" % String(cd["name"]))
		lines.append("      %s" % String(cd["desc"]))
	lines.append("")
	return "\n".join(lines)


static func by_id(id: String) -> Dictionary:
	for c in CATALOG:
		if String((c as Dictionary)["id"]) == id:
			return c as Dictionary
	return {}


static func is_known(id: String) -> bool:
	return not by_id(id).is_empty()


static func name_of(id: String) -> String:
	var c := by_id(id)
	return String(c.get("name", id)) if not c.is_empty() else id


static func desc_of(id: String) -> String:
	return String(by_id(id).get("desc", ""))


## The combined multiplier a set of held card ids applies to dial `key` — the
## PRODUCT of every held card's `mods[key]` (1.0 when none touch it). Product, not
## sum, so two +35% damage cards stack multiplicatively (1.35² ≈ +82%), which keeps
## a lucky double from being merely additive and dull.
static func modifier(held: Array, key: String) -> float:
	var m := 1.0
	for id in held:
		var mods: Dictionary = by_id(String(id)).get("mods", {})
		if mods.has(key):
			m *= float(mods[key])
	return m


## Every proc effect across the held cards that fires on `event`, as a flat list of
## {effect, amount}. The world walks this at each event site and applies each.
static func procs_for(held: Array, event: String) -> Array:
	var out: Array = []
	for id in held:
		for p in (by_id(String(id)).get("procs", []) as Array):
			if String((p as Dictionary).get("on", "")) == event:
				out.append(p)
	return out


## Draw up to `n` DISTINCT card ids for a draft, excluding ones already `held`,
## weighted by each card's `weight`. Fewer than `n` are returned when the deck is
## nearly exhausted; an empty array means every card is already held (the world
## then simply drains the pending draft — no empty picker). `rng` is passed in so
## the caller owns determinism, exactly like the whale pod pick.
static func draw_choices(rng: RandomNumberGenerator, held: Array, n: int) -> Array:
	var pool: Array = []
	for c in CATALOG:
		var id := String((c as Dictionary)["id"])
		if not held.has(id):
			pool.append(c)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var total := 0
		for c in pool:
			total += int((c as Dictionary).get("weight", 1))
		var roll := rng.randi_range(0, maxi(total - 1, 0))
		var acc := 0
		var picked := 0
		for i in pool.size():
			acc += int((pool[i] as Dictionary).get("weight", 1))
			if roll < acc:
				picked = i
				break
		out.append(String((pool[picked] as Dictionary)["id"]))
		pool.remove_at(picked)
	return out
