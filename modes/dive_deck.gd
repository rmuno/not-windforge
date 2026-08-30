class_name DiveDeck
extends RefCounted

## READING THE LAUNCH DECK OUT OF ITS BLUEPRINT (owner 2026-08-30: "you can just
## plan it out with ascii characters like we've done with the ship builder").
##
## `ships/dive_deck.ship` is the ground a run starts on, and it is an ordinary
## `.ship` file the owner edits by hand: runs of `-` are platform you stand on,
## runs of `.` are BERTHS with a hull moored under each. This class is the one
## piece of logic that connects the two — it finds the gaps and hands back where
## their middles are.
##
## Static and pure, so the suite can check a layout without spawning anything.
## That matters more here than usual: the deck's geometry has been wrong four
## times, twice because a number was scaled and once because it was not, and
## every one of those was invisible until somebody walked it. Arithmetic on the
## authored file catches the same mistakes in a millisecond.

## The narrowest run of empty columns that counts as a berth rather than as a
## hole somebody left in the floor, in CELLS of the authored blueprint.
const MIN_BERTH_CELLS := 8


## Which columns of `cells` hold anything. Returns {col: true}.
static func occupied_columns(cells: Dictionary) -> Dictionary:
	var out := {}
	for cell in cells:
		out[(cell as Vector2i).x] = true
	return out


## The berths in a deck layout, as [{centre_cell, width_cells}] in left-to-right
## order. A berth is a run of empty columns BETWEEN two pieces of platform —
## the open air off either END of the deck is not a berth, it is the edge you
## walk off to dive with nothing.
static func berths(cells: Dictionary) -> Array:
	var out: Array = []
	if cells.is_empty():
		return out
	var held := occupied_columns(cells)
	var lo := 1 << 30
	var hi := -(1 << 30)
	for c in held:
		lo = mini(lo, int(c))
		hi = maxi(hi, int(c))
	# `in_run` is a BOOL and not a negative sentinel on `run_start`, because a
	# deck's columns are routinely negative — `origin` in the blueprint puts cell
	# (0,0) wherever the author wants it, and the shipped deck starts at column
	# −61. A `run_start < 0` sentinel silently swallowed every berth left of the
	# origin, which is half of them.
	var in_run := false
	var run_start := 0
	for c in range(lo, hi + 1):
		if held.has(c):
			if in_run:
				var w := c - run_start
				if w >= MIN_BERTH_CELLS:
					out.append({"centre_cell": float(run_start) + float(w) * 0.5 - 0.5,
						"width_cells": w})
				in_run = false
		elif not in_run:
			in_run = true
			run_start = c
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
## to rise out of it without catching a platform corner?
static func fits(hull_width: float, berth_width: float) -> bool:
	return hull_width > 0.0 and berth_width >= hull_width * 1.05
