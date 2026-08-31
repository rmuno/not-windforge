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

## Extraction line. Climbing back to depth 1's air is the escape; it is the same
## altitude you started at, which is the point — the way home is the way you
## came, and you have to fly all of it.
const EXTRACT_FRAC := TOP_FRAC

## The grace after arriving somewhere new before that depth's den notices you.
## This is the "calm" half of the beat — mine, build, patch gasbags, breathe.
const ARRIVAL_GRACE := 30.0

## DYING ABOARD. The owner ruled that dying on foot respawns you on the deck
## "at a cost"; this is the cost, and the cap that stops it being a loop.
##
## The cap is not decoration. The headless playtest (tools/dive_probe.gd) drove a
## run to depth 6, where the air is already unbreathable (Airspace.DEEP_TOP is
## 0.34 and that rung sits at 0.317) — the pilot suffocated, respawned on the
## deck still in unbreathable air, and the run stalled there dying forever. With
## a cap the air gate becomes a countdown you can feel instead of a wall you
## bounce off, and the way past it is the kit an outpost sells.
const DEATH_LIMIT := 3
const DEATH_POT_LOSS := 0.35

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
}
const BASE_COIN := 20

## Coin scaling with depth: a kill at depth d is worth base × (1 + DEPTH_COIN ×
## (d − 1)). Deeper things are worth more BEFORE the extraction premium, so the
## greed has two reasons and the player feels both.
const DEPTH_COIN := 0.35

# --- Live run state ---------------------------------------------------------

var depth := 1          ## where you are right now (1..DEPTHS)
var deepest := 1        ## the headline number: how far down you got
var pot := 0            ## coins carried and NOT yet banked — burns with the ship
var banked := 0         ## what reached the permanent wallet (set when the run ends)
var kills := 0
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
var _grace := ARRIVAL_GRACE   ## seconds until this depth's den comes for you
var _seen := {1: true}        ## depths already arrived at (the surge arms once)
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


## HOW FAST A RUN LETS A HULL FALL (owner 2026-08-30: "it'd just be nice if it
## wasn't so FORCED to descend so fast, then, on the ship during dive mode i
## guess. or it falls too fast").
##
## Measured on the shipped hull, holding the stick down in clear air: 4,220 px/s
## after one second, terminal 6,704. A screen is about 4,200 px tall at the
## shipped zoom, so the hull crossed **more than a screen and a half every
## second** — nothing legible, nothing dodgeable, the ladder a flicker. And with
## the stick NEUTRAL it still sank at 2,389 px/s and rising, which is the FORCED
## half: lift is a function of air density, high air is thin, and a hull that
## floats at the surface simply falls. The stick had no meaning.
##
## Two numbers fix it, and they live here rather than in the world so the
## arithmetic is testable without dragging `world.gd` — and its `Net` autoload —
## into a test's compile graph (the trap `pause_menu.gd` and `title_screen.gd`
## both carry scars from).
##
## `DESCENT_BLEED` is why the limit is EASED rather than clamped: the excess over
## the cap bleeds off per second, so pushing down still accelerates and the limit
## arrives as thick air, not a wall. **20, not 4** — an eased limit settles where
## the bleed balances the hull's own acceleration (`settles_at` below), and at 4
## that was a thousand px/s over the number, which made the cap decorative.
const DESCENT_BLEED := 20.0
## What the cap becomes with the stick NEUTRAL, as a fraction of the driven cap.
## Letting go is a slow sink you can read; pushing down is three times that.
const DRIFT_FRACTION := 0.34


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


## THE TOP OF THE LADDER IS THIN AIR (owner 2026-08-30: "now it's a little too
## slow between layers 1 and 2, then 2 & 3?").
##
## One cap for the whole shaft made the shallow rungs a commute: they are the
## emptiest part of a run — the garrison is smallest and there is nothing to dodge
## — so the same speed that reads as tense at the floor reads as dead time at the
## top. It also had no physical excuse, which is the tell. THIN AIR IS THE
## EXCUSE, and it was already in the model: lift falls with air density, which is
## why a hull sinks on a neutral stick up high in the first place. Thin air is
## also less to push through.
##
## So the cap is `DESCENT_TOP_MULT` at depth 1 and 1.0 at the floor, straight
## line between. The descent opens fast and thickens as you go — which is the
## shape the mode wants anyway: the deep should feel like it is closing in.
const DESCENT_TOP_MULT := 2.1
static func descent_depth_mult(d: int) -> float:
	if DEPTHS <= 1:
		return 1.0
	var t := float(clampi(d, 1, DEPTHS) - 1) / float(DEPTHS - 1)
	return lerpf(DESCENT_TOP_MULT, 1.0, t)


## The cap that applies right now, in px/s, for a hull whose helm axis is `axis`
## (negative is DOWN — `Input.get_axis("ship_down", "ship_up")`).
static func descent_cap(base: float, axis: float) -> float:
	return base if axis <= -0.1 else base * DRIFT_FRACTION


## One frame of the bleed: `vy` eased toward `cap`, never past it, never upward.
static func bleed_descent(vy: float, cap: float, delta: float) -> float:
	if cap <= 0.0 or vy <= cap:
		return vy
	return maxf(cap, vy - (vy - cap) * minf(1.0, DESCENT_BLEED * delta))


## Where an eased cap actually SETTLES for a body accelerating downward at
## `accel` px/s². This is the arithmetic the first cut got wrong, so it is a
## function rather than a comment: a bleed that loses to gravity is a cap in
## name only.
static func settles_at(cap: float, accel: float) -> float:
	return cap + accel / maxf(DESCENT_BLEED, 0.001)


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
		"label": "Hull patch — mend her where she stands"},
	{"id": "balloon", "cost": 90,
		"label": "Large balloon — more lift, tether it with Q"},
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


## How many hunters a depth's den throws at you in one surge. Deliberately gentle
## at the top and unreasonable at the bottom — the ladder IS the difficulty
## curve, so nothing else has to be.
static func surge_count(d: int) -> int:
	return clampi(1 + int(floor(float(clampi(d, 1, DEPTHS) - 1) * 0.5)), 1, 5)


## The name of a depth, for the HUD and the ledger. Depth DEPTHS is not a number
## to the player; it is the place the Leviathan lives.
static func depth_label(d: int) -> String:
	if d >= DEPTHS:
		return "THE FLOOR"
	return "DEPTH %d" % clampi(d, 1, DEPTHS)


# --- The run ----------------------------------------------------------------

## Advance the run by `delta` at altitude fraction `a`, with `surge_period`
## seconds between a depth's attacks. Returns the events the world must act on,
## in order:
##
##   "depth"     — you reached a NEW deepest depth (announce it; arm the den)
##   "surge"     — this depth's den comes for you now (spawn the hunters)
##   "leviathan" — you have arrived at the floor; wake the boss (once)
##   "escaped"   — you climbed back out alive; the pot is banked
##
## Returns nothing at all once the run is over — a finished run is inert, so a
## world that keeps ticking it (and one does, for the ledger) costs nothing.
func advance(delta: float, a: float, surge_period: float) -> Array:
	if outcome != "":
		return []
	var out: Array = []
	elapsed += delta
	depth = depth_of(a)
	if depth > deepest:
		deepest = depth
	if not _seen.has(depth):
		_seen[depth] = true
		_grace = ARRIVAL_GRACE
		out.append("depth")
	if depth >= DEPTHS and not _leviathan_called:
		_leviathan_called = true
		out.append("leviathan")
	# The den's clock. It runs everywhere, but arriving somewhere new resets it,
	# so the beat is always "get there, breathe, then they come".
	#
	# THE DOCK IS SAFE UNTIL YOU HAVE BEEN DOWN. While you have never left the
	# top rung the clock does not run at all, so choosing a ship on the launch
	# deck is unhurried. Come back up here to extract, though, and `deepest` is
	# long past 1 — the way home is not a safe place, which is the point.
	if deepest <= 1:
		return out
	_grace -= delta
	if _grace <= 0.0:
		_grace = maxf(surge_period, 1.0)
		surges += 1
		out.append("surge")
	# The escape. Only after you have actually been down — otherwise sitting at
	# the start line would end the run before it began.
	if a >= EXTRACT_FRAC and deepest > 1:
		outcome = "escaped"
		banked = bank_value(pot, deepest)
		out.append("escaped")
	return out


## Credit a kill of `kind` at the current depth. Returns the coins added, so the
## world can float the number over the corpse. The kill also feeds the CARD XP bar
## (a kill's coin value is its XP), and every bar filled owes a draft.
func credit_kill(kind: String) -> int:
	if outcome != "":
		return 0
	var coins := coins_for(kind, depth)
	pot += coins
	kills += 1
	_gain_xp(coins)
	return coins


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


## The proc effects the held cards fire on `event`, as [{effect, amount}, ...].
func procs_for(event: String) -> Array:
	return DiveCards.procs_for(cards, event)


## A death with a deck to wake up on. Burns part of the pot; the DEATH_LIMIT-th
## one ends the run. Returns true when it did.
func perish_aboard() -> bool:
	if outcome != "":
		return true
	deaths += 1
	pot = maxi(0, int(round(float(pot) * (1.0 - DEATH_POT_LOSS))))
	if deaths >= DEATH_LIMIT:
		outcome = "lost"
		lost_how = "worn"
		banked = 0
		return true
	return false


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


## Seconds until this depth's den attacks (0 while a run is over).
func surge_in() -> float:
	return 0.0 if outcome != "" else maxf(_grace, 0.0)


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
		"surges": surges,
		"elapsed": elapsed,
		"surge_in": surge_in(),
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


## The current draft offer as painter-ready rows: [{id, name, desc}, ...], empty
## when nothing is on offer.
func draft_view() -> Array:
	var out: Array = []
	for id in draft:
		out.append({"id": id, "name": DiveCards.name_of(String(id)),
			"desc": DiveCards.desc_of(String(id))})
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
					return "THE DEEP WORE YOU DOWN at %s. %d coins left aboard." % [
						String(l.get("deepest_label", "")), int(l.get("pot", 0))]
			return "YOUR SHIP IS GONE. You reached %s. %d coins fell with it." % [
				String(l.get("deepest_label", "")), int(l.get("pot", 0))]
	return ""
