class_name DiveCards
extends RefCounted

## THE DIVE'S CARD CATALOG (owner arc Q-L, 2026-08-31). A run-scoped upgrade draft:
## defeat things on the way down and you draw cards that make THIS run stronger —
## the roguelite power curve the Dive was missing between landings. Banked coins
## stay the META reward; cards are the in-run build, and they burn with the run.
##
## THE COHESION THE OWNER ASKED FOR ("lots of systems, little cohesion"): a card is
## not a new mechanic. It is EITHER a passive MULTIPLIER on a dial that already
## exists (damage, fire rate, thrust, mending) OR a PROC wired to an
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
##     dials wired today: "damage" (WHATEVER YOU ARE FIRING — the turret volley at
##     the helm, the sidearm on foot), "fire_rate" (the interval between trigger
##     pulls, at the helm AND on foot — <1 is FASTER), "hull_repair" (the Dive
##     assistant's mend rate), "thrust" (your hull's propeller force —
##     `Ship.thrust_mult`, stamped on the local ship each dive tick, reset by
##     end_dive), "dive_rate" (how fast the vertical stick takes you DOWN —
##     `Ship.dive_rate_mult`, stamped the same way), "fall_damage_taken" (the bill
##     for a hard arrival — <1 is SOFTER; `Player.fall_damage_mult` on foot AND
##     `Ship.impact_damage_mult` for the hull's collision crush).
##     STAGED (model supports, world not yet): "grapple", "ride".
##
##     v0.140.0 MERGED `weapon_damage` + `turret_damage` INTO `damage`, and gave
##     `fire_rate` the helm's volley cadence (review §4.2 item 1). A committed run
##     is flown from the helm, so a deck that only buffed the SIDEARM was buffing a
##     gun the run never fires: seventeen of twenty-six cards bought a resource the
##     helm does not spend. One dial, applied at whichever trigger your finger is
##     actually on, is the fix — and it deletes a whole card (Honed Edge was Heavy
##     Shells wearing the other dial's name).
##   adds:  {dial_key: amount}               — ADDED to an existing number
##     A second, deliberately tiny channel (v0.134.0). Some numbers are not
##     sensibly a percentage: the owner asked for "+25 max HP (flat)", and a
##     multiplier on a pool that GRIT already scales would mean a different card
##     for every character. Multipliers stay the default — `adds` exists for the
##     handful of dials where a flat number is what the card actually promises.
##     dials wired today: "max_hp" (`Player.bonus_max_health`; taking the card
##     HEALS the difference, so +25 max at 40/100 reads 65/125 — and, while you
##     are at the helm, HULL_PER_BODY_HP times that on the run's integrity pool).
##   flags: ["flag_name"]                    — a RULE turned on, not a number moved
##     The third channel, and the smallest (v0.134.0). Some cards do not scale
##     anything: they lift a restriction or arm a one-shot. A flag is held or it
##     is not, and the world asks `_dive_flag("x")`.
##     flags wired today: "second_heart" (the first lethal blow of a run leaves
##     you at 1 HP instead; the run model spends it once — `DiveRun.spend_second_heart`).
##   procs: [{on, effect, amount}]           — fired when the world emits `on`
##     events wired today: "kill" (a creature died to you), "hit" (your shot landed
##     on an enemy), "land" (you reached a new depth). STAGED: "attack", "hurt".
##     effects wired today: "coins" (+amount to the pot), "heal" (+amount HP to
##     WHAT YOU ARE — see HULL_PER_BODY_HP), "lifesteal" (mend amount× the damage
##     dealt into whatever you are — the pool at the helm, the body on foot),
##     "explode" (the hit detonates: amount× the damage dealt again to every
##     enemy within BLAST_RADIUS_PX × world_scale of the struck hull), "ricochet" (the hit
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
##     Quick Hands / Hair Trigger / Hungry Engine).
##   * fire_rate × lifesteal — Leech Rig turns a fast gun into the hull's own
##     repair crew.
##   * coins × the outpost counter — Pickpocket and Prize Money buy the Aether
##     Lung and the hull patches sooner, and the pot is the only money a landing
##     spends. (They no longer draw CARDS: since v0.137.0 XP is SCRAP, a physical
##     drop swept off a corpse rather than a share of the coins — the two channels
##     are separate now, see DiveRun.credit_kill.)
##   * ricochet × lifesteal/explode — a BOUNCE IS A REAL HIT (world._dive_ricochet
##     re-fires the hit event on it), so Ricochet Rounds turns one trigger pull
##     into two Sanguine Tide heals or two Cluster Shells detonations. Deliberate;
##     the loop guard is that a bounce never bounces again.
##   * max_hp × fall_damage_taken × lifesteal — the SURVIVAL build, pointed at the
##     thing that actually dies in a run: the HULL. Iron Ribs and Thick Skin widen
##     the integrity pool, the leech cards refill it out of the guns, and
##     fall_damage_taken discounts what a slab costs you on the way down.
##   * damage × dive_rate — Lead Keel buys the descent the ten-minute cap wants,
##     and the only thing that makes going fast survivable is killing fast.
##
## THE DECK POINTS AT THE HULL (v0.140.0, review §4.2). The deck was authored when
## the run's life was the player's three lives; v0.111.0 moved the run's life to
## the hull's integrity pool and the deck never followed, so a 45% lifesteal on a
## body at full health was a blank card. Now every heal-family effect lands on
## WHAT YOU ARE — the pool while you are at the helm, the body when you are not.

## Rarity tiers, weakest first. Display order in the codex, too.
const RARITIES := ["common", "uncommon", "epic", "legendary"]

## WHICH SYSTEM A CARD BUYS — a closed list, one word per row, painted as a chip
## on the picker (review §4.3: "say which system, first"). The player's real
## question at the draft is *"does this matter at the helm?"*, and colour already
## answers rarity, not that. Parity-tested exactly like DIALS: a row naming a
## system outside this set is a chip the picker cannot paint.
const SYSTEMS := ["guns", "hull", "flight", "pot"]

## HOW MANY POINTS OF THE RUN'S INTEGRITY POOL ONE BODY POINT IS WORTH.
##
## EVERY flat heal-family effect in this catalog is authored in BODY units (+25,
## +40, +50) and the world multiplies by this when the mend lands on the HULL
## instead — `world._dive_heal_player` for the heal procs, `Ship.grant_bonus_integrity`
## for the `max_hp` addend. Authored one way and converted at the sink, rather
## than two numbers per card: a row that had to state both would drift the moment
## either pool is retuned, and the description would be the thing that lied.
##
## WHY TEN AND NOT THIRTY. The two pools stand at 100 (the body) and 3,000
## (`dive_ship_integrity`), so PARITY would be thirty. Ten is deliberately a third
## of that: these numbers were tuned against a 100-point body, and at parity the
## four flat/heal cards would roughly TRIPLE a run's life between them. At ten,
## Iron Ribs is +8% of the pool where it is +25% of a body — a real card, not the
## run. The cards meant to carry a long descent are the leeches, which refill the
## pool out of the guns and so scale with how well you are actually fighting.
##
## NOT applied to lifesteal: a leech card's amount is a fraction of the DAMAGE
## dealt, and damage is already in the pool's own units (`Ship.damage_cell` drains
## integrity one-for-one by the structural hp it destroys). See
## `world._dive_lifesteal` for the dimensional argument.
const HULL_PER_BODY_HP := 10.0

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
## the closed vocabulary above, the rarity in RARITIES and the system in SYSTEMS,
## or the world silently ignores them and `_test_dive_cards` reddens on the
## parity check.
##
## HULL NUMBERS ARE SHOWN, BODY NUMBERS ARE AUTHORED. Every heal-family row below
## carries the BODY figure (`adds`/`amount`), and its `desc` states the HULL figure
## first — that is HULL_PER_BODY_HP times it, and it is the number that matters,
## because a committed run is flown from the helm and the hull is what dies there.
const CATALOG := [
	# --- COMMON (white) — the plain multipliers. The spine of a run's curve ---
	{"id": "heavy_shells", "name": "Heavy Shells", "rarity": "common",
		"system": "guns", "weight": 10,
		"desc": "Guns hit 35% harder.",
		"mods": {"damage": 1.35}, "procs": []},
	{"id": "quick_hands", "name": "Quick Hands", "rarity": "common",
		"system": "guns", "weight": 8,
		"desc": "Guns fire 25% faster.",
		"mods": {"fire_rate": 0.80}, "procs": []},
	{"id": "field_medic", "name": "Field Medic", "rarity": "common",
		"system": "hull", "weight": 7,
		"desc": "Repair station mends 60% faster.",
		"mods": {"hull_repair": 1.60}, "procs": []},
	{"id": "trimmed_sails", "name": "Trimmed Sails", "rarity": "common",
		"system": "flight", "weight": 8,
		"desc": "Thrust +30%.",
		"mods": {"thrust": 1.30}, "procs": []},
	{"id": "bounty_hunter", "name": "Bounty Hunter", "rarity": "common",
		"system": "pot", "weight": 8,
		"desc": "Every kill: +10 coins.",
		"mods": {}, "procs": [{"on": "kill", "effect": "coins", "amount": 10}]},
	{"id": "pickpocket", "name": "Pickpocket", "rarity": "common",
		"system": "pot", "weight": 7,
		"desc": "Every hit: +3 coins.",
		"mods": {}, "procs": [{"on": "hit", "effect": "coins", "amount": 3}]},

	# The `adds` channel's first row, and the reason it exists: the owner asked
	# for "+25 max HP (flat, not %)". Taking it MENDS the difference on the spot —
	# a card that raises your ceiling and leaves you as hurt as you were would read
	# as a downgrade in the middle of a fight. Since v0.140.0 the ceiling it raises
	# is the HULL's while you are at the helm (×10, HULL_PER_BODY_HP).
	{"id": "iron_constitution", "name": "Iron Ribs", "rarity": "common",
		"system": "hull", "weight": 9,
		"desc": "+250 hull (+25 on foot), mended on the spot.",
		"mods": {}, "adds": {"max_hp": 25.0}, "procs": []},

	# --- UNCOMMON (blue) — stronger, or two systems at once ------------------
	{"id": "vampiric_rounds", "name": "Leech Line", "rarity": "uncommon",
		"system": "hull", "weight": 8,
		"desc": "Hits mend 8% of the damage into the hull.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.08}]},
	{"id": "second_wind", "name": "Second Wind", "rarity": "uncommon",
		"system": "hull", "weight": 7,
		"desc": "New depth: +400 hull (+40 on foot).",
		"mods": {}, "procs": [{"on": "land", "effect": "heal", "amount": 40}]},
	{"id": "hair_trigger", "name": "Hair Trigger", "rarity": "uncommon",
		"system": "guns", "weight": 7,
		"desc": "Guns fire 32% faster.",
		"mods": {"fire_rate": 0.68}, "procs": []},
	{"id": "field_surgeon", "name": "Field Surgeon", "rarity": "uncommon",
		"system": "hull", "weight": 7,
		"desc": "Kill: +250 hull (+25 on foot).",
		"mods": {}, "procs": [{"on": "kill", "effect": "heal", "amount": 25}]},
	# Both channels on one row, which is the point of it: a flat pool and a
	# multiplier on what a hard arrival charges you. Since v0.140.0 the discount
	# covers the HULL's collision crush too (`Ship.impact_damage_mult`) — at the
	# helm, "a landing" is the hull hitting a slab, not your boots hitting a floor.
	{"id": "thick_skin", "name": "Thick Skin", "rarity": "uncommon",
		"system": "hull", "weight": 6,
		"desc": "+500 hull (+50 on foot); impacts and landings hurt 15% less.",
		"mods": {"fall_damage_taken": 0.85}, "adds": {"max_hp": 50.0}, "procs": []},
	# THE FLIGHT SLOT THE DECK WAS MISSING (review §4.4: thrust, a descent
	# control, a boost). Thrust cards buy the climb; nothing bought the DIVE, and
	# the run is on a clock — so the one card that spends the clock is a card that
	# makes going down a choice rather than a wait.
	{"id": "lead_keel", "name": "Lead Keel", "rarity": "uncommon",
		"system": "flight", "weight": 7,
		"desc": "Dive 35% faster.",
		"mods": {"dive_rate": 1.35}, "procs": []},

	# --- EPIC (purple) — build-defining. Pure upside, bigger numbers ----------
	{"id": "full_sail", "name": "Full Sail", "rarity": "epic",
		"system": "flight", "weight": 8,
		"desc": "Thrust +75%.",
		"mods": {"thrust": 1.75}, "procs": []},
	{"id": "broadside", "name": "Broadside", "rarity": "epic",
		"system": "guns", "weight": 7,
		"desc": "Guns hit 90% harder.",
		"mods": {"damage": 1.90}, "procs": []},
	{"id": "blood_engine", "name": "Hungry Engine", "rarity": "epic",
		"system": "guns", "weight": 6,
		"desc": "Guns fire 15% faster; hits mend 20% of the damage into the hull.",
		"mods": {"fire_rate": 0.85},
		"procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.20}]},

	# A BOUNCE IS A REAL HIT. The world re-fires the whole hit event on the bounced
	# target, so lifesteal and Cluster Shells both chain off it — deliberate, and
	# the reason this is an epic rather than an uncommon. The loop guard is one
	# rule: a ricochet never ricochets (world._dive_in_ricochet).
	{"id": "ricochet_rounds", "name": "Ricochet Rounds", "rarity": "epic",
		"system": "guns", "weight": 6,
		"desc": "Shots bounce to the nearest other enemy for 50% of the damage.",
		"mods": {}, "procs": [{"on": "hit", "effect": "ricochet", "amount": 0.50}]},

	# --- LEGENDARY (orange) — the run you tell someone about -----------------
	{"id": "cluster_shells", "name": "Cluster Shells", "rarity": "legendary",
		"system": "guns", "weight": 8,
		"desc": "Hits detonate: 60% of the damage again to everything nearby.",
		"mods": {}, "procs": [{"on": "hit", "effect": "explode", "amount": 0.60}]},
	{"id": "kings_ransom", "name": "Prize Money", "rarity": "legendary",
		"system": "pot", "weight": 6,
		"desc": "Every kill: +120 coins; every hit: +12.",
		"mods": {}, "procs": [
			{"on": "kill", "effect": "coins", "amount": 120},
			{"on": "hit", "effect": "coins", "amount": 12}]},
	{"id": "sanguine_tide", "name": "Leech Rig", "rarity": "legendary",
		"system": "hull", "weight": 5,
		"desc": "Hits mend 45% of the damage into the hull.",
		"mods": {}, "procs": [{"on": "hit", "effect": "lifesteal", "amount": 0.45}]},
	# IT CARRIES ITS OWN FIRST BOUNCE (design call, v0.134.0). A legendary that
	# does nothing unless you already drew a particular epic is a legendary that
	# reads as a dud two runs out of three, so this row carries BOTH procs and is a
	# complete card on its own. Holding Ricochet Rounds too is not double-dipping:
	# the world takes the MAX of the ricochet amounts and fires ONE sequence
	# (world._dive_apply_procs), so the pair is an upgrade, never two bounces.
	{"id": "chain_lightning", "name": "Skip Shot", "rarity": "legendary",
		"system": "guns", "weight": 5,
		"desc": "Shots bounce for 50%, then twice more for 35% each.",
		"mods": {}, "procs": [
			{"on": "hit", "effect": "ricochet", "amount": 0.50},
			{"on": "hit", "effect": "chain", "amount": 0.35}]},
	# ONE LIFE, ONCE FORGIVEN. The run's one-life rule (DiveRun.perish_aboard) is
	# untouched — this card is spent BEFORE the death path is reached, so the
	# second lethal blow of a run still ends it. It guards the BODY, which is why
	# it is a hull card rather than a rule of its own: on a committed run the body
	# only dies once the hull has already stopped protecting it.
	{"id": "second_heart", "name": "Second Heart", "rarity": "legendary",
		"system": "hull", "weight": 4,
		"desc": "The first killing blow of a run leaves your body at 1 health.",
		"mods": {}, "flags": ["second_heart"], "procs": []},
]

## The events a proc may hook, and the effects the world knows how to apply. A card
## naming anything outside these is a bug the suite catches — the world's
## interpreter is deliberately a closed set.
const EVENTS := ["kill", "hit", "land", "attack", "hurt"]
const EFFECTS := ["coins", "heal", "lifesteal", "explode", "ricochet", "chain"]
## Dial keys a `mods` entry may name (mirrors the world's `_dive_mod` call sites).
## `damage` and `fire_rate` are ONE dial each across both triggers (v0.140.0) —
## the merge that made the gun cards work at the helm; `move_speed`,
## `grapple_range` and `grapple_speed` went out with the legs/grapple cards
## (owner call, review §4.2 item 4: they buy a resource a committed run does not
## spend, so they leave the Dive's draw rather than sit in it as blanks).
const DIALS := ["damage", "fire_rate", "hull_repair", "thrust", "dive_rate",
	"fall_damage_taken", "grapple", "ride"]
## Dial keys an `adds` entry may name (the world's `_dive_add` call sites). A
## separate list, not a corner of DIALS, because the two channels compose
## differently — a missing multiplier is 1.0 and a missing addend is 0.0, and a
## key in the wrong one would silently do nothing at all.
const ADDS := ["max_hp"]
## Rule switches a `flags` entry may name (the world's `_dive_flag` call sites).
const FLAGS := ["second_heart"]


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


## WHICH SYSTEM a card buys ("guns"/"hull"/"flight"/"pot"). Defaults to "hull" so
## an un-tagged row is still legal data — the suite is what insists every shipped
## row names one, exactly as it does for rarity.
static func system_of(id: String) -> String:
	return String(by_id(id).get("system", "hull"))


## The chip the picker paints, upper-cased. One place, so the picker and the
## gallery cannot spell a system two ways.
static func system_label(id: String) -> String:
	return system_of(id).to_upper()


## THE STACKED TOTAL — "(×1.82 with what you hold)", or "" for a card with no
## `mods` (review §4.3: "show the stacked total"). The PRODUCT rule is the best
## thing about the deck and it is completely invisible at the picker: a second
## Heavy Shells reads as another +35% when it is really 1.35² = +82%.
##
## The dial reported is the card's FIRST `mods` key. Every shipped multi-dial row
## is a headline number plus a rider (Hungry Engine's cadence, Thick Skin's
## discount), and the headline is what the row is authored to lead with — so
## "first key" is the card's own emphasis, not an arbitrary pick.
##
## Pure and static so the world can precompute it into the draft row and the HUD
## can stay a painter (world-decides/layer-paints).
static func stack_text(held: Array, id: String) -> String:
	var mods: Dictionary = by_id(id).get("mods", {})
	if mods.is_empty():
		return ""
	var key := ""
	for k in mods:
		key = String(k)
		break
	var total := modifier(held, key) * float(mods[key])
	return "(×%.2f with what you hold)" % total


## What a card actually weighs in the draw: its own bias times its tier's. Never
## below 1, so a legendary is rare and not impossible.
static func draw_weight(card: Dictionary) -> int:
	var tier := String(card.get("rarity", "common"))
	var mult := int(RARITY_WEIGHT.get(tier, RARITY_WEIGHT["common"]))
	return maxi(1, int(card.get("weight", 1)) * mult)


# --- THE BLAST (the "explode" effect) ---------------------------------------
#
# Pure geometry, kept here rather than in the world, because the world cannot be
# named in a test (its `Net` autoload poisons the compile graph — the trap
# `pause_menu.gd` and `title_screen.gd` both carry scars from). The world's job
# is only to turn its live Ships into
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
				"system": String(cd.get("system", "hull")),
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
	# deck of this size runs off the bottom of a 720p window.
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
