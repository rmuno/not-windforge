class_name TerrainDB
extends RefCounted

## Terrain block table — deliberately SEPARATE from BlockDB (Sprint 2, terrain
## foundation).
##
## Terrain cells are typed in a grid exactly like ship blocks (grid-as-truth),
## but they are their own domain and must stay that way:
##   * terrain never rides a ship's wire/save payload, so its type ints are
##     free to evolve without disturbing the ship block enum that DOES ride the
##     format (BlockDB.Type — "appended, never reordered");
##   * terrain carries no mass, lift, power, thrust or severing — none of the
##     ship-block columns apply. Folding dirt/stone/ore into BlockDB would drag
##     all of that machinery across the seam for no gain.
## So terrain gets a small dedicated table. `dig()` returns one of these Type
## ints, which is the ONLY hook the mining chunk needs to turn a removed cell
## into an inventory item.

## Cell granularity in px, matching Ship.CELL so terrain and ships share one
## world grid. Pixel size on screen is CELL × world_scale (read from the world,
## like Ship.scale_unit) — the type table itself is scale-agnostic.
const CELL := 16.0

## Types are APPENDED, never reordered (AIR must stay 0 — an unset chunk byte is
## air). Terrain ints do NOT ride any ship wire/save format (TerrainDB is its own
## domain), so the enum is free to grow; the ordering here is only convenience.
## The banded island generator (terrain/island_gen.gd) picks BODY / CAP / POCKET
## materials per altitude band via `band_materials()` below — common/lighter
## materials up high, exotic/valuable ore deep (WORLD_SPEC + owner survey).
enum Type {
	AIR,        ## 0 — MUST stay 0: an unset byte in a chunk's PackedByteArray is air.
	DIRT,       ## common topsoil / island cap
	STONE,      ## common body rock (mid band)
	ORE,        ## generic ore — the mid-band pocket
	PUMICE,     ## light, soft body rock — TOP-band island bodies (lighter up high)
	COPPER,     ## common ore — the TOP-band pocket
	OBSIDIAN,   ## dark dense body rock — DEEP-band island bodies
	AETHERITE,  ## exotic crystal — the DEEP-band (and rare gap-island) pocket, the prize
}

## color — the flat placeholder rect colour, drawn in code like ship blocks
##         (no sprites until the art pass — DECISIONS art-pass).
## hp    — damage the cell absorbs before mining breaks it; the mine seam reads
##         it as HARDNESS (dig-time = hp / MINE_POWER), so it doubles as feel:
##         soft topsoil pops, exotic crystal takes real work.
const BLOCKS := {
	Type.DIRT:      {"name": "Dirt",      "hp": 40.0,  "color": Color(0.42, 0.32, 0.22)},
	Type.STONE:     {"name": "Stone",     "hp": 120.0, "color": Color(0.36, 0.37, 0.41)},
	Type.ORE:       {"name": "Ore",       "hp": 200.0, "color": Color(0.64, 0.53, 0.30)},
	Type.PUMICE:    {"name": "Pumice",    "hp": 70.0,  "color": Color(0.70, 0.68, 0.62)},
	Type.COPPER:    {"name": "Copper",    "hp": 160.0, "color": Color(0.74, 0.46, 0.28)},
	Type.OBSIDIAN:  {"name": "Obsidian",  "hp": 240.0, "color": Color(0.15, 0.13, 0.19)},
	Type.AETHERITE: {"name": "Aetherite", "hp": 360.0, "color": Color(0.40, 0.80, 0.86)},
}

## Band → island material policy (WORLD_SPEC: better/common high, exotic deep).
## Returns {"body", "cap", "pocket"} TerrainDB types for an island generated in
## that Airspace.Band. Kept here beside the material table so the whole material
## story reads in one place; the generator just applies it. The bands come from
## Airspace.Band (altitude-fraction thirds + gaps over a lava floor).
##   TOP  — lighter pumice body, common copper pocket (rich but not exotic).
##   MID  — plain stone body, generic ore pocket (home; mixed, unremarkable).
##   DEEP — dense obsidian body, EXOTIC aetherite pocket (the prize is deep).
##   GAPS — stone body, aetherite pocket: the rare wind-route island carries the
##          exotic weighting (owner's gap-island rare-loot conjecture, kept simple).
static func band_materials(band: int) -> Dictionary:
	match band:
		Airspace.Band.TOP:
			return {"body": Type.PUMICE, "cap": Type.DIRT, "pocket": Type.COPPER}
		Airspace.Band.DEEP:
			return {"body": Type.OBSIDIAN, "cap": Type.STONE, "pocket": Type.AETHERITE}
		Airspace.Band.GAP_LOW, Airspace.Band.GAP_HIGH:
			return {"body": Type.STONE, "cap": Type.DIRT, "pocket": Type.AETHERITE}
	# MID (and any NONE/LAVA fallback — the generator never places in those).
	return {"body": Type.STONE, "cap": Type.DIRT, "pocket": Type.ORE}


static func is_solid(type: int) -> bool:
	return type != Type.AIR


static func get_def(type: int) -> Dictionary:
	return BLOCKS.get(type, BLOCKS[Type.STONE])


static func color_of(type: int) -> Color:
	return get_def(type)["color"]


static func max_hp(type: int) -> float:
	return get_def(type)["hp"]
