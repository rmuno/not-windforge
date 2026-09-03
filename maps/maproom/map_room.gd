class_name MapRoomScreen
extends Control

## THE MAP ROOM (owner arc, 2026-09-01: "this way I can look at the full Dive
## mode map, for example, and SEE the entire thing there").
##
## A workshop SCREEN, off the title's WORKSHOP door, in the drafting table's
## house style (maps/editor/ship_editor.gd): dark ground, ink/dim palette,
## left-aligned lists, a back row. No world, no run, no physics — which is the
## whole point. A dive map you can only see by diving is a map you cannot study.
##
## It draws the WIND RING unrolled left to right, exactly as the owner sketched
## it — `V . . . . . ^ . . . . . V` — with the eight depth rungs across it, the
## ladder's landings, the outposts, the floating rock of the flanks, the
## unbreathable line and the floor.
##
## EVERYTHING HERE IS DERIVED FROM PURE MODEL FUNCTIONS (`DiveRun.*`,
## `Airspace.*`, `Backdrop.band_palette`). `model()` returns the whole chart as
## plain values and `_draw_chart` only paints them, so the suite can assert the
## map without a renderer — the world-decides/layer-paints rule, with the MODEL
## standing in for the world. Read-only this round: no editing, no seeding a run.

const _BG := Color(0.05, 0.07, 0.11)
const _PANEL := Color(0.08, 0.11, 0.16)
const _INK := Color(0.88, 0.92, 1.0)
const _DIM := Color(0.55, 0.62, 0.74)
const _GRID := Color(0.16, 0.20, 0.27)
const _COIN := Color(0.95, 0.83, 0.42)
const _LAND := Color(0.62, 0.58, 0.50)
const _ROCK := Color(0.44, 0.41, 0.36)
const _POST := Color(0.45, 0.90, 0.72)
const _SEAM := Color(0.95, 0.55, 0.40)
const _START := Color(0.55, 0.80, 1.0)
const _DANGER := Color(0.95, 0.40, 0.35)
## The garrison's own colour — the chart's foe ink, kept distinct from the
## unbreathable line's red so a dot is never mistaken for the air gate.
const _FOE := Color(0.90, 0.33, 0.50)

## Half a tile of air at each end, so the seam columns are not clipped in half.
const CHART_PAD_TILES := 0.5
## One pregenerated picket's dot, in screen px. Small on purpose: there are a
## couple of hundred of them and the ladder has to stay the thing you read.
const GARRISON_DOT_PX := 2.0

## The seed the chart is drawn for. A REAL RUN ROLLS ITS OWN (DiveRun._init), so
## this is a specimen, not a promise — the screen says so in as many words.
var seed_v := 0

var _canvas: Control
var _seed_label: Label
## How many times the chart has actually painted. A test asserting "the redraw
## did not crash" is vacuous if the redraw never happened, and whether a headless
## Godot calls `_draw` is exactly the sort of thing that quietly changes.
var draws := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if seed_v == 0:
		seed_v = randi()

	var bg := ColorRect.new()
	bg.color = _BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_build_side())

	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_chart)
	root.add_child(_canvas)

	_refresh()


# --- The panel ---------------------------------------------------------------

func _build_side() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 260
	col.add_theme_constant_override("separation", 4)
	_title_row(col, "  THE MAP ROOM", _INK, 15)
	_note(col, "  the Dive's whole sky, unrolled")
	col.add_child(HSeparator.new())
	_title_row(col, "  THE WIND RING", _COIN, 13)
	_note(col, "  V . . . . . ^ . . . . . V\n"
		+ "  ^ updraft (the start, centre)\n"
		+ "  . the rocks — floating land\n"
		+ "  V downdraft, and the SEAM:\n"
		+ "    both edges are one tile.\n"
		+ "    Fly off either side and\n"
		+ "    you arrive from the other.")
	col.add_child(HSeparator.new())
	_title_row(col, "  THE LADDER", _COIN, 13)
	_note(col, "  %d depths, top to floor.\n" % DiveRun.DEPTHS
		+ "  ◆ a landing  ◆ an outpost\n"
		+ "  ▬ floating rock\n"
		+ "  the red line is where the\n"
		+ "  air stops being breathable.")
	col.add_child(HSeparator.new())
	_title_row(col, "  THE GARRISON", _FOE, 13)
	_note(col, "  • one picket, standing where\n"
		+ "    the seed put it. They are\n"
		+ "    already there — a run only\n"
		+ "    gives them bodies once you\n"
		+ "    are two screens away.\n"
		+ "  the flanks are worse than home,\n"
		+ "  and the downdraft is worst.")
	col.add_child(HSeparator.new())
	_seed_label = Label.new()
	_seed_label.add_theme_font_size_override("font_size", 12)
	_seed_label.add_theme_color_override("font_color", _INK)
	col.add_child(_seed_label)
	_action(col, "reroll the seed", reroll)
	_note(col, "  a real run rolls its own seed,\n  so this is a specimen sky")
	col.add_child(HSeparator.new())
	_action(col, "back to the title", _back)
	return col


func _title_row(col: Control, text: String, tint: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint)
	col.add_child(l)


func _note(col: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", _DIM)
	col.add_child(l)


func _action(col: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = "  " + label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	col.add_child(b)


## A NEW SKY, with no world anywhere near it: the chart is a pure function of the
## seed, so rerolling is a redraw and nothing else.
func reroll() -> void:
	seed_v = randi()
	_refresh()


func _refresh() -> void:
	if _seed_label != null:
		_seed_label.text = "  seed  %d" % seed_v
	if _canvas != null:
		_canvas.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_back()


func _back() -> void:
	var err := get_tree().change_scene_to_file("res://maps/intro/intro.tscn")
	if err != OK:
		push_error("MapRoom: could not return to the title (%d)" % err)


# --- THE MODEL ---------------------------------------------------------------

## How many SHELF widths one tile is worth — the conversion the ladder needs,
## because `DiveRun.landing_offset` is measured in SHELF widths while this
## chart's x axis is measured in TILES. The dive's own world sizes a tile as
## `dive_zone_tile_widths` of the AUTHORED shelf (`world.dive_nominal_tile_w`),
## so the map room reads the same lever rather than inventing a second one.
##
## A live run's landings are cut against the MEASURED shelf, which the widest
## hull in the sky can only make SMALLER (`world._dive_shelf_span`) — so the
## slalom drawn here is the widest it can ever be, and a real ladder sits inside
## it. Overstating the spread is the safe direction for a chart to be wrong in.
func tile_widths() -> float:
	return maxf(Tunables.get_num("dive_zone_tile_widths"), 0.001)


## THE WHOLE CHART, as plain values. Nothing below this line needs a world, a
## run, a ship or a renderer — which is what makes the map room headless-testable
## and what keeps this screen honest: if the drawing and the game ever disagree,
## it is because the game stopped using its own model.
func model() -> Dictionary:
	var per_shelf := 1.0 / tile_widths()
	var columns := DiveRun.ring_overview(seed_v, tile_widths())

	var rows: Array = []
	for d in range(1, DiveRun.DEPTHS + 1):
		var alt := DiveRun.depth_altitude(d)
		var pal := Backdrop.band_palette(alt)
		rows.append({
			"depth": d,
			"label": DiveRun.depth_label(d),
			"alt": alt,
			"band": Airspace.band_at_frac(alt),
			# The band's own sky colour — the backdrop's language, so a rung on
			# this chart is the colour of the air you will actually be flying in.
			"color": pal[1] as Color,
			"ink": pal[2] as Color,
			# In TILE widths from the ring's centre line, so it shares the x axis
			# with the ring's columns.
			"landing_x": DiveRun.landing_offset(seed_v, d) * per_shelf,
			"outpost": DiveRun.is_outpost(seed_v, d),
			"breathable": not Airspace.is_unbreathable_frac(alt),
		})

	# The floating rock of the flanks, placed on the same axis. The seam column
	# is emitted twice by ring_overview, so its chunks would be too — it is a
	# "down" tile and grows none, but the loop is written to survive a table
	# where it does.
	var chunks: Array = []
	for c in columns:
		var col := c as Dictionary
		for d in range(2, DiveRun.DEPTHS + 1):
			for r in DiveRun.tile_chunks(seed_v, int(col["tile"]), d):
				var row := r as Dictionary
				chunks.append({
					"tile": int(col["tile"]),
					"depth": d,
					"x": float(col["offset"]) + float(row["x"]),
					"alt": float(row["alt"]),
					"w": float(row["w"]),
					"h": float(row["h"]),
				})

	# WHO IS ALREADY OUT THERE (owner 2026-09-01: the garrison is pregenerated
	# per seed now, so the chart can finally answer "where will they be" instead
	# of "where might something appear"). The very same pure rows the world
	# materializes from — `DiveRun.tile_garrison` — on the same axis as
	# everything else. The seam column is emitted twice, so its pickets are drawn
	# at both edges, which is right: it is one tile seen from both sides.
	#
	# Since v0.141.0 a depth's garrison stands in the three tiles around its own
	# LANDING COLUMN, so this draws a diagonal of clusters following the ladder's
	# slalom rather than an evenly-seeded ring — which is the chart finally
	# saying "the fight is here, the loot is out there" (review §5.1).
	var garrison: Array = []
	for c2 in columns:
		var col2 := c2 as Dictionary
		for d2 in range(2, DiveRun.DEPTHS + 1):
			for g in DiveRun.tile_garrison(seed_v, int(col2["tile"]), d2,
					tile_widths()):
				var grow := g as Dictionary
				garrison.append({
					"tile": int(col2["tile"]),
					"depth": d2,
					"kind": String(grow["kind"]),
					"x": float(col2["offset"]) + float(grow["x"]),
					"alt": float(grow["alt"]),
				})

	var half := float(DiveRun.RING.size()) * 0.5
	return {
		"seed": seed_v,
		"columns": columns,
		"rows": rows,
		"chunks": chunks,
		"garrison": garrison,
		# The x axis, in tile widths: the ring plus half a tile of air at each end.
		"x_min": -half - CHART_PAD_TILES,
		"x_max": half + CHART_PAD_TILES,
		"unbreathable_alt": Airspace.DEEP_TOP,
		"floor_alt": DiveRun.FLOOR_FRAC,
		"top_alt": DiveRun.TOP_FRAC,
	}


# --- The chart ---------------------------------------------------------------

func _draw_chart() -> void:
	draws += 1
	var m := model()
	var font := ThemeDB.fallback_font
	var area := Rect2(Vector2(16.0, 30.0), _canvas.size - Vector2(32.0, 52.0))
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	_canvas.draw_rect(area, _PANEL)

	var x_min := float(m["x_min"])
	var x_max := float(m["x_max"])
	var tile_px := area.size.x / maxf(x_max - x_min, 0.001)

	# --- the sky: one strip per rung, in that rung's own band colour ---------
	var rows := m["rows"] as Array
	for i in rows.size():
		var row := rows[i] as Dictionary
		var y_mid := _alt_y(float(row["alt"]), area)
		var y_top := y_mid if i == 0 else (y_mid + _alt_y(
			float((rows[i - 1] as Dictionary)["alt"]), area)) * 0.5
		var y_bot := area.end.y if i == rows.size() - 1 else (y_mid + _alt_y(
			float((rows[i + 1] as Dictionary)["alt"]), area)) * 0.5
		if i == 0:
			y_top = area.position.y
		_canvas.draw_rect(Rect2(area.position.x, y_top, area.size.x, y_bot - y_top),
			row["color"] as Color)

	# --- the ring's columns -------------------------------------------------
	var columns := m["columns"] as Array
	for c in columns:
		var col := c as Dictionary
		var cx := _tile_x(float(col["offset"]), area, x_min, tile_px)
		var edge := _tile_x(float(col["offset"]) - 0.5, area, x_min, tile_px)
		_canvas.draw_line(Vector2(edge, area.position.y), Vector2(edge, area.end.y),
			_GRID)
		var kind := String(col["kind"])
		var tint: Color = _SEAM if bool(col["seam"]) else (
			_START if bool(col["start"]) else _DIM)
		# The wind's own arrow, so the ring reads at a glance: ^ up, V down.
		var glyph := "^" if kind == "up" else ("V" if kind == "down" else "·")
		_canvas.draw_string(font, Vector2(cx - 4.0, area.position.y - 12.0),
			glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tint)
		if bool(col["start"]) or bool(col["seam"]):
			_canvas.draw_line(Vector2(cx, area.position.y), Vector2(cx, area.end.y),
				Color(tint, 0.45), 2.0)
			_canvas.draw_string(font, Vector2(cx - 34.0, area.end.y + 14.0),
				String(col["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)

	# THE LOOP, SAID OUT LOUD: matching arrows at both edges, because the two
	# seam columns are one place and a chart that does not say so is a chart
	# that reads as a corridor with walls.
	_canvas.draw_string(font, Vector2(area.position.x + 4.0, area.position.y + 16.0),
		"◀ loops to the far edge", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _SEAM)
	var tail := "loops to the near edge ▶"
	_canvas.draw_string(font,
		Vector2(area.end.x - font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 11).x - 4.0, area.position.y + 16.0),
		tail, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _SEAM)

	# --- the floating rock of the flanks ------------------------------------
	for k in m["chunks"] as Array:
		var ch := k as Dictionary
		var w: float = maxf(float(ch["w"]) * tile_px, 2.0)
		var h: float = maxf(float(ch["h"]) * tile_px, 2.0)
		var at := Vector2(_tile_x(float(ch["x"]), area, x_min, tile_px) - w * 0.5,
			_alt_y(float(ch["alt"]), area) - h * 0.5)
		_canvas.draw_rect(Rect2(at, Vector2(w, h)), _ROCK)

	# --- the garrison: who is standing in that sky before you get there -----
	# Drawn UNDER the rung lines and the landings, so the ladder still reads
	# first: this is the answer to "how bad is it over there", not the chart's
	# subject. Small hostile dots, one per pregenerated picket.
	for g in m["garrison"] as Array:
		var pk := g as Dictionary
		_canvas.draw_circle(
			Vector2(_tile_x(float(pk["x"]), area, x_min, tile_px),
				_alt_y(float(pk["alt"]), area)), GARRISON_DOT_PX, _FOE)

	# --- the ladder: a rung line, its landing, its shop ----------------------
	for r in rows:
		var row := r as Dictionary
		var y := _alt_y(float(row["alt"]), area)
		_canvas.draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y),
			Color(row["ink"] as Color, 0.8))
		_canvas.draw_string(font, Vector2(area.position.x + 4.0, y - 4.0),
			String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _INK)
		var lx := _tile_x(float(row["landing_x"]), area, x_min, tile_px)
		var lw: float = maxf(tile_px / tile_widths(), 4.0)
		_canvas.draw_rect(Rect2(lx - lw * 0.5, y - 3.0, lw, 6.0), _LAND)
		if bool(row["outpost"]):
			_canvas.draw_rect(Rect2(lx - lw * 0.5, y - 9.0, lw, 5.0), _POST)
			_canvas.draw_string(font, Vector2(lx + lw * 0.5 + 4.0, y - 4.0),
				"OUTPOST", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, _POST)

	# --- the two lines that decide whether you live -------------------------
	var air_y := _alt_y(float(m["unbreathable_alt"]), area)
	_canvas.draw_line(Vector2(area.position.x, air_y), Vector2(area.end.x, air_y),
		_DANGER, 2.0)
	_canvas.draw_string(font, Vector2(area.position.x + 4.0, air_y - 6.0),
		"UNBREATHABLE BELOW THIS LINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _DANGER)
	_canvas.draw_line(Vector2(area.position.x, area.end.y - 1.0),
		Vector2(area.end.x, area.end.y - 1.0), _COIN, 2.0)
	_canvas.draw_string(font, Vector2(area.position.x + 4.0, area.end.y - 5.0),
		"THE FLOOR — the lava, and the Leviathan",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _COIN)


## An altitude fraction (0 = floor, 1 = ceiling) to a y in the chart. The chart
## spans the LADDER, not the whole sky: the run never sees the air above depth 1.
func _alt_y(a: float, area: Rect2) -> float:
	var top := DiveRun.TOP_FRAC
	var bottom := DiveRun.FLOOR_FRAC
	var t := clampf((top - a) / maxf(top - bottom, 0.001), 0.0, 1.0)
	return area.position.y + t * area.size.y


func _tile_x(tiles: float, area: Rect2, x_min: float, tile_px: float) -> float:
	return area.position.x + (tiles - x_min) * tile_px
