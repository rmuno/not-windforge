class_name ShipEditorScreen
extends Control

## THE DRAFTING TABLE (owner arc Q-Q, 2026-09-01; opened up in Q-T, 2026-09-02)
## — the native ship builder. Replaces the mid-air Shipyard ("the midair shipyard
## is ridiculous"): no world, no physics, no 8× grid. A quiet screen off the
## title's WORKSHOP door where the owner paints a blueprint at AUTHORED 1× — the
## one granularity a shipped default may be written at — with the Loft's stats
## beside it, improved.
##
## Q-T OPENED IT TO EVERY FILE (owner: *"this is just for players to design their
## own ships if they want, and for me to manually review/modify anything else
## we've created"*). Creatures, nests and the launch deck are `.ship` files too,
## so the table now:
##
##   · LISTS every blueprint under `res://ships` (drafts included) and the
##     player's `ShipLayout.user_dir`, and opens any of them;
##   · SAVES — "save as" into `user://ships`, or overwrite the file that is open;
##   · carries the HEADER VOCABULARY (`ShipLayout.META_KEYS`) as editable fields,
##     which is what makes a creature file a whole creature rather than a
##     silhouette the spawn code has to recognise by its path;
##   · swaps the PALETTE and the FYI PANEL by `kind`, because a whale has no
##     engines and a hull has no blubber;
##   · and can FLY THE THING — TRY IT boots a quiet world with this blueprint
##     spawned in front of the player, through the game's own spawn functions.
##
## Layout: files (left) · palette · the sheet (centre) · FYI + headers + actions.
## Every rule lives in the MODEL (modes/ship_edit.gd — pure, headless-tested);
## this scene forwards clicks and paints, per the world-decides/layer-paints
## split (here the model decides).
##
## MAKE IT THE DEFAULT: "export to clipboard" always works (paste into any
## `.ship`, or into the Loft). "OVERWRITE the open file" writes `res://` directly
## — which only sticks where res:// is a real writable directory (running from
## the project; the web export's res:// is a packed read-only bundle), so the
## button says what happened, honestly.

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
var _palette_box: VBoxContainer
var _palette_buttons := {}
var _painting := false
var _erasing := false

## The file list, and the rows behind it (same order).
var _file_list: ItemList
var _rows: Array = []

## The header fields. Written into `edit.meta` on every edit.
var _f_name: LineEdit
var _f_kind: OptionButton
var _f_health: LineEdit
var _f_tame: LineEdit
var _f_bounty: LineEdit
var _f_role: LineEdit
var _f_tint: LineEdit
var _f_notes: LineEdit
var _f_save_as: LineEdit
## True while the fields are being filled FROM the meta, so the change signals
## they emit do not write straight back over what they are displaying.
var _filling := false

## The overwrite button is ARMED by a first press and fires on the second. It
## used to be able to clobber exactly one file (the starter); it can now clobber
## any blueprint in the repo, and a mis-click on "the file I was reading" is a
## different kind of mistake from a mis-click on "the file I was editing".
var _overwrite_btn: Button
var _overwrite_armed := false


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

	root.add_child(_build_files())
	root.add_child(_build_palette())

	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	root.add_child(_canvas)

	root.add_child(_build_side())

	_open_on_boot()
	refresh_files()


## WHAT IS ON THE TABLE WHEN YOU WALK IN. In order: the sheet you carried out to
## TRY IT (unsaved work must survive a look at the world — that was the whole
## risk of adding a button that changes scenes), then the last file you had open
## (walking back through the WORKSHOP door returns you to where you were), then
## the starter, which is what the owner came to edit the first time.
func _open_on_boot() -> void:
	if ShipEdit.carry_text != "" and edit.from_text(ShipEdit.carry_text):
		_say("your unsaved sheet is back%s"
			% ("" if ShipEdit.last_path == "" else " (from %s)" % ShipEdit.last_path))
		_after_load()
		return
	if ShipEdit.last_path != "" and edit.load_path(ShipEdit.last_path):
		_say("%s is on the table" % ShipEdit.last_path)
		_after_load()
		return
	load_starter()


# --- Panels ------------------------------------------------------------------

func _build_files() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 220
	col.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "  BLUEPRINTS"
	title.add_theme_color_override("font_color", _COIN)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "  res://ships and your own\n  saved ships — click to open"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", _DIM)
	col.add_child(hint)
	_file_list = ItemList.new()
	_file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_list.add_theme_font_size_override("font_size", 12)
	_file_list.item_selected.connect(_open_row)
	col.add_child(_file_list)
	_action(col, "refresh the list", refresh_files)
	return col


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
	# The palette itself is REBUILT whenever the kind changes, so it lives in its
	# own box rather than straight in this column.
	_palette_box = VBoxContainer.new()
	_palette_box.add_theme_constant_override("separation", 4)
	col.add_child(_palette_box)
	_rebuild_palette()
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


## Fill the palette box for the open blueprint's `kind`. A brush that is not in
## the new palette falls back to its first entry — otherwise switching a hull to
## a whale would leave an engine loaded in a palette that cannot paint one.
func _rebuild_palette() -> void:
	if _palette_box == null:
		return
	for child in _palette_box.get_children():
		child.queue_free()
	_palette_buttons = {}
	var types := ShipEdit.palette_for(edit.kind())
	if not types.has(brush) and brush != -1:
		brush = int(types[0]) if not types.is_empty() else -1
	for type in types:
		var def := BlockDB.get_def(type)
		var b := Button.new()
		b.text = "  %s" % def["name"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = (type == brush)
		b.add_theme_color_override("font_color", def["color"])
		b.pressed.connect(func() -> void: _pick_brush(type))
		_palette_box.add_child(b)
		_palette_buttons[type] = b
	var erase := Button.new()
	erase.text = "  erase (or right-click)"
	erase.alignment = HORIZONTAL_ALIGNMENT_LEFT
	erase.toggle_mode = true
	erase.button_pressed = (brush == -1)
	erase.pressed.connect(func() -> void: _pick_brush(-1))
	_palette_box.add_child(erase)
	_palette_buttons[-1] = erase


func _build_side() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 320
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "IT WOULD FLY LIKE THIS"
	title.add_theme_color_override("font_color", _COIN)
	col.add_child(title)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.add_theme_color_override("font_color", _INK)
	col.add_child(_stats)
	col.add_child(HSeparator.new())

	var htitle := Label.new()
	htitle.text = "HEADERS (written into the file)"
	htitle.add_theme_color_override("font_color", _COIN)
	col.add_child(htitle)
	_f_name = _field(col, "name")
	_f_kind = OptionButton.new()
	for k in ShipLayout.META_KINDS:
		_f_kind.add_item(String(k))
	_f_kind.item_selected.connect(func(_i: int) -> void: _write_meta())
	col.add_child(_label_for("kind"))
	col.add_child(_f_kind)
	_f_health = _field(col, "health")
	_f_tame = _field(col, "tame")
	_f_bounty = _field(col, "bounty")
	_f_role = _field(col, "role")
	_f_tint = _field(col, "tint  (r g b, 0..1)")
	_f_notes = _field(col, "notes")
	col.add_child(HSeparator.new())

	_f_save_as = LineEdit.new()
	_f_save_as.placeholder_text = "name to save as"
	col.add_child(_f_save_as)
	_action(col, "SAVE AS (user://ships)", _save_as)
	_overwrite_btn = Button.new()
	_overwrite_btn.text = "OVERWRITE the open file"
	_overwrite_btn.pressed.connect(_overwrite_open)
	col.add_child(_overwrite_btn)
	_action(col, "TRY IT — fly this now", _try_it)
	col.add_child(HSeparator.new())
	_action(col, "load the starter", load_starter)
	_action(col, "load from clipboard", _load_clipboard)
	_action(col, "export to clipboard", _export_clipboard)
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
	return scroll


func _label_for(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", _DIM)
	return l


func _field(col: Control, label: String) -> LineEdit:
	col.add_child(_label_for(label))
	var e := LineEdit.new()
	e.text_changed.connect(func(_t: String) -> void: _write_meta())
	col.add_child(e)
	return e


func _action(col: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	col.add_child(b)


func _pick_brush(type: int) -> void:
	brush = type
	for t in _palette_buttons:
		(_palette_buttons[t] as Button).button_pressed = (t == brush)


# --- The header fields <-> edit.meta ------------------------------------------

## Fields -> meta. An EMPTY field erases its key rather than writing a blank, so
## "I did not say" and "I said nothing" stay the same thing — which is what makes
## the override layer safe: an absent header means the spawn code's own constant.
func _write_meta() -> void:
	if _filling:
		return
	_set_meta_text("name", _f_name.text)
	edit.meta["kind"] = String(ShipLayout.META_KINDS[_f_kind.selected]) \
		if _f_kind.selected >= 0 else "vessel"
	_set_meta_num("health", _f_health.text, false)
	_set_meta_num("tame", _f_tame.text, true)
	_set_meta_num("bounty", _f_bounty.text, true)
	_set_meta_text("role", _f_role.text)
	_set_meta_text("notes", _f_notes.text)
	var tint := _f_tint.text.strip_edges()
	if tint == "":
		edit.meta.erase("tint")
	else:
		var parts := tint.split(" ", false)
		if parts.size() >= 3:
			edit.meta["tint"] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	_rebuild_palette()
	_refresh()


func _set_meta_text(key: String, value: String) -> void:
	var v := value.strip_edges()
	if v == "":
		edit.meta.erase(key)
	else:
		edit.meta[key] = v


func _set_meta_num(key: String, value: String, whole: bool) -> void:
	var v := value.strip_edges()
	if v == "":
		edit.meta.erase(key)
	elif whole:
		edit.meta[key] = int(v)
	else:
		edit.meta[key] = float(v)


## meta -> fields, after a load. `_filling` keeps the change signals from writing
## straight back (which would, among other things, re-type a float as its own
## printed form on every open).
func _fill_fields() -> void:
	if _f_name == null:
		return
	_filling = true
	_f_name.text = String(edit.meta.get("name", ""))
	var k := edit.kind()
	_f_kind.selected = maxi(0, ShipLayout.META_KINDS.find(k))
	_f_health.text = "" if not edit.meta.has("health") \
		else "%.0f" % float(edit.meta["health"])
	_f_tame.text = "" if not edit.meta.has("tame") else str(int(edit.meta["tame"]))
	_f_bounty.text = "" if not edit.meta.has("bounty") else str(int(edit.meta["bounty"]))
	_f_role.text = String(edit.meta.get("role", ""))
	_f_notes.text = String(edit.meta.get("notes", ""))
	if edit.meta.has("tint"):
		var c: Color = edit.meta["tint"]
		_f_tint.text = "%.3f %.3f %.3f" % [c.r, c.g, c.b]
	else:
		_f_tint.text = ""
	_filling = false


# --- The file list -----------------------------------------------------------

func refresh_files() -> void:
	_rows = ShipEdit.file_rows()
	if _file_list == null:
		return
	_file_list.clear()
	var last_source := ""
	for row in _rows:
		var d := row as Dictionary
		var prefix := ""
		if String(d["source"]) != last_source:
			last_source = String(d["source"])
			prefix = "· " if last_source == "user" else ""
		_file_list.add_item("%s%s" % [prefix, String(d["label"])])


func _open_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var path := String((_rows[index] as Dictionary)["path"])
	if edit.load_path(path):
		ShipEdit.carry_text = ""   # the carried sheet is superseded
		_say("%s is on the table" % path)
	elif ShipLayout.file_scale(FileAccess.get_file_as_string(path)) > 1:
		# An F2 `export_ship` file: already at the world’s granularity, so editing
		# it here and saving it as a default would be the eightfold family.
		_say("%s is an UPSCALED export (scale %d) — the table edits authored 1× files only. F2-spawn it in a world instead."
			% [path, ShipLayout.file_scale(FileAccess.get_file_as_string(path))])
	else:
		_say("%s did not parse — nothing loaded" % path)
	_after_load()


## Everything that must follow a load, wherever it came from: the fields, the
## palette (the kind may have changed) and the panel.
func _after_load() -> void:
	_fill_fields()
	_rebuild_palette()
	_disarm_overwrite()
	_refresh()


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
	# Lift-prop markers are a VESSEL's business; a creature has no props and the
	# rule would paint nothing anyway, so the query is skipped for one.
	var vertical := edit.vertical_prop_cells() if edit.kind() == "vessel" else {}
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
	if edit.load_path(STARTER_PATH):
		ShipEdit.carry_text = ""
		_say("the starter is on the table")
	else:
		_say("could not open %s" % STARTER_PATH)
	_after_load()


func _load_clipboard() -> void:
	var text := DisplayServer.clipboard_get()
	if edit.from_text(text):
		ShipEdit.carry_text = ""
		_say("clipboard blueprint loaded")
	elif ShipLayout.file_scale(text) > 1:
		_say("that is an UPSCALED export (scale %d) — the table edits authored 1× files only. Paste it into the Loft, or F2-spawn it in a world." % ShipLayout.file_scale(text))
	else:
		_say("the clipboard is not a .ship blueprint")
	_after_load()


func _export_clipboard() -> void:
	var text := edit.to_text()
	if text.is_empty():
		_say("an empty sheet exports nothing")
		return
	DisplayServer.clipboard_set(text)
	_say("copied — paste over any .ship in the repo to make it the default, or into the Loft")


## SAVE AS: the player's own shelf, `ShipLayout.user_dir`. This is also where the
## Dive's launch deck looks for candidates, so saving a vessel here is the whole
## of "dive with the ship I designed".
func _save_as() -> void:
	var typed := _f_save_as.text.strip_edges()
	if typed == "":
		typed = String(edit.meta.get("name", ""))
	if typed == "":
		_say("give it a name first — that is what the file is called")
		return
	# The name you save under IS the blueprint's name, unless it already had one.
	if not edit.meta.has("name"):
		edit.meta["name"] = typed
		_fill_fields()
	var path := ShipEdit.user_path_for(typed)
	if edit.save_to(path):
		ShipEdit.carry_text = ""
		_say("saved to %s — a vessel saved here is a launch-deck candidate in the Dive" % path)
	else:
		_say("could not write %s" % path)
	refresh_files()
	_refresh()


## The owner's "make it the default", generalised from the starter to WHATEVER IS
## OPEN. res:// is a real directory when running from the project (the owner's
## machine, the editor, the suite) and a packed read-only bundle in an export —
## so this works exactly where making a file the default makes sense, and says so
## where it does not. Two presses, because it can now overwrite any file in the
## repo rather than only the one the button was named after.
func _overwrite_open() -> void:
	var path := ShipEdit.last_path
	if path == "":
		_say("nothing is open — use SAVE AS")
		return
	if edit.to_text().is_empty():
		_say("an empty sheet cannot overwrite anything")
		return
	if not _overwrite_armed:
		_overwrite_armed = true
		_overwrite_btn.text = "…really? click again to overwrite"
		_say("this will replace %s on disk" % path)
		return
	_disarm_overwrite()
	if edit.save_to(path):
		ShipEdit.carry_text = ""
		_say("%s OVERWRITTEN — it is what the game loads now (next boot)" % path)
	else:
		_say("could not write %s — res:// is read-only in an exported build; use 'export to clipboard' and paste it into the repo instead" % path)
	refresh_files()


func _disarm_overwrite() -> void:
	_overwrite_armed = false
	if _overwrite_btn != null:
		_overwrite_btn.text = "OVERWRITE the open file"


## TRY IT: the sheet goes out to a quiet world and comes back. The text is
## written to a scratch file (`ShipEdit.try_file`) because the world spawns from
## a PATH — the same path every other blueprint reaches the spawn code by, which
## is what makes this a preview of the real thing — and it is ALSO kept in
## `carry_text`, so an unsaved design survives the round trip.
func _try_it() -> void:
	var text := edit.to_text()
	if text.is_empty():
		_say("an empty sheet has nothing to fly")
		return
	if not edit.save_to(ShipEdit.try_file(), false):
		_say("could not write %s" % ShipEdit.try_file())
		return
	ShipEdit.carry_text = text
	GameMode.try_path = ShipEdit.try_file()
	GameMode.pending = GameMode.SANDBOX
	var err := get_tree().change_scene_to_file(GameMode.scene_for(GameMode.SANDBOX))
	if err != OK:
		GameMode.try_path = ""
		push_error("ShipEditor: could not open a world to try it in (%d)" % err)
		_say("could not open a world to try it in")


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg


func _back() -> void:
	var err := get_tree().change_scene_to_file("res://maps/intro/intro.tscn")
	if err != OK:
		push_error("ShipEditor: could not return to the title (%d)" % err)
