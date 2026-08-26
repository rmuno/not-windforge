class_name BuildPicker
extends Control

## HOLD B → the build palette as a GRID; release over an entry to choose it
## (owner 2026-08-26: "the picker sounds good"). TAP B still cycles — the two
## live side by side, so alternating between two things stays one key and
## choosing out of two dozen stops being a scroll.
##
## Why a picker at all: the B cycle had grown to ~27 entries (13 block types +
## the rotated propeller + every placeable material in the pack + 3 balloons),
## and a linear cycle degrades with every item added. The weapon is NOT one of
## those entries and never will be — LMB shoots unconditionally — so this only
## ever grew for BUILDING, which is exactly where a grid beats a ring.
##
## Presentation only, the split every HUD surface here uses (CharacterSheet,
## HudLayer, MapView): the world builds the model (`build_picker_model`) and
## commits the choice (`select_build`); this paints the grid and answers which
## cell the cursor is over. It never touches a palette, an inventory or a Ship.
##
## Mouse-driven on purpose: WASD walks the player, so the cursor is the only
## free pointer while B is held. The grid is CENTRED rather than dropped at the
## cursor (the owner's words were "a grid at the cursor") because hover-to-pick
## wants the cursor to START clear of the cells and travel TO one — opening
## under the cursor would land it on an arbitrary entry.

var world: Node2D

## Laid out in _draw and read back by hovered_entry(), so the geometry the
## cursor is tested against is exactly the geometry drawn — one source, never a
## second copy that can drift (the lesson PhysicsCensus/FrameCensus are built on).
var _cells: Array = []   # [{ "rect": Rect2, "entry": Dictionary }, ...]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the game reads the raw cursor
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_cells.clear()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # counts and reach change live; and the hover moves


## The entry under the cursor right now, or {} if the cursor is off the grid
## (release there keeps the current selection — a cancel).
func hovered_entry() -> Dictionary:
	var m := get_local_mouse_position()
	for cell in _cells:
		if (cell["rect"] as Rect2).has_point(m):
			return cell["entry"]
	return {}


func _scale() -> int:
	var vh := get_viewport_rect().size.y
	return clampi(int(round(vh / 900.0)), 1, 3)


func _draw() -> void:
	_cells.clear()
	if world == null or not visible:
		return
	var groups: Variant = world.call("build_picker_model")
	if groups == null:
		return
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 13 * s
	var title_fs := 14 * s

	# Cell + layout metrics.
	var cols := 4
	var cell_w := 150.0 * s
	var cell_h := 30.0 * s
	var gap := 6.0 * s
	var pad := 16.0 * s
	var row_h := 22.0 * s   # a group's header line

	# Panel height: title + per-group (header + wrapped rows of cells).
	var grid_w := cols * cell_w + (cols - 1) * gap
	var w := grid_w + pad * 2.0
	var content_h := title_fs + 10.0 * s
	for g in groups:
		var n: int = (g["entries"] as Array).size()
		var rows := int(ceil(float(n) / float(cols)))
		content_h += row_h + rows * (cell_h + gap) + gap
	var h := content_h + pad * 2.0
	var origin := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)

	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.05, 0.07, 0.10, 0.95))
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.35, 0.42, 0.52, 0.9), false, 1.0)

	var x0 := origin.x + pad
	var y := origin.y + pad + title_fs
	draw_string(font, Vector2(x0, y),
		"BUILD   (release B to choose  ·  tap B to cycle)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, Color(0.90, 0.94, 1.0))
	y += 10.0 * s

	var mouse := get_local_mouse_position()
	for g in groups:
		y += row_h
		draw_string(font, Vector2(x0, y - 6.0 * s), str(g["title"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11 * s, Color(0.60, 0.66, 0.74))
		var entries: Array = g["entries"]
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var col := i % cols
			var rowi := i / cols
			var cx := x0 + col * (cell_w + gap)
			var cy := y + rowi * (cell_h + gap)
			var rect := Rect2(Vector2(cx, cy), Vector2(cell_w, cell_h))
			_cells.append({"rect": rect, "entry": entry})

			var hovered := rect.has_point(mouse)
			var current := bool(entry.get("current", false))
			# Ground, then state: hover is brightest, the current pick keeps a
			# steady outline so you can see where you are even while hovering
			# elsewhere.
			draw_rect(rect, Color(0.14, 0.17, 0.22, 0.95) if hovered
				else Color(0.09, 0.11, 0.15, 0.95))
			if hovered:
				draw_rect(rect, Color(0.75, 0.85, 0.98), false, 2.0)
			elif current:
				draw_rect(rect, Color(0.45, 0.80, 0.95), false, 1.0)

			# Colour swatch.
			var sw := cell_h - 12.0 * s
			var swatch := Rect2(Vector2(cx + 6.0 * s, cy + 6.0 * s), Vector2(sw, sw))
			var scol: Color = entry.get("color", Color.MAGENTA)
			var stock: int = int(entry.get("count", -1))
			if stock == 0:
				scol = scol.darkened(0.5)  # an empty stack reads dim
			draw_rect(swatch, scol)
			draw_rect(swatch, Color(0, 0, 0, 0.5), false, 1.0)

			# Label + optional count.
			var tx := cx + sw + 12.0 * s
			var tcol := Color(0.88, 0.92, 0.98) if stock != 0 else Color(0.55, 0.58, 0.63)
			var label := str(entry.get("label", "?"))
			if stock >= 0:
				label += "  x%d" % stock
			draw_string(font, Vector2(tx, cy + cell_h - 9.0 * s), label,
				HORIZONTAL_ALIGNMENT_LEFT, cell_w - (sw + 18.0 * s), fs, tcol)
		var rows2 := int(ceil(float(entries.size()) / float(cols)))
		y += rows2 * (cell_h + gap) + gap
