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
##     end_dive), "move_speed" (your legs — `Player.run_speed_mult`, stamped the
##     same way). STAGED (model supports, world not yet): "grapple", "ride".
##   procs: [{on, effect, amount}]           — fired when the world emits `on`
##     events wired today: "kill" (a creature died to you), "hit" (your shot landed
##     on an enemy), "land" (you reached a new depth). STAGED: "attack", "hurt".
##     effects wired today: "coins" (+amount to the pot), "heal" (+amount HP to the
##     player), "lifesteal" (heal amount× the damage dealt), "explode" (the hit
##     detonates: amount× the damage dealt again to every enemy within
##     BLAST_RADIUS_PX × world_scale of the struck hull).
##
## RARITY (owner 2026-09-01: "white -> normal & common, green or blue ->
## rarer/better, purple -> spicy epic, orange -> legendary for extra spicy
## things"). Rarity is DATA on the row and it does exactly two jobs: it multiplies
## the draw weight (RARITY_WEIGHT — a common is offered ~33× as often as a
## legendary before the card's own `weight` biases within its tier), and it colours
## the card in the picker and the codex (RARITY_COLOR). Nothing else in the game
## branches on it, so re-tiering a card is a one-word edit.
##
## THE DECK STAYS SMALL (owner: "I don't want a bazillion cards", "they have to be
## meaningful"). Under twenty rows, and every one of them either changes a number
## you can feel in the first ten seconds or writes a build around a SYNERGY that
## already exists in the vocabulary:
##   * fire_rate × explode — more trigger pulls, more blasts (Cluster Shells wants
##     Quick Hands / Hair Trigger / Blood Engine).
##   * fire_rate × lifesteal — Sanguine Tide turns a fast gun into a health bar.
##   * coins × the XP curve — coins ARE xp (DiveRun.credit_kill), so Pickpocket and
##     King's Ransom do not merely pay, they DRAW MORE CARDS.
##   * move_speed × going shipless — the run is legal without a hull, and legs are
##     the only engine a shipless run has (Light Boots, Sea Legs).

## Rarity tiers, weakest first. Display order in the codex, too.
const RARITIES := ["common", "uncommon", "epic", "legendary"]

## How much a tier multiplies a card's own `weight` in the draw. Commons dominate
## the offer; a legendary is a run you will remember. The card's `weight` still
## biases WITHIN a tier, which is why this is a multiplier and not a replacement.
const RARITY_WEIGHT := {"common": 100, "uncommon": 40, "epic": 12, "legendary": 3}

## The owner's colour language, straight across: white/ink, blue, purple, orange.
const RARITY_COLOR := {
	"common": Color(0.88, 0.92, 1.00),
	"uncommon": Color(0.42, 0.68, 0.98),
	"epic": Color(0.74, 0.48, 0.99),
	"legendary": Color(0.99, 0.62, 0.22),
}

## What a tier is CALLED on screen.
const RARITY_LABEL := {
	"common": "COMMON", "uncommon": "UNCOMMON",
	"epic": "EPIC", "legendary": "LEGENDARY",
}

## THE BLAST's radius in px at scale 1 — the world multiplies by `world_scale`, so
## it is ~1,760 px at the shipped 8×, a bit under half a screen height at the
## shipped zoom. Big enough that a cluster of pickets goes up together (which is
## the whole fantasy), small enough that you have to aim into the crowd.
const BLAST_RADIUS_PX := 220.0

## The deck. Order is display order within the draft. Keep procs' effect/amount in
## the closed vocabulary above and the rarity in RARITIES, or the world silently
## ignores them and `_test_dive_cards` reddens on the parity check.
const CATALOG := [
	# --- COMMON (white) — the plain multipliers. The spine of a run's curve ---
	{"id": "honed_edge", "name": "Honed Edge", "rarity": "common", "weight": 10,
		"desc": "Your sidearm hits 35% harder.",
		"mods": {"weapon_damage": 1.35}, "procs": []},
	{"id": "heavy_shells", "name": "Heavy Shells", "rarity": "common", "weight": 10,
		"desc": "Your ship's guns hit 35% harder.",
		"mods": {"turret_damage": 1.35}, "procs": []},
	{"id": "quick_hands", "name": "Quick Hands", "rarity": "common", "weight": 8,
		"desc": "Your sidearm fires 25% faster.",
		"mods": {"fire_rate": 0.80}, "procs": []},
	{"id": "field_medic", "name": "Field Medic", "rarity": "common", "weight": 7,
		"desc": "Your repair station mends 60% faster.",
		"mods": {"hull_repair": 1.60}, "procs": []},
	{"id": "trimmed_sails", "name": "Trimmed Sails", "rarity": "common", "weight": 8,
		"desc": "Your ship's propellers push 30% harder.",
		"mods": {"thrust": 1.30}, "procs": []},
	# The owner's own ask, verbatim: "+10% player move speed".
	{"id": "light_boots", "name": "Light Boots", "rarity": "common", "weight": 9,
		"desc": "You run 10% faster on foot.",
		"mods": {"move_speed": 1.10}, "procs": []},
	{"id": "bounty_hunter", "name": "Bounty Hunter", "rarity": "common", "weight": 8,
		"desc": "Every kill drops 10 extra coins.",
		"mods": {}, "procs": [{"on": "kill", "effect": "coins", "amount": 10}]},
	# Small, but coins are XP — so this quietly draws you more cards, which is the
	# cheapest synergy in the deck and the one that teaches the rule.
	{"id": "pickpocket", "name": "Pickpocket", "rarity": "common", "weight": 7,
		"desc": "Every hit shakes 3 coins loose. Coins are experience.",
		"mods": {}, "procs": [{"on": "hit", "effect": "coins", "amount": 3}]},

	# --- UNCOMMON (blue) — stronger, or two systems at once ------------------
	{"id": "vampiric_rounds", "name": "Vampiric Rounds", "rarity": "uncommon", "weight": 8,
		"desc": "Landing a hit heals you for 8% of the damage.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.08}]},
	{"id": "second_wind", "name": "Second Wind", "rarity": "uncommon", "weight": 7,
		"desc": "Reaching a new depth heals you 40 HP.",
		"mods": {}, "procs": [{"on": "land", "effect": "heal", "amount": 40}]},
	{"id": "hair_trigger", "name": "Hair Trigger", "rarity": "uncommon", "weight": 7,
		"desc": "Your sidearm fires 32% faster.",
		"mods": {"fire_rate": 0.68}, "procs": []},
	{"id": "field_surgeon", "name": "Field Surgeon", "rarity": "uncommon", "weight": 7,
		"desc": "Every kill mends you 25 HP.",
		"mods": {}, "procs": [{"on": "kill", "effect": "heal", "amount": 25}]},
	{"id": "sea_legs", "name": "Sea Legs", "rarity": "uncommon", "weight": 6,
		"desc": "You run 25% faster and your propellers push 15% harder.",
		"mods": {"move_speed": 1.25, "thrust": 1.15}, "procs": []},

	# --- EPIC (purple) — build-defining. Pure upside, bigger numbers ----------
	{"id": "full_sail", "name": "Full Sail", "rarity": "epic", "weight": 8,
		"desc": "Your propellers push 75% harder.",
		"mods": {"thrust": 1.75}, "procs": []},
	{"id": "broadside", "name": "Broadside", "rarity": "epic", "weight": 7,
		"desc": "Ship guns hit 90% harder; your sidearm 40% harder.",
		"mods": {"turret_damage": 1.90, "weapon_damage": 1.40}, "procs": []},
	{"id": "blood_engine", "name": "Blood Engine", "rarity": "epic", "weight": 6,
		"desc": "Fire 15% faster, and every hit heals you 20% of the damage.",
		"mods": {"fire_rate": 0.85},
		"procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.20}]},

	# --- LEGENDARY (orange) — the run you tell someone about -----------------
	{"id": "cluster_shells", "name": "Cluster Shells", "rarity": "legendary", "weight": 8,
		"desc": "Every hit detonates — 60% of the damage again to everything around it.",
		"mods": {}, "procs": [{"on": "hit", "effect": "explode", "amount": 0.60}]},
	{"id": "kings_ransom", "name": "King's Ransom", "rarity": "legendary", "weight": 6,
		"desc": "Kills drop 120 coins, hits shake 12 loose — and coins are experience.",
		"mods": {}, "procs": [
			{"on": "kill", "effect": "coins", "amount": 120},
			{"on": "hit", "effect": "coins", "amount": 12}]},
	{"id": "sanguine_tide", "name": "Sanguine Tide", "rarity": "legendary", "weight": 5,
		"desc": "Every hit heals you 45% of the damage dealt.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.45}]},
]

## The events a proc may hook, and the effects the world knows how to apply. A card
## naming anything outside these is a bug the suite catches — the world's
## interpreter is deliberately a closed set.
const EVENTS := ["kill", "hit", "land", "attack", "hurt"]
const EFFECTS := ["coins", "heal", "lifesteal", "explode"]
## Dial keys a `mods` entry may name (mirrors the world's `_dive_mod` call sites).
const DIALS := ["weapon_damage", "turret_damage", "fire_rate", "hull_repair",
	"thrust", "move_speed", "grapple", "ride"]


## The tier a card sits in (defaults to common, so an un-tiered row is still legal
## data — the suite is what insists every shipped row names one).
static func rarity_of(id: String) -> String:
	return String(by_id(id).get("rarity", "common"))


## A tier's colour, and a card's. One place, so the picker and the codex cannot
## drift apart.
static func rarity_color(rarity: String) -> Color:
	return RARITY_COLOR.get(rarity, RARITY_COLOR["common"])


static func color_of(id: String) -> Color:
	return rarity_color(rarity_of(id))


static func rarity_label(rarity: String) -> String:
	return String(RARITY_LABEL.get(rarity, rarity.to_upper()))


## What a card actually weighs in the draw: its own bias times its tier's. Never
## below 1, so a legendary is rare and not impossible.
static func draw_weight(card: Dictionary) -> int:
	var tier := String(card.get("rarity", "common"))
	var mult := int(RARITY_WEIGHT.get(tier, RARITY_WEIGHT["common"]))
	return maxi(1, int(card.get("weight", 1)) * mult)


# --- THE BLAST (the "explode" effect) ---------------------------------------
#
# Pure geometry, kept here rather than in the world, because the world cannot be
# named in a test (its `Net` autoload poisons the compile graph — see DiveRun's
# DESCENT_BLEED comment). The world's job is only to turn its live Ships into
# rows and hand the caught ones to the damage plumbing it already has.

## How far `p` lies from rectangle `r` — 0 when the rectangle contains it. Used
## against a hull's `solid_bounds` IN THE SHIP'S OWN FRAME, so a long vessel is
## caught by its nearest plating rather than by wherever its origin happens to
## sit, and the test works at any rotation for free.
static func rect_distance(r: Rect2, p: Vector2) -> float:
	var nearest := Vector2(
		clampf(p.x, r.position.x, r.end.x),
		clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(nearest)


## Which candidate bodies a blast catches, as INDICES into `rows`. Each row is
## {"dist": px from the blast centre (rect_distance), "hostile": bool}. Flat, not
## falling off: the owner asked for "amount × the damage dealt to ALL enemies
## within a radius", and a taper would make the card's number a lie at the rim.
## The struck body is a row like any other, which is how it takes its own blast.
static func blast_catches(rows: Array, radius: float) -> Array:
	var out: Array = []
	for i in rows.size():
		var row := rows[i] as Dictionary
		if not bool(row.get("hostile", false)):
			continue
		if float(row.get("dist", INF)) <= radius:
			out.append(i)
	return out


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
		"  Rarer is rarer: a legendary is offered about once",
		"  for every thirty commons.",
		"",
	]
	# Grouped by tier, weakest first — the same order (and the same names) the
	# picker paints, so the page reads as the deck's own ladder. ONE LINE PER
	# CARD: the title panel is a plain VBox with no scroll, and at two lines a
	# nineteen-card deck runs off the bottom of a 720p window.
	for tier in RARITIES:
		var tier_cards: Array = []
		for c in CATALOG:
			if String((c as Dictionary).get("rarity", "common")) == tier:
				tier_cards.append(c)
		if tier_cards.is_empty():
			continue
		lines.append("  --- %s ---" % rarity_label(String(tier)))
		for c in tier_cards:
			var cd := c as Dictionary
			lines.append("  %s — %s" % [String(cd["name"]), String(cd["desc"])])
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
## weighted by each card's `draw_weight` (its own bias × its RARITY tier's — so a
## common shows up far more often than a legendary, and a heavy common still beats
## a light one). Fewer than `n` are returned when the deck is
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
			total += draw_weight(c as Dictionary)
		var roll := rng.randi_range(0, maxi(total - 1, 0))
		var acc := 0
		var picked := 0
		for i in pool.size():
			acc += draw_weight(pool[i] as Dictionary)
			if roll < acc:
				picked = i
				break
		out.append(String((pool[picked] as Dictionary)["id"]))
		pool.remove_at(picked)
	return out
