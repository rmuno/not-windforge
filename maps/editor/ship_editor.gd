class_name ShipEditorScreen
extends Control

## THE DRAFTING TABLE (owner arc Q-Q, 2026-09-01) — the native ship builder.
## Replaces the mid-air Shipyard ("the midair shipyard is ridiculous"): no
## world, no physics, no 8× grid. A quiet screen off the title's WORKSHOP door
## where the owner paints a blueprint at AUTHORED 1× — the one granularity a
## shipped default may be written at — with the Loft's stats beside it, improved.
##
## Layout: palette (left) · the sheet (centre) · FYI stats + actions (right).
## Every rule lives in the MODEL (modes/ship_edit.gd — pure, headless-tested);
## this scene forwards clicks and paints, per the world-decides/layer-paints
## split (here the model decides).
##
## MAKE IT THE DEFAULT: "export to clipboard" always works (paste into
## res://ships/starter.ship, or into the Loft). "OVERWRITE the starter" writes
## res://ships/starter.ship directly — which only sticks where res:// is a real
## writable directory (running from the project; the web export's res:// is a
## packed read-only bundle), so the button says what happened, honestly.

const _BG := Color(0.05, 0.07, 0.11)
const _PANEL := Color(0.08, 0.11, 0.16)
const _INK := Color(0.88, 0.92, 1.0)
const _DIM := Color(0.55, 0.62, 0.74)
const _GRID := Color(0.16, 0.20, 0.27)
const _COIN := Color(0.95, 0.83, 0.42)

const STARTER_PATH := "res://ships/starter.ship"

var edit := ShipEdit.new()

## The selected palette type; -1 is the eraser.
var brush: int = BlockDB.Type.HULL

var _canvas: Control
var _stats: Label
var _status: Label
var _palette_buttons := {}
var _painting := false
var _erasing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = _BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_build_palette())

	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	root.add_child(_canvas)

	root.add_child(_build_side())

	# The starter is what the owner came to edit; open on it.
	load_starter()


# --- Panels ------------------------------------------------------------------

func _build_palette() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 190
	col.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "  THE DRAFTING TABLE"
	title.add_theme_color_override("font_color", _INK)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "  authored 1× — the game\n  upscales at boot"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", _DIM)
	col.add_child(hint)
	col.add_child(HSeparator.new())
	for type in ShipEdit.palette():
		var def := BlockDB.get_def(type)
		var b := Button.new()
		b.text = "  %s" % def["name"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = (type == brush)
		b.add_theme_color_override("font_color", def["color"])
		b.pressed.connect(func() -> void: _pick_brush(type))
		col.add_child(b)
		_palette_buttons[type] = b
	var erase := Button.new()
	erase.text = "  erase (or right-click)"
	erase.alignment = HORIZONTAL_ALIGNMENT_LEFT
	erase.toggle_mode = true
	erase.pressed.connect(func() -> void: _pick_brush(-1))
	col.add_child(erase)
	_palette_buttons[-1] = erase
	col.add_child(HSeparator.new())
	var mirror := CheckButton.new()
	mirror.text = "mirror X"
	mirror.toggled.connect(func(on: bool) -> void: edit.mirror_x = on)
	col.add_child(mirror)
	var undo := Button.new()
	undo.text = "undo (Ctrl+Z)"
	undo.pressed.connect(_undo)
	col.add_child(undo)
	return col


func _build_side() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "IT WOULD FLY LIKE THIS"
	title.add_theme_color_override("font_color", _COIN)
	col.add_child(title)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.add_theme_color_override("font_color", _INK)
	col.add_child(_stats)
	col.add_child(HSeparator.new())
	_action(col, "load the starter", load_starter)
	_action(col, "load from clipboard", _load_clipboard)
	_action(col, "export to clipboard", _export_clipboard)
	_action(col, "OVERWRITE the starter (res://)", _overwrite_starter)
	_action(col, "clear the sheet", func() -> void:
		edit.clear()
		_refresh())
	col.add_child(HSeparator.new())
	_action(col, "back to the title", _back)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", _DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 290
	col.add_child(_status)
	return col


func _action(col: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	col.add_child(b)


func _pick_brush(type: int) -> void:
	brush = type
	for t in _palette_buttons:
		(_palette_buttons[t] as Button).button_pressed = (t == brush)


# --- The sheet ---------------------------------------------------------------

## Cell size: fit the whole sheet to the canvas, whole pixels, never below 4.
func _cell_px() -> int:
	if edit.width <= 0 or edit.height <= 0:
		return 8
	var fit := mini(int(_canvas.size.x / edit.width), int(_canvas.size.y / edit.height))
	return maxi(4, fit)


func _sheet_origin() -> Vector2:
	var px := float(_cell_px())
	return (_canvas.size - Vector2(edit.width, edit.height) * px) * 0.5


func _cell_at(pos: Vector2) -> Vector2i:
	var px := float(_cell_px())
	var p := (pos - _sheet_origin()) / px
	return Vector2i(floori(p.x), floori(p.y))


func _draw_canvas() -> void:
	var px := float(_cell_px())
	var o := _sheet_origin()
	_canvas.draw_rect(Rect2(o, Vector2(edit.width, edit.height) * px), _PANEL)
	# The grid, light: verticals + horizontals every 4 cells, the mirror line.
	for x in range(0, edit.width + 1, 4):
		_canvas.draw_line(o + Vector2(x * px, 0), o + Vector2(x * px, edit.height * px), _GRID)
	for y in range(0, edit.height + 1, 4):
		_canvas.draw_line(o + Vector2(0, y * px), o + Vector2(edit.width * px, y * px), _GRID)
	if edit.mirror_x:
		var mx := o.x + edit.width * px * 0.5
		_canvas.draw_line(Vector2(mx, o.y), Vector2(mx, o.y + edit.height * px),
			Color(_COIN, 0.35), 1.0)
	var vertical := edit.vertical_prop_cells()
	for cell in edit.cells:
		var c: Vector2i = cell
		var type: int = edit.cells[cell]
		var def := BlockDB.get_def(type)
		var r := Rect2(o + Vector2(c) * px, Vector2(px, px))
		_canvas.draw_rect(r, def["color"])
		# Lift props get a marker so the mounting rule is VISIBLE while placing
		# (the axis comes from mounting, and guessing it wrong is the #1 trap).
		if vertical.has(c):
			_canvas.draw_rect(Rect2(r.position + r.size * 0.3, r.size * 0.4), Color(1, 1, 1, 0.5))


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_painting = true
				_erasing = (mb.button_index == MOUSE_BUTTON_RIGHT)
				edit.begin_stroke()
				_apply(mb.position)
			else:
				_painting = false
	elif event is InputEventMouseMotion and _painting:
		_apply((event as InputEventMouseMotion).position)


func _apply(pos: Vector2) -> void:
	var type := -1 if _erasing else brush
	if edit.paint(_cell_at(pos), type):
		_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.keycode == KEY_Z and k.ctrl_pressed:
			_undo()
		elif k.keycode == KEY_ESCAPE:
			_back()


func _undo() -> void:
	if edit.undo():
		_refresh()


func _refresh() -> void:
	_stats.text = edit.stats_text()
	_canvas.queue_redraw()


# --- Actions -----------------------------------------------------------------

func load_starter() -> void:
	var f := FileAccess.open(STARTER_PATH, FileAccess.READ)
	if f == null:
		_say("could not open %s" % STARTER_PATH)
		return
	if edit.from_text(f.get_as_text()):
		_say("the starter is on the table")
	else:
		_say("the starter did not parse — nothing loaded")
	_refresh()


func _load_clipboard() -> void:
	var text := DisplayServer.clipboard_get()
	if edit.from_text(text):
		_say("clipboard blueprint loaded")
	elif ShipLayout.file_scale(text) > 1:
		_say("that is an UPSCALED export (scale %d) — the table edits authored 1× files only. Paste it into the Loft, or F2-spawn it in a world." % ShipLayout.file_scale(text))
	else:
		_say("the clipboard is not a .ship blueprint")
	_refresh()


func _export_clipboard() -> void:
	var text := edit.to_text()
	if text.is_empty():
		_say("an empty sheet exports nothing")
		return
	DisplayServer.clipboard_set(text)
	_say("copied — paste over res://ships/starter.ship (or any .ship) to make it a default, or into the Loft")


## The owner's "make it the default". res:// is a real directory when running
## from the project (the owner's machine, the editor, the suite) and a packed
## read-only bundle in an export — so this works exactly where making a file the
## default makes sense, and says so where it does not.
func _overwrite_starter() -> void:
	var text := edit.to_text()
	if text.is_empty():
		_say("an empty sheet cannot be the starter")
		return
	var f := FileAccess.open(STARTER_PATH, FileAccess.WRITE)
	if f == null:
		_say("res:// is read-only here (exported build) — use 'export to clipboard' and paste over ships/starter.ship in the repo instead")
		return
	f.store_string(text)
	f.close()
	_say("ships/starter.ship OVERWRITTEN — it is the default now (next boot flies it)")


func _say(msg: String) -> void:
	_status.text = msg


func _back() -> void:
	var err := get_tree().change_scene_to_file("res://maps/intro/intro.tscn")
	if err != OK:
		push_error("ShipEditor: could not return to the title (%d)" % err)
