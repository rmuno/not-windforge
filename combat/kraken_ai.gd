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
## Krakens are UNTAMEABLE (world.try_tame refuses `creature_kind == "kraken"`), so
## the tamed/ridden branches inherited from WhaleAI never engage here; a kraken is
## always the wild, hunting brain. Aggression: it does not wait to be attacked —
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
	# Aggression: hunt on sight. A wild kraken keeps itself provoked while a living
	# prey is around, so the inherited align→push→glide ram runs immediately (the
	# whale only rams AFTER being hit; the kraken does not wait). Untameable, so
	# `tamed` is never set — but guard it anyway to stay honest with the base class.
	if not tamed and not ridden and prey_ship != null and is_instance_valid(prey_ship) \
			and not prey_ship.is_carcass():
		_provoked_until = Time.get_ticks_msec() + HUNT_RESTAMP_MS
	super.tick(delta, target)
	# The mouth grab rides ON TOP of the inherited swim/ram: a living, wild kraken
	# whose mouth has reached the prey chews it continuously. Two prey KINDS, one
	# mouth: the block grid of a ship, and the PERSON standing in the jaws.
	grabbing = false
	grabbing_player = false
	if not _is_alive() or tamed:
		return
	if prey_ship != null and is_instance_valid(prey_ship) and not prey_ship.is_carcass():
		_mouth_grab(delta, prey_ship)
	_mouth_grab_player(delta)


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
## paths cannot drift apart; krakens are untameable, but the base class is not.)
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
