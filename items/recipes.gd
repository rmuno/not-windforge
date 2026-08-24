class_name Recipes
extends RefCounted

## The minimal, data-driven crafting seam (v0.25.0, the make/use loop). A recipe
## is data — inputs consumed and one output produced — and craft() is the whole
## engine: check inputs, consume, yield. This is the seam the economy grows on,
## kept deliberately SMALL (owner's "crafting without repetition" charter,
## BACKLOG): a couple of clean paths grounded in the wiki, NOT a recipe tree.
##
## Every id is an ItemDB id, so terrain materials, whale products and crafted
## goods compose in one Inventory without collision (see items/item_db.gd).
##
## Grounded in WIKI_REFERENCE (whale-product tooltips):
##   * Whale Oil is "created by refining whale blubber" and sells for 8× blubber
##     — refining is where the value is. So blubber PRODUCT -> whale oil.
##   * Copper ore -> a Copper Ingot: raw ore into a hull-grade building material,
##     the make step between mining and building.

## Each recipe: {name, inputs {item_id -> count}, output item_id, count}.
## APPEND new recipes; the craft UI cycles this array by index.
const RECIPES := [
	{
		"name": "Render Whale Oil",
		"inputs": {ItemDB.Product.BLUBBER: 2},
		"output": ItemDB.Crafted.WHALE_OIL,
		"count": 1,
	},
	{
		"name": "Smelt Copper Ingot",
		"inputs": {TerrainDB.Type.COPPER: 3},
		"output": ItemDB.Crafted.INGOT,
		"count": 1,
	},
	{
		# The deep-air survival gate (player/life_support.gd). A steampunk mask +
		# bladder: copper fittings (an ingot) around a blubber-sealed air store.
		# Both inputs are gathered in the BREATHABLE bands — copper is the top-band
		# ore, blubber comes off whales that roam mid/top — so you assemble the
		# Lung up high, then descend. That is the gate on the deep's exotic prize
		# (aetherite is the deep-band pocket): no life-support, no deep mining.
		"name": "Assemble Aether Lung",
		"inputs": {ItemDB.Crafted.INGOT: 2, ItemDB.Product.BLUBBER: 3},
		"output": ItemDB.Crafted.LIFE_SUPPORT,
		"count": 1,
	},
]


## Does `inv` hold every input `recipe` needs?
static func can_craft(inv: Inventory, recipe: Dictionary) -> bool:
	if inv == null:
		return false
	for id in recipe["inputs"]:
		if inv.count(id) < int(recipe["inputs"][id]):
			return false
	return true


## Craft `recipe` against `inv`: if every input is present, consume the inputs and
## add the output, returning true. If ANY input is missing, nothing is consumed
## and the inventory is left exactly as it was (returns false). The consume-then-
## produce order is safe because can_craft has already proven the whole cost is
## affordable, so no partial spend can happen.
static func craft(inv: Inventory, recipe: Dictionary) -> bool:
	if not can_craft(inv, recipe):
		return false
	for id in recipe["inputs"]:
		inv.remove(id, int(recipe["inputs"][id]))
	inv.add(int(recipe["output"]), int(recipe.get("count", 1)))
	return true


## A short "2 Blubber -> 1 Whale Oil" line for the craft HUD, using ItemDB names.
static func summary(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for id in recipe["inputs"]:
		parts.append("%d %s" % [int(recipe["inputs"][id]), ItemDB.name_of(id)])
	return "%s  (%s -> %d %s)" % [
		recipe["name"],
		" + ".join(parts),
		int(recipe.get("count", 1)),
		ItemDB.name_of(int(recipe["output"])),
	]
