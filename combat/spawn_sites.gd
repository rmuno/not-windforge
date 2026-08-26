class_name SpawnSites
extends RefCounted

## WORLD-ANCHORED SPAWN SITES — charter §4, and the hardest architectural rule
## this project has.
##
## "Population lives in the world, never around the camera." The original
## spawned enemies on a ring just outside the viewport, so pressure was
## constant, sourceless and unearned, and clearing an area could never mean
## anything because the area was not where the enemies came from. Until this
## file, ours was worse in a quieter way: everything alive spawned ONCE, at
## world build, beside the player's ship. Fly an hour in any direction and the
## sky was empty — danger was not a property of place, it was a property of
## the starting room.
##
## A site is a PLACE that holds a population. It is not a node and not a saved
## record: it is a pure function of the world seed and a lattice coordinate, so
## the same seed has the same sky forever and nothing has to be serialised for
## it. The world keeps a small amount of live state per site it has actually
## visited — how many of its residents are out, how many it has left to give,
## when it may give the next one — and that is all.
##
## WHAT MAKES A PLACE DANGEROUS IS ITS BAND. Kraken dens are deep, whale grounds
## are high (the roadmap: "top band most frequent, none below the green band"),
## bandit roosts sit in the temperate middle where the trade is. The lava floor
## holds nothing: nothing lives in it.
##
## HOW IT STAYS CHEAP. Sites are never enumerated world-wide — the world is
## ~1.57M × 1.18M px and would hold hundreds. Only the lattice cells around a
## focus are ever asked about, exactly like terrain chunk streaming, and a cell
## with no site answers null in a few arithmetic ops.

## Lattice spacing in px at world_scale 1; the world multiplies by its scale.
## At the shipped 8× that is ~46k px between candidate cells — a few minutes of
## flight, so a site is a destination rather than scenery.
const LATTICE := 5800.0

## Fraction of a lattice cell a site may be jittered off its centre, so the
## population does not sit on a visible grid.
const JITTER := 0.34

## Not every cell holds a site. Rolled per cell from the seed.
const OCCUPANCY := 0.55

## How near a focus must come for a site to put its residents out. Deliberately
## inside dormancy's wake range (0.8 × dormant_range_px = 9,600) so a fresh
## resident is awake and simulated rather than born asleep — and far outside the
## camera, so nothing is ever seen appearing.
const ACTIVATE_PX := 9000.0

## Seconds between one site releasing one resident. A site fills up over a
## minute or so rather than dumping its whole pool the moment you come in range.
const RELEASE_SECONDS := 12.0

## Seconds to regrow one unit of stock. Slow on purpose: clearing a nest has to
## MEAN something for a while, which is the whole point of the charter rule.
const REGEN_SECONDS := 240.0

## A wild resident this far from every focus is RECLAIMED — freed, its stock
## returned to the site that made it. Without this a long flight leaves a trail
## of dormant bodies across the world and the node count only ever grows. Well
## past the dormancy range, so nothing is reclaimed anywhere near the player.
const RECLAIM_PX := 45000.0

enum Kind { NONE, WHALE_GROUND, CRITTER_MEADOW, BANDIT_ROOST, KRAKEN_DEN,
	BASILISK_EYRIE }


## The site in lattice cell `coord`, or an empty Dictionary for a cell that
## holds none. Pure: (seed, coord, world rect, scale) in, a site out. Keys:
## `coord`, `pos`, `kind`, `pool`, `radius`.
static func site_at(coord: Vector2i, world_seed: int, world_rect: Rect2,
		scale: float) -> Dictionary:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return {}
	var step := LATTICE * maxf(scale, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "site", coord.x, coord.y])
	if rng.randf() > OCCUPANCY:
		return {}
	var centre := Vector2(
		world_rect.position.x + (float(coord.x) + 0.5) * step,
		world_rect.position.y + (float(coord.y) + 0.5) * step)
	var pos := centre + Vector2(
		rng.randf_range(-JITTER, JITTER) * step,
		rng.randf_range(-JITTER, JITTER) * step)
	if not world_rect.has_point(pos):
		return {}
	var kind := kind_for(pos, world_rect, rng)
	if kind == Kind.NONE:
		return {}
	return {
		"coord": coord,
		"pos": pos,
		"kind": kind,
		"pool": pool_for(kind),
		"radius": ACTIVATE_PX * maxf(scale, 1.0),
	}


## What lives at this altitude. The band IS the answer — that is the whole
## content of "danger is a property of place" at this stage of the world.
static func kind_for(pos: Vector2, world_rect: Rect2, rng: RandomNumberGenerator) -> Kind:
	var frac := clampf((world_rect.end.y - pos.y) / world_rect.size.y, 0.0, 1.0)
	var band := Airspace.band_at_frac(frac)
	var roll := rng.randf()
	match band:
		Airspace.Band.LAVA:
			return Kind.NONE            # nothing lives in the floor
		Airspace.Band.DEEP:
			return Kind.KRAKEN_DEN if roll < 0.75 else Kind.NONE
		Airspace.Band.GAP_LOW:
			return Kind.KRAKEN_DEN if roll < 0.35 else Kind.NONE
		Airspace.Band.MID:
			# The temperate middle: people and small wildlife, no whales below
			# the green band (WORLD_SPEC / roadmap).
			return Kind.BANDIT_ROOST if roll < 0.45 else Kind.CRITTER_MEADOW
		Airspace.Band.GAP_HIGH:
			if roll < 0.5:
				return Kind.WHALE_GROUND
			return Kind.BASILISK_EYRIE if roll < 0.7 else Kind.CRITTER_MEADOW
		Airspace.Band.TOP:
			# The richest fauna is up top — the reason to build a better ship —
			# and so is the thing that sets it on fire.
			if roll < 0.55:
				return Kind.WHALE_GROUND
			return Kind.BASILISK_EYRIE if roll < 0.85 else Kind.BANDIT_ROOST
	return Kind.NONE


## How many residents a site of this kind holds at once.
static func pool_for(kind: Kind) -> int:
	match kind:
		Kind.WHALE_GROUND:
			return 3
		Kind.CRITTER_MEADOW:
			return 3
		Kind.BANDIT_ROOST:
			return 2
		Kind.KRAKEN_DEN:
			return 2
		Kind.BASILISK_EYRIE:
			# Two is a fight; three of anything that shoots from range is a
			# firing squad, and the top band already has meteors in it.
			return 2
	return 0


## The lattice cell a world position falls in.
static func coord_of(pos: Vector2, world_rect: Rect2, scale: float) -> Vector2i:
	var step := LATTICE * maxf(scale, 1.0)
	return Vector2i(
		floori((pos.x - world_rect.position.x) / step),
		floori((pos.y - world_rect.position.y) / step))


## Every site within `radius` px of any focus. The only enumeration that ever
## happens: a bounded box of lattice cells per focus, never the world.
static func near(foci: Array, radius: float, world_seed: int,
		world_rect: Rect2, scale: float) -> Array:
	var out: Array = []
	if foci.is_empty() or world_rect.size.x <= 0.0:
		return out
	var step := LATTICE * maxf(scale, 1.0)
	var r_cells := int(ceil(radius / step)) + 1
	var seen := {}
	for f in foci:
		var focus: Vector2 = f
		var fc := coord_of(focus, world_rect, scale)
		for dy in range(-r_cells, r_cells + 1):
			for dx in range(-r_cells, r_cells + 1):
				var coord := fc + Vector2i(dx, dy)
				if seen.has(coord):
					continue
				seen[coord] = true
				var site := site_at(coord, world_seed, world_rect, scale)
				if site.is_empty():
					continue
				if focus.distance_to(site["pos"] as Vector2) <= radius:
					out.append(site)
	return out


## A resident's spawn point: scattered around the site so a pool does not
## appear stacked in one spot. Deterministic in (site, index).
static func resident_pos(site: Dictionary, index: int, world_seed: int,
		scale: float) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "resident", site["coord"], index])
	var spread := LATTICE * 0.22 * maxf(scale, 1.0)
	return (site["pos"] as Vector2) + Vector2(
		rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))


## The STRUCTURE that stands at a site of this kind, or "" for a place that has
## none. Charter §4's second half: "Destroying the nest structure clears it for
## good" — a population you can point at AND stop. A whale ground has no nest
## on purpose: it is open sky on a migration route, and there is nothing there
## to break. Some places can be cleared; some can only be survived.
static func nest_for(kind: Kind) -> String:
	match kind:
		Kind.BANDIT_ROOST:
			return "res://ships/nest_roost.ship"
		Kind.KRAKEN_DEN:
			return "res://ships/nest_den.ship"
		Kind.CRITTER_MEADOW:
			return "res://ships/nest_hive.ship"
		Kind.BASILISK_EYRIE:
			return "res://ships/nest_eyrie.ship"
	return ""


## Which side a site's structure belongs to: a roost is people who shoot at
## you, a den and a hive are wildlife.
static func nest_faction(kind: Kind) -> int:
	return 1 if kind == Kind.BANDIT_ROOST else 2


## Human-readable name — the map legend and the debug window read this.
static func kind_name(kind: Kind) -> String:
	match kind:
		Kind.WHALE_GROUND:
			return "whale ground"
		Kind.CRITTER_MEADOW:
			return "meadow"
		Kind.BANDIT_ROOST:
			return "bandit roost"
		Kind.KRAKEN_DEN:
			return "kraken den"
		Kind.BASILISK_EYRIE:
			return "basilisk eyrie"
	return "empty"


## The map marker's colour, in the same friend/foe language the blips use:
## hostile red for people who shoot, wildlife green, deep-hunter violet.
static func kind_color(kind: Kind) -> Color:
	match kind:
		Kind.WHALE_GROUND:
			return Color(0.55, 0.75, 0.90)
		Kind.CRITTER_MEADOW:
			return Color(0.60, 0.85, 0.55)
		Kind.BANDIT_ROOST:
			return Color(0.90, 0.45, 0.40)
		Kind.KRAKEN_DEN:
			return Color(0.70, 0.50, 0.85)
		Kind.BASILISK_EYRIE:
			return Color(0.95, 0.62, 0.30)
	return Color.GRAY
