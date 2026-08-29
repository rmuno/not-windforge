class_name StartChooser
extends PanelContainer

## THE BOOT CHOICE (owner 2026-08-29: "some option on game start to determine
## whether it'll be the sandbox mode or regular"). One small centred panel the
## moment a single-player world opens: [1] EXPEDITION (the full game, exactly
## as before) or [2] SANDBOX (kitted out, no deep-air suffocation — the
## v0.85.0 loadout, one press instead of a trip through F2).
##
## Deliberately NOT a main menu: the world is already alive behind it, nothing
## is paused, and any other key just dismisses it as EXPEDITION — so a player
## who ignores it entirely gets the unchanged game. Sandbox remains reversible
## afterwards through F2 exactly as before; this is only a front door to a
## toggle that already exists.
##
## It does not show in HEADLESS runs (the suite boots dozens of worlds and a
## panel eating digit keys would poison unrelated checks) or ONLINE (sandbox
## is a host-side dev toggle) — but `open()` is public, so the startup test
## drives the real panel and the real keys.

var world: Node2D
var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_label.text = "\n".join([
		"  NOT WINDFORGE  ",
		"",
		"  [1]  EXPEDITION — the full game  ",
		"  [2]  SANDBOX — kitted out, no suffocation; jump straight to the meat  ",
		"",
		"  (any other key: expedition)  "])
	add_child(_label)
	visible = false
	if DisplayServer.get_name() != "headless" and not Net.is_online():
		open()


func open() -> void:
	visible = true


## Keys are taken at the INPUT stage while visible, marked handled so they
## reach nothing behind the panel (the same pre-GUI stage the world's global
## toggles use, and for the same reason — the first press must always land).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	match (event as InputEventKey).keycode:
		KEY_2, KEY_KP_2:
			if world != null and world.has_method("debug_sandbox_loadout"):
				world.call("debug_sandbox_loadout")
		_:
			pass  # 1, Esc, anything: expedition — the world is already the world
	visible = false
	get_viewport().set_input_as_handled()
