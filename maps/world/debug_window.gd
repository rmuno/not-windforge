class_name DebugWindow
extends CanvasLayer

## The dev-facing DEBUG WINDOW (owner tool, session 5): a toggled, tabbed panel
## that spawns enemies on demand and exposes the gameplay LEVERS (Tunables) for
## live tweaking. Hidden by default — a dev overlay, not always-on chrome, in
## keeping with the decluttered-screen direction. Toggled with F2 (world.gd; F1/
## F3/F5/F9 and the letter keys are all taken).
##
## The lever tabs are BUILT FROM the Tunables registry — one tab per group, one
## row per lever — so adding a lever (one registry row) makes it appear here with
## no UI change. Each row edits Tunables live; a `note` ("next spawn") marks
## levers that only apply on the next spawn/rebuild (pod count, whale health).
##
## The Spawn / Player tabs call real methods on the world (debug_spawn,
## debug_grant_money, …); the Perf tab surfaces the live counts + the existing
## whale diagnostic toggle. Everything routes through the world so this node holds
## no game state — it only reads/writes Tunables and calls world verbs.
##
## Single-player / host dev tool. Networked/replicated debug spawns are a seam
## (world.debug_spawn is authority-gated); persisting lever overrides is a seam.

var world: Node2D

var _tabs: TabContainer
var _perf_label: Label
## id -> the Range control (slider) / CheckBox, and id -> its value Label, so a
## "reset all" can push the defaults back into the live controls.
var _controls := {}
var _value_labels := {}

const _BG := Color(0.05, 0.07, 0.10, 0.96)
const _BORDER := Color(0.35, 0.42, 0.52, 0.95)
const _FG := Color(0.85, 0.89, 0.96)
const _MUTED := Color(0.60, 0.64, 0.70)
const _ACCENT := Color(0.55, 0.82, 0.55)


func _ready() -> void:
	layer = 128  # above the HUD layer
	visible = false
	_build()


func toggle() -> void:
	visible = not visible


## The active tab index (state, not pixels — what the window tests assert).
func active_tab() -> int:
	return _tabs.current_tab if _tabs != null else 0


func set_tab(i: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(i, 0, maxi(0, _tabs.get_tab_count() - 1))


func _process(_delta: float) -> void:
	if visible and _perf_label != null:
		_perf_label.text = _perf_text()


# --- Build -----------------------------------------------------------------

func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.custom_minimum_size = Vector2(460, 560)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _BG
	sb.border_color = _BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var title := Label.new()
	title.text = "DEBUG  (F2 to close)"
	title.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	title.add_theme_font_size_override("font_size", 15)
	outer.add_child(title)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(436, 500)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)

	# Spawn first — the owner's headline ask ("spawn enemies on demand").
	_build_spawn_tab()
	# One tab per Tunables group (Whale, Combat, World), built from the registry.
	for group in Tunables.groups():
		_build_lever_tab(group)
	_build_player_tab()
	_build_perf_tab()


## A scrollable VBox tab, returned so the caller fills it with rows.
func _add_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	return box


## Build a tab of live lever rows for one Tunables group.
func _build_lever_tab(group: String) -> void:
	var box := _add_tab(group)
	for row in Tunables.in_group(group):
		_build_lever_row(box, row as Dictionary)


func _build_lever_row(box: VBoxContainer, row: Dictionary) -> void:
	var id: String = row["id"]
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	var label_text: String = row["label"]
	if row.has("note"):
		label_text += "  (%s)" % row["note"]
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(210, 0)
	name_label.add_theme_color_override("font_color", _FG)
	name_label.add_theme_font_size_override("font_size", 12)
	line.add_child(name_label)

	if row["kind"] == Tunables.KIND_BOOL:
		var check := CheckBox.new()
		check.button_pressed = Tunables.get_bool(id)
		check.toggled.connect(func(on: bool) -> void: Tunables.set_value(id, on))
		_controls[id] = check
		line.add_child(check)
	else:
		var slider := HSlider.new()
		slider.min_value = float(row["min"])
		slider.max_value = float(row["max"])
		slider.step = float(row["step"])
		slider.value = Tunables.get_num(id)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(150, 0)
		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(64, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", _ACCENT)
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.text = _fmt(id)
		slider.value_changed.connect(func(v: float) -> void:
			Tunables.set_value(id, v)
			value_label.text = _fmt(id))
		_controls[id] = slider
		_value_labels[id] = value_label
		line.add_child(slider)
		line.add_child(value_label)

	box.add_child(line)


func _build_spawn_tab() -> void:
	var box := _add_tab("Spawn")
	_hint(box, "Spawns near the player (authority / single-player).")
	_action_button(box, "Spawn hulk (bandit)", func() -> void: _spawn("hulk"))
	_action_button(box, "Spawn whale (random variant)", func() -> void: _spawn("whale"))


func _build_player_tab() -> void:
	var box := _add_tab("Player")
	_hint(box, "Cheats for the local player body.")
	_action_button(box, "Grant $1000", func() -> void:
		if world != null: world.call("debug_grant_money", 1000))
	_action_button(box, "Heal to full", func() -> void:
		if world != null: world.call("debug_heal_player"))
	_action_button(box, "Max all stats", func() -> void:
		if world != null: world.call("debug_max_stats"))


func _build_perf_tab() -> void:
	var box := _add_tab("Perf")
	_perf_label = Label.new()
	_perf_label.add_theme_color_override("font_color", _FG)
	_perf_label.add_theme_font_size_override("font_size", 13)
	_perf_label.text = _perf_text()
	box.add_child(_perf_label)
	_action_button(box, "Toggle whale diagnostic (F3)", func() -> void:
		if world != null: world.call("_toggle_whale_diag"))
	_action_button(box, "Reset ALL tunables to defaults", func() -> void: _reset_all())


func _hint(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _MUTED)
	l.add_theme_font_size_override("font_size", 11)
	box.add_child(l)


func _action_button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	box.add_child(b)


# --- Actions ---------------------------------------------------------------

func _spawn(kind: String) -> void:
	if world == null:
		return
	world.call("debug_spawn", kind, _spawn_pos())


## Where a debug spawn appears: a little to port of the player (or the local
## ship, or the ship-start fallback), so it lands in view but not on top of you.
func _spawn_pos() -> Vector2:
	if world == null:
		return Vector2.ZERO
	var scale := maxf(float(world.get("world_scale")), 1.0)
	var off := Vector2(-320.0, -80.0) * scale
	var p: Variant = world.get("player")
	if p != null and is_instance_valid(p):
		return (p as Node2D).global_position + off
	var s: Variant = world.get("local_ship")
	if s != null and is_instance_valid(s):
		return (s as Node2D).global_position + off
	return off


func _reset_all() -> void:
	Tunables.reset_all()
	# Push the defaults back into every live control so the UI reflects the reset.
	for id in _controls:
		var c: Control = _controls[id]
		if c is CheckBox:
			(c as CheckBox).button_pressed = Tunables.get_bool(id)
		elif c is Range:
			(c as Range).value = Tunables.get_num(id)
		if _value_labels.has(id):
			(_value_labels[id] as Label).text = _fmt(id)


# --- Formatting ------------------------------------------------------------

func _fmt(id: String) -> String:
	var d := Tunables.def(id)
	if d.get("kind", "") == Tunables.KIND_INT:
		return str(Tunables.get_int(id))
	var v := Tunables.get_num(id)
	# Compact: no trailing zeros for whole numbers, else a couple of decimals.
	if absf(v - roundf(v)) < 0.0005:
		return str(int(roundf(v)))
	return "%.3f" % v


func _perf_text() -> String:
	var ships := 0
	var shots := 0
	if world != null:
		var fleet: Variant = world.get("fleet")
		if fleet != null and is_instance_valid(fleet):
			ships = (fleet.call("ships") as Array).size()
		var tree := world.get_tree()
		if tree != null:
			shots = tree.get_nodes_in_group("shots").size()
	return "FPS:    %d\nShips:  %d\nShots:  %d" % [
		Engine.get_frames_per_second(), ships, shots]
