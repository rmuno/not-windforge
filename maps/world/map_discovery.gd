class_name MapDiscovery
extends RefCounted

## Fog-of-war discovery state for the world map (owner 2026-08-22: "what about the
## map?"). DATA MODEL ONLY — it owns which coarse map-regions the player has
## uncovered and nothing about how the map is drawn, so it is unit-testable
## without a rendered overlay (MapView queries it, exactly like a promoted chunk
## is a derived view of Terrain's grid).
##
## COARSE GRID. The world is divided into square map-cells. By default a map-cell
## is one terrain CHUNK (the world sets cell_px from Terrain.chunk_px()), so "does
## this region hold terrain?" is a chunk lookup on the map screen. A cell is
## REVEALED when a focus — the player or a ship, the same streaming foci — comes
## within reveal_radius of the cell's centre. Discovery is MONOTONIC: once seen,
## always seen; nothing ever re-fogs.

## Map-cell edge in world px. Defaults to a reasonable value; the world overwrites
## it from Terrain.chunk_px() so the map tracks the real world at any scale.
var cell_px := 512.0

## How near a focus must come (world px, focus to map-cell centre) to reveal a
## cell. THE fog-of-war knob: dropping the distance test in reveal() — marking
## every cell in the scan box regardless of range — is the break-the-fix, and the
## far-focus test then fails (a distant focus would light up the whole box).
var reveal_radius := 1536.0

var _discovered := {}  # Vector2i map-cell -> true


func cell_of(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_px), floori(world_pos.y / cell_px))


## World position of a map-cell's centre — what the reveal distance is measured to.
func cell_centre(mc: Vector2i) -> Vector2:
	return (Vector2(mc) + Vector2(0.5, 0.5)) * cell_px


## Reveal every map-cell whose centre lies within reveal_radius of ANY focus.
## Scans only the cells in a bounding box around each focus (radius in cells), so
## the cost is O(foci × radius²-in-cells), never the whole map. Monotonic — it only
## ever adds. `foci` is an Array of world-space Vector2 positions.
func reveal(foci: Array) -> void:
	var r_cells := int(ceil(reveal_radius / cell_px)) + 1
	for f in foci:
		var focus: Vector2 = f
		var fc := cell_of(focus)
		for dy in range(-r_cells, r_cells + 1):
			for dx in range(-r_cells, r_cells + 1):
				var mc := fc + Vector2i(dx, dy)
				# The distance gate: reveal a cell only if its centre is genuinely
				# within reach of this focus. Removing this line is the break-the-
				# fix — a far focus would then reveal its whole scan box.
				if focus.distance_to(cell_centre(mc)) <= reveal_radius:
					_discovered[mc] = true


func is_discovered(mc: Vector2i) -> bool:
	return _discovered.has(mc)


func is_discovered_at(world_pos: Vector2) -> bool:
	return is_discovered(cell_of(world_pos))


func discovered_count() -> int:
	return _discovered.size()


## Every discovered map-cell — the map view iterates these to lift the fog.
func discovered_cells() -> Array:
	return _discovered.keys()
