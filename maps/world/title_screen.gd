class_name TitleScreen
extends PanelContainer

## THE FRONT DOOR'S PANEL — two pages of text over the intro scene
## (maps/intro/intro.gd), which is what actually moves behind it.
##
##   TITLE — the name, and PLAY.
##   MODES — the three doors: [1] EXPEDITION, [2] SANDBOX, [3] THE DIVE.
##
## It knows nothing about the world or the modes: it calls `choose_mode(name)`
## on whatever owns it, and the intro decides what that means. That is what let
## the intro become its own scene without this file changing shape — it was
## already talking to an owner rather than to a world.
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
##
## ORDER MATTERS HERE, and it cost the owner a crash: choosing a door tears this
## whole scene down (`SceneTree.change_scene_to_file`), so ANYTHING this node
## touches afterwards — `visible`, `get_viewport()` — is touching a node on its
## way out. The event is marked handled FIRST, and the choice is the LAST thing
## this function does. `_handled()` also tolerates a null viewport, because a
## panel being torn down is exactly when it has one.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	var keycode := (event as InputEventKey).keycode
	_handled()
	if page == Page.TITLE:
		# Esc quits from the title — the one place in the game where it means
		# "I did not want to play", rather than "close this".
		if keycode == KEY_ESCAPE:
			get_tree().quit()
			return
		page = Page.MODES
		_repaint()
		return
	# Hide before choosing, so the last frame of this scene is not a menu over a
	# world that is already loading — and choose last, because after this call
	# there may be no `self` worth touching.
	visible = false
	_choose(keycode)


## Mark the event consumed, tolerating a node that is already leaving the tree.
func _handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## Apply one mode. Anything unlisted is EXPEDITION — the world is already the
## world, so that door costs nothing to walk through.
func _choose(keycode: int) -> void:
	if world == null or not is_instance_valid(world) or not world.has_method("choose_mode"):
		# Loud rather than silent: a panel that quietly does nothing is the
		# worst front door there is. This fires if the intro scene ever hands
		# the panel an owner that cannot take a choice.
		push_error("TitleScreen: no owner to choose a mode — the front door is inert")
		visible = true
		return
	match keycode:
		KEY_2, KEY_KP_2:
			world.call("choose_mode", GameMode.SANDBOX)
		KEY_3, KEY_KP_3:
			world.call("choose_mode", GameMode.DIVE)
		_:
			world.call("choose_mode", GameMode.EXPEDITION)
