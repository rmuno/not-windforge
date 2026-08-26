class_name BlockDB
extends RefCounted

## Static block-type table. Everything about a block's physical behaviour lives
## here so that ship simulation stays data-driven — adding a block type must
## never require touching ship.gd.
##
## Component architecture (matches the original — see docs/WIKI_REFERENCE.md):
##   ENGINES produce power. PROPELLERS produce thrust and consume power.
##   Turrets consume power too. When demand exceeds supply, everything powered
##   degrades proportionally — a brownout, not a blackout.

enum Type {
	HULL,
	GASBAG,
	ENGINE,
	PROPELLER,
	HELM,
	BALLAST,
	TURRET,
	DOOR,
	PLATFORM,
	STRUT,
	# Appended (never reordered): the type int rides the wire/save format.
	DOOR_CLOSED,
	# Whale blubber (owner survey 2026-08-20): the original's "naturally
	# buoyant" building material — solid, shapeable, lifting. Armored
	# buoyancy, versus the gasbag's fragile dedicated lift: less lift per
	# mass (2.9 own-masses vs 11), but it IS hull. Mined from whale
	# corpses eventually; buildable now.
	BLUBBER,
	# Whale meat: dense flesh, no lift. Whales are ~60% blubber and much
	# of the rest is this (owner survey). Buildable, per the original's
	# own joke ("you could build a house. Not that anyone would want to").
	MEAT,
	# Kraken SHELL (owner survey 2026-08-23, from the source tooltip:
	# "lightweight and extremely hard", HP 1000, Physical Damage Resistance 80).
	# The ARMOR material: very hard (high hp), light, and a big collision_resist
	# so ram/crush damage barely dents it — this is what lets a shell-nosed
	# kraken/brown-whale RAM terrain to mine without dying, while a flesh nose
	# takes the full bruise. Mined from kraken corpses eventually; buildable.
	SHELL,
}

## mass    — arbitrary units; ship mass is the sum. Gravity is 980 px/s².
## hp      — damage the block absorbs before it is destroyed.
## lift    — buoyancy, in units of "mass this block can hold aloft" at full
##           air density. LIFT_PER_MASS converts it to newtons. Free — no power.
##   shield: blocks BULLETS but not bodies (the control panel is furniture
##           you stand at, not a wall — owner spec). Rendered as a separate
##           layer-4 child body, because per-shape layers do not exist.
## thrust  — propulsive force at full input. ONE propeller block serves both
##           axes: its axis derives from mounting (see Ship._derive_prop_axes) —
##           hung under a hull it lifts, mounted on a side wall it pushes.
## power   — power produced (engines).
## draw    — power consumed at full activity (propellers, turrets).
## is_core — ship survives severing around blocks flagged as core.
##           (A `torque` column once fed the PD flight assist; the upright
##           rule — lock_rotation, owner 2026-08-20 — made rotation not
##           exist for ships, and the column went with it.)
## solid   — contributes collision. Doors are stateful (owner spec,
##           session 3): OPEN is structure without a collider — bodies and
##           bullets pass; CLOSED joins the hull collider and stops both.
##           The state is a type swap (Ship.toggle_door) so it rides the
##           wire/save format for free. Blueprints author doors CLOSED
##           (owner 2026-08-20): ships start and place sealed.
## platform — one-way floor: stand on it, jump up through it from below, and
##           down+jump drops through. Gets a thin one-way shape on a separate
##           child body, never part of the hull collider.
## collision_resist — a MULTIPLIER on the budget a cell absorbs before a
##           COLLISION crush destroys it (Ship._process crush walk), and the
##           reciprocal scaling of the crush damage it takes. 1.0 (the default
##           for every type without the column) is unchanged. Gasbags carry 10:
##           a balloon deforms under a bump, it does not shatter (owner survey
##           2026-08-21 — "blimps should take less damage from soft collisions").
##           COMBAT is untouched: shots reach cells through damage_cell directly,
##           never the crush walk, so this never makes a gasbag bullet-proof.
## flammable — how readily FIRE takes hold (combat/fire.gd), as a multiplier on
##           the base spread chance. Absent or 0 means the material does not
##           burn AT ALL and fire cannot cross it — which is what makes a
##           deconstructed row of hull a real firebreak. Blubber and a gasbag's
##           lifting gas catch fast; timber-ish structure catches slowly; shell,
##           ballast and metal fittings do not catch.
## glyph   — single letter drawn on the block so types read at a glance.
const BLOCKS := {
	Type.HULL:       {"name": "Hull",       "mass": 10.0, "hp": 100.0, "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "flammable": 0.35, "glyph": "",  "color": Color(0.55, 0.45, 0.35)},
	Type.GASBAG:     {"name": "Gasbag",     "mass": 4.0,  "hp": 35.0,  "lift": 44.0, "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "collision_resist": 10.0, "flammable": 2.5, "glyph": "",  "color": Color(0.85, 0.80, 0.62)},
	Type.ENGINE:     {"name": "Engine",     "mass": 12.0, "hp": 80.0,  "lift": 0.0,  "thrust": 0.0,     "power": 1500.0, "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "glyph": "E", "color": Color(0.70, 0.35, 0.20)},
	Type.PROPELLER:  {"name": "Propeller",  "mass": 6.0,  "hp": 60.0,  "lift": 0.0,  "thrust": 30000.0, "power": 0.0,    "draw": 900.0,  "is_core": false, "solid": true,  "platform": false, "glyph": "P", "color": Color(0.60, 0.66, 0.72)},
	Type.HELM:       {"name": "Helm",       "mass": 8.0,  "hp": 140.0, "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": true,  "solid": false, "shield": true, "platform": false, "glyph": "H", "color": Color(0.35, 0.62, 0.80)},
	Type.BALLAST:    {"name": "Ballast",    "mass": 26.0, "hp": 120.0, "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "glyph": "",  "color": Color(0.30, 0.30, 0.34)},
	Type.TURRET:     {"name": "Turret",     "mass": 14.0, "hp": 90.0,  "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 250.0,  "is_core": false, "solid": true,  "platform": false, "glyph": "T", "color": Color(0.55, 0.35, 0.35)},
	Type.DOOR:       {"name": "Door (open)", "mass": 5.0, "hp": 60.0,  "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": false, "platform": false, "flammable": 0.5, "glyph": "D", "color": Color(0.72, 0.62, 0.42, 0.45)},
	Type.DOOR_CLOSED: {"name": "Door (closed)", "mass": 5.0, "hp": 60.0, "lift": 0.0, "thrust": 0.0,    "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "flammable": 0.5, "glyph": "D", "color": Color(0.72, 0.62, 0.42, 0.92)},
	Type.BLUBBER:    {"name": "Blubber",    "mass": 7.0,  "hp": 60.0,  "lift": 20.0, "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "flammable": 1.8, "glyph": "",  "color": Color(0.86, 0.72, 0.66)},
	Type.MEAT:       {"name": "Meat",       "mass": 8.0,  "hp": 50.0,  "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "flammable": 0.6, "glyph": "",  "color": Color(0.58, 0.28, 0.26)},
	Type.SHELL:      {"name": "Shell",      "mass": 2.0,  "hp": 250.0, "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": true,  "platform": false, "collision_resist": 20.0, "glyph": "",  "color": Color(0.74, 0.62, 0.46)},
	Type.PLATFORM:   {"name": "Platform",   "mass": 3.0,  "hp": 40.0,  "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": false, "platform": true, "flammable": 0.5,  "glyph": "",  "color": Color(0.62, 0.52, 0.36)},
	Type.STRUT:      {"name": "Strut",      "mass": 2.0,  "hp": 50.0,  "lift": 0.0,  "thrust": 0.0,     "power": 0.0,    "draw": 0.0,    "is_core": false, "solid": false, "platform": false, "flammable": 0.5, "glyph": "",  "color": Color(0.40, 0.42, 0.46)},
}

## Newtons of lift per unit of `lift` at full air density. Tuned so gravity
## (980) is exactly cancelled: one gasbag holds up `lift` units of mass.
const LIFT_PER_MASS := 980.0

## True component footprints at the shipped 8× scale (owner survey,
## WORLD_SPEC.md → "Scale and component footprints, observed"): engine
## 4×4, propeller 6×2 (or 2×6 by mounting), turret 2×8. A component's
## OUTPUT is its rating, set by the world scale — never by how many
## cells its footprint happens to cover — so per-cell power/thrust/draw
## are normalised by scale²/footprint (Ship._fp_norm): a 12-cell prop
## delivers exactly what a uniform 64-cell slab did, and a 1× ship
## (footprint 1) is untouched. Types absent here keep plain per-cell
## behaviour — bulk blocks (gasbag, blubber) SHOULD scale with their
## cell count. Mass and hp stay per-cell for everything: a smaller
## footprint really is lighter and dies faster.
const FOOTPRINT_8X := {
	Type.ENGINE: 16.0,     # 4×4
	Type.PROPELLER: 12.0,  # 6×2 / 2×6
	Type.TURRET: 16.0,     # 2×8
	Type.HELM: 28.0,       # 4×7 (no output — normalises mass only)
}

## Cells a component of `type` occupies at world scale `su`. Footprints
## are defined for the shipped 8× scale only; every other scale (the 1×
## test fixtures) falls back to the uniform su² slab, which makes the
## normalisation factor exactly 1 there.
static func footprint_cells(type: int, su: float) -> float:
	if is_equal_approx(su, 8.0) and FOOTPRINT_8X.has(type):
		return FOOTPRINT_8X[type]
	return su * su


## Component bundle SHAPES (owner 2026-08-25: "an engine will never be a single
## block, but a rectangle or square — same for other NONPRIMITIVE buildables").
## The width x height each machine PLACES AS, at the shipped 8× scale — the
## same survey shapes FOOTPRINT_8X normalises output by, so a hand-built,
## full-footprint machine produces exactly its rating and weighs exactly its
## rated mass. DOOR_CLOSED (no output, so no footprint entry) bundles too: a
## 2×8 person-height doorway — the player is 8 cells tall, and a one-cell
## door passes nobody. Types absent here are PRIMITIVES (hull, gasbag,
## ballast, platform, strut, flesh): freeform bulk, placed cell by cell.
const BUNDLE_8X := {
	# GASBAG (owner 2026-08-25, "a gasbag is just placeable as a single block
	# — what happened to the helium balloon test?"): a helium bag is a
	# prebuilt THING in the source, never a loose cell. It stamps 4×4 but
	# stays BULK — lift per cell, no output normalisation, and C sculpts it
	# cell by cell (see deconstructs_whole: the starter carries ~49k gasbag
	# cells in a few connected bags; region-removal there would let one
	# misclick delete the ship's whole lift).
	Type.GASBAG: Vector2i(4, 4),
	Type.ENGINE: Vector2i(4, 4),
	Type.PROPELLER: Vector2i(6, 2),  # or 2×6 by mounting — see bundle_dims(rot)
	Type.TURRET: Vector2i(2, 8),
	Type.HELM: Vector2i(4, 7),
	Type.DOOR_CLOSED: Vector2i(2, 8),
}


## The rectangle `type` places as at world scale `su`: its BUNDLE_8X shape at
## the shipped 8×, (1,1) everywhere else — so the 1× test fixtures keep their
## per-cell placement, exactly like footprint_cells. `rot` swaps width and
## height (the source's propeller mounts either way).
static func bundle_dims(type: int, su: float, rot := false) -> Vector2i:
	if is_equal_approx(su, 8.0) and BUNDLE_8X.has(type):
		var d: Vector2i = BUNDLE_8X[type]
		return Vector2i(d.y, d.x) if rot else d
	return Vector2i.ONE


## Does `type` PLACE as a bundle at this scale?
static func is_bundle(type: int, su: float) -> bool:
	return bundle_dims(type, su) != Vector2i.ONE


## Does C remove `type` as a whole machine (the 4-connected region)? True for
## the MACHINES — discrete units whose region is one authored component. The
## gasbag is deliberately excluded: it is bundle-PLACED but BULK — authored
## ships carry contiguous bags tens of thousands of cells large, and "remove
## the whole region" there turns a misclick into deleting the ship's lift.
static func deconstructs_whole(type: int, su: float) -> bool:
	return is_bundle(type, su) and type != Type.GASBAG

static func get_def(type: int) -> Dictionary:
	return BLOCKS.get(type, BLOCKS[Type.HULL])

static func mass_of(type: int) -> float:
	return get_def(type)["mass"]

static func max_hp(type: int) -> float:
	return get_def(type)["hp"]


## How much a cell resists COLLISION crush damage (Ship._process crush walk),
## as a multiplier on the budget it absorbs before dying. 1.0 = a normal block;
## gasbags carry 10. Absent from most rows on purpose — the default keeps every
## other type exactly as it was, and combat never reads this (shots damage cells
## directly, not through the crush).
static func collision_resist(type: int) -> float:
	# The gasbag's resist is a live-tunable lever (debug window / Tunables); every
	# other type reads its table value. Default matches the table (10.0), so the
	# gasbag-soft-collision behaviour is identical until the lever is touched.
	if type == Type.GASBAG:
		return Tunables.get_num("gasbag_collision_resist")
	return get_def(type).get("collision_resist", 1.0)

static func color_of(type: int) -> Color:
	return get_def(type)["color"]

static func type_count() -> int:
	return BLOCKS.size()
