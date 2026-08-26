class_name MapView
extends Control

## The toggled world map (owner 2026-08-22: "what about the map?"). Opened with a
## key (Tab), hidden by default. Code-drawn, no assets, in the placeholder style:
## the world frame, the three airspace bands tinted, discovered islands as marks,
## undiscovered regions as fog with "?" — and the player/ship positions.
##
## Rendering ONLY. The discovered-region state lives in MapDiscovery (a testable
## data model); this reads it, reads Terrain for which coarse regions hold land,
## and reads the world for the live foci. One map-cell is one terrain CHUNK, so a
## "does this region have land?" check is a chunk lookup.

var world: Node2D
var terrain: Terrain
var discovery: MapDiscovery

## Airspace bands to tint, as (altitude-fraction low, high, colour). Fractions are
## Airspace's own (0 = floor, 1 = ceiling); we read the constants directly rather
## than Airspace.bounds, which is deliberately empty at runtime (generation-only).
const BANDS := [
	[Airspace.GAP_HIGH_TOP, 1.0, Color(0.30, 0.36, 0.52, 0.5)],       # TOP
	[Airspace.GAP_LOW_TOP, Airspace.MID_TOP, Color(0.26, 0.40, 0.34, 0.5)],  # MID
	[Airspace.LAVA_TOP, Airspace.DEEP_TOP, Color(0.34, 0.26, 0.30, 0.5)],    # DEEP
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func toggle() -> void:
	visible = not visible


# --- World → map screen mapping -------------------------------------------

func _world_px_rect() -> Rect2:
	var cp := 16.0
	var wr := IslandGen.WORLD_CELLS
	if terrain != null:
		# SUBDIV-AWARE (owner 2026-08-25, "the map doesn't seem to have scaled
		# with the world changes"): the world's CELL extent scales UP by subdiv
		# exactly as cell_px scales DOWN by it, so the true px rect is their
		# subdiv-invariant product — the same formula the boundary walls and
		# the save's location label already use (CELL × world_scale). Reading
		# raw WORLD_CELLS against the subdiv-divided cell_px framed only
		# 1/subdiv of the world: a QUARTER of it at the shipped subdiv 4.
		cp = terrain.cell_px()
		wr = IslandGen.world_cells(terrain.subdiv)
	return Rect2(Vector2(wr.position) * cp, Vector2(wr.size) * cp)


## The on-screen rectangle the whole world maps into: centred, margined, aspect
## preserved. Returned as [origin, size, scale].
func _map_rect() -> Array:
	var wpx := _world_px_rect()
	var margin := 70.0
	var avail := Vector2(size.x - margin * 2.0, size.y - margin * 2.0 - 40.0)
	var sc: float = minf(avail.x / wpx.size.x, avail.y / wpx.size.y)
	var msize := wpx.size * sc
	var morigin := Vector2((size.x - msize.x) * 0.5, (size.y - msize.y) * 0.5 + 12.0)
	return [morigin, msize, sc]


## A ship's blip colour — the MAP half of the friend/foe language (Ship's
## attitude_cast is the world half). Pulled out of _draw so it is a value the
## suite can assert on: a colour buried in a draw call is a colour no test
## can see.
##
## A tamed creature is yours, but it is not a VESSEL — reading it as one is
## how you lose track of your whale among your ships — so it takes the same
## teal it wears in the world.
static func blip_color(ship: Ship) -> Color:
	if ship.faction == 1:
		return Color(0.95, 0.40, 0.35)             # hostile
	if ship.is_tamed_ally():
		return Ship.CAST_ALLY                      # your tamed creature
	if ship.faction == 2:
		return Color(0.85, 0.70, 0.95)             # wildlife
	return Color(0.55, 0.80, 1.0)                  # player / vessel


func _w2m(world_pos: Vector2, mr: Array) -> Vector2:
	var wpx := _world_px_rect()
	return (mr[0] as Vector2) + (world_pos - wpx.position) * float(mr[2])


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var mr := _map_rect()
	var morigin := mr[0] as Vector2
	var msize := mr[1] as Vector2
	var map_area := Rect2(morigin, msize)

	# Dim the whole screen behind the map, then the map's own dark ground.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.82))
	draw_rect(map_area, Color(0.07, 0.09, 0.13))

	_draw_bands(map_area)
	_draw_fog_and_land(mr, map_area, font)
	_draw_wind(map_area)
	_draw_frame(map_area)
	_draw_markers(mr, font)
	_draw_title(font, morigin, msize)


## The three airspace bands as subtle horizontal tints across the map.
func _draw_bands(map_area: Rect2) -> void:
	for b in BANDS:
		var f_low := float(b[0])
		var f_high := float(b[1])
		# altitude frac 1 = ceiling = top of the map.
		var y_top := map_area.position.y + (1.0 - f_high) * map_area.size.y
		var y_bot := map_area.position.y + (1.0 - f_low) * map_area.size.y
		draw_rect(Rect2(map_area.position.x, y_top, map_area.size.x, y_bot - y_top),
			b[2] as Color)


## Fog over the whole map, lifted where discovered; discovered land drawn as
## island blips; a sparse "?" sprinkled over the fog so undiscovered reads as
## mystery, not emptiness.
func _draw_fog_and_land(mr: Array, map_area: Rect2, font: Font) -> void:
	# Fog blanket.
	draw_rect(map_area, Color(0.12, 0.13, 0.16, 0.78))

	var cp := 16.0
	var sub := 1
	if terrain != null:
		cp = terrain.cell_px()
		sub = maxi(terrain.subdiv, 1)
	# One map-cell == 512×512 FINE tiles (MapDiscovery.cell_px = chunk_px×subdiv
	# ×2 — two coarse chunks; owner 2026-08-24): constant PX granularity at any
	# terrain resolution. Fine chunks bucket DOWN to this grid below, so "has
	# land" stays one dictionary hit per map cell.
	var bucket := sub * 2
	var chunk_px := float(Terrain.CHUNK) * cp * float(bucket)
	var cell_screen := chunk_px * float(mr[2])

	# Which map cells hold land (fine chunk coords ÷ the bucket factor, floor
	# toward −∞ so the grid is correct across the origin).
	var land := {}
	if terrain != null:
		for c in terrain.chunk_coords():
			var fc: Vector2i = c
			land[Vector2i(floori(float(fc.x) / bucket), floori(float(fc.y) / bucket))] = true

	# Lift the fog on discovered cells, and blip any that hold land.
	if discovery != null:
		for mc in discovery.discovered_cells():
			var cell: Vector2i = mc
			var topleft := _w2m(Vector2(cell) * chunk_px, mr)
			var r := Rect2(topleft, Vector2(cell_screen, cell_screen) + Vector2.ONE)
			# Revealed sky: a faint clearing over the fog.
			draw_rect(r, Color(0.16, 0.20, 0.26, 0.55))
			if land.has(cell):
				# An island mark — inset so cells read as discrete marks, not a slab.
				var inset := cell_screen * 0.18
				var blip := Rect2(topleft + Vector2(inset, inset),
					Vector2(cell_screen - inset * 2.0, cell_screen - inset * 2.0))
				draw_rect(blip, Color(0.62, 0.72, 0.55))

	# Sparse "?" over undiscovered cells, on a coarse screen lattice so the glyph
	# count is bounded by the screen, not the map (thousands of cells otherwise).
	var wpx := _world_px_rect()
	var step: float = maxf(26.0, cell_screen)
	var fs := 13
	var y := map_area.position.y
	while y < map_area.end.y:
		var x := map_area.position.x
		while x < map_area.end.x:
			var world_pos := wpx.position + (Vector2(x, y) - (mr[0] as Vector2)) / float(mr[2])
			if discovery == null or not discovery.is_discovered_at(world_pos):
				draw_string(font, Vector2(x, y + fs), "?",
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.34, 0.37, 0.44, 0.7))
			x += step
		y += step


## The wind circulation drawn over the band tints (owner 2026-08-23): ONLY the
## frame's spine and rim carry wind, never per band. The vertical limbs — centre
## updraft, both edge downdrafts — are faint tinted columns with an arrow column
## each; the top and bottom CONNECTOR ROWS are faint tinted strips with a row of
## arrows each (outward across the top, inward across the bottom). Every direction
## and boundary comes from Airspace.wind_dir_at (the fraction constants), so the
## map and sim can never drift apart. The four horizontal DIVIDER rows (ceiling
## OUTWARD, blue/green gap INWARD, green/red gap OUTWARD, floor INWARD) are faint
## tinted strips with a row of arrows each; the band interiors between them stay
## calm — nothing drawn there — so the loop reads at any world size.
func _draw_wind(map_area: Rect2) -> void:
	var tint := Color(0.42, 0.64, 0.74, 0.14)
	# Vertical limbs (tinted columns) + the four horizontal divider rows (tinted):
	# ceiling, the blue/green gap (GAP_HIGH), the green/red gap (GAP_LOW), the floor.
	_draw_frac_column(map_area, 0.5 - Airspace.CENTRE_HALF_W, 0.5 + Airspace.CENTRE_HALF_W, tint)
	_draw_frac_column(map_area, 0.0, Airspace.EDGE_W, tint)
	_draw_frac_column(map_area, 1.0 - Airspace.EDGE_W, 1.0, tint)
	_draw_frac_row(map_area, 1.0 - Airspace.EDGE_H, 1.0, tint)                          # ceiling
	_draw_frac_row(map_area, Airspace.MID_TOP, Airspace.GAP_HIGH_TOP, tint)             # blue/green gap
	_draw_frac_row(map_area, Airspace.DEEP_TOP, Airspace.GAP_LOW_TOP, tint)             # green/red gap
	_draw_frac_row(map_area, 0.0, Airspace.EDGE_H, tint)                                # floor

	var limb_col := Color(0.62, 0.84, 0.92, 0.5)   # vertical limbs (up / down)
	var flow_col := Color(0.92, 0.83, 0.60, 0.5)   # horizontal connectors (out / in)
	var arrow := 13.0

	# The vertical limbs: one arrow column each, full height, at the limb centres
	# derived from the fractions (guaranteed a mark even where they are narrow).
	var vstep := 40.0
	for limb_fx in [0.5, Airspace.EDGE_W * 0.5, 1.0 - Airspace.EDGE_W * 0.5]:
		var lx: float = map_area.position.x + float(limb_fx) * map_area.size.x
		var ly := map_area.position.y + vstep * 0.5
		while ly < map_area.end.y:
			var a := 1.0 - (ly - map_area.position.y) / map_area.size.y
			var dir := Airspace.wind_dir_at(float(limb_fx), a)
			if dir != Vector2.ZERO:
				_draw_arrow(Vector2(lx, ly), dir, arrow, limb_col)
			ly += vstep

	# The horizontal divider rows: one arrow ROW each, sampled along the MIDDLE of
	# each divider (ceiling, the two band gaps, floor) so the thin rows never fall
	# between lattice samples. The limb columns are skipped (vertical, drawn above).
	var hstep := 44.0
	for row_a in [
			1.0 - Airspace.EDGE_H * 0.5,                                # ceiling
			(Airspace.MID_TOP + Airspace.GAP_HIGH_TOP) * 0.5,          # blue/green gap
			(Airspace.DEEP_TOP + Airspace.GAP_LOW_TOP) * 0.5,         # green/red gap
			Airspace.EDGE_H * 0.5]:                                     # floor
		var ry: float = map_area.position.y + (1.0 - float(row_a)) * map_area.size.y
		var rx := map_area.position.x + hstep * 0.5
		while rx < map_area.end.x:
			var fx := (rx - map_area.position.x) / map_area.size.x
			var dir := Airspace.wind_dir_at(fx, float(row_a))
			if dir != Vector2.ZERO and dir.y == 0.0:
				_draw_arrow(Vector2(rx, ry), dir, arrow, flow_col)
			rx += hstep


func _draw_frac_column(map_area: Rect2, f_lo: float, f_hi: float, col: Color) -> void:
	var x_lo := map_area.position.x + f_lo * map_area.size.x
	var x_hi := map_area.position.x + f_hi * map_area.size.x
	draw_rect(Rect2(x_lo, map_area.position.y, x_hi - x_lo, map_area.size.y), col)


## A horizontal band tint spanning altitude fractions [f_lo, f_hi] (0 = floor).
func _draw_frac_row(map_area: Rect2, f_lo: float, f_hi: float, col: Color) -> void:
	var y_top := map_area.position.y + (1.0 - f_hi) * map_area.size.y
	var y_bot := map_area.position.y + (1.0 - f_lo) * map_area.size.y
	draw_rect(Rect2(map_area.position.x, y_top, map_area.size.x, y_bot - y_top), col)


## A small arrow centred on `center`, pointing along the unit `dir`.
func _draw_arrow(center: Vector2, dir: Vector2, length: float, col: Color) -> void:
	var half := dir * (length * 0.5)
	var tip := center + half
	draw_line(center - half, tip, col, 1.5)
	var back := dir * (length * 0.4)
	var perp := Vector2(-dir.y, dir.x) * (length * 0.28)
	draw_line(tip, tip - back + perp, col, 1.5)
	draw_line(tip, tip - back - perp, col, 1.5)


func _draw_frame(map_area: Rect2) -> void:
	draw_rect(map_area, Color(0.55, 0.62, 0.72, 0.9), false, 2.0)


## Player and ship positions. The player is a bright marker (you are here); ships
## are smaller dots tinted by faction so the hulk and whale read apart.
func _draw_markers(mr: Array, font: Font) -> void:
	if world == null:
		return
	var fleet: Variant = world.get("fleet")
	if fleet != null:
		for ship in fleet.ships():
			if not is_instance_valid(ship):
				continue
			var p := _w2m(ship.global_position, mr)
			draw_circle(p, 3.0, blip_color(ship))
	var player: Variant = world.get("player")
	if player != null and is_instance_valid(player):
		var pp := _w2m(player.global_position, mr)
		# A small up-triangle so "you" stands out from the ship dots.
		var pts := PackedVector2Array([
			pp + Vector2(0, -6), pp + Vector2(-5, 5), pp + Vector2(5, 5)])
		draw_colored_polygon(pts, Color(1.0, 0.95, 0.55))


func _draw_title(font: Font, morigin: Vector2, msize: Vector2) -> void:
	draw_string(font, Vector2(morigin.x, morigin.y - 14.0),
		"WORLD MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.90, 1.0))
	var hint := "Tab to close   ·   ? = undiscovered   ·   fly near a region to chart it"
	draw_string(font, Vector2(morigin.x, morigin.y + msize.y + 22.0),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.60, 0.66, 0.75))
