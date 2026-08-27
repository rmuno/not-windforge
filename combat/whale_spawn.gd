class_name WhaleSpawn
extends RefCounted

## The pod picker (Sprint 4, whale-variant spawning). The design jam
## (2026-08-20) produced five authored body plans, all suite-gated by
## `_check_whale_body_plan`; today the world only ever spawned
## `whale.ship`. This turns the sky's whales into a VARIED pod: a weighted
## pick over the five plans, so a few whales roaming read as different
## creatures, not clones.
##
## Weighting follows the ROADMAP (Phase 4): "three common, one semi-rare,
## one very rare". The reference blue and the bull/humpback are the
## everyday whales; the sleek is a semi-rare; the leviathan is the rare
## giant (its 1.6× mass makes its ram superlinearly harder — a per-variant
## charge-accel tune is a documented seam, kept rare so a one-in-a-pod
## leviathan cannot routinely one-shot a starter — see DECISIONS/BACKLOG).
##
## Cosmetic-only per-variant TINTS give the pod visible variety beyond
## silhouette (Ship.body_tint is documented cosmetic — never mass/collision/
## damage). The ghost-whale easter egg (a rare pale tint) still overrides
## these when its seed rolls (maps/world/easter_eggs.gd → the Pale Wanderer).
##
## Pure logic (a RefCounted, no tree, RNG passed in), so the whole pick is
## unit-testable without booting the world (see run_tests).

## One entry per authored body plan: its .ship path, spawn weight, and a
## cosmetic body tint. Weights need not sum to anything — pick_plan
## normalises against their total.
const PLANS := [
	{"path": "res://ships/whale.ship",           "weight": 10, "tint": Color(0.82, 0.86, 0.95)},  # reference blue — common
	{"path": "res://ships/whale_bull.ship",      "weight": 8,  "tint": Color(0.90, 0.84, 0.74)},  # tan bull — common
	{"path": "res://ships/whale_humpback.ship",  "weight": 8,  "tint": Color(0.78, 0.82, 0.80)},  # grey humpback — common
	{"path": "res://ships/whale_sleek.ship",     "weight": 4,  "tint": Color(0.74, 0.80, 0.90)},  # steel sleek — semi-rare
	{"path": "res://ships/whale_leviathan.ship", "weight": 1,  "tint": Color(0.86, 0.74, 0.78)},  # pale-red leviathan — very rare
	# Design jam #2 (2026-08-26): three new silhouettes to widen the pod.
	{"path": "res://ships/whale_bowhead.ship",   "weight": 5,  "tint": Color(0.55, 0.60, 0.66)},  # slate bowhead TANK — fat/deep, semi-common
	{"path": "res://ships/whale_manta.ship",     "weight": 3,  "tint": Color(0.52, 0.62, 0.72)},  # manta WING-glider — tall diamond, semi-rare
	{"path": "res://ships/whale_narwhal.ship",   "weight": 3,  "tint": Color(0.70, 0.76, 0.84)},  # tusked NARWHAL — pale steel, semi-rare
]


## Weighted pick over PLANS, returning the chosen plan's .ship path. `rng`
## is passed in so the caller owns determinism (a fixed seed → a fixed pod,
## exactly like the world seed picks a fixed island field).
static func pick_plan(rng: RandomNumberGenerator) -> String:
	var total := 0
	for p in PLANS:
		total += int(p["weight"])
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for p in PLANS:
		acc += int(p["weight"])
		if roll < acc:
			return String(p["path"])
	return String(PLANS[0]["path"])  # unreachable; a total>0 guard for safety


## The cosmetic tint for a body plan (white if the path is unknown). The
## world multiplies this over the whale's block colours, unless the ghost
## roll overrides it.
static func tint_for(path: String) -> Color:
	for p in PLANS:
		if String(p["path"]) == path:
			return p["tint"]
	return Color.WHITE


# --- Deep-spawn keep-out (2026-08-24) --------------------------------------
#
# Krakens spawn DEEP, and the deep is exactly where the island field is thickest,
# so a computed spawn point can land INSIDE an island: a 12,000-hp body wedged in
# rock, grinding on the collider from frame one. The player/ship spawn already had
# a ±220-cell keep-out; creatures never did.
#
# The fix probes the body's would-be FOOTPRINT against the terrain and, if it is
# in rock, walks a FIXED table of offsets until one is clear. Deliberately no
# RandomNumberGenerator: the scatter must be a pure function of the blocked
# position, or the same world seed would stop reproducing the same world.
#
# Pure statics (terrain + geometry in, a position out), so the whole keep-out is
# unit-testable without booting the world — as with pick_plan above.

## Unscaled px a try steps out, ×world_scale. Try `i` steps (i+1) of these in the
## next cardinal direction, so eight tries sweep out to ~8 steps around the blocked
## point — enough to clear a deep island — and the try ORDER is fixed forever.
const SCATTER_STEP := 400.0
const SCATTER_TRIES := 8
## Right/up first: deep bodies are wider than they are tall, so sideways is the
## cheapest way out, and up is the way OFF an island rather than deeper into it.
const SCATTER_DIRS := [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]


## The body-local px AABB a cells dict occupies — the footprint the keep-out
## probes. Matches Ship.local_pos_of (cell × CELL) and counts the far cell's own
## width, so the rect covers the whole block rather than just its corner.
static func footprint_of(cells: Dictionary) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in cells:
		var c: Vector2i = cell
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2(Vector2(lo) * Ship.CELL, Vector2(hi - lo + Vector2i.ONE) * Ship.CELL)


## Is the footprint, placed at `pos`, in solid terrain? Samples the four CORNERS
## plus the CENTRE — five cells, not the thousands the body covers, because this
## runs once at spawn and only needs to catch "embedded in an island", not shave a
## body past an overhang. No terrain (a bare test scene, a world still building)
## means there is nothing to be blocked by.
static func footprint_blocked(terrain: Terrain, pos: Vector2, foot: Rect2) -> bool:
	if terrain == null or not is_instance_valid(terrain) \
			or foot.size.x <= 0.0 or foot.size.y <= 0.0:
		return false
	var r := Rect2(pos + foot.position, foot.size)
	for p in [r.position, r.position + Vector2(r.size.x, 0.0),
			r.position + Vector2(0.0, r.size.y), r.end, r.get_center()]:
		if terrain.is_solid(terrain.world_to_cell(p)):
			return true
	return false


## `pos` if the footprint is clear there; otherwise the first scattered position
## that IS clear. Falls back to `pos` when every try is blocked — better a bad
## spawn than a missing kraken, and the caller cannot tell the two apart (both are
## simply "where it went").
static func clear_spawn_pos(terrain: Terrain, pos: Vector2, foot: Rect2,
		scale: float) -> Vector2:
	if not footprint_blocked(terrain, pos, foot):
		return pos
	for i in SCATTER_TRIES:
		var dir: Vector2 = SCATTER_DIRS[i % SCATTER_DIRS.size()]
		var candidate := pos + dir * SCATTER_STEP * scale * float(i + 1)
		if not footprint_blocked(terrain, candidate, foot):
			return candidate
	return pos
