extends SceneTree

## THE DIVE, PLAYED. A headless playtest of a whole run on the REAL shipped 8x
## scene: start a run on the launch deck, take a hull, fly it down the ladder
## with real input, and report what the run actually felt like in numbers —
## seconds per depth, when the dens attacked, what the pot did, whether the
## hull survived.
##
##   godot --headless --path . --script tools/dive_probe.gd
##   godot --headless --path . --script tools/dive_probe.gd -- --seed 892583619
##
## The second form pins the run's seed (`world.pin_dive_seed`), which is the only
## way two of these numbers are comparable: a run rolls a fresh seed, and since
## v0.154.0 that seed decides the ground as well as the ladder. Every run prints
## its own SEED — feed it back in to fly the same dive again.
##
## This is a PROBE, not a test: it measures, it does not assert. The numbers it
## prints are the ones nothing but arithmetic has judged — how long a depth
## takes at ship speed, how many PICKETS a depth actually puts in your way now
## that the timer surge is retired (v0.141.0) and a depth's garrison is
## `surge_count(d)` around its landing column, whether a run fits the owner's
## ten minutes.
##
## THE PILOT FLIES LIKE A CAREFUL PLAYER (v0.149.0). Every run before this one
## ended `lost / worn` at DEPTH 2, 33-60 s in, hull 4,464 blocks -> 0 (one run:
## 787,117 damage over 57 collision hits), because the autopilot held DOWN at the
## full 1,920 px/s stick rate and steered STRAIGHT AT `dive_landing_pos(d + 1)` —
## which is not a waypoint in clear air, it is a 1,600 px-thick stone slab. The
## hull ground itself away on the rungs and the floating rock, exploded, and the
## body fell and died. Every seconds-per-depth number past depth 2, and the whole
## kraken scorecard, was measuring that keyboard habit and not the game.
##
## THAT PILOT STILL FLEW INTO ROCK (v0.161.0). Measured on the three scorecard
## seeds it ended `terrain 100 %` of the hull bill every time — depth 2, 2 and 3,
## crash bills of 2.1 M, 0.7 M and 5.8 M — so depths 4-8, the kraken half of the
## ladder and the Leviathan were all UNMEASURED, and DESIGN_KRAKEN slice 7 waits
## on exactly those numbers. Two things were wrong and both were geometry:
##
##   * the lookahead was a ray down the CENTRE LINE of a 1,536 × 1,152 px body.
##     A hull sliding out of a blocked column while still sinking travels
##     DIAGONALLY at ~1,400 px/s and meets the slab with its SHOULDER; a centre
##     ray passes through the gap the shoulder does not fit through. Every crash
##     log ends with `closest the keel ever came to rock: 0 px` — the pilot never
##     saw it at all;
##   * the descent rate came from a fixed two-second lookahead rather than from
##     what this hull can actually stop out of, so the pad was fiction: no term
##     in it was the hull's authority, its mass, its air or its damage.
##
## What flies it now, in five rules (`_fly`, arithmetic in `tools/pilot_nav.gd`):
##   1. LOOK WHERE YOU ARE GOING. A FAN of rays — five origins across the hull's
##      skin, three directions each — down the heading, down the velocity vector
##      and straight down, every tick. Rays start on the hull's SURFACE, not at
##      its centre: a clearance measured from the middle of this body is
##      three-quarters of a hull optimistic, which is the size of the pad itself.
##   2. FLY THE SPEED THE ROOM ALLOWS. `PilotNav.safe_speed(room)` is the exact
##      inverse of `stopping_distance(v)`, and the deceleration in it is
##      MEASURED off this hull this run (`_measure_brake`: pressing UP commands
##      `+climb_rate_max`, so the largest deceleration ever seen while the up
##      stick was held is this hull's real authority, brownout and battle damage
##      included), with a 30 % margin. The stick is on/off, so the commanded rate
##      is flown bang-bang against the hull's own `linear_velocity.y`.
##   3. GO AROUND, DON'T PUSH THROUGH. Seven candidate headings are scored every
##      tick by `PilotNav.heading_score`, in which room MULTIPLIES the score — so
##      a blocked heading is worth zero however well it points at the next rung,
##      and the pilot can never talk itself into a wall because the wall lies
##      toward the lane. Sideways has its own stopping distance and no rate
##      controller to fly it, so when the room on that side runs short the
##      lateral stick REVERSES (thrust is the only sideways brake a hull has).
##   4. NOTICE WHEN NOTHING IS WORKING. If the deepest y reached has not improved
##      in STUCK_SECS the column is a dead end: climb out for ESCAPE_SECS, commit
##      to the OTHER side of the next slab (`_lane_flip`) and re-plan. The
##      seconds spent doing it are REPORTED per rung — a pilot that spends the
##      run escaping is measuring itself again, and the reader has to see that.
##   6. THE AIR IS MEASURED, NOT FOUGHT. The rate stick commands a speed
##      RELATIVE TO THE AIR, so a column of falling air adds its speed to every
##      descent and takes it off every brake. The ladder's wind columns run at
##      1,000 px/s against a full up-stick worth 960 (`dive_climb_rate` 120 × 8),
##      so inside one NO stick stops the descent. The probe REPORTS that time
##      ("carried by air no stick can beat") rather than steering around it: a
##      cut that turned the vertical over and ran sideways instead lost the hull
##      at depth 1 in 19 s, because a wall of the ladder is something you punch
##      through, not something you loiter beside. Which of the two a player
##      should do is the ladder's design question, not the autopilot's.
##   5. FIGHT BACK, AND GIVE THE WILDLIFE ROOM — unchanged from v0.149.0. A
##      volley at the nearest hostile inside max-zoom sight every
##      `turret_cadence`, aimed at a kraken's MEAT and anything else's middle;
##      and a bubble kept off everything except krakens, because one neutral
##      whale gliding into the hull at descent speed cost 39,978 damage in a
##      single frame. A hunter reaching you is the thing this probe TIMES, so
##      krakens are never dodged.
##
## Names no `class_name` as a type on purpose: doing that inside a --script file
## compiles that script before the autoloads exist (CODEMAP §4).

const STEP := 1.0 / 60.0

## Air the pilot keeps around the hull at all times, in ship cells (× world
## scale). Inside it the answer is "stop", never "a bit less of the same".
const KEEL_PAD_CELLS := 8.0
## Seconds of command lag the pilot budgets for before its braking bites — the
## reaction term of `PilotNav.stopping_distance`. A bang-bang stick decides on
## one physics frame and is read on the next, and the props then spend a frame
## or two turning the descent's momentum around.
const REACTION := 0.30
## Rays across a fan's face, and how far to either side of the heading the fan
## spreads. Five origins across a 1,536 px beam is one every ~350 px, which is
## finer than any gap the hull could fit through anyway.
const FAN_RAYS := 5
const FAN_SPREAD := 0.38          ## radians, ~22°
## THE CANDIDATE HEADINGS the pilot chooses between every tick: straight down,
## two shallow diagonals, two sideways lanes that still sink, and two that climb
## out to the side. Normalised at use.
const HEADINGS := [
	Vector2(0.0, 1.0), Vector2(-0.5, 1.0), Vector2(0.5, 1.0),
	Vector2(-1.0, 0.45), Vector2(1.0, 0.45),
	Vector2(-1.0, -0.35), Vector2(1.0, -0.35),
]
## How far a fan looks: the hull's own stopping distance with a margin, floored
## so a stationary hull still sees the room it is about to move into.
const HORIZON_MULT := 2.0
const HORIZON_MIN_CELLS := 24.0
## How much more room than the arithmetic demands the pilot insists on before it
## will fly a speed. The stopping distance is honest but it is not conservative:
## the crash that survived the first cut of this pilot read "keel sees 5,054 px,
## needs 5,078" — inside one per cent, and lost. A third again is cheap now that
## the ladder's columns carry a descent at ~1,900 px/s anyway.
const SAFETY := 1.35
## Scoring weights (`PilotNav.heading_score`) and the hold that stops the pilot
## dithering on the crest of a slab it is trying to leave.
const DOWN_WEIGHT := 0.75
const LANE_WEIGHT := 0.35
const HEADING_HOLD := 0.12
const HEADING_HOLD_SECS := 1.5
## Bang-bang dead band on the commanded descent rate, px/s.
const RATE_HYST := 60.0
## THE STUCK DETECTOR. If the deepest y reached has not improved by
## STUCK_GAIN_PX inside STUCK_SECS the column the pilot chose is a dead end:
## climb out for ESCAPE_SECS, commit to the OTHER side of the next slab, and
## let the heading search start again from up there.
const STUCK_GAIN_PX := 900.0
const STUCK_SECS := 14.0
const ESCAPE_SECS := 6.0
## The deceleration the pilot assumes before it has measured any (px/s²), and
## the margin it keeps off what it has measured.
const DECEL_PRIOR := 500.0
const DECEL_MARGIN := 0.7
## A terrain contact EPISODE that bills more than this is a CRASH; anything less
## is a graze. The per-depth crash count is the line that says whether the pilot
## is flying the ladder or bouncing down it.
const CRASH_HP := 500.0
## Hard stop, simulated seconds. The owner's design budget for a whole run is
## ten minutes; this is two minutes of slack on top so a run that overruns is
## REPORTED as an overrun rather than truncated into one.
const RUN_GUARD := 60.0 * 12.0

## The scorecard's arithmetic, kept apart so the SUITE can check it (Q-O: the
## four candidates are ranked off these percentages, so a wrong denominator is a
## wrong design decision). Loaded BY PATH rather than by `class_name`: a
## `--script` file that names a class as a type compiles that script — and
## anything it touches — before the autoloads exist (CODEMAP §4). This one
## touches nothing at all, so the preload is safe and the cache is irrelevant.
const Score := preload("res://tools/combat_score.gd")
## THE PILOT'S NAVIGATION ARITHMETIC, kept apart for the same reason and loaded
## the same way: stopping distance, the ray fan's geometry and the heading score
## decide whether the deep is ever REACHED, so "the pilot flew into rock" must
## not be a possible reading of "the deep is unreachable".
const Nav := preload("res://tools/pilot_nav.gd")

var world: Node
var fleet
var pl

# Combat scorecard tallies (Q-O). `hits_taken` counts DAMAGE EVENTS on our hull
# from every source; the shell ledger below is what counts gunnery.
var hits_taken := 0
var damage_taken := 0.0
var enemy_shots := 0
var shots_fired := 0        ## OUR volleys — the line that says the pilot shot at all

# --- THE SHELL LEDGER (Q-O, v0.157.0) --------------------------------------
# "Enemy shells fired vs hits on us" used to divide two numbers that are not
# about the same thing: `enemy_shots` counted shells born, while `hits_taken`
# counted every `damaged` event on our hull — a terrain crush, a whale ram and a
# kraken chew all inflated the "hit rate" of enemy GUNNERY, and one shell that
# lands on a 64-cell component fires `damaged` once but was never comparable to
# a shell in flight. So the printed hit % was not a hit %.
#
# Now every shell books its own outcome (`Shot.spent`, added for this): who
# fired it (its faction) and what stopped it (an enemy hull, our hull, a person,
# rock, or nothing at all). Fired and landed are then the same population
# counted twice, which is what a rate needs.
#
# Keyed by the SHOOTER'S FACTION so every line is attributable: 0 = ours,
# 1 = hostile crewed vessels, 2 = creatures, 3 = wrecks.
var shells_fired := {}          ## faction -> shells born
var shells_landed := {}         ## faction -> shells that dealt damage to somebody
var shells_dealt := {}          ## faction -> damage those shells dealt
var shells_why := {}            ## "faction|reason" -> count (terrain / blocked / expired)
var shells_onto := {}           ## "faction|what it hit" -> count
var shells_fired_d := {}        ## "depth|faction" -> shells born at that rung
var shells_landed_d := {}       ## "depth|faction" -> shells that landed at that rung
## A BASILISK'S SPIT IS NOT A SHELL. It is a `HazardFireball` — a different
## system with its own integrator — and the garrison puts basilisks at depths 3
## and 5 (`DiveRun.SURGE_LADDER`). Counted separately so "enemy fire" does not
## quietly mean "enemy fire except the fire".
var spits_fired := 0
var spits_landed := 0           ## on ANY ship or person (a hazard has no faction)
var spits_on_us := 0
var spits_dealt_us := 0.0
var _scoring := false           ## the books are open (the descent, not the deck)
var _depth_now := 1

# --- WHO WE FOUGHT, AND WHAT IT COST TO KILL THEM ---------------------------
# TIME TO KILL, per picket kind, needs three things the probe never kept: which
# body a shell of ours landed on, when the first one landed, and the moment that
# body died. Death is exact rather than inferred: an exploded VESSEL is not
# freed, it is stripped to a husk and re-flagged `Ship.FACTION_WRECK`
# (`world._dive_leave_a_husk`), and a CREATURE dies when its shared pool empties
# (`Ship.is_carcass`). A body that leaves the fleet with neither having happened
# was CULLED alive, and must never be averaged in as a kill.
var foes := {}                  ## instance id -> the book on one hostile body
var kills_booked: Array[Dictionary] = []
var foes_gone_alive := 0

# --- ENGAGEMENTS ------------------------------------------------------------
# "Damage taken per surge" cannot be measured any more: the timer surge is
# retired (v0.141.0) and a run normally has zero of them. The honest unit is an
# ENGAGEMENT — a contiguous stretch with at least one live hostile inside the
# same 4k×8 range the THREAT line already uses, closed after ENGAGE_TAIL seconds
# of nobody in range so one picket weaving in and out is one fight.
const ENGAGE_RANGE := 4000.0 * 8.0
const ENGAGE_TAIL := 4.0
var engagements: Array[Dictionary] = []
var _engage := {}
var _engage_quiet := 0.0
## The union of every engagement, in seconds — merged, so three pickets on you
## at once for ten seconds is ten seconds of fighting and not thirty.
var _engage_spans: Array = []

# --- CONTACT ----------------------------------------------------------------
## depth -> seconds from entering it until the first LIVE hostile of any kind
## came inside ENGAGE_RANGE. The kraken table next to it answers the same
## question for the deep alone; this one answers "does anything ever arrive".
var first_contact := {}
var closest_by_kind := {}       ## kind -> the nearest that kind ever came, px
var closed_to_gun := {}         ## kind -> distinct bodies that reached firing range
var met_of_kind := {}           ## kind -> distinct bodies met at all
## Frames with a live kraken inside GRAB REACH of the hull — the denominator the
## grab number was missing. A hunter that never arrived cannot be blamed for not
## grabbing, and one that rode us for a minute and chewed for two seconds is a
## different problem entirely.
var kraken_reach_frames := 0

# --- WHAT IS EATING THE HULL (v0.149.0) ------------------------------------
# The scorecard attributed krakens and nothing else, so "the pilot flew into a
# slab" and "a gunboat shot us" arrived as one number. Three buckets now, and
# the attribution is the same shape the kraken one already had: a per-frame
# stamp of WHO WAS ON US, read by the `damaged` handler.
#
# TERRAIN gets a short tail (`TERRAIN_TAIL`) on purpose: a crush is RECORDED in
# `_integrate_forces` and BILLED on a later idle frame (`Ship._process`), by
# which time the contact may already have separated. Without the tail the
# hull's own crash damage lands in the "shells" bucket.
const TERRAIN_TAIL := 0.35
var dmg_terrain := 0.0
var dmg_shells := 0.0
var dmg_kraken := 0.0
var dmg_ram := 0.0          ## another HULL hit us (or we hit it) — see `_ram_who`
var _terrain_recent := 0.0
var _ram_recent := 0.0
var _ram_who := ""
var terrain_hits := 0
var ram_hits := 0
## CRASHES, PER RUNG. `terrain_hits` counts every contact EPISODE, graze and
## catastrophe alike, so a run that brushed a slab twice and a run that buried
## itself in one print the same number. A crash is an episode that billed more
## than CRASH_HP; the count is kept per depth because "the pilot cannot fly
## depth 5" and "the pilot cannot fly at all" want different fixes.
var crashes_d := {}         ## depth -> terrain episodes that billed over CRASH_HP
var crashes_total := 0
var _terrain_bill := 0.0    ## what the OPEN terrain episode has billed so far
var crash_worst_d := {}     ## depth -> the biggest single episode bill there
## ...and how many of those crashes the hull was already FALLING into (see
## `falls`): a powerless hull hitting the floor is not a flying mistake, and it
## is usually the biggest bill in the run.
var crash_fall_d := {}
var _fall_until := -1.0
var _t := 0.0               ## the loop's clock, readable from the `damaged` handler
## Every single damage event over BIG_HIT, with what was touching the hull when
## it landed. One frame of hull-on-hull contact can bill five figures at 8×, and
## a total alone cannot tell that from a minute of being shot at.
const BIG_HIT := 500.0
var big_hits: Array[String] = []
## The crush, off `Ship.collision_damage` — what contacts actually spent on the
## grid, with no contact-stamp guessing in the way.
var crush_events := 0
var crush_spent := 0.0

# --- THE KRAKEN SCORECARD (DESIGN_KRAKEN §7 slice 2) -----------------------
# "Every later round tunes against them": four numbers the deep has never been
# measured by. All four are read off the LIVE brains and bodies, so they answer
# for what the fight did, not for what the spawn tables intended.
#
#   * TIME TO FIRST CONTACT — entering a depth, to the first frame a kraken has
#     hold of you or is standing on your hull. Infinite at every depth is the
#     bug this whole slice is about (designer C's arithmetic: the old
#     horizontal-only heave cannot reach a hull that is falling).
#   * GRABS — rising edges of `KrakenAI.grabbing`, per minute, longest hold.
#   * INTEGRITY LOST TO KRAKENS — the grab's drain and the ram's bruise, split
#     out of the total by "was a kraken on us this frame".
#   * CULLED ALIVE — krakens the wake cull FREED while they still had a pool.
#     Measured from outside `_dive_cull_the_wake` on purpose (a body that
#     vanishes with health left was deleted, not killed), so this line reads
#     the same before and after that function is ever touched.
var kraken_first_contact := {}     ## depth -> seconds from entering it
var kraken_contact_frames := 0
var kraken_grabs := 0
var kraken_grab_frames := 0
var kraken_hold := 0.0
var kraken_longest_hold := 0.0
var kraken_damage := 0.0
var krakens_culled_alive := 0
var krakens_perished := 0
var kraken_seen := {}              ## depth -> distinct kraken bodies met at it
## ...and the SAME TWO NUMBERS PER RUNG, so grab uptime prints at every depth
## the run reached rather than once for the whole descent. A single run-wide
## uptime cannot separate "the deep is unreadable" at depth 7 from "we barely
## touched depth 5", which is exactly the distinction slice 7 is arguing over.
var kgrab_d := {}                  ## depth -> frames a kraken had hold of us
var kreach_d := {}                 ## depth -> frames a kraken was inside reach
## instance id -> the last pool we saw it with. A kraken that leaves this list
## without its pool having reached zero was freed alive.
var _kraken_pools := {}
var _kraken_grabbing := {}
## True while a kraken is grabbing us or in contact with our hull — the
## attribution the `damaged` handler reads (designer C's own fallback: "else by
## 'a mouth was in reach this frame'").
var _kraken_on_us := false


## Is this body one of the deep's hunters? Matches the Leviathan too, whatever
## the concurrent slice ends up calling it, without needing its name here.
func _is_kraken(s) -> bool:
	return String(s.get("creature_kind")).begins_with("kraken")


## One frame of the kraken scorecard: who is alive, who has hold of us, who
## disappeared while still alive. Also stamps TERRAIN contact, because the same
## `get_colliding_bodies()` sweep already knows: anything touching the hull that
## is not a Ship is rock.
func _tally_krakens(t: float, depth: int, depth_started: float) -> void:
	var hull = world.get("local_ship")
	var brains: Dictionary = world.get("_whale_ais")
	var touching := {}
	var was_terrain := _terrain_recent > 0.0
	_terrain_recent = maxf(0.0, _terrain_recent - STEP)
	_ram_recent = maxf(0.0, _ram_recent - STEP)
	if hull != null and is_instance_valid(hull):
		for body in hull.get_colliding_bodies():
			touching[body.get_instance_id()] = true
			# A Ship carries a `blocks` grid; a TerrainChunk is a bare
			# StaticBody2D. That is the whole test, and it wants no class name
			# (see the header: --script cannot name one).
			if body.get("blocks") == null:
				if _terrain_recent <= 0.0:
					terrain_hits += 1
				_terrain_recent = TERRAIN_TAIL
			elif not _is_kraken(body):
				# ANOTHER HULL IS ON US. Its own bucket, because a hull-on-hull
				# contact episode at 8× bills in five figures in ONE frame
				# (`Ship._integrate_forces`: closing speed × reduced mass), and
				# folded into "shells" it reads as a firefight that never
				# happened.
				if _ram_recent <= 0.0:
					ram_hits += 1
				_ram_recent = TERRAIN_TAIL
				_ram_who = "%s faction %d%s" % [
					String(body.get("creature_kind")) if String(body.get("creature_kind")) != ""
						else "hull",
					int(body.get("faction")),
					" (carcass)" if bool(body.call("is_carcass")) else ""]
	var live := {}
	var on_us := false
	var holding := false
	# THE GRAB'S DENOMINATOR (Q-O). A grab count on its own cannot tell "the
	# mouth is unreadable" from "the hunter never caught up". `KrakenAI._grab`
	# starts from a COARSE test — the grab reach plus the prey's own extent —
	# before it walks the grab sites, so the same coarse figure is the honest
	# "could it have grabbed us this frame", read off the live bodies.
	var in_reach := false
	var mine: Rect2 = hull.solid_bounds if hull != null and is_instance_valid(hull) \
		else Rect2()
	var reach_base: float = Tunables.get_num("kraken_grab_reach") \
		* (float(hull.scale_unit) if hull != null and is_instance_valid(hull) else 1.0)
	for s in fleet.ships():
		if not is_instance_valid(s) or not _is_kraken(s):
			continue
		var id: int = s.get_instance_id()
		live[id] = true
		_kraken_pools[id] = float(s.get("shared_health"))
		if float(s.get("shared_health")) <= 0.0:
			continue   # a carcass neither grabs nor counts as a hunter
		if hull != null and is_instance_valid(hull):
			var theirs: Rect2 = s.solid_bounds
			var gap: float = hull.to_global(mine.get_center()).distance_to(
				s.to_global(theirs.get_center()))
			if gap <= reach_base + (mine.size.length() + theirs.size.length()) * 0.5:
				in_reach = true
		var ai = brains.get(id)
		var grabbing: bool = ai != null and (bool(ai.get("grabbing"))
			or bool(ai.get("grabbing_player")))
		if grabbing:
			holding = true
			if not bool(_kraken_grabbing.get(id, false)):
				kraken_grabs += 1
		_kraken_grabbing[id] = grabbing
		if grabbing or touching.has(id):
			on_us = true
	# Anything that was in the books last frame and is not alive now: killed if
	# its pool had emptied, FREED BY THE CULL if it had not.
	for id in _kraken_pools.keys():
		if live.has(id):
			continue
		if float(_kraken_pools[id]) > 0.0:
			krakens_culled_alive += 1
		else:
			krakens_perished += 1
		_kraken_pools.erase(id)
		_kraken_grabbing.erase(id)
	_kraken_on_us = on_us
	if in_reach:
		kraken_reach_frames += 1
		_bump(kreach_d, depth)
	if holding:
		_bump(kgrab_d, depth)
		kraken_grab_frames += 1
		kraken_hold += STEP
		kraken_longest_hold = maxf(kraken_longest_hold, kraken_hold)
	else:
		kraken_hold = 0.0
	if on_us:
		kraken_contact_frames += 1
		if not kraken_first_contact.has(depth):
			kraken_first_contact[depth] = t - depth_started
	# THE TERRAIN EPISODE CLOSES HERE, one tail after the last contact — the only
	# place that knows both that the contacts have stopped and which rung they
	# happened on. Only the loop above can re-open it, so an episode that is
	# still cold at the end of the tick is over.
	if was_terrain and _terrain_recent <= 0.0:
		_close_terrain_episode(depth)


## One terrain contact episode is over: was it a CRASH or a graze?
func _close_terrain_episode(depth: int) -> void:
	if _terrain_bill >= CRASH_HP:
		_bump(crashes_d, depth)
		crashes_total += 1
		crash_worst_d[depth] = maxf(float(crash_worst_d.get(depth, 0.0)), _terrain_bill)
		# A HULL THAT WAS ALREADY FALLING did not fly into anything: it was
		# carried into it by gravity with no stick left to argue. Without this
		# split the biggest bill in a run reads as a piloting error, when the
		# piloting error (if any) was thirty seconds earlier and had nothing to
		# do with rock.
		if _t <= _fall_until:
			_bump(crash_fall_d, depth)
	_terrain_bill = 0.0


# --- THE COMBAT SCORECARD'S BOOKKEEPING ------------------------------------

## Add one to `book[key]`.
func _bump(book: Dictionary, key, by := 1) -> void:
	book[key] = int(book.get(key, 0)) + by


## Add `by` to `book[key]` as a float.
func _add(book: Dictionary, key, by: float) -> void:
	book[key] = float(book.get(key, 0.0)) + by


## WHAT A BODY IS, in one word, for the scorecard's rows. A creature answers with
## its own `creature_kind` (the deep's hunters are not "a ship"); a vessel is
## named by its side, because that is the only thing that distinguishes a picket
## from the hull we are flying; anything with a grit pool is a person.
func _kind_of(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "nothing"
	var ck = node.get("creature_kind")
	if ck != null and String(ck) != "":
		return String(ck)
	var fac = node.get("faction")
	if node.get("blocks") != null and fac != null:
		match int(fac):
			0: return "our hull"
			1: return "picket"
			3: return "wreck"
			_: return "vessel f%d" % int(fac)
	if node.get("max_health") != null:
		return "person"
	return "terrain"


## EVERY SHELL AND EVERY SPIT IS BOOKED AT BIRTH. `node_added` is the only hook
## that cannot miss one: the group scan this replaces ran once a frame and would
## never see a shell fired and stopped inside the same frame — which is exactly
## what a point-blank picket does, and exactly the shell whose hit rate matters.
func _on_node_added(node: Node) -> void:
	if not _scoring:
		return
	if node.is_in_group("shots"):
		var fac := int(node.get("faction"))
		_bump(shells_fired, fac)
		_bump(shells_fired_d, "%d|%d" % [_depth_now, fac])
		if fac == 1:
			enemy_shots += 1     # the old line, kept so old runs stay comparable
		node.connect("spent", func(reason: String, victim: Node, amount: float) -> void:
			_book_shell(fac, reason, victim, amount))
	elif node.is_in_group("hazard_fireballs"):
		spits_fired += 1
		node.connect("spent", func(reason: String, victim: Node, amount: float) -> void:
			_book_spit(reason, victim, amount))


## One shell's outcome. `amount > 0` is the definition of a HIT: a shell stopped
## by its own side's plating or by rock touched something and hurt nobody, and
## folding those into "landed" is how a 9% hit rate reads as 40%.
func _book_shell(fac: int, reason: String, victim: Node, amount: float) -> void:
	if not _scoring:
		return
	_bump(shells_why, "%d|%s" % [fac, reason])
	if amount <= 0.0:
		return
	_bump(shells_landed, fac)
	_add(shells_dealt, fac, amount)
	_bump(shells_landed_d, "%d|%d" % [_depth_now, fac])
	_bump(shells_onto, "%d|%s" % [fac, _kind_of(victim)])
	if fac == 0:
		_book_our_hit(victim, amount)


## A basilisk's fireball, same two questions. It carries no faction, so "landed"
## means it burned SOMETHING; the line that matters to us is the third one.
func _book_spit(reason: String, victim: Node, amount: float) -> void:
	if not _scoring:
		return
	_bump(shells_why, "spit|%s" % reason)
	if amount <= 0.0:
		return
	spits_landed += 1
	if victim != null and is_instance_valid(victim) \
			and (victim == world.get("local_ship") or victim == pl):
		spits_on_us += 1
		spits_dealt_us += amount


## OUR shell landed on `victim`: open its book if it is new and start its clock.
## The first hit is the start of time-to-kill — not the first sighting, which
## would measure how long the pilot took to close, not how long the gun took.
func _book_our_hit(victim: Node, amount: float) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var id := victim.get_instance_id()
	if not foes.has(id):
		return          # our own hull, a person, or something not in the books
	var rec: Dictionary = foes[id]
	if float(rec["first_hit"]) < 0.0:
		rec["first_hit"] = _t
	rec["our_damage"] = float(rec["our_damage"]) + amount
	rec["our_hits"] = int(rec["our_hits"]) + 1


## IS THIS BODY COMING FOR US? A picket, a kraken or a basilisk is; a WHALE is
## not, whatever its faction says. The distinction decides what counts as an
## ENGAGEMENT and as FIRST CONTACT, and getting it wrong would be the loudest
## kind of wrong: the sky is full of whales, so counting one drifting past as a
## fight would print a run as permanently under attack — the exact opposite of
## the report ("enemies are not aggressive") these numbers exist to settle.
func _is_hunter(s) -> bool:
	if int(s.get("faction")) == 1:
		return true
	var ck := String(s.get("creature_kind"))
	return ck.begins_with("kraken") or ck.begins_with("basilisk")


## ONE FRAME OF THE HOSTILE BOOKS: who is out there, how close they have come,
## who just died and who slipped away alive. Also opens and closes ENGAGEMENTS.
func _tally_foes(t: float, d: int, depth_started: float) -> void:
	var here: Vector2 = pl.global_position if is_instance_valid(pl) else Vector2.ZERO
	var gun: float = Tunables.get_num("enemy_aggro_range") * float(world.get("world_scale"))
	var seen := {}
	var in_range := false
	for s in fleet.ships():
		if not is_instance_valid(s) or int(s.get("faction")) == 0:
			continue
		var id: int = s.get_instance_id()
		seen[id] = true
		var dd: float = s.global_position.distance_to(here)
		var dead: bool = bool(s.call("is_carcass")) or int(s.get("faction")) == 3
		if not foes.has(id):
			# A WRECK IS NOT A FOE. Husks keep flying (and keep stopping our
			# shells) long after the fight; opening a book on one would print
			# kills we never made.
			if int(s.get("faction")) == 3:
				continue
			var kind := _kind_of(s)
			foes[id] = {"kind": kind, "born": t, "depth": d, "first_hit": -1.0,
				"our_damage": 0.0, "our_hits": 0, "closest": INF, "last": t,
				"closed": false, "dead": false}
			_bump(met_of_kind, kind)
		var rec: Dictionary = foes[id]
		rec["last"] = t
		rec["closest"] = minf(float(rec["closest"]), dd)
		var kind2 := String(rec["kind"])
		closest_by_kind[kind2] = minf(float(closest_by_kind.get(kind2, INF)), dd)
		if dd <= gun and not bool(rec["closed"]):
			rec["closed"] = true
			_bump(closed_to_gun, kind2)
		if dead and not bool(rec["dead"]):
			rec["dead"] = true
			_book_death(rec, t, d)
		if not dead and dd <= ENGAGE_RANGE and _is_hunter(s):
			in_range = true
			if not first_contact.has(d):
				first_contact[d] = t - depth_started
	# GONE FROM THE FLEET WITHOUT DYING = culled alive. The same reading the
	# kraken scorecard already takes, widened to every hostile: a body deleted
	# behind us is not a body we beat.
	for id in foes.keys():
		if seen.has(id):
			continue
		var rec: Dictionary = foes[id]
		if not bool(rec["dead"]):
			foes_gone_alive += 1
			rec["dead"] = true
			rec["culled"] = true
		foes.erase(id)
	_run_engagement(t, d, in_range)


## A body just died. Booked with what OUR guns spent on it — and the kills we
## did not pay for are kept too (`ours` false), because "they die to terrain and
## each other" is itself one of the numbers Q-O is arguing about.
func _book_death(rec: Dictionary, t: float, d: int) -> void:
	var first := float(rec["first_hit"])
	kills_booked.append({
		"kind": String(rec["kind"]), "depth": d,
		"ttk": Score.ttk(first, t),
		"ours": first >= 0.0,
		"damage": float(rec["our_damage"]), "hits": int(rec["our_hits"]),
		"met_for": t - float(rec["born"]),
	})


## Open / extend / close the current engagement. The tail is what keeps one
## picket weaving through the 4k×8 boundary from printing as six fights.
func _run_engagement(t: float, d: int, in_range: bool) -> void:
	if in_range:
		_engage_quiet = 0.0
		if _engage.is_empty():
			_engage = {"start": t, "depth": d, "dmg0": damage_taken,
				"ours0": int(shells_fired.get(0, 0)), "hit0": int(shells_landed.get(0, 0)),
				"theirs0": int(shells_fired.get(1, 0)), "land0": int(shells_landed.get(1, 0)),
				"kills0": kills_booked.size(), "end": t}
		_engage["end"] = t
		return
	if _engage.is_empty():
		return
	_engage_quiet += STEP
	if _engage_quiet < ENGAGE_TAIL:
		return
	_close_engagement()


func _close_engagement() -> void:
	if _engage.is_empty():
		return
	var e: Dictionary = _engage
	var row := {
		"depth": int(e["depth"]),
		"start": float(e["start"]),
		"secs": float(e["end"]) - float(e["start"]),
		"damage": damage_taken - float(e["dmg0"]),
		"theirs": int(shells_fired.get(1, 0)) - int(e["theirs0"]),
		"landed": int(shells_landed.get(1, 0)) - int(e["land0"]),
		"ours": int(shells_fired.get(0, 0)) - int(e["ours0"]),
		"we_hit": int(shells_landed.get(0, 0)) - int(e["hit0"]),
		"kills": kills_booked.size() - int(e["kills0"]),
	}
	engagements.append(row)
	_engage_spans.append([float(e["start"]), float(e["end"])])
	_engage = {}
	_engage_quiet = 0.0


## THE COMBAT SCORECARD (Q-O), printed. Every percentage goes through
## `tools/combat_score.gd`, which the suite checks — a probe asserts nothing, so
## the arithmetic behind a number that ranks four design candidates has to be
## pinned somewhere else.
func _print_scorecard(t: float, met_total: int) -> void:
	var sides := {0: "OURS   ", 1: "PICKETS", 2: "CREATURE", 3: "WRECKS "}
	print("\n=== COMBAT SCORECARD (Q-O) ===")
	print("  shooter  | fired | landed |  hit % | damage dealt | stopped by: rock | own side | expired | still flying")
	for fac in [1, 0, 2, 3]:
		var f := int(shells_fired.get(fac, 0))
		if f == 0:
			continue
		var l := int(shells_landed.get(fac, 0))
		var rock := int(shells_why.get("%d|terrain" % fac, 0))
		var own := int(shells_why.get("%d|blocked" % fac, 0))
		var old := int(shells_why.get("%d|expired" % fac, 0))
		print("  %-8s | %5d | %6d | %5.1f%% | %12.0f | %16d | %8d | %7d | %12d" % [
			String(sides.get(fac, "f%d" % fac)), f, l, Score.hit_pct(l, f),
			float(shells_dealt.get(fac, 0.0)), rock, own, old,
			f - l - rock - own - old])
	if spits_fired > 0:
		print("  BASILISK SPIT (a hazard, not a shell): %d spat | %d burned something | %d of those on US for %.0f damage"
			% [spits_fired, spits_landed, spits_on_us, spits_dealt_us])
	# WHAT EACH SIDE'S SHELLS ACTUALLY HIT. The line that says whether a hit rate
	# is low because the gunners miss or because the sky is full of rock.
	for fac in [1, 0]:
		var onto := ""
		for k in shells_onto:
			if String(k).begins_with("%d|" % fac):
				onto += "%s:%d " % [String(k).split("|")[1], int(shells_onto[k])]
		if onto != "":
			print("  %s landed on: %s" % [String(sides.get(fac, "?")).strip_edges(), onto])

	# TIME TO KILL, per kind. Only bodies OUR guns actually hit have one: a
	# picket that flew into a cliff is a death, not a kill, and averaging it in
	# would make the guns look twice as good as they are.
	print("\n--- time to kill (first shell of ours that landed -> death) ---")
	print("  kind        | killed | ours | median-ish mean s | damage we spent | hits | died to us %")
	var by_kind := {}
	for k in kills_booked:
		var kind := String(k["kind"])
		if not by_kind.has(kind):
			by_kind[kind] = {"n": 0, "ours": 0, "ttk": [], "dmg": 0.0, "hits": 0}
		var b: Dictionary = by_kind[kind]
		b["n"] = int(b["n"]) + 1
		if bool(k["ours"]) and float(k["ttk"]) >= 0.0:
			b["ours"] = int(b["ours"]) + 1
			(b["ttk"] as Array).append(float(k["ttk"]))
			b["dmg"] = float(b["dmg"]) + float(k["damage"])
			b["hits"] = int(b["hits"]) + int(k["hits"])
	for kind in by_kind:
		var b: Dictionary = by_kind[kind]
		print("  %-11s | %6d | %4d | %17.1f | %15.0f | %4d | %11.0f%%" % [
			kind, int(b["n"]), int(b["ours"]), Score.mean(b["ttk"] as Array),
			Score.per_each(float(b["dmg"]), int(b["ours"])), int(b["hits"]),
			Score.pct(float(int(b["ours"])), float(int(b["n"])))])
	if by_kind.is_empty():
		print("  nothing died in the whole run")
	print("  %d hostiles left the books ALIVE (culled behind us, never beaten)" % foes_gone_alive)

	# DO PICKETS EVER CLOSE? (BACKLOG "Enemies are not aggressive.") Firing range
	# is the honest bar — a hostile that never got inside `enemy_aggro_range`
	# never had the option of fighting you.
	var gun: float = Tunables.get_num("enemy_aggro_range") * float(world.get("world_scale"))
	print("\n--- did they ever close? (firing range is %.0f px) ---" % gun)
	print("  kind        | met | reached firing range | nearest ever px")
	for kind in met_of_kind:
		print("  %-11s | %3d | %20d | %15.0f" % [kind, int(met_of_kind[kind]),
			int(closed_to_gun.get(kind, 0)), float(closest_by_kind.get(kind, INF))])

	# ENGAGEMENTS — the honest replacement for "per surge" (the timer surge is
	# retired; a run normally has none).
	var fight := Score.span_union(_engage_spans)
	print("\n--- engagements (a hostile inside %.0f px, closed after %.0fs of quiet) ---"
		% [ENGAGE_RANGE, ENGAGE_TAIL])
	print("  #  | depth | started | secs | damage taken | their shells | landed | hit % | our shells | landed | hit % | kills")
	var n := 0
	for e in engagements:
		n += 1
		print("  %-2d | %5d | %7.1f | %4.0f | %12.0f | %12d | %6d | %5.1f%% | %10d | %6d | %5.1f%% | %5d" % [
			n, int(e["depth"]), float(e["start"]), float(e["secs"]), float(e["damage"]),
			int(e["theirs"]), int(e["landed"]), Score.hit_pct(int(e["landed"]), int(e["theirs"])),
			int(e["ours"]), int(e["we_hit"]), Score.hit_pct(int(e["we_hit"]), int(e["ours"])),
			int(e["kills"])])
	if engagements.is_empty():
		print("  NONE — nothing came within %.0f px for the whole run" % ENGAGE_RANGE)
	print("  %d engagements | %.0f s of the run's %.0f s spent in contact (%.0f%%) | %.0f damage per engagement"
		% [engagements.size(), fight, t, Score.pct(fight, t),
			Score.per_each(damage_taken, engagements.size())])

	# TIME TO FIRST CONTACT, per rung — for anything, not only the deep.
	var ttfc := ""
	for dd in range(1, 9):
		ttfc += "d%d:%s " % [dd, ("%.1f" % float(first_contact[dd]))
			if first_contact.has(dd) else "-"]
	print("FIRST CONTACT:  %s(seconds after entering the rung, any live hostile)" % ttfc)

	# THE SHELL LEDGER, RUNG BY RUNG.
	print("\n--- gunnery, rung by rung ---")
	print("  depth | their shells | landed | hit % | our shells | landed | hit %")
	for dd in range(1, 9):
		var tf := int(shells_fired_d.get("%d|1" % dd, 0))
		var of := int(shells_fired_d.get("%d|0" % dd, 0))
		if tf == 0 and of == 0:
			continue
		var tl := int(shells_landed_d.get("%d|1" % dd, 0))
		var ol := int(shells_landed_d.get("%d|0" % dd, 0))
		print("  %5d | %12d | %6d | %5.1f%% | %10d | %6d | %5.1f%%" % [
			dd, tf, tl, Score.hit_pct(tl, tf), of, ol, Score.hit_pct(ol, of)])


# --- THE LADDER (Q-V, DESIGN_DESCENT §11), as the pilot actually met it -------
#
# The seal is two columns of moving wind loops now, and the pacing questions the
# owner asked are all about TIME: how much of a run is spent riding a calm down,
# how often a wall catches you, how long it holds you when it does, and what it
# bills while it has you. All four are one accumulator each, sampled on the
# COMMITTED HULL (the thing the ladder is a decision for) at the probe's own tick.
var _lad_calm := 0.0
var _lad_band := 0.0
var _lad_none := 0.0
var _lad_entries := 0
var _lad_in := false
var _lad_stay := 0.0
var _lad_longest := 0.0
var _lad_bill := 0.0
var _lad_hp_was := -1.0


## One tick of "where in the ladder is the hull, and what is it costing".
## The bill is a DELTA on `hull_integrity` rather than a read of the grind rate:
## what the owner wants to know is what a wall actually took off the pool while
## it had hold of the hull, mender refunds and all.
func _tally_the_ladder(world: Node, hull) -> void:
	if hull == null or not is_instance_valid(hull) 			or not world.has_method("dive_ladder_at"):
		return
	var zone := String((world.call("dive_ladder_at", hull.global_position)
		as Dictionary).get("zone", "none"))
	if zone == "band":
		_lad_band += STEP
		if not _lad_in:
			_lad_entries += 1
			_lad_in = true
			_lad_stay = 0.0
		_lad_stay += STEP
		_lad_longest = maxf(_lad_longest, _lad_stay)
		if _lad_hp_was >= 0.0:
			_lad_bill += maxf(_lad_hp_was - hull.hull_integrity, 0.0)
	else:
		_lad_in = false
		if zone == "calm":
			_lad_calm += STEP
		else:
			_lad_none += STEP
	_lad_hp_was = hull.hull_integrity


func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	world = packed.instantiate()
	root.add_child(world)
	for i in 40:
		await process_frame
	fleet = world.get("fleet")
	pl = world.get("player")
	print("\n=== THE DIVE — headless playtest (8x, the shipped scene) ===")
	print("boot: %d ships, player at %s" % [fleet.ships().size(), str(pl.global_position)])

	# FLY THE SAME SKY TWICE. A run rolls a fresh seed (v0.154.0 makes that the
	# GROUND too, not just the ladder), which is right for the game and useless
	# for a probe: a number measured under one seed cannot be compared with a
	# number measured under another. `--seed N` pins the run this probe opens, so
	# a change can be measured against the dive it changed.
	var pinned := _seed_from_args()
	if pinned != 0:
		world.call("pin_dive_seed", pinned)
	# ...and the DIALS, before the run opens, so a balance A/B is one build.
	_apply_lever_args()
	world.call("begin_dive")
	await _frames(10)
	_report("on the launch deck")
	# The run's SEED is the thing that makes two runs different (the ladder's
	# slalom, the outposts, the garrison, the floating rock and — in the Dive's
	# own scene — the islands), so a probe run is only quotable with it printed.
	# Feed it back in as `--seed` to fly it again.
	print("SEED: %d%s   ladder: %s" % [int((world.get("dive") as Object).get("seed_v")),
		"  (pinned)" if pinned != 0 else "", _ladder_line()])

	# --- Take a hull, the way a player does: walk to a helm and use it -------
	var hull = _nearest_hull()
	if hull == null:
		print("!! no candidate hull on the deck — a run would have to be shipless")
		return quit()
	pl.global_position = hull.to_global(hull.local_pos_of(hull.helm_cells[0]))
	await _frames(2)
	var took: bool = pl.board(hull, hull.helm_cells[0])
	await _frames(4)
	print("took the helm: %s   committed: %s" % [str(took),
		str((world.get("dive") as Object).get("committed"))])
	print("GEAR:   %s" % _gear(world.get("local_ship")))
	print("PARTS:  %s" % _components_line(world.get("local_ship")))
	# THE COMBAT SCORECARD (Q-O, measure first): every hit that lands on OUR
	# hull, counted and summed off the ship's own damaged signal — the number
	# enemy-shell-speed tuning has to answer to.
	var hull_now = world.get("local_ship")
	if hull_now != null and is_instance_valid(hull_now):
		hull_now.damaged.connect(func(_cell: Vector2i, amount: float) -> void:
			# THE BOOKS CLOSE WITH THE HULL. An exploded hull is left as a falling
			# HUSK (`_dive_leave_a_husk`) that keeps this signal wired and keeps
			# crashing all the way to the floor — 897,054 damage of pure noise in
			# one measured run, filed under "shells" because `local_ship` was
			# already null and no contact could be stamped.
			if not _measuring:
				return
			hits_taken += 1
			damage_taken += amount
			# ...and how much of it the deep took. `_kraken_on_us` is stamped
			# once a frame by `_tally_krakens`, which is the only attribution
			# the ram bruise admits of: a collision carries no shooter id.
			# TERRAIN is the same idiom with a short tail (see TERRAIN_TAIL);
			# what neither claims is a shell.
			var by := "shells"
			if _kraken_on_us:
				kraken_damage += amount
				dmg_kraken += amount
				by = "kraken"
			elif _terrain_recent > 0.0:
				dmg_terrain += amount
				_terrain_bill += amount
				by = "terrain"
			elif _ram_recent > 0.0:
				dmg_ram += amount
				by = "ram by %s" % _ram_who
			else:
				dmg_shells += amount
			if amount >= BIG_HIT and big_hits.size() < 24:
				big_hits.append(("    t=%5.1f  %-9.0f on one cell  <- %-8s"
					+ " | the pilot saw %.0f px under the keel and %.0f px along a"
					+ " %.0f px/s travel, horizon %.0f") % [_t, amount, by,
					_saw_down, _saw_travel, _saw_v.length(), _saw_horizon]))

		# ...and the CRUSH, straight from the horse's mouth. `Ship.collision_damage`
		# fires with what a contact actually spent on the grid, which is the one
		# signal that separates "we hit something" from "we were shot" without
		# guessing from contacts.
		hull_now.collision_damage.connect(func(_at: Vector2, amount: float) -> void:
			if not _measuring:
				return
			crush_events += 1
			crush_spent += amount)

	# --- Shop, the way a player who found an outpost would -----------------
	# Depths 6-8 are below Airspace.DEEP_TOP, so a run without a Lung dies at
	# the gate (this probe proved that). Buy one through the REAL counter so the
	# rest of the descent measures the game a prepared player actually plays.
	var run0 = world.get("dive")
	run0.pot = 600
	world.call("_plant_outpost", pl.global_position)
	var bought: bool = world.call("try_buy_stock", 0)
	print("bought a Lung at the counter: %s   (pot now %d)" % [str(bought),
		int(run0.get("pot"))])

	# --- Fly DOWN, holding the dive, and log every rung ---------------------
	var t := 0.0
	var last_depth := 1
	var depth_started := 0.0
	var log_lines: Array[String] = []
	var closest := INF
	var engaged := 0
	## Hostile instance id -> the depth it first came within engagement range at,
	## and the tally per depth. See the booking site in the loop below.
	var met_ids := {}
	var met_by_depth := {}
	var hp0 := 0.0
	var hull0 = world.get("local_ship")
	if hull0 != null and is_instance_valid(hull0):
		hp0 = float(hull0.blocks.size())
	print("HULL BEAM: %.0f x %.0f px | shelf slab %s | sight %.0f px" % [
		hull0.solid_bounds.size.x, hull0.solid_bounds.size.y,
		str(world.call("_dive_shelf_span")), world.call("max_view_horizon_px")])
	# THE BOOKS OPEN HERE, not at boot: the deck is not the fight, and a shell
	# fired while the pilot was walking to a helm would be in the hit rate. Every
	# shell and every basilisk spit from now on is booked at birth by
	# `_on_node_added` — the SceneTree's own signal, which is the only hook that
	# cannot miss a shell fired and stopped inside one frame.
	_scoring = true
	node_added.connect(_on_node_added)
	var rows: Array[Dictionary] = []
	var mark := _snapshot(1, 0.0, 0)
	var guard := 0
	var beat := 0.0
	while guard < int(RUN_GUARD / STEP):
		guard += 1
		await world.get_tree().physics_frame
		t += STEP
		_t = t
		var run = world.get("dive")
		if run == null or String(run.get("outcome")) != "":
			break
		var d := int(run.get("depth"))
		# Which rung a shell fired THIS tick belongs to. Read by `_on_node_added`
		# from inside the engine's own signal, which has no other way to know.
		_depth_now = d
		# THE PILOT. One tick of looking, flying and shooting — the whole of the
		# v0.149.0 change lives in these two calls.
		_fly(d)
		_shoot()
		_watch_the_body(t, d)
		_tally_the_ladder(world, world.get("local_ship"))
		if d != last_depth:
			log_lines.append("  depth %d -> %d after %5.1f s   (pot %d, kills %d, surges %d)"
				% [last_depth, d, t - depth_started, int(run.get("pot")),
					int(run.get("kills")), int(run.get("surges"))])
			rows.append(_row(last_depth, mark, t - depth_started,
				int(met_by_depth.get(last_depth, 0))))
			mark = _snapshot(d, t, 0)
			last_depth = d
			depth_started = t
		_tally_krakens(t, d, depth_started)
		_tally_foes(t, d, depth_started)
		# THREAT: did anything actually reach us? A garrison you never met is
		# a spawn count, not a fight.
		for sh in fleet.ships():
			if not is_instance_valid(sh) or sh.faction == 0 or sh.is_carcass():
				continue
			var dd: float = sh.global_position.distance_to(pl.global_position)
			closest = minf(closest, dd)
			if dd < 4000.0 * 8.0:
				engaged += 1
				# PICKETS MET PER DEPTH (v0.141.0). With the timer surge retired,
				# "how many did the sky actually put in your way" is THE pacing
				# number, and it is a count of BODIES, not of events. Each
				# hostile is booked once, at the depth where it first closed.
				var hid: int = sh.get_instance_id()
				if not met_ids.has(hid):
					met_ids[hid] = d
					met_by_depth[d] = int(met_by_depth.get(d, 0)) + 1
					if _is_kraken(sh):
						kraken_seen[d] = int(kraken_seen.get(d, 0)) + 1
		beat += STEP
		if beat >= 30.0:
			beat = 0.0
			var hull2 = world.get("local_ship")
			print("   t=%5.1f  depth %d  y %.0f  vy %.0f  blocks %d  [%s]" % [t, d,
				pl.global_position.y,
				0.0 if hull2 == null or not is_instance_valid(hull2) else hull2.linear_velocity.y,
				0 if hull2 == null or not is_instance_valid(hull2) else hull2.blocks.size(),
				_gear(hull2)])
		if d >= 8:
			break
		# A SHIPLESS TAIL MEASURES NOTHING about the dive's flight model, and
		# without this the probe spent eleven of its twelve minutes watching a
		# body stand at the respawn point.
		if _hull_gone > 8.0:
			log_lines.append("  hull lost at depth %d — the rest of the run is shipless, stopping" % d)
			break
	_release_all()
	# THE BOOKS CLOSE WITH THE DESCENT. What follows is the climb home, and a
	# shell fired there belongs to no rung.
	_close_engagement()
	# ...and so does the terrain episode that is still open. The run's LAST crash
	# is usually the one that ended it, so leaving it unclosed would drop exactly
	# the contact the reader came for.
	if _terrain_bill > 0.0:
		_close_terrain_episode(last_depth)
	_scoring = false
	rows.append(_row(last_depth, mark, t - depth_started,
		int(met_by_depth.get(last_depth, 0))))

	var hull1 = world.get("local_ship")
	var hp1 := 0.0
	if hull1 != null and is_instance_valid(hull1):
		hp1 = float(hull1.blocks.size())
	print("\nTHREAT: nearest hostile ever %.0f px | frames with one within 4k*8: %d"
		% [closest, engaged])
	# THE GARRISON, AS MET (v0.141.0). The model says a depth is worth
	# `DiveRun.surge_count(d)` pickets around its landing column; this is how many
	# of them a real descent actually flew into.
	var met_line := ""
	var met_total := 0
	for dd2 in range(1, 9):
		var got := int(met_by_depth.get(dd2, 0))
		met_total += got
		met_line += "d%d:%d " % [dd2, got]
	print("PICKETS MET: %s| total %d distinct hostiles" % [met_line, met_total])
	# THE COMBAT SCORECARD (Q-O): what the fight actually did, in numbers.
	# Per-picket, not per-surge: the surge timer is retired, so the denominator
	# that means something is how many hostiles actually reached us.
	var hull3 = world.get("local_ship")
	var integ := "unarmed"
	if hull3 != null and is_instance_valid(hull3) and hull3.hull_integrity_max > 0.0:
		integ = "%.0f/%.0f" % [hull3.hull_integrity, hull3.hull_integrity_max]
	# NOT A HIT RATE, and it never was: `hits_taken` counts DAMAGE EVENTS on our
	# hull from every source at once (a crush, a ram and a chew all land here),
	# so dividing it by shells fired mixed two populations. Kept as the "what got
	# through" line; the gunnery rate is the ledger below.
	print("DAMAGE ON US: %d damage events, %.0f total (%.0f per picket met) | integrity %s"
		% [hits_taken, damage_taken, Score.per_each(damage_taken, met_total), integ])
	print("LADDER: %.0f s riding a calm | %.0f s in a wall over %d catches (longest %.1f s) | %.0f s in a corridor | %.0f hp of grind"
		% [_lad_calm, _lad_band, _lad_entries, _lad_longest, _lad_none, _lad_bill])
	print("OUR FIRE:  %d volleys sent | closest the keel ever came to rock while descending: %.0f px"
		% [shots_fired, _worst_clear])
	_print_scorecard(t, met_total)
	print("DODGES:    %d frames keeping station off other bodies | %d times the descent pushed through anyway | nearest one ever %.0f px"
		% [dodges, vetoes_spent, _closest_wildlife])
	# WHAT ATE THE HULL. The line the old scorecard could not draw: a run that
	# lost its hull printed one damage number and left "flew into a slab" and
	# "was shot down" indistinguishable.
	print("HULL BILL: terrain %.0f (%.0f%%, %d crashes) | ram %.0f (%.0f%%, %d contacts, last %s) | shells %.0f (%.0f%%) | kraken %.0f (%.0f%%)"
		% [dmg_terrain, 100.0 * dmg_terrain / maxf(damage_taken, 1.0), terrain_hits,
			dmg_ram, 100.0 * dmg_ram / maxf(damage_taken, 1.0), ram_hits,
			"-" if _ram_who == "" else _ram_who,
			dmg_shells, 100.0 * dmg_shells / maxf(damage_taken, 1.0),
			dmg_kraken, 100.0 * dmg_kraken / maxf(damage_taken, 1.0)])
	print("CRUSH:     %d contact bites spent %.0f on the grid (Ship.collision_damage)"
		% [crush_events, crush_spent])
	for l in big_hits:
		print(l)
	# THE KRAKEN SCORECARD (DESIGN_KRAKEN §7 slice 2). Targets, from the design:
	# first contact under 25 s at d4-d7, 1.5-3 grabs a minute, krakens taking
	# 15-25 % of the 3,000 integrity pool over a descent, and culled-alive 0.
	var ttc := ""
	for dd in range(1, 9):
		ttc += "d%d:%s " % [dd, ("%.1f" % float(kraken_first_contact[dd]))
			if kraken_first_contact.has(dd) else "-"]
	print("KRAKEN CONTACT: %s| %.1f s of contact in %.0f s of diving" % [ttc,
		float(kraken_contact_frames) * STEP, t])
	var seen_line := ""
	for dd in range(1, 9):
		seen_line += "d%d:%d " % [dd, int(kraken_seen.get(dd, 0))]
	print("KRAKENS MET:    %s" % seen_line)
	# GRAB UPTIME (Q-O). Grabs per minute is a rate over the WHOLE run, which
	# blames the mouth for the descent: the fair denominator is the time a
	# kraken was actually inside grab reach. A low uptime with plenty of reach
	# time is a readability/mechanic problem; a low uptime with no reach time at
	# all is a pursuit problem, and they want opposite fixes.
	var held: float = Score.frames_to_secs(kraken_grab_frames, STEP)
	var reach: float = Score.frames_to_secs(kraken_reach_frames, STEP)
	print("KRAKEN GRABS:   %d | %.2f per minute | held %.1f s total, longest %.1f s"
		% [kraken_grabs, Score.per_minute(kraken_grabs, t),
			held, kraken_longest_hold])
	print("KRAKEN UPTIME:  %.1f s within grab reach | %.1f s actually grabbing = %.0f%% uptime"
		% [reach, held, Score.uptime_pct(held, reach)])
	print("KRAKEN BILL:    %.0f of %.0f damage taken (%.0f%%) | %d killed | %d CULLED ALIVE"
		% [kraken_damage, damage_taken,
			100.0 * kraken_damage / maxf(damage_taken, 1.0),
			krakens_perished, krakens_culled_alive])
	if hull1 == null or not is_instance_valid(hull1):
		hp1 = float(maxi(_blocks_at_loss, 0))
	print("HULL:   %.0f blocks -> %.0f (%.0f lost)%s" % [hp0, hp1, hp0 - hp1,
		"" if hull1 != null and is_instance_valid(hull1)
			else "   [as it stood when the run took it away — the grid was not ground down]"])
	print("GEAR:   %s" % _gear(hull1))
	print("\n--- the descent ---")
	for l in log_lines:
		print(l)
	if log_lines.is_empty():
		print("  never left depth 1 in %.0f s — the ship is not descending" % t)
	print("\n--- the descent, rung by rung ---")
	print("  depth |  secs | blocks lost | integrity | terrain |    ram | shells | kraken | kills | pickets | kraken s")
	for r in rows:
		print(("  %5d | %5.1f | %11d | %9.0f | %7.0f | %6.0f | %6.0f | %6.0f | %5d | %7d | %6.1f"
			% [int(r["depth"]), float(r["secs"]), int(r["blocks"]), float(r["integ"]),
				float(r["terrain"]), float(r["ram"]), float(r["shells"]), float(r["kraken"]),
				int(r["kills"]), int(r["pickets"]), float(r["kcontact"])]))
	# THE PILOT, RUNG BY RUNG (v0.161.0). Three questions the run-wide lines
	# cannot answer, printed for EVERY depth the run reached — including the ones
	# that cost nothing, because a blank row is the finding when the row above it
	# is full:
	#   * CRASHES — terrain contact episodes that billed over CRASH_HP. The
	#     honest measure of whether the pilot is flying the ladder or bouncing
	#     down it, and the number this whole round exists to drive to zero.
	#   * STUCK — seconds the stuck detector spent climbing back out of a dead
	#     end. Time the run spent measuring the AUTOPILOT rather than the game.
	#   * GRAB UPTIME — held over time in reach, per rung (DESIGN_KRAKEN slice
	#     7). A run-wide uptime cannot tell "depth 7's mouth is unreadable" from
	#     "we barely touched depth 5".
	print("\n--- the pilot, rung by rung ---")
	print("  depth | crashes | of those, fell into | worst bill | stuck s | kraken reach s | grabbed s | uptime %")
	var deepest_row := 1
	for r in rows:
		deepest_row = maxi(deepest_row, int(r["depth"]))
	for dd in range(1, deepest_row + 1):
		var reach_s: float = Score.frames_to_secs(int(kreach_d.get(dd, 0)), STEP)
		var held_s: float = Score.frames_to_secs(int(kgrab_d.get(dd, 0)), STEP)
		print("  %5d | %7d | %19d | %10s | %7.1f | %14.1f | %9.1f | %7.0f%%" % [
			dd, int(crashes_d.get(dd, 0)), int(crash_fall_d.get(dd, 0)),
			"-" if int(crashes_d.get(dd, 0)) == 0
				else "%.0f" % float(crash_worst_d.get(dd, 0.0)),
			float(stuck_d.get(dd, 0.0)), reach_s, held_s,
			Score.uptime_pct(held_s, reach_s)])
	print("PILOT:  %d crashes over %.0f s of diving | %d climb-outs from dead ends costing %.1f s | measured braking %.0f px/s² (best seen %.0f)"
		% [crashes_total, t, escapes, stuck_secs, _decel, _decel_seen])
	print("STICK:  %.0f s down | %.0f s up | %.0f s neutral (the hover holding station) | %.0f s carried by air no stick can beat"
		% [secs_sinking, secs_climbing, secs_coasting, carried_secs])
	print("TOO LATE: %d ticks (%.1f s) descending with less room under the keel than the descent needed to stop"
		% [too_late, float(too_late) * STEP])
	for l in late_lines:
		print(l)
	for l in falls:
		print(l)

	print("\n--- what the body and the hull actually took ---")
	print("  body %.0f/%.0f" % [float(pl.health) if is_instance_valid(pl) else 0.0,
		float(pl.max_health) if is_instance_valid(pl) else 0.0])
	for l in body_hits:
		print(l)
	for l in hull_steps:
		print(l)
	if body_hits.is_empty() and hull_steps.is_empty():
		print("    nothing touched either")
	_report("after %.0f s of diving" % t)

	# --- Turn around and climb home -----------------------------------------
	var run2 = world.get("dive")
	var still_flying = world.get("local_ship")
	# A SHIPLESS BODY CANNOT CLIMB, and eight simulated minutes of it standing at
	# the respawn point is eight minutes of wall clock for nothing.
	if still_flying == null or not is_instance_valid(still_flying):
		print("\nno hull left to climb with — the run ends here")
	elif run2 != null and String(run2.get("outcome")) == "":
		Input.action_press("ship_up")
		var up := 0.0
		while up < 60.0 * 8.0:
			await world.get_tree().physics_frame
			up += STEP
			if String((world.get("dive") as Object).get("outcome")) != "":
				break
		Input.action_release("ship_up")
		print("\nclimbed for %.0f s" % up)
		print("GEAR:   %s" % _gear(world.get("local_ship")))
	_report("at the end")
	var fin = world.get("dive")
	if fin != null:
		print("LEDGER: %s" % str(fin.call("ledger")))
	quit()


# --- THE PILOT --------------------------------------------------------------
#
# State the flying carries between ticks. The stick is ON/OFF input (there is no
# fractional axis to press), so a commanded RATE is flown bang-bang against the
# hull's own `linear_velocity.y` — which is exactly how a player flies it: they
# hold DOWN, watch the rock come up, and let go.
var _down := false
var _up := false
var _steer := 0
var _fire_cd := 0.0
var _worst_clear := INF     ## closest the keel ever came to rock while descending
## THE LAST THING THE PILOT SAW, one tick old, so a big-hit line can quote it.
## "The hull hit rock" and "the hull hit rock it had been staring at for two
## seconds" are different bugs behind the same damage number.
var _saw_down := 0.0
var _saw_travel := 0.0
var _saw_horizon := 0.0
var _saw_v := Vector2.ZERO
## TOO LATE: ticks where the keel's clearance was already inside the descent's
## own stopping distance. Not a crash — a crash is what follows one of these if
## the brakes do not win — but it is the ONE line that separates "the fan is
## blind" from "the fan sees and the hull cannot stop".
var too_late := 0
var late_lines: Array[String] = []
## ...and the ticks where the hull was going down faster than the stick could
## ever command. See the booking site: a fall is a different finding from a fast
## descent, and the two used to print as the same number.
var falls: Array[String] = []
## THE MEASURED BRAKES (rule 2). `_decel_seen` is the largest deceleration this
## hull has ever achieved with the up stick held; `_decel` is that with the
## margin taken off, and it is what every stopping distance in the tick uses.
var _decel := DECEL_PRIOR
var _decel_seen := 0.0
var _last_vy := 0.0
## The heading the search settled on, and how long its hold bonus still runs.
var _heading := Vector2.DOWN
var _heading_t := 0.0
## THE STUCK DETECTOR's state: the deepest y ever reached, how long since it
## improved, and the climb-out that is running now.
var _best_y := -INF
var _stuck_t := 0.0
var _escape_t := 0.0
var _escape_dir := 1
## Which side of the next slab the lane sits on, and the rung that choice was
## made for — a flip is a reaction to THIS column, never a standing habit.
var _lane_flip := false
var _lane_depth := 0
## What the pilot's own troubles cost, for the report: climb-outs spent, seconds
## held by them (total and per rung), and the crashes those seconds bought off.
var escapes := 0
var stuck_secs := 0.0
var stuck_d := {}           ## depth -> seconds the stuck detector held the descent
var secs_climbing := 0.0    ## seconds with the up stick held (braking or escaping)
var secs_sinking := 0.0     ## seconds with the down stick held
var secs_coasting := 0.0    ## seconds on a neutral stick — the hover holding station
## Seconds inside air falling faster than a full up-stick can climb — the part
## of a descent that is not the pilot's at all (see rule 6 in `_fly`).
var carried_secs := 0.0

# --- WHAT ENDED THE RUN -----------------------------------------------------
# `lost / worn` means THE BODY died, and nothing in the old log said what hit
# it: the hull line printed "4,464 blocks -> 0" for a hull that was merely
# UNBOUND (`local_ship` clears when the pilot dies), which read as "the hull was
# ground away" and sent the diagnosis after the wrong thing entirely. Every
# health step the body takes is now booked with the frame's context.
var _measuring := true      ## false once the hull is no longer ours to measure
var _hull_gone := 0.0       ## seconds since `local_ship` went away
var _last_health := -1.0
var _last_blocks := -1
## The INTEGRITY POOL, watched directly. It is not the same number as the
## `damaged` total and never was: `Ship.damage_cell` emits `amount` ONCE for the
## struck cell but drains the pool by the structural hp taken across every cell
## of the struck COMPONENT — and at 8× an authored 1×1 component is 64 cells.
var _last_integ := -1.0
## The last honest readings, kept past the unbind so the table stays true.
var _blocks_at_loss := -1
var _integ_at_loss := -1.0
var body_hits: Array[String] = []
var hull_steps: Array[String] = []


## Release every held key. Called at the end of the descent and whenever the
## hull is gone, so a shipless tail does not fly a ghost.
func _release_all() -> void:
	if _down:
		Input.action_release("ship_down")
		_down = false
	if _up:
		Input.action_release("ship_up")
		_up = false
	if _steer != 0:
		Input.action_release("ship_right" if _steer > 0 else "ship_left")
		_steer = 0


## Distance from `from` to the first solid thing along `dir * len`, or `len` if
## the segment is clear. `hit_from_inside` is ON: a keel already buried in rock
## must read as ZERO clearance, not as open air (the default would report the
## most dangerous case as the safest).
func _ray(from: Vector2, dir: Vector2, length: float, rid) -> float:
	var space = world.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, from + dir * length, 1, [rid])
	q.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return length
	return minf(length, from.distance_to(hit["position"]))


## The lane to fly down past depth `d + 1`: BESIDE that rung's slab, on the side
## the ladder leans next, so the slalom is flown rather than the rock rammed.
##
## The old pilot aimed at `dive_landing_pos(d + 1)` itself. That point is the
## TOP-CENTRE OF A STONE SLAB (`_cut_landing` -> `_stone`, span wide and 1,600 px
## thick at 8×) — aiming at it and holding full DOWN is a controlled flight into
## terrain, and it is what killed every run before v0.149.0. Nothing needs to
## touch a landing: `DiveRun.depth_of` rounds to the nearest rung, so a depth
## registers half a rung ABOVE its slab.
func _lane_x(d: int) -> float:
	var hull = world.get("local_ship")
	var beam: float = 0.0 if hull == null or not is_instance_valid(hull) \
		else hull.solid_bounds.size.x
	var nd: int = mini(d + 1, 8)
	var here: Vector2 = world.call("dive_landing_pos", nd)
	var span: Vector2 = world.call("_dive_shelf_span")
	var side := 1.0
	if nd + 1 <= 8:
		var after: Vector2 = world.call("dive_landing_pos", nd + 1)
		if not is_zero_approx(after.x - here.x):
			side = signf(after.x - here.x)
	# BACK OFF AND GO AROUND. The stuck detector flips which side of the slab
	# the lane sits on: the side the ladder leans next is the RIGHT default, but
	# it is only a preference, and a run that has spent fourteen seconds not
	# getting any deeper has proved that this seed put something in that lane.
	if _lane_flip:
		side = -side
	return here.x + side * (span.x * 0.5 + beam * 0.9)


## THE FAN. Minimum clearance from the hull's SKIN along `dir`, measured with
## `rays` origins spread across the face pointing that way and `spread` slightly
## fanned directions from each. Returns `length` when the whole fan is clear.
##
## This is rule 1 of the pilot, and the two arguments are the whole of it: a
## single ray from the centre of a body this size was what let five runs in six
## end `terrain 100 %` with the crash never appearing in the clearance log.
func _clear_along(hull, b: Rect2, rid, dir: Vector2, length: float,
		rays := FAN_RAYS, dir_count := 3) -> float:
	var out := length
	var dirs: Array = Nav.fan_dirs(dir, dir_count, FAN_SPREAD)
	for o in Nav.fan_origins(b, dir, rays, 0.9):
		var from: Vector2 = hull.to_global(o)
		for dv in dirs:
			out = minf(out, _ray(from, dv, length, rid))
			if out <= 0.0:
				return 0.0
	return out


## THIS HULL'S BRAKING, MEASURED (rule 2). Pressing UP commands `+climb_rate_max`
## through the rate controller, which asks the v-props for everything they have —
## so the largest deceleration ever seen while the up stick was held IS this
## hull's authority in this air, with its brownout, its lost props and its
## thinning atmosphere already inside the number. A margin comes off it because
## the air keeps thinning on the way down: a stopping distance optimistic by
## 30 % is a crash, one pessimistic by 30 % is a slow run.
## A CONTACT IS NOT BRAKING, and this is the trap the first cut walked into: a
## hull that hits rock loses its whole descent in ONE frame, which reads as
## 146,897 px/s² of authority — after which every stopping distance is
## effectively zero and the pilot dives at full stick into everything, having
## "measured" that it can stop on a coin. Two guards, both from the hull itself:
## no sample while anything is touching us, and a hard ceiling at the most the
## v-props could possibly produce (`thrust × scale ÷ mass`, with the prop
## normalisation, the power ratio and the air density all taken at 1.0, so the
## ceiling is generous and still finite).
func _measure_brake(hull, vy: float) -> void:
	# A NEUTRAL STICK IS ALSO A BRAKE, and sampling it is what makes this number
	# real: the rate controller's neutral target is zero vertical speed, so a
	# descending hull on a centred stick is already asking the props for
	# everything they have. Sampling the up stick alone left one second of
	# evidence in a hundred-second run, and the prior standing in its place.
	if not _down and vy > 60.0 and _terrain_recent <= 0.0 and _ram_recent <= 0.0 \
			and not _kraken_on_us:
		var ceiling: float = float(hull.get("_total_vthrust")) \
			* float(hull.scale_unit) / maxf(hull.mass, 1.0)
		var a: float = minf((_last_vy - vy) / STEP, ceiling)
		if a > _decel_seen:
			_decel_seen = a
			# The prior is a STARTING GUESS, not a floor. Leaving it as a floor
			# made "measured" decorative on the shipped starter, whose real
			# authority (480 px/s²) is below the guess — and an optimistic
			# stopping distance is the one direction this number must not err in.
			_decel = maxf(100.0, _decel_seen * DECEL_MARGIN)
	_last_vy = vy


## ONE TICK OF FLYING: measure the brakes, check for a dead end, fan the rays,
## pick a heading, then fly the fastest speed the room allows down it.
func _fly(d: int) -> void:
	var hull = world.get("local_ship")
	if hull == null or not is_instance_valid(hull) or hull.blocks.is_empty():
		_release_all()
		return
	var rid = hull.get_rid()
	var b: Rect2 = hull.solid_bounds
	var beam: float = maxf(b.size.x, 1.0)
	var unit: float = maxf(float(hull.scale_unit), 1.0)
	var pad := 16.0 * KEEL_PAD_CELLS * unit          # Ship.CELL × cells × scale
	var sink_max: float = maxf(float(hull.dive_rate_max), 240.0)
	var vel: Vector2 = hull.linear_velocity
	_measure_brake(hull, vel.y)
	# A NEW RUNG IS A NEW PLAN. The lane's flip is a reaction to one column being
	# a dead end; carrying it down to the next rung would fly the slalom
	# backwards for the rest of the run.
	if d != _lane_depth:
		_lane_depth = d
		_lane_flip = false
		_stuck_t = 0.0
		_best_y = hull.global_position.y

	# --- 0. IS ANYTHING WORKING? (rule 4) --------------------------------
	var here_y: float = hull.global_position.y
	if here_y > _best_y + STUCK_GAIN_PX:
		_best_y = here_y
		_stuck_t = 0.0
	else:
		_stuck_t += STEP
	if _escape_t > 0.0:
		_escape_t -= STEP
		stuck_secs += STEP
		stuck_d[d] = float(stuck_d.get(d, 0.0)) + STEP
	elif _stuck_t >= STUCK_SECS:
		_escape_t = ESCAPE_SECS
		_escape_dir = -_escape_dir
		_lane_flip = not _lane_flip
		_stuck_t = 0.0
		_best_y = here_y
		escapes += 1

	# --- 1. LOOK (rule 1). Fans, from the hull's skin, not its centre. ----
	var horizon: float = maxf(Nav.stopping_distance(
			maxf(vel.length(), sink_max), _decel, REACTION) * HORIZON_MULT,
		16.0 * HORIZON_MIN_CELLS * unit)
	var down_clear := _clear_along(hull, b, rid, Vector2.DOWN, horizon)
	if vel.y > 0.0:
		_worst_clear = minf(_worst_clear, down_clear)
	# WHAT THE PILOT COULD SEE, kept for one tick so a crash line can quote it.
	# "The hull hit rock" and "the hull hit rock it had been looking straight at
	# for two seconds" are different bugs and the same damage number.
	_saw_v = vel
	_saw_down = down_clear
	_saw_horizon = horizon
	# A FALL IS NOT A DESCENT. The rate stick commands a speed the props hold; if
	# the hull is going down faster than the stick could ever ask for, something
	# else has it — thin air, lost lift, a current — and the vertical axis is out
	# of the pilot's hands until that changes. Booked once, with everything the
	# diagnosis needs, because it is not visible in any other line.
	if vel.y > sink_max * 1.5:
		_fall_until = _t + 2.0
	if vel.y > sink_max * 2.0 and falls.size() < 6:
		falls.append("    t=%5.1f d%d  FALLING at vy %.0f (stick tops out at %.0f) | y %.0f | mass %.0f | lift %.0f vs weight %.0f | air density %.4f (floor %.2f) | wind %s | %s"
			% [_t, d, vel.y, sink_max, hull.global_position.y, hull.mass,
				float(hull.get("_total_lift")), hull.mass * 980.0 * hull.gravity_scale,
				float(hull.call("air_density_at", hull.global_position.y)),
				float(hull.get("air_density_floor")), str(hull.get("extra_wind")),
				_gear(hull)])
	# ...and the pilot's own quality control: is the keel already INSIDE the room
	# this descent needs to stop? Every crash before this round happened with no
	# such moment anywhere in the log, which is what said the old lookahead was
	# blind rather than merely slow.
	var need_down: float = Nav.stopping_distance(maxf(vel.y, 0.0), _decel, REACTION) + pad
	if vel.y > 60.0 and down_clear < need_down:
		too_late += 1
		if late_lines.size() < 8:
			late_lines.append("    t=%5.1f d%d  keel sees %.0f px, needs %.0f to stop from vy %.0f (fan horizon %.0f, air %s, rate cap %.0f)"
				% [_t, d, down_clear, need_down, vel.y, horizon,
					str(hull.get("extra_wind")), sink_max])
	# ALONG THE TRAVEL — the case straight-down rays structurally cannot see: a
	# hull sliding out of a blocked column while still sinking is moving
	# DIAGONALLY, and the rock it meets is the slab's SHOULDER.
	var travel_clear := horizon
	var speed := vel.length()
	if speed > 60.0:
		travel_clear = _clear_along(hull, b, rid, vel / speed, horizon)
	_saw_travel = travel_clear
	# THE CEILING IS ALSO ROCK. Climbing out of a blocked column into an
	# overhang is the same crash upside down.
	var head := _clear_along(hull, b, rid, Vector2.UP, pad * 2.5, 3, 1)

	# ...and GIVE THE WILDLIFE ROOM (rule 5). A neutral whale that glides into a
	# hull descending at 960 px/s bills `creature_ram_damage` × the episode's
	# momentum: MEASURED 39,978 damage in ONE frame against a 3,000 integrity
	# pool. Rays do not save you from it — the body is moving too, and a whale is
	# wider than the beam — so the pilot keeps a bubble the way a player who has
	# been hit once does. KRAKENS ARE EXEMPT: a hunter reaching you is the thing
	# this probe exists to time, and dodging them would measure the dodge.
	var dodge := _dodge_wildlife(hull, beam)
	# ...and even a whale cannot hold the run up forever. A vertical veto runs on
	# a duty cycle: DODGE_VETO_MAX seconds of waiting, then the same again of
	# descending anyway (the lateral half keeps running throughout). A rung you
	# never leave measures nothing.
	_veto_t = maxf(0.0, _veto_t - STEP)
	if dodge.y != 0.0 and _veto_t <= 0.0:
		_veto_held += STEP
		if _veto_held > DODGE_VETO_MAX:
			_veto_held = 0.0
			_veto_t = DODGE_VETO_MAX
			vetoes_spent += 1
	elif dodge.y == 0.0:
		_veto_held = 0.0
	if _veto_t > 0.0:
		dodge.y = 0.0

	# THE AIR IS PART OF THE ARITHMETIC (rule 6, v0.162.0). The rate stick
	# commands a speed RELATIVE TO THE AIR, so a column of falling air adds its
	# own speed to every descent AND subtracts from every brake. The ladder's
	# wind columns run at 1,000 px/s against a full up-stick worth 960
	# (`dive_climb_rate` 120 × 8), so inside one of them NO stick stops the
	# descent — `floor_v` is the part of it that is simply not the pilot's any
	# more. It is MEASURED and reported, not steered around: a cut that handed the
	# vertical over and ran sideways instead lost the hull at depth 1 in 19 s to
	# the wall's own grind — a wall of the ladder is something a player punches
	# through, not something to loiter beside, and which of those is right is the
	# ladder's design question rather than the autopilot's.
	var wind_y: float = (hull.get("extra_wind") as Vector2).y
	var climb_max: float = maxf(float(hull.climb_rate_max), 240.0)
	var floor_v: float = maxf(wind_y - climb_max, 0.0)
	if floor_v > 0.0:
		carried_secs += STEP

	# --- 2. PICK A HEADING (rule 3) --------------------------------------
	var lane_off: float = _lane_x(d) - hull.to_global(b.get_center()).x
	_heading_t = maxf(0.0, _heading_t - STEP)
	var best := Vector2.DOWN
	var best_score := -1.0
	for h in HEADINGS:
		var dir: Vector2 = (h as Vector2).normalized()
		var c: float = down_clear if dir.is_equal_approx(Vector2.DOWN) \
			else _clear_along(hull, b, rid, dir, horizon, 3, 1)
		var sc: float = Nav.heading_score(c, horizon, dir,
			Nav.lane_gain(lane_off, dir.x, horizon), DOWN_WEIGHT, LANE_WEIGHT)
		if _heading_t > 0.0 and dir.dot(_heading) > 0.98:
			sc += HEADING_HOLD
		if sc > best_score:
			best_score = sc
			best = dir
	if not best.is_equal_approx(_heading):
		_heading = best
		_heading_t = HEADING_HOLD_SECS
	# ESCAPING OVERRIDES THE SEARCH. The search is what got stuck; a dead end
	# scores its own walls consistently, so the way out has to be commanded.
	if _escape_t > 0.0:
		var e := Vector2(float(_escape_dir), -0.6).normalized()
		if _clear_along(hull, b, rid, e, horizon, 3, 1) < horizon * 0.4:
			_escape_dir = -_escape_dir
			e = Vector2(float(_escape_dir), -0.6).normalized()
		best = e
		_heading = e


	# --- 3. THE VERTICAL STICK (rule 2). The fastest descent this column can
	# still be stopped out of, from THIS hull's measured authority — and zero
	# whenever anything says stop, because a rung is not something to settle onto
	# gently, it is something to be beside.
	var v_safe: float = minf(
		Nav.safe_speed(maxf(down_clear - pad, 0.0) / SAFETY, _decel, REACTION), sink_max)
	# ...and the same rule down the TRAVEL vector, converted back to its vertical
	# share. A hull crossing the slalom is mostly moving sideways, and a hard
	# veto on a short travel fan would stop the descent every time the lane's far
	# wall came into view — which is most of the descent. Its VERTICAL component
	# is the only part the down stick can spend, so that is the part it caps.
	if speed > 60.0 and vel.y > 0.0:
		v_safe = minf(v_safe, Nav.safe_speed(maxf(travel_clear - pad, 0.0) / SAFETY,
			_decel, REACTION) * (vel.y / speed))
	if best.y <= 0.0 or dodge.y != 0.0 or _escape_t > 0.0:
		v_safe = 0.0
	var vy: float = vel.y
	var climb: bool = (v_safe <= 0.0 and (vy > 0.0 or down_clear <= pad)) \
		or _escape_t > 0.0 or dodge.y > 0.0
	if head <= pad * 0.6 and _escape_t <= 0.0:
		climb = false          # nothing above to climb into
	var sink := not climb and vy < v_safe - RATE_HYST
	if _up != climb:
		_up = climb
		if climb:
			Input.action_press("ship_up")
		else:
			Input.action_release("ship_up")
	if _down != sink:
		_down = sink
		if sink:
			Input.action_press("ship_down")
		else:
			Input.action_release("ship_down")
	# WHERE THE STICK ACTUALLY WENT. A run that takes twice as long as the
	# owner's budget is a finding either way, but "descending slowly through
	# thick country" and "spending half the run climbing back out" are different
	# findings, and the elapsed time alone cannot tell them apart.
	if _up:
		secs_climbing += STEP
	elif _down:
		secs_sinking += STEP
	else:
		secs_coasting += STEP

	# --- 4. THE LATERAL STICK. The heading's own x, unless the wildlife bubble
	# overrules it — and never accelerating into rock: sideways has a stopping
	# distance of its own and NO rate controller to fly it, so when the room on
	# that side runs short the stick reverses. Thrust is the only sideways brake
	# a hull has.
	var want: int = Nav.steer_sign(best.x, 0.20)
	if not is_zero_approx(dodge.x):
		want = 1 if dodge.x > 0.0 else -1
	var need_x := Nav.stopping_distance(absf(vel.x), _decel, REACTION) + pad * 0.6
	if want != 0:
		if _clear_along(hull, b, rid, Vector2(float(want), 0.0),
				maxf(need_x, 1.0), 3, 1) < need_x:
			want = -want if absf(vel.x) > 40.0 \
				and signf(vel.x) == signf(float(want)) else 0
	if want == 0 and absf(vel.x) > 40.0:
		# Drifting sideways with no reason to: the drift needs room too.
		var drift := Vector2(signf(vel.x), 0.0)
		if _clear_along(hull, b, rid, drift, maxf(need_x, 1.0), 3, 1) < need_x:
			want = -int(signf(vel.x))
	if want != _steer:
		if _steer != 0:
			Input.action_release("ship_right" if _steer > 0 else "ship_left")
		if want != 0:
			Input.action_press("ship_right" if want > 0 else "ship_left")
		_steer = want


## How many hull widths of air the pilot leaves around a body it does not want
## to touch. Wide, because the bill is not proportionate: ONE whale contact at
## descent speed measured 39,978 damage against a 3,000 pool.
const WILDLIFE_BUBBLE_W := 2.5
## Bodies dodged, and the closest one ever allowed — the line that says whether
## the pilot was actually able to keep its distance.
var dodges := 0
var vetoes_spent := 0
var _closest_wildlife := INF
## How long the wildlife veto may hold the descent before the pilot pushes on.
const DODGE_VETO_MAX := 5.0
var _veto_held := 0.0
var _veto_t := 0.0


## KEEP OUT OF EVERYTHING'S WAY. Returns `x` = which way to run (0 = no need),
## `y` > 0 = climb, `y` < 0 = stop descending.
##
## Every body except KRAKENS: neutral wildlife (a whale simply in the way) AND
## hostile pickets. Both were measured one-shotting the run — a whale for 39,978
## and a picket gunboat for 11,031, each emptying the 3,000 pool in ONE frame —
## so keeping station off them is not caution, it is the only way to fly. Krakens
## stay exempt on purpose: a hunter reaching you is the thing this probe times,
## and a pilot that dodged them would measure the dodge. The guns keep firing at
## everything either way (`_shoot`), so a dodged picket is still a fought picket.
func _dodge_wildlife(hull, beam: float) -> Vector2:
	var bubble := beam * WILDLIFE_BUBBLE_W
	var out := Vector2.ZERO
	var mine: Rect2 = hull.solid_bounds
	var here: Vector2 = hull.to_global(mine.get_center())
	var worst := INF
	for s in fleet.ships():
		if not is_instance_valid(s) or s == hull:
			continue
		if _is_kraken(s):
			continue
		# Our own side's scenery (the launch deck, a moored candidate) is not a
		# threat to steer around — the deck is where the run starts.
		if int(s.get("faction")) == 0 and String(s.get("creature_kind")) == "":
			continue
		var theirs: Rect2 = s.solid_bounds
		var gap: Vector2 = here - s.to_global(theirs.get_center())
		# Bubble scaled by BOTH bodies: a whale is far wider than the beam.
		var span := bubble + (mine.size.length() + theirs.size.length()) * 0.5
		var dd := gap.length()
		worst = minf(worst, dd)
		if dd > span or dd < 1.0:
			continue
		if absf(gap.x) < absf(out.x) or is_zero_approx(out.x):
			out.x = gap.x if not is_zero_approx(gap.x) else 1.0
		# It is BELOW us: stop descending onto it. Well below and close: climb.
		#
		# WILDLIFE ONLY, and this is the one rule that decides whether the probe
		# gets anywhere. A whale is a wall you wait out — it is drifting, it does
		# not want you, and thirty seconds of patience clears it. A PICKET is
		# not: it chases, it holds station under you as long as you hold station,
		# and vetoing the descent for it is a deadlock. Measured, before this
		# line existed: 633 seconds parked at depth 3 with a full 3,000 pool, one
		# picket 5,049 px below, 25,462 frames of dodging and 1,342 volleys
		# fired. You out-fly a picket by going THROUGH the rung, not by waiting.
		if gap.y < 0.0 and String(s.get("creature_kind")) != "":
			out.y = 1.0 if dd < span * 0.6 else -1.0
	if not is_zero_approx(out.x) or not is_zero_approx(out.y):
		dodges += 1
	_closest_wildlife = minf(_closest_wildlife, worst)
	return out


## FIGHT BACK. A volley at the nearest hostile inside max-zoom sight, every
## `world.turret_cadence` — the cadence the game itself assigns, brownout and all.
##
## Sight is `max_view_horizon_px()` and not the shell's 88,000 px range on
## purpose: THE MAX-ZOOM RULE is what the game uses for "could a player see this
## at all", and a pilot sniping things it has never seen is not the pilot being
## measured. The aim point is a kraken's MEAT (`KrakenAI._mouth_world`, the
## exposed-meat centroid — DESIGN_KRAKEN §3: shell ÷4, meat ×1) and anything
## else's `solid_bounds` middle.
func _shoot() -> void:
	_fire_cd = maxf(0.0, _fire_cd - STEP)
	if _fire_cd > 0.0:
		return
	var hull = world.get("local_ship")
	if hull == null or not is_instance_valid(hull) or hull.blocks.is_empty():
		return
	var ratio: float = clampf(hull.power_supply() / maxf(hull.active_draw(), 1.0), 0.0, 1.0)
	if ratio <= 0.01:
		return          # no power, no fire — the game's own rule
	var sight: float = world.call("max_view_horizon_px")
	var target = null
	var best := sight
	for s in fleet.ships():
		if not is_instance_valid(s) or s == hull or s.faction == 0 or s.is_carcass():
			continue
		if s.is_tamed_ally():
			continue
		# DO NOT PICK A FIGHT WITH THE WILDLIFE. `_dive_body_rows` counts every
		# faction != 0 body as hostile, whales included, and the old pilot shot at
		# whatever was nearest — which PROVOKES a neutral whale (`WhaleAI`) into
		# ramming the hull that shot it, and one ram is the whole integrity pool
		# (measured: 39,978 and 3,369, both fatal). A player diving past a whale
		# leaves it alone. Krakens are still shot at: they are the deep's hunters
		# and they are coming either way.
		if String(s.get("creature_kind")) != "" and not _is_kraken(s):
			continue
		var dd: float = hull.global_position.distance_to(s.global_position)
		if dd < best:
			best = dd
			target = s
	if target == null:
		return
	var aim: Vector2 = target.to_global((target.solid_bounds as Rect2).get_center())
	if _is_kraken(target):
		var brains: Dictionary = world.get("_whale_ais")
		var ai = brains.get(target.get_instance_id())
		if ai != null and ai.has_method("_mouth_world"):
			aim = ai.call("_mouth_world")
	if bool(world.call("_fire_turrets", hull, aim)):
		shots_fired += 1
		_fire_cd = float(world.call("turret_cadence", ratio))
	# No gun bore on it this tick: keep the cooldown at zero and try again next
	# frame, the way a player holding the trigger does.


## BOOK EVERY STEP THE BODY AND THE HULL TAKE. Cheap (two comparisons a frame),
## and it is the difference between "the run ended" and knowing why.
func _watch_the_body(t: float, d: int) -> void:
	var hull = world.get("local_ship")
	var alive: bool = hull != null and is_instance_valid(hull)
	var hp: float = float(pl.health) if is_instance_valid(pl) else 0.0
	if _last_health >= 0.0 and hp < _last_health - 0.01 and body_hits.size() < 24:
		body_hits.append("    t=%5.1f d%d  body %.0f -> %.0f (-%.0f) | piloting %s | vy %.0f | hull %s"
			% [t, d, _last_health, hp, _last_health - hp,
				str(pl.is_piloting()),
				0.0 if not alive else hull.linear_velocity.y,
				"gone" if not alive else "%d blocks, integrity %.0f"
					% [hull.blocks.size(), hull.hull_integrity]])
	_last_health = hp
	var integ: float = hull.hull_integrity if alive else -1.0
	# Only steps worth a line: the assistant mends the pool a few points a second,
	# so a 1-point threshold fills the whole book with grazes and loses the blow
	# that actually ended the run.
	var stepped: bool = _last_integ >= 0.0 and integ >= 0.0 and integ < _last_integ - 25.0
	if stepped and hull_steps.size() < 24:
		hull_steps.append("    t=%5.1f d%d  INTEGRITY %.0f -> %.0f (-%.0f) | blocks %d | hits %d dmg %.0f | id %d | husk %s | on us: %s"
			% [t, d, _last_integ, integ, _last_integ - integ, hull.blocks.size(),
				hits_taken, damage_taken, hull.get_instance_id(), str(hull.get("is_husk")),
				("kraken" if _kraken_on_us else "terrain" if _terrain_recent > 0.0
					else "hull " + _ram_who if _ram_recent > 0.0 else "nothing touching")])
	_last_integ = integ
	var blocks: int = hull.blocks.size() if alive else -1
	if _last_blocks >= 0 and blocks != _last_blocks and hull_steps.size() < 24:
		hull_steps.append("    t=%5.1f d%d  hull %d -> %s | id %s | integrity %s"
			% [t, d, _last_blocks,
				"UNBOUND (the pilot left the helm or died)" if blocks < 0 else str(blocks),
				"-" if not alive else str(hull.get_instance_id()),
				"-" if not alive else "%.0f" % hull.hull_integrity])
	if blocks < 0:
		if _measuring:
			# WHAT THE HULL WAS WORTH WHEN WE LOST IT. Without this the per-rung
			# table reads a gone hull as ZERO blocks and prints "4,464 blocks
			# lost" for a hull that lost none — which is precisely the misreading
			# that sent the first diagnosis of this bug after landing slabs for a
			# week. `local_ship` UNBINDS when the pilot dies; the grid is still
			# standing.
			_blocks_at_loss = _last_blocks
			_integ_at_loss = _last_integ
		_measuring = false
		_hull_gone += STEP
	_last_blocks = blocks


## The run's totals right now — the per-depth table is the difference between
## two of these.
func _snapshot(d: int, t: float, pickets: int) -> Dictionary:
	var hull = world.get("local_ship")
	var run = world.get("dive")
	return {
		"depth": d, "t": t, "pickets": pickets,
		"blocks": (maxi(_blocks_at_loss, 0) if hull == null or not is_instance_valid(hull)
			else hull.blocks.size()),
		"integ": (maxf(_integ_at_loss, 0.0) if hull == null or not is_instance_valid(hull)
			else hull.hull_integrity),
		"terrain": dmg_terrain, "shells": dmg_shells, "kraken": dmg_kraken,
		"ram": dmg_ram,
		"kills": 0 if run == null else int(run.get("kills")),
		"kframes": kraken_contact_frames,
	}


## One rung's row: what the depth that started at `mark` cost.
func _row(d: int, mark: Dictionary, secs: float, pickets: int) -> Dictionary:
	var now := _snapshot(d, 0.0, 0)
	return {
		"depth": d, "secs": secs, "pickets": pickets,
		"blocks": int(mark["blocks"]) - int(now["blocks"]),
		"integ": maxf(float(mark["integ"]) - float(now["integ"]), 0.0),
		"terrain": float(now["terrain"]) - float(mark["terrain"]),
		"shells": float(now["shells"]) - float(mark["shells"]),
		"ram": float(now["ram"]) - float(mark["ram"]),
		"kraken": float(now["kraken"]) - float(mark["kraken"]),
		"kills": int(now["kills"]) - int(mark["kills"]),
		"kcontact": float(int(now["kframes"]) - int(mark["kframes"])) * STEP,
	}


## The ladder this seed rolled, in shelf widths off the centre line — the shape
## the pilot is flying, printed once so a run's table can be read against it.
func _ladder_line() -> String:
	var out := ""
	for d in range(1, 9):
		var at: Vector2 = world.call("dive_landing_pos", d)
		out += "d%d:%.0f " % [d, at.x]
	return out


## The seed asked for on the command line, or 0 for a fresh one. User args
## survive `--script` and land in `OS.get_cmdline_user_args()` after a bare `--`,
## the same idiom `tests/pilot_test.gd --scale 8` uses:
##
##   godot --headless --path . --script tools/dive_probe.gd -- --seed 892583619
func _seed_from_args() -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		return int(args[i + 1])
	return 0


## `--lever id=value`, repeatable: set F2 levers before the run opens.
##
## A BALANCE ROUND'S BEFORE AND AFTER HAVE TO BE THE SAME BINARY (v0.160.0). The
## seed pins the sky; this pins the dials, so "what did changing the shell's
## worth do" is one build, one seed, two lever sets — rather than two checkouts
## whose OTHER differences ride along in the numbers. Prints what it set, because
## a probe run is only quotable with its conditions printed.
##
##   --script tools/dive_probe.gd -- --seed 565218463 --lever dive_shell_worth=1
func _apply_lever_args() -> void:
	var args := OS.get_cmdline_user_args()
	var set_line := ""
	for i in args.size():
		if String(args[i]) != "--lever" or i + 1 >= args.size():
			continue
		var pair := String(args[i + 1]).split("=", true, 1)
		if pair.size() != 2:
			continue
		var id := pair[0]
		if Tunables.def(id).is_empty():
			print("LEVERS: no such lever '%s' — ignored" % id)
			continue
		var kind := String(Tunables.def(id)["kind"])
		var value: Variant = pair[1].to_lower() in ["1", "true", "on"] \
			if kind == "bool" else float(pair[1])
		set_line += "%s=%s " % [id, str(Tunables.set_value(id, value))]
	if set_line != "":
		print("LEVERS: %s(everything else at its shipped default)" % set_line)


func _frames(n: int) -> void:
	for i in n:
		await world.get_tree().physics_frame


## WHAT CAN THIS HULL STILL DO — the line the stall diagnosis was missing. The
## 2026-08-31 baseline ended with a hull that could neither descend nor CLIMB
## (vy 0 through 480 s of held ship_up) after losing 547 blocks, and nothing in
## the log said WHICH blocks: a wedge and a hull whose engines were shot off
## print identically without this. Thrust totals are the authority that actually
## moves a ship; the counts say what the pickets ate.
func _gear(hull) -> String:
	if hull == null or not is_instance_valid(hull):
		return "no hull"
	var props := 0
	var engines := 0
	var turrets := 0
	for cell in hull.blocks:
		match int(hull.blocks[cell]["type"]):
			BlockDB.Type.PROPELLER: props += 1
			BlockDB.Type.ENGINE: engines += 1
			BlockDB.Type.TURRET: turrets += 1
	return "thrust h=%.0f v=%.0f | props %d engines %d turrets %d | power %.0f vs draw %.0f" % [
		hull.get("_total_hthrust"), hull.get("_total_vthrust"),
		props, engines, turrets,
		hull.power_supply(), hull.active_draw()]


## WHAT ONE SHELL COSTS, AND HOW FAR IT REACHES — two numbers, not one.
##
## `Ship.damage_cell` hits EVERY cell of the struck COMPONENT (the owner's "a
## machine or a balloon is one unit") but since v0.149.0 it bills the integrity
## pool ONCE: the struck cell's own loss, capped at its remaining hp. So the POOL
## cost of a shell is `min(shell damage, cell hp)` wherever it lands, while the
## BLOCKS one shell removes is the size of the cluster it lands in.
##
## The second number is the one this probe found: at 8× the starter's 24 authored
## gasbag cells upscaled into ONE contiguous 1,536-cell "G" cluster, so a shell
## into the canopy reached all of it and a graze deleted the ship's whole lift.
## Balloons cluster per authored tile since v0.151.0 (64 cells at 8×), so watch
## this line for a "G" that has grown back into the thousands.
##
## (The old text here printed `shell × cluster` as the pool drain — the
## pre-v0.149.0 arithmetic, stale the moment the pool stopped billing per cell.)
func _components_line(hull) -> String:
	if hull == null or not is_instance_valid(hull):
		return "no hull"
	var biggest := {}   # glyph -> cells in its biggest cluster
	var sample := {}    # glyph -> one cell of that cluster, for its block hp
	var counts := {}    # glyph -> how many clusters wear it
	for cluster in hull._glyph_clusters:
		var k := String(cluster["key"])
		var cells: Array = cluster["cells"]
		counts[k] = int(counts.get(k, 0)) + 1
		if cells.size() > int(biggest.get(k, 0)) and not cells.is_empty():
			biggest[k] = cells.size()
			sample[k] = cells[0]
	var worst := 0
	var worst_key := "-"
	var out := ""
	for k in biggest:
		out += "%s:%d×%d " % [k, int(biggest[k]), int(counts.get(k, 0))]
		if int(biggest[k]) > worst:
			worst = int(biggest[k])
			worst_key = String(k)
	if worst_key == "-":
		return "no glyph clusters (all raw structure)"
	var shell: float = Tunables.get_num("turret_damage")
	var pool: float = hull.hull_integrity_max
	# The pool bill of one shell into that cluster: capped at the cell's own hp
	# (v0.149.0, a component is billed once), then multiplied by WHAT A SHELL IS
	# WORTH (v0.160.0) — the same cap-then-scale order Ship.damage_cell uses, so
	# this line quotes the arithmetic the game will actually run rather than the
	# pre-lever number it printed for two rounds.
	var cell_hp := 0.0
	var wc: Vector2i = sample[worst_key]
	if hull.blocks.has(wc):
		cell_hp = BlockDB.max_hp(int(hull.blocks[wc]["type"]))
	var bill := minf(shell, cell_hp) * maxf(Tunables.get_num("dive_shell_worth"), 0.0)
	return ("biggest cluster per glyph (cells×clusters) %s| one %.0f-damage shell into '%s' "
		+ "reaches %d cells (%.0f hp each) and bills the pool %.0f of %.0f "
		+ "— %.0f such hits before the pool is gone") % [
		out, shell, worst_key, worst, cell_hp, bill, pool,
		maxf(pool, 0.0) / maxf(bill, 1.0)]


func _nearest_hull():
	var best = null
	var bd := INF
	for s in fleet.ships():
		if not is_instance_valid(s) or s.faction != 0 or s.creature_kind != "":
			continue
		if s.is_carcass() or not s.has_helm() or s.helm_cells.is_empty():
			continue
		var d: float = s.global_position.distance_to(pl.global_position)
		if d < bd:
			bd = d
			best = s
	return best


func _report(when: String) -> void:
	var run = world.get("dive")
	var ship = world.get("local_ship")
	var st := "no run"
	if run != null:
		st = "depth %d (deepest %d) pot %d kills %d surges %d  %.0f s" % [
			int(run.get("depth")), int(run.get("deepest")), int(run.get("pot")),
			int(run.get("kills")), int(run.get("surges")), float(run.get("elapsed"))]
	print("%-28s %s | ships %d | hull %s | body y %.0f" % [
		when, st, fleet.ships().size(),
		"none" if ship == null or not is_instance_valid(ship)
			else "%d blocks" % ship.blocks.size(),
		pl.global_position.y if is_instance_valid(pl) else 0.0])
