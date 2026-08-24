class_name Economy
extends RefCounted

## The salvage economy: what the stuff you carry is worth in money (Sprint 5).
## Salvage IS the loot system (WIKI_REFERENCE → the dismantle tool): you mine
## terrain, harvest whale corpses, craft goods — then sell the lot at a trainer
## for money to buy stat levels. This is the one place item -> value is decided,
## a small data table (like `Recipes`), so the whole economy tunes here.
##
## Every id is an `ItemDB` id (terrain / product / crafted), so one Inventory
## sells in one pass without branching on kind. Values are grounded in the
## original's item screen where we have it (WIKI_REFERENCE whale-product tooltips:
## blubber sells ~7, meat ~3, whale oil ~50 — refining is where the value is) and
## sit sensibly against the terrain materials otherwise (exotic aetherite is the
## prize; dirt is nearly worthless).

## item id -> sell value in money. Absent == worthless (0), sold for nothing and
## left in the pack.
const VALUES := {
	# Terrain materials (mined) — common cheap, exotic dear.
	TerrainDB.Type.DIRT: 1,
	TerrainDB.Type.STONE: 2,
	TerrainDB.Type.PUMICE: 2,
	TerrainDB.Type.ORE: 8,
	TerrainDB.Type.COPPER: 10,
	TerrainDB.Type.OBSIDIAN: 12,
	TerrainDB.Type.AETHERITE: 40,
	# Whale products (harvested) — the wiki's sell prices.
	ItemDB.Product.BLUBBER: 7,
	ItemDB.Product.MEAT: 3,
	ItemDB.Product.BONE: 5,
	ItemDB.Product.STOMACH_LOOT: 25,
	# Crafted goods — refining adds value (oil is 8x blubber in the source).
	ItemDB.Crafted.WHALE_OIL: 50,
	ItemDB.Crafted.INGOT: 20,
}


## What one `id` sells for (0 if worthless / unknown).
static func sell_value(id: int) -> int:
	return int(VALUES.get(id, 0))


## What selling everything sellable in `inv` would yield right now, at the given
## trade bonus (LORE) — the "+$N" the shop shows before you commit. Does NOT
## mutate the inventory. `trade_bonus` 0.25 == +25%; floored to a whole coin.
static func appraise(inv: Inventory, trade_bonus := 0.0) -> int:
	if inv == null:
		return 0
	var total := 0
	for id in inv.types():
		total += sell_value(id) * inv.count(id)
	return int(floor(float(total) * (1.0 + maxf(0.0, trade_bonus))))


## Sell every sellable item in `inv`: remove the ones with value, return the money
## earned (trade bonus applied). Worthless items (value 0) are LEFT in the pack —
## you keep what nobody will buy. Returns 0 and changes nothing on an empty or
## all-worthless inventory.
static func sell_all(inv: Inventory, trade_bonus := 0.0) -> int:
	if inv == null:
		return 0
	var raw := 0
	# Snapshot the types first — removing mutates the map we would be iterating.
	for id in inv.types():
		var value := sell_value(id)
		if value <= 0:
			continue
		raw += value * inv.count(id)
		inv.remove(id, inv.count(id))
	return int(floor(float(raw) * (1.0 + maxf(0.0, trade_bonus))))
