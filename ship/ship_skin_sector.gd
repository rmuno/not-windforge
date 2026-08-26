class_name ShipSkinSector
extends Node2D

## One 64x64-cell tile of a Ship's drawn skin (the lag audit's phase B,
## 2026-08-25). The whole body used to be ONE CanvasItem, so any redraw --
## a damage shade crossing, a placed block, a harvested cell -- re-batched
## every cell it owned: 38-53 ms on a creature, ~1.1 s on the 194k-cell
## starter. Each sector paints only its own cell range, and an edit
## invalidates only its sector, so the per-edit draw cost is bounded by the
## sector area, never the body.
##
## Sits at the parent Ship's origin (position ZERO), so its local space IS
## the ship's -- the paint code (Ship._paint_sector) is the very code the
## whole-body _draw ran, filtered to the range. Draw calls are not clipped
## to a canvas item, so region rects that touch the sector edge draw
## complete; each cell belongs to exactly one sector, so nothing paints
## twice.

var ship: Ship = null
var sector := Vector2i.ZERO

## Diagnostics. `paints` counts real repaints (only meaningful with a live
## renderer); `invalidations` counts queue_redraw requests, which IS
## observable headless -- the phase-B tests pin "one edit, one sector" on it.
var paints := 0
var invalidations := 0


func invalidate() -> void:
	invalidations += 1
	queue_redraw()


func _draw() -> void:
	if ship == null or not is_instance_valid(ship):
		return
	paints += 1
	ship._paint_sector(self, sector)
