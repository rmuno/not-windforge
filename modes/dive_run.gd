class_name DiveRun
extends RefCounted

## THE DIVE — the roguelite mode's run model (owner arc Q-G, 2026-08-30).
##
## The shape, as the owner ruled it over session 18 rounds 2–5:
##
##   * You start HIGH — breathable, safe, poor — and the run goes DOWN. Eight
##     depths. Down is richer and worse: better salvage, unbreathable air, a
##     thicker haze, meaner dens.
##   * There is no menu asking "dive or extract". The DEPTH IS WHERE YOU ARE:
##     the run reads your altitude and the choice is made with the stick, every
##     second, which is the "much more active gameplay" the owner asked for.
##   * CLIMBING BACK to the top band is the extraction, and it is a run in
##     reverse that gets longer the deeper you went. It BANKS the coins you are
##     carrying (into the permanent wallet), scaled by how deep you reached.
##   * DEPTH 8 is the LEVIATHAN's den. Killing it ends the run in triumph with
##     a completion bonus — the owner killed the "then climb back out endlessly"
##     phase on the grounds that the ascent had no antagonist of its own.
##   * LOSING THE SHIP ends the run and burns everything unbanked. The fall is
##     the run-over screen; the ledger writes itself over it.
##
## This class is the MODEL and nothing else — no nodes, no scene, no spawning.
## `advance()` takes a delta and an altitude fraction and returns the EVENTS the
## world should act on, so a whole ten-minute run is drivable in a headless test
## with a for-loop and no physics. The world owns everything with a body in it.

## How many depths the ladder has. Depth 1 is the surface, depth DEPTHS is the
## Leviathan's den. The owner's number: eight beats at roughly 75 s each is the
## ~10-minute cap they set ("I don't want to condemn anyone to more than 10 mins
## of their time at first").
const DEPTHS := 8

## Altitude fraction (0 = lava floor, 1 = ceiling) at the CENTRE of depth 1 and
## of depth DEPTHS. The ladder is linear between them. The top sits in the TOP
## band (Airspace.GAP_HIGH_TOP 0.68) so depth 1 is unambiguously safe air, and
## the bottom sits just above the lava (Airspace.LAVA_TOP 0.05) because you
## cannot dive past the floor — which is exactly why the run ends down there.
const TOP_FRAC := 0.86
const FLOOR_FRAC := 0.10

## THE SKY CLOSES BEHIND YOU (owner ruling 2026-08-31: "let's try the sky thing…
## just a forced push downward without ability to traverse back up, similar to
## ball pit"). A CEILING rides `CEILING_SLACK_RUNGS` above the altitude of the
## DEEPEST rung you have reached; above it the air runs DOWN, harder the further
## you trespass. Extraction therefore does not mean climbing out — it is PASSAGE
## HOME at an outpost counter (`go_home`, the "passage" stock row). The fiction is
## deliberately unexplained (owner: "perhaps even just disregard").
##
## Gated on `deepest > 1` by the world, like the den's clock, so the launch deck
## stays an unhurried place.
const CEILING_SLACK_RUNGS := 0.75


## One rung's height as an altitude fraction — the ladder's spacing.
static func rung_frac() -> float:
	return (TOP_FRAC - FLOOR_FRAC) / float(maxi(DEPTHS - 1, 1))


## The altitude fraction of the closed sky's underside for a run whose LOWEST
## reached altitude is `low` — slack rungs above that, never above the deck's
## own air. CONTINUOUS on purpose (owner 2026-08-31: "allow going up?"): the
## first cut hung the ceiling off the deepest RUNG, and because `depth_of`
## rounds at the midpoint between rungs, the ratchet clicked while you were
## still half a rung ABOVE the next landing — right after the click you had a
## quarter-rung of headroom, which read as "cannot go up at all". Off the
## continuous low-water mark, the promised slack is the headroom you actually
## have, at every moment.
static func ceiling_at(low: float) -> float:
	return minf(TOP_FRAC, low + rung_frac() * CEILING_SLACK_RUNGS)



# --- THE RUN'S WEATHER, AS ONE VECTOR (review §3.2 / owner call 2) -----------
#
# The ring's lean and the closing sky used to be two force sites in `world.gd`,
# each with its own multiplier, cap and call. They are ONE AIRSTREAM now, stamped
# on `Ship.extra_wind` and delivered through the drag term `Airspace` has always
# used — which turns the closing sky from a RAIL into a LEASH without a single
# clamp, because `Ship`'s rate controller measures its `v_up` relative to the
# air. In a downdraft faster than `climb_rate_max` a full climb is a fall you are
# slowing; in a slower one it is a climb you win. You can pop up to a ledge; you
# cannot commute (owner call 2, review §3.3 — "a leash, not a rail").
#
# `CEILING_PUSH` / `ceiling_push` / `CEILING_MAX_RUNGS` retired with the force.

## The hull's drag coefficient, mirrored from `Ship.AIR_DAMP`. It is here because
## a force of `mass · damp · wind` holds equilibrium exactly at `wind` px/s, so
## an acceleration authored for the old force sites converts to an airstream
## SPEED by dividing by it. Mirrored rather than read, because this file is a
## pure model with no Node classes in it; `_test_dive_weather` pins the parity.
const AIR_DAMP := 0.4

## The closing sky's airstream, px/s at scale 1 PER RUNG of trespass, and the cap
## on that ramp in rungs. 150 × 2 = 300 px/s@1× = 2,400 px/s at the shipped 8×.
##
## The numbers are chosen against `dive_climb_rate` (120@1× = 960 px/s at 8×),
## which is the only thing they have to be true against:
##   * a full rung over  → 1,200 px/s down: a full climb still LOSES 240 px/s;
##   * a quarter over    →   300 px/s down: a full climb WINS at ~660 px/s.
## That is the approved shape — a ledge is reachable, a commute is not.
const CEILING_LEASH_SPEED := 150.0
const CEILING_LEASH_MAX_RUNGS := 2.0


## THE WHOLE OF THE RUN'S WEATHER at one place, px/s at scale 1 (+y is DOWN); the
## world multiplies by `world_scale` and stamps it on `Ship.extra_wind`.
##
##   `zone_kind`     — the ring tile the point is in ("" or an unknown kind = no
##                     ring wind at all, which is the zones-off corridor case).
##   `over_rungs`    — how far the point is ABOVE the closed sky's underside, in
##                     rungs. <= 0 (or a run that has never left the deck, which
##                     the world passes as 0) means the sky is not shut yet.
##   `zone_mult`     — F2 `dive_zone_wind_mult`.
##   `ceiling_mult`  — F2 `dive_ceiling_mult`.
##
## The ring half is `ZONE_WIND / AIR_DAMP`: the SAME lean as before at rest (a
## steady mass·damp·wind force is exactly the old mass·accel force when the hull
## is still), now capped at the air's own speed instead of accelerating forever.
static func weather_wind(zone_kind: String, over_rungs: float,
		zone_mult: float, ceiling_mult: float) -> Vector2:
	var vy := zone_wind_of(zone_kind) * ZONE_WIND / AIR_DAMP * zone_mult
	vy += CEILING_LEASH_SPEED * clampf(over_rungs, 0.0, CEILING_LEASH_MAX_RUNGS) \
		* ceiling_mult
	return Vector2(0.0, vy)

## DYING. One pool, one life (owner 2026-08-31: "where did the 3 lives come
## from? just do 100 hp for the player"). The old three-deaths-with-a-pot-cut
## respawn loop is gone: your GRIT pool is the whole story, and when it empties
## in a run, the run is over. (The lives cap once existed to stop an infinite
## suffocate-respawn loop at the air gate; with death final, that loop cannot
## exist at all.)

## Extraction premium: banking pays the pot times 1 + this × how far down you
## got (0 at depth 1, the full bonus at the floor). So a wise retreat from depth
## 5 is never a wasted ten minutes, which is what keeps "one more depth" a hard
## question instead of an obvious one.
const DEPTH_BONUS := 1.5

## Killing the Leviathan pays this on top of the banked pot.
const TRIUMPH_BONUS := 2000

## What one creature is worth at depth 1, by `Ship.creature_kind`. Absent kinds
## fall back to BASE_COIN — a coin drop is a reward for a fight, not an economy,
## and the sell-value table (rpg/economy.gd) stays the place item worth lives.
const KIND_COIN := {
	"critter": 8,
	"whale": 40,
	"kraken": 60,
	"basilisk": 55,
	"whale_city": 500,
	# A gunboat picket, killed by breaking its INTEGRITY (v0.111.0 — vessels in
	# a run die as units now). Before integrity, a destroyed vessel never paid:
	# `_dive_credit_kill` only heard the creature-death signal, which is half of
	# why the top rungs felt inconsequential.
	"hulk": 35,
}
const BASE_COIN := 20

## Coin scaling with depth: a kill at depth d is worth base × (1 + DEPTH_COIN ×
## (d − 1)). Deeper things are worth more BEFORE the extraction premium, so the
## greed has two reasons and the player feels both.
const DEPTH_COIN := 0.35

# --- Live run state ---------------------------------------------------------

var depth := 1          ## where you are right now (1..DEPTHS)
var deepest := 1        ## the headline number: how far down you got
## The LOWEST altitude fraction ever reached — the closing sky hangs off this
## (ceiling_at), continuously, so climbing headroom never ratchets away.
var low_frac := 1.0
var pot := 0            ## coins carried and NOT yet banked — burns with the ship
var banked := 0         ## what reached the permanent wallet (set when the run ends)
var kills := 0
## Surges sent. The 45-second timer that used to drive this is retired (see
## `advance`); `world._dive_surge` is an F2 verb now and increments it, so the
## ledger's "attacks" line stays true instead of counting a clock nobody runs.
var surges := 0
var deaths := 0
var elapsed := 0.0
## "" while running, then one of "escaped" / "lost" / "triumph".
var outcome := ""

## THIS RUN'S SEED. Not the world's: regenerating terrain mid-session is a world
## rebuild, and what actually has to vary run to run is the run's SHAPE — where
## each depth's landing sits and which of them are outposts. The sky around them
## still comes from the world seed, which is the part that should stay familiar.
var seed_v := 0

## Have you taken a hull? A run starts on the LAUNCH DECK with nobody's ship
## under you (owner 2026-08-30) — the candidates are parked, and boarding one is
## the first decision of the run. It matters because it decides HOW THE RUN CAN
## END: with a hull, losing it is the ending; with none, only your body is.
var committed := false

## How the run ended, when it ended badly: "ship" (the hull you took was
## destroyed), "shipless" (you never took one and your body gave out), or "worn"
## (you kept dying aboard until there was nothing left of you).
var lost_how := ""
var _seen := {1: true}        ## depths already arrived at (each announces once)
var _leviathan_called := false

# --- Cards (owner arc Q-L, 2026-08-31) --------------------------------------
#
# A run-scoped upgrade draft (DiveCards). Kills grant XP; a full bar owes a DRAFT;
# a draft is a choice of three, and the picks make THIS run stronger. Drafts also
# come at run-start (the opening hand) and from an outpost quartermaster on arrival
# (the owner's "npcs can sometimes grant cards"). Held cards apply passive
# multipliers to dials and PROCS to events — the world reads `modifier`/`procs_for`
# and acts; this model just holds the deck and the bar.

## Card ids the player is holding this run.
var cards: Array = []
## XP toward the next draft, and how many drafts have been earned (the bar's level).
var xp := 0
var xp_level := 0
## Drafts OWED but not yet taken. The world offers a choice-of-three while > 0.
var pending := 0
## The three ids currently on offer ([] when no draft is being shown). The world
## fills this via `offer` and consumes it via `take`.
var draft: Array = []

## XP for the NEXT draft grows with each one taken, so early cards come fast (the
## run gets a build quickly) and later ones are earned. XP is the COINS a kill is
## worth, so a deeper kill advances the bar faster — the same "down is richer"
## curve the pot already rides.
const XP_BASE := 60
const XP_STEP := 40
static func xp_for_level(level: int) -> int:
	return XP_BASE + XP_STEP * maxi(0, level)


func _init() -> void:
	seed_v = randi()


# --- The pure ladder --------------------------------------------------------

## The altitude fraction at the centre of depth `d`. Pure, so the world's
## placement and the tests share one ladder.
static func depth_altitude(d: int) -> float:
	if DEPTHS <= 1:
		return TOP_FRAC
	var t := float(clampi(d, 1, DEPTHS) - 1) / float(DEPTHS - 1)
	return TOP_FRAC + (FLOOR_FRAC - TOP_FRAC) * t


## Which depth an altitude fraction is in — the inverse of `depth_altitude`,
## rounded to the nearest rung and clamped to the ladder. Everything above depth
## 1 is depth 1 (the sky over the surface is still the surface) and everything
## below depth DEPTHS is the floor.
static func depth_of(a: float) -> int:
	var span := TOP_FRAC - FLOOR_FRAC
	if span <= 0.0:
		return 1
	var t := (TOP_FRAC - a) / span
	return clampi(1 + int(round(t * float(DEPTHS - 1))), 1, DEPTHS)


## How far the ladder may wander from the centre line, in shelf widths. The
## descent is a SHAFT, not a country (owner 2026-08-30: "I'm not sure how much
## sense it makes for the dive to have a FULL wide map if the purpose is to go
## straight down"). Unbounded, the cumulative slalom below could drift thirty
## widths over eight rungs — a third of a million pixels at 8×, which is a map,
## not a dive.
const LADDER_SPREAD := 3.0


## The smallest sidestep between one landing and the next, in shelf widths. A
## landing IS a shelf wide, so anything under 1.0 leaves the two slabs
## overlapping and a straight drop lands on the next one down.
const LANDING_STEP_MIN := 1.5
## The largest, so the slalom is a lean and not a lunge.
const LANDING_STEP_MAX := 4.0


## Where depth `d`'s LANDING sits, as a horizontal offset in SHELF WIDTHS from
## the world's centre line. Depth 1 (the launch deck) is the centre line; every
## rung below sidesteps to one side or the other, CUMULATIVELY — so the descent
## is a slalom you fly rather than a lift shaft you drop down — and the walk
## stays inside `LADDER_SPREAD`, the corridor the run holds you in
## (`world.dive_corridor_half`). Pure in (seed, depth).
##
## THE BOUND IS NOT A CLAMP, and that distinction was a shipped bug (owner
## 2026-08-30: *"it seems you get stuck at depth 4 (no more falling)"*). Clamping
## `x + step` to ±LADDER_SPREAD makes the wall a SINK: a run that reaches ±3 and
## keeps rolling the same side stays at ±3 for every rung after it, so landing
## after landing is stamped at exactly the same x — and since each one is a solid
## slab about a shelf wide, the ship simply lands on the next rung down and the
## descent stops. Measured over 200 seeds, **381 of 1,400 rung transitions came
## out under one shelf width apart, many of them exactly zero.**
##
## So the SIDE is chosen against the room available instead: if the rolled side
## has less than `LANDING_STEP_MIN` to give, the ladder turns around, and the
## step is then trimmed to what that side actually has. Because the corridor is
## ±3 and the minimum step is 1.5, at least one side always has room — so every
## rung is guaranteed to sidestep at least a shelf and a half, at every depth,
## for every seed. That is the invariant `_test_dive_ladder_never_stacks` pins.
static func landing_offset(sv: int, d: int) -> float:
	var x := 0.0
	for k in range(2, clampi(d, 1, DEPTHS) + 1):
		var r := absi(hash([sv, "landing", k]))
		var side := 1.0 if (r & 1) == 1 else -1.0
		if LADDER_SPREAD - side * x < LANDING_STEP_MIN:
			side = -side
		var span := LANDING_STEP_MAX - LANDING_STEP_MIN
		var step := LANDING_STEP_MIN + float((r >> 1) % 250) / 250.0 * span
		x += side * minf(step, LADDER_SPREAD - side * x)
	return x


## THE DESCENT CAP IS RETIRED (DESIGN_DIVE_REVIEW §3.2). `DESCENT_BLEED`,
## `DRIFT_FRACTION`, `descent_cap`, `bleed_descent`, `settles_at`,
## `DESCENT_TOP_MULT` and `descent_depth_mult` lived here to hold a hull to
## `dive_descent_max` by easing `linear_velocity.y` toward a limit — a velocity
## write into a rigid body, every tick, which is what "the physics feel off" was
## made of. The cap existed because a hull sank at 2,389 px/s on a NEUTRAL stick:
## the run started in air of density 0.05 and lift had nothing to hold up. Both
## halves of that are gone. `Ship.air_density_floor` puts the run in real air, so
## a trimmed hull hovers; `Ship.rate_control` makes the stick command a SPEED, so
## the old cap survives as the F2 lever `dive_dive_rate` (the same 240) — the
## stick's own down scale — and arrives as a controller settling rather than as a
## write the solver never made.


## HOW HARD THE CORRIDOR LEANS, px/s² at scale 1 per shelf-width of trespass, and
## the cap on that ramp.
##
## These were 260 and an inline 4.0 in `world.gd`, which made the corridor push
## at 260 × 8 × 4 = **8,320 px/s² against a hull whose own props manage about
## 1,000** — forty times the pilot's authority. Measured, holding `ship_right`
## inside a run carried the ship **19,865 px to the LEFT** in five seconds, which
## the owner filed as *"my propeller thrust seems way nerfed, even sideways."* It
## was not the props. It was this, and it had quietly turned the corridor into the
## RAIL it was explicitly chosen instead of (DECISIONS, "the Dive is a CORRIDOR,
## not a rail").
##
## They live here now so the suite can hold them against a hull's real authority —
## `world.gd` cannot be named in a test without dragging its `Net` autoload into
## the compile graph. `HULL_LATERAL_ACCEL` is the measured figure that makes the
## comparison meaningful rather than a vibe.
const CORRIDOR_PUSH := 16.0
const CORRIDOR_MAX_WIDTHS := 4.0
## What a shipped hull's own props actually deliver sideways, px/s² at scale 1
## (measured: ~1,000 px/s² at 8×). The corridor must stay a fraction of it.
const HULL_LATERAL_ACCEL := 125.0


## The corridor's push for a hull `over_widths` shelf-widths outside it.
static func corridor_push(over_widths: float) -> float:
	return CORRIDOR_PUSH * clampf(over_widths, 0.0, CORRIDOR_MAX_WIDTHS)


## CAN THIS BODY TAKE THAT HELM? (owner 2026-08-30: *"could you compute the
## boundaries for 'getting on' such that it works above, below, to the sides, and
## by the corners? you're really just drawing a bounding square and making it 1-2
## (or 8-16) blocks wider in every direction (so double that)"*.)
##
## Exactly that, and it is one line: the hull's own bounding box grown by the
## margin ON ALL FOUR SIDES, which is what `Rect2.grow` does — so the box gets
## `2 * margin` wider and `2 * margin` taller, above and below and to the sides,
## and the corners come out right for free because it is a rectangle test rather
## than four edge tests or a radius.
##
## `local` is the body in the SHIP'S frame and `bounds` is `Ship.solid_bounds`,
## which is already world pixels at any scale — the margin is what carries the
## scale (`world.DIVE_HELM_MARGIN_CELLS`).
##
## Pure, so every direction the owner listed is pinned in the suite without a
## ship, a deck or a keypress.
static func helm_in_reach(bounds: Rect2, local: Vector2, margin: float) -> bool:
	if bounds.size == Vector2.ZERO:
		return false
	return bounds.grow(margin).has_point(local)


## WHAT TO SAY WHEN THE SHIP WILL NOT GO DOWN (owner 2026-08-30: "it seems you
## get stuck at depth 4 (no more falling)").
##
## Half of that report was a bug in this file (see `landing_offset`) and half of
## it was the mode working as designed with nothing saying so: the ladder is a
## SLALOM, every rung is a solid slab, and a ship that holds the stick down from
## a fixed column meets one sooner or later and simply rests on it. Flying clear
## of it is the answer, and the run already draws an edge marker at the next
## landing — but a player pressing DOWN and going nowhere has no reason to look
## at a marker they are not currently failing to reach.
##
## So the run says it, once, in the direction the next landing actually lies.
## Pure so the wording is testable without a ship, a shelf or an input.
static func stuck_hint(dx: float) -> String:
	if absf(dx) < 1.0:
		return "The ledge has you. Fly clear of it — straight down is rock."
	var side := "starboard" if dx > 0.0 else "port"
	return "The ledge has you. Fly clear of it — the next landing is to %s." % side


## Which depths hold an OUTPOST — a landing that trades (owner 2026-08-30: "a few
## natural safe zones along the way … in-run upgrades which are temporary but
## MUCH cheaper than anything permanent").
##
## Always three, always spread: one from each PAIR of the middle rungs, so the
## longest stretch without a shop is three rungs and there is never a barren
## descent. Never depth 1 (the launch deck is not a shop) and never the floor
## (nobody trades down there).
const OUTPOST_PAIRS := [[2, 3], [4, 5], [6, 7]]
static func outpost_depths(sv: int) -> Array:
	var out: Array = []
	for i in OUTPOST_PAIRS.size():
		var pair: Array = OUTPOST_PAIRS[i]
		out.append(pair[absi(hash([sv, "outpost", i])) % pair.size()])
	return out


static func is_outpost(sv: int, d: int) -> bool:
	return outpost_depths(sv).has(clampi(d, 1, DEPTHS))


## WHAT AN OUTPOST SELLS (owner 2026-08-30: "in-run upgrades which are temporary
## but MUCH cheaper than anything permanent").
##
## Three things, all of them gear that already exists, all of them bought with
## THE POT — the coins you are carrying and have not banked. That is the whole
## economy in one sentence: **every purchase is money you are choosing not to
## take home**, so the shop and the extraction premium pull against each other
## every single time you land.
##
## The Aether Lung is the important one. Depths 6–8 sit below
## `Airspace.DEEP_TOP`, so the air down there kills an unprotected pilot — the
## headless playtest ended a run on exactly that. The Lung is therefore not a
## nice-to-have: it is the ticket past the gate, and it is why the landings are
## load-bearing rather than scenery.
const STOCK := [
	{"id": "lung", "cost": 220,
		"label": "Aether Lung — breathe below the line"},
	{"id": "patch", "cost": 120,
		"label": "Hull patch — mend it where it stands"},
	{"id": "balloon", "cost": 90,
		"label": "Large balloon — more lift, tether it with Q"},
	# EXTRACTION (the sky closes behind a run, so the way home is a berth on the
	# quartermaster's balloon, not a climb). Free — the extraction premium is
	# the pot's own arithmetic (`bank_value`), and charging a fee on top would
	# tax the one row that ends the run. Last on purpose: the counter reads
	# "spend it here, or take it home", in that order.
	{"id": "passage", "cost": 0,
		"label": "PASSAGE HOME — bank the pot, end the run"},
]


## WHAT THIS RUN HANDED YOU, as {item id: count}. Everything an outpost sells is
## TEMPORARY — that is the owner's word for it — and temporary has to mean
## something, or the Aether Lung is bought once and the depth gate is open
## forever after. So the run remembers exactly what it granted and the world
## takes that much back when the run ends. What you owned before a run is
## untouched: only the counted grants come off.
var granted := {}


## Record that this run handed over `n` of item `id`.
func grant(id: int, n := 1) -> void:
	granted[id] = int(granted.get(id, 0)) + n


## Spend `cost` from the pot. Refused (and nothing changes) if you cannot afford
## it — no debt, exactly like `Wallet.spend`.
func spend(cost: int) -> bool:
	if outcome != "" or cost < 0 or pot < cost:
		return false
	pot -= cost
	return true


## What one creature of `kind` is worth killed at `d`. Whole coins, never
## negative.
static func coins_for(kind: String, d: int) -> int:
	var base: int = int(KIND_COIN.get(kind, BASE_COIN))
	var mult := 1.0 + DEPTH_COIN * float(clampi(d, 1, DEPTHS) - 1)
	return maxi(0, int(round(float(base) * mult)))


## What carrying `p` coins out from a run that reached `d` pays into the wallet.
static func bank_value(p: int, d: int) -> int:
	if p <= 0:
		return 0
	var reach := float(clampi(d, 1, DEPTHS) - 1) / float(maxi(1, DEPTHS - 1))
	return int(round(float(p) * (1.0 + DEPTH_BONUS * reach)))


## WHAT a depth throws at you, as `world.debug_spawn` kinds, in the order they
## arrive (owner 2026-08-30: "the first height levels can have just enemies on
## their tiny ships shooting at you").
##
## The ladder is a ladder of KIND before it is a ladder of number. The top is
## crewed vessels — things with guns that shoot back and can be out-flown, which
## is a fight you can lose without dying. The bottom is krakens, which is the
## deep's own answer. The middle is where the two overlap and the basilisk (a
## stand-off fire-spitter) makes altitude matter.
##
## Deliberately NOT a whale in sight: the whale is the sky's neutral third party.
## It already retaliates against whoever shot it LAST (Shot stamps the shooter
## onto `Ship.last_attacker_id`, the world's damage wiring hands it to
## `WhaleAI.provoke`, pinned by `_test_provoked_whale_rams_its_attacker`), so a
## whale that wanders into a firefight is a weapon lying on the floor for
## whichever side is willing to aim it. Spawning them as ENEMIES would delete
## that: a whale sent at you is not a whale you can turn.
const SURGE_LADDER := [
	["hulk"],                    # 1 — one gunboat. You can simply leave.
	["hulk"],                    # 2
	["hulk", "basilisk"],        # 3 — the first thing that punishes hovering
	["hulk", "kraken"],          # 4 — the deep starts reaching up
	["kraken", "basilisk"],      # 5
	["kraken"],                  # 6 — vessels stop coming this far down
	["kraken"],                  # 7
	["kraken"],                  # 8 — and something else lives here
]


## What depth `d` sends. Never empty — a depth with nothing in it is a corridor.
static func surge_kinds(d: int) -> Array:
	var i := clampi(d, 1, DEPTHS) - 1
	if i < 0 or i >= SURGE_LADDER.size():
		return ["kraken"]
	return (SURGE_LADDER[i] as Array).duplicate()


## How many hunters a depth's den throws at you in one surge. TOP-HEAVY WITH
## WEAK VESSELS on purpose (owner 2026-08-31: "more weak enemies — people on
## their tiny ships — on the first level; those should be the threat"): the
## shallow rungs swarm with gunboats you can beat, the floor sends few, mean
## things. Whales stay neutral (never in the ladder — pinned).
const SURGE_COUNTS := [3, 3, 2, 2, 3, 3, 4, 5]
static func surge_count(d: int) -> int:
	return int(SURGE_COUNTS[clampi(d, 1, DEPTHS) - 1])


## The name of a depth, for the HUD and the ledger. Depth DEPTHS is not a number
## to the player; it is the place the Leviathan lives.
static func depth_label(d: int) -> String:
	if d >= DEPTHS:
		return "THE FLOOR"
	return "DEPTH %d" % clampi(d, 1, DEPTHS)


# --- The run ----------------------------------------------------------------

## Advance the run by `delta` at altitude fraction `a`. Returns the events the
## world must act on, in order:
##
##   "depth"     — you reached a NEW deepest depth (announce it, cut the rung)
##   "leviathan" — you have arrived at the floor; wake the boss (once)
##
## THE TIMER SURGE IS RETIRED (owner call 6, review §5.3). A 45-second clock that
## spawned hunters past the horizon and flew them in is exactly the sourceless
## ring-spawn `DESIGN.md` §4 forbids — "danger is a property of PLACE" — and with
## a standing garrison and a chase that never lets go, its job (pressure on a
## parked player) was already being done twice. So `_grace`, `ARRIVAL_GRACE`,
## `surge_in()` and the `"surge"` event are gone, and arriving at a depth spawns
## nothing by itself: a run's population IS its garrison. `world._dive_surge`
## survives as an F2 verb so the owner can still summon pressure for an A/B.
##
## (There is no "escaped" event any more either: the sky closes behind a run, so
## extraction is `go_home` at an outpost counter, not an altitude.)
##
## Returns nothing at all once the run is over — a finished run is inert, so a
## world that keeps ticking it (and one does, for the ledger) costs nothing.
func advance(delta: float, a: float) -> Array:
	if outcome != "":
		return []
	var out: Array = []
	elapsed += delta
	low_frac = minf(low_frac, a)
	depth = depth_of(a)
	if depth > deepest:
		deepest = depth
	if not _seen.has(depth):
		_seen[depth] = true
		out.append("depth")
	if depth >= DEPTHS and not _leviathan_called:
		_leviathan_called = true
		out.append("leviathan")
	return out


## PASSAGE HOME — extraction, now that the sky closes behind a run. Bought at an
## outpost counter (the "passage" stock row): banks the pot at the same
## deepest-scaled premium the old climb-out paid — the premium always scaled
## with how deep you GOT, never with the climb, so the economy is untouched;
## only extraction's location moved from the top of the shaft to the landings.
## Refused before you have ever left the deck (a run you never dived is not a
## run you can be extracted from) and on a finished run. Returns whether the
## run ended.
func go_home() -> bool:
	if outcome != "" or deepest <= 1:
		return false
	outcome = "escaped"
	banked = bank_value(pot, deepest)
	return true


## Credit a kill of `kind` at the current depth. Returns the coins added, so the
## world can float the number over the corpse.
##
## COINS ONLY, since v0.137.0. The XP half used to be paid right here — a kill's
## coin value WAS its XP — and the owner moved it out of the kill entirely: XP is
## SCRAP now, a physical drop that hangs where the thing died and pays whoever
## flies through it (`absorb_scrap`; the field lives in `combat/scrap.gd`). The
## two channels are deliberately different in kind, which is the owner's
## "separate, a la vampire survivors": coins are credited to the KILLER (the
## world still asks `_dive_kill_is_yours` before paying), scrap is collected by
## whoever gets NEAREST — "if a kraken kills an enemy ship, I guess the player
## can still get that exp".
func credit_kill(kind: String) -> int:
	if outcome != "":
		return 0
	var coins := coins_for(kind, depth)
	pot += coins
	kills += 1
	return coins


## What a death of `kind` at depth `d` HANGS IN THE AIR as scrap. Identical to
## its coin value on purpose: that is exactly what the XP bar used to be paid, so
## every pacing number the card deck was tuned against survives the move to a
## physical drop untouched.
static func scrap_for(kind: String, d: int) -> int:
	return coins_for(kind, d)


## Absorb `amount` XP out of collected scrap. The one door XP comes through now,
## and the reason it is public where `_gain_xp` is not: the world calls this at
## the absorption site, every frame a mote lands. Returns the XP actually taken
## (0 on a finished run — a dead run cannot level).
func absorb_scrap(amount: int) -> int:
	if outcome != "" or amount <= 0:
		return 0
	_gain_xp(amount)
	return amount


## Add `amount` XP and owe a draft for each bar it fills. A single fat kill can
## fill more than one bar, so this loops.
func _gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_for_level(xp_level):
		xp -= xp_for_level(xp_level)
		xp_level += 1
		pending += 1


## Owe the player a draft that did not come from XP — the opening hand at run
## start, or an outpost quartermaster on arrival (the owner's NPC grant).
func add_draft(n := 1) -> void:
	pending = maxi(0, pending + n)


## Is a draft waiting to be taken? (A draft may still resolve to an empty offer if
## every card is already held — `offer` handles that by draining the debt.)
func draft_pending() -> bool:
	return pending > 0


## Fill the current offer if a draft is owed and none is showing. Returns the ids
## on offer (possibly fewer than three near the end of the deck; empty if every
## card is held — in which case the debt is simply drained, no picker). `rng` is
## the world's, so a fixed seed offers a fixed hand.
func offer(rng: RandomNumberGenerator) -> Array:
	if pending <= 0:
		draft = []
		return draft
	if draft.is_empty():
		draft = DiveCards.draw_choices(rng, cards, 3)
		if draft.is_empty():
			# Nothing left to offer — do not strand a pending draft forever.
			pending = 0
	return draft


## Take card `id` from the current offer: it must be one of the three showing.
## Consumes one owed draft and clears the offer (the next pending draft, if any,
## refills on the next `offer`). Returns false if the id is not on offer.
func take(id: String) -> bool:
	if not draft.has(id):
		return false
	cards.append(id)
	draft = []
	pending = maxi(0, pending - 1)
	return true


## Grant a card outright (a debug reveal, or a fixed reward) — bypasses the draft.
func grant_card(id: String) -> void:
	if DiveCards.is_known(id) and not cards.has(id):
		cards.append(id)


## The combined multiplier the held cards apply to dial `key` (1.0 when none do).
func modifier(key: String) -> float:
	return DiveCards.modifier(cards, key)


## The combined ADDEND the held cards apply to dial `key` (0.0 when none do).
func addend(key: String) -> float:
	return DiveCards.addend(cards, key)


## Is rule `flag` switched on by a held card? (Second Heart is the only one left
## since the grapple cards left the Dive's draw.)
func flag(name: String) -> bool:
	return DiveCards.has_flag(cards, name)


## The proc effects the held cards fire on `event`, as [{effect, amount}, ...].
func procs_for(event: String) -> Array:
	return DiveCards.procs_for(cards, event)


## SECOND HEART, spent (owner-approved legendary, 2026-09-01). Has this run
## already used its one reprieve?
var second_heart_spent := false


## Spend the reprieve, if there is one to spend. True EXACTLY ONCE per run, and
## only while the card is held and the run is live — the world calls this at the
## death site and, on a true, puts the body back at 1 HP instead of ending the
## run. The one-life rule is otherwise untouched: the next lethal blow finds this
## returning false and the run is over, which is the whole shape of the card.
func spend_second_heart() -> bool:
	if outcome != "" or second_heart_spent or not flag("second_heart"):
		return false
	second_heart_spent = true
	return true


## The player died with the run live. One life (owner ruling): the run ends
## here, whatever was aboard or banked-to-be. Returns true (it always ends now;
## the bool survives for call-site stability).
func perish_aboard() -> bool:
	if outcome != "":
		return true
	deaths += 1
	outcome = "lost"
	lost_how = "worn"
	banked = 0
	return true


## You took this hull; from here, losing it is the ending.
func commit() -> void:
	committed = true


## The run is over with nothing banked. `shipless` distinguishes the two ways
## that happens: your hull was destroyed, or you never took one and your body
## gave out. The pot burns either way.
func lose(shipless := false) -> void:
	if outcome == "":
		outcome = "lost"
		lost_how = "shipless" if shipless else "ship"
		banked = 0


## The Leviathan is dead. Bank the pot at the floor's rate, plus the completion
## bonus the owner asked for.
func triumph() -> void:
	if outcome == "":
		outcome = "triumph"
		banked = bank_value(pot, DEPTHS) + TRIUMPH_BONUS


## The run in plain values — the HUD paints this and the ledger prints it, and
## nothing else reaches into the model (the world-decides/layer-paints rule).
func ledger() -> Dictionary:
	return {
		"outcome": outcome,
		"committed": committed,
		"lost_how": lost_how,
		"deaths": deaths,
		"depth": depth,
		"deepest": deepest,
		"deepest_label": depth_label(deepest),
		"pot": pot,
		"banked": banked,
		"kills": kills,
		# "attacks" on the run-over card. With the timer retired this counts the
		# surges the F2 verb actually sent, which in normal play is zero — the
		# sky's population is the garrison, and the ledger says so honestly.
		"surges": surges,
		"elapsed": elapsed,
		# Cards (Q-L): held names, the XP bar, and the current draft offer (each as
		# {id, name, desc}) so the HUD paints without reaching into the catalog.
		"cards": card_names(),
		"xp": xp,
		"xp_need": xp_for_level(xp_level),
		"card_level": xp_level,
		"draft": draft_view(),
	}


## The held cards' display names, in the order taken.
func card_names() -> Array:
	var out: Array = []
	for id in cards:
		out.append(DiveCards.name_of(String(id)))
	return out


## The current draft offer as painter-ready rows, empty when nothing is on offer:
## [{id, name, desc, system, system_label, stack, rarity, rarity_label, color},
## ...]. The RARITY travels as plain data + a finished Colour so the picker never
## reaches into the catalog to work out what colour a card is
## (world-decides/layer-paints).
##
## `system` and `stack` are the review's two picker fixes (§4.3), and both are
## decided HERE rather than in the HUD: the chip is a catalog lookup, and the
## stacked total needs the HELD deck — neither is something a painter is allowed
## to reach for. `stack` arrives finished ("(×1.82 with what you hold)") or empty
## for a card that multiplies nothing.
func draft_view() -> Array:
	var out: Array = []
	for id in draft:
		var cid := String(id)
		var tier := DiveCards.rarity_of(cid)
		out.append({"id": cid, "name": DiveCards.name_of(cid),
			"desc": DiveCards.desc_of(cid),
			"system": DiveCards.system_of(cid),
			"system_label": DiveCards.system_label(cid),
			"stack": DiveCards.stack_text(cards, cid),
			"rarity": tier, "rarity_label": DiveCards.rarity_label(tier),
			"color": DiveCards.rarity_color(tier)})
	return out


## The run-over headline — the owner's "you traversed X vertical distance", said
## as the thing the player will try to beat next time.
static func outcome_line(l: Dictionary) -> String:
	match String(l.get("outcome", "")):
		"triumph":
			return "THE LEVIATHAN IS DEAD. You came back up with %d coins." % int(l.get("banked", 0))
		"escaped":
			return "YOU MADE IT OUT. %s, and %d coins banked." % [
				String(l.get("deepest_label", "")), int(l.get("banked", 0))]
		"lost":
			match String(l.get("lost_how", "ship")):
				"shipless":
					return "YOU FELL. No ship, %s reached, %d coins gone with you." % [
						String(l.get("deepest_label", "")), int(l.get("pot", 0))]
				"worn":
					return "THE DEEP TOOK YOU at %s. %d coins died with you." % [
						String(l.get("deepest_label", "")), int(l.get("pot", 0))]
			return "YOUR SHIP IS GONE. You reached %s. %d coins fell with it." % [
				String(l.get("deepest_label", "")), int(l.get("pot", 0))]
	return ""


# --- THE WIND RING (owner experiment, 2026-08-31) ---------------------------
#
# "I want to be able to travel left/right and for the world to loop. We'd start
# at the center which has wind pushing up. Going either side takes us to a bit
# more of a rocky area which is just harder to traverse, as well as the usual
# enemies. If you keep going, the wind instead will push DOWN … and if you keep
# going in that direction, you'd just loop back to the center."
#
# The run's sky is a RING of tiles, wrapping. Tile 0 is the start — an UPDRAFT
# that fights your descent, so the middle of the map is the slow, safe line.
# The flanks are THE ROCKS: no wind help, more pickets. The far side is the
# DOWNDRAFT — descent express, and the meanest garrison. Cross the ring's edge
# and you arrive from the other side.
#
# THE OWNER'S OWN DRAWING (2026-09-01), and the ring is now exactly it:
#
#     V . . . . . ^ . . . . . V
#
# `^` is the UPDRAFT you start in, at the CENTRE. Five intermediate tiles run
# out to either flank. `V` is the DOWNDRAFT — and the two `V`s in the sketch are
# ONE TILE, the ring's SEAM, drawn at both ends because that is where the world
# "loops onto the world for both edges". Thirteen symbols, twelve tiles.
#
# Which makes the table below read straight off the sketch: index 0 is `^`,
# 1-5 and 7-11 are the dots, and index 6 is the `V` that sits at ±6 tile widths
# — i.e. astride the wrap, half of it on each edge (see `zone_offset`).
#
# The ladder's landings stay near the centre column, so the downdraft is fast
# but berthless — you ride it down, then come around. The RING table is data:
# resizing it is an edit here and nowhere else (the wrap, the HUD, the world's
# width and the MAP ROOM all read `RING.size()`).
const RING := ["up", "rock", "rock", "rock", "rock", "rock",
	"down", "rock", "rock", "rock", "rock", "rock"]
## Wind AT STRENGTH 1, authored as px/s² at scale 1 and read as an airstream
## speed of `ZONE_WIND / AIR_DAMP` (75 px/s@1×, 600 at the shipped 8×) — see
## `weather_wind`. The force at rest is identical either way; what changed is
## that the lean now stops at the air's own speed instead of accelerating on.
## Comparable to the props (HULL_LATERAL_ACCEL 125): the updraft meaningfully
## slows a descent and the downdraft meaningfully feeds one, but neither is a
## rail. 120 was authored blind and turned the updraft into a geyser ~5x the
## hull's own vertical authority — the start tile pinned the ship. 30 is a LEAN:
## you feel it, you fly through it.
const ZONE_WIND := 30.0


## Which ring tile an offset of `x_off_tiles` tile-widths from the world centre
## lands in. Nearest-tile, wrapped — so ±0.5 tiles is still the centre, and the
## ring closes seamlessly in both directions.
static func zone_index(x_off_tiles: float) -> int:
	return posmod(roundi(x_off_tiles), RING.size())


static func zone_kind(i: int) -> String:
	return String(RING[posmod(i, RING.size())])


## The tile's wind as a SIGNED strength factor (+y is DOWN): the updraft is
## negative, the downdraft positive, the rocks still.
static func zone_wind(i: int) -> float:
	return zone_wind_of(zone_kind(i))


## ...by KIND rather than by index, because `weather_wind` is handed the kind the
## world already resolved for a position. An unknown kind (including "") is calm,
## which is what makes the zones-off corridor case fall out for free.
static func zone_wind_of(kind: String) -> float:
	match kind:
		"up": return -1.0
		"down": return 1.0
	return 0.0


## Extra pickets a SURGE adds in this tile — the ring grows meaner away from home
## ("just with maybe more enemies"). The picket cap still bounds the total.
##
## THE STANDING GARRISON NO LONGER READS THIS (owner call 3, v0.141.0): a depth's
## garrison is `surge_count(d)` in TOTAL around its landing column, so adding a
## per-tile bonus on top of it would put the ring straight back at 48 pickets a
## rung. It survives for `world._dive_surge` (the F2 verb) and for the map room's
## per-column readout, which is where "how bad is that side" is still a question.
static func zone_extra_pickets(i: int) -> int:
	match zone_kind(i):
		"rock": return 1
		"down": return 2
	return 0


## The tile's name for the HUD — where you are, in the sky's own words.
static func zone_label(i: int) -> String:
	match zone_kind(i):
		"up": return "UPDRAFT"
		"down": return "DOWNDRAFT"
	return "THE ROCKS"


## Where tile `i`'s CENTRE sits, as a signed offset in tile widths from the
## ring's centre — the inverse of `zone_index`, taking the SHORT way round so
## the second half of the table lies to PORT rather than miles out to starboard.
##
## At RING.size() 12 that puts the seam tile (index 6) at exactly ±6, which is
## the wrap line itself: half of the downdraft hangs off each edge of the world,
## which is what makes the owner's `V … ^ … V` sketch literally true.
static func zone_offset(i: int) -> float:
	var n := RING.size()
	var t := posmod(i, n)
	return float(t - n) if t > n / 2 else float(t)


## THE RING, UNROLLED FOR A VIEWER (the MAP ROOM's spine).
##
## RING.size() + 1 columns, left to right, in the sketch's own order: the seam
## tile is emitted TWICE — once at each end — so a reader can see that the two
## edges are the same place. Everything is a plain value; nothing here needs a
## world, which is what lets the map room draw the whole dive with no dive.
static func ring_overview(sv: int, tile_widths: float) -> Array:
	var out: Array = []
	var n := RING.size()
	var half := n / 2
	for col in range(-half, half + 1):
		var tile := posmod(col, n)
		out.append({
			"tile": tile,
			"offset": float(col),
			"kind": zone_kind(tile),
			"label": zone_label(tile),
			"wind": zone_wind(tile),
			"extra_pickets": zone_extra_pickets(tile),
			"start": tile == 0,
			# The seam is the column drawn at both ends — the loop, made visible.
			"seam": absi(col) == half,
			"chunks": chunk_count(sv, tile),
			# ...and who is already standing in it, before you ever fly there
			# (the pregenerated garrison, below) — most tiles now keep NOBODY,
			# because a depth's whole garrison stands around its landing column.
			"pickets": tile_picket_count(sv, tile, tile_widths),
		})
	return out


# --- THE ROCKS HAVE ROCKS IN THEM ------------------------------------------
#
# Owner, on the intermediate tiles: "perhaps with just more chunks of floating
# land". So every ROCK tile grows a handful of small floating slabs at each
# depth — content to dodge on the way down, and the reason the flanks are
# "harder to traverse" rather than merely windless.
#
# Pure, and deliberately so: the world stamps these lazily as you enter a tile,
# and the MAP ROOM draws the very same rows without a world in sight. Positions
# are in TILE-RELATIVE units (x in tile widths from the tile's own centre,
# altitude as an Airspace fraction), so nothing here knows about world_scale.

## How many slabs a rock tile grows at one depth, and how far out they may sit.
## Conservative on purpose: this is a slalom, not a wall.
const CHUNK_MIN := 2
const CHUNK_MAX := 4
## Half-width of the band a chunk may sit in, in TILE widths. Under 0.5 so a
## chunk never crosses into the neighbouring tile.
const CHUNK_SPAN := 0.34
## A chunk's own width, in tile widths, and how flat it is.
const CHUNK_W_MIN := 0.06
const CHUNK_W_MAX := 0.14
const CHUNK_ASPECT := 0.30
## How far a chunk drifts off its depth's rung, in rungs (±half of this).
const CHUNK_ALT_JITTER := 0.5
## Air kept clear at both ends of the ladder: no chunk above the launch deck's
## own altitude, none inside the lava. Altitude fractions.
const CHUNK_DECK_CLEAR := 0.02
const CHUNK_FLOOR_CLEAR := 0.02


## The floating slabs of rock tile `tile` at depth `d`. Empty for the updraft,
## the downdraft, depth 1 (the launch deck's own air is left alone) and any
## depth off the ladder.
static func tile_chunks(sv: int, tile: int, d: int) -> Array:
	var out: Array = []
	if zone_kind(tile) != "rock" or d < 2 or d > DEPTHS:
		return out
	var t := posmod(tile, RING.size())
	var span := CHUNK_MAX - CHUNK_MIN + 1
	var n := CHUNK_MIN + absi(hash([sv, "chunkn", t, d])) % span
	for k in n:
		var r := absi(hash([sv, "chunk", t, d, k]))
		var x := (float(r % 1000) / 1000.0 * 2.0 - 1.0) * CHUNK_SPAN
		var drift := (float((r >> 10) % 1000) / 1000.0 - 0.5) * CHUNK_ALT_JITTER * rung_frac()
		var alt := clampf(depth_altitude(d) + drift,
			FLOOR_FRAC + CHUNK_FLOOR_CLEAR, depth_altitude(1) - CHUNK_DECK_CLEAR)
		var w := CHUNK_W_MIN + float((r >> 20) % 1000) / 1000.0 * (CHUNK_W_MAX - CHUNK_W_MIN)
		out.append({"tile": t, "depth": d, "x": x, "alt": alt,
			"w": w, "h": w * CHUNK_ASPECT})
	return out


## How many slabs a tile carries over the whole ladder — the map room's per-tile
## readout, and a cheap way for a test to prove a rock tile is not empty.
static func chunk_count(sv: int, tile: int) -> int:
	var n := 0
	for d in range(2, DEPTHS + 1):
		n += tile_chunks(sv, tile, d).size()
	return n


# --- THE PREGENERATED GARRISON (owner 2026-09-01) ---------------------------
#
# "I don't really like how enemies just suddenly APPEAR. Again, perhaps we
# should pregenerate per seed, and only spawn things as the player is close
# enough, perhaps 2 screens away: (this would necessarily have to be computed
# based on whatever the ship's MAX ZOOM is)."
#
# So a run's STANDING POPULATION is decided the moment its seed is rolled, not
# the moment you arrive. Every ring tile at every rung below the launch deck
# carries a fixed roster of pickets at fixed places, and the world only gives
# them BODIES when a player comes within two screens of MAX ZOOM-OUT
# (`world.dive_materialize_px`). They are already there; you fly up on them.
#
# A DEPTH'S GARRISON IS `surge_count(d)` PICKETS IN TOTAL (owner call 3, review
# §5.1, v0.141.0), standing in the three tiles around that rung's LANDING COLUMN.
# It used to be `surge_count(d) + zone_extra_pickets(tile)` in EVERY tile, which
# under the owner's revised clear-ALL ruling (DESCENT §0) meant 48 pickets and
# ~12 minutes for one rung. Small and placed is the fix: the ring reads as "the
# fight is here, the loot is out there", the far tiles are optional country, and
# a rung is 45-75 s. `_dive_surge` (now an F2 verb only) still reads
# `zone_extra_pickets`; the standing garrison does not.
#
# Pure, and deliberately so — exactly like `tile_chunks`. The world materializes
# these rows and the MAP ROOM draws the very same rows with no world in sight,
# so "where will they be" is answerable without diving.
#
# DEPTH 1 IS EMPTY, for the same reason `tile_chunks` leaves it alone and the
# den's clock does not run there: the launch deck is an unhurried place while
# you choose a hull (`advance` returns early while `deepest <= 1`). A garrison
# standing around the deck would delete that.

## Half the band, in TILE widths, that a tile's pickets are spread across. Under
## 0.5 so a picket never stands in the neighbouring tile.
const GARRISON_X_SPAN := 0.42
## The smallest gap between two pickets of one tile, in tile widths. At the 8×
## ring's 33,600 px tile that is ~3,400 px — a couple of gunboat lengths, which
## is what stops the owner's "their ships are literally stuck to each other".
## Slots narrower than this (a very crowded depth) fall back to the slot width,
## which `garrison_min_sep` reports so a test can hold the real invariant.
const GARRISON_MIN_SEP := 0.10
## How far a picket hangs off its depth's rung, in rungs (±half of this). Under
## 1 so a picket always belongs to the rung it was rolled for.
const GARRISON_ALT_JITTER := 0.7
## Air kept clear at both ends of the ladder: nothing above the launch deck's own
## altitude, nothing in the lava. Altitude fractions.
const GARRISON_DECK_CLEAR := 0.02
const GARRISON_FLOOR_CLEAR := 0.02


## WHICH RING TILE THIS DEPTH'S LANDING COLUMN SITS IN. `landing_offset` is in
## SHELF widths and a tile is `tile_widths` shelves across, so the division is
## the landing's position in tile widths and `zone_index` rounds it to the tile
## it is standing in. `tile_widths` is passed in (F2 `dive_zone_tile_widths`)
## rather than read, because this file stays pure — the world and the MAP ROOM
## both hand it the same lever and so cannot disagree about where the fight is.
static func landing_tile(sv: int, d: int, tile_widths: float) -> int:
	return zone_index(landing_offset(sv, d) / maxf(tile_widths, 0.001))


## HOW MANY PICKETS TILE `tile` KEEPS AT DEPTH `d` — the depth's WHOLE garrison,
## shared out among three tiles (owner call 3, review §5.1).
##
## The old table added `surge_count(d)` to `zone_extra_pickets(tile)` in EVERY
## tile, which with the owner's revised clear-ALL ruling (DESCENT §0) came to 48
## pickets at depth 2 — ~12 minutes of a single rung. A depth is worth
## `surge_count(d)` pickets IN TOTAL now, and they stand in the three tiles
## around that depth's LANDING COLUMN: the fight is where you are going, and the
## rest of the ring is optional country (wrecks, scrap, an outpost, a whale).
##
## Round-robin from the CENTRE tile out, so 4 splits 2/1/1 and 3 splits 1/1/1 —
## the landing's own tile is never the light one.
static func garrison_count(sv: int, tile: int, d: int, tile_widths: float) -> int:
	if d < 2 or d > DEPTHS:
		return 0
	var n := RING.size()
	var t := posmod(tile, n)
	var lt := landing_tile(sv, d, tile_widths)
	var order := [lt, posmod(lt - 1, n), posmod(lt + 1, n)]
	var mine := 0
	for k in surge_count(d):
		if int(order[k % order.size()]) == t:
			mine += 1
	return mine


## What a tile carries over the whole ladder — the map room's per-tile readout,
## and the twin of `chunk_count`. SEED-DEPENDENT since v0.141.0: the seed decides
## where each rung's landing column falls, and the garrison follows the landing.
static func tile_picket_count(sv: int, tile: int, tile_widths: float) -> int:
	var n := 0
	for d in range(2, DEPTHS + 1):
		n += garrison_count(sv, tile, d, tile_widths)
	return n


## The GUARANTEED smallest gap between two of a tile's `n` pickets, in tile
## widths. `GARRISON_MIN_SEP` when the slots are wide enough to hold it, the slot
## width otherwise — stated as a function rather than a constant so the suite can
## pin the invariant that actually holds instead of the one we hoped for.
static func garrison_min_sep(n: int) -> float:
	if n <= 1:
		return 0.0
	return minf(GARRISON_MIN_SEP, 2.0 * GARRISON_X_SPAN / float(n))


## A stable name for one garrison entry. The run marks these SPAWNED (see
## `mark_garrison_spawned`), so the key has to survive being written down.
static func garrison_key(tile: int, d: int, k: int) -> String:
	return "%d:%d:%d" % [posmod(tile, RING.size()), d, k]


## WHO STANDS IN TILE `tile` AT DEPTH `d`, as [{key, tile, depth, index, kind,
## x, alt}]. `x` is in TILE widths from that tile's own centre and `alt` is an
## Airspace fraction, so nothing here knows about `world_scale` — the same
## contract `tile_chunks` keeps.
##
## SPACED BY CONSTRUCTION. The band is cut into `n` equal slots and a picket
## jitters inside its own slot by at most half the slack, so two of them can
## never be closer than `garrison_min_sep(n)` however the hash falls. The world's
## spawn path may still nudge a body by its real `solid_bounds` — this only has
## to stop the MODEL stacking them.
static func tile_garrison(sv: int, tile: int, d: int, tile_widths: float) -> Array:
	var out: Array = []
	var t := posmod(tile, RING.size())
	var n := garrison_count(sv, t, d, tile_widths)
	if n <= 0:
		return out
	var kinds := surge_kinds(d)
	var slot := 2.0 * GARRISON_X_SPAN / float(n)
	var jitter := maxf(0.0, (slot - garrison_min_sep(n)) * 0.5)
	var ceiling := depth_altitude(1) - GARRISON_DECK_CLEAR
	for k in n:
		var r := absi(hash([sv, "garrison", d, t, k]))
		var mid := -GARRISON_X_SPAN + slot * (float(k) + 0.5)
		var x := mid + (float(r % 1000) / 1000.0 * 2.0 - 1.0) * jitter
		var drift := (float((r >> 10) % 1000) / 1000.0 - 0.5) * GARRISON_ALT_JITTER * rung_frac()
		var alt := clampf(depth_altitude(d) + drift,
			FLOOR_FRAC + GARRISON_FLOOR_CLEAR, ceiling)
		out.append({
			"key": garrison_key(t, d, k),
			"tile": t, "depth": d, "index": k,
			"kind": String(kinds[k % kinds.size()]),
			"x": x, "alt": alt,
		})
	return out


## THE WHOLE GARRISON of a seed, every tile at every rung. The map room draws
## this; the world never asks for it (it scans the tiles around you instead —
## see `world._dive_materialize_garrison`).
static func garrison_all(sv: int, tile_widths: float) -> Array:
	var out: Array = []
	for tile in RING.size():
		for d in range(2, DEPTHS + 1):
			out.append_array(tile_garrison(sv, tile, d, tile_widths))
	return out


# --- WHERE THE PLAYERS ARE (owner 2026-09-01) -------------------------------
#
# "It would have to be the boundary of all active players as if they were using
# a ship's MAX ZOOM."
#
# So the two distances a materialization is judged by are both measured against
# EVERY active body, not against "the player":
#
#   * the INCLUSION radius is the distance to the NEAREST player — anybody who
#     could see it is reason enough for it to exist;
#   * the EXCLUSION bubble is that same nearest distance held OUTSIDE a max-zoom
#     view — nothing may be born inside anyone's widest possible frame, because
#     that is the pop-in the owner is complaining about.
#
# Pure, taking plain positions, so the world site and the suite share exactly
# one piece of arithmetic and a two-player case needs no second body to test.

## Distance from `pos` to the NEAREST of `points`, or INF when there is nobody to
## be near (a world mid-teardown decides nothing — the same convention
## `Dormancy.distance_to_nearest` keeps).
static func nearest_distance(pos: Vector2, points: Array) -> float:
	var best := INF
	for p in points:
		best = minf(best, pos.distance_to(p as Vector2))
	return best


## May a garrison entry at `pos` be given a body right now? Inside somebody's
## `reach`, and outside EVERYBODY's `keep_out` bubble.
static func in_materialize_band(pos: Vector2, points: Array,
		keep_out: float, reach: float) -> bool:
	if points.is_empty():
		return false
	var d := nearest_distance(pos, points)
	return d > keep_out and d <= reach


## Push `pos` along `dir` until it is `keep_out` clear of every player — what the
## den's pulse uses when its lead down YOUR travel vector would land it inside
## somebody else's frame. Bounded (four passes): each pass moves by the worst
## shortfall, and a surge that still cannot find air is one the world skips.
static func clear_of_players(pos: Vector2, dir: Vector2, points: Array,
		keep_out: float) -> Vector2:
	if points.is_empty() or dir.length_squared() <= 0.0:
		return pos
	var step := dir.normalized()
	var out := pos
	for _pass in 4:
		var short := 0.0
		for p in points:
			short = maxf(short, keep_out - out.distance_to(p as Vector2))
		if short <= 0.0:
			return out
		out += step * (short + 1.0)
	return out


# --- The garrison's live half (this run's bookkeeping) ----------------------

## Garrison entries this run has already given a body, by `garrison_key`.
##
## SPAWN-ONCE IS THE WHOLE RULE, and it is also the owner's "a cleared sky stays
## cleared": an entry the wake cull frees (or that you blew apart) is marked and
## never comes back, while an entry you simply never flew near stays pending for
## as long as the run lasts. Nothing here is saved — a run is not a save file.
var garrison_spawned := {}


func garrison_is_spawned(key: String) -> bool:
	return garrison_spawned.has(key)


func mark_garrison_spawned(key: String) -> void:
	garrison_spawned[key] = true
