class_name Hazards
extends Node2D

## Environmental hazards that make altitude MEAN something (ROADMAP Phase 2):
## meteors sweep the TOP band, the lava core erupts from the FLOOR. Both are the
## owner's hazard rule made real (DECISIONS 2026-08-18): hazards are BROAD,
## in-place, PREPARABLE, and NEVER camera-radius. A meteor is anchored to a world
## column and falls slowly from well above you — you see it coming and plan around
## it — the exact opposite of the original's spawn-on-a-ring-just-off-camera
## jumpscare, which was rejected outright ("no room for preparation, inorganic,
## absolutely annoying"; WORLD_SPEC top band).
##
## Resident-world discipline (DECISIONS: population is world-anchored, inert away
## from players): the whole system is OFF-cost unless a focus (player/ship) is
## actually IN a hazard band. update() early-outs on one pair of band checks,
## spawning nothing and paying nothing otherwise — so mid-band flight and the
## normal startup (the arena spawn is mid-band) never fire a hazard.
##
## Band geometry reads the world rect + Airspace band FRACTIONS directly, because
## Airspace.bounds is generation-only and empty in flight (map_view.gd does the
## same). Damage reuses the existing paths — Ship.net_damage_cell for hulls,
## Terrain.net_dig for ground — through HazardFireball; no new damage model.
##
## Authority-only, like whale spawning (world.gd gates the call): hazards edit
## authoritative state, and networked hazard replication is a documented seam.

# --- Meteors (top band) ----------------------------------------------------
## Seconds between meteors while a focus is up top (the cadence knob).
const METEOR_INTERVAL := 3.5
## Slow (owner: "small fireballs fall slowly"). Unscaled px/s; ×scale_unit.
const METEOR_SPEED := 95.0
const METEOR_DAMAGE := 60.0
## A shallow arc — mostly a straight slow fall (see Shot.GRAVITY_FACTOR reasoning).
const METEOR_GRAVITY_FACTOR := 0.03
## Half-width of the BROAD drop zone around a focus (unscaled px): meteors are
## spread across a wide stretch of the band, not dropped in one spot.
const METEOR_SPREAD := 2600.0
## A meteor never spawns closer than this ABOVE a focus — so it is always seen
## coming and can never be a drop-on-your-head jumpscare (the hazard rule).
const METEOR_MIN_GAP := 600.0
## Spawn X is snapped to this world grid (unscaled px): a meteor targets a fixed
## world COLUMN, not a screen pixel — world-anchored, never camera-relative.
const METEOR_COLUMN := 64.0

# --- Lava core (floor) -----------------------------------------------------
const LAVA_INTERVAL := 2.2
## Upward launch speed; gravity arcs it back down like a shell. Unscaled px/s.
const LAVA_SPEED := 560.0
const LAVA_DAMAGE := 80.0
## A real ballistic arc — heavier pull than a meteor so it rises and falls back.
const LAVA_GRAVITY_FACTOR := 0.18
## Half-width of the eruption spread around a focus (unscaled px).
const LAVA_SPREAD := 2200.0

## How far past a band still counts as "near" it (fraction of world height) — the
## "in OR near the band" the spec asks for. Small enough that MID never triggers.
const NEAR_FRAC := 0.03

## The world extents the sky maps onto (set by world.gd at this scale). Empty →
## the system is inert (matches Airspace.active(): no sky, no weather).
var world_rect := Rect2()
var scale_unit := 1.0
var terrain: Terrain = null

var _meteor_cd := 0.0
var _lava_cd := 0.0
var _rng := RandomNumberGenerator.new()


## 0 at the floor, 1 at the ceiling — the same convention as Airspace, computed
## from this scale's world rect (Airspace.bounds is empty in flight). -1 when the
## system is inert (no world rect set).
func _altitude_frac(y: float) -> float:
	if world_rect.size.y <= 0.0:
		return -1.0
	return clampf((world_rect.end.y - y) / world_rect.size.y, 0.0, 1.0)


## The first focus in (or near) the TOP band, or null — the meteor gate.
func _first_in_top(foci: Array) -> Variant:
	for f in foci:
		if _altitude_frac((f as Vector2).y) >= Airspace.GAP_HIGH_TOP - NEAR_FRAC:
			return f
	return null


## The first focus near the floor (in the DEEP band or below), or null — the lava
## gate.
func _first_near_floor(foci: Array) -> Variant:
	for f in foci:
		var a := _altitude_frac((f as Vector2).y)
		if a >= 0.0 and a <= Airspace.DEEP_TOP + NEAR_FRAC:
			return f
	return null


## Public band predicates (readable in tests): is any focus up top / near floor.
func any_in_top(foci: Array) -> bool:
	return _first_in_top(foci) != null


func any_near_floor(foci: Array) -> bool:
	return _first_near_floor(foci) != null


## Drive the hazards for one frame. The single early-out is the whole off-cost
## story: with no focus in a hazard band this returns immediately, having spawned
## nothing. `foci` are world positions (the same player+ships set that streams
## terrain). Authority gates the CALL (world.gd), not this method.
func update(delta: float, foci: Array) -> void:
	if world_rect.size.y <= 0.0 or foci.is_empty():
		return
	var top_focus: Variant = _first_in_top(foci)
	var floor_focus: Variant = _first_near_floor(foci)
	if top_focus == null and floor_focus == null:
		return   # OFF-COST: no focus in a hazard band — spawn nothing, pay nothing

	if top_focus != null:
		_meteor_cd -= delta
		if _meteor_cd <= 0.0:
			_meteor_cd = Tunables.get_num("meteor_interval")
			spawn_meteor(top_focus)
	if floor_focus != null:
		_lava_cd -= delta
		if _lava_cd <= 0.0:
			_lava_cd = Tunables.get_num("lava_interval")
			spawn_lava(floor_focus)


## Spawn one meteor over `focus`. Broken out (public) so tests can gather the
## spread without waiting out the cadence.
func spawn_meteor(focus: Vector2) -> HazardFireball:
	# X: a BROAD, world-ANCHORED spread. Random across a wide window, then SNAPPED
	# to a world column — so a meteor names a fixed world position, not a fixed
	# offset from the camera (the rejected camera-ring). Across several spawns the
	# X's fan out across the band; none sit at a constant distance from you.
	var half := METEOR_SPREAD * scale_unit
	var col := METEOR_COLUMN * scale_unit
	var x := focus.x + _rng.randf_range(-half, half)
	x = roundf(x / col) * col
	x = clampf(x, world_rect.position.x, world_rect.end.x)
	# Y: somewhere in the TOP band ABOVE the focus, but never closer than
	# METEOR_MIN_GAP — always seen coming, never dropped on your head.
	var lo := world_rect.position.y + 40.0 * scale_unit
	var hi := focus.y - METEOR_MIN_GAP * scale_unit
	if hi < lo:
		hi = lo
	var y := _rng.randf_range(lo, hi)

	var fb := HazardFireball.new()
	fb.kind = HazardFireball.Kind.METEOR
	fb.position = Vector2(x, y)
	# A slow fall, with a slight sideways drift so a stream reads as organic.
	var mspeed := Tunables.get_num("meteor_speed")
	fb.velocity = Vector2(_rng.randf_range(-0.15, 0.15) * mspeed, mspeed) * scale_unit
	fb.gravity = 980.0 * scale_unit * METEOR_GRAVITY_FACTOR
	fb.damage = Tunables.get_num("meteor_damage")
	fb.terrain = terrain
	fb.visual_scale = scale_unit
	add_child(fb)
	return fb


## Erupt one lava fireball under `focus`. Public for the same test reason.
func spawn_lava(focus: Vector2) -> HazardFireball:
	var half := LAVA_SPREAD * scale_unit
	var x := clampf(focus.x + _rng.randf_range(-half, half),
		world_rect.position.x, world_rect.end.x)
	var y := world_rect.end.y - 2.0 * scale_unit    # erupts AT the floor

	var fb := HazardFireball.new()
	fb.kind = HazardFireball.Kind.LAVA
	fb.position = Vector2(x, y)
	# Launched UP; gravity brings it back down — a ballistic arc like a shell.
	var lspeed := Tunables.get_num("lava_speed")
	fb.velocity = Vector2(_rng.randf_range(-0.3, 0.3) * lspeed, -lspeed) * scale_unit
	fb.gravity = 980.0 * scale_unit * LAVA_GRAVITY_FACTOR
	fb.damage = Tunables.get_num("lava_damage")
	fb.terrain = terrain
	fb.visual_scale = scale_unit
	add_child(fb)
	return fb
