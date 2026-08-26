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
## whole-body _draw ran, over a subset of the cells. Draw calls are not
## clipped to a canvas item, so region rects that touch the sector edge draw
## complete; each cell belongs to exactly one sector, so nothing paints
## twice.

var ship: Ship = null
var sector := Vector2i.ZERO

## The cells this tile owns — the sector's share of Ship.blocks, and the
## ONLY thing its paint iterates. The first cut scanned the 64x64 RANGE
## instead (4,096 `blocks.has` probes whatever the tile held), which made a
## whole-body repaint of a SPARSE body cost `4096 x sectors` where the old
## single-canvas pass cost `cells` -- a regression in exactly the
## creature-under-fire case, since a wound shade is whole-body. Owning the
## set makes every repaint proportional to what is actually drawn.
##
## Truth is Ship.blocks; this is a partition of it, refilled from scratch by
## Ship._sync_skin_sectors on every rebuild and patched by the two
## incremental hooks (_skin_cell_added / _skin_cell_removed) between
## rebuilds. The suite pins the union against blocks after a rebuild-free
## building session.
var cells := {}

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
	ship._paint_sector(self)
