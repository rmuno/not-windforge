class_name DiveDeck
extends RefCounted

## READING THE LAUNCH DECK OUT OF ITS BLUEPRINT (owner 2026-08-30: "you can just
## plan it out with ascii characters like we've done with the ship builder").
##
## `ships/dive_deck.ship` is the ground a run starts on, and it is an ordinary
## `.ship` file the owner edits by hand. The owner drew the layout it has now
## (2026-08-30): a CONTINUOUS SOLID WALKWAY of hull with DROP-THROUGH PLATFORM
## sections over each moored ship — *"which would allow for ships to be a block
## or two BELOW the platforms so they're easy to reach and you can just keep
## walking to the ship you want... and also the platforms can be as wide as
## whatever ship is right under it plus a small buffer of 2 blocks."*
##
## So a BERTH IS A RUN OF PLATFORM, not a run of empty. That is the inversion of
## the previous deck, where `-` was the walkway and the gaps between were the
## berths: choosing a ship used to be a jump across a hole and is now S+jump
## through the hatch you are standing on.
##
## Static and pure, so the suite can check a layout without spawning anything.
## That matters more here than usual: the deck's geometry has been wrong five
## times, twice because a number was scaled and once because it was not, and
## every one of those was invisible until somebody walked it. Arithmetic on the
## authored file catches the same mistakes in a millisecond.

## The narrowest run of platform columns that counts as a berth rather than as a
## hatch somebody put in the floor, in CELLS of the authored blueprint.
const MIN_BERTH_CELLS := 8

## How much wider than its hull a berth must be, in authored cells — the owner's
## "small buffer of 2 blocks". It is CLEARANCE FOR THE CLIMB OUT: a candidate
## rises straight up through its platform (one-way strips are collision layer 3
## and a ship masks layer 1, so the platform is not there as far as the hull is
## concerned), but the WALKWAY either side of it is solid hull on a real body,
## and a hull wider than its hatch would climb into it.
const BERTH_BUFFER_CELLS := 2.0


## Which columns of `cells` hold anything at all — the deck's full extent.
static func occupied_columns(cells: Dictionary) -> Dictionary:
	var out := {}
	for cell in cells:
		out[(cell as Vector2i).x] = true
	return out


## Which columns of `cells` are DROP-THROUGH — a column counts if any row in it
## is a platform. The shipped deck only ever puts platform on the top row (a
## hatch is one surface per storey, not a stack of planks — see
## `ShipLayout.upscale_cells`), but a hand-edited deck may not, and a column with
## a hatch anywhere in it is a column you can fall down.
static func platform_columns(cells: Dictionary) -> Dictionary:
	var out := {}
	for cell in cells:
		if int(cells[cell]) == BlockDB.Type.PLATFORM:
			out[(cell as Vector2i).x] = true
	return out


## The berths in a deck layout, as [{centre_cell, width_cells}] in left-to-right
## order. A berth is a run of PLATFORM columns — the hatch you drop through, with
## a hull moored under it. The open air off either END of the deck is not a
## berth, it is the edge you walk off to dive with nothing, and it never can be:
## it has no platform in it.
static func berths(cells: Dictionary) -> Array:
	var out: Array = []
	if cells.is_empty():
		return out
	var hatch := platform_columns(cells)
	var lo := 1 << 30
	var hi := -(1 << 30)
	for c in hatch:
		lo = mini(lo, int(c))
		hi = maxi(hi, int(c))
	if lo > hi:
		return out
	# `in_run` is a BOOL and not a negative sentinel on `run_start`, because a
	# deck's columns are routinely negative — `origin` in the blueprint puts cell
	# (0,0) wherever the author wants it, and the shipped deck starts at column
	# −56. A `run_start < 0` sentinel silently swallowed every berth left of the
	# origin, which is half of them.
	var in_run := false
	var run_start := 0
	for c in range(lo, hi + 2):
		if hatch.has(c):
			if not in_run:
				in_run = true
				run_start = c
		elif in_run:
			var w := c - run_start
			if w >= MIN_BERTH_CELLS:
				out.append({"centre_cell": float(run_start) + float(w) * 0.5 - 0.5,
					"width_cells": w})
			in_run = false
	return out


## Where the berths are in the DECK'S OWN frame, in px. `cell_px` is what one
## authored cell measures once the layout has been upscaled — `Ship.CELL` times
## the world scale — because a `.ship` is authored at 1× and the world builds it
## by multiplying the cell COUNT (see `ShipLayout.upscale_cells`).
static func berth_offsets(cells: Dictionary, cell_px: float) -> Array:
	var out: Array = []
	for b in berths(cells):
		var d := b as Dictionary
		out.append({
			"x": float(d["centre_cell"]) * cell_px,
			"width": float(d["width_cells"]) * cell_px,
		})
	return out


## Does `hull_width` px of ship fit in a berth `berth_width` px wide, with room
## to rise out of it without catching the walkway either side? `cell_px` is what
## one authored cell measures in the world, so the owner's buffer is expressed in
## the units they drew it in — blocks — rather than as a percentage that means
## something different for a 22-cell hull and a 96-cell one.
static func fits(hull_width: float, berth_width: float, cell_px: float) -> bool:
	if hull_width <= 0.0 or cell_px <= 0.0:
		return false
	return berth_width >= hull_width + BERTH_BUFFER_CELLS * cell_px
