class_name Ship
extends RigidBody2D

## A player-authored grid of blocks simulated as a single rigid body.
##
## The whole game hangs off this class, so the invariants matter:
##   * `blocks` is the single source of truth. Collider, mass, centre of mass
##     and rendering are all derived from it by `rebuild()`.
##   * The ship simulates as ONE thing (owner 2026-08-20): rotation is
##     LOCKED (the upright rule below), which makes a force at an offset
##     identical to a central force — so flight is three aggregate
##     central forces from rebuild()-cached totals, with zero per-block
##     work at runtime. What each block contributes is settled once per
##     structural change, so damage still changes flight the same frame,
##     and translation remains a consequence of how the player built.
##   * Destroying a block can disconnect the grid. `_resolve_severing()` finds
##     the disconnected islands and spawns them as independent ships.

signal block_destroyed(cell: Vector2i, type: int)
## Any hp actually lost, from any cause — shots, crashes, debug pokes.
## The world uses it to let a crew REACT to being hit (owner 2026-08-20):
## provocation, not bookkeeping. Fires on the authority only, since that
## is where damage_cell runs.
signal damaged(cell: Vector2i, amount: float)
## Collision/impact damage that actually landed, with its WORLD contact point.
## Unlike `damaged` (which fires for EVERY cause — shots, crashes, the whale
## pool drain), this fires ONLY from the crash-crush path (_process), so a
## listener can float a damage number exactly where a collision bit and never
## for gunfire. Authority-only, like the crush itself. (owner 2026-08-22)
signal collision_damage(world_pos: Vector2, amount: float)
## Combat (gunfire) damage that landed on a cell, with its WORLD point. The
## gunfire twin of `collision_damage`: fired ONLY from the net_damage_cell shot
## path (authority side), so a listener floats a damage number for every shot
## that bites — including a whale, whose hits vanish into the shared pool and so
## never showed a number before (owner 2026-08-23: "turrets shooting whales seem
## to produce no damage numbers"). Kept separate from `damaged` because that also
## fires from the crash crush, which already floats via collision_damage — one
## number per hit, never two.
signal combat_damage(world_pos: Vector2, amount: float)
signal severed(new_ship: Ship)
signal destroyed

const CELL := 16.0

## Air thins with altitude, so lift falls off and every ship has a ceiling set
## by its own lift-to-weight ratio. Godot's Y axis grows downward: up is -Y.
const SEA_LEVEL_Y := 0.0
const CEILING_Y := -24000.0
const MIN_AIR_DENSITY := 0.05

## --- Upright rule (owner spec 2026-08-20, source fidelity) ---------------
## Ships are ALWAYS upright, regardless of configuration — a lone block no
## less than a battleship. The original never banks or tumbles, and every
## rotational failure mode (death spins, crash pivots, walking on a tilting
## deck) is deleted wholesale by `lock_rotation` in _ready(): the solver
## treats the hull as un-rotatable, so there is nothing to tune and no
## settle time. This replaced the earned PD flight assist and the emergent
## gasbag self-righting — see docs/DECISIONS.md.

## Altitude hold: with no W/S input, the lift props automatically trim against
## buoyant imbalance and damp vertical drift — so the player builds *roughly*
## balanced and the props do the bookkeeping, instead of hand-tuning gasbags
## against every mass change. Authority is capped by the ship's real lift-prop
## thrust and it draws real power, so it is earned like everything else: no
## props or no engines means no hover, and wreckage (assist off) drifts free.
const HOVER_DAMP := 2.0          ## damping on vertical speed, per second
const HOVER_MIN_FORCE := 200.0   ## dead-zone; below this the props stay quiet

## Contact impulse scales with mass (impulse ≈ mass × Δv), so for the ~250-mass
## starter this threshold forgives touches up to ~80 px/s and starts charging
## for real slams. The old value (900) punished anything over ~4 px/s — found
## the moment the arena box made wall contact routine.
const IMPACT_DAMAGE_THRESHOLD := 20000.0
const IMPACT_DAMAGE_SCALE := 0.01

## A living creature takes a crash ONCE, into its shared pool, damped by this
## factor — flesh flexes where wood shatters. This is THE knob for how much
## collisions hurt creatures relative to gunfire, and it covers both vessel
## rams and terrain (terrain now also bills once per contact episode for a
## living body — see _integrate_forces).
##
## Anchored at the shipped 8× (whale mass 37,184, pool 15,000): a full-speed
## terrain crash kills ~3,800 px/s in the one step the solver needs, carrying
## `available` = (3800·37184 − 20000·8³)·0.01/8² ≈ 20,500 → 1,024 hp, 6.8% of
## the pool; a full vessel ram (`available` ≈ 10,000) costs ~500. A 20 s angry
## chase past a wall block and the ground costs ~385 hp total (2.6%): a
## CHARGING creature is immune along its charge, so only its clumsy
## align-phase clouts are billed. All well inside the owner's "noticeable
## bruise, never death" band — so this stayed at 0.05 when the 2026-08-21
## death report was fixed. That report was chiefly a BILLING bug (the
## ram-immunity race, see _is_ram_immune); the terrain factor below is the
## smaller magnitude half.
const CREATURE_IMPACT_FACTOR := 0.05

## Terrain crashes bill a living creature at this GENTLER factor than a
## vessel ram (above). A whale CHOOSES to ram a ship — that is its attack,
## and the victim pays the vessel factor — but it does not choose to clip
## the scenery mid-chase; an incidental clout off a world block should
## sting, not gut it. At 0.02 a full-speed 8× terrain crash costs ~410 hp
## (2.7% of WHALE_HEALTH) instead of ~1,024 (6.8%), so a whole angry chase
## that crashes a few times stays a bruise. Vessels never reach this path
## (living creatures only); a carcass crushes per-cell like any hull.
const CREATURE_TERRAIN_IMPACT_FACTOR := 0.02

## cell -> {"type": int, "hp": float}
var blocks: Dictionary = {}

## The structural WALL layer (owner spec, from the original's model): a set
## of cells (cell -> true) that holds the ship together. Walls are
## indestructible to combat, never collide, and cause no damage — combat
## only ever touches the blocking tiles in `blocks`. As long as a cell's
## wall stands, the ship's integrity there survives the block's
## destruction: pieces only fall off when walls themselves are REMOVED
## (deconstruct/mining — remove_block), never when blocks are shot away.
## Initialised to the ship's built footprint; building extends it.
var walls: Dictionary = {}

## --- Kinematic pose (owner-approved 2026-08-20) --------------------------
## The solver can never rotate a ship (the upright rule), but a creature
## may STRIKE A POSE: WhaleAI pitches into its motion, as source whales
## angle ~30° each way. The pose is a TARGET angle; every ship eases its
## rotation toward its target (default 0, cost-free when already level),
## which also rights inherited tilt — a severed chunk of a pitched whale
## settles flat instead of freezing mid-pose.
const POSE_MAX := 0.55   ## rad ≈ 31° — the source's observed range
const POSE_EASE := 3.0   ## approach rate, per second

var _pose_tilt := 0.0


func set_pose_tilt(angle: float) -> void:
	_pose_tilt = clampf(angle, -POSE_MAX, POSE_MAX)


## --- Visual facing (ROADMAP Q10; owner REVERSED the constraint 2026-08-21) -
## A creature's DRAWN body faces where it swims. The head is authored +x
## (ships/whale.ship), so a whale swimming left has to show its head on the
## left or it reads as swimming backwards.
##
## THE COLLIDER MIRRORS WITH THE SKIN (owner 2026-08-21, reversing the
## original "never mirror geometry" pin). The drawn body and the physical
## collider must occupy the SAME reflected-and-pitched shape, so a probe
## into the drawn head hits solid body on that same side. The mirror is a
## reflection about the vertical centreline of the SOLID footprint (see
## _mirror_axis_x), applied IDENTICALLY to the draw transform (_draw) and to
## the CollisionShape2D positions (_rebuild_collider). `blocks`, `walls`,
## `solid_bounds`, mass, centre of mass and severing all derive from the
## authored grid and never move — only the DERIVED collider geometry and the
## drawing reflect. The owner accepts the rider-dump risk this reintroduces
## (the source's flip teleports the cone head out from under anyone standing
## on it; DECISIONS 2026-08-20 "fiddly").
##
## The reflection lives in the collider SHAPES, not in the body transform,
## so the RigidBody's own transform stays a clean rotation+translate
## (positive determinant): Godot 2D physics never sees a mirrored body, and
## contacts / impact damage resolve normally. The contact→cell path
## UN-reflects the recorded point (see _impact_cell and _process) so a crush
## on the mirrored collider bills the authored cell it visually struck.
##
## The pose tilt (see POSE_MAX) is a REAL eased node rotation shared by the
## drawing and the collider alike. A body reflected about x needs the
## OPPOSITE rotation sign for its nose to read as pitched into the motion,
## so WhaleAI multiplies its tilt target by this facing — and now the
## collider, reflected the same way, pitches to AGREE with the drawing
## instead of against it (which is the whole point of the reversal).
##
## +1 = head drawn toward +x (the authored form) · -1 = mirrored.
var visual_facing := 1

## Hysteresis: horizontal speed (unscaled px/s, ×scale_unit) a body must
## exceed in the OPPOSITE direction before the skin flips. Below it the
## last facing simply HOLDS, so a creature hovering, station-keeping on its
## own buoyancy or nudged by wind never flickers back and forth. 6 sits
## well under a roaming whale's ~20 px/s cruise (WhaleAI.ROAM_ACCEL 8
## against linear_damp 0.4, terminal a/damp) so the figure-eight still
## turns around at its ends, and well over the sub-px/s jitter of a body
## doing nothing in particular.
const FACING_FLIP_SPEED := 6.0

## Last frame's position, the facing signal's only input. Deliberately
## position DELTA rather than `linear_velocity`: a client's hull is a
## FROZEN kinematic driven by _follow_net_pose, so the only signal that
## exists and means the same thing on both sides of the wire is how far the
## drawn body actually moved. One rule, one code path, server and client —
## and no new replicated property (facing costs nothing on the wire).
var _facing_prev_pos := Vector2.ZERO
var _facing_has_prev := false


## Derive the drawn facing from where the body actually went last frame.
## Runs for LIVING CREATURES ONLY, and that is two rules in one:
##   * a vessel (shared_health_max == 0) has no facing — it is drawn as
##     authored, forever, and hulls are unaffected by any of this;
##   * a CARCASS (pool empty) freezes whatever it was facing when it died.
##     A corpse does not turn to face its own drift.
func _update_visual_facing(delta: float) -> void:
	var moved := position - _facing_prev_pos
	var had_prev := _facing_has_prev
	_facing_prev_pos = position
	_facing_has_prev = true
	if not had_prev or delta <= 0.0:
		return  # first frame: nothing to compare against yet
	if shared_health_max <= 0.0 or shared_health <= 0.0:
		return  # not a living creature — see above
	var vx := moved.x / delta
	var threshold := FACING_FLIP_SPEED * scale_unit
	var want := visual_facing
	if vx > threshold:
		want = 1
	elif vx < -threshold:
		want = -1
	if want != visual_facing:
		visual_facing = want
		# The collider mirrors WITH the skin (owner 2026-08-21): rebuild the
		# derived collision shapes reflected about the footprint centre so the
		# physical body matches the drawing. Flips are rare (the hysteresis
		# above holds a station-keeping body steady), so a rebuild-on-flip is
		# cheap. This runs in _physics_process, BEFORE the solver step, so the
		# step sees the mirrored collider; mass/CoM/severing derive from the
		# authored grid and are untouched.
		_rebuild_collider()
		# _draw output persists until the next redraw (godot-quirks), and a
		# creature that is only being mirrored has no other reason to redraw.
		queue_redraw()


## True when the DRAWN body — and now the collider — is reflected about the
## solid footprint's vertical centreline. The same condition the _draw mirror
## uses: only a living creature or its carcass ever holds facing -1, and it
## needs a real solid footprint to have an axis. A vessel never reaches it.
func _is_mirrored() -> bool:
	return visual_facing < 0 and solid_bounds.size.x > 0.0


## The body-local x the mirror reflects about: the centre of the SOLID
## footprint, identical to the _draw transform's axis, so the reflected
## drawing and collider occupy exactly the AABB solid_bounds still describes.
func _mirror_axis_x() -> float:
	return solid_bounds.position.x + solid_bounds.size.x * 0.5


## Reflect a body-local point about the mirror axis when the body is mirrored;
## the identity otherwise. Used to place collider shapes on the drawn side, and
## to carry a recorded contact point back to authored-grid space.
func _mirror_point(p: Vector2) -> Vector2:
	if _is_mirrored():
		return Vector2(2.0 * _mirror_axis_x() - p.x, p.y)
	return p


## --- Creature body (owner 2026-08-20) ------------------------------------
## A living creature is ONE unit: damage anywhere drains a shared pool
## and its blocks stay whole — no tiny squares popping off a live whale.
## When the pool empties the creature is DEAD, and only then does the
## body become ordinary breakable blocks (mining a carcass). 0 max means
## "not a creature" — every ship behaves as before. Wounding is drawn as
## whole-body darkening by pool fraction.
var shared_health := 0.0
var shared_health_max := 0.0

## Whale carcasses carry a stomach full of swallowed loot (WIKI_REFERENCE: the
## whale doubles as a treasure container). Set once the first time the corpse is
## harvested so the fixed stomach drop is awarded exactly once per carcass. The
## drop TABLE itself is a `[?]` — a fixed placeholder for now (see take_stomach_loot).
var _stomach_looted := false

## --- The sealed LOOT CAVITY (kraken bodies, 2026-08-24) --------------------
## Both authored kraken plans wall a hollow POCKET into the middle of the meat
## (ships/kraken_*.ship: "a meat-walled LOOT CAVITY -- mine through to reach
## it"). Unlike the mouth aperture, that air never reaches the outside, so it is
## a container you have to CRACK: harvest a wall cell off the carcass and the
## bundle spills, exactly once. Same shape as the whale's stomach drop above.
##
## `_cavity_cells` is LATCHED the first time it is asked for, because a breach is
## precisely the thing that destroys the evidence — once the wall is gone the
## flood reaches the pocket and it stops looking like a cavity at all. The probe
## in harvest_cell runs BEFORE the removal, and the world latches it at spawn
## (world._spawn_one_kraken), so the map is always taken off the whole body and
## an eroding corpse is still measured against the ORIGINAL cavity.
##
## SEAM (shared with `_stomach_looted`): neither flag rides the spawn payload nor
## the save file, so a corpse that survives a host migration or a save/load
## forgets it was looted and can be cracked twice. One fix serves both when
## carcass state is persisted — docs/BACKLOG.md.
var _cavity_cells := {}
var _cavity_mapped := false
var _cavity_breached := false
var _cavity_looted := false

## What a breached cavity pays out: entries of [item_id, count]. TERRAIN-range
## ItemDB ids (a terrain item's id IS its TerrainDB.Type — see items/item_db.gd),
## so this invents no new item type; it is a buried cache of the deep's own
## materials — the aetherite prize the band is mined for, plus the grit it sat in.
const CAVITY_LOOT := [
	[TerrainDB.Type.AETHERITE, 12],
	[TerrainDB.Type.STONE, 3],
]

## Test/debug escape hatch: force the exact per-cell collider even on a living
## creature (defeats the coarse path in _use_coarse_collider). Off in all normal
## play; the break-the-fix test flips it to prove the coarse path is what buys
## the living creature its lower shape count.
var force_precise_collider := false

## While a creature CHARGES, collisions along its charge direction never
## damage the charger — a ram is its attack, not self-harm (owner spec;
## bullets are unaffected, they damage via the shot path, not contacts).
## ZERO disables. Set per-tick by the creature's AI.
var ram_immunity_dir := Vector2.ZERO

## Taming difficulty TIER (the small→whale progression, WIKI). A small critter is
## tier 1; a great whale is tier 2. The LORE taming gate is `Stats.taming_level()
## >= tame_level` (world.try_tame), so a whale needs the higher perk and a critter
## the lower one. 1 for plain vessels too, but faction gates those out of taming.
var tame_level := 1

## Multiplier on the RIDE throttle (WhaleAI ridden branch). 1.0 for a whale; a
## small critter rides NIMBLER (>1.0). Cosmetic to physics elsewhere — only the
## rider's steering force reads it, so a wild creature swims exactly as before.
var ride_speed_mult := 1.0

## Which brain a faction-2 creature gets, and the taming/AI switch. "" (a plain
## whale/critter) uses WhaleAI; "kraken" uses the two-ended KrakenAI (mouth grab +
## shell-tip ram) and is UNTAMEABLE (world.try_tame refuses it). Rides the payload
## so a rehomed/loaded kraken stays a kraken; default "" keeps every legacy ship a
## whale-brained creature, unchanged.
var creature_kind := ""

## --- Tethered lift balloons (carcass-as-airship, owner 2026-08-23) ------------
## Helium balloons bolted onto a body's cell by cable(s): EXTERNAL lift you attach
## to a corpse (which has none of its own) to fly it. Buoyancy alone only floats;
## these are the lift you add. Each entry is {"cell": Vector2i, "size": int}. A
## balloon's lift is folded into _total_lift in rebuild(), so the WHOLE flight /
## hover / ceiling model accounts for it (a taut cable transmits the lift to the
## body; the balloon renders above on its cable — see WorldOverlay). A balloon
## whose anchor cell is mined or severed away DETACHES on the next rebuild. Rides
## the payload + save so a built airship persists.
## THE SOURCE MODEL (owner 2026-08-24, correcting the v1 seam list): balloons are
## RIGID PREBUILT PLACEABLES — a few fixed sizes, each with a SET number of
## tethers, and NOT independently destructible cell by cell: "when the balloon is
## damaged or destroyed, the entire placeable has the same effect (no need to
## destroy EVERY block of the balloon, just have to hit it from anywhere)". So a
## balloon is ONE object with ONE hp pool: any hit anywhere on its bulb damages
## the whole thing, and at zero it POPS entirely — its lift gone in an instant,
## which is the drama (a shot balloon drops what it was holding up).
enum BalloonSize { SMALL, MEDIUM, LARGE }
## Lift each size adds (same units as a block's lift — a gasbag is 44; these are
## big external balloons). Generous: a handful floats a mined-down corpse chunk.
## THE balloon feel knob (ram/whatnot elsewhere).
const BALLOON_LIFT := [250.0, 480.0, 750.0]
## Cable count per size — small ONE, medium TWO, large THREE (owner's spec:
## "the smallest only has 1 tether, and the largest has 3"). Visual only (the
## lift is applied at the anchor); read by the renderer.
const BALLOON_CABLES := [1, 2, 3]
## Balloon body radius in cells (×scale): small ~a cell, large a few — 16×16 vs
## ~64×32 at 1× (owner). Renderer reads it.
const BALLOON_RADIUS_CELLS := [1.2, 1.9, 2.6]
## Hit points per size — the WHOLE placeable's pool, not per cell. Bigger bags
## are bigger targets and take a little more to burst.
const BALLOON_HP := [60.0, 90.0, 120.0]
## How high above its anchor a balloon rides on a taut cable, in cells (×scale).
const BALLOON_CABLE_CELLS := 6.0
## Attached balloons: {"cell": Vector2i, "size": int, "hp": float}. `hp` is the
## placeable's single pool (see BALLOON_HP) — legacy entries without it are
## healed to full on load.
var balloons: Array = []

## A balloon POPPED at this world point (its bulb centre) — the world floats a
## damage number / cue and the renderer stops drawing it. Emitted from
## damage_balloon only, so it fires exactly once per burst.
signal balloon_popped(at: Vector2, size: int)

## TRUE only while a mining-capable mount (a ridden whale) is actively being
## driven — the world sets it each frame in _handle_riding and clears it on
## dismount. It converts the whale's terrain CRUSH into terrain IMMUNITY (see
## _integrate_forces): a whale mining through terrain must NOT bill its shared
## pool for the terrain it is eating, or it suicides on its own dig (owner spec).
## A wild whale keeps this false and crashes into terrain exactly as before.
var ridden_mining := false

## Instance id of the last thing that SHOT this body (the player on foot, a
## piloted ship, a bandit ship) — stamped by Shot just before net_damage_cell,
## read by the world's provoke wiring so a creature retaliates against its
## ACTUAL attacker, not the nearest player-side ship (owner 2026-08-24: "if I
## shoot a whale on foot, the whale goes for the ship???"). An id, not a ref,
## so a freed attacker can never dangle; 0 = unattributed (terrain, hazards).
var last_attacker_id := 0


## Pilot input, matching the original's model: propellers push the hull around,
## the ship does not steer like a car. x = right(+)/left(−) via propellers,
## y = up(+)/down(−) via lift props. Both -1..1.
var thrust_input := Vector2.ZERO
## Gates the altitude hold only (rotation needs no assist — the upright
## rule is unconditional). False on wreckage: a dead hull does not trim.
var assist_enabled := true

## Peer id allowed to fly this ship. 0 means nobody — wreckage, derelicts.
var pilot_peer := 1

## Damage allegiance. Shots never harm a ship of their own faction: your
## own bullets pass through your hull (charter §9 — no stray-click
## self-damage), and enemies lined up in your firing line do not chew each
## other down (the original's clunk, rejected by the owner).
## 0 = player side · 1 = hostiles (wear the red cast, crews man guns) ·
## 2 = wildlife (whales: neutral, no tint, provoked by damage — see
## combat/whale_ai.gd).
var faction := 0

## Cosmetic-only body tint, multiplied over every block colour in _draw. White
## (identity) for every normal ship — the sole use today is a hidden easter-egg
## whale variant (maps/world/easter_eggs.gd → the Pale Wanderer). Never touches
## mass, collision, damage or the wire format; it is pure skin.
var body_tint := Color.WHITE

## World-scale experiment: the ship's linear feel multiplier, riding every
## spawn payload. 1 is the shipped game and changes nothing. At S, every
## distance in the world is S× bigger, so preserving *feel* (times, not
## pixel speeds) requires: gravity, thrust and lift ×S (accelerations
## scale with distance), impact thresholds ×S³ (momentum = mass·v ∝ S²·S),
## and the air column stretched ×S (or the sky's ceiling sits inside the
## arena). Rotation does not exist for ships (the upright rule).
## The setter re-derives the grid aggregates when the scale changes after
## construction (spawn payloads and tests assign it post-build): component
## MASS normalises by footprint (see _fp_norm) and is baked at rebuild, so
## a stale scale would leave the body's mass wrong.
var scale_unit := 1.0:
	set(v):
		var changed := not is_equal_approx(scale_unit, v)
		scale_unit = v
		if changed and not blocks.is_empty() and is_inside_tree():
			rebuild()

## Local-px AABB over the SOLID cells, rebuilt with the grid. This is the
## live-grid cache gunnery and the enemy AI lean on (owner: "keep this in
## the blueprint to cache computations" — the blueprint is the *intended*
## ship, but combat reshapes the live one, so live caches must follow the
## live grid; rebuild() already runs exactly once per structural change).
var solid_bounds := Rect2()

var _total_lift := 0.0
var _total_vthrust := 0.0
var _total_hthrust := 0.0
var _has_core := false
## Interaction hot-lists, rebuilt with the grid: the per-frame reach scans
## (find_helm / find_door) used to walk every block of every ship — 11k
## dictionary iterations per frame at 8×, ~6 ms (owner: 22 FPS).
var helm_cells: Array[Vector2i] = []
var door_cells: Array[Vector2i] = []
## Prop-cluster wash emitters (center/axis/half-width), rebuilt with the
## grid — see wash_accel_at().
var _wash_props: Array[Dictionary] = []
var _hover_engaged := false
## Propeller cells whose axis is vertical, derived from mounting at rebuild.
var _vertical_props := {}
## One entry per contiguous glyph-bearing component: {"key": String,
## "rect": Rect2 in local px}. Derived at rebuild; _draw paints one glyph
## per cluster instead of one per cell (owner: an 8× engine slab printing
## 64 letters reads as noise).
var _glyph_clusters: Array[Dictionary] = []
## cell -> index into _glyph_clusters, for component-atomic damage.
var _component_of := {}
## Power grid, derived from the grid by rebuild(). Engines produce; propellers
## and turrets consume. See _power_ratio().
var _power_supply := 0.0
var _hprop_draw := 0.0
var _vprop_draw := 0.0
var _turret_draw := 0.0
var _pending_impacts: Array[Dictionary] = []
## Coalesced structural-rebuild flag. Set whenever a topology-PRESERVING
## grid change needs the derived colliders / mass / CoM / draw re-derived,
## and drained to a SINGLE rebuild() per frame in _process. Two sources
## set it: COMBAT cell deaths (net_damage_cell / a client's _request_damage,
## which now destroy the struck cells but defer the rebuild) and the crash
## CRUSH batch. Neither can sever — combat never touches walls, and the
## crush walk severs nothing either — so one rebuild after N deaths is
## correct. This is what collapses a turret volley or sustained fire on a
## big carcass from N full ~5,120-cell greedy-merge rebuilds per frame down
## to 1 (the whale-carcass FPS cliff). Structural changes that CAN sever
## (remove_block, deconstruct, mining, severing) still rebuild immediately.
var _rebuild_dirty := false

## The hull collision shapes and their grid-space rects, kept parallel and in
## step by _rebuild_collider / _add_hull_shape. Combat damage on plain bulk
## cells (hull, blubber, meat, ballast) uses these to drop a dead cell's
## coverage in O(dead) — split the one rect that held it — instead of the full
## O(cells) greedy re-merge, which measured ~50 ms on the 5,120-cell whale and
## made a carcass under fire drop to a slideshow (see _combat_incremental_drop).
var _hull_shapes: Array[CollisionShape2D] = []
var _hull_rects: Array[Rect2i] = []
var _prev_velocity := Vector2.ZERO
## Whether the last physics step had a live ship-on-ship contact — the
## edge that begins a vessel-collision EPISODE (see _integrate_forces).
var _was_touching_ship := false
## The same episode bookkeeping for TERRAIN, but for LIVING CREATURES only
## (see _integrate_forces): the contact normals already billed during the
## touch that is still in progress, emptied the moment the body separates
## from terrain entirely. Normals rather than a single flag because "one
## episode" must not swallow a genuinely new obstacle — a whale sliding
## along the ground and then slamming a wall has crashed twice, and a
## bare flag let the wall through free. A vessel keeps the per-step
## terrain path unchanged — a hull grinding along rock is supposed to keep
## shedding blocks.
var _creature_terrain_billed_normals: Array[Vector2] = []
## How aligned two contact normals must be to count as the same face, and
## therefore as the same crash still being resolved by the solver.
const SAME_CONTACT_FACE_DOT := 0.7
var _grid_replicated := false
## True once the grid has changed since the spawn payload was built — i.e. the
## payload MultiplayerSpawner replays to a late joiner no longer describes this
## ship. Only then is a catch-up push worth sending (see push_grid_to).
var _grid_diverged_from_payload := false

## --- Live diagnostics (instrumentation only) -----------------------------
## How many times rebuild() ran since the counter was last read. rebuild() is
## the prime suspect for the whale-sandwich FPS drop (an 11k-cell greedy
## merge is not free), so the diagnostic reads and RESETS this each frame to
## see a rebuild storm as a number. A bare int increment on a path that
## already does real work — it changes no behaviour and costs the same
## whether anything is watching. See maps/world/whale_diag.gd.
var rebuilds_this_frame := 0

## Optional diagnostic sink (a WhaleDiag, or null). Null ALWAYS in normal
## play: every hook below is then a single reference check, no allocation and
## no behavioural effect. The world attaches one only to whales, and only
## while the owner is recording (F3). Purely observational — nothing here
## touches collision, damage or rebuild behaviour.
var diag: Object = null


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	# The upright rule (see the header): every ship, always, even one block.
	lock_rotation = true
	add_to_group("ships")  # shots sample every ship's prop wash
	# Aerodynamic drag. Explicit rather than inherited from project defaults,
	# because these are feel knobs and belong next to the rest of the tuning.
	# 0.4 does double duty: a full-throttle ship tops out near 340 px/s
	# (thrust / (damp × mass)) instead of an absurd ~1,360, and an unpiloted
	# ship coasts to walking pace in a few seconds — momentum > drag, as the
	# owner specified — rather than carrying its crew for a minute.
	linear_damp = 0.4
	angular_damp = 1.0
	# Collisions transfer momentum like pool balls, not putty (owner 2026-08-23:
	# "whale collision against ship still doesn't seem to transfer all the
	# momentum on impact — shouldn't it be a bit more transferrable?"). With no
	# physics material Godot's contacts are perfectly inelastic (restitution 0):
	# a whale ramming a lighter ship shares velocity instead of kicking it clear,
	# so most of the whack is absorbed rather than passed on. A modest restitution
	# makes the struck body spring off — a partly-elastic hit — without turning
	# terrain landings into a trampoline (a small bounce, and linear_damp/gravity
	# settle it). Tunable so the feel is a dial, not a recompile.
	var pm := PhysicsMaterial.new()
	pm.bounce = Tunables.get_num("ship_restitution")
	pm.friction = 1.0
	physics_material_override = pm
	if is_authority():
		# Ships built directly (single-player, tests, the editor) never went
		# through from_data, so the shadow pose starts here instead.
		net_position = position
		net_rotation = rotation
	rebuild()
	if blueprint.is_empty():
		capture_blueprint()  # the ship's as-built form is its intended form


## Same reasoning as Fleet: replication has to be wired before any packet can
## arrive, and _ready() is too late to guarantee that.
func _enter_tree() -> void:
	if is_online() and not has_node("Sync"):
		_setup_replication()


# --- Network authority ----------------------------------------------------
#
# Ship deliberately does not depend on the Net autoload — it reads the
# multiplayer state straight off the node. That keeps a Ship correct when it is
# constructed outside the tree, in tests, or in single-player where there is no
# peer at all.

func is_online() -> bool:
	return NetUtil.is_online(self)


## True on the server, and true in single-player. The physics simulation and
## every structural change run only where this is true.
func is_authority() -> bool:
	return NetUtil.is_authority(self)


## --- Client-side interpolation (owner charter §1) ------------------------
## The wire does NOT write the visible transform. It writes a shadow pose —
## `net_position` / `net_rotation` — which the server republishes each tick and
## every client eases the real body toward in _physics_process. Replicating
## `.:position` directly (what this used to do) teleports a remote hull once
## per sync packet: someone else's ship judders across the sky exactly as
## badly as an unsmoothed one of your own, and clunk is clunk whichever ship
## it is.
##
## Presentation only, deliberately: the shadow is authored by the authority
## alone, the client never writes back to it, and the visible body always
## converges on it — so this can slow a correction down but can never argue
## with one. The cost is a bounded trailing error of roughly speed/RATE px.
const NET_SMOOTH_RATE := 18.0        ## e-folds per second toward the wire pose
const NET_SNAP_CELLS := 25.0         ## error (in cells) that means "teleport"
const NET_ROT_SNAP := 1.2            ## rad of error that means the same

## The authority's transform as it went onto the wire. Clients read it; nobody
## else writes it. (A shadow rather than the node's own transform because a
## replicated `position` is applied to the body the instant the packet lands.)
var net_position := Vector2.ZERO
var net_rotation := 0.0


## Clients do not simulate: they are driven by the synchroniser below, so the
## body is frozen to stop local physics fighting the replicated transform.
func _setup_replication() -> void:
	var config := SceneReplicationConfig.new()
	config.add_property(^".:net_position")
	config.add_property(^".:net_rotation")
	config.add_property(^".:linear_velocity")
	config.add_property(^".:angular_velocity")

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"  # deterministic, so the node path matches across peers
	sync.replication_config = config
	add_child(sync)

	if not is_authority():
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC


## Ease the visible body toward the pose the server published. Runs on clients
## only; the body is a frozen kinematic there, so writing the transform is the
## sanctioned way to move it and nothing in the solver fights back.
##
## A teleport must never be smoothed — a respawn, a world reset or a fresh
## spawn would visibly glide the whole way across the map. Past the snap
## threshold the body is simply placed. The threshold is in CELLS so it holds
## at any world scale: at 8× everything is eight times further apart, and a
## fixed pixel budget would either snap constantly or never.
func _follow_net_pose(delta: float) -> void:
	var snap_px := NET_SNAP_CELLS * CELL * scale_unit
	var drift := net_position - position
	if drift.length_squared() > snap_px * snap_px \
			or absf(angle_difference(rotation, net_rotation)) > NET_ROT_SNAP:
		position = net_position
		rotation = net_rotation
		return
	# Exponential approach, framerate-independent: the same fraction of the
	# remaining error is closed per second no matter the tick rate.
	var t := 1.0 - exp(-NET_SMOOTH_RATE * delta)
	position += drift * t
	rotation = lerp_angle(rotation, net_rotation, t)


# --- Grid editing ---------------------------------------------------------

func set_block(cell: Vector2i, type: int, rebuild_now := true) -> void:
	blocks[cell] = {"type": type, "hp": BlockDB.max_hp(type)}
	walls[cell] = true  # building is construction: the wall comes with it
	# Construction is the ONLY thing that grows the blueprint (owner):
	# combat never touches it, and repair rebuilds toward exactly this.
	_blueprint_set(cell, type)
	if rebuild_now:
		rebuild()


## Deconstruction: removes the block AND its wall — the only way a ship
## loses structural integrity, and therefore the only path to severing.
## Also clears the wall of an already-destroyed cell (block long shot away,
## ghost frame remaining).
func remove_block(cell: Vector2i, rebuild_now := true) -> void:
	var had_block := blocks.has(cell)
	if not had_block and not walls.has(cell):
		return
	if had_block:
		var type: int = blocks[cell]["type"]
		blocks.erase(cell)
		block_destroyed.emit(cell, type)
	walls.erase(cell)
	_blueprint_erase(cell)  # deconstruction shrinks the intended form too
	if rebuild_now:
		rebuild()
		_resolve_severing()


func has_block(cell: Vector2i) -> bool:
	return blocks.has(cell)


## Is this a whale CARCASS — a dead creature whose flesh blocks break for
## harvesting? A creature has a shared pool (shared_health_max > 0); it is a
## carcass once that pool is empty. A LIVING creature (pool > 0) is one unit and
## never yields, and a plain VESSEL (no pool) is not a creature at all. This is
## the exact gate that separates "you can harvest this" from "shooting a live
## whale" (world harvest path) and from ship deconstruction.
func is_carcass() -> bool:
	return shared_health_max > 0.0 and shared_health <= 0.0


## Harvest one flesh cell off a CARCASS: removes the block and returns the
## whale-product ITEM id it yields (ItemDB.Product.*), or -1 if nothing is
## harvestable here — a living creature, a plain vessel, an empty cell, or a
## non-flesh block (only BLUBBER/MEAT flesh yields a product). Removal goes
## through remove_block, so it also drops the wall and can sink/sever the corpse,
## exactly like mining a corpse in the original ("mining the blubber off a corpse
## makes it sink faster"). Only the AUTHORITY should call this (grid mutation);
## the world's harvest path is authority-gated, networked harvest deferred.
func harvest_cell(cell: Vector2i) -> int:
	if not is_carcass() or not blocks.has(cell):
		return -1
	var product := ItemDB.whale_product_for(blocks[cell]["type"])
	if product < 0:
		return -1  # not harvestable flesh (e.g. a component cell on the corpse)
	# Cracking a cavity WALL breaches the pocket. Probed here, before the removal,
	# because the cavity map has to be read off a body that still encloses it.
	if not _cavity_breached and _breaches_cavity(cell):
		_cavity_breached = true
	remove_block(cell)
	return product


## The carcass's one-time stomach drop (WIKI_REFERENCE: the whale swallows an
## NPC's inventory — a treasure container, not just a resource node). Returns the
## loot item id the FIRST time it is called on a given carcass, then -1 forever
## after, so cracking the corpse open yields the cargo exactly once.
##
## `[?]` — the stomach LOOT TABLE is unspecified in the source survey. This ships
## a fixed placeholder (one STOMACH_LOOT item); a real weighted table is a seam
## left for the economy slice (BACKLOG).
func take_stomach_loot() -> int:
	if not is_carcass() or _stomach_looted:
		return -1
	_stomach_looted = true
	return ItemDB.Product.STOMACH_LOOT


## The BREACHED cavity's one-time bundle: a copy of CAVITY_LOOT the first time it
## is called on a CARCASS whose sealed pocket has been cracked open, then an empty
## array forever after. Empty until the breach, so simply killing a kraken pays
## nothing — you have to mine into it. Mirrors take_stomach_loot; returns an ARRAY
## because the cavity is a bundle (counts included), not a single item.
func take_cavity_loot() -> Array:
	if not is_carcass() or _cavity_looted or not _cavity_breached:
		return []
	_cavity_looted = true
	return CAVITY_LOOT.duplicate(true)


## Has the sealed cavity been cracked open? Read by tests/debug; the payout gate
## is take_cavity_loot.
func cavity_breached() -> bool:
	return _cavity_breached


## The SEALED interior air cells — every empty cell inside the body's bounding box
## that the outside flood never reached. Latched on the first call (see the
## `_cavity_cells` notes): an already-breached body would map to nothing.
func cavity_cells() -> Dictionary:
	if _cavity_mapped:
		return _cavity_cells
	_cavity_mapped = true
	if blocks.is_empty():
		return _cavity_cells
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in blocks:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var exterior := exterior_air()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not blocks.has(c) and not exterior.has(c):
				_cavity_cells[c] = true
	return _cavity_cells


## Would removing `cell` open the cavity? True when it is one of the pocket's
## walls — 4-adjacent to a latched cavity cell.
func _breaches_cavity(cell: Vector2i) -> bool:
	var cavity := cavity_cells()
	if cavity.is_empty():
		return false
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if cavity.has(cell + d):
			return true
	return false


## Every EMPTY cell the OUTSIDE can reach, flooded inward from a ring one cell
## clear of the body's bounding box. The single place "is this air open to the
## sky?" is decided: KrakenAI's mouth finder tells an opening from a sealed
## cavity with it, and cavity_cells() is precisely its complement inside the box.
func exterior_air() -> Dictionary:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in blocks:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var seen := {}
	var stack: Array[Vector2i] = [lo]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c) or blocks.has(c):
			continue
		if c.x < lo.x or c.y < lo.y or c.x > hi.x or c.y > hi.y:
			continue
		seen[c] = true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(c + d)
	return seen


func is_door(cell: Vector2i) -> bool:
	if not blocks.has(cell):
		return false
	var t: int = blocks[cell]["type"]
	return t == BlockDB.Type.DOOR or t == BlockDB.Type.DOOR_CLOSED


## Doors open and close as a whole component (owner spec, session 3): open
## passes bodies and bullets, closed stops both — "shoot-through only when
## open". The state is a type swap so it replicates and saves for free; hp
## carries over (both states share max hp). The BLUEPRINT is untouched:
## opening a door is use, not construction, and repair restores the
## authored (open) door.
func toggle_door(cell: Vector2i) -> bool:
	if not is_door(cell):
		return false
	var closing: bool = blocks[cell]["type"] == BlockDB.Type.DOOR
	var new_type := BlockDB.Type.DOOR_CLOSED if closing else BlockDB.Type.DOOR
	for c in _component_members(cell):
		if is_door(c):
			blocks[c]["type"] = new_type
	rebuild()
	return true


## Correct in single-player and online alike, same contract as net_set_block.
func net_toggle_door(cell: Vector2i) -> void:
	if is_authority():
		toggle_door(cell)
	else:
		_request_toggle_door.rpc_id(1, cell)


@rpc("any_peer", "reliable")
func _request_toggle_door(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	toggle_door(cell)


## A ship is controllable only through a standing control panel.
func has_helm() -> bool:
	return _has_core


## A block may only be placed where it touches an existing block — ships stay
## one connected piece by construction rather than by validation after the fact.
func can_place_at(cell: Vector2i) -> bool:
	if blocks.has(cell):
		return false
	if blocks.is_empty():
		return true
	for n in _neighbours(cell):
		if blocks.has(n):
			return true
	return false


func cell_at_global(global_pos: Vector2) -> Vector2i:
	var local := to_local(global_pos)
	return Vector2i(roundi(local.x / CELL), roundi(local.y / CELL))


## The nearest SOLID cell to a world point — the cell `cell_at_global` gives if it
## already holds a block, else the closest block within `max_ring` cells (ring by
## ring, so the first hit is nearest). Returns the raw cell if nothing solid is
## near (a genuine miss).
##
## WHY (owner 2026-08-24, "whales seem immune while charging"): a LIVING creature
## collides as ONE coarse AABB box (v0.41.1, the physics-cliff fix), but its cells
## are SPARSE inside that box — a whale silhouette leaves the AABB corners empty.
## A shot striking the box at an empty corner mapped to an AIR cell, so
## `damage_cell` found no block, dealt nothing, and the shot was consumed anyway:
## the whale visibly ate the shot and read as immune. Snapping the hit to the
## nearest real block makes a visible hit always bite (ram immunity is, and stays,
## a BLOCKS-only crush thing — it never touched gunfire). A vessel (exact per-cell
## collider) always hits a solid cell first, so this is a no-op for ships.
func nearest_solid_cell(global_pos: Vector2, max_ring: int = 8) -> Vector2i:
	var base := cell_at_global(global_pos)
	if blocks.has(base):
		return base
	var best := base
	var best_d2 := 1 << 30
	for r in range(1, max_ring + 1):
		# Scan the square ring at Chebyshev distance r; keep the nearest by true
		# (squared) distance so a diagonal never beats a closer orthogonal cell.
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := base + Vector2i(dx, dy)
				if blocks.has(c):
					var d2 := dx * dx + dy * dy
					if d2 < best_d2:
						best_d2 = d2
						best = c
		if best_d2 < (1 << 30):
			return best  # this ring had a block — it is the nearest one
	return base


func local_pos_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL


## Attach a balloon of `size` (BalloonSize) at `cell` — a solid block to tether to.
## Rebuilds so the added lift takes effect immediately. Returns false if the cell
## holds no block (nothing to bolt a cable to).
func attach_balloon(cell: Vector2i, size: int) -> bool:
	if not blocks.has(cell):
		return false
	balloons.append({"cell": cell, "size": size, "hp": BALLOON_HP[size]})
	rebuild()
	return true


## Lift contributed by attached balloons alone (tests / readouts).
func balloon_lift_total() -> float:
	var t := 0.0
	for b in balloons:
		t += BALLOON_LIFT[int(b["size"])]
	return t


## The world-space centre of balloon `i`'s bulb — where it floats on its taut
## cable above its anchor. THE hit target: the whole placeable is one object, so
## a shot anywhere within its radius of this point damages all of it. Shared by
## the renderer and the hit test so what you see is exactly what you can shoot.
func balloon_center(i: int) -> Vector2:
	var b: Dictionary = balloons[i]
	return to_global(local_pos_of(b["cell"])) \
		+ Vector2(0.0, -BALLOON_CABLE_CELLS * CELL * scale_unit)


## The balloon whose bulb contains `world_pos`, or -1. Nearest-centre wins when
## bulbs overlap, so a cluster disambiguates cleanly.
func balloon_at_global(world_pos: Vector2) -> int:
	var best := -1
	var best_d2 := INF
	for i in balloons.size():
		var r: float = BALLOON_RADIUS_CELLS[int(balloons[i]["size"])] * CELL * scale_unit
		var d2 := (balloon_center(i) - world_pos).length_squared()
		if d2 <= r * r and d2 < best_d2:
			best_d2 = d2
			best = i
	return best


## Damage balloon `i` as ONE PLACEABLE (owner's rule: a hit anywhere on it hurts
## the whole thing, and at zero the WHOLE balloon pops — never a partial bag).
## Returns true if it popped. The lift disappears with it via the rebuild, so a
## shot balloon drops whatever it was holding up.
func damage_balloon(i: int, amount: float) -> bool:
	if i < 0 or i >= balloons.size():
		return false
	var b: Dictionary = balloons[i]
	b["hp"] = float(b.get("hp", BALLOON_HP[int(b["size"])])) - amount
	if b["hp"] > 0.0:
		balloons[i] = b
		return false
	var at := balloon_center(i)
	var size := int(b["size"])
	balloons.remove_at(i)
	rebuild()  # the lift goes with it, this frame
	balloon_popped.emit(at, size)
	return true


# --- Derivation from the grid --------------------------------------------

func rebuild() -> void:
	# Instrumentation: count every rebuild so the diagnostic can surface a
	# rebuild storm (the FPS suspect). Inert — a lone int, read+reset by the
	# diagnostic; nobody reads it in normal play.
	rebuilds_this_frame += 1
	if blocks.is_empty():
		destroyed.emit()
		queue_free()
		return

	# The wall layer is the built footprint: captured from the first grid
	# this ship derives from (spawn payload, test construction, wreckage).
	if walls.is_empty():
		for cell in blocks:
			walls[cell] = true

	var total_mass := 0.0
	var weighted := Vector2.ZERO
	_total_lift = 0.0
	_total_vthrust = 0.0
	_total_hthrust = 0.0
	_power_supply = 0.0
	_hprop_draw = 0.0
	_vprop_draw = 0.0
	_turret_draw = 0.0

	_vertical_props.clear()
	_has_core = false
	helm_cells.clear()
	door_cells.clear()
	_derive_prop_axes()
	var smin := Vector2i(1 << 30, 1 << 30)
	var smax := Vector2i(-(1 << 30), -(1 << 30))
	for cell in blocks:
		var type: int = blocks[cell]["type"]
		var def := BlockDB.get_def(type)
		if def["solid"]:
			smin = Vector2i(mini(smin.x, cell.x), mini(smin.y, cell.y))
			smax = Vector2i(maxi(smax.x, cell.x), maxi(smax.y, cell.y))
		if def["is_core"]:
			helm_cells.append(cell)
		if type == BlockDB.Type.DOOR or type == BlockDB.Type.DOOR_CLOSED:
			door_cells.append(cell)
		# Component mass is a rating like its output (the machine did not
		# get lighter because its true footprint covers fewer cells than a
		# uniform slab) — normalised so an 8× ship's total mass, trim and
		# feel match the 1× ship exactly. _fp_norm is 1 for bulk blocks
		# and everything at 1×.
		var m: float = def["mass"] * _fp_norm(type)
		total_mass += m
		weighted += local_pos_of(cell) * m
		_total_lift += def["lift"]
		_power_supply += def["power"]
		_has_core = _has_core or def["is_core"]
		if def["thrust"] > 0.0:
			if _vertical_props.has(cell):
				_total_vthrust += def["thrust"]
				_vprop_draw += def["draw"]
			else:
				_total_hthrust += def["thrust"]
				_hprop_draw += def["draw"]
		else:
			_turret_draw += def["draw"]

	# Tethered balloons fold their helium lift into the body's total (carcass-as-
	# airship). A balloon whose anchor cell is gone (mined/severed/combat) detaches.
	if not balloons.is_empty():
		var kept: Array = []
		for b in balloons:
			if blocks.has(b["cell"]):
				kept.append(b)
				_total_lift += BALLOON_LIFT[int(b["size"])]
		balloons = kept

	solid_bounds = Rect2() if smax.x < smin.x else Rect2(
		Vector2(smin) * CELL - Vector2.ONE * CELL * 0.5,
		Vector2(smax - smin + Vector2i.ONE) * CELL)

	_rebuild_glyph_clusters()

	_wash_props.clear()
	for cluster in _glyph_clusters:
		if cluster["key"] == "PH" or cluster["key"] == "PV":
			var r: Rect2 = cluster["rect"]
			_wash_props.append({
				"center": r.get_center(),
				"vertical": cluster["key"] == "PV",
				"half_width": maxf(r.size.x, r.size.y) * 0.5 + CELL,
			})

	# Set here, not in _ready(), so that rebuild() is correct no matter when it
	# is called. Godot silently ignores center_of_mass unless the mode is
	# CUSTOM, which fails quietly rather than loudly — leave this line alone.
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM

	mass = maxf(total_mass, 0.001)
	center_of_mass = weighted / mass
	inertia = 0.0  # sentinel: 0 means "recompute from the new shapes"

	# No control panel, no control (owner): a ship whose helm is destroyed
	# flies on momentum alone until the panel is repaired from the
	# blueprint. Kills any input that was held when the helm died.
	if not _has_core:
		thrust_input = Vector2.ZERO

	_rebuild_collider()
	queue_redraw()

	# rebuild() is called exactly when the grid changes structurally, which is
	# exactly when clients need the new grid. One hook covers building, mining,
	# damage and severing without each of them remembering to replicate.
	_broadcast_grid()


## One propeller *component* serves both axes; the axis derives from how it
## is MOUNTED (owner spec): supported from the side pushes, hung above or
## below its support lifts. "Mounted" means touching a NON-propeller block —
## a slab's own prop cells are its body, not its mounting. This matters the
## moment a blueprint upscale turns one prop cell into an 8×8 slab: under
## the old per-cell rule every interior cell saw prop neighbours to its
## sides and the whole slab derived as horizontal — zero lift props at 8×,
## which the owner met as "can't move up or down, EXTREMELY slow".
## Horizontal wins when both mounting kinds exist; a free-floating
## component defaults to horizontal, as before.
func _derive_prop_axes() -> void:
	var visited := {}
	for cell in blocks:
		if visited.has(cell) or BlockDB.get_def(blocks[cell]["type"])["thrust"] <= 0.0:
			continue
		var cluster: Array[Vector2i] = []
		var queue: Array[Vector2i] = [cell]
		visited[cell] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			cluster.append(c)
			for n in _neighbours(c):
				if not visited.has(n) and blocks.has(n) \
						and BlockDB.get_def(blocks[n]["type"])["thrust"] > 0.0:
					visited[n] = true
					queue.append(n)

		var side_mounted := false
		var hung := false
		for c in cluster:
			side_mounted = side_mounted or _is_mount(c + Vector2i.LEFT) \
				or _is_mount(c + Vector2i.RIGHT)
			hung = hung or _is_mount(c + Vector2i.UP) or _is_mount(c + Vector2i.DOWN)
		if hung and not side_mounted:
			for c in cluster:
				_vertical_props[c] = true


func _is_mount(cell: Vector2i) -> bool:
	return blocks.has(cell) and BlockDB.get_def(blocks[cell]["type"])["thrust"] <= 0.0


## Greedy rectangle merge: adjacent solid cells collapse into as few
## RectangleShape2Ds as possible. A 200-block hull becomes a handful of shapes
## instead of 200, which is the difference between a ship that runs and one
## that stutters.
func _rebuild_collider() -> void:
	var stale: Array[Node] = []
	for child in get_children():
		if child is CollisionShape2D:
			stale.append(child)
	for child in stale:
		remove_child(child)
		child.queue_free()

	# The hull shapes and their grid rects are kept in step (parallel arrays) so
	# combat damage can drop a dead cell's coverage incrementally instead of
	# re-merging the whole body — see _drop_cell_from_collider.
	_hull_shapes.clear()
	_hull_rects.clear()
	# A LIVING creature gets a COARSE collider, not the cell-accurate grid (see
	# _use_coarse_collider). Vessels and carcasses keep the exact per-cell merge.
	var rects := _coarse_creature_rects() if _use_coarse_collider() else _merge_rects()
	if rects.is_empty() and not blocks.is_empty():
		# Nothing solid left — a wreck of pure pass-through structure
		# (struts, open doors, furniture). A RigidBody2D with zero shapes
		# falls through the WORLD, so a shot-down hulk reduced to its
		# scaffolding tunneled out through the arena floor (owner report,
		# session 3). A tangle of poles still lands on the ground: give the
		# wreck colliders from whatever cells remain. In-play pass-through
		# is unaffected while any solid cell stands — this path only exists
		# for all-scaffold wrecks.
		rects = _merge_rects(true)
	for rect in rects:
		_add_hull_shape(rect)

	_rebuild_platforms()
	_rebuild_shields()


## Create one hull CollisionShape2D for a grid rect and record it in the
## parallel _hull_shapes / _hull_rects arrays. Shared by the full rebuild and
## the incremental combat drop, so both place shapes IDENTICALLY — reflected
## onto the drawn side for a mirrored creature, identity for every vessel and
## unflipped creature (see visual_facing).
func _add_hull_shape(rect: Rect2i) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(rect.size) * CELL
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = _mirror_point(
		(Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5) * CELL)
	add_child(cs)
	_hull_shapes.append(cs)
	_hull_rects.append(rect)


## --- Coarse creature collider (owner + measurement, session 5) ------------
## A LIVING creature does not need a cell-accurate collider. It is ONE flexing
## body (owner model): while alive no cell breaks, and every impact drains the
## SHARED POOL regardless of which cell was struck — so cell-precise collision
## is wasted work while alive. Only the CARCASS needs the per-cell grid (for
## mining and per-cell crushing); a VESSEL always keeps it.
##
## This is THE whale-sandwich FPS fix. Measured headless (a living whale pressed
## between a ram and a StaticBody2D wall, both bodies held precise): the whale's
## greedy-merged blubber is ~7 rectangle shapes, and two such bodies deeply
## interpenetrating cost ~181 ms/frame TIME_PHYSICS_PROCESS (the ~3 FPS the owner
## saw). Dropping the whale to ≤4 large coarse boxes collapsed it to ~30 ms — a
## ~6× cut — because the sustained contact-solver work scales with the number of
## overlapping shape PAIRS (roughly O(whale_shapes × other_shapes) per substep),
## not with cell count. Idle cost is ~0.3 ms either way, and mass / centre of
## mass / lift derive from the GRID (rebuild loop), never the collider, so the
## coarse shape is CONTACT-ONLY: buoyancy, trim and flight are untouched.
##
## Only creatures big enough to actually have a many-shape collider take this
## path (COARSE_COLLIDER_MIN_CELLS): a tiny test creature already merges to one
## or two shapes, so coarsening it would only sacrifice fidelity (e.g. the
## mirror probes in the skin test) for no perf gain.
const COARSE_COLLIDER_MIN_CELLS := 64


## A living creature (pool alive) large enough to have a many-shape collider
## takes the coarse path. shared_health_max == 0 is a vessel; pool 0 is a
## carcass; both keep the exact per-cell grid.
func _use_coarse_collider() -> bool:
	if force_precise_collider:
		return false
	if shared_health_max <= 0.0 or shared_health <= 0.0:
		return false
	var solid := 0
	for cell in blocks:
		if BlockDB.get_def(blocks[cell]["type"])["solid"]:
			solid += 1
			if solid >= COARSE_COLLIDER_MIN_CELLS:
				return true
	return false


## A living creature collides as a SINGLE box — its solid AABB. This is the far
## end of the coarse-collider idea (owner 2026-08-23: "insane FPS drop"). The 2D
## solver's cost under deep penetration scales with overlapping shape PAIRS, and a
## provoked POD piling onto the player near terrain is many bodies × several shapes
## each — measured ~36 ms avg / ~206 ms peak for three whales rammed together. One
## box per creature collapses that to one pair per body-pair: the same three-whale
## sandwich drops to a few ms. A living creature is one flexing body (damage pools,
## no cell ever breaks or is mined while alive), so cell-accurate collision buys
## nothing here; mass / CoM / lift / severing all derive from the GRID, never the
## collider, so this is contact-only. A carcass and every vessel keep the exact
## per-cell grid (see _use_coarse_collider), so mining and ship-vs-ship are untouched.
## The box is a clean over-approximation of the solid AABB — it covers every solid
## cell (never a gap to fall through) and never reaches past the footprint.
func _coarse_creature_rects() -> Array[Rect2i]:
	var smin := Vector2i(1 << 30, 1 << 30)
	var smax := Vector2i(-(1 << 30), -(1 << 30))
	for cell in blocks:
		if not BlockDB.get_def(blocks[cell]["type"])["solid"]:
			continue
		smin = Vector2i(mini(smin.x, cell.x), mini(smin.y, cell.y))
		smax = Vector2i(maxi(smax.x, cell.x), maxi(smax.y, cell.y))
	if smax.x < smin.x:
		return []
	return [Rect2i(smin, smax - smin + Vector2i.ONE)]


## Shield cells (the control panel) block BULLETS but not bodies: their
## shapes live on a separate layer-4 child, because per-shape collision
## layers do not exist (godot-quirks). Shots mask layers 1|4; characters
## mask 1|3 and walk straight through the furniture.
func _rebuild_shields() -> void:
	var stale: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("Shield"):
			stale.append(child)
	for child in stale:
		remove_child(child)
		child.queue_free()

	var cells: Array[Vector2i] = []
	for cell in blocks:
		if BlockDB.get_def(blocks[cell]["type"]).get("shield", false):
			cells.append(cell)
	if cells.is_empty():
		return

	var body := AnimatableBody2D.new()
	body.name = "Shield"
	body.sync_to_physics = false  # positional carry glues it; true breaks (quirk)
	body.collision_layer = 0
	body.set_collision_layer_value(4, true)
	body.collision_mask = 0
	add_child(body)
	for cell in cells:
		var shape := RectangleShape2D.new()
		shape.size = Vector2.ONE * CELL
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = _mirror_point(local_pos_of(cell))
		body.add_child(cs)


## Platform cells become thin one-way strips on separate child bodies — one
## body per deck row (cell.y). Separate from the hull because per-shape
## collision layers do not exist; separate per ROW so a drop-through can
## exclude exactly the storey under the player's feet while every other
## platform keeps colliding (the previous layer-wide off switch let the
## player fall through storeys they never asked to pass — owner report).
## AnimatableBody2D rather than StaticBody2D so characters standing on a
## strip inherit the moving ship's velocity.
func _rebuild_platforms() -> void:
	for child in get_children():
		if child is AnimatableBody2D and String(child.name).begins_with("Platforms"):
			remove_child(child)
			child.queue_free()

	var rows := {}
	for cell in blocks:
		if not BlockDB.get_def(blocks[cell]["type"])["platform"]:
			continue
		if not rows.has(cell.y):
			var body := AnimatableBody2D.new()
			body.name = "Platforms_%s" % str(cell.y).replace("-", "n")
			# sync_to_physics stays FALSE. Setting it true (chasing a platform
			# bookkeeping theory) broke strip solidity outright under a
			# parent-driven body — players passed through planks in BOTH
			# directions in live play, while the near-stationary test ships
			# masked it. The positional carry with false glues riders fine.
			body.sync_to_physics = false
			body.collision_layer = 0
			body.set_collision_layer_value(3, true)
			body.collision_mask = 0
			add_child(body)
			rows[cell.y] = body

		var shape := RectangleShape2D.new()
		shape.size = Vector2(CELL, 4.0)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.one_way_collision = true
		# A fast fall covers more than the default 1px one-way margin in a
		# single frame, and the contact gets discarded — the player tunnels
		# straight through the strip. Seen dropping one storey onto the hold
		# platforms at ~250 px/s.
		cs.one_way_collision_margin = 12.0
		# Flush with the hull's walk plane. Seams between separate bodies are
		# sub-pixel fragile in either direction (flush catches one way, a
		# raised lip catches the other — both were observed); the player's
		# step-up assist is what actually makes the crossing reliable.
		cs.position = _mirror_point(local_pos_of(cell) + Vector2(0, -CELL * 0.5 + 2.0))
		rows[cell.y].add_child(cs)


func _merge_rects(include_all := false) -> Array[Rect2i]:
	var remaining := {}
	for cell in blocks:
		# Open doors/struts are structure without collision — openings you
		# walk through. include_all is the all-scaffold-wreck fallback only.
		if include_all or BlockDB.get_def(blocks[cell]["type"])["solid"]:
			remaining[cell] = true
	return _greedy_rects(remaining)


## Greedy rectangle cover of a cell set (consumes `remaining`). Shared by
## the collider build and the batched renderer.
static func _greedy_rects(remaining: Dictionary) -> Array[Rect2i]:
	var ordered := remaining.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)

	var rects: Array[Rect2i] = []
	for cell in ordered:
		if not remaining.has(cell):
			continue

		var w := 1
		while remaining.has(cell + Vector2i(w, 0)):
			w += 1

		var h := 1
		while true:
			var row_full := true
			for i in w:
				if not remaining.has(cell + Vector2i(i, h)):
					row_full = false
					break
			if not row_full:
				break
			h += 1

		for j in h:
			for i in w:
				remaining.erase(cell + Vector2i(i, j))
		rects.append(Rect2i(cell, Vector2i(w, h)))

	return rects


# --- Simulation -----------------------------------------------------------

func air_density_at(y: float) -> float:
	# The air column stretches with the world scale — otherwise an 8× arena
	# tops out in near-vacuum and ships stall a few lengths off the deck.
	return clampf(inverse_lerp(CEILING_Y * scale_unit, SEA_LEVEL_Y, y), MIN_AIR_DENSITY, 1.0)


## Footprint normalisation (see BlockDB.FOOTPRINT_8X): per-cell
## power/thrust/draw sums are multiplied by su²/footprint so a
## component's output is its rating at this world scale, independent of
## how many cells its true footprint covers. Exactly 1.0 at 1× and for
## any type without a footprint entry. Applied at use time, not baked
## into the rebuild totals, so a scale_unit assigned after construction
## (spawn payloads, tests) still normalises correctly.
func _fp_norm(type: int) -> float:
	return scale_unit * scale_unit / BlockDB.footprint_cells(type, scale_unit)


## Power demanded by everything currently running. Turrets idle-scan, so they
## always draw; propellers draw only while their axis is being used.
func active_draw() -> float:
	var draw := _turret_draw * _fp_norm(BlockDB.Type.TURRET)
	var prop_norm := _fp_norm(BlockDB.Type.PROPELLER)
	if not is_zero_approx(thrust_input.x):
		draw += _hprop_draw * prop_norm
	if not is_zero_approx(thrust_input.y) or _hover_engaged:
		draw += _vprop_draw * prop_norm
	return draw


## The brownout rule, straight from the original: when demand exceeds supply,
## every powered component degrades proportionally rather than shutting off.
## An underpowered ship flies sluggishly — it does not stop flying. And a ship
## with no engines produces 0 supply, so propellers are inert: engines are
## required, exactly as the wiki's component list says.
func _power_ratio() -> float:
	var draw := active_draw()
	if draw <= 0.0:
		return 1.0
	return clampf(_power_supply * _fp_norm(BlockDB.Type.ENGINE) / draw, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	# Before the authority branch, deliberately: the drawn facing is derived
	# from the body's own visible motion (see visual_facing), which is the
	# solver's on the server and _follow_net_pose's easing on a client. Same
	# rule, same code, both sides — nothing extra goes on the wire.
	_update_visual_facing(delta)

	if not is_authority():
		# Clients are driven by the replicated pose, not by forces — but they
		# ease into it rather than snapping to it. See _follow_net_pose.
		_follow_net_pose(delta)
		return

	# Publish this tick's pose for the synchroniser. Read before the forces
	# below, because the solver has not stepped yet: this is the transform the
	# clients were last entitled to see.
	net_position = position
	net_rotation = rotation

	var wind := Vector2.ZERO
	if Airspace.active():
		# Wind drags the hull toward the airstream's velocity. Godot's linear
		# damping decelerates at damp·v, so a steady force of mass·damp·wind
		# holds equilibrium exactly at wind speed: still air keeps today's
		# behaviour, and a dead ship in a stream ends up travelling with it.
		wind = Airspace.wind_at(global_position)
		apply_central_force(mass * linear_damp * wind)
		gravity_scale = Airspace.gravity_scale_at(global_position) * scale_unit
		# The hard ceiling: the sky just ends. No damage, no bounce — upward
		# motion stops and the forces above keep it pinned until it descends.
		if global_position.y <= Airspace.ceiling_y() and linear_velocity.y < 0.0:
			linear_velocity.y = 0.0

	var density := air_density_at(global_position.y)
	var facing := transform.basis_xform(Vector2.RIGHT).normalized()

	# Balloons MAINTAIN, they never propel (owner's rule). Buoyancy is clamped
	# at neutral: capacity at or above weight floats the ship exactly, and no
	# surplus ever pushes it upward — so trim can never be "too buoyant", and
	# battle damage that lightens the ship cannot strand it in the sky. Less
	# capacity than weight is a different story: the ship is doomed to fall,
	# and only props (or shedding weight) save it. The emergent ceiling
	# survives: thin air cuts capacity, and where capacity < weight you sink.
	var weight := mass * 980.0 * gravity_scale
	var lift_capacity := _total_lift * BlockDB.LIFT_PER_MASS * density * scale_unit
	var lift_factor := 1.0
	if lift_capacity > weight and lift_capacity > 0.0:
		lift_factor = weight / lift_capacity

	# Altitude hold. Engagement is decided before the power ratio, because
	# hovering props draw power like manually driven ones. With buoyancy
	# clamped there is never a surplus to fight — the props only make up
	# deficits and damp vertical drift.
	var hover_needed := 0.0
	_hover_engaged = false
	if assist_enabled and is_zero_approx(thrust_input.y) and _total_vthrust > 0.0:
		var deficit_up := weight - minf(lift_capacity, weight)
		# Drift is damped relative to the AIR, not the world (owner: the
		# engines have no idea where world-x,y is). In still air these are
		# identical; in a wind stream the hover happily rides the current
		# instead of station-keeping against it. Absolute station-keeping,
		# if it ever exists, is an upgrade — never the default.
		var v_up := -(linear_velocity.y - wind.y)
		hover_needed = deficit_up - v_up * mass * HOVER_DAMP
		_hover_engaged = absf(hover_needed) > HOVER_MIN_FORCE

	var ratio := _power_ratio()

	var prop_norm := _fp_norm(BlockDB.Type.PROPELLER)
	var v_input := thrust_input.y
	if _hover_engaged:
		var capability := _total_vthrust * prop_norm * ratio * density * scale_unit
		v_input = clampf(hover_needed / capability, -1.0, 1.0) if capability > 0.0 else 0.0

	# Aggregate central forces, not per-block application. Under the
	# upright rule (lock_rotation) a force at an offset and a central
	# force are INDISTINGUISHABLE — the torque component is discarded by
	# the infinite rotational inertia — so the old per-block loop bought
	# nothing but cost: ~5,600 dict lookups + basis_xforms per tick on
	# the 8× ships, ~6 ms/frame of the owner's 22 FPS report. The totals
	# are rebuilt with the grid, so damage still changes flight the same
	# frame. (If ships ever rotate again, this is the first thing to
	# revisit — per-block application is what made handling emergent.)
	apply_central_force(Vector2.UP
		* _total_lift * BlockDB.LIFT_PER_MASS * density * lift_factor * scale_unit)
	if not is_zero_approx(v_input) and _total_vthrust > 0.0:
		apply_central_force(Vector2.UP
			* _total_vthrust * prop_norm * v_input * ratio * density * scale_unit)
	if not is_zero_approx(thrust_input.x) and _total_hthrust > 0.0:
		apply_central_force(facing
			* _total_hthrust * prop_norm * thrust_input.x * ratio * density * scale_unit)


## The net UNSUPPORTED weight at the current altitude — the ship's weight minus
## what its buoyancy can hold up here, clamped at zero (never negative: buoyancy
## is clamped at neutral, it never lifts). This is the downward force a creature
## must overcome by MUSCLE to hold altitude. Mirrors the weight/lift_capacity
## computed in _physics_process. Used by a ridden/tamed whale to tread water
## instead of sinking out of the thin upper air (owner 2026-08-23) — a whale has
## no props, so the hull's own hover assist can never engage for it.
func unsupported_weight() -> float:
	var density := air_density_at(global_position.y)
	var weight := mass * 980.0 * gravity_scale
	var lift_capacity := _total_lift * BlockDB.LIFT_PER_MASS * density * scale_unit
	return maxf(0.0, weight - lift_capacity)


## --- Prop wash ------------------------------------------------------------
## The air jet a RUNNING propeller expels, opposite its thrust: a
## climbing ship blasts air downward, a pusher blasts it astern. Shots
## sample this every frame (owner survey 2026-08-20: the original's
## props visibly bend slow projectiles — heavy artillery lobs deflect
## hard, machine-gun rounds barely notice). The slow-bends-more rule is
## EMERGENT: deflection scales with time spent in the jet, so nothing is
## special-cased per projectile. Projectiles only for now — wash on
## bodies and ships is the full Sprint-4 propeller-wash item (BACKLOG).
const WASH_RANGE_CELLS := 8.0   ## jet length, in cells (×scale_unit)
const WASH_ACCEL := 2600.0      ## px/s² at full power (×scale_unit)


func wash_accel_at(global_pos: Vector2) -> Vector2:
	if _wash_props.is_empty():
		return Vector2.ZERO
	var ratio := _power_ratio()
	if ratio <= 0.01:
		return Vector2.ZERO  # unpowered props are windmills, not fans
	var out := Vector2.ZERO
	var range_px := WASH_RANGE_CELLS * CELL * scale_unit
	var facing := transform.basis_xform(Vector2.RIGHT).normalized()
	for prop in _wash_props:
		var jet := Vector2.ZERO
		if prop["vertical"]:
			var v := thrust_input.y
			if _hover_engaged:
				v = 1.0  # trimming props blow too — hover is real thrust
			if is_zero_approx(v):
				continue
			jet = Vector2.DOWN * signf(v)  # climbing = air blasted down
		else:
			if is_zero_approx(thrust_input.x):
				continue
			jet = -facing * signf(thrust_input.x)
		var rel := global_pos - to_global(prop["center"])
		var along := rel.dot(jet)
		if along < 0.0 or along > range_px:
			continue
		if absf(rel.dot(Vector2(-jet.y, jet.x))) > float(prop["half_width"]) * 1.5:
			continue
		out += jet * WASH_ACCEL * ratio * scale_unit * (1.0 - along / range_px)
	return out


## Impact detection measures the ship's actual killed momentum — mass times
## the velocity the solver removed — never per-contact impulses. A crash
## splits its impulse across corner contacts and solver steps, and each
## fragment can duck any per-contact threshold (observed: a 72,000-momentum
## ram whose largest single contact reported 18,988).
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not is_authority():
		# A client's hull is a frozen kinematic followed by _follow_net_pose.
		# Neither the pose easing nor impact detection may run here: both would
		# write a transform the wire owns, and damage is the server's alone.
		return

	# Ease toward the pose target (see POSE_MAX). It MUST happen here:
	# the physics server owns an active rigid body's transform and
	# overwrites node-side rotation sets every step — easing from
	# _physics_process survived exactly one frame (test-caught). Writing
	# state.transform is the sanctioned kinematic rotation of a rigid
	# body. Free for the common case: everything but a swimming whale
	# sits level at level.
	var rot := state.transform.get_rotation()
	if rot != _pose_tilt:
		rot = lerp_angle(rot, _pose_tilt, 1.0 - exp(-POSE_EASE * state.step))
		if absf(rot - _pose_tilt) < 0.001:
			rot = _pose_tilt
		state.transform = Transform2D(rot, state.transform.origin)

	var best := -1
	var best_impulse := -1.0
	var ship_best := -1
	var ship_best_closing := 0.0
	var ship_other: Ship = null
	var touching_ship := false
	for i in state.get_contact_count():
		# People never damage a hull by standing, walking or landing on it.
		# Without this, crew on the deck shred their own ship in seconds — the
		# most trivial possible case of the original's "far too easy to damage
		# your own ship" complaint. Impact damage is for terrain and vessels.
		var obj := state.get_contact_collider_object(i)
		if obj is CharacterBody2D:
			continue
		if obj is Ship:
			# Vessel contacts take the EPISODE path below, never this one:
			# ship-on-ship collisions resolve softly across many solver
			# steps (both hulls yield), so each step's killed momentum
			# ducks any per-step threshold — the whale rammed at 4,600 px/s
			# and the victim never lost a block (owner 2026-08-21).
			touching_ship = true
			var closing := (_prev_velocity - (obj as Ship)._prev_velocity) \
				.dot(-state.get_contact_local_normal(i))
			if closing > ship_best_closing:
				ship_best_closing = closing
				ship_best = i
				ship_other = obj as Ship
			continue
		var impulse := state.get_contact_impulse(i).length()
		if impulse > best_impulse:
			best_impulse = impulse
			best = i

	# A LIVING creature bills each terrain FACE once per touch episode. This
	# is EXPLICIT insurance, not the load-bearing fix: instrumenting the
	# owner's "it'll hit a world block and just poof" (2026-08-21) showed
	# terrain already bills about once on its own — `killed` measures against
	# the previous post-solve velocity, and once the solver has zeroed the
	# into-surface velocity there is nothing left to bill, so a grind does
	# not repeat. The real killer was the ram-immunity race (see
	# _is_ram_immune). But the once-per-episode guarantee is cheap to make
	# explicit and robust to future physics (restitution, a different solver)
	# that could reintroduce per-step billing on the one pooled body — the
	# per-step path stays right for a rigid HULL (rock grinding a wooden keel
	# should keep shedding blocks) and is untouched. A face latches on its
	# first QUALIFYING step (not its first CONTACT step: a crash whose hard
	# step is the second one must still cost something), and the whole record
	# clears the moment the body leaves the ground — separate and re-strike
	# and it costs again.
	var living := shared_health_max > 0.0 and shared_health > 0.0
	if best < 0 and not _creature_terrain_billed_normals.is_empty():
		_creature_terrain_billed_normals.clear()
	if best >= 0:
		var normal := state.get_contact_local_normal(best)
		# Momentum killed *into the obstacle* since last step. The dot guards
		# against counting our own plow-refund (a velocity gain) as a hit.
		# Terrain kills a hull's velocity within a step, so per-step
		# accounting measures the real crash here (unlike ship contacts).
		var killed := (_prev_velocity - state.linear_velocity).dot(-normal)
		# With restitution the solver REVERSES the into-surface velocity, so this
		# would read approach + rebound and bill a bouncy terrain crash far deeper
		# than the inelastic one it used to be. Only the momentum needed to bring
		# the hull to REST is absorbed by crushing; the elastic rebound is returned
		# as motion, not spent on blocks. Cap `killed` at the approach speed so a
		# springier hull (owner 2026-08-23) bounces off terrain WITHOUT taking more
		# crash damage than before — a no-op at restitution 0.
		killed = minf(killed, _prev_velocity.dot(-normal))
		var momentum := killed * mass
		var already_billed := false
		if living:
			for n in _creature_terrain_billed_normals:
				if n.dot(normal) > SAME_CONTACT_FACE_DOT:
					already_billed = true
					break
		if momentum > Tunables.get_num("impact_damage_threshold") * _unit3() and not already_billed:
			if living:
				_creature_terrain_billed_normals.append(normal)
			_pending_impacts.append({
				# SHIP-LOCAL, not global: the crush runs on a later idle
				# frame, and a hull moving at 8× combat speed has drifted
				# whole cells by then — a stale global point resolves into
				# empty air and the crush silently fizzles (the whale's
				# ram did zero damage this way, owner 2026-08-21).
				"pos": state.transform.affine_inverse()
					* state.get_contact_local_position(best),
				"impulse": momentum,
				"normal": normal,
				# Stamp the ram-immunity verdict HERE, where the normal and
				# the immunity are contemporaneous — see _is_ram_immune. Only a
				# creature's OWN charging ram is forgiven now; a ridden mining whale
				# is NO LONGER blanket-immune (owner 2026-08-23: "whales should take
				# damage if they're being used to ram into things"). It takes the
				# terrain bruise, but ARMOR (the struck cell's collision_resist —
				# shell barely dents) divides it below, so a shell-nosed kraken rams
				# and mines while a flesh-nosed whale pays the full bruise.
				"immune": _is_ram_immune(normal),
				# Terrain, so a living creature bills the gentler factor.
				"terrain": true,
			})

	# Ship-vs-ship: one BITE per contact episode, sized by the physics of
	# the impact itself — closing speed × reduced mass, the momentum the
	# collision actually exchanges — measured from both hulls' pre-solve
	# velocities. (If the other hull's callback ran first this step, its
	# _prev_velocity is already post-solve and the bite under-measures by
	# its Δv — bounded, and far better than the per-step path's zero.)
	# One bite per episode also means a hull glued to its victim cannot
	# grind it down frame by frame: it must separate and strike again,
	# which is exactly the whale's push-glide rhythm.
	if touching_ship and not _was_touching_ship and ship_best >= 0:
		var mu := mass * ship_other.mass / maxf(mass + ship_other.mass, 0.001)
		var episode_momentum := ship_best_closing * mu
		if episode_momentum > Tunables.get_num("impact_damage_threshold") * _unit3():
			_pending_impacts.append({
				"pos": state.transform.affine_inverse()
					* state.get_contact_local_position(ship_best),
				"impulse": episode_momentum,
				"normal": state.get_contact_local_normal(ship_best),
				"immune": _is_ram_immune(state.get_contact_local_normal(ship_best)),
			})
	_was_touching_ship = touching_ship

	_prev_velocity = state.linear_velocity


## Momentum plowing (owner spec). The contact impulse *is* mass × killed
## velocity, so damage is inherently proportional to both. A hit hard enough
## to destroy the contact block refunds the momentum the block did not absorb
## as restored velocity into the obstacle — next frame the shorter ship
## advances into the gap and meets the next block. The crash you feel is the
## frame loop: crunch, slow, crunch, slow, until the momentum is spent or
## nothing is left in the way. A hit that only dents absorbs fully: no refund.
func _process(_delta: float) -> void:
	# Contacts are collected during the physics step; grid mutation happens
	# outside it, because rebuilding a collider mid-solve is not safe.
	if not is_authority():
		# Clients never rebuild from damage — their grid arrives over the wire.
		_pending_impacts.clear()
		_rebuild_dirty = false
		return
	# A combat-only frame has no crash to crush, but deferred cell deaths
	# (net_damage_cell) still need the single coalesced rebuild at the tail of
	# this function. Take it directly — a frame with neither impacts nor a dirty
	# grid is the common no-op return.
	if _pending_impacts.is_empty():
		if _rebuild_dirty:
			_rebuild_dirty = false
			rebuild()
		return
	var impacts := _pending_impacts.duplicate()
	_pending_impacts.clear()

	# Only the dominant contact refunds momentum — several contacts in one
	# frame describe one crash, and refunding each would mint free velocity.
	var dominant := -1
	var dominant_impulse := 0.0
	for i in impacts.size():
		if impacts[i]["impulse"] > dominant_impulse:
			dominant_impulse = impacts[i]["impulse"]
			dominant = i

	for i in impacts.size():
		if blocks.is_empty():
			break  # the last block died to an earlier impact this frame
		var impact: Dictionary = impacts[i]
		# A charging creature's ram is its attack, not self-harm: skip
		# impacts along the charge direction (the contact normal points
		# back INTO the charger). The victim's own contact processing
		# still charges it full price.
		# Forgiven if the creature was charging when the contact was RECORDED
		# (the stamped verdict) OR is charging right now. The record stamp is
		# the load-bearing half: WhaleAI clears immunity the instant the ram's
		# crunch kills its speed — between record and this idle-frame billing —
		# and the live check alone then made the whale pay full price for its
		# own terminal ram. See _is_ram_immune for the race this closes.
		if bool(impact.get("immune", false)) or _is_ram_immune(impact["normal"]):
			# A forgiven ram costs nothing — but the diagnostic still wants to
			# SEE it (a whale dying "for free" is exactly the owner's report),
			# so record the zero-cost impact before skipping. Inert when off.
			if diag != null:
				diag.on_whale_damage(self,
					"terrain" if impact.get("terrain", false) else "ship-episode",
					0.0, impact["normal"], true, shared_health)
			continue
		var cell := _impact_cell(impact["pos"], impact["normal"])
		if not blocks.has(cell):
			continue
		# Threshold scales with unit³ (momentum ∝ mass·v ∝ unit³), but the
		# damage CONVERSION divides by unit² only: cells keep constant hp
		# while shrinking relative to the world, so the same relative crash
		# must bite unit× deeper in cells to leave the same relative dent.
		# Full unit³ normalisation made an 8× crash crunch two tiny squares
		# and read as "no damage" (owner report).
		var unit2 := scale_unit * scale_unit
		var available: float = (impact["impulse"] \
				- Tunables.get_num("impact_damage_threshold") * _unit3()) \
			* Tunables.get_num("impact_damage_scale") / unit2
		# A LIVING creature is one flexing body, not a rigid grid, so the
		# inward walk below has nothing to spend itself on: damage_cell banks
		# everything in the shared pool and breaks no block, so the walk
		# marches on through the body billing the pool its still-huge
		# `remaining` at EVERY step until the budget is spent —
		# ≈ available²/(2·hp), tens of times the whole pool. That is how the
		# 15,000-health whale died within moments of touching the player or
		# the terrain (owner report 2026-08-21). Charge flesh ONCE, damped.
		# The `continue` also deliberately skips the punch-through refund
		# below: a living body soaks the crash, nothing rides through it. The
		# ram-immunity skip above still runs first, so a charging creature's
		# own ram stays free.
		if shared_health_max > 0.0 and shared_health > 0.0:
			var factor: float = Tunables.get_num("creature_terrain_impact_factor") \
				if impact.get("terrain", false) else Tunables.get_num("creature_impact_factor")
			# ARMOR: the struck cell's collision_resist divides the ram bruise, so a
			# SHELL nose (resist 20) barely feels a crash a flesh nose (resist 1)
			# pays in full — the owner's armored-kraken/brown-whale (2026-08-23).
			# This is the whole ride-mining survivability model now that the blanket
			# ridden-mining immunity is gone: durability is EARNED by shell, not a
			# flag, so a half-mined nose loses its armor exactly as its shell strips.
			var billed := available * factor / BlockDB.collision_resist(blocks[cell]["type"])
			damage_cell(cell, billed, false)
			# A living creature's crash also floats a number at the contact point
			# (owner 2026-08-22) — coalesced by the listener so a crush against a
			# wall shows one growing number, not a spray.
			if billed > 0.0:
				collision_damage.emit(to_global(impact["pos"]), billed)
			# Record the collision bite with its source and the resulting pool.
			# Inert when off (diag null for every ship but a watched whale).
			if diag != null:
				diag.on_whale_damage(self,
					"terrain" if impact.get("terrain", false) else "ship-episode",
					billed, impact["normal"], false, shared_health)
			continue
		# The crush spends itself INWARD, cell by cell along the contact
		# normal, in this one impact. The old per-frame refund loop re-paid
		# the collision threshold on every step, so the bite always stopped
		# after one cell no matter how hard the hit.
		var local_n: Vector2 = transform.basis_xform_inv(impact["normal"])
		# The walk marches through the authored `blocks` grid, so a mirrored
		# carcass needs the normal's x reflected into grid space too (same as
		# _impact_cell) or the crush would eat inward on the wrong side.
		if _is_mirrored():
			local_n.x = -local_n.x
		var step := Vector2i(roundi(local_n.x), roundi(local_n.y))
		if step == Vector2i.ZERO:
			step = Vector2i(0, -1)
		var walk := cell
		var remaining := available
		while blocks.has(walk) and remaining > 0.0:
			var hp: float = blocks[walk]["hp"]
			# A cell may RESIST the crush (gasbags deform, they don't shatter —
			# owner). resist multiplies the budget it absorbs before dying, and
			# divides the crush damage it actually takes; 1.0 leaves every normal
			# block exactly as before. Combat is untouched — shots never walk
			# here (see BlockDB.collision_resist).
			var resist: float = BlockDB.collision_resist(blocks[walk]["type"])
			# rebuild_now=false: ONE rebuild after the whole batch — the
			# belly-flop freeze was a full rebuild (11k-block greedy merge)
			# per crunched cell, all in a single frame.
			var died := damage_cell(walk, remaining / resist, false)
			_rebuild_dirty = _rebuild_dirty or died
			var cost := hp * resist  # budget this cell soaks before it breaks
			if remaining < cost:
				remaining = 0.0
				break
			remaining -= cost
			walk += step
		# Collision damage landed: float a number at the world contact point
		# (owner 2026-08-22). `available - remaining` is what the hull actually
		# absorbed — zero when a fully immune/whiffed crush changed nothing.
		var spent := available - remaining
		if spent > 0.0:
			collision_damage.emit(to_global(impact["pos"]), spent)
		if remaining > 0.0 and i == dominant:
			# Punched clean through: whatever the hull did not absorb rides
			# on as restored velocity into the gap.
			var leftover_momentum := remaining / Tunables.get_num("impact_damage_scale") * unit2
			var restored: Vector2 = -impact["normal"] * (leftover_momentum / mass)
			linear_velocity += restored

	# One coalesced rebuild for everything that changed the grid this frame —
	# the crash crush above and/or combat cell deaths deferred by
	# net_damage_cell. Walls held through both, so no severing (N deaths → 1
	# rebuild).
	if _rebuild_dirty:
		_rebuild_dirty = false
		rebuild()


## Is this contact the creature's own charge landing? The normal of a hit
## taken head-on while charging points back INTO the charger, so a normal
## opposed to `ram_immunity_dir` is the ram itself, not self-harm.
##
## MUST be evaluated at RECORD time (in _integrate_forces) as well as at
## billing time, and that is the whole point of the "immune" stamp. The
## two clocks are different: contacts are recorded during the physics step
## and billed on a later IDLE frame, and WhaleAI ends the attack — clearing
## `ram_immunity_dir` — exactly when the crunch kills the whale's speed.
## Any frame carrying two physics ticks therefore slotted `_end_attack()`
## between record and billing, and the whale paid full price for the very
## ram this immunity exists to forgive. Measured 2026-08-21: 1,024 hp per
## terminal crunch at 8×, ~7% of the pool per successful ram, on EVERY ram
## that actually connects — the owner's "it hits a world block and just
## poofs".
func _is_ram_immune(normal: Vector2) -> bool:
	return ram_immunity_dir != Vector2.ZERO \
		and normal.dot(ram_immunity_dir) < -0.3


## Momentum scales with mass·velocity ∝ unit²·unit, so impact thresholds
## and damage conversion carry unit³ — the same crash at any scale costs
## the same blocks.
func _unit3() -> float:
	return scale_unit * scale_unit * scale_unit


## Resolve a SHIP-LOCAL contact point to the block it actually hit.
## Contacts land exactly on faces and corners, where rounding falls into
## empty neighbours. Local coordinates on purpose: the crush runs on a
## later idle frame, and at 8× combat speeds the hull drifts whole cells
## between recording and processing — a global point resolved against
## the moved ship lands in open air and the crush silently fizzles.
## Sample inward along the (global) normal first, then take the nearest
## occupied cell in the 3×3 around the sample.
func _impact_cell(local_pos: Vector2, normal: Vector2) -> Vector2i:
	# The recorded point and the collider live in mirrored physical space for a
	# flipped creature; the `blocks` grid does not. Carry both the point and the
	# (node-local) normal back to authored-grid space so the cell we resolve is
	# the one the drawn/collider head actually struck — otherwise a crush on the
	# drawn head would bill the cell on the far (tail) side.
	var grid_pos := _mirror_point(local_pos)
	var grid_n := transform.basis_xform_inv(normal)
	if _is_mirrored():
		grid_n.x = -grid_n.x
	var sample: Vector2 = grid_pos + grid_n * (CELL * 0.5)
	var cell := Vector2i((sample / CELL).round())
	if blocks.has(cell):
		return cell
	var best := cell
	var best_d := INF
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var n := cell + Vector2i(dx, dy)
			if not blocks.has(n):
				continue
			var d := local_pos_of(n).distance_squared_to(grid_pos)
			if d < best_d:
				best_d = d
				best = n
	if best_d < INF:
		return best
	# Last resort: nearest occupied cell anywhere. Corner contacts on a
	# hull at 8× combat speed land whole cells outside the grid (the
	# contact pose is a solver step stale on top of the tangential slop),
	# and a fizzled resolution here silently voids the entire crash —
	# the whale's ram "did no damage" through exactly this hole. O(blocks)
	# is fine: impacts are rare, discrete events.
	for n in blocks:
		var d := local_pos_of(n).distance_squared_to(grid_pos)
		if d < best_d:
			best_d = d
			best = n
	return best


# --- Damage ---------------------------------------------------------------

func damage_at_global(global_pos: Vector2, amount: float) -> void:
	damage_cell(cell_at_global(global_pos), amount)


## Named components — engines, helms, doors, propellers, turrets — live and
## die AS A WHOLE (owner spec): damage to any of their cells is damage to
## every cell, so a component's toughness is its per-cell hp regardless of
## footprint, and an engine never lingers as a half-dead corner. Raw
## structure (hull, gasbags, ballast, platforms) stays per-cell.
## Combat damage NEVER severs and never touches the wall layer or the
## blueprint (owner spec): the walls hold the ship's shape while its
## blocking tiles are shot away, and repair can restore the rest. Also the
## single biggest perf rule on a big ship — no per-hit connectivity
## flood-fill. Returns true if any block died. `rebuild_now := false`
## lets a crash batch many cell deaths into ONE rebuild (the belly-flop
## freeze was N full rebuilds + N flood-fills in a single frame).
##
## `dead_out`, when given, is filled with one {"cell", "type"} entry per block
## actually destroyed by this call — the hook the coalesced COMBAT path uses to
## update mass / CoM / collider incrementally without a full rebuild (see
## net_damage_cell → _combat_incremental_drop). A fresh [] is the default, so
## callers that don't care (the crush walk, build/repair) are unaffected.
func damage_cell(cell: Vector2i, amount: float, rebuild_now := true,
		dead_out: Array = []) -> bool:
	if not blocks.has(cell):
		return false
	# A LIVING creature absorbs everything into its shared pool — blocks
	# break only on a carcass (see "Creature body" above). Still emits
	# `damaged`, so provocation works; still redraws, so the wound shows.
	if shared_health_max > 0.0 and shared_health > 0.0:
		shared_health = maxf(0.0, shared_health - amount)
		damaged.emit(cell, amount)
		queue_redraw()
		# The living→carcass transition: the coarse living collider must switch
		# to the exact per-cell grid the moment the pool empties, so a corpse
		# mines and crushes cell-by-cell (see _use_coarse_collider). A full
		# rebuild swaps it; the crush path passes rebuild_now=false, so defer to
		# the one coalesced rebuild in _process there. Only fires on the single
		# hit that kills the pool — a still-living hit returned above.
		if shared_health <= 0.0:
			if rebuild_now:
				rebuild()
			else:
				_rebuild_dirty = true
		return false
	var members: Array = _component_members(cell)
	var dead: Array[Vector2i] = []
	for c in members:
		if not blocks.has(c):
			continue  # cluster map can be stale mid-batch
		blocks[c]["hp"] -= amount
		if blocks[c]["hp"] <= 0.0:
			dead.append(c)
	damaged.emit(cell, amount)
	if dead.is_empty():
		queue_redraw()
		return false
	for c in dead:
		var type: int = blocks[c]["type"]
		dead_out.append({"cell": c, "type": type})
		blocks.erase(c)
		block_destroyed.emit(c, type)
	if rebuild_now:
		rebuild()
	return true


## Plain BULK structure: a solid cell whose ONLY contributions to the derived
## body are mass, buoyancy and collider coverage — no component glyph, no power
## grid, no thrust, no core, no one-way strip, no bullet shield. Hull, ballast,
## blubber and meat qualify; the whale's whole flesh is these. Gasbags and
## propellers are EXCLUDED even though their BlockDB glyph is "" — they form
## their own draw/behaviour clusters ("G" / "PH"/"PV"), so their death must
## re-derive. This is the gate for the O(dead) combat drop below: a bulk death
## is fully described by "subtract its mass and lift, punch its cell out of the
## collider", with nothing else to recompute.
func _is_bulk(type: int) -> bool:
	if type == BlockDB.Type.GASBAG or type == BlockDB.Type.PROPELLER:
		return false
	var def := BlockDB.get_def(type)
	return def["solid"] and not def["is_core"] and not def["platform"] \
		and not def.get("shield", false) and def["glyph"] == "" \
		and is_zero_approx(def["thrust"]) and is_zero_approx(def["power"]) \
		and is_zero_approx(def["draw"])


## Reconcile the derived body after BULK cells died in combat, in O(dead)
## instead of the O(cells) full rebuild. Mass, centre of mass and total lift
## are patched by subtracting each dead cell's contribution (exactly what the
## rebuild loop would have added), and each cell's collider coverage is punched
## out of the single hull rect that held it. Topology is guaranteed unchanged
## (combat never touches walls), and draw batching self-heals — _draw re-merges
## the live grid every redraw, and damage_cell already queued one.
##
## solid_bounds is deliberately NOT shrunk here: it is only ever a reach/mirror
## cache, a valid (if occasionally half-a-cell generous) superset while cells
## die, and the draw and collider both read the SAME cached axis so they stay
## mutually aligned. The next real structural change (mining, repair, severing,
## a facing flip) runs a full rebuild and refreshes it exactly.
func _combat_incremental_drop(dead: Array) -> void:
	for d in dead:
		var cell: Vector2i = d["cell"]
		var def := BlockDB.get_def(d["type"])
		var m: float = def["mass"] * _fp_norm(d["type"])
		# mass and CoM: peel this cell back out of the weighted sum.
		var weighted := center_of_mass * mass - local_pos_of(cell) * m
		var new_mass := mass - m
		mass = maxf(new_mass, 0.001)
		center_of_mass = weighted / mass if new_mass > 0.0 else Vector2.ZERO
		_total_lift = maxf(0.0, _total_lift - def["lift"])
		_drop_cell_from_collider(cell)
	# 0 is the "recompute from the new shapes" sentinel (godot-quirks); the
	# collider changed, so the physics inertia must be re-derived.
	inertia = 0.0


## Punch one dead cell out of the hull collider: find the merged rect that
## covered it, remove that one shape, and re-merge only the still-solid live
## cells inside that rect's little area. Cost is the area of the affected rect,
## not the whole body — the first hit into a big slab re-merges that slab once
## and splits it, and every hit after lands in a small sub-rect. The shape and
## rect arrays stay in step because both are edited together (see _add_hull_shape).
func _drop_cell_from_collider(cell: Vector2i) -> void:
	var idx := -1
	for i in _hull_rects.size():
		if _hull_rects[i].has_point(cell):
			idx = i
			break
	if idx < 0:
		return  # not covered (already punched, or never solid) — nothing to do
	var rect := _hull_rects[idx]
	var node := _hull_shapes[idx]
	_hull_rects.remove_at(idx)
	_hull_shapes.remove_at(idx)
	remove_child(node)
	node.queue_free()
	var region := {}
	for yy in rect.size.y:
		for xx in rect.size.x:
			var c := rect.position + Vector2i(xx, yy)
			if blocks.has(c) and BlockDB.get_def(blocks[c]["type"])["solid"]:
				region[c] = true
	for r in _greedy_rects(region):
		_add_hull_shape(r)


## The cells that share this cell's fate: its whole glyph cluster for
## component types, just itself for raw blocks.
func _component_members(cell: Vector2i) -> Array:
	var idx: int = _component_of.get(cell, -1)
	if idx < 0:
		return [cell]
	return _glyph_clusters[idx]["cells"]


# --- Severing -------------------------------------------------------------

## Flood-fill over the WALL layer union the current blocks — connectivity
## is structural, so a run of shot-out cells whose walls still stand keeps
## the two sides one ship. The island holding the helm (or the largest, if
## the helm was the thing removed) stays this ship; every other island
## becomes its own Ship, inheriting the velocity it actually had at that
## point on the hull — so severed wreckage tumbles away instead of
## teleporting.
func _resolve_severing() -> void:
	if not is_authority():
		return  # clients receive the result as a grid sync plus a spawned piece
	var islands := _connected_islands()
	if islands.size() <= 1:
		return

	var keep_index := _pick_main_island(islands)

	for i in islands.size():
		if i == keep_index:
			continue
		_spawn_island(islands[i])
		for cell in islands[i]:
			blocks.erase(cell)
			walls.erase(cell)
			_blueprint_erase(cell)  # the piece takes its intended form along

	rebuild()


func _connected_islands() -> Array:
	var unvisited := {}
	for cell in blocks:
		unvisited[cell] = true
	for cell in walls:
		unvisited[cell] = true

	var islands := []
	while not unvisited.is_empty():
		var start: Vector2i = unvisited.keys()[0]
		var island: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		unvisited.erase(start)

		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			island.append(cell)
			for n in _neighbours(cell):
				if unvisited.has(n):
					unvisited.erase(n)
					queue.append(n)

		islands.append(island)

	return islands


func _pick_main_island(islands: Array) -> int:
	var best := 0
	var best_size := -1
	for i in islands.size():
		for cell in islands[i]:
			# Islands can hold wall-only cells (block shot away, wall stands).
			if blocks.has(cell) and BlockDB.get_def(blocks[cell]["type"])["is_core"]:
				return i
		if islands[i].size() > best_size:
			best_size = islands[i].size()
			best = i
	return best


## Build a Ship from a spawn payload. Used for severed wreckage, for network
## spawning, and (later) for loading saves — one construction path, so a ship
## rebuilt from a save is identical to one rebuilt from the wire.
static func from_data(data: Dictionary) -> Ship:
	var s := Ship.new()
	s.position = data["pos"]
	s.rotation = data["rot"]
	# Seed the interpolation shadow from the payload. Without this a client's
	# newly spawned ship would start easing toward a net pose of (0,0) for the
	# frame or two before the first sync packet lands.
	s.net_position = s.position
	s.net_rotation = s.rotation
	# Walls ride the payload (the structural footprint that holds severing
	# connectivity). Set BEFORE apply_serialized, because the rebuild it triggers
	# only derives walls from the block footprint when `walls` is still empty —
	# so an explicit set here is preserved, and its absence (a legacy payload, or
	# an empty array) falls back to derive-from-footprint. This keeps a ship whose
	# blocks were shot away while their walls stood severable exactly as it was,
	# instead of re-deriving a drifted footprint (see to_payload).
	s.walls = _decode_walls(data.get("walls", PackedInt32Array()))
	# Tethered balloons before the rebuild, so their lift is folded in at build time.
	s.balloons = _decode_balloons(data.get("balloons", PackedInt32Array()))
	s.apply_serialized(data["grid"])
	s.linear_velocity = data["linvel"]
	s.angular_velocity = data["angvel"]
	s.assist_enabled = data.get("assist", true)
	s.pilot_peer = data.get("pilot", 1)
	s.faction = int(data.get("faction", 0))
	s.shared_health = float(data.get("shared", 0.0))
	s.shared_health_max = float(data.get("shared_max", 0.0))
	# Creature identity for the taming/riding layer: the taming tier (whale vs
	# critter) and the ride nimbleness. Default to a plain vessel's values so a
	# legacy payload / a non-creature is unchanged.
	s.tame_level = int(data.get("tame_level", 1))
	s.ride_speed_mult = float(data.get("ride_speed_mult", 1.0))
	s.creature_kind = String(data.get("creature_kind", ""))
	s.scale_unit = float(data.get("unit", 1.0))
	if s.scale_unit != 1.0:
		# Gravity scales with the world so fall timing matches the bigger
		# distances. (The Airspace, when active, multiplies this per band.)
		s.gravity_scale = s.scale_unit
	# Absent for wreckage, which is its own intended form from now on.
	s.blueprint = data.get("blueprint", PackedInt32Array())
	return s


## The inverse of from_data: this ship as a spawn payload. Used to re-create a
## ship *through the spawner* — a hull that was added to the Fleet directly
## (single-player, tests) is invisible to MultiplayerSpawner, so hosting a
## session after offline play has to respawn it (maps/world/world.gd).
##
## Every field a peer needs must be here. Assigning one to the Ship that comes
## back sets it on the server only, silently — the trap that shipped as
## "sometimes you can fly someone else's ship" (godot-quirks). If a new
## replicated property is added to from_data, it belongs in this dictionary in
## the same commit.
##
## The WALL layer rides the payload (`walls`) so a rehomed/severed/replicated
## ship keeps its EXACT structural footprint instead of re-deriving it from the
## current block footprint. Re-deriving drifts severability: a cell whose block
## was shot away while its wall still stood would come back severable where it
## was not before. A payload without `walls` (a legacy save, wreckage) still
## loads — from_data falls back to derive-from-footprint. See from_data.
func to_payload() -> Dictionary:
	return {
		"grid": serialize(),
		"pos": position,
		"rot": rotation,
		"linvel": linear_velocity,
		"angvel": angular_velocity,
		"assist": assist_enabled,
		"pilot": pilot_peer,
		"unit": scale_unit,
		"faction": faction,
		"shared": shared_health,
		"shared_max": shared_health_max,
		"tame_level": tame_level,
		"ride_speed_mult": ride_speed_mult,
		"creature_kind": creature_kind,
		"blueprint": blueprint,
		"walls": _encode_walls(),
		"balloons": _encode_balloons(),
	}


## Attached balloons as a flat [cell.x, cell.y, size, hp×100, ...] array (FOUR
## ints each). Rides `to_payload` so a built carcass-airship keeps its lift AND
## its battle damage; decoded below. hp is fixed-point ×100 to stay integral.
func _encode_balloons() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(balloons.size() * 4)
	var i := 0
	for b in balloons:
		out[i] = int(b["cell"].x)
		out[i + 1] = int(b["cell"].y)
		out[i + 2] = int(b["size"])
		out[i + 3] = int(round(float(b.get("hp", BALLOON_HP[int(b["size"])])) * 100.0))
		i += 4
	return out


## Decode a flat balloon array back into the {"cell","size","hp"} list.
## Absent/empty (a legacy payload) yields none — a plain ship with no balloons,
## unchanged. BACKWARD-COMPAT: the pre-hp format packed THREE ints per balloon;
## a length divisible by 3 but not 4 is read that way and healed to full, so a
## save made before balloons had hp still loads its airship.
static func _decode_balloons(data: PackedInt32Array) -> Array:
	var out: Array = []
	var stride := 4 if data.size() % 4 == 0 else 3
	var i := 0
	while i + stride - 1 < data.size():
		var size: int = clampi(data[i + 2], 0, BALLOON_HP.size() - 1)
		var hp: float = float(data[i + 3]) / 100.0 if stride == 4 else BALLOON_HP[size]
		out.append({"cell": Vector2i(data[i], data[i + 1]), "size": size, "hp": hp})
		i += stride
	return out


## The wall layer as a flat PackedInt32Array [x, y, ...] — two ints per wall
## cell, the same compact idea as the block grid (which carries type + hp too,
## but a wall is just a present cell). Rides `to_payload`; decoded by _decode_walls.
func _encode_walls() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(walls.size() * 2)
	var i := 0
	for cell in walls:
		out[i] = cell.x
		out[i + 1] = cell.y
		i += 2
	return out


## Decode a flat [x, y, ...] wall array back into the {Vector2i: true} set. An
## empty array (a legacy payload with no `walls`, or one encoded from an empty
## set) yields an empty dict, which rebuild() then fills from the block footprint
## — the backward-compatible fallback.
static func _decode_walls(data: PackedInt32Array) -> Dictionary:
	var w := {}
	var i := 0
	while i + 1 < data.size():
		w[Vector2i(data[i], data[i + 1])] = true
		i += 2
	return w


func _island_data(island: Array) -> Dictionary:
	# Wall-only cells (block destroyed, wall standing) don't travel: the
	# severed piece is built from its real blocks, and its own footprint
	# becomes its wall layer on construction.
	var block_cells: Array[Vector2i] = []
	for cell in island:
		if blocks.has(cell):
			block_cells.append(cell)
	var grid := PackedInt32Array()
	grid.resize(block_cells.size() * 4)
	var i := 0
	for cell in block_cells:
		grid[i] = cell.x
		grid[i + 1] = cell.y
		grid[i + 2] = blocks[cell]["type"]
		grid[i + 3] = roundi(blocks[cell]["hp"])
		i += 4

	return {
		# Same cell coordinates and same transform, so the piece does not jump.
		# (Under the upright rule ships carry no spin, so the piece inherits
		# the parent's linear velocity plainly — the old ω × r lever term is
		# gone with the ω.)
		"grid": grid,
		"pos": position,
		"rot": rotation,
		"linvel": linear_velocity,
		"angvel": 0.0,
		"assist": false,  # wreckage does not fly itself
		"pilot": 0,       # and nobody is flying it
		"unit": scale_unit,  # wreckage falls at its world's scale
		"faction": faction,  # and keeps its allegiance
	}


func _spawn_island(island: Array) -> void:
	var data := _island_data(island)
	if (data["grid"] as PackedInt32Array).is_empty():
		return  # an island of bare walls with no blocks left just evaporates
	var parent := get_parent()
	var piece: Ship = null

	# A Fleet parent routes the spawn through MultiplayerSpawner so clients see
	# the wreckage too. Without one (single-player, tests) construct directly.
	if parent != null and parent.has_method("spawn_ship"):
		piece = parent.spawn_ship(data)
	else:
		piece = Ship.from_data(data)
		if parent != null:
			parent.call_deferred("add_child", piece)

	if piece != null:
		severed.emit(piece)


func _neighbours(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.LEFT,
		cell + Vector2i.RIGHT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN,
	]


# --- Serialisation --------------------------------------------------------
#
# The whole ship is four ints per block: x, y, type, hp. A 200-block vessel is
# 3.2 KB, and it only travels when the grid actually changes. Everything
# else — collider, mass, centre of mass, inertia, lift, rendering — is derived
# identically on every peer by rebuild(). This is what grid-as-truth buys.
#
# The same format is the save format. Do not let them diverge.

func serialize() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(blocks.size() * 4)
	var i := 0
	for cell in blocks:
		out[i] = cell.x
		out[i + 1] = cell.y
		out[i + 2] = blocks[cell]["type"]
		out[i + 3] = roundi(blocks[cell]["hp"])
		i += 4
	return out


func apply_serialized(data: PackedInt32Array) -> void:
	blocks.clear()
	var i := 0
	while i + 3 < data.size():
		blocks[Vector2i(data[i], data[i + 1])] = {
			"type": data[i + 2],
			"hp": float(data[i + 3]),
		}
		i += 4
	rebuild()


# --- Blueprint and repair -------------------------------------------------
#
# Playing the original showed the repair tool restoring a ship "to its original
# form", which means the game keeps the ship's *intended* shape separately from
# its current one. Under grid-as-truth that costs nothing: a blueprint is just
# another serialised grid, in the same format used for saves and the wire.
#
# Repair is therefore "move the current grid toward the blueprint grid", and it
# works for both damaged blocks and blocks that were destroyed outright.

var blueprint: PackedInt32Array = PackedInt32Array()


func capture_blueprint() -> void:
	blueprint = serialize()
	_bp_cache_size = -1  # invalidate


## The blueprint may only be edited through construction — set_block /
## remove_block (the wall layer) — never by combat (owner spec).
func _blueprint_set(cell: Vector2i, type: int) -> void:
	var i := 0
	while i + 3 < blueprint.size():
		if blueprint[i] == cell.x and blueprint[i + 1] == cell.y:
			blueprint[i + 2] = type
			blueprint[i + 3] = roundi(BlockDB.max_hp(type))
			if _bp_cache_size == blueprint.size():
				_bp_cache[cell] = type  # keep the cache honest on type swap
			return
		i += 4
	blueprint.append(cell.x)
	blueprint.append(cell.y)
	blueprint.append(type)
	blueprint.append(roundi(BlockDB.max_hp(type)))
	_bp_cache_size = -1


func _blueprint_erase(cell: Vector2i) -> void:
	var i := 0
	while i + 3 < blueprint.size():
		if blueprint[i] == cell.x and blueprint[i + 1] == cell.y:
			for _k in 4:
				blueprint.remove_at(i)
			_bp_cache_size = -1
			return
		i += 4


## Cached — the repair sweep queries this many times per frame, and an
## 11k-entry rebuild per query would be its own freeze.
var _bp_cache := {}
var _bp_cache_size := -1


func blueprint_map() -> Dictionary:
	if _bp_cache_size != blueprint.size():
		_bp_cache.clear()
		var i := 0
		while i + 3 < blueprint.size():
			_bp_cache[Vector2i(blueprint[i], blueprint[i + 1])] = blueprint[i + 2]
			i += 4
		_bp_cache_size = blueprint.size()
	return _bp_cache


## Repair one cell toward the blueprint. Heals a damaged block, or rebuilds one
## that was destroyed. Returns whether any work was actually done, so a repair
## tool can avoid charging the player for dragging over intact hull.
func repair_cell(cell: Vector2i, amount: float) -> bool:
	if not is_authority():
		return false

	var intended := blueprint_map()
	if not intended.has(cell):
		return false  # never build beyond the blueprint — that is construction

	var type: int = intended[cell]
	var max_hp := BlockDB.max_hp(type)

	if blocks.has(cell):
		if blocks[cell]["hp"] >= max_hp:
			return false
		blocks[cell]["hp"] = minf(blocks[cell]["hp"] + amount, max_hp)
		queue_redraw()
		return true

	# Destroyed outright. Only rebuild where it can attach, so repairing a hull
	# cannot conjure back a section that was severed and drifted away.
	if not can_place_at(cell):
		return false
	set_block(cell, type)
	blocks[cell]["hp"] = minf(amount, max_hp)
	queue_redraw()
	return true


## The repair wand (owner, from the original): effectively unlimited
## reach, slow, sweeps with the mouse — this repairs the most cursor-near
## blueprint cell that needs work, within a small scan box, so dragging
## across a wreck heals it strip by strip. Returns whether work was done.
const REPAIR_SCAN := 3  # cells each way around the cursor

static var _repair_offsets: Array[Vector2i] = []


func repair_near(cell: Vector2i, amount: float) -> bool:
	if _repair_offsets.is_empty():
		for dy in range(-REPAIR_SCAN, REPAIR_SCAN + 1):
			for dx in range(-REPAIR_SCAN, REPAIR_SCAN + 1):
				_repair_offsets.append(Vector2i(dx, dy))
		_repair_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a).length_squared() < Vector2(b).length_squared())
	for off in _repair_offsets:
		if repair_cell(cell + off, amount):
			return true
	return false


func net_repair_near(cell: Vector2i, amount: float) -> void:
	if is_authority():
		repair_near(cell, amount)
	else:
		_request_repair.rpc_id(1, cell, amount)


@rpc("any_peer", "reliable")
func _request_repair(cell: Vector2i, amount: float) -> void:
	if not multiplayer.is_server():
		return
	repair_near(cell, amount)


## 0.0 – 1.0 against the blueprint, counting both missing and damaged blocks.
func blueprint_completion() -> float:
	var intended := blueprint_map()
	if intended.is_empty():
		return 1.0
	var total := 0.0
	var current := 0.0
	for cell in intended:
		var max_hp := BlockDB.max_hp(intended[cell])
		total += max_hp
		if blocks.has(cell):
			current += minf(blocks[cell]["hp"], max_hp)
	return current / total if total > 0.0 else 1.0


# --- Replication ----------------------------------------------------------
#
# Authority model: the server simulates and owns every structural change.
# Clients ask; they never assume. A client that could mutate its own grid would
# desync the instant the server disagreed about whether a block was still
# there — and with destructible ships, that happens constantly.

func _broadcast_grid() -> void:
	if not (is_online() and multiplayer.is_server()):
		return
	if not _grid_replicated:
		# The spawn payload already carried this grid, and broadcasting now
		# would race the spawn packet — the RPC can reach a peer before the
		# node it addresses exists there. Skip the first one.
		_grid_replicated = true
		return
	# From here on the payload the spawner replays to a late joiner is stale:
	# they need the current grid pushed after they announce readiness.
	_grid_diverged_from_payload = true
	_sync_grid.rpc(serialize())


@rpc("authority", "call_remote", "reliable")
func _sync_grid(data: PackedInt32Array) -> void:
	apply_serialized(data)


## MultiplayerSpawner replays the *original* spawn payload to a late joiner, so
## a ship that has since been built on, mined or shot would arrive stale. The
## server pushes the current grid to bring them level, on the joiner's own
## ready signal (see Fleet's late-join handshake).
##
## A ship whose grid still matches its payload is skipped: the joiner already
## has the right grid, and an 11k-block push per pristine hull on every join is
## a real bill. It also closes the last ordering hole — a ship spawned in the
## same frame the ready signal lands has not been created on the joiner yet,
## and an RPC to a node that does not exist there would be dropped anyway.
func push_grid_to(peer: int) -> void:
	if not _grid_diverged_from_payload:
		return
	if is_online() and multiplayer.is_server():
		_sync_grid.rpc_id(peer, serialize())


## Public API for build input. Correct in single-player and online alike, so
## callers never branch on network state.
func net_set_block(cell: Vector2i, type: int) -> void:
	if is_authority():
		if can_place_at(cell):
			set_block(cell, type)
	else:
		_request_set_block.rpc_id(1, cell, type)


func net_remove_block(cell: Vector2i) -> void:
	if is_authority():
		remove_block(cell)
	else:
		_request_remove_block.rpc_id(1, cell)


func net_damage_cell(cell: Vector2i, amount: float) -> void:
	if is_authority():
		var had := blocks.has(cell)
		_apply_combat_damage(cell, amount)
		# Float a damage number at the struck cell's world point — the gunfire
		# twin of the crush's collision_damage. Emitted here (not in damage_cell)
		# so ONLY shots float, never the crash crush; guarded by `had` so a shot
		# into empty space mints no number. This is what finally makes whale hits
		# read: their damage drains the shared pool and breaks no block, so the
		# only feedback was the wound-darkening.
		if had:
			combat_damage.emit(to_global(local_pos_of(cell)), amount)
		# Shot hits reach a whale only through here (impacts call damage_cell
		# directly), so this is the clean place to tag "shot" for the
		# diagnostic. Inert when off. Shots carry no contact normal.
		if diag != null:
			diag.on_whale_damage(self, "shot", amount, Vector2.ZERO, false, shared_health)
	else:
		_request_damage.rpc_id(1, cell, amount)


## Damage balloon `i` through the authority (the balloon twin of net_damage_cell:
## a balloon's hp and its pop are structural state, so the server owns them and a
## client forwards the request). Floats a damage number at the bulb either way.
func net_damage_balloon(i: int, amount: float) -> void:
	if is_authority():
		if i < 0 or i >= balloons.size():
			return
		var at := balloon_center(i)
		damage_balloon(i, amount)
		combat_damage.emit(at, amount)
	else:
		_request_balloon_damage.rpc_id(1, i, amount)


@rpc("any_peer", "reliable")
func _request_balloon_damage(i: int, amount: float) -> void:
	if not multiplayer.is_server():
		return  # a client must never act on another peer's request
	net_damage_balloon(i, amount)


## The authority-side combat-damage path, shared by net_damage_cell and a
## client's _request_damage. Destroys the struck cells NOW, then reconciles the
## derived body WITHOUT a full O(cells) rebuild wherever it safely can:
##   * plain BULK cells (hull, blubber, meat, ballast — no lift-cluster, no
##     component, no platform/shield) are dropped incrementally: mass, CoM and
##     the one collider rect that held them are patched in O(dead). This is the
##     carcass-under-fire fix — a full rebuild measured ~50 ms on the 5,120-cell
##     whale, so one per frame (never mind one per hit) was a slideshow.
##   * anything else (a component, a gasbag, a platform) changes lift / power /
##     glyphs / one-way strips, so it falls back to the COALESCED full rebuild
##     (_rebuild_dirty, drained once per frame in _process). Combat never severs
##     (walls hold), so neither path needs a connectivity pass.
func _apply_combat_damage(cell: Vector2i, amount: float) -> void:
	var dead: Array = []
	if not damage_cell(cell, amount, false, dead):
		return
	if blocks.is_empty():
		# The last block just died — only a full rebuild emits `destroyed` and
		# frees the node (an incremental patch would leave a 0-block, 0-shape
		# ghost that falls through the world). Coalesced, so a volley that
		# finishes a ship still frees it exactly once.
		_rebuild_dirty = true
		return
	for d in dead:
		if not _is_bulk(d["type"]):
			# A component/gasbag/platform died — its lift, power, glyphs or
			# one-way strips changed. Re-derive everything once this frame.
			_rebuild_dirty = true
			return
	_combat_incremental_drop(dead)


@rpc("any_peer", "reliable")
func _request_set_block(cell: Vector2i, type: int) -> void:
	if not multiplayer.is_server():
		return  # a client must never act on another client's request
	if can_place_at(cell):
		set_block(cell, type)


@rpc("any_peer", "reliable")
func _request_remove_block(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	remove_block(cell)


@rpc("any_peer", "reliable")
func _request_damage(cell: Vector2i, amount: float) -> void:
	if not multiplayer.is_server():
		return
	# Same incremental / coalesced path as net_damage_cell — a client's shots
	# must not each fire a full rebuild on the server either.
	_apply_combat_damage(cell, amount)


## Flight input. Sent unreliably and ordered — a dropped control frame is
## replaced by the next one 16ms later, and stale input is worse than none.
func net_set_controls(h: float, v: float) -> void:
	if is_authority():
		if not has_helm():
			return  # no control panel, no control — repair it first
		thrust_input = Vector2(clampf(h, -1.0, 1.0), clampf(v, -1.0, 1.0))
	else:
		_request_controls.rpc_id(1, h, v)


@rpc("any_peer", "unreliable_ordered")
func _request_controls(h: float, v: float) -> void:
	if not multiplayer.is_server():
		return
	# You may only fly your own ship. Without this check any peer could steer
	# any vessel, which is the cheapest possible exploit to leave open.
	if multiplayer.get_remote_sender_id() != pilot_peer:
		return
	if not has_helm():
		return
	thrust_input = Vector2(clampf(h, -1.0, 1.0), clampf(v, -1.0, 1.0))


# --- Placeholder rendering ------------------------------------------------

## Blocks are drawn directly rather than sprited, so the prototype needs no art
## and damage stays legible: a block darkens as it loses hp. Functional blocks
## carry a letter glyph (E engine, P propeller, V lift prop, H helm, T turret)
## so a ship's anatomy is readable at a glance — the helm being findable is
## what makes the ship pilotable at all.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	# THE SKIN FLIP (see visual_facing / ROADMAP Q10). One canvas transform,
	# set before a single command is emitted, so the region-batched rects,
	# the gasbag edges, the damage and whole-body wound shading and the
	# glyphs all ride it for free. It mirrors about the vertical axis
	# through the centre of the SOLID footprint, so the mirrored drawing
	# occupies exactly the AABB the untouched collider still occupies —
	# the body turns without the geometry moving a hair, which is the whole
	# point (the source's real mirror dumps riders off the head).
	# Only a creature can ever hold facing -1; vessels never reach here.
	if visual_facing < 0 and solid_bounds.size.x > 0.0:
		var axis_x := solid_bounds.position.x + solid_bounds.size.x * 0.5
		draw_set_transform(Vector2(axis_x * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))
	# Batched placeholder art (owner report: 22 FPS with nothing going
	# on). One filled rect per contiguous same-type, same-damage-shade
	# region instead of one per cell: the per-block version retained ~23k
	# canvas commands across the 8× ships, and the renderer replays every
	# retained command every frame. Damage still darkens, in 6 visible
	# steps; balloons keep their per-cell borders (owner: a blimp LOOKS
	# like the list of blocks it is) via a single multiline command.
	var groups := {}  # type*8+shade -> {"cells": {}, "color": Color, "type": int}
	var bag_edges := PackedVector2Array()
	# A living creature wounds as a WHOLE: one shade for the whole body,
	# from the shared pool. (Its blocks are all pristine while it lives.)
	var creature_shade := -1
	if shared_health_max > 0.0 and shared_health > 0.0:
		creature_shade = roundi(clampf(shared_health / shared_health_max, 0.0, 1.0) * 5.0)
	for cell in blocks:
		var type: int = blocks[cell]["type"]
		var frac: float = clampf(blocks[cell]["hp"] / BlockDB.max_hp(type), 0.0, 1.0)
		var shade := creature_shade if creature_shade >= 0 else roundi(frac * 5.0)
		var key := type * 8 + shade
		if not groups.has(key):
			var color := BlockDB.color_of(type).darkened((1.0 - shade / 5.0) * 0.6)
			if faction == 1:
				# Friend/foe must read before range (playtest scar):
				# HOSTILE hulls wear their allegiance as a red cast.
				# Wildlife (faction 2) keeps its natural colours — a
				# neutral whale must not read as an enemy.
				color = color.lerp(Color(0.80, 0.18, 0.15), 0.4)
			color *= body_tint  # cosmetic (identity white for all normal ships)
			groups[key] = {"cells": {}, "color": color, "type": type}
		(groups[key]["cells"] as Dictionary)[cell] = true
		if type == BlockDB.Type.GASBAG:
			var tl := local_pos_of(cell) - Vector2.ONE * CELL * 0.5
			bag_edges.append_array(PackedVector2Array([
				tl, tl + Vector2(CELL, 0),
				tl + Vector2(CELL, 0), tl + Vector2(CELL, CELL),
				tl + Vector2(CELL, CELL), tl + Vector2(0, CELL),
				tl + Vector2(0, CELL), tl,
			]))

	for key in groups:
		var g: Dictionary = groups[key]
		for rect in _greedy_rects(g["cells"]):
			_draw_region(rect, g["type"], g["color"])
	if bag_edges.size() >= 4:
		var line := BlockDB.color_of(BlockDB.Type.GASBAG).darkened(0.35)
		if faction == 1:
			line = line.lerp(Color(0.80, 0.18, 0.15), 0.4)
		line *= body_tint
		draw_multiline(bag_edges, line, 1.0)

	for cluster in _glyph_clusters:
		_draw_cluster_glyph(font, cluster)


## Contiguous same-labelled cells become one cluster; the label is drawn
## once across the cluster's bounds, scaled to fit. Owner spec for the 8×
## world: a 4×4 generator reads "E", propeller slabs read "P(V)"/"P(H)"
## by axis, doors carry two Ds at 25% and 75% of their height.
func _rebuild_glyph_clusters() -> void:
	_glyph_clusters.clear()
	_component_of.clear()
	var visited := {}
	for cell in blocks:
		if visited.has(cell):
			continue
		var key := _glyph_key(cell)
		if key == "":
			continue
		visited[cell] = true
		var queue: Array[Vector2i] = [cell]
		var cells: Array[Vector2i] = []
		var rect := Rect2(local_pos_of(cell) - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL)
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			cells.append(c)
			rect = rect.merge(Rect2(local_pos_of(c) - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL))
			for n in _neighbours(c):
				if not visited.has(n) and blocks.has(n) and _glyph_key(n) == key:
					visited[n] = true
					queue.append(n)
		# Turrets get a firing arc: a 180° half-plane facing AWAY from the
		# mounting (owner; matches the original). Hung under a strut →
		# bears downward; bolted to a wall → bears outboard; corner mounts
		# average to a diagonal.
		var facing := Vector2.ZERO
		if key == "T":
			for c in cells:
				for n in _neighbours(c):
					if blocks.has(n) and _glyph_key(n) != "T":
						facing -= Vector2(n - c)
			facing = facing.normalized() if facing.length() > 0.01 else Vector2.DOWN
		for c in cells:
			_component_of[c] = _glyph_clusters.size()
		_glyph_clusters.append({"key": key, "rect": rect, "cells": cells, "facing": facing})


## Propellers cluster by axis; gasbags cluster as balloons (one unit, no
## letter — owner: "the blimp sections should be one unit, as with P(H)/
## P(V)"); everything else by its glyph. "" means the type is raw
## structure (hull, ballast, platform) and stays per-cell.
func _glyph_key(cell: Vector2i) -> String:
	var type: int = blocks[cell]["type"]
	if type == BlockDB.Type.PROPELLER:
		return "PV" if _vertical_props.has(cell) else "PH"
	if type == BlockDB.Type.GASBAG:
		return "G"
	return BlockDB.get_def(type)["glyph"]


func _draw_cluster_glyph(font: Font, cluster: Dictionary) -> void:
	var rect: Rect2 = cluster["rect"]
	var key: String = cluster["key"]
	if key == "G":
		return  # balloons are a silent unit — mass of colour, no letter
	var color := Color(0.05, 0.05, 0.08, 0.85)

	if key == "D":
		# Two Ds at 25% and 75% of the door's height (owner spec).
		var dfs := clampf(minf(rect.size.x * 0.8, rect.size.y * 0.3), 9.0, 60.0)
		for frac in [0.25, 0.75]:
			draw_string(font,
				Vector2(rect.position.x, rect.position.y + rect.size.y * frac + dfs * 0.36),
				"D", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, int(dfs), color)
		return

	# Single cells keep the terse 1× glyphs; slabs get the descriptive form.
	var single := rect.size.x <= CELL + 0.5 and rect.size.y <= CELL + 0.5
	var label := key
	match key:
		"PV": label = "V" if single else "P(V)"
		"PH": label = "P" if single else "P(H)"
	var fs := clampf(minf(rect.size.y * 0.7, rect.size.x * 1.5 / label.length()), 9.0, 110.0)
	draw_string(font,
		Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + fs * 0.36),
		label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, int(fs), color)


## Draw one merged region in its type's idiom: platforms as top planks,
## struts as one pole per cell column, everything else as a bordered slab.
func _draw_region(cells: Rect2i, type: int, color: Color) -> void:
	var origin := Vector2(cells.position) * CELL - Vector2.ONE * CELL * 0.5
	var size := Vector2(cells.size) * CELL
	if BlockDB.get_def(type)["platform"]:
		# Planks: a thin bar at the top, open below. Thickness follows the
		# world scale (owner: too thin at 8×); the walkable strip stays
		# the 4px top — the bar is presence, not floor.
		var bar := Rect2(origin, Vector2(size.x, clampf(5.0 * scale_unit, 5.0, 12.0)))
		draw_rect(bar, color)
		draw_rect(bar, color.darkened(0.35), false, 1.0)
		return
	if type == BlockDB.Type.STRUT:
		# Scaffold poles, not tiles (born of the owner's review: "did you
		# put a 4x4 DOOR between propeller and turret???"). One pole per
		# cell column spanning the region, so an upscaled strut slab still
		# reads as a bundle of poles.
		for i in cells.size.x:
			var pole := Rect2(origin + Vector2(i * CELL + CELL * 0.36, 0.0),
				Vector2(CELL * 0.28, size.y))
			draw_rect(pole, color)
			draw_rect(pole, color.darkened(0.35), false, 1.0)
		return
	var rect := Rect2(origin, size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.35), false, 1.0)


# --- Stats ----------------------------------------------------------------

## Lift-to-weight at the ship's current altitude. Above 1.0 the ship climbs.
## This is the number the build UI should show the player while they build.
func lift_ratio() -> float:
	var weight := mass * 980.0
	if weight <= 0.0:
		return 0.0
	return (_total_lift * BlockDB.LIFT_PER_MASS * air_density_at(global_position.y)) / weight


func power_supply() -> float:
	return _power_supply * _fp_norm(BlockDB.Type.ENGINE)


func ceiling_estimate() -> float:
	## Altitude where lift exactly cancels weight, i.e. where the ship stops
	## climbing. Weight carries gravity ×unit and lift carries ×unit, so the
	## `needed` density is scale-free; only the air column stretches.
	var weight := mass * 980.0
	if _total_lift <= 0.0 or weight <= 0.0:
		return SEA_LEVEL_Y
	var needed := weight / (_total_lift * BlockDB.LIFT_PER_MASS)
	if needed >= 1.0:
		return SEA_LEVEL_Y
	if needed <= MIN_AIR_DENSITY:
		return CEILING_Y * scale_unit
	return lerpf(CEILING_Y * scale_unit, SEA_LEVEL_Y, needed)
