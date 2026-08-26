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
## The regions _draw emits, merged ONCE at rebuild: [Rect2i in local cells,
## TerrainDB type]. It used to be the per-type cell GROUPS, re-merged (over a
## `duplicate()`, because the greedy merge consumes its input) on every single
## repaint — a second O(cells) pass over the same data the rebuild had just
## grouped. The groups only change when the chunk rebuilds, so the merge
## belongs there and a repaint is now pure emission.
var _draw_regions: Array = []


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
	# ONE partition serves BOTH derivations (2026-08-25). The collider used to
	# merge across TYPES — adjacent stone and dirt collapsing into a single
	# rect — which meant a second dictionary holding every solid cell AND a
	# second greedy pass over it: together about half the rebuild. Physics does
	# not care what a rect is made of, only where it is, so the per-TYPE rects
	# the renderer already needs make colliders just as well. The price on the
	# live world is 27 → 51 static shapes, which the solver will never feel
	# (they are static and never overlap); the COVERAGE is identical, because
	# each solid cell lands in exactly one type's rect — the invariant the
	# suite pins as collider_cell_count() == the chunk's solid cells.
	var groups := {}  # type -> {local Vector2i: true}, spent by the merge below
	# Read the chunk's bytes ONCE and index them directly, rather than calling
	# terrain.cell_type() per cell — that path re-derives the chunk coord with
	# two float divides and re-hashes the chunk dictionary every single time,
	# for a chunk this node already names. Measured (render_cost_probe,
	# 2026-08-25): 43% of the rebuild pass, spent rediscovering a known
	# answer.
	# Typed explicitly: `terrain` is a bare Node2D here (the chunk is a pure
	# view and must not depend on Terrain's class), so inference has nothing.
	var bytes: PackedByteArray = terrain.chunk_bytes(chunk_coord)
	# An EMPTY array means nothing solid was ever written into this chunk —
	# most of the sky. Skip the scan, but never the bookkeeping below: a chunk
	# whose last solid cell was just dug out still has colliders to drop.
	if not bytes.is_empty():
		for ly in chunk_cells:
			var row := ly * chunk_cells
			for lx in chunk_cells:
				var t: int = bytes[row + lx]
				if not TerrainDB.is_solid(t):
					continue
				if not groups.has(t):
					groups[t] = {}
				(groups[t] as Dictionary)[Vector2i(lx, ly)] = true

	# The one merge, through the shared greedy helper the ship hull uses (never
	# a second copy of the algorithm). It consumes each dict, so `groups` is
	# spent here — nothing outside this call needs the cell sets again.
	_draw_regions.clear()
	var rects: Array[Rect2i] = []
	for type in groups:
		for r in Ship._greedy_rects(groups[type] as Dictionary):
			_draw_regions.append([r, type])
			rects.append(r)
	_collider_rects = rects

	# Drop the previous shapes immediately (not queue_free), so the coverage
	# built below is the only coverage the space sees this frame.
	for cs in _shapes:
		remove_child(cs)
		cs.free()
	_shapes.clear()
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


## How many rects this chunk's repaint emits (each costs a fill AND a border
## command, both RETAINED and replayed every frame). Surfaced in the F2 Perf
## readout beside the ship totals.
func draw_region_count() -> int:
	return _draw_regions.size()


func _draw() -> void:
	# Batched placeholder art, same idiom as the ship skin: one filled rect per
	# contiguous same-type region, plus a darker border. The regions were
	# merged at rebuild (through the very same shared greedy helper), so a
	# repaint is emission and nothing else.
	for entry in _draw_regions:
		var r: Rect2i = entry[0]
		var color: Color = TerrainDB.color_of(entry[1])
		var rect := Rect2(Vector2(r.position) * cell_px, Vector2(r.size) * cell_px)
		draw_rect(rect, color)
		draw_rect(rect, color.darkened(0.35), false, 1.0)
