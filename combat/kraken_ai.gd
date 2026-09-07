class_name KrakenAI
extends WhaleAI

## The kraken (owner survey 2026-08-23, from the source): a two-ended deep hunter,
## EXTREMELY AGGRESSIVE and never stops moving. It is a WhaleAI at heart — it
## inherits the roam, the altitude align, and the PUSH…glide ram rhythm — and adds
## the two things that make a kraken a kraken:
##
##   1. THE SHELL-TIP RAM (pulsed). The inherited push…glide IS the pulsed ram —
##      a heavy shove every ~1–2 s, then a ballistic coast (owner: squids move by
##      reeling their tentacles in and shoving). Because the body plan is a SHELL
##      CASING wrapping a meat interior, almost every leading edge is armoured
##      (v0.39.0: a struck SHELL cell's collision_resist divides the ram bruise),
##      so the kraken rams terrain and hulls without gutting itself — the armour is
##      earned by the shell, not a flag. No special "which end" code is needed: the
##      casing is the armour, all the way around, save the one soft mouth.
##
##   2. THE MOUTH GRAB (continuous). The one exposed-meat opening is the mouth
##      (plus, on the squid body, the tentacle roots). While that mouth is within
##      reach of the prey, the kraken latches and chews: small CONTINUOUS damage
##      that builds up fast (owner). This is active damage the brain applies —
##      unlike the ram, which is pure collision momentum.
##
## Krakens ARE tameable, at the TOP tier (owner 2026-08-24, reversing the earlier
## untameable ruling: "you can tame krakens, they just are a little wild in their
## movement and always do damage if you touch their mouth parts"). `world.try_tame`
## gates on `tame_level` alone — a kraken carries 3, above the whale's 2 and the
## critter's 1 — so the tamed/ridden branches inherited from WhaleAI DO engage for
## a player whose LORE reaches it. (This comment said the opposite until
## 2026-08-26; the code had been right since v0.40.x.)
## Aggression: it does not wait to be attacked —
## while a prey ship is alive it keeps itself "provoked" so the whale ram doctrine
## (align to altitude, then shove) runs on sight.

## Continuous mouth-grab damage per second, applied to the prey cell nearest the
## mouth — or to the on-foot player standing in the jaws — while it is within
## GRAB_REACH. Small per frame, but "builds up fast" on a latched target (a hull
## cell is 100 hp, so ~1 cell/second here). THE grab feel knob; ram lethality
## stays PUSH_ACCEL (inherited).
##
## Both grab constants are the DOCUMENTED DEFAULTS of F2 levers now
## (`kraken_grab_dps` / `kraken_grab_reach`, group Combat) — the use sites read
## Tunables.get_num, exactly as the inherited ram reads `whale_push_accel`. Keep
## these values and the registry defaults in step: the parity checks compare them.
const GRAB_DPS := 120.0
## How close the MOUTH must be to a prey cell to latch, unscaled px ×scale_unit.
## ~a few cells — a bite range, not a reach-across-the-screen grab.
const GRAB_REACH := 70.0
## While a living prey exists the kraken stays provoked (re-stamped each tick) so
## the inherited ram doctrine runs without waiting for a hit. A small margin over
## one frame; anger seconds are irrelevant since it is re-stamped continuously.
const HUNT_RESTAMP_MS := 500.0

## --- THE HEAVE FINDS YOU (v0.147.0, DESIGN_KRAKEN §1.3–§1.5) ---------------
## The owner's complaint was that krakens are easy to avoid, and the reason was
## one vector: `WhaleAI` latches a purely HORIZONTAL shove, while the Dive's
## whole verb is DOWN. Four seconds of attack against a hull falling 1,920 px/s
## is a punch thrown at a line you left in the first half-second — designer C's
## arithmetic nets the hull +7,222 px every cycle, forever.
##
## Three kraken-only overrides fix it, and each is an F2 lever whose documented
## default is the constant beside it (the parity checks compare the two):
##
##   * LEAD, don't align. Aim where the prey WILL be — `kraken_lead_seconds`
##     ahead on its own velocity — so neither the align nor the latch chases an
##     altitude you have already left.
##   * THE SHOVE GETS A VERTICAL SHARE. `_push_dir` is the vector to that lead
##     point with its HORIZONTAL share floored at `kraken_push_vertical`; 1.0 is
##     today's broadside byte for byte, 0.5 lets ~0.87 of the heave be vertical.
##   * IT COILS FIRST. `kraken_coil_seconds` of rearing AWAY, pose held away —
##     the telegraph the charter demands, and the window in which the helm's
##     lateral authority beats a shove that is already committed.
const LEAD_SECONDS := 1.6
const PUSH_VERTICAL := 0.5
const COIL_SECONDS := 0.7
## The rear-back, as a fraction of the ram's own heave. Small: this is a tell
## made of motion, not a second attack — and it must not out-travel the shove
## it precedes (it is applied for 0.7 s against PUSH's 1.0).
const COIL_RECOIL := 0.25

## --- MOUTHS ARE CLUSTERS (v0.148.0, DESIGN_KRAKEN §1.2 / jam #3 B-T3 = C-M6) -
## The exterior-exposed MEAT of a body is not one opening: it is a set of
## CLUSTERS, and a body plan's arm count is therefore a text file rather than a
## line of GDScript. One cluster is the THROAT; every other is a ROOT — an arm,
## with its own reach and its own small pool.
##
## THREE DECISIONS THIS SLICE HAD TO MAKE, and why they came out this way:
##
## 1. **8-CONNECTED, not 4.** The authored gullets are DIAGONAL STAIRCASES.
##    `kraken_leviathan.ship`'s eleven throat cells 4-connect into FIVE
##    fragments — and four of them would then be "arms" grabbing from inside the
##    boss's own maw, which is exactly the shelter both judges ruled to keep
##    (judge 2 §4, D §2b). Diagonally they are one piece of flesh, and the
##    measured answer on the shipped plans is the AUTHORED anatomy: the
##    Leviathan 1 throat + 6 arm roots, every common kraken 1 throat + 0 roots
##    (their "tentacles" are drawn continuous with the head).
## 2. **THE THROAT IS THE CLUSTER NEAREST THE BODY'S SOLID CENTROID.** Largest-
##    wins is the rule judge 2 explicitly refused: D's throat is 11 cells against
##    a 12-cell arm, so the bite would land on whichever arm the flood reached
##    first. "Nearest the interior" is the shape of the thing — a throat is an
##    opening IN the body, an arm trails away from it. Measured margin on the
##    Leviathan: the throat's centroid is 5.6 authored cells from the solid
##    centroid, the nearest arm 16.8. Ties break by cell count, then by the
##    lowest cell, so the answer is deterministic across peers and boots.
## 3. **THE BITE DOES NOT MOVE.** `_mouth_local` is still the centroid of ALL
##    exterior-exposed meat, computed exactly as it was and PINNED on the first
##    ask — judge 2's ruling word for word ("the derived centroid keeps computing
##    the BITE … clustering is used only to enumerate ROOTS"), and D's −17.0
##    measurement with it. That is what keeps "the mouth cannot reach into its
##    own mouth" true: the bubble is centred 6 cells PAST the jaw lip and stops
##    1.6 cells short of the aperture, so a hull parked in the maw is inside the
##    boss and out of the bite. A throat site placed on the throat's OWN cells
##    would swallow the maw and delete the fight's one shelter.
##    Consequence, deliberately: an arm dying never moves the bite, because the
##    pinned point is never recomputed.
##
## So the SITES are: the throat (biting at the pinned derived centroid) plus one
## per root (biting at its own centroid). Seven on the Leviathan; one — today's
## behaviour, byte for byte — on every other kraken in `ships/`.

## A root's own pool, per AUTHORED cell — the documented default of the F2 lever
## `kraken_root_hp_per_cell` (the parity check compares the two). A living
## creature is ONE unit and no block breaks while it lives (`damage_cell` drains
## the shared pool and returns before removing anything), so "kill this arm"
## needs a pool of its own. A hit that lands ON a root's cells drains the shared
## pool as it always did AND this; at zero the arm's cells come off the body and
## it stops grabbing. 80 × a 12-cell arm = 960 hp — about 24 s of the bare
## starter's 40 hp/s on meat: permanent, visible progress with no phase machine.
##
## AUTHORED cells, not blocks: at 8× every authored cell is 64 blocks, and the
## lever has to mean the same number at both scales.
const ROOT_HP_PER_CELL := 80.0

## The mouth point in AUTHORED body-local px (centroid of the exterior-exposed
## meat — the soft opening). Computed once from the body; Vector2.INF = not yet.
var _mouth_local := Vector2.INF
## Read by tests/debug: was ANY grab site latched onto prey this tick?
var grabbing := false
## Read by tests/debug/probe: how many distinct SITES had hold this tick (the
## boss has seven). `grabbing` is "any of them"; this is how many.
var grab_sites_latched := 0

## The ROOTS, in cluster order: {cells: Array[Vector2i], local: Vector2 (authored
## body-local px), hp: float, hp_max: float}. Empty until `_ensure_sites`.
var _roots: Array[Dictionary] = []
## The throat cluster's own cells (read by tests). It has NO pool: killing the
## throat is killing the animal, and that is what `shared_health` is.
var _throat_cells: Array[Vector2i] = []
## cell -> index into `_roots`, so a landed hit is routed in O(1).
var _root_cells := {}
var _sites_built := false

## The ON-FOOT player, handed in by the world each tick (world._creature_swim).
## Null when there is nobody, or while they are PILOTING — a pilot rides inside
## the hull, and that hull is already the prey the mouth is chewing, so biting
## them as well would double-bill one grab straight through the deck.
##
## Typed Node2D, not Player, for the same reason the base class took Node2D for
## its ram target: the brain needs a position and a `take_damage`, nothing more,
## and staying untyped here keeps the AI free of the player scene (a test can
## stand in any node that answers both).
var prey_player: Node2D = null
## Read by tests/debug: did the mouth chew the on-foot player this tick?
var grabbing_player := false


## --- THE BREATH (DESIGN_KRAKEN §6, designer A §2.1) -------------------------
## The Leviathan's inhale, and the only thing about it that lives in the brain:
## a CLOCK and a PHASE. The wind itself is `DiveRun`'s pure model and the world's
## one weather stamp (`world.dive_weather_at`) — a creature that applied its own
## suction force would be a second airstream, and the run has exactly one.
##
## Three phases off the pool alone (§6), so the fight has no state machine to
## desync and the body's own wound shade IS the phase read-out (see
## `DiveRun.BREATH_PHASE_2`):
##
##   P1 100–70 %  the hunter: coil, heave, glide. No breath.
##   P2  70–30 %  THE BREATH: rear (the tell) … inhale … rear …, forever.
##   P3   < 30 %  THE SINK: it breaks off, retreats under its roof and holds.
##                The dunk is off the table; the throat is the only door.
##
## Only the FLOOR'S RESIDENT breathes — `breathes` is set by the world at the
## wake. A common hunter with a kraken brain is untouched, byte for byte.
var breathes := false
## Where it retreats to in P3 (the den, under the roof), handed in at the wake.
## Vector2.INF = nowhere to go, and the sink is then just a broken-off fight.
var den_anchor := Vector2.INF
## The breath's own clock. Advances only while it is alive and breathing, so the
## first inhale of a fight always opens with a full tell.
var _breath_t := 0.0

## How hard it swims home in P3, px/s² ×scale_unit. Between the align (360) and
## the heave (1,100): a deliberate withdrawal, not a rout and not another charge.
const SINK_ACCEL := 620.0
## How near the den counts as home — in BODY HEIGHTS, so a re-authored Leviathan
## keeps its own tolerance. Inside it the swim bladder does the holding.
const SINK_HOLD_HEIGHTS := 0.5


func tick(delta: float, target: Node2D) -> void:
	if whale == null or not is_instance_valid(whale):
		return
	# The Ship-shaped prey (the caller's nearest-ship fallback). The base class
	# takes Node2D now (retaliation can target the on-foot player), but the
	# kraken's own additions — the hunt restamp and the per-cell mouth grab —
	# need a block grid, so they act on the SHIP prey only.
	var prey_ship := target as Ship
	# AN ARM THAT RAN OUT OF POOL COMES OFF, once, at the top of a tick. Deferred
	# from the hit that emptied it on purpose: the drain arrives inside
	# `Ship.damage_cell`'s `damaged.emit`, and mutating the grid re-entrantly
	# from inside the damage walk is the one thing that branch is not written to
	# survive.
	_reap_dead_roots()
	# THE BREATH'S CLOCK, and only while it is a living thing that breathes: a
	# carcass does not inhale, and a hunter never did.
	var sinking := false
	if breathes and _is_alive() and not tamed and not ridden:
		_breath_t += delta
		sinking = breath_phase() == 3
	if sinking:
		# P3, THE SINK (§6): it stops hunting and withdraws under its roof. The
		# anger is CLEARED rather than merely un-restamped, because every shot
		# that brought it to 30 % re-provoked it for `whale_anger_seconds` —
		# leave that standing and the inherited doctrine keeps ramming through
		# the retreat. The pull below is applied after the base tick.
		_provoked_until = -1.0e12
		_end_attack()
	elif not tamed and not ridden and prey_ship != null and is_instance_valid(prey_ship) \
			and not prey_ship.is_carcass():
		# Aggression: hunt on sight. A WILD kraken keeps itself provoked while a
		# living prey is around, so the inherited align→push→glide ram runs
		# immediately (the whale only rams AFTER being hit; the kraken does not
		# wait). A tamed one stops hunting — but stays dangerous (below).
		_provoked_until = Time.get_ticks_msec() + HUNT_RESTAMP_MS
	super.tick(delta, target)
	if sinking:
		_swim_to_the_den()
	# A LITTLE WILD, always (owner 2026-08-24 — krakens are tameable but "a
	# little wild in their movement"): a living kraken never sits still. A
	# deterministic two-frequency wander force rides on top of whatever the
	# base brain (roam / tamed loiter / the rider's steer) decided — small
	# enough to flavour, not fight, the steering.
	if _is_alive():
		var u := whale.scale_unit
		var wild := Tunables.get_num("kraken_wildness") * u
		whale.apply_central_force(Vector2(
			sin(_t * 2.7) + 0.5 * sin(_t * 6.1),
			cos(_t * 3.3) + 0.5 * cos(_t * 5.3)) * wild * whale.mass)
	# THE MOUTH ALWAYS BITES (owner: krakens "always do damage if you touch
	# their mouth parts" — tamed or wild, tamer included). Two prey KINDS, one
	# mouth: the block grid of a ship (wild hunting only — the world hands a
	# tamed brain no ship target), and ANY person standing in the jaws.
	grabbing = false
	grabbing_player = false
	grab_sites_latched = 0
	if not _is_alive():
		return
	# ONE world-space site list per tick — the boss has seven and both grab paths
	# want them, so they are resolved once rather than per path per site.
	var sites := site_worlds()
	var latched := {}
	if prey_ship != null and is_instance_valid(prey_ship) and not prey_ship.is_carcass():
		_mouth_grab(delta, prey_ship, sites, latched)
	_mouth_grab_player(delta, sites, latched)
	grab_sites_latched = latched.size()


## --- The four attack hooks (WhaleAI's, re-decided) -------------------------
## All four are guarded by `not tamed and not ridden`: a tamed kraken you ride
## keeps the base creature's manners, and the whale's broadside ruling
## (`whale_ai.gd` header) is untouched because a whale never calls any of this.

## LEAD, DON'T ALIGN: where the prey will be `kraken_lead_seconds` from now.
func _aim_point(prey: Node2D) -> Vector2:
	if tamed or ridden:
		return super._aim_point(prey)
	return lead_point(prey.global_position, prey_velocity(prey),
		Tunables.get_num("kraken_lead_seconds"))


## THE HEAVE GETS A VERTICAL SHARE: the vector to the lead point, horizontal
## share floored (see `floor_horizontal`).
func _latch_push_dir(to: Vector2, prey: Node2D) -> Vector2:
	if tamed or ridden:
		return super._latch_push_dir(to, prey)
	return floor_horizontal(to, Tunables.get_num("kraken_push_vertical"))


## IT COILS FIRST — unless the lever turns the windup off entirely, in which
## case the attack opens straight into the heave as it always did.
func _attack_entry_phase() -> Phase:
	if tamed or ridden or Tunables.get_num("kraken_coil_seconds") <= 0.0:
		return super._attack_entry_phase()
	return Phase.COIL


func _coil_seconds() -> float:
	return Tunables.get_num("kraken_coil_seconds")


func _coil_accel() -> Vector2:
	return -_push_dir * Tunables.get_num("whale_push_accel") * COIL_RECOIL \
		* whale.scale_unit


## THE POSE IS LATCHED to the attack, not read off the velocity.
##
## `WhaleAI` pitches the body by `linear_velocity.y` alone, so the most violent
## thing a kraken does — a horizontal ram — is the moment its pose is most
## NEUTRAL, and a heave thrown downward reads flat until the speed has already
## arrived (designer C, on `whale_ai.gd`'s pose line). Latching the tilt to
## `_push_dir` across COIL→PUSH→GLIDE fixes both: it rears AWAY during the
## windup and holds the attack's own angle for the whole shove and coast, which
## is what makes the glide window readable — the throat faces backward from the
## tip and cannot turn. Fixed for the KRAKEN path only: the whale's suite pins
## the velocity pose ("facing right, a dive pitches the nose down"), and its
## flat broadside is an owner ruling, not a bug.
##
## Between attacks (`Phase.NONE`) it falls back to the inherited velocity pose,
## so a roaming or aligning kraken still pitches into its own motion — except
## while it REARS FOR THE BREATH, which is the one pose in the fight that has to
## be held against the body's own motion (designer A: "brain-driven instead of
## velocity-driven"). An attack in flight still wins: the heave is the louder
## statement, and the two never need to be read at once.
func _pose_tilt_target() -> float:
	if _phase == Phase.NONE and breath_telling():
		return Ship.POSE_MAX * float(whale.visual_facing)
	if _phase == Phase.NONE or _push_dir == Vector2.ZERO:
		return super._pose_tilt_target()
	var d := -_push_dir if _phase == Phase.COIL else _push_dir
	# atan2 against the horizontal MAGNITUDE, times the facing: the body is
	# reflected about x when it swims left (v0.14.0), so the same downward
	# heave needs the opposite rotation sign to read as nose-into-motion —
	# the identical transform the inherited velocity pose applies.
	return clampf(atan2(d.y, absf(d.x)), -Ship.POSE_MAX, Ship.POSE_MAX) \
		* float(whale.visual_facing)


## --- THE BREATH, read off the body ------------------------------------------
## Everything here is a thin read over `DiveRun`'s pure model plus this body's
## own pool: the brain owns the CLOCK, the model owns the SHAPE, and the world
## owns the WIND. Three owners, no duplicated arithmetic.

## This body's pool as a fraction. 1.0 for anything with no pool at all (an
## arena fixture), which reads as phase 1 — no breath, no sink.
func pool_frac() -> float:
	if whale == null or not is_instance_valid(whale) or whale.shared_health_max <= 0.0:
		return 1.0
	return clampf(whale.shared_health / whale.shared_health_max, 0.0, 1.0)


## 1 the hunter, 2 the breath, 3 the sink (DESIGN_KRAKEN §6). A body that does
## not breathe is always in phase 1: it has no phases to be in.
func breath_phase() -> int:
	if not breathes:
		return 1
	return DiveRun.breath_phase(pool_frac())


## THE F2 SWITCH, in one place, so the lever turns off the tell and the pull
## together — a rear that announces nothing is worse than no rear at all.
func _breath_armed() -> bool:
	return breathes and _is_alive() and not tamed and not ridden \
		and Tunables.get_bool("dive_breath") and breath_phase() == 2


## IS IT REARING RIGHT NOW — the tell, held for `DiveRun.BREATH_TELL_SECONDS`
## before every inhale.
func breath_telling() -> bool:
	if not _breath_armed():
		return false
	return DiveRun.breath_telling(_breath_t, Tunables.get_num("dive_breath_period"))


## HOW HARD IT IS INHALING this tick, 0..1. The world multiplies this by the
## field and the F2 strength; 0 covers "not breathing", "rearing" and "levered
## off" alike, so the world has exactly one number to ask for.
func breath_pull() -> float:
	if not _breath_armed():
		return 0.0
	return DiveRun.breath_cycle(_breath_t, Tunables.get_num("dive_breath_period"))


## WHERE THE AIR IS GOING: the maw in world space — the pinned derived bite
## point, which is the mouth for the grab and therefore the mouth for the
## breath. Public because the world needs it to place the field; `_mouth_world`
## stays the internal name the grab paths already use.
func maw_world() -> Vector2:
	return _mouth_world()


## P3, THE SINK: swim back to the den and hold there, under the roof. Applied
## AFTER the base tick so it rides on top of the swim bladder (which is what
## actually holds the altitude once it arrives) rather than replacing it.
##
## Not a new movement mode — a central force toward a point, which is what every
## other branch of this brain already is. It stops pushing inside a half body
## height of home, so the arrival is a settle rather than an oscillation.
func _swim_to_the_den() -> void:
	if den_anchor == Vector2.INF or whale == null or not is_instance_valid(whale):
		return
	var to := den_anchor - whale.global_position
	var hold := maxf(whale.solid_bounds.size.y, whale.scale_unit * Ship.CELL) \
		* SINK_HOLD_HEIGHTS
	if to.length() <= hold:
		return
	whale.apply_central_force(to.normalized() * SINK_ACCEL * whale.scale_unit
		* whale.mass)


## --- The heave's arithmetic, pure ------------------------------------------
## Static and total so the suite can assert the vectors directly, with no body,
## no world and no physics — the numbers this whole slice is made of.

## Where the prey WILL be. Clamped above the floor by `clamp_above_floor`, so
## "lead your prey" can never mean "aim into the lava".
static func lead_point(at: Vector2, vel: Vector2, seconds: float) -> Vector2:
	return clamp_above_floor(at + vel * maxf(seconds, 0.0))


## A prey's velocity, whatever KIND of body it is: a Ship (and any RigidBody2D)
## carries `linear_velocity`, the on-foot player a `velocity`, and a bare Node2D
## neither. Zero for anything that cannot answer — an unmoving prey leads to
## itself, which is exactly today's aim.
static func prey_velocity(prey: Node2D) -> Vector2:
	if prey == null or not is_instance_valid(prey):
		return Vector2.ZERO
	var v: Variant = prey.get("linear_velocity")
	if not (v is Vector2):
		v = prey.get("velocity")
	if v is Vector2:
		return v as Vector2
	return Vector2.ZERO


## THE FLOOR THE AIM CANNOT CROSS (designer C's R2). A kraken that aims downward
## drives ITSELF downward, and while SHELL survives rock, nothing survives the
## lava core (`world._update_lava_core` consumes creatures). The lead point is
## therefore held above the same altitude a dormant migration refuses to cross,
## `Dormancy.MIGRATE_FLOOR_FRAC` 0.10 — itself comfortably above the lava band's
## own top (`Airspace.LAVA_TOP` 0.05). With no sky at all (the Sprint-1 arena, a
## unit test) there is no floor to clamp to and the point passes through.
static func clamp_above_floor(at: Vector2) -> Vector2:
	if not Airspace.active():
		return at
	var b := Airspace.bounds
	return Vector2(at.x,
		minf(at.y, b.end.y - Dormancy.MIGRATE_FLOOR_FRAC * b.size.y))


## THE LATCHED DIRECTION: `raw` normalized, with its HORIZONTAL share floored at
## `h_floor`. At 1.0 the answer is the purely horizontal broadside `WhaleAI`
## latches today, sign for sign — that is the lever's regression contract. Below
## it the remainder goes vertical (0.5 horizontal → 0.866 vertical), so the
## shove can finally be thrown down at a diving hull, or up at a climbing one.
static func floor_horizontal(raw: Vector2, h_floor: float) -> Vector2:
	var sx := signf(raw.x)
	if sx == 0.0:
		sx = 1.0   # dead astern: the base class's own fallback
	var h := clampf(h_floor, 0.0, 1.0)
	var d := raw.normalized()
	if d == Vector2.ZERO:
		return Vector2(sx, 0.0)   # standing on us: shove sideways, as today
	if absf(d.x) >= h:
		return d
	var sy := signf(d.y)
	if sy == 0.0:
		sy = 1.0
	return Vector2(sx * h, sy * sqrt(maxf(1.0 - h * h, 0.0)))


## A living creature (pool not yet empty). A carcass has drained its pool; the
## inherited tick already stops swimming for it, and it must not bite either.
func _is_alive() -> bool:
	return whale.shared_health_max > 0.0 and whale.shared_health > 0.0


## Latch the mouth onto the prey and chew: find the prey's solid cell nearest the
## mouth and, if it is within bite range, drain it by GRAB_DPS·delta.
##
## A BITE IS A LOCAL QUESTION, AND IT IS ASKED LOCALLY (v0.164.0). This used to
## walk the prey's whole block dictionary — every cell transformed to world space
## and distance-tested — to find a cell that is, by definition, within four
## authored cells of the mouth. Measured at the Dive floor (tools/floor_tick_probe):
## 4.4 ms per call on a 3,595-cell hull, ~1.3 ms of every physics tick, and it
## grew with the size of the SHIP rather than with the size of the bite.
##
## The answer is the same one, found two ways instead:
##
##   * THE COARSE GATE IS THE PREY'S ACTUAL BOX, not a radius around its origin.
##     `solid_bounds` grown by the reach, tested in the prey's own local space —
##     still a superset of "within reach of a solid cell", so no bite is lost,
##     but it rejects a mouth that is merely near a long hull's midpoint.
##   * THE SEARCH IS A RING WALK OUTWARD FROM THE MOUTH'S OWN CELL, stopping as
##     soon as no further ring can beat what it already has. A latched mouth is
##     standing on the hull, so it answers in the first ring or two.
##
## The cell it damages is identical: the transform is a rigid motion with uniform
## scale, so ordering by local distance and ordering by world distance are the
## same ordering, and the reach is converted once rather than per cell.
func _mouth_grab(delta: float, target: Ship, sites: Array[Vector2],
		latched: Dictionary) -> void:
	if sites.is_empty():
		return
	var u := whale.scale_unit
	var reach := Tunables.get_num("kraken_grab_reach") * u
	if target.blocks.is_empty():
		return
	# The reach in the PREY's local units — the space `solid_bounds`, the cell
	# lattice and the search below all live in.
	var body_scale: float = maxf(target.global_transform.get_scale().x, 0.0001)
	var reach_local := reach / body_scale
	var box := target.solid_bounds.grow(reach_local)
	var dps := Tunables.get_num("kraken_grab_dps")
	var t_walk := Time.get_ticks_usec()
	for i in sites.size():
		var at := target.to_local(sites[i])
		if not box.has_point(at):
			continue
		var cell := _nearest_solid_cell_near(target, at, reach_local)
		if cell.x == 0x7FFFFFFF:
			continue
		target.net_damage_cell(cell, dps * delta)
		grabbing = true
		latched[i] = true
	if TickPerf.on:
		TickPerf.bill("in: kraken grab grid-walk", t_walk)


## The prey's SOLID cell nearest a point in its own local space, within
## `reach_local` px of it — or the sentinel `(0x7FFFFFFF, 0)` when the bite finds
## nothing. Rings outward from the point's own cell in Chebyshev order and stops
## once the nearest possible cell of the next ring is already further than the
## best found: a mouth resting on plating answers after one or two rings, and a
## mouth in open air past the plating's edge stops at the reach.
static func _nearest_solid_cell_near(target: Ship, at: Vector2,
		reach_local: float) -> Vector2i:
	var cell_px := float(Ship.CELL)
	var base := Vector2i(roundi(at.x / cell_px), roundi(at.y / cell_px))
	var max_r := int(ceilf(reach_local / cell_px)) + 1
	var best := Vector2i(0x7FFFFFFF, 0)
	var best_d2 := reach_local * reach_local
	for r in max_r + 1:
		# Any cell on ring r is at least (r - 0.5) cells away, because `at` sits
		# within half a cell of `base`'s centre. Once that floor beats the best
		# distance so far, no further ring can improve on it.
		var floor_px := (float(r) - 0.5) * cell_px
		if r > 0 and floor_px * floor_px > best_d2:
			break
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := base + Vector2i(dx, dy)
				if not target.blocks.has(c):
					continue
				if not BlockDB.get_def(target.blocks[c]["type"])["solid"]:
					continue
				var d2 := (Vector2(c) * cell_px - at).length_squared()
				if d2 < best_d2:
					best_d2 = d2
					best = c
	return best


## The mouth chews PEOPLE too (owner follow-up 2026-08-24): stand in the jaws on
## foot and the kraken eats YOU at the same GRAB_DPS a hull cell takes — the ram
## can miss a person entirely (they are small and it plows past), so without this
## the one continuous attack simply did not exist for anyone off a ship.
##
## Far cheaper than the ship grab: a person has no block grid, so this is one
## distance test against the mouth point, no per-cell scan and no coarse gate.
## `take_damage` is duck-typed rather than cast to Player — see `prey_player`.
## (The tamed guard lives in tick(), shared with the ship grab, so the two bite
## paths cannot drift apart; a kraken tames only at the top tier, but the base
## class serves every creature that does.)
func _mouth_grab_player(delta: float, sites: Array[Vector2],
		latched: Dictionary) -> void:
	if prey_player == null or not is_instance_valid(prey_player) \
			or not prey_player.has_method("take_damage"):
		return
	var reach := Tunables.get_num("kraken_grab_reach") * whale.scale_unit
	var dps := Tunables.get_num("kraken_grab_dps")
	for i in sites.size():
		if (prey_player.global_position - sites[i]).length_squared() > reach * reach:
			continue
		prey_player.take_damage(dps * delta)
		grabbing_player = true
		latched[i] = true


## The mouth in WORLD space. Mirrors the authored point with the body's facing
## (the collider mirrors with the skin, v0.14.0), so the mouth tracks the drawn
## head whichever way the kraken is swimming.
func _mouth_world() -> Vector2:
	_ensure_sites()
	return whale.to_global(whale._mirror_point(_mouth_local))


## --- THE GRAB SITES --------------------------------------------------------

## Every grab site in AUTHORED body-local px: the THROAT first (the pinned
## derived mouth centroid — see the header's decision 3), then one per live ROOT
## at its own cluster centroid.
func site_locals() -> Array[Vector2]:
	_ensure_sites()
	var out: Array[Vector2] = [_mouth_local]
	for r in _roots:
		out.append(r["local"] as Vector2)
	return out


## The same list in WORLD space. Mirrored with the body's facing (the collider
## mirrors with the skin, v0.14.0), so an arm tracks the drawn arm whichever way
## the kraken is swimming.
func site_worlds() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if whale == null or not is_instance_valid(whale):
		return out
	for p in site_locals():
		out.append(whale.to_global(whale._mirror_point(p)))
	return out


## How many ROOTS this body still has (tests / F2 / probe). The throat is not
## counted: it is the animal, not a limb.
func root_count() -> int:
	_ensure_sites()
	return _roots.size()


## A root's remaining pool, and its full one. -1 for an index that is not a root.
func root_hp(i: int) -> float:
	_ensure_sites()
	return float(_roots[i]["hp"]) if i >= 0 and i < _roots.size() else -1.0


func root_hp_max(i: int) -> float:
	_ensure_sites()
	return float(_roots[i]["hp_max"]) if i >= 0 and i < _roots.size() else -1.0


## The throat cluster's cells (tests). The cells of root `i` are `root_cells(i)`.
func throat_cells() -> Array[Vector2i]:
	_ensure_sites()
	return _throat_cells


func root_cells(i: int) -> Array[Vector2i]:
	_ensure_sites()
	if i < 0 or i >= _roots.size():
		return [] as Array[Vector2i]
	return _roots[i]["cells"] as Array[Vector2i]


## A HIT LANDED ON THIS BODY. Wired at the ONE place a creature's brain is set up
## (`world._whale_ai_for` already connects `damaged` there to provoke it), so
## the routing cannot drift into a second copy: if the struck cell belongs to a
## root, that root's own pool drains by the SAME amount the shared pool just
## took — post shell tax, which for bare meat is 1:1 (`Ship.damage_cell` emits
## the drained figure, not the weapon's number).
##
## The reap is NOT done here — see `tick`.
func absorb_hit(cell: Vector2i, amount: float) -> void:
	if whale == null or not is_instance_valid(whale) or amount <= 0.0:
		return
	# A CARCASS HAS NO ARMS TO LOSE. `damaged` fires on the mining path too, and
	# a corpse being harvested must not pay for an exterior-air flood per hit.
	if not _is_alive():
		return
	# The first landed hit is a fine moment to learn the anatomy: a creature
	# nobody is fighting never pays for the flood, and one that IS being shot
	# has to know which arm is taking it.
	_ensure_sites()
	var i: int = int(_root_cells.get(cell, -1))
	if i < 0 or i >= _roots.size():
		return
	var root: Dictionary = _roots[i]
	root["hp"] = maxf(float(root["hp"]) - amount, 0.0)


## AN ARM THAT RAN OUT OF POOL COMES OFF THE BODY. Removing cells from a LIVING
## creature is new — everything else in the game removes blocks from a carcass —
## so this is the deliberate list of what it must not break:
##
##   * SEVERING. Not a severing pass: `remove_block(cell, false)` skips the
##     per-cell rebuild AND `_resolve_severing`, exactly as `strip_to_husk`
##     does, so cutting an arm off can never spray the crown into six
##     independent bodies. One coalesced `rebuild()` pays for the whole strip.
##   * THE COARSE COLLIDER. Rebuilt by that one `rebuild()`, like every other
##     structural change; a living creature's boxes are derived, never stored.
##   * THE SEALED CAVITY. `cavity_cells()` is latched at spawn and an arm is
##     exterior flesh: cutting one cannot breach the hoard.
##   * THE BITE. `_mouth_local` is pinned and is NOT recomputed here — only the
##     cluster list is. That is decision 3 in the header, and the test that
##     pins it.
##   * THE POOL. `shared_health` is untouched: an arm is not free damage, it is
##     a second bill you chose to pay.
func _reap_dead_roots() -> void:
	if not _sites_built or _roots.is_empty() or not _is_alive():
		return
	var doomed: Array[Vector2i] = []
	for r in _roots:
		if float(r["hp"]) > 0.0:
			continue
		for c in (r["cells"] as Array):
			doomed.append(c)
	if doomed.is_empty():
		return
	for c in doomed:
		whale.remove_block(c, false)
	_sites_built = false        # the clusters are stale; the pinned bite is not
	whale.rebuild()
	_ensure_sites()


## Cluster the body once and decide which cluster is the throat. Lazy: an
## exterior-air flood over a 416 × 200 8× bounding box is not something to pay
## for on a body nobody is fighting. Re-run only when an arm has actually come
## off (`_reap_dead_roots`).
func _ensure_sites() -> void:
	if _sites_built or whale == null or not is_instance_valid(whale):
		return
	_sites_built = true
	var exterior := whale.exterior_air()
	# THE BITE, PINNED ONCE (header decision 3): all exposed meat, the shipped
	# formula, and never recomputed however many arms come off afterwards.
	if _mouth_local == Vector2.INF:
		_mouth_local = _compute_mouth_local(exterior)
	var clusters := meat_clusters(whale.blocks, exterior)
	var ti := throat_index(clusters, whale.blocks)
	_throat_cells = clusters[ti] as Array[Vector2i] if ti >= 0 else ([] as Array[Vector2i])
	# A recomputed root INHERITS the damage its old self had taken (matched by a
	# shared cell), or shooting one arm and then killing another would heal the
	# first.
	var was := _roots
	_roots = []
	_root_cells = {}
	var per_cell := Tunables.get_num("kraken_root_hp_per_cell")
	for i in clusters.size():
		if i == ti:
			continue
		var cells: Array[Vector2i] = clusters[i]
		var hp_max := per_cell * _authored_cells(cells.size())
		var taken := 0.0
		for old in was:
			if (old["cells"] as Array).has(cells[0]):
				taken = maxf(float(old["hp_max"]) - float(old["hp"]), 0.0)
				break
		var idx := _roots.size()
		for c in cells:
			_root_cells[c] = idx
		_roots.append({
			"cells": cells,
			"local": cluster_centroid(cells) * Ship.CELL,
			"hp": maxf(hp_max - taken, 0.0),
			"hp_max": hp_max,
		})


## Blocks -> AUTHORED cells. At 8× every authored cell is an 8×8 patch of blocks,
## so a lever quoted per authored cell means the same thing at both scales.
func _authored_cells(blocks: int) -> float:
	var u := maxf(whale.scale_unit, 1.0)
	return float(blocks) / (u * u)


## --- The clustering, pure --------------------------------------------------
## Static and total so the suite can assert a body plan's anatomy straight off
## the `.ship` file, with no body, no world and no physics.

## The EXTERIOR-EXPOSED MEAT of `blocks`, 8-connected into clusters. `exterior`
## is `Ship.exterior_air()` — the air that reaches the outside, so a sealed loot
## cavity's inner meat walls are not an opening.
##
## EIGHT-connected, not four: see the header's decision 1 — the authored gullets
## are diagonal staircases and 4-connectivity shatters them.
##
## Deterministic: the flood starts from the SORTED cell list, because a
## Dictionary iterates in insertion order and a spawn payload's order is not a
## promise. The returned clusters are sorted too, so `cells[0]` is a stable
## identity for a root across a recompute.
static func meat_clusters(blocks: Dictionary, exterior: Dictionary) -> Array:
	var exposed := {}
	for cell in blocks:
		if int(blocks[cell]["type"]) != BlockDB.Type.MEAT:
			continue
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if exterior.has(cell + d):
				exposed[cell] = true
				break
	var starts := exposed.keys()
	starts.sort()
	var seen := {}
	var out: Array = []
	for start in starts:
		if seen.has(start):
			continue
		var group: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var n := Vector2i(c.x + dx, c.y + dy)
					if exposed.has(n) and not seen.has(n):
						seen[n] = true
						stack.append(n)
		group.sort()
		out.append(group)
	return out


static func cluster_centroid(cells: Array) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c as Vector2i)
	return sum / float(cells.size())


## WHICH CLUSTER IS THE THROAT — the one whose centroid is NEAREST the body's
## solid centroid (header decision 2). A throat is an opening IN the body; an arm
## trails away from it, so "nearest the interior" is the shape of the thing, and
## it is the rule that survives D's 11-cell throat beside a 12-cell arm where
## "largest wins" does not.
##
## Ties: the larger cluster, then the lowest first cell. Both are only there so
## two peers and two boots agree — no shipped plan reaches them.
## Returns -1 when there is no exposed meat at all (a fully-cased body).
static func throat_index(clusters: Array, blocks: Dictionary) -> int:
	if clusters.is_empty():
		return -1
	var centre := Vector2.ZERO
	var n := 0
	for cell in blocks:
		if not BlockDB.get_def(int(blocks[cell]["type"]))["solid"]:
			continue
		centre += Vector2(cell as Vector2i)
		n += 1
	if n > 0:
		centre /= float(n)
	var best := -1
	var best_d2 := INF
	for i in clusters.size():
		var d2 := (cluster_centroid(clusters[i]) - centre).length_squared()
		var better := d2 < best_d2 - 0.0001
		if not better and absf(d2 - best_d2) <= 0.0001 and best >= 0:
			var a: Array = clusters[i]
			var b: Array = clusters[best]
			better = a.size() > b.size() \
				or (a.size() == b.size() and (a[0] as Vector2i) < (b[0] as Vector2i))
		if better:
			best_d2 = minf(best_d2, d2)
			best = i
	return best


## The mouth centroid in authored body-local px: the average of the EXTERIOR-
## exposed MEAT cells (the mouth throat, plus a squid's tentacle roots). "Exterior"
## = adjacent to open air that reaches the outside — the sealed loot cavity's inner
## meat walls do NOT count, so this lands at the real opening. Falls back to the
## meat centroid if nothing is exposed (a fully-cased body), and to the body
## centre if there is no meat at all.
func _compute_mouth_local(exterior := {}) -> Vector2:
	var meat: Array[Vector2i] = []
	for cell in whale.blocks:
		if whale.blocks[cell]["type"] == BlockDB.Type.MEAT:
			meat.append(cell)
	if exterior.is_empty():
		exterior = _exterior_air()
	var sum := Vector2.ZERO
	var n := 0
	for cell in meat:
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if exterior.has(cell + d):
				sum += Vector2(cell)
				n += 1
				break
	if n == 0:  # fully cased — fall back to the meat centroid, then the body centre
		for cell in meat:
			sum += Vector2(cell)
		n = meat.size()
	if n == 0:
		return whale.solid_bounds.get_center()
	return (sum / float(n)) * Ship.CELL


## The air cells that reach the outside — used to tell the mouth opening from the
## sealed loot cavity. The flood itself lives on Ship now (Ship.exterior_air), so
## the mouth finder and the cavity map (Ship.cavity_cells, its complement) can
## never disagree about what "sealed" means.
func _exterior_air() -> Dictionary:
	return whale.exterior_air()
