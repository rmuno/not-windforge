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
## BRIEF, NOT HIDDEN (owner 2026-09-05: "TOO MUCH INFORMATION EVERYWHERE… use a
## tooltip for the TMI bits"). Every row shows a short label in one fixed column
## (so the sliders line up) and carries the registry's `tip` as the tooltip on
## both halves; every button is an imperative verb with its explanation in its
## tooltip; the perf readout is one line with the whole cost picture behind it.
## Nothing is behind a fold — the owner playtests through this window, so one
## glance still shows every lever and every verb it has.
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
## The one Tunables group that shares a tab with the hardcoded player cheats
## instead of getting its own auto-tab — see _build (a same-named second tab
## collapsed to an unreadable "@ScrollContainer@NN" title).
const PLAYER_TAB := "Player"
## One label column for every lever row, so the sliders line up down the tab.
## Labels are capped at 28 characters in the registry and clipped here, so this
## width is a promise the rows cannot break.
const LABEL_W := 172.0


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


## How often the live readout re-samples. NOT every frame: this walks every
## ship and every promoted chunk, and the project has already paid once for a
## diagnostic that changed the thing it measured (the F3 whale diag,
## 2026-08-22). Four times a second is faster than anyone reads, and cheap
## enough to leave the window open while playing.
const PERF_SAMPLE := 0.25

var _perf_age := 0.0
## Counter values at the previous sample, for the per-second RATES — which are
## the numbers that actually explain a hitch (what rebuilt, what repainted),
## as opposed to the totals, which only say how long the session has run.
var _perf_prev := {}


func _process(delta: float) -> void:
	if not visible or _perf_label == null:
		return
	_perf_age += delta
	if _perf_age < PERF_SAMPLE:
		return
	# The tooltip carries the detail; the label is the one line read at a glance.
	# `_perf_text` advances the rate counters, so it runs ONCE per sample.
	_perf_label.tooltip_text = _perf_text(_perf_age)
	_perf_label.text = _perf_line()
	_perf_age = 0.0


# --- Build -----------------------------------------------------------------

func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.custom_minimum_size = Vector2(500, 560)
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
	_tabs.custom_minimum_size = Vector2(476, 500)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)

	# Player, Spawn, then one tab per Tunables group in registry order (Dive,
	# Combat, World, Whale — the Dive first because that is what the owner
	# playtests), then Perf. "Player" is the exception in the loop: it is folded
	# into the Player tab so the movement-feel levers and the player cheats share
	# ONE tab — and so a second TabContainer child named "Player" never collides
	# into an unreadable "@ScrollContainer@NN" tab title (the F2 bug, 2026-08-27).
	_build_player_tab()
	_build_spawn_tab()
	for group in Tunables.groups():
		if group == PLAYER_TAB:
			continue
		_build_lever_tab(group)
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
	var tip: String = str(row.get("tip", ""))
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 8)

	# The label is SHORT and clipped to one column width; everything the old long
	# label used to spell out is the tooltip now. A Label ignores the mouse by
	# default in Godot 4, so the filter is what makes its tooltip reachable.
	var name_label := Label.new()
	name_label.text = str(row["label"])
	name_label.custom_minimum_size = Vector2(LABEL_W, 0)
	name_label.clip_text = true
	name_label.tooltip_text = tip
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.add_theme_color_override("font_color", _FG)
	name_label.add_theme_font_size_override("font_size", 12)
	line.add_child(name_label)

	if row["kind"] == Tunables.KIND_BOOL:
		var check := CheckBox.new()
		check.button_pressed = Tunables.get_bool(id)
		check.tooltip_text = tip
		check.toggled.connect(func(on: bool) -> void: Tunables.set_value(id, on))
		_controls[id] = check
		line.add_child(check)
	else:
		var slider := HSlider.new()
		slider.min_value = float(row["min"])
		slider.max_value = float(row["max"])
		slider.step = float(row["step"])
		slider.value = Tunables.get_num(id)
		slider.tooltip_text = tip
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(120, 0)
		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(52, 0)
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

	# `note` rides the END of the row, dim — it says WHEN a change lands, which
	# is not part of the lever's name.
	if row.has("note"):
		var note := Label.new()
		note.text = str(row["note"])
		note.add_theme_color_override("font_color", _MUTED)
		note.add_theme_font_size_override("font_size", 10)
		line.add_child(note)

	box.add_child(line)


func _build_spawn_tab() -> void:
	var box := _add_tab("Spawn")
	_hint(box, "Everything here lands just to port of you (authority / single-player).")

	_section(box, "SPAWN")
	_action_button(box, "Spawn hulk",
		"A bandit hulk — hostile, and what most fights in the sky are made of.",
		func() -> void: _spawn("hulk"))
	_action_button(box, "Spawn whale", "One whale of a random variant.",
		func() -> void: _spawn("whale"))
	_action_button(box, "Spawn critter", "A small tameable critter.",
		func() -> void: _spawn("critter"))
	_action_button(box, "Spawn kraken", "A deep hunter — what a kraken den fields.",
		func() -> void: _spawn("kraken"))
	_action_button(box, "Spawn basilisk", "The top-band fire-spitter.",
		func() -> void: _spawn("basilisk"))
	_action_button(box, "Spawn the city-whale boss",
		"The Leviathan Arcology: the city-whale BOSS.",
		func() -> void: _spawn("boss"))
	_action_button(box, "Spawn whale carcass",
		"A corpse-airship bench — the hull a salvaged ship gets built out of.",
		func() -> void: _spawn("carcass"))
	_action_button(box, "Spawn my Loft ship",
		"Spawns the ship saved in the Blueprint Loft beside you. Board it or grapple it.",
		func() -> void: _spawn("loft"))
	# Paste a .ship from the Blueprint Loft and fly it straight away — no file
	# round-trip (owner 2026-08-27). Upscaled 8x + spawned beside you, faction 0.
	_hint(box, "…or paste a .ship and spawn that:")
	var paste := TextEdit.new()
	paste.placeholder_text = "paste .ship text here (origin line + glyph rows)…"
	paste.custom_minimum_size = Vector2(0, 96)
	paste.add_theme_font_size_override("font_size", 11)
	box.add_child(paste)
	_action_button(box, "Spawn pasted .ship",
		"Spawns the .ship text above beside you: upscaled to the world, faction 0, no file round-trip.",
		func() -> void:
			if world != null and not paste.text.strip_edges().is_empty():
				world.call("debug_spawn_text", paste.text, _spawn_pos()))

	# THE DIVE (Q-G). Every verb a run has, reachable from inside a live world:
	# standing order — a feature F2 cannot reach is invisible.
	_section(box, "DIVE")
	_action_button(box, "Start a dive",
		"Begins a roguelite run — eight depths down — without going back to the boot chooser.",
		func() -> void:
			if world != null and world.has_method("begin_dive"):
				world.call("begin_dive"))
	_action_button(box, "Try the 1x dive",
		"The same dive boot at world scale 1, a 64th of the blocks per ship — a lag experiment, not a mode. The starter flies slow relative to its world there.",
		func() -> void:
			if world != null:
				world.get_tree().change_scene_to_file("res://maps/dive/dive_1x.tscn"))
	# The 45-second timer that used to fire this is retired (v0.141.0): a run's
	# pressure is its standing garrison, so this button is the only way a wave
	# arrives — which is what A/Bs "garrison alone" against "garrison plus chase".
	_action_button(box, "Send a surge",
		"Flies a wave of hunters in from past the horizon, ahead of your travel. No-op outside a live run.",
		func() -> void:
			if world != null and world.has_method("_dive_surge"):
				world.call("_dive_surge"))
	_action_button(box, "Plant a Dive outpost",
		"Plants an outpost beside you; K opens its counter and 1-3 buy its stock.",
		func() -> void:
			if world != null and world.has_method("_plant_outpost"):
				world.call("_plant_outpost", _spawn_pos()))
	_action_button(box, "End the dive",
		"Abandons the run where it stands — no ledger, no bank.",
		func() -> void:
			if world != null and world.has_method("end_dive"):
				world.call("end_dive"))

	# THE DIVE CARDS (Q-L): the deck has to be playtestable without grinding kills.
	_section(box, "CARDS")
	_action_button(box, "Offer a card draft",
		"Offers a draft; pick it with 1/2/3. No-op outside a live run.",
		func() -> void:
			if world != null and world.has_method("debug_grant_card_draft"):
				world.call("debug_grant_card_draft"))
	_action_button(box, "Add 100 run XP",
		"Pours XP into the run so the card bar fills without grinding kills.",
		func() -> void:
			if world != null and world.has_method("debug_grant_dive_xp"):
				world.call("debug_grant_dive_xp", 100))
	_action_button(box, "Drop a scrap cloud",
		"Drops a kraken's worth of scrap just outside the absorption radius — fly into it to judge the magnet. The radius is Dive → Scrap pickup radius.",
		func() -> void:
			if world != null and world.has_method("debug_spawn_scrap"):
				world.call("debug_spawn_scrap"))
	# These cards change what a draft cannot be relied on to hand you — a widened
	# pool, a softer crash, a bounce, a reprieve — so one press deals the lot.
	_action_button(box, "Deal the survival suite",
		"Deals the whole survival hand at once: hull, bounce, reprieve (world.gd DEBUG_CARD_SUITE).",
		func() -> void:
			if world != null and world.has_method("debug_grant_card_suite"):
				world.call("debug_grant_card_suite"))
	# The title gallery is META, not run state — these two work outside a run.
	_action_button(box, "Reveal every card",
		"Fills the title screen's card gallery, so the page is playtestable without drafting the deck across a dozen runs.",
		func() -> void:
			if world != null and world.has_method("debug_reveal_cards"):
				world.call("debug_reveal_cards"))
	_action_button(box, "Forget every card", "Wipes the title card gallery back to empty.",
		func() -> void:
			if world != null and world.has_method("debug_forget_cards"):
				world.call("debug_forget_cards"))

	# The creature log (title-screen workshop, step 1).
	_section(box, "BESTIARY")
	_action_button(box, "Reveal every creature",
		"Fills the title bestiary with the whole roster, so the page is playtestable without hunting it first.",
		func() -> void:
			if world != null and world.has_method("debug_reveal_creatures"):
				world.call("debug_reveal_creatures"))
	_action_button(box, "Forget all creatures", "Wipes the bestiary log back to nothing met.",
		func() -> void:
			if world != null and world.has_method("debug_forget_creatures"):
				world.call("debug_forget_creatures"))

	_section(box, "WORLD")
	# Fire is not a spawnable body, but it has to be CAUSABLE on demand or it
	# cannot be playtested at all.
	_action_button(box, "Set the nearest ship alight",
		"Lights the nearest burnable body near the spawn point. The X wand douses it.",
		func() -> void: _ignite())
	_action_button(box, "Stir the deep",
		"+0.25 kraken ascendancy — one band per press, so the worldwide kraken surge is playtestable without hunting a whole pod.",
		func() -> void:
			if world != null and world.has_method("debug_stir_deep"):
				world.call("debug_stir_deep", 0.25))


func _build_player_tab() -> void:
	var box := _add_tab(PLAYER_TAB)

	_section(box, "CHEATS")
	# SANDBOX (owner 2026-08-28): the one-press "cut the fluff, play the meat"
	# button. Top of the tab — it is the fastest way into a focused session.
	_action_button(box, "Kit me out (sandbox)",
		"Opens every gate and grants the loadout: nothing scarce, no deep-air suffocation. Flips World → Sandbox on.",
		func() -> void:
			if world != null and world.has_method("debug_sandbox_loadout"):
				world.call("debug_sandbox_loadout"))
	_action_button(box, "Grant $1000", "Adds 1000 to your purse.",
		func() -> void:
			if world != null: world.call("debug_grant_money", 1000))
	_action_button(box, "Heal to full", "Refills the local player body's health.",
		func() -> void:
			if world != null: world.call("debug_heal_player"))
	_action_button(box, "Grant 3 of each balloon",
		"Three crafted balloons of every size. B selects one, Q tethers it.",
		func() -> void:
			if world != null: world.call("debug_grant_balloons", 3))
	_action_button(box, "Max all stats", "Raises every character stat to its cap.",
		func() -> void:
			if world != null: world.call("debug_max_stats"))

	_section(box, "SHIP")
	_action_button(box, "Export my ship",
		"Writes your hull to user://ships as a .ship blueprint and copies it to the clipboard.",
		func() -> void:
			if world != null and world.has_method("export_ship"):
				world.call("export_ship"))
	_action_button(box, "Bolt on a repair station",
		"Adds a repair station block to your ship. E runs it.",
		func() -> void:
			if world != null: world.call("debug_add_mender"))

	# The movement-FEEL levers (coyote/buffer/jump-cut/fall damage) live in the
	# "Player" Tunables group; their rows join this same tab, so everything
	# player-facing is in one place and no duplicate "Player" tab is built.
	if Tunables.groups().has(PLAYER_TAB):
		_section(box, "FEEL")
		for row in Tunables.in_group(PLAYER_TAB):
			_build_lever_row(box, row as Dictionary)


func _build_perf_tab() -> void:
	var box := _add_tab("Perf")
	# ONE LINE, the rest in its tooltip (owner 2026-09-05). The whole cost picture
	# is still sampled and still one hover away — it is just no longer a wall of
	# numbers the eye has to wade through to read the frame rate.
	_perf_label = Label.new()
	_perf_label.add_theme_color_override("font_color", _FG)
	_perf_label.add_theme_font_size_override("font_size", 13)
	_perf_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_perf_label.text = _perf_line()
	_perf_label.tooltip_text = _perf_text()
	box.add_child(_perf_label)
	_hint(box, "Hover the line for the full cost picture.")
	_action_button(box, "Toggle whale diagnostic",
		"The same overlay F3 toggles: what the whale brains are thinking.",
		func() -> void:
			if world != null: world.call("_toggle_whale_diag"))
	_action_button(box, "Reset all tunables",
		"Puts every lever in every tab back to its shipped default.",
		func() -> void: _reset_all())


func _hint(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _MUTED)
	l.add_theme_font_size_override("font_size", 11)
	box.add_child(l)


## A dim section header. A LABEL, not a collapsible: F2 is a dev tool, and one
## glance has to show everything it can do (owner 2026-09-05).
func _section(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _MUTED)
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)


## An action button: an imperative label (<= 28 chars, enforced by run_tests) and
## the explanation that used to live inside it, as the tooltip. The tip comes
## BEFORE the callable so a multi-line lambda can stay the last argument.
func _action_button(box: VBoxContainer, text: String, tip: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	box.add_child(b)


# --- Actions ---------------------------------------------------------------

func _spawn(kind: String) -> void:
	if world == null:
		return
	world.call("debug_spawn", kind, _spawn_pos())


## Light the nearest burnable body at the spawn point — the fire playtest hook.
func _ignite() -> void:
	if world != null and world.has_method("debug_ignite"):
		world.call("debug_ignite", _spawn_pos())


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


## THE ONE LINE the Perf tab actually shows: frame rate, the physics millisecond
## count that explains a hitch, how many ships are in the sim, and which build
## this is (a bug report without the version is half a report). Everything else
## `_perf_text` gathers is one hover away.
func _perf_line() -> String:
	var ships := 0
	if world != null:
		var fleet: Variant = world.get("fleet")
		if fleet != null and is_instance_valid(fleet):
			ships = (fleet.call("ships") as Array).size()
	return "%d fps · %.1f ms phys · %d ships · v%s" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		ships,
		str(ProjectSettings.get_setting("application/config/version", "dev"))]


## The live cost picture, in the owner's own session. Everything here is
## already counted somewhere for the tests; this is the one place it is
## visible while PLAYING, which is the only place a hitch can be reported
## from. The RATES block is the diagnostic half: a rebuild or a repaint storm
## is what a stutter is made of, and the totals cannot show a storm.
##
## `window` is the seconds since the last sample (0 on the first build, which
## simply prints the rates as 0).
func _perf_text(window := 0.0) -> String:
	var ships := 0
	var residents := 0   # site-spawned bodies alive — the charter §4 population
	var ship_cells := 0
	var tiles := 0
	var shots := 0
	var chunks := 0
	var chunk_cells := 0
	var t_regions := 0
	var now := {"ship_rebuilds": 0, "chunk_rebuilds": 0, "repaints": 0}

	if world != null:
		var fleet: Variant = world.get("fleet")
		if fleet != null and is_instance_valid(fleet):
			for s in (fleet.call("ships") as Array):
				var ship := s as Ship
				ships += 1
				if ship.from_spawn_site:
					residents += 1
				ship_cells += ship.blocks.size()
				tiles += ship.skin_tile_count()
				now["ship_rebuilds"] = int(now["ship_rebuilds"]) + ship.rebuild_count
				now["repaints"] = int(now["repaints"]) + ship.skin_repaints()
		var terrain: Variant = world.get("terrain")
		if terrain != null and is_instance_valid(terrain):
			for c in (terrain as Node).get_children():
				if c is TerrainChunk:
					var ch := c as TerrainChunk
					chunks += 1
					chunk_cells += ch.collider_cell_count()
					t_regions += ch.draw_region_count()
					now["chunk_rebuilds"] = int(now["chunk_rebuilds"]) + ch.rebuild_count
		var tree := world.get_tree()
		if tree != null:
			shots = tree.get_nodes_in_group("shots").size()

	var rates := ""
	for key in ["chunk_rebuilds", "ship_rebuilds", "repaints"]:
		var per_sec := 0.0
		if window > 0.0 and _perf_prev.has(key):
			per_sec = maxf(0.0, float(int(now[key]) - int(_perf_prev[key]))) / window
		rates += "\n  %-16s %6.1f" % [key.replace("_", " "), per_sec]
	_perf_prev = now

	# THE PHYSICS BLOCK. The owner's 3-FPS capture was a physics frame
	# overrunning its 16.67 ms budget, after which Godot runs up to 8 catch-up
	# steps per rendered frame -- so `phys` over ~16 is the number that matters
	# most on this panel, and pairs/active say why. Ship sets can_sleep=false,
	# so `active` never falls on its own: every ship is simulated forever,
	# near or far.
	var cen := PhysicsCensus.of_world(world)
	var physics := ("\n\nphysics  \u2014 over ~16 ms/frame and the engine starts"
		+ " catching up (8x)\n  broadphase pairs %-6d  active bodies %d, %d islands"
		+ "\n  ship shapes     %-6d  worst body %d shapes (%d cells), %d coarse"
		+ "\n  terrain bodies  %-6d  %d shapes"
		+ "\n  DORMANT bodies  %-6d  (out of the simulation, coasting)") % [
		cen["pairs"], cen["active"], cen["islands"],
		cen["shapes"], cen["worst"], cen["worst_cells"], cen["coarse"],
		cen["chunks"], cen["chunk_shapes"], cen["dormant"]]

	# WORLD-ANCHORED POPULATION (charter §4). Two numbers say whether sites are
	# doing their job: how many residents are out (against the global cap that
	# stops a tuning slip from filling the sky) and how many places the player
	# has actually charted.
	var sites := ""
	if world != null and world.has_method("discovered_sites"):
		sites = "
Sites:    %-6d  charted, %d/%d residents out" % [
			(world.call("discovered_sites") as Array).size(),
			residents, Tunables.get_int("site_max_residents")]
		# ECOLOGY (Q-C): how far the deep has risen from overhunting whales, and
		# what a kraken den fields right now because of it. The band label is the
		# same one the notices use, so the number and the story agree.
		var asc := float(world.get("kraken_ascendancy"))
		var bands := ["quiet", "stirring", "rising", "ASCENDANT"]
		var lvl: int = world.call("_eco_level_of", asc) if world.has_method("_eco_level_of") else 0
		var den: int = world.call("_kraken_surge_pool", SpawnSites.Kind.KRAKEN_DEN, 2) \
			if world.has_method("_kraken_surge_pool") else 2
		sites += "\nDeep:     %-6s  %d%% ascendant, kraken den fields %d" % [
			bands[clampi(lvl, 0, 3)], roundi(asc * 100.0), den]
	# CREATURE LOG (the title bestiary): how much of the roster has been met.
	if world != null and world.has_method("creature_log_status"):
		var cl: Dictionary = world.call("creature_log_status")
		sites += "\nBestiary: %-6s  creatures met" % ("%d/%d" % [
			int(cl.get("met", 0)), int(cl.get("total", 0))])
	# CARD LOG (the title gallery): how much of the deck has ever been drafted.
	if world != null and world.has_method("card_log_status"):
		var kl: Dictionary = world.call("card_log_status")
		sites += "\nCards:    %-6s  cards taken (ever)" % ("%d/%d" % [
			int(kl.get("taken", 0)), int(kl.get("total", 0))])

	# Retained rect COMMANDS: every merged region draws a fill and a border,
	# and the renderer replays both every frame forever. Terrain's regions are
	# cached (merged at rebuild) so this is a read; the ships' are not, so the
	# engine's own draw-call monitor stands in for them.
	# Fixed-width first column so the numbers stay in line as they change --
	# this is read at a glance, mid-flight, while something is going wrong.
	return ("FPS:      %-6d  process %.2f ms   physics %.2f ms"
		+ "\nDraws:    %-6d  nodes %d"
		+ "\nShips:    %-6d  %d cells in %d skin tiles"
		+ "\nTerrain:  %-6d  chunks, %d cells, %d regions (%d cmds)"
		+ "\nShots:    %-6d"
		+ "%s%s"
		+ "\n\nper second \u2014 what a hitch is made of%s") % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		ships, ship_cells, tiles,
		chunks, chunk_cells, t_regions, t_regions * 2,
		shots, sites, physics, rates]
