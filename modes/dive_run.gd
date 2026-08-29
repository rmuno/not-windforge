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
var elapsed := 0.0
## "" while running, then one of "escaped" / "lost" / "triumph".
var outcome := ""

var _grace := ARRIVAL_GRACE   ## seconds until this depth's den comes for you
var _seen := {1: true}        ## depths already arrived at (the surge arms once)
var _leviathan_called := false


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
## world can float the number over the corpse.
func credit_kill(kind: String) -> int:
	if outcome != "":
		return 0
	var coins := coins_for(kind, depth)
	pot += coins
	kills += 1
	return coins


## The ship is gone. The run is over and the pot burns with it.
func lose() -> void:
	if outcome == "":
		outcome = "lost"
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
		"depth": depth,
		"deepest": deepest,
		"deepest_label": depth_label(deepest),
		"pot": pot,
		"banked": banked,
		"kills": kills,
		"surges": surges,
		"elapsed": elapsed,
		"surge_in": surge_in(),
	}


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
			return "YOUR SHIP IS GONE. You reached %s. %d coins fell with it." % [
				String(l.get("deepest_label", "")), int(l.get("pot", 0))]
	return ""
