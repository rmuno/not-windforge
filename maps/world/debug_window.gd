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
## The one Tunables group that shares a tab with the hardcoded player cheats
## instead of getting its own auto-tab — see _build (a same-named second tab
## collapsed to an unreadable "@ScrollContainer@NN" title).
const PLAYER_TAB := "Player"


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
	_perf_label.text = _perf_text(_perf_age)
	_perf_age = 0.0


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
	# One tab per Tunables group (Whale, Combat, World, ...), built from the
	# registry. "Player" is the exception: it is folded into the Player tab below
	# so the movement-feel levers and the player cheats share ONE tab — and so a
	# second TabContainer child named "Player" never collides into an unreadable
	# "@ScrollContainer@NN" tab title (the owner's F2 bug, 2026-08-27).
	for group in Tunables.groups():
		if group == PLAYER_TAB:
			continue
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
	_action_button(box, "Spawn critter (small tameable)", func() -> void: _spawn("critter"))
	_action_button(box, "Spawn KRAKEN (deep hunter!)", func() -> void: _spawn("kraken"))
	_action_button(box, "Spawn BASILISK (spits fire)", func() -> void: _spawn("basilisk"))
	_action_button(box, "Spawn the CITY-WHALE BOSS (the Leviathan Arcology)",
		func() -> void: _spawn("boss"))
	_action_button(box, "Spawn whale CARCASS (corpse-airship bench)", func() -> void: _spawn("carcass"))
	# The creature log / bestiary (title-screen workshop, step 1): reveal or wipe
	# the met-creatures record so the title page is playtestable without hunting
	# the whole roster first (standing order — a feature F2 cannot reach is invisible).
	_action_button(box, "BESTIARY: reveal every creature (fills the title log)",
		func() -> void:
			if world != null and world.has_method("debug_reveal_creatures"):
				world.call("debug_reveal_creatures"))
	_action_button(box, "BESTIARY: forget all creatures (wipe the log)",
		func() -> void:
			if world != null and world.has_method("debug_forget_creatures"):
				world.call("debug_forget_creatures"))
	_action_button(box, "Spawn MY LOFT SHIP beside you (board it / grapple it)",
		func() -> void: _spawn("loft"))
	# Paste a .ship from the Blueprint Loft and fly it straight away — no file
	# round-trip (owner 2026-08-27). Upscaled 8x + spawned beside you, faction 0.
	_hint(box, "…or paste a .ship from the Blueprint Loft and spawn it:")
	var paste := TextEdit.new()
	paste.placeholder_text = "paste .ship text here (origin line + glyph rows)…"
	paste.custom_minimum_size = Vector2(0, 96)
	paste.add_theme_font_size_override("font_size", 11)
	box.add_child(paste)
	_action_button(box, "Spawn PASTED .ship beside you", func() -> void:
		if world != null and not paste.text.strip_edges().is_empty():
			world.call("debug_spawn_text", paste.text, _spawn_pos()))
	# Fire is not a spawnable body, but it is a thing the owner has to be able
	# to CAUSE on demand to playtest it at all (standing order: a feature F2
	# cannot reach is invisible).
	_action_button(box, "SET FIRE to the nearest ship (X douses it)",
		func() -> void: _ignite())
	# Ecology (Q-C): shove the deep's ascendancy up so the kraken surge is
	# playtestable without hunting a whole pod first. +0.25 = one band per press.
	_action_button(box, "STIR THE DEEP (+ecology: krakens surge worldwide)",
		func() -> void:
			if world != null and world.has_method("debug_stir_deep"):
				world.call("debug_stir_deep", 0.25))
	# THE DIVE (Q-G): start a run without going back to the boot chooser, so the
	# mode is playtestable from inside a live world (standing order — a feature
	# F2 cannot reach is invisible).
	_action_button(box, "START A DIVE (roguelite run: 8 depths down)",
		func() -> void:
			if world != null and world.has_method("begin_dive"):
				world.call("begin_dive"))
	_action_button(box, "Plant a Dive OUTPOST beside you (K trades at it)",
		func() -> void:
			if world != null and world.has_method("_plant_outpost"):
				world.call("_plant_outpost", _spawn_pos()))
	_action_button(box, "END the dive (abandon the run, no ledger)",
		func() -> void:
			if world != null and world.has_method("end_dive"):
				world.call("end_dive"))
	# THE DIVE CARDS (Q-L): offer a draft, or pour in XP to trigger one, so the deck
	# is playtestable without grinding kills. Both no-op outside a live run.
	_action_button(box, "DIVE CARD: offer a draft (pick with 1/2/3)",
		func() -> void:
			if world != null and world.has_method("debug_grant_card_draft"):
				world.call("debug_grant_card_draft"))
	_action_button(box, "DIVE CARD: +100 run XP (fills the card bar)",
		func() -> void:
			if world != null and world.has_method("debug_grant_dive_xp"):
				world.call("debug_grant_dive_xp", 100))


func _build_player_tab() -> void:
	var box := _add_tab(PLAYER_TAB)
	_hint(box, "Cheats for the local player body.")
	# SANDBOX (owner 2026-08-28): the one-press "cut the fluff, play the meat"
	# button — every gate open, nothing scarce, deep-air suffocation off. The full
	# crafting game is one toggle away (World → Sandbox). Top of the tab: it is the
	# fastest way to get into a focused session.
	_action_button(box, "SANDBOX: kit me out — open every gate, nothing scarce",
		func() -> void:
			if world != null and world.has_method("debug_sandbox_loadout"):
				world.call("debug_sandbox_loadout"))
	_action_button(box, "Grant $1000", func() -> void:
		if world != null: world.call("debug_grant_money", 1000))
	_action_button(box, "Heal to full", func() -> void:
		if world != null: world.call("debug_heal_player"))
	_action_button(box, "Grant 3 balloons of each size (B selects, Q tethers)",
		func() -> void:
			if world != null: world.call("debug_grant_balloons", 3))
	_action_button(box, "Max all stats", func() -> void:
		if world != null: world.call("debug_max_stats"))
	_action_button(box, "Bolt a REPAIR STATION onto your ship (E runs it)",
		func() -> void:
			if world != null: world.call("debug_add_mender"))
	# The movement-FEEL levers (coyote/buffer/jump-cut) live in the "Player"
	# Tunables group; their rows join this same tab, so everything player-facing
	# is in one place and no duplicate "Player" tab is built (see _build above).
	if Tunables.groups().has(PLAYER_TAB):
		for row in Tunables.in_group(PLAYER_TAB):
			_build_lever_row(box, row as Dictionary)


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
