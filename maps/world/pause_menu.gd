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
## IT ACTUALLY PAUSES (owner 2026-08-30: *"escape within game does not pause even
## if it says it does"*). The first cut was chrome like every other panel, on the
## reasoning that a pause is a way to stop a fight you are losing — but a panel
## that says PAUSED and does not pause is lying to the player, and in a single-
## player game the pause is what the word promises. So the tree really stops,
## EXCEPT online, where one player cannot stop everyone else's world; there the
## label says the truth instead.
##
## The panel runs with PROCESS_MODE_ALWAYS, or it could not read the key that
## closes it.
##
## No new binding: Escape already exists as `quit_game`, and this is the same key
## doing the same verb one step less abruptly (docs/KEYBINDINGS.md).

var world: Node2D
var _label: Label


static func _text(in_run: bool, really_paused := true) -> String:
	return "\n".join([
		"",
		"  PAUSED  " if really_paused else "  MENU (the world keeps running)  ",
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
	# Reads its own key while the tree is stopped — without this the menu opens,
	# pauses the game and can never be closed again.
	process_mode = Node.PROCESS_MODE_ALWAYS


func open() -> void:
	var in_run := false
	if world != null and is_instance_valid(world) and world.has_method("dive_style"):
		in_run = bool(world.call("dive_style"))
	_label.text = _text(in_run, _can_pause())
	visible = true
	if _can_pause():
		get_tree().paused = true


func close() -> void:
	visible = false
	# Never leave the tree stopped behind a hidden panel. Unconditional on
	# purpose: whatever paused it, closing this is the way back.
	if is_inside_tree():
		get_tree().paused = false


## A pause stops the whole tree, which is one player stopping everybody's world.
## Single-player only; online the panel is honest chrome instead.
##
## THIS ASKS THE ENGINE, NOT `Net`, and that is not a style choice: the startup
## suite names `PauseMenu` (it checks this panel's wording), which pulls this
## script into that test's COMPILE-TIME dependency graph — and a test script is
## compiled before the engine's autoloads exist. `Net.is_online()` here became
## "Identifier not found: Net" and took the whole suite down. `title_screen.gd`
## carries the same scar and the same rule: a `class_name` script a test may name
## must not reference an autoload. `NetUtil.is_online` is this, verbatim.
func _can_pause() -> bool:
	if not is_inside_tree():
		return true
	var peer := multiplayer.multiplayer_peer
	return peer == null or peer is OfflineMultiplayerPeer


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
