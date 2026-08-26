class_name ItemDB
extends RefCounted

## The ONE unified item-id space every Inventory speaks (v0.25.0, the make/use
## loop). Sprint 2 mining stored raw TerrainDB.Type ints as inventory keys; once
## items grow past terrain — whale products you harvest, goods you craft — they
## all have to coexist in one type->count map WITHOUT colliding. This is the seam
## the economy grows on, so the id scheme is fixed here and nowhere else.
##
## THE ID SCHEME — three disjoint numeric RANGES, so an id alone says what KIND
## of item it is and two kinds can never share a key:
##   * TERRAIN  [0, 100)   — a terrain material item's id IS its TerrainDB.Type
##     value (dirt=1 .. aetherite=7). Deliberate: mining already credits
##     TerrainDB.Type ints (world._on_terrain_dug), and the existing inventory
##     tests key on TerrainDB.Type — keeping terrain ids == TerrainDB.Type means
##     the whole mining path and its tests need no change. AIR (0) is never an item.
##   * PRODUCT  [100, 200) — whale-product items HARVESTED from a carcass
##     (blubber, meat, bone, stomach loot). Distinct block-vs-item: a BLUBBER
##     *block* (BlockDB.Type.BLUBBER) is ship structure; a Blubber *product*
##     (ItemDB.Product.BLUBBER) is what harvesting that block off a corpse yields.
##   * CRAFTED  [200, 300) — goods produced by a recipe (items/recipes.gd):
##     whale oil rendered from blubber, an ingot smelted from ore.
## Ranges are 100 apart with room to spare; TerrainDB.Type tops out at 7, so the
## terrain range will not reach PRODUCT_BASE for a very long time.
##
## Lookups (name/color) DISPATCH on the range: terrain ids delegate to TerrainDB
## (its table stays the source of truth for materials), products/crafted read the
## small table below. So the HUD and pickup floats call ItemDB.name_of(id) for
## ANY item and never branch on kind themselves.

const TERRAIN_BASE := 0
const PRODUCT_BASE := 100
const CRAFTED_BASE := 200

## Whale-product items — what harvesting a carcass yields (see Ship.harvest_cell).
## Values are explicit so they sit in the PRODUCT range regardless of order.
enum Product {
	BLUBBER = PRODUCT_BASE,  ## 100 — rendered into oil; the economy's raw material
	MEAT,                    ## 101 — food / building flesh
	BONE,                    ## 102 — reserved: no bone BLOCK exists to harvest yet
	STOMACH_LOOT,            ## 103 — the [?] drop: a carcass's swallowed cargo
}

## Crafted goods — recipe outputs (see items/recipes.gd).
enum Crafted {
	WHALE_OIL = CRAFTED_BASE,  ## 200 — refined blubber; "powers the world's machinery"
	INGOT,                     ## 201 — smelted ore; a hull-grade building material
	LIFE_SUPPORT,              ## 202 — the deep-air survival gear (player/life_support.gd):
	                           ##       carry one and the deep band's unbreathable air can't
	                           ##       suffocate you. Crafted from copper ingot + blubber.
	# The three PREBUILT balloon sizes (the owner's source model: fixed sizes with
	# fixed tether counts — Ship.BalloonSize). ONE item per size rather than one
	# item plus a size field, because the inventory is a flat id->count map: a
	# stack of "balloon" that is secretly three different things cannot be counted,
	# shown, or sold. Order MUST match Ship.BalloonSize — BALLOON_ITEMS indexes on it.
	BALLOON_SMALL,             ## 203 — 1 tether, 250 lift
	BALLOON_MEDIUM,            ## 204 — 2 tethers, 480 lift
	BALLOON_LARGE,             ## 205 — 3 tethers, 750 lift
}

## Products + crafted goods, name/color for the HUD and pickup floats. Terrain
## materials are absent on purpose — their names/colors live in TerrainDB and
## name_of/color_of delegate there for the terrain range.
const ITEMS := {
	Product.BLUBBER:      {"name": "Blubber",      "color": Color(0.86, 0.72, 0.66)},
	Product.MEAT:         {"name": "Meat",         "color": Color(0.58, 0.28, 0.26)},
	Product.BONE:         {"name": "Bone",         "color": Color(0.90, 0.88, 0.80)},
	Product.STOMACH_LOOT: {"name": "Stomach Loot", "color": Color(0.70, 0.60, 0.85)},
	Crafted.WHALE_OIL:    {"name": "Whale Oil",    "color": Color(0.30, 0.28, 0.16)},
	Crafted.INGOT:        {"name": "Copper Ingot", "color": Color(0.80, 0.52, 0.32)},
	Crafted.LIFE_SUPPORT: {"name": "Aether Lung",  "color": Color(0.55, 0.80, 0.74)},
	Crafted.BALLOON_SMALL:  {"name": "Small Balloon",  "color": Color(0.88, 0.84, 0.66)},
	Crafted.BALLOON_MEDIUM: {"name": "Medium Balloon", "color": Color(0.86, 0.78, 0.58)},
	Crafted.BALLOON_LARGE:  {"name": "Large Balloon",  "color": Color(0.84, 0.72, 0.50)},
}

## THE ITEM-COUNT BUDGET (owner scar, ORIGINAL_PLAYTEST: "49 distinct items
## after only 30 minutes. Plainly excessive"). A ceiling, not a target — the
## whole roster today is 7 mined materials (TerrainDB) + these 10, i.e. ~17
## obtainable ids, and it stays deliberately lean. This is the wall future
## features (recruitment, the economy, the opening) may not silently push
## through: `_test_item_roster_stays_within_budget` fails if the count crosses
## it. Raising the wall is a deliberate owner decision logged in DECISIONS, not
## a side effect of adding an id.
##
## The rule an id must pass to earn a slot (all three): it has a distinct USE (a
## recipe input, a placeable, or a consumable) — not flavour; it cannot fold
## into an existing id as a quantity or tier; and it earns a name, a colour and
## a place in the economy. This is already the de-facto rule the code cites
## ("no new item ids" — SpawnSites.nest_cache); the budget makes it enforceable.
const ITEM_BUDGET := 24


## How many DISTINCT ids can ever sit in a player's inventory: the mined terrain
## materials (solid TerrainDB types) plus every product/crafted good. The number
## the budget guards.
static func obtainable_item_count() -> int:
	var n := ITEMS.size()
	for t in TerrainDB.Type.values():
		if TerrainDB.is_solid(t):
			n += 1
	return n


## Balloon SIZE (Ship.BalloonSize) -> the crafted item you spend to tether one.
## The single place that mapping lives, so the recipe table, the attach verb, the
## HUD cue and the tests cannot drift apart.
const BALLOON_ITEMS := [
	Crafted.BALLOON_SMALL, Crafted.BALLOON_MEDIUM, Crafted.BALLOON_LARGE,
]


## The crafted item spent to tether a balloon of `size` (Ship.BalloonSize). An
## out-of-range size CLAMPS rather than crashing — a bad size is a caller bug,
## not a reason to take the frame down.
static func balloon_item_for(size: int) -> int:
	return BALLOON_ITEMS[clampi(size, 0, BALLOON_ITEMS.size() - 1)]


## The balloon SIZE `id` stands for, or -1 when it is not a balloon item at all.
## The inverse of balloon_item_for.
static func balloon_size_of(id: int) -> int:
	return BALLOON_ITEMS.find(id)


## Is `id` a terrain-material item? (The [0,100) range.) AIR (0) is not a real
## item, but the range test stays honest — callers screen AIR separately where it
## matters (placement uses is_placeable_terrain).
static func is_terrain(id: int) -> bool:
	return id >= TERRAIN_BASE and id < PRODUCT_BASE


## Is `id` a whale-product item? (The [100,200) range.)
static func is_product(id: int) -> bool:
	return id >= PRODUCT_BASE and id < CRAFTED_BASE


## Is `id` a crafted good? (The [200,300) range.)
static func is_crafted(id: int) -> bool:
	return id >= CRAFTED_BASE and id < CRAFTED_BASE + 100


## Can this item be PLACED into the terrain grid (world placement)? Only real
## terrain materials — a solid TerrainDB type, never AIR, never a product/craft.
static func is_placeable_terrain(id: int) -> bool:
	return is_terrain(id) and TerrainDB.is_solid(id)


## The whale-product ITEM id a flesh BLOCK yields when harvested off a carcass,
## or -1 if the block is not harvestable flesh. The one place block-type ->
## product-item is decided (Ship.harvest_cell reads it). Bone is intentionally
## absent: no bone block exists to harvest (STATE/BACKLOG).
static func whale_product_for(block_type: int) -> int:
	match block_type:
		BlockDB.Type.BLUBBER:
			return Product.BLUBBER
		BlockDB.Type.MEAT:
			return Product.MEAT
	return -1


## Display name for ANY item id — terrain, product or crafted. Dispatches on the
## range so callers never branch on kind.
static func name_of(id: int) -> String:
	if is_terrain(id):
		return TerrainDB.get_def(id)["name"]
	return ITEMS.get(id, {"name": "Item %d" % id})["name"]


## Display color for ANY item id (same dispatch as name_of).
static func color_of(id: int) -> Color:
	if is_terrain(id):
		return TerrainDB.color_of(id)
	return ITEMS.get(id, {"color": Color.MAGENTA})["color"]
