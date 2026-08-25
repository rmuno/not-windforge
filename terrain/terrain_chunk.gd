class_name TerrainChunk
extends StaticBody2D

## One PROMOTED chunk: the live colliders + rendering for a fixed block of
## terrain cells. It is a pure VIEW derived from Terrain's resident data —
## demote frees it and the data outlives it untouched. Terrain is STATIC
## (StaticBody2D, collision layer 1, per DECISIONS: ships and terrain share
## layer 1, characters mask it on layer 2); it never flies, severs or carries
## power.
##
## Colliders are GREEDY-MERGED with the SAME static helper the ship hull uses
## (Ship._greedy_rects) so a solid slab collapses to a handful of rectangles
## rather than one shape per cell. Rendering batches per type like Ship._draw:
## one filled rect per merged same-type region.

## Set by Terrain before rebuild(). The chunk reads its cells straight back out
## of the resident data through `terrain`, so there is never a second copy of
## the bytes to keep in sync — a dig updates the data and calls rebuild().
var terrain: Node2D = null
var chunk_coord := Vector2i.ZERO
var chunk_cells := 32
var cell_px := 16.0

## The greedy-merged solid coverage, in LOCAL cell space. This is the derived
## truth the tests assert against (coverage == the chunk's solid cells) and it
## is refreshed synchronously in rebuild(), so a dig's shrink is visible the
## same call — no waiting for a deferred free.
var _collider_rects: Array[Rect2i] = []
var _shapes: Array[CollisionShape2D] = []
## type -> {local Vector2i: true}, the per-type groups the batched _draw merges.
var _draw_groups := {}


func _ready() -> void:
	# Terrain shares layer 1 with ships (DECISIONS); it detects nothing itself.
	collision_layer = 1
	collision_mask = 0


## Re-derive colliders and rendering from the resident data. Cheap because it is
## CHUNK-SCOPED: at most chunk_cells² cells, greedy-merged. Called on promote and
## again whenever a cell in this chunk is dug. Runs from game logic / streaming,
## never from a physics contact callback, so freeing the old shapes immediately
## (rather than deferring) is safe — and it keeps the coverage correct the
## instant a dig re-merges (godot-quirks: don't mutate colliders inside the
## physics step; this is outside it).
## Diagnostic: how many times this chunk has rebuilt — the dirty-batch tests
## pin "many edits, ONE rebuild per flush" on it (the 2026-08-25 moving-FPS fix).
var rebuild_count := 0


func rebuild() -> void:
	rebuild_count += 1
	var solid := {}
	_draw_groups = {}
	var base := chunk_coord * chunk_cells
	for ly in chunk_cells:
		for lx in chunk_cells:
			var t: int = terrain.cell_type(base + Vector2i(lx, ly))
			if not TerrainDB.is_solid(t):
				continue
			var lc := Vector2i(lx, ly)
			solid[lc] = true
			if not _draw_groups.has(t):
				_draw_groups[t] = {}
			(_draw_groups[t] as Dictionary)[lc] = true

	# Drop the previous shapes immediately (not queue_free), so the merged
	# coverage below is the only coverage the space sees this frame.
	for cs in _shapes:
		remove_child(cs)
		cs.free()
	_shapes.clear()

	# REUSE the ship hull's greedy merge (shared static helper) rather than
	# duplicating the algorithm. It consumes the dict, so `solid` is spent here.
	_collider_rects = Ship._greedy_rects(solid)
	for r in _collider_rects:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size) * cell_px
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = (Vector2(r.position) + Vector2(r.size) * 0.5) * cell_px
		add_child(cs)
		_shapes.append(cs)

	queue_redraw()


## Solid cells this chunk's colliders cover, summed from the merged rects. The
## greedy merge is a non-overlapping partition of the solid set, so this equals
## the chunk's solid-cell count exactly — the invariant the tests pin.
func collider_cell_count() -> int:
	var n := 0
	for r in _collider_rects:
		n += r.size.x * r.size.y
	return n


func _draw() -> void:
	# Batched placeholder art, same idiom as Ship._draw: one filled rect per
	# contiguous same-type region, plus a darker border. Merges per type through
	# the very same greedy helper (duplicating the group each call because the
	# merge consumes it, and _draw runs every redraw).
	for type in _draw_groups:
		var color: Color = TerrainDB.color_of(type)
		for r in Ship._greedy_rects((_draw_groups[type] as Dictionary).duplicate()):
			var rect := Rect2(Vector2(r.position) * cell_px, Vector2(r.size) * cell_px)
			draw_rect(rect, color)
			draw_rect(rect, color.darkened(0.35), false, 1.0)
