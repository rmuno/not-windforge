class_name TitleScreen
extends PanelContainer

## THE FRONT DOOR (owner 2026-08-30: "what if we have an intro screen of just
## the whales floating around in the sky, then you can choose PLAY -> choose 1
## of the 3 modes").
##
## Two pages over a LIVE world — nothing is paused, nothing is a separate scene:
##
##   TITLE — the name, and PLAY. While this is up the camera stops following
##           your body and drifts across the whale pod instead (world._track_
##           camera). That is the whole intro: the game's own sky, its own
##           whales, its own backdrop, moving. No mock-up, no video, no assets.
##   MODES — the three doors: [1] EXPEDITION, [2] SANDBOX, [3] THE DIVE.
##
## It grew out of the v0.88.0 boot chooser (StartChooser) and keeps its rules:
## it does not show in HEADLESS runs (the suite boots dozens of worlds and a
## panel eating digit keys would poison unrelated checks) or ONLINE (sandbox and
## the Dive are single-player things) — but `open()` is public, so the startup
## test drives the real panel with real keys.
##
## Any key that is not a listed choice falls through to EXPEDITION, so a player
## who mashes past the whole thing gets the unchanged game.

enum Page { TITLE, MODES }

var world: Node2D
var page: int = Page.TITLE

var _label: Label

static func _title_text() -> String:
	return "\n".join([
	"",
	"        N O T   W I N D F O R G E        ",
	"",
	"            [Enter]   PLAY            ",
	"",
	"              (Esc quits)              ",
	"",
])

static func _modes_text() -> String:
	return "\n".join([
	"",
	"  CHOOSE YOUR GAME  ",
	"",
	"  [1]  EXPEDITION — the full game  ",
	"  [2]  SANDBOX — kitted out, no suffocation; jump straight to the meat  ",
	"  [3]  THE DIVE — a run: eight depths down, bank what you carry  ",
	"",
	"  (any other key: expedition)  ",
])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	add_child(_label)
	_repaint()
	visible = false
	if DisplayServer.get_name() != "headless" and not Net.is_online():
		open()


func open() -> void:
	page = Page.TITLE
	_repaint()
	visible = true


## Which page is showing, as a plain bool. The startup suite asks through this
## rather than reading `Page` off the class: naming the type in a test file pulls
## THIS script into that test's compile-time dependency graph, and it is compiled
## before the engine's autoloads exist — so the `Net.is_online()` below became
## "Identifier not found: Net" and took the whole suite down with it.
func on_title_page() -> bool:
	return page == Page.TITLE


func _repaint() -> void:
	if _label != null:
		_label.text = _title_text() if page == Page.TITLE else _modes_text()


## Keys are taken at the INPUT stage while visible, marked handled so they reach
## nothing behind the panel (the same pre-GUI stage the world's global toggles
## use, and for the same reason — the first press must always land).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	var keycode := (event as InputEventKey).keycode
	if page == Page.TITLE:
		# Esc quits from the title — the one place in the game where it means
		# "I did not want to play", rather than "close this".
		if keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			get_tree().quit()
			return
		page = Page.MODES
		_repaint()
		get_viewport().set_input_as_handled()
		return
	_choose(keycode)
	visible = false
	get_viewport().set_input_as_handled()


## Apply one mode. Anything unlisted is EXPEDITION — the world is already the
## world, so that door costs nothing to walk through.
func _choose(keycode: int) -> void:
	if world == null:
		return
	match keycode:
		KEY_2, KEY_KP_2:
			if world.has_method("debug_sandbox_loadout"):
				world.call("debug_sandbox_loadout")
		KEY_3, KEY_KP_3:
			if world.has_method("begin_dive"):
				world.call("begin_dive")
		_:
			pass  # 1, Esc, anything: expedition
