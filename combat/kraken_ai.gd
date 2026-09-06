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

## The mouth point in AUTHORED body-local px (centroid of the exterior-exposed
## meat — the soft opening). Computed once from the body; Vector2.INF = not yet.
var _mouth_local := Vector2.INF
## Read by tests/debug: was the mouth latched onto prey this tick?
var grabbing := false

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


func tick(delta: float, target: Node2D) -> void:
	if whale == null or not is_instance_valid(whale):
		return
	# The Ship-shaped prey (the caller's nearest-ship fallback). The base class
	# takes Node2D now (retaliation can target the on-foot player), but the
	# kraken's own additions — the hunt restamp and the per-cell mouth grab —
	# need a block grid, so they act on the SHIP prey only.
	var prey_ship := target as Ship
	# Aggression: hunt on sight. A WILD kraken keeps itself provoked while a
	# living prey is around, so the inherited align→push→glide ram runs
	# immediately (the whale only rams AFTER being hit; the kraken does not
	# wait). A tamed one stops hunting — but stays dangerous (below).
	if not tamed and not ridden and prey_ship != null and is_instance_valid(prey_ship) \
			and not prey_ship.is_carcass():
		_provoked_until = Time.get_ticks_msec() + HUNT_RESTAMP_MS
	super.tick(delta, target)
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
	if not _is_alive():
		return
	if prey_ship != null and is_instance_valid(prey_ship) and not prey_ship.is_carcass():
		_mouth_grab(delta, prey_ship)
	_mouth_grab_player(delta)


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
## so a roaming or aligning kraken still pitches into its own motion.
func _pose_tilt_target() -> float:
	if _phase == Phase.NONE or _push_dir == Vector2.ZERO:
		return super._pose_tilt_target()
	var d := -_push_dir if _phase == Phase.COIL else _push_dir
	# atan2 against the horizontal MAGNITUDE, times the facing: the body is
	# reflected about x when it swims left (v0.14.0), so the same downward
	# heave needs the opposite rotation sign to read as nose-into-motion —
	# the identical transform the inherited velocity pose applies.
	return clampf(atan2(d.y, absf(d.x)), -Ship.POSE_MAX, Ship.POSE_MAX) \
		* float(whale.visual_facing)


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
## mouth and, if it is within bite range, drain it by GRAB_DPS·delta. Cheap: the
## O(cells) nearest-cell scan runs only after a coarse whole-body proximity gate,
## so it costs nothing until the mouth is actually near the prey.
func _mouth_grab(delta: float, target: Ship) -> void:
	var mouth := _mouth_world()
	var u := whale.scale_unit
	var reach := Tunables.get_num("kraken_grab_reach") * u
	# Coarse gate: skip the per-cell scan unless the mouth is near the prey body at
	# all (reach + the prey's own extent). solid_bounds is body-local px.
	var coarse := reach + target.solid_bounds.size.length()
	if (mouth - target.global_position).length() > coarse:
		return
	var best_cell := Vector2i.ZERO
	var best_d2 := INF
	for cell in target.blocks:
		if not BlockDB.get_def(target.blocks[cell]["type"])["solid"]:
			continue
		var d2 := (target.to_global(target.local_pos_of(cell)) - mouth).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best_cell = cell
	if best_d2 <= reach * reach:
		target.net_damage_cell(best_cell, Tunables.get_num("kraken_grab_dps") * delta)
		grabbing = true


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
func _mouth_grab_player(delta: float) -> void:
	if prey_player == null or not is_instance_valid(prey_player) \
			or not prey_player.has_method("take_damage"):
		return
	var reach := Tunables.get_num("kraken_grab_reach") * whale.scale_unit
	if (prey_player.global_position - _mouth_world()).length_squared() > reach * reach:
		return
	prey_player.take_damage(Tunables.get_num("kraken_grab_dps") * delta)
	grabbing_player = true


## The mouth in WORLD space. Mirrors the authored point with the body's facing
## (the collider mirrors with the skin, v0.14.0), so the mouth tracks the drawn
## head whichever way the kraken is swimming.
func _mouth_world() -> Vector2:
	if _mouth_local == Vector2.INF:
		_mouth_local = _compute_mouth_local()
	return whale.to_global(whale._mirror_point(_mouth_local))


## The mouth centroid in authored body-local px: the average of the EXTERIOR-
## exposed MEAT cells (the mouth throat, plus a squid's tentacle roots). "Exterior"
## = adjacent to open air that reaches the outside — the sealed loot cavity's inner
## meat walls do NOT count, so this lands at the real opening. Falls back to the
## meat centroid if nothing is exposed (a fully-cased body), and to the body
## centre if there is no meat at all.
func _compute_mouth_local() -> Vector2:
	var meat: Array[Vector2i] = []
	for cell in whale.blocks:
		if whale.blocks[cell]["type"] == BlockDB.Type.MEAT:
			meat.append(cell)
	var exterior := _exterior_air()
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
