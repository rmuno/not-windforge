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
##   CARDS    — the CARD GALLERY: one tile per card in the Dive's deck, grouped
##              by rarity, the ones you have actually drafted lit and the rest
##              dimmed. Also read from the profile (owner 2026-09-01: "the card
##              screen should display the individual known cards based on what
##              the user has selected... as cards not as a wall of text").
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

## The taken-cards set (id -> true) the CARDS page renders lit. Handed over the
## same way `discovered` is — the intro reads the profile once and passes both;
## this panel never touches disk and never sees a world. Empty = nothing drafted
## yet, and the whole gallery is dimmed (every card still legible).
var cards_taken := {}

## THE GALLERY'S SHAPE. Four columns of fixed tiles inside a scroll box: the deck
## is nineteen cards and the panel is a plain centred VBox with no scroll of its
## own, so a taller page simply ran off the bottom of a 720p window (the wall of
## text hit exactly this, which is why it was one line per card). Four × 196 plus
## the gaps is ~810 px wide and the box is capped at 430 px tall — the whole page,
## header and back button included, fits inside 720p with room to spare.
const GALLERY_COLUMNS := 4
const GALLERY_TILE := Vector2(196, 96)
const GALLERY_MAX_HEIGHT := 430.0

var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	# The preset is applied while the panel is EMPTY, so its offsets are ~zero
	# and the panel's top-left sat at the screen's centre — every page then hung
	# down-right (the owner's screenshotted "awkward"). Growing BOTH ways from
	# the centre anchor keeps the panel centred at whatever size a page needs.
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
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
##
## STANDARDIZED (owner 2026-09-01: "Text within the menus should be more
## standardized. There's TMI everywhere and text is centered instead of left
## aligned, so in a list it looks really awkward"): the TITLE stays centred (it
## is a title, not a list); every LIST is left-aligned terse rows; the three
## modes are CARDS — the name with a tiny description under it — with THE DIVE
## first (owner's order, and the keys follow the cards: 1 = the Dive now).
func _repaint() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()
	match page:
		Page.MODES:
			_label("  CHOOSE YOUR GAME  ", 15)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			_rows.add_child(row)
			_mode_card(row, "1", "THE DIVE", "a run. eight depths, one life",
				func() -> void: _choose(GameMode.DIVE))
			_mode_card(row, "2", "EXPEDITION", "the full open game",
				func() -> void: _choose(GameMode.EXPEDITION))
			_mode_card(row, "3", "SANDBOX", "kitted out, free build",
				func() -> void: _choose(GameMode.SANDBOX))
			_list_button("back", func() -> void: _go(Page.TITLE))
		Page.WORKSHOP:
			_label("  THE WORKSHOP  ", 15)
			_list_button("BESTIARY", func() -> void: _go(Page.BESTIARY))
			_list_button("CARD CODEX", func() -> void: _go(Page.CARDS))
			_list_button("SHIP BUILDER", func() -> void: _choose(GameMode.BUILDER))
			_list_button("MAP ROOM", func() -> void: _choose(GameMode.MAPROOM))
			_list_button("back", func() -> void: _go(Page.TITLE))
		Page.BESTIARY:
			_label(CreatureLog.bestiary_text(discovered), 13)
			_list_button("back", func() -> void: _go(Page.WORKSHOP))
		Page.CARDS:
			var deck: Array = DiveCards.gallery_rows(cards_taken)
			_label("  T H E   C A R D S  ", 15)
			_label("  %d of %d taken in your runs  "
				% [DiveCards.taken_count(cards_taken), deck.size()], 12)
			_card_gallery(deck)
			_list_button("back", func() -> void: _go(Page.WORKSHOP))
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


## A centred action — the TITLE page only; everywhere else is a list.
func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_rows.add_child(b)


## A list row: left-aligned, terse, no dash-explainers. The standard for every
## page that lists things (centred rows in a list were the owner's "awkward").
func _list_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_rows.add_child(b)


## One MODE CARD: the number chip, the name, a tiny description — clickable
## anywhere on the card. A real PanelContainer rather than a multiline Button
## so the three lines carry their own sizes and colours.
func _mode_card(row: Container, chip: String, mode_name: String, desc: String,
		cb: Callable) -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	style.border_color = Color(0.55, 0.62, 0.74, 0.7)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(180, 96)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var c := Label.new()
	c.text = "[%s]" % chip
	c.add_theme_font_size_override("font_size", 10)
	c.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
	col.add_child(c)
	var n := Label.new()
	n.text = mode_name
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 16)
	n.add_theme_color_override("font_color", Color(0.95, 0.83, 0.42))
	col.add_child(n)
	var d := Label.new()
	d.text = desc
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 11)
	d.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
	col.add_child(d)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			cb.call())
	row.add_child(card)


## THE CARD GALLERY — a scrolling column of rarity sections, each a grid of card
## tiles. `deck` is the model's plain rows (DiveCards.gallery_rows); this reads
## nothing else, so the page is exactly as truthful as that pure function
## (world-decides/layer-paints, with the catalog standing in for the world).
func _card_gallery(deck: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(
		float(GALLERY_COLUMNS) * GALLERY_TILE.x + float(GALLERY_COLUMNS + 1) * 8.0,
		GALLERY_MAX_HEIGHT)
	# Vertical only: the grid is sized to fit the width exactly, and a sideways
	# scrollbar on a page of cards reads as a layout bug.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	_rows.add_child(scroll)
	# The rows arrive already in tier order, so a change of rarity opens a new
	# section — no second pass over the catalog, and the grouping cannot disagree
	# with the model's order.
	var tier := ""
	var grid: GridContainer = null
	for row in deck:
		var r := row as Dictionary
		if String(r.get("rarity", "")) != tier:
			tier = String(r.get("rarity", ""))
			var head := Label.new()
			head.text = "  %s  " % String(r.get("rarity_label", tier.to_upper()))
			head.add_theme_font_size_override("font_size", 11)
			head.add_theme_color_override("font_color",
				Color(r.get("color", Color.WHITE) as Color, 0.85))
			col.add_child(head)
			grid = GridContainer.new()
			grid.columns = GALLERY_COLUMNS
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			col.add_child(grid)
		if grid != null:
			_card_tile(grid, r)


## ONE CARD TILE. The in-run picker's visual language, brought to the title
## (dive_hud._draw_draft): the rarity is the colour, and a rarer card wears a
## thicker, brighter frame, so the shape of your collection reads before a word
## of it does.
##
## TAKEN vs NOT is the second axis, and it is deliberately NOT a lock: an untaken
## card shows its name and exactly what it does, dimmed (the codex's doctrine —
## the deck is strategy, not a spoiler). The tick mark carries the same fact
## without colour, so the page still works if the dimming is hard to see.
func _card_tile(parent: Container, row: Dictionary) -> void:
	var taken := bool(row.get("taken", false))
	var tint := row.get("color", Color(0.88, 0.92, 1.0)) as Color
	var rare := String(row.get("rarity", "common")) != "common"
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	style.border_color = Color(tint, 0.85 if rare else 0.55)
	style.set_border_width_all(2 if rare else 1)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = GALLERY_TILE
	# A tile is a fact, not a button — nothing on this page is clickable, so it
	# keeps the arrow cursor and the page stays a display.
	if not taken:
		card.modulate = Color(1.0, 1.0, 1.0, 0.42)
	# The suite counts tiles and reads their ids through these (a headless test
	# cannot see a drawn card, and walking for Labels would count the headers too).
	card.set_meta("card_id", String(row.get("id", "")))
	card.set_meta("card_taken", taken)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)
	var n := Label.new()
	n.text = ("✓ " if taken else "·  ") + String(row.get("name", ""))
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", tint)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	var tier_word := Label.new()
	tier_word.text = String(row.get("rarity_label", ""))
	tier_word.add_theme_font_size_override("font_size", 8)
	tier_word.add_theme_color_override("font_color", Color(tint, 0.7))
	top.add_child(tier_word)
	var d := Label.new()
	d.text = String(row.get("desc", ""))
	d.add_theme_font_size_override("font_size", 10)
	d.add_theme_color_override("font_color", Color(0.78, 0.82, 0.90))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(GALLERY_TILE.x - 24.0, 0.0)
	col.add_child(d)
	parent.add_child(card)


## Every card tile currently on screen, as {id, taken} rows. The suite's handle on
## the gallery — asked through a method rather than by walking the tree from a
## test, so the panel owns how a tile is recognised.
func card_tiles() -> Array:
	var out: Array = []
	_collect_tiles(self, out)
	return out


func _collect_tiles(node: Node, out: Array) -> void:
	# A repaint queue_frees the old page and builds the new one in the SAME frame,
	# so the previous page's tiles are still children until the tree catches up.
	# Skipping the doomed ones is what makes this an answer about what is on
	# screen rather than about how many times the page has been opened.
	if node.is_queued_for_deletion():
		return
	if node.has_meta("card_id"):
		out.append({"id": String(node.get_meta("card_id")),
			"taken": bool(node.get_meta("card_taken"))})
	for child in node.get_children():
		_collect_tiles(child, out)


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
			# The keys follow the CARDS' order — the Dive is first (owner
			# 2026-09-01), so 1 is the Dive now.
			match keycode:
				KEY_ESCAPE:
					_handled()
					_go(Page.TITLE)
				KEY_1, KEY_KP_1:
					_handled()
					_choose(GameMode.DIVE)
				KEY_2, KEY_KP_2:
					_handled()
					_choose(GameMode.EXPEDITION)
				KEY_3, KEY_KP_3:
					_handled()
					_choose(GameMode.SANDBOX)
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
