class_name EasterEggs
extends RefCounted

## Hidden, discoverable easter eggs (owner 2026-08-22: "I expect some easter eggs
## somewhere!"). CLEAN-ROOM — original, playful, ours; no copyrighted names,
## quotes or characters. Kept genuinely HIDDEN: none is ever surfaced in the HUD.
## What each one is and how to find it lives in docs/DECISIONS.md (dev-facing) so
## we don't lose them — the code here is the source of truth for WHERE they are.
##
## 1. THE CAIRN — a secret aetherite beacon at a fixed, hidden world coordinate,
##    deep and far to port, well outside the spawn neighbourhood and the ordinary
##    flight lanes. A deliberate plus/cross shape of exotic crystal so a wanderer
##    who stumbles on it knows it was placed, not grown. Planted AFTER normal
##    generation, so it exists at CAIRN_CELL in every world regardless of seed.
##    Find it: fly deep (down) and far to the left edge, then mine the beacon.
## 2. THE PALE WANDERER — a rare ghost-whale variant. A deterministic 1-in-N roll
##    off the world seed; when it hits, the spawned whale wears a ghostly tint.
##    Most worlds carry an ordinary whale; a lucky seed carries the ghost. It
##    behaves exactly like any whale (no balance change) — only its skin differs.
##    Find it: reroll world_seed until a pale whale drifts in off the port bow.
## 3. THE OLD SALUTE — a Konami-style key sequence (up up down down left right
##    left right B A) that pops a harmless burst of celebratory floats over the
##    player. Purely fun; touches nothing about play, balance or the inventory.
## 4. THE DEEP SOVEREIGN — a rare ghost KRAKEN, the deep's answer to the Pale
##    Wanderer. A deterministic 1-in-N roll off the world seed; when it hits, the
##    first kraken of the pod wears a regal violet cast. Pure cosmetic, no balance
##    change. Find it: reroll world_seed and dive deep until a violet kraken looms.
## 5. THE HIGH CAIRN — a SECOND hidden beacon that BOOKENDS the Cairn: where the
##    Cairn is deep and far to PORT (aetherite), this one is high and far to
##    STARBOARD, built of COPPER (the top-band metal). A wanderer who finds both
##    learns the world is deliberately framed corner to corner. Planted after
##    generation like the Cairn, so it is in every world regardless of seed.

# --- 1. The Cairn ----------------------------------------------------------

## Where the Cairn sits, in TERRAIN CELL coordinates (scale-agnostic like all
## terrain). Deep band (positive y is down) and far to port, but clear of the
## left downdraft wind column and far outside the spawn keep-out — and outside
## every island-generation test window, so it disturbs nothing. Fixed so it can
## be pinned by test and found again.
const CAIRN_CELL := Vector2i(-1360, 980)


## Carve the Cairn into a generated terrain: a solid aetherite core with four arms
## making a plus/beacon. Always present so the egg can't silently vanish. Just
## writes cells (idempotent enough to re-run). Called once after IslandGen.generate.
## Scales with the terrain's SUBDIV — CAIRN_CELL is a coarse-cell coordinate, so
## everything multiplies by `sub` and the beacon keeps its exact pixel position
## and size at any terrain resolution (and `cairn_cell_for(terrain)` is still
## solid, which the startup pin asserts).
static func plant_cairn(terrain: Terrain) -> void:
	var sub := maxi(terrain.subdiv, 1)
	var c := CAIRN_CELL * sub
	# A solid 5×5 (coarse) aetherite core.
	terrain.fill_rect(Rect2i(c - Vector2i(2, 2) * sub, Vector2i(5, 5) * sub),
		TerrainDB.Type.AETHERITE)
	# Four arms — the plus/beacon that reads as deliberate, not natural terrain.
	# Each arm is a coarse-cell-thick bar from radius 3 to 5 (coarse).
	terrain.fill_rect(Rect2i(c + Vector2i(3 * sub, 0), Vector2i(3 * sub, sub)),
		TerrainDB.Type.AETHERITE)
	terrain.fill_rect(Rect2i(c + Vector2i(-5 * sub, 0), Vector2i(3 * sub, sub)),
		TerrainDB.Type.AETHERITE)
	terrain.fill_rect(Rect2i(c + Vector2i(0, 3 * sub), Vector2i(sub, 3 * sub)),
		TerrainDB.Type.AETHERITE)
	terrain.fill_rect(Rect2i(c + Vector2i(0, -5 * sub), Vector2i(sub, 3 * sub)),
		TerrainDB.Type.AETHERITE)


## The Cairn's anchor cell in THIS terrain's (possibly subdivided) grid — the
## cell tests and tools should probe. CAIRN_CELL itself is the coarse coordinate.
static func cairn_cell_for(terrain: Terrain) -> Vector2i:
	return CAIRN_CELL * maxi(terrain.subdiv, 1)


# --- 5. The High Cairn (a bookend beacon, far starboard and high) ----------

## The High Cairn's coarse-cell coordinate — the MIRROR of the Cairn: high (up
## is negative y) and far to STARBOARD (+x), the opposite corner. Inside the
## (halved 2026-08-26) world, clear of the spawn keep-out and every island-gen
## test window, so it disturbs nothing. Built of COPPER, not aetherite, so the
## two beacons read as a deliberate deep/high, port/starboard pair.
const HIGH_CAIRN_CELL := Vector2i(1360, -980)


## Carve the High Cairn: a copper plus/beacon, the same shape and size as the
## Cairn so a finder recognises the kinship, at the mirrored corner. Idempotent;
## called once after IslandGen.generate, right beside plant_cairn.
static func plant_high_cairn(terrain: Terrain) -> void:
	var sub := maxi(terrain.subdiv, 1)
	var c := HIGH_CAIRN_CELL * sub
	terrain.fill_rect(Rect2i(c - Vector2i(2, 2) * sub, Vector2i(5, 5) * sub),
		TerrainDB.Type.COPPER)
	terrain.fill_rect(Rect2i(c + Vector2i(3 * sub, 0), Vector2i(3 * sub, sub)),
		TerrainDB.Type.COPPER)
	terrain.fill_rect(Rect2i(c + Vector2i(-5 * sub, 0), Vector2i(3 * sub, sub)),
		TerrainDB.Type.COPPER)
	terrain.fill_rect(Rect2i(c + Vector2i(0, 3 * sub), Vector2i(sub, 3 * sub)),
		TerrainDB.Type.COPPER)
	terrain.fill_rect(Rect2i(c + Vector2i(0, -5 * sub), Vector2i(sub, 3 * sub)),
		TerrainDB.Type.COPPER)


## The High Cairn's anchor cell in THIS terrain's grid.
static func high_cairn_cell_for(terrain: Terrain) -> Vector2i:
	return HIGH_CAIRN_CELL * maxi(terrain.subdiv, 1)


# --- 2. The Pale Wanderer (rare ghost whale) -------------------------------

## Odds the world's whale is the ghost: 1 in this many seeds. Deterministic per
## seed so a world always agrees with itself; rare enough to be a surprise.
const GHOST_WHALE_ODDS := 7
## The residue (0..ODDS-1) that rolls the ghost — arbitrary, fixed. posmod keeps
## it correct for negative seeds.
const GHOST_WHALE_RESIDUE := 3
const GHOST_WHALE_NAME := "the Pale Wanderer"
## A ghostly, cold tint multiplied over the whale's natural colours (Ship.body_tint).
const GHOST_WHALE_TINT := Color(0.70, 0.82, 0.98)


## Is this world's whale the rare ghost? A pure, deterministic function of the
## seed — a seed always agrees with itself, and a test can pin a known ghost seed.
static func is_ghost_whale(world_seed: int) -> bool:
	return posmod(world_seed, GHOST_WHALE_ODDS) == GHOST_WHALE_RESIDUE


# --- 4. The Deep Sovereign (rare ghost kraken) -----------------------------

## Odds the pod's lead kraken is the Sovereign: 1 in this many seeds. A distinct
## residue from the ghost whale so the two eggs are independent — a seed can
## carry both, neither, or one. Deterministic per seed (a world agrees with
## itself; a test pins a known seed).
const SOVEREIGN_KRAKEN_ODDS := 11
const SOVEREIGN_KRAKEN_RESIDUE := 6
const SOVEREIGN_KRAKEN_NAME := "the Deep Sovereign"
## A regal deep-violet cast multiplied over the kraken's natural colours.
const SOVEREIGN_KRAKEN_TINT := Color(0.62, 0.52, 0.86)


## Is this world's lead kraken the rare Sovereign? Pure and deterministic — the
## deep's twin of is_ghost_whale.
static func is_sovereign_kraken(world_seed: int) -> bool:
	return posmod(world_seed, SOVEREIGN_KRAKEN_ODDS) == SOVEREIGN_KRAKEN_RESIDUE


# --- 3. The Old Salute (Konami-style input) --------------------------------

## The sequence, as physical keycodes. Observed passively (never consumed), so
## the keys keep doing their normal jobs while the salute watches for the pattern.
const KONAMI: Array = [
	KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN,
	KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT,
	KEY_B, KEY_A,
]


## Does the tail of `recent` (a rolling list of recently pressed keycodes) match
## the salute? Pure — the world keeps the rolling buffer and calls this. A match
## needs at least KONAMI.size() keys, the last of which end in the sequence.
static func konami_matches(recent: Array) -> bool:
	if recent.size() < KONAMI.size():
		return false
	var offset := recent.size() - KONAMI.size()
	for i in KONAMI.size():
		if int(recent[offset + i]) != int(KONAMI[i]):
			return false
	return true
