class_name TitleScreen
extends PanelContainer

## THE FRONT DOOR'S PANEL — pages of BUTTONS over the intro scene
## (maps/intro/intro.gd), which is what actually moves behind it.
##
##   TITLE    — the name; PLAY, WORKSHOP, QUIT.
##   MODES    — the three doors: EXPEDITION, SANDBOX, THE DIVE.
##   WORKSHOP — the in-game workshop's front door (owner 2026-08-31: "where's
##              the workshop? should be in game"): the Bestiary today, the
##              records board and builder tomorrow — one page they all hang off.
##   BESTIARY — the creature log, read from the persistent profile.
##
## CLICKABLE, NOT KEY-SALAD (owner 2026-08-31: "don't add all the random
## keybindings on the title screen. Those can be clickable. No need to force
## 'any key' to do things"). Every choice is a real Button; the only keys kept
## are the quiet conventions — Enter opens PLAY, Escape means "back", 1/2/3
## pick a door while the doors are showing (the intro suite drives those) —
## nothing is advertised as a letter, and no stray key does anything at all.
##
## It knows nothing about the world or the modes: it calls `choose_mode(name)`
## on whatever owns it, and the intro decides what that means.

enum Page { TITLE, MODES, WORKSHOP, BESTIARY, CARDS }

var world: Node2D
var page: int = Page.TITLE

## The met-creatures set (id -> true) the BESTIARY page renders. The intro loads
## it from the persistent profile and hands it over before open(); this panel
## knows nothing about disk. Empty = a fresh player who has met nothing.
var discovered := {}

var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	add_child(_rows)
	_repaint()
	visible = false


func open() -> void:
	page = Page.TITLE
	_repaint()
	visible = true


## Which page is showing, as a plain bool. The startup suite asks through this
## rather than reading `Page` off the class: naming the type in a test file pulls
## THIS script into that test's compile-time dependency graph, and it is compiled
## before the engine's autoloads exist — so a `Net.…` reference here became
## "Identifier not found" and took the whole suite down with it.
func on_title_page() -> bool:
	return page == Page.TITLE


## Rebuild the page as labels + buttons. Buttons over key-lists on purpose (the
## owner's ruling above); the handful of quiet keys live in _input.
func _repaint() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	match page:
		Page.MODES:
			_label("  CHOOSE YOUR GAME  ", 15)
			_button("EXPEDITION — the full game",
				func() -> void: _choose(GameMode.EXPEDITION))
			_button("SANDBOX — kitted out, no suffocation",
				func() -> void: _choose(GameMode.SANDBOX))
			_button("THE DIVE — eight depths down, bank what you carry",
				func() -> void: _choose(GameMode.DIVE))
			_button("back", func() -> void: _go(Page.TITLE))
		Page.WORKSHOP:
			_label("  THE WORKSHOP  ", 15)
			_label("everything you have gathered, in one place", 11)
			_button("BESTIARY — the creatures you have met",
				func() -> void: _go(Page.BESTIARY))
			_button("CARDS — the run's whole deck",
				func() -> void: _go(Page.CARDS))
			_button("SHIP BUILDER — calm sky, free build, export .ship",
				func() -> void: _choose(GameMode.BUILDER))
			_button("back", func() -> void: _go(Page.TITLE))
		Page.BESTIARY:
			_label(CreatureLog.bestiary_text(discovered), 13)
			_button("back", func() -> void: _go(Page.WORKSHOP))
		Page.CARDS:
			_label(DiveCards.codex_text(), 13)
			_button("back", func() -> void: _go(Page.WORKSHOP))
		_:
			_label("\n  N O T   W I N D F O R G E  \n", 17)
			_button("PLAY", func() -> void: _go(Page.MODES))
			_button("WORKSHOP", func() -> void: _go(Page.WORKSHOP))
			_button("QUIT", func() -> void: get_tree().quit())


func _label(text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_rows.add_child(l)


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_rows.add_child(b)


func _go(to: int) -> void:
	page = to
	_repaint()


## The quiet keys — conventions, not a menu: Enter = PLAY from the title,
## Escape = back, 1/2/3 = the doors while the doors are showing. Nothing else
## does anything (the owner's "no need to force 'any key'"). Handled-first and
## choose-last, as ever: choosing tears this scene down.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	var keycode := (event as InputEventKey).keycode
	match page:
		Page.TITLE:
			if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
				_handled()
				_go(Page.MODES)
		Page.MODES:
			match keycode:
				KEY_ESCAPE:
					_handled()
					_go(Page.TITLE)
				KEY_1, KEY_KP_1:
					_handled()
					_choose(GameMode.EXPEDITION)
				KEY_2, KEY_KP_2:
					_handled()
					_choose(GameMode.SANDBOX)
				KEY_3, KEY_KP_3:
					_handled()
					_choose(GameMode.DIVE)
		Page.WORKSHOP:
			if keycode == KEY_ESCAPE:
				_handled()
				_go(Page.TITLE)
		Page.BESTIARY:
			if keycode == KEY_ESCAPE:
				_handled()
				_go(Page.WORKSHOP)
		Page.CARDS:
			if keycode == KEY_ESCAPE:
				_handled()
				_go(Page.WORKSHOP)


## Mark the event consumed, tolerating a node that is already leaving the tree.
func _handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## Apply one mode — the LAST thing that runs, because after `choose_mode` this
## whole scene is on its way out (SceneTree.change_scene_to_file is deferred,
## but nothing here may touch `self` after asking for it — the v0.96.1 crash).
func _choose(mode: String) -> void:
	if world == null or not is_instance_valid(world) or not world.has_method("choose_mode"):
		# Loud rather than silent: a panel that quietly does nothing is the
		# worst front door there is.
		push_error("TitleScreen: no owner to choose a mode — the front door is inert")
		visible = true
		return
	visible = false
	world.call("choose_mode", mode)
