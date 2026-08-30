class_name PauseMenu
extends PanelContainer

## THE ESCAPE MENU (owner 2026-08-30: "how about we also completely convert the
## use of the escape key such that it doesn't just immediately quit? … in-game,
## we can add an 'escape' menu -> quit to title").
##
## Escape used to close the game where you stood, mid-run, with no confirmation
## — the one keypress in the game that could throw away ten minutes by accident.
## It opens this instead: resume, or go back to the front door.
##
## It is a PANEL, not a mode: nothing pauses. That is deliberate and matches the
## rest of the game's chrome (the title, the saves list, the character sheet) —
## the world keeps running behind it, so opening the menu is never a way to stop
## a fight you are losing.
##
## No new binding: Escape already exists as `quit_game`, and this is the same key
## doing the same verb one step less abruptly (docs/KEYBINDINGS.md).

var world: Node2D
var _label: Label


static func _text(in_run: bool) -> String:
	return "\n".join([
		"",
		"  PAUSED  ",
		"",
		"  [Esc]  back to it  ",
		"  [Q]    quit to the title screen  ",
		"",
		("  (a run in progress is LOST — the ledger is the only record)  "
			if in_run else "  (your world is saved with F5, not here)  "),
	])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	add_child(_label)
	visible = false


func open() -> void:
	var in_run := false
	if world != null and is_instance_valid(world) and world.has_method("dive_style"):
		in_run = bool(world.call("dive_style"))
	_label.text = _text(in_run)
	visible = true


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Keys are taken at the INPUT stage while visible, marked handled first so the
## world behind never also acts on them. Quitting to the title tears this scene
## down, so — as with the title panel — it is the LAST thing this function does.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	var keycode := (event as InputEventKey).keycode
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
	match keycode:
		KEY_ESCAPE:
			close()
		KEY_Q:
			close()
			if world != null and is_instance_valid(world) \
					and world.has_method("quit_to_title"):
				world.call("quit_to_title")
