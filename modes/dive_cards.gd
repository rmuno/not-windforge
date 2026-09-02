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
##     same way), "grapple_range" / "grapple_speed" (`Player.hook_range_mult` /
##     `hook_speed_mult`, stamped the same way), "fall_damage_taken" (the bill for
##     a landing — <1 is SOFTER; `Player.fall_damage_mult`).
##     STAGED (model supports, world not yet): "grapple", "ride".
##   adds:  {dial_key: amount}               — ADDED to an existing number
##     A second, deliberately tiny channel (v0.134.0). Some numbers are not
##     sensibly a percentage: the owner asked for "+25 max HP (flat)", and a
##     multiplier on a pool that GRIT already scales would mean a different card
##     for every character. Multipliers stay the default — `adds` exists for the
##     handful of dials where a flat number is what the card actually promises.
##     dials wired today: "max_hp" (`Player.bonus_max_health`; taking the card
##     HEALS the difference, so +25 max at 40/100 reads 65/125).
##   flags: ["flag_name"]                    — a RULE turned on, not a number moved
##     The third channel, and the smallest (v0.134.0). Some cards do not scale
##     anything: they lift a restriction or arm a one-shot. A flag is held or it
##     is not, and the world asks `_dive_flag("x")`.
##     flags wired today: "grapple_free_fire" (the hook is fired from your own
##     moving frame, so it works at full reach even in free fall — see
##     `Player.hook_step`), "second_heart" (the first lethal blow of a run leaves
##     you at 1 HP instead; the run model spends it once — `DiveRun.spend_second_heart`).
##   procs: [{on, effect, amount}]           — fired when the world emits `on`
##     events wired today: "kill" (a creature died to you), "hit" (your shot landed
##     on an enemy), "land" (you reached a new depth). STAGED: "attack", "hurt".
##     effects wired today: "coins" (+amount to the pot), "heal" (+amount HP to the
##     player), "lifesteal" (heal amount× the damage dealt), "explode" (the hit
##     detonates: amount× the damage dealt again to every enemy within
##     BLAST_RADIUS_PX × world_scale of the struck hull), "ricochet" (the hit
##     BOUNCES to the nearest OTHER enemy within RICOCHET_RADIUS_PX × world_scale
##     for amount× the damage), "chain" (the bounce keeps going, CHAIN_HOPS more
##     times at amount× the damage each).
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
## meaningful"). Under thirty rows, and every one of them either changes a number
## you can feel in the first ten seconds or writes a build around a SYNERGY that
## already exists in the vocabulary:
##   * fire_rate × explode — more trigger pulls, more blasts (Cluster Shells wants
##     Quick Hands / Hair Trigger / Blood Engine).
##   * fire_rate × lifesteal — Sanguine Tide turns a fast gun into a health bar.
##   * coins × the outpost counter — Pickpocket and King's Ransom buy the Aether
##     Lung and the hull patches sooner, and the pot is the only money a landing
##     spends. (They no longer draw CARDS: since v0.137.0 XP is SCRAP, a physical
##     drop swept off a corpse rather than a share of the coins — the two channels
##     are separate now, see DiveRun.credit_kill.)
##   * move_speed × going shipless — the run is legal without a hull, and legs are
##     the only engine a shipless run has (Light Boots, Sea Legs).
##   * ricochet × lifesteal/explode — a BOUNCE IS A REAL HIT (world._dive_ricochet
##     re-fires the hit event on it), so Ricochet Rounds turns one trigger pull
##     into two Sanguine Tide heals or two Cluster Shells detonations. Deliberate;
##     the loop guard is that a bounce never bounces again.
##   * max_hp × fall_damage_taken × grapple — the SURVIVAL build the deck was
##     missing. Fall damage is charged on the speed you ACTUALLY LAND AT, so a
##     grapple that works while you are falling (Harpooneer's Arm) is already the
##     game's own answer to a long drop; Thick Skin pays the rest of the bill.

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

## THE BOUNCE's reach in px at scale 1 — the same unit as BLAST_RADIUS_PX, so the
## world multiplies by `world_scale` and it is ~2,240 px at the shipped 8×.
## DELIBERATELY WIDER THAN THE BLAST: a blast is an area you aim INTO (it wants a
## crowd), while a bounce is a line the shell finds for you and has to read as
## generous or the card looks broken every time the second gunboat is one hull
## length too far. Still well under a screen, so "the nearest OTHER enemy" is
## somebody you can see when it happens.
const RICOCHET_RADIUS_PX := 280.0

## How many EXTRA hops the "chain" effect adds after the first bounce. Two, so a
## chained shot touches four bodies in all (struck + bounce + 2) — enough to read
## as lightning, few enough that a surge does not resolve in one trigger pull.
const CHAIN_HOPS := 2

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
		"desc": "Your propellers push 30% harder.",
		"mods": {"thrust": 1.30}, "procs": []},
	# The owner's own ask, verbatim: "+10% player move speed".
	{"id": "light_boots", "name": "Light Boots", "rarity": "common", "weight": 9,
		"desc": "You run 10% faster.",
		"mods": {"move_speed": 1.10}, "procs": []},
	{"id": "bounty_hunter", "name": "Bounty Hunter", "rarity": "common", "weight": 8,
		"desc": "Kills drop 10 extra coins.",
		"mods": {}, "procs": [{"on": "kill", "effect": "coins", "amount": 10}]},
	# Small, but coins are XP — so this quietly draws you more cards, which is the
	# cheapest synergy in the deck and the one that teaches the rule.
	{"id": "pickpocket", "name": "Pickpocket", "rarity": "common", "weight": 7,
		"desc": "Hits shake 3 coins loose.",
		"mods": {}, "procs": [{"on": "hit", "effect": "coins", "amount": 3}]},

	# The `adds` channel's first row, and the reason it exists: the owner asked
	# for "+25 max HP (flat, not %)". Taking it MENDS the difference on the spot —
	# a card that raises your ceiling and leaves you as hurt as you were would read
	# as a downgrade in the middle of a fight.
	{"id": "iron_constitution", "name": "Iron Ribs", "rarity": "common", "weight": 9,
		"desc": "+25 max health, mended on the spot.",
		"mods": {}, "adds": {"max_hp": 25.0}, "procs": []},
	# ONE CARD, BOTH NUMBERS (owner: "grapple range should probably also have hook
	# speed attached to it"). Range on its own is a hook that takes longer to reach
	# the same wall — a nerf wearing a buff.
	{"id": "long_line", "name": "Long Line", "rarity": "common", "weight": 8,
		"desc": "Your grapple reaches 40% further and flies 40% faster.",
		"mods": {"grapple_range": 1.40, "grapple_speed": 1.40}, "procs": []},

	# --- UNCOMMON (blue) — stronger, or two systems at once ------------------
	{"id": "vampiric_rounds", "name": "Leech Line", "rarity": "uncommon", "weight": 8,
		"desc": "Hits heal you 8% of the damage.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.08}]},
	{"id": "second_wind", "name": "Second Wind", "rarity": "uncommon", "weight": 7,
		"desc": "Reaching a new depth heals you 40 health.",
		"mods": {}, "procs": [{"on": "land", "effect": "heal", "amount": 40}]},
	{"id": "hair_trigger", "name": "Hair Trigger", "rarity": "uncommon", "weight": 7,
		"desc": "Your sidearm fires 32% faster.",
		"mods": {"fire_rate": 0.68}, "procs": []},
	{"id": "field_surgeon", "name": "Field Surgeon", "rarity": "uncommon", "weight": 7,
		"desc": "Kills mend you 25 health.",
		"mods": {}, "procs": [{"on": "kill", "effect": "heal", "amount": 25}]},
	{"id": "sea_legs", "name": "Sea Legs", "rarity": "uncommon", "weight": 6,
		"desc": "You run 25% faster; your propellers push 15% harder.",
		"mods": {"move_speed": 1.25, "thrust": 1.15}, "procs": []},

	# THE RESTRICTION, LIFTED. The hook is a world-space projectile that does NOT
	# inherit your velocity, and HOOK_SPEED (900) is exactly MAX_FALL (900) — so a
	# body at terminal velocity firing straight down separates from its own hook at
	# 0 px/s and the line simply hangs at your boots. This card fires the hook from
	# YOUR frame instead (Player.hook_step's `carry`), so it separates at full speed
	# in every direction whatever you are doing. See `Player.hook_separation_speed`.
	{"id": "harpooneers_arm", "name": "Harpooneer's Arm", "rarity": "uncommon", "weight": 7,
		"desc": "Your grapple fires at full strength in any direction, even falling.",
		"mods": {}, "flags": ["grapple_free_fire"], "procs": []},
	# Both channels on one row, which is the point of it: a flat pool and a
	# multiplier on what the ground charges you.
	{"id": "thick_skin", "name": "Thick Skin", "rarity": "uncommon", "weight": 6,
		"desc": "+50 max health; landings hurt 15% less.",
		"mods": {"fall_damage_taken": 0.85}, "adds": {"max_hp": 50.0}, "procs": []},

	# --- EPIC (purple) — build-defining. Pure upside, bigger numbers ----------
	{"id": "full_sail", "name": "Full Sail", "rarity": "epic", "weight": 8,
		"desc": "Your propellers push 75% harder.",
		"mods": {"thrust": 1.75}, "procs": []},
	{"id": "broadside", "name": "Broadside", "rarity": "epic", "weight": 7,
		"desc": "Your ship's guns hit 90% harder; your sidearm 40%.",
		"mods": {"turret_damage": 1.90, "weapon_damage": 1.40}, "procs": []},
	{"id": "blood_engine", "name": "Hungry Engine", "rarity": "epic", "weight": 6,
		"desc": "You fire 15% faster; hits heal you 20% of the damage.",
		"mods": {"fire_rate": 0.85},
		"procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.20}]},

	# A BOUNCE IS A REAL HIT. The world re-fires the whole hit event on the bounced
	# target, so lifesteal and Cluster Shells both chain off it — deliberate, and
	# the reason this is an epic rather than an uncommon. The loop guard is one
	# rule: a ricochet never ricochets (world._dive_in_ricochet).
	{"id": "ricochet_rounds", "name": "Ricochet Rounds", "rarity": "epic", "weight": 6,
		"desc": "Shots bounce to the nearest other enemy for 50% of the damage.",
		"mods": {}, "procs": [{"on": "hit", "effect": "ricochet", "amount": 0.50}]},

	# --- LEGENDARY (orange) — the run you tell someone about -----------------
	{"id": "cluster_shells", "name": "Cluster Shells", "rarity": "legendary", "weight": 8,
		"desc": "Hits detonate: 60% of the damage again to everything nearby.",
		"mods": {}, "procs": [{"on": "hit", "effect": "explode", "amount": 0.60}]},
	{"id": "kings_ransom", "name": "Prize Money", "rarity": "legendary", "weight": 6,
		"desc": "Kills drop 120 extra coins; hits shake 12 loose.",
		"mods": {}, "procs": [
			{"on": "kill", "effect": "coins", "amount": 120},
			{"on": "hit", "effect": "coins", "amount": 12}]},
	{"id": "sanguine_tide", "name": "Leech Rig", "rarity": "legendary", "weight": 5,
		"desc": "Hits heal you 45% of the damage.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.45}]},
	# IT CARRIES ITS OWN FIRST BOUNCE (design call, v0.134.0). A legendary that
	# does nothing unless you already drew a particular epic is a legendary that
	# reads as a dud two runs out of three, so this row carries BOTH procs and is a
	# complete card on its own. Holding Ricochet Rounds too is not double-dipping:
	# the world takes the MAX of the ricochet amounts and fires ONE sequence
	# (world._dive_apply_procs), so the pair is an upgrade, never two bounces.
	{"id": "chain_lightning", "name": "Skip Shot", "rarity": "legendary", "weight": 5,
		"desc": "Shots bounce for 50%, then twice more for 35% each.",
		"mods": {}, "procs": [
			{"on": "hit", "effect": "ricochet", "amount": 0.50},
			{"on": "hit", "effect": "chain", "amount": 0.35}]},
	# ONE LIFE, ONCE FORGIVEN. The run's one-life rule (DiveRun.perish_aboard) is
	# untouched — this card is spent BEFORE the death path is reached, so the
	# second lethal blow of a run still ends it. Run-scoped state, like everything
	# else a card does: it does not survive `end_dive`.
	{"id": "second_heart", "name": "Second Heart", "rarity": "legendary", "weight": 4,
		"desc": "The first killing blow each run leaves you at 1 health instead.",
		"mods": {}, "flags": ["second_heart"], "procs": []},
]

## The events a proc may hook, and the effects the world knows how to apply. A card
## naming anything outside these is a bug the suite catches — the world's
## interpreter is deliberately a closed set.
const EVENTS := ["kill", "hit", "land", "attack", "hurt"]
const EFFECTS := ["coins", "heal", "lifesteal", "explode", "ricochet", "chain"]
## Dial keys a `mods` entry may name (mirrors the world's `_dive_mod` call sites).
const DIALS := ["weapon_damage", "turret_damage", "fire_rate", "hull_repair",
	"thrust", "move_speed", "grapple_range", "grapple_speed", "fall_damage_taken",
	"grapple", "ride"]
## Dial keys an `adds` entry may name (the world's `_dive_add` call sites). A
## separate list, not a corner of DIALS, because the two channels compose
## differently — a missing multiplier is 1.0 and a missing addend is 0.0, and a
## key in the wrong one would silently do nothing at all.
const ADDS := ["max_hp"]
## Rule switches a `flags` entry may name (the world's `_dive_flag` call sites).
const FLAGS := ["grapple_free_fire", "second_heart"]


## The whole deck's size — the denominator of "N of M taken" in the gallery.
static func total() -> int:
	return CATALOG.size()


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


# --- THE BOUNCE (the "ricochet" / "chain" effects) --------------------------
#
# The blast's twin, and deliberately the SAME row shape ({dist, hostile}) so the
# world builds its candidate list once and both effects read it. Where a blast
# catches EVERY hostile in a radius, a bounce picks exactly ONE — the nearest
# that has not been hit yet — which is what makes it read as a shell finding its
# way rather than as a smaller explosion.

## The NEAREST hostile row within `radius`, ignoring every index in `taken`
## (the bodies this bounce sequence has already struck — the struck hull first
## of all, or the shell would simply bounce back into what it just hit). -1 when
## nothing qualifies, which is how the world knows a chain has run out of sky.
##
## Ties go to the lower index. Arbitrary, but DETERMINISTIC, which is what a test
## needs and what stops two identical shots resolving differently.
static func nearest_catch(rows: Array, radius: float, taken: Array) -> int:
	var best := -1
	var best_d := INF
	for i in rows.size():
		var row := rows[i] as Dictionary
		if not bool(row.get("hostile", false)) or taken.has(i):
			continue
		var d := float(row.get("dist", INF))
		if d <= radius and d < best_d:
			best_d = d
			best = i
	return best


## How much damage each step of a bounce sequence deals, given the ORIGINAL hit's
## `damage`, the first-bounce fraction and the per-chain-hop fraction. Empty when
## nothing bounces; one entry with no chain; 1 + CHAIN_HOPS entries with one.
##
## Pure so the card's arithmetic — "50%, then 35% each" — is pinned without a
## ship, and so the world's loop has nothing to get wrong but the geometry.
static func bounce_damages(damage: float, first: float, chain: float) -> Array:
	var out: Array = []
	if damage <= 0.0 or first <= 0.0:
		return out
	out.append(damage * first)
	if chain > 0.0:
		for _hop in CHAIN_HOPS:
			out.append(damage * chain)
	return out


# --- THE CARD LOG (an instance) --------------------------------------------
#
# WHICH CARDS YOU HAVE EVER TAKEN, across every run and every save (owner
# 2026-09-01: "the card screen from the title should display the individual known
# cards based on what the user has selected"). The exact shape CreatureLog uses
# for creatures — catalog statics above, a discovered set and its dict codec
# here, and the page model below — so `save/profile.gd` stores the two logs the
# same way and the title reads them the same way.
#
# It lives HERE rather than in a new file for the same reason the bestiary's set
# lives in CreatureLog: the set is meaningless without the catalog that defines
# which ids are real, and one file means an id can never be spelled two ways.
#
# Held cards inside a live run stay `DiveRun.held` (they burn with the run). This
# is the META record, and the only thing that writes it is the world's take site.

## Taken card ids, as a set (id -> true). A Dictionary so `has`/`mark` are O(1)
## and it JSON round-trips straight into the profile.
var taken := {}


## Record that card `id` has been taken. True only on a genuinely NEW card that
## is really in the catalog — the signal the world uses to persist. An unknown id
## (a card since cut from the deck) is dropped rather than stored.
func mark(id: String) -> bool:
	if id == "" or not is_known(id) or taken.has(id):
		return false
	taken[id] = true
	return true


func has(id: String) -> bool:
	return taken.has(id)


## How many DISTINCT catalog cards have been taken — counted against the CATALOG,
## so a stale id from an older deck cannot inflate the gallery's header.
func count() -> int:
	var n := 0
	for c in CATALOG:
		if taken.has(String((c as Dictionary)["id"])):
			n += 1
	return n


## The set as a JSON-safe dict {id: true}. Only ids still in the deck are written,
## so a retired card is quietly cleaned out on the next save.
func to_dict() -> Dictionary:
	var out := {}
	for c in CATALOG:
		var id := String((c as Dictionary)["id"])
		if taken.has(id):
			out[id] = true
	return out


static func from_dict(data: Dictionary) -> DiveCards:
	var log := DiveCards.new()
	for key in data.keys():
		var id := String(key)
		if is_known(id) and bool(data[key]):
			log.taken[id] = true
	return log


# --- THE GALLERY MODEL (pure; the title's CARDS page paints these rows) ------

## The whole deck as PLAIN ROWS for the card gallery, grouped in tier order
## (common → legendary), each {id, name, desc, rarity, rarity_label, color,
## taken}. World-decides/layer-paints: the panel never asks the catalog anything,
## it just builds one tile per row and dims the ones with `taken` false.
##
## EVERY card is a row, taken or not. The deck is strategy, not a spoiler (the
## codex's own doctrine, unchanged since it was a wall of text) — so an untaken
## card still shows its name and what it does; it is simply dimmed, which is what
## makes the gallery read as progress rather than as a locked grid.
static func gallery_rows(taken_set: Dictionary) -> Array:
	var out: Array = []
	for tier in RARITIES:
		for c in CATALOG:
			var cd := c as Dictionary
			if String(cd.get("rarity", "common")) != tier:
				continue
			out.append({
				"id": String(cd["id"]),
				"name": String(cd["name"]),
				"desc": String(cd.get("desc", "")),
				"rarity": String(tier),
				"rarity_label": rarity_label(String(tier)),
				"color": rarity_color(String(tier)),
				"taken": taken_set.has(String(cd["id"])),
			})
	return out


## How many of the deck a set has taken — counted against the CATALOG (a stale id
## does not count), so the gallery's "N of M" is always honest.
static func taken_count(taken_set: Dictionary) -> int:
	var n := 0
	for c in CATALOG:
		if taken_set.has(String((c as Dictionary)["id"])):
			n += 1
	return n


## THE CARD CODEX — the whole deck as one block of text. The title's CARDS page
## paints TILES now (gallery_rows above, owner 2026-09-01: "I'd like to see them
## as cards not as a wall of text"), but this stays: it is the cheapest complete
## assertion that every shipped row has a name, a description and a tier, and the
## suite reads it as exactly that.
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


## The combined ADDEND a set of held card ids applies to dial `key` — the SUM of
## every held card's `adds[key]` (0.0 when none touch it). Sum, not product, and
## that is the whole reason this channel is separate: two +25 HP cards must be
## +50 HP, and a flat number folded into a multiplier vocabulary would either
## compound absurdly or need a special case at every read site.
static func addend(held: Array, key: String) -> float:
	var a := 0.0
	for id in held:
		var adds: Dictionary = by_id(String(id)).get("adds", {})
		if adds.has(key):
			a += float(adds[key])
	return a


## Does any held card raise `flag`? A flag is a RULE, so holding it twice is the
## same as holding it once — which is why this is a bool and not a count.
static func has_flag(held: Array, flag: String) -> bool:
	for id in held:
		if (by_id(String(id)).get("flags", []) as Array).has(flag):
			return true
	return false


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
