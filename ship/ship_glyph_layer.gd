class_name ShipGlyphLayer
extends Node2D

## The component-glyph overlay of a Ship's sectored skin (phase B): "E" on
## engines, "P(H)/P(V)" on propeller slabs, the door Ds, the turret arcs'
## letters. Glyph clusters span sector boundaries, so they draw from ONE
## top layer (kept as the Ship's last child, above every sector) instead of
## being split per sector. Clusters only change on a full rebuild, so this
## layer redraws rarely and cheaply (cluster count, not cell count).

var ship: Ship = null


func _draw() -> void:
	if ship == null or not is_instance_valid(ship):
		return
	ship._paint_glyphs(self)
