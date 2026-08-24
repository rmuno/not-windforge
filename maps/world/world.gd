extends Node2D

## Sprint 1 harness: terrain to crash into, a ship per player, and enough
## on-screen numbers to tune flight feel. Deliberately throwaway — the real
## world streams chunks and is authored, not built in _ready().
##
## Multiplayer: press H to host, J to join localhost, or launch with
## `-- --server` / `-- --client [address]`.

## World-scale experiment (WORLD_SPEC.md → scale): 1 is the shipped game.
## scale_test.tscn sets 8 — the same harness with the blueprint upscaled
## 8×, the player 8 cells tall, and every world distance multiplied. The
## L key toggles between the two scenes so the comparison is one keypress.
@export var world_scale := 1
@export var camera_zoom := 0.9
## How much further the view pulls back at the helm (owner-tuned per scene).
@export var pilot_zoom_out := 1.3

## Scroll-wheel zoom: a user multiplier on top of the scene defaults,
## clamped to ±50% of them (owner's first guess at the range).
var _zoom_user := 1.0

const SHIP_START := Vector2(0, -200)

## You wake up inside the cabin, AT the controls (the helm is furniture —
## standing in its cell reads as manning the panel). Moved off the old
## midpoint between door and helm when doors gained a closed state: spawn
## must be unambiguously the helm's spot, so F right after waking boards
## rather than working the door. Kept as a cell so it stays correct if
## CELL or the starter layout changes.
const PLAYER_SPAWN_CELL := Vector2i(3, -1)

## How tall the player stands, in cells, in the scale experiment — the
## owner-observed height in the original, and the number under test.
const SCALED_PLAYER_CELLS := 8.0

var _ship_spacing := 260.0

## Weapons are cooldown-based — no ammo anywhere (DECISIONS 2026-08-18).
const SHOOT_COOLDOWN := 0.18
const TURRET_COOLDOWN := 0.5
var _shoot_cooldown := 0.0
var _turret_cooldown := 0.0

## Fall past this and you are dead. The original lets you jump off and die in
## the first minute, which is worth keeping — but falling *forever* is not
## death, it is a softlock.
var WORLD_BOTTOM := 2200.0

# (Camera is hard-locked to the player — no lead, no smoothing. A velocity-
# leading camera was tried and vetoed by the owner: it reads as the camera
# "following motion". See docs/DECISIONS.md.)

var fleet: Fleet
var crew: Crew
var camera: Camera2D
## Top-left status panel: ship stats WHILE PILOTING only (and the connecting /
## no-ship messages). Empty on foot in single-player — the decluttered screen
## (owner 2026-08-22). Kept named `hud` so nothing downstream breaks.
var hud: Label
## Small, gray bottom-right corner: build number + FPS, plus the one always-on
## trace of everything that moved to a toggle ("F1 help   Tab map").
var _corner_label: Label
## Controls + block legend, hidden by default, shown on F1 (the old 13-line
## always-on legend and the giant control line, folded into ONE on-demand panel).
var _help_panel: PanelContainer
## The scroller inside the help panel + its label — kept so the panel can be
## height-capped to the viewport when opened (it must never run off screen).
var _help_scroll: ScrollContainer
var _help_label: Label
## The calm HUD layer (maps/world/hud_layer.gd): reticle + inventory swatches +
## the contextual cue bar, drawn in screen space, all fed from this node.
var _hud_layer: HudLayer
## The deep-band ember haze (maps/world/deep_fog.gd): a screen-space wash that
## thickens as you descend. Under the HUD, over the world; driven by fog_density().
var _deep_fog: DeepFog

## Which balloon SIZE the attach key (U) bolts on (Ship.BalloonSize; Y cycles it).
## Carcass-as-airship: aim at a hull/corpse cell + U to tether a helium balloon.
var _balloon_size := 0
## The toggled world map (maps/world/map_view.gd), opened with Tab. Hidden by
## default; reads the fog-of-war model below.
var _map_view: MapView
## The toggled character sheet (maps/world/character_sheet.gd), opened with K.
## Hidden by default (the calm screen); doubles as the trainer shop while a
## trainer is in reach. Reads the model this node builds (character_sheet_model).
var _character_sheet: CharacterSheet
## The trainer station (rpg/trainer.gd): where you spend money to raise a stat and
## sell your salvage. A world marker planted near spawn in the throwaway harness;
## real trainers belong to towns (Phase 6). Single-player / host only.
var _trainer: Trainer
## Fog-of-war discovery (maps/world/map_discovery.gd): which coarse regions have
## been charted. Revealed each frame from the same foci that stream terrain.
var _discovery: MapDiscovery
## Rolling buffer of recently pressed keycodes, for the hidden Konami salute
## (maps/world/easter_eggs.gd). Passive — never consumes the keys.
var _konami_recent: Array = []
## The lift-before/after readout that floats at the mouse while the build
## ghost is up. A screen-space Label rather than world-space text: the ghost
## is one 16px cell, and world text sized to match it would be unreadable
## (or, sized to be readable, absurd next to the cell it describes).
var _ghost_label: Label
## Live whale/collision diagnostic (F3). See maps/world/whale_diag.gd. The
## on-screen indicator shows the owner it is recording and where the log lands.
var _whale_diag: WhaleDiag
var _diag_label: Label
## The dev-facing tabbed debug window (maps/world/debug_window.gd), toggled with
## F2. Hidden by default; spawns enemies on demand and exposes the Tunables levers
## for live tuning. Single-player / host dev tool.
var _debug_window: DebugWindow
## Floating collision-damage numbers (maps/world/damage_numbers.gd), coalesced
## per source. Fed by each ship's `collision_damage` signal, drawn by the
## WorldOverlay above the hulls. Pure data here; nothing to free.
var _damage_numbers: DamageNumbers
## Instance ids whose `collision_damage` signal is already wired. A bound
## callable never compares equal to its base, so this set guards the lazy
## per-frame wiring (same trick as `_enemy_watched`).
var _collision_watched := {}
## Instance ids of player bodies whose `died` signal is already wired. The local
## body can be re-created (respawn through the spawner on host, replication on
## join), so the wiring is lazy per-frame and guarded by id — same trick as
## `_collision_watched`.
var _player_death_watched := {}
## Floating "+1 Stone" pickup numbers that pop when you mine a cell
## (maps/world/pickup_floats.gd). Pure data here; drawn by the WorldOverlay.
var _pickups: PickupFloats
var build_type: int = BlockDB.Type.HULL
var local_ship: Ship = null
var player: Player = null

## USER-FACING SAVE / LOAD (save/save_game.gd). F5 quicksaves the session; F9
## toggles a saves panel (name / timestamp / playtime / location) and loads the
## selected slot. Single-player / host only — a client shares the host's world.
## `_playtime` is the wall-clock time played, accumulated every frame and carried
## across a load so the metadata keeps counting from where the save left off.
var _playtime := 0.0
const QUICKSAVE_NAME := "quicksave"
## The toggled saves panel (built in _ready like the help panel), and the row the
## player has highlighted for load (Up/Down move it, Enter loads it).
var _save_panel: PanelContainer
var _save_panel_label: Label
var _save_selected := 0

## The world is a BOUNDED box so flying can't drift off into endless empty sky —
## but the box now FRAMES THE WHOLE GENERATED WORLD (IslandGen.WORLD_CELLS), not
## the tiny Sprint-1 arena, so every generated island is reachable. Left/right
## walls + a ceiling are static rects (computed from the world rect in _ready);
## there is no floor wall — falling past the deepest island respawns you
## (WORLD_BOTTOM), never a forever-drop. The floor and slabs are gone: the
## resident, DESTRUCTIBLE terrain (`terrain` below) generates real floating
## islands you fly to and mine, promoted/demoted as you move.
var _terrain_rects: Array[Rect2] = []

## The world px rect the boundary walls + hazards frame (set in _ready from
## IslandGen.WORLD_CELLS at this scale). Kept so on-foot systems can read a live
## altitude fraction — Airspace.bounds is generation-only and empty in flight, so
## the deep-air gate (LifeSupport) computes its fraction from this, exactly as
## Hazards does. Empty until _ready runs → altitude reads -1 (breathable).
var _world_rect := Rect2()

## Deep-air suffocation cooldown for the LOCAL player (player/life_support.gd). The
## world owns the one local body, so its breath-timer lives here; LifeSupport.tick
## counts it down and re-arms it. Off-cost: only advances while the person is in
## unbreathable air unprotected (see _update_suffocation).
var _suffocate_cd := 0.0

## The seed that selects the world. A fixed seed → a fixed, reproducible world
## (tests pin it; play is repeatable). Overridable per-scene / by the owner.
@export var world_seed: int = IslandGen.DEFAULT_SEED

## The resident destructible world (terrain/terrain.gd): ONE data grid, chunks
## promoted to live colliders+rendering only near a focus (player/ship), demoted
## on leave — no loading screens (DECISIONS 2026-08-18). Generated below into a
## floor + a couple of floating slabs; mining (dig→item) is the next chunk.
var terrain: Terrain = null

## Environmental hazards (maps/world/hazards.gd): meteors sweep the TOP band, the
## lava core erupts from the FLOOR. Band-gated, world-anchored, and OFF-cost away
## from a hazard band — the arena spawn is mid-band, so this never fires during
## the normal startup/pilot flow. Driven (authority-gated) from _physics_process.
var _hazards: Hazards = null

## The earth's core (maps/world/lava_core.gd): the bottom slice of the world is a
## molten sea. Rendered behind the ships; the world's _update_lava_core does the
## lethal check (any ship or person touching it is consumed) against the same
## geometry. Created in _ready from the framed world rect.
var _lava_core: LavaCore = null


func _ready() -> void:
	# Frame the whole generated world (IslandGen.WORLD_CELLS) in world px at this
	# scale, then bound it with walls + a ceiling. cell_px = CELL × world_scale.
	var cp := TerrainDB.CELL * world_scale
	var wr := IslandGen.WORLD_CELLS
	var wpx := Rect2(Vector2(wr.position) * cp, Vector2(wr.size) * cp)
	_world_rect = wpx   # kept for the on-foot altitude read (deep-air gate)
	var t := 4.0 * cp   # wall thickness (a few cells)
	_terrain_rects = [
		Rect2(wpx.position.x - t, wpx.position.y - t, t, wpx.size.y + 2.0 * t),  # left wall
		Rect2(wpx.end.x, wpx.position.y - t, t, wpx.size.y + 2.0 * t),           # right wall
		Rect2(wpx.position.x - t, wpx.position.y - t, wpx.size.x + 2.0 * t, t),  # ceiling
	]
	_ship_spacing *= world_scale
	# Fall past the world floor and you respawn (no forever-drop); no floor wall,
	# so the deep band is reachable, and the backstop sits just below it.
	WORLD_BOTTOM = wpx.end.y + 8.0 * cp

	_build_terrain()
	_build_generated_terrain()

	# Environmental hazards over this scale's world rect (meteors up top, lava at
	# the floor). Reuses the same world px rect the boundary walls framed above +
	# Airspace band fractions; band-gated + OFF-cost, driven from _physics_process.
	_hazards = Hazards.new()
	_hazards.name = "Hazards"
	_hazards.world_rect = wpx
	_hazards.scale_unit = float(world_scale)
	_hazards.terrain = terrain
	add_child(_hazards)

	# The earth's core: a molten lava sea filling the bottom slice of the world.
	# Rendered behind everything; the lethal check lives in _update_lava_core.
	_lava_core = LavaCore.new()
	_lava_core.name = "LavaCore"
	_lava_core.world_rect = wpx
	_lava_core.scale_unit = float(world_scale)
	add_child(_lava_core)

	fleet = Fleet.new()
	fleet.name = "Fleet"
	add_child(fleet)

	crew = Crew.new()
	crew.name = "Crew"  # same node path on every peer — the spawner needs it
	add_child(crew)

	_damage_numbers = DamageNumbers.new()
	_pickups = PickupFloats.new()

	var overlay := WorldOverlay.new()
	overlay.world = self
	add_child(overlay)

	camera = Camera2D.new()
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	add_child(camera)
	camera.make_current()

	# --- Fog-of-war model + the map/HUD layers -----------------------------
	# The decluttered screen (owner 2026-08-22): a calm world, a reticle, a
	# couple of contextual cues, a small status corner — everything else on a
	# toggle. See maps/world/hud_layer.gd, map_view.gd, map_discovery.gd.
	_discovery = MapDiscovery.new()
	if terrain != null:
		# One map-cell == one COARSE terrain chunk. ×subdiv keeps the map-cell a
		# constant PX size at any terrain resolution (at subdiv 8 a raw chunk is
		# 8× smaller, and per-chunk map cells would octuple the fog granularity
		# and the draw cost); "does this region hold land?" buckets fine chunks
		# down to this grid in MapView.
		_discovery.cell_px = terrain.chunk_px() * terrain.subdiv
		_discovery.reveal_radius = terrain.chunk_px() * terrain.subdiv * 2.5

	var layer := CanvasLayer.new()

	# The deep-band ember haze — FIRST child of the HUD layer so it draws OVER the
	# world but UNDER every HUD element (health, cues, the map stay readable through
	# the murk). Silent above the deep band (fog_density 0). Screen-space, so it
	# does not scale with the world zoom.
	_deep_fog = DeepFog.new()
	_deep_fog.world = self
	layer.add_child(_deep_fog)

	# Top-left status: ship stats WHILE PILOTING only (and connecting/no-ship).
	# Empty on foot in single-player — the wall of always-on stats is gone.
	hud = Label.new()
	hud.position = Vector2(12, 10)
	hud.add_theme_color_override("font_color", Color(0.90, 0.93, 1.0, 0.92))
	hud.add_theme_font_size_override("font_size", 13)
	layer.add_child(hud)

	# The calm HUD: reticle + inventory swatches + contextual cue bar.
	_hud_layer = HudLayer.new()
	_hud_layer.world = self
	layer.add_child(_hud_layer)

	# The toggled world map, hidden until Tab.
	_map_view = MapView.new()
	_map_view.world = self
	_map_view.terrain = terrain
	_map_view.discovery = _discovery
	layer.add_child(_map_view)

	# The toggled character sheet, hidden until K — the RPG progression + shop.
	_character_sheet = CharacterSheet.new()
	_character_sheet.world = self
	layer.add_child(_character_sheet)

	# The on-demand help panel: the old 13-line legend and the giant control
	# line, folded into ONE panel that is HIDDEN by default and shown on F1.
	_help_panel = _build_help_panel()
	layer.add_child(_help_panel)

	# The saves panel (F9): the list of saves with their metadata, hidden by
	# default. Built once; only its visibility and text change.
	_save_panel = _build_save_panel()
	layer.add_child(_save_panel)

	# Build readout, floated at the cursor. Hidden until the ghost is up.
	_ghost_label = Label.new()
	_ghost_label.add_theme_font_size_override("font_size", 13)
	_ghost_label.visible = false
	layer.add_child(_ghost_label)

	# Small, gray corner status, bottom-right: build + FPS, and the one always-on
	# trace of what moved to a toggle ("F1 help   Tab map").
	_corner_label = Label.new()
	_corner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_corner_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_corner_label.add_theme_font_size_override("font_size", 11)
	_corner_label.add_theme_color_override("font_color", Color(0.58, 0.60, 0.66, 0.85))
	_corner_label.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	layer.add_child(_corner_label)

	# Whale diagnostic recording indicator, centred along the top. Hidden
	# until F3 turns recording on; red so it reads as "REC".
	_whale_diag = WhaleDiag.new()
	_diag_label = Label.new()
	_diag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diag_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.32))
	_diag_label.add_theme_font_size_override("font_size", 13)
	_diag_label.visible = false
	_diag_label.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	layer.add_child(_diag_label)

	add_child(layer)

	# The dev debug window (F2): its own CanvasLayer (above the HUD), hidden until
	# toggled. Built last so `world` is fully wired before it can call a spawn verb.
	_debug_window = DebugWindow.new()
	_debug_window.world = self
	add_child(_debug_window)

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	# A client joining a session throws away its offline body — the server
	# spawns a replicated one for every peer, this machine included.
	multiplayer.connected_to_server.connect(_on_connected_to_server)

	_handle_cmdline()
	# You always start aboard a ship — single-player must never wait for one.
	# Only a client that is still connecting has nothing yet.
	if not Net.is_online():
		_give_ship_to(1)
		_spawn_enemy_hulk()
		_spawn_whale()
		_spawn_critters()
		_spawn_kraken()
		_spawn_trainer()

	# You are a person, not a ship. Spawn standing on the deck, as the original
	# does — see docs/ORIGINAL_PLAYTEST.md, "the opening sequence". Spawning
	# goes through Crew so the same body replicates when a session is live.
	if not Net.is_online() or Net.is_server():
		player = crew.spawn_player(_my_id(), _spawn_offset(), _player_scale_mult())


## Where the player stands relative to their ship, at any world scale.
func _spawn_offset() -> Vector2:
	return SHIP_START + Vector2(PLAYER_SPAWN_CELL) * Ship.CELL * world_scale


## The body multiplier for the world-scale experiment: a person
## SCALED_PLAYER_CELLS tall instead of the shipped ~1.1 cells. Timing is
## identical at any scale (scale_body multiplies gravity too) — only
## distances grow. 18.0 is the unscaled body height (player.gd SIZE).
func _player_scale_mult() -> float:
	if world_scale <= 1:
		return 1.0
	return SCALED_PLAYER_CELLS * Ship.CELL / 18.0


# --- Help / map toggles (the decluttered screen) ---------------------------

## The on-demand controls + block-legend panel. Everything that used to sit
## always-on (the 13-line legend + the giant control line) folded into ONE panel,
## hidden by default and shown on F1. Built once; only its visibility toggles.
func _build_help_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	# TOP-left, not centre-left: anchored to the centre the panel began halfway
	# down the screen (owner 2026-08-23: "it starts about half way down the Y
	# axis"). Pin it near the top-left corner and let it grow down, scrolling when
	# it would overrun the viewport.
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.92)
	sb.border_color = Color(0.35, 0.42, 0.52, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	# The controls list can be taller than a small window, so it lives in a
	# ScrollContainer that is height-capped to the viewport when opened (owner
	# 2026-08-23: "the F1 info window exceeds screen size — it could scroll").
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var label := Label.new()
	label.add_theme_color_override("font_color", Color(0.85, 0.89, 0.96))
	label.add_theme_font_size_override("font_size", 13)
	label.text = "\n".join([
		"CONTROLS   (F1 to close)",
		"A/D walk    Space jump    F use helm / door",
		"LMB shoot (turrets at the helm)    RMB grapple — W/S reel, jump to sling",
		"grapple a whale + hold to TAME it (needs LORE Beast Whisperer) — then WASD steers; release the hook (RMB) to let go",
		"Z mine / harvest (hold + aim)    X repair (hold + sweep)",
		"V place terrain    B cycle material    N cycle recipe    M craft",
		"U tether a helium balloon (aim at a hull/corpse cell)    Y balloon size — fly a carcass!",
		"the DEEP band's air is unbreathable — craft & carry an Aether Lung (N/M) or you suffocate",
		"Q build hull    C remove    E cycle block    G damage",
		"K character sheet (stats/perks/money — trainer shop when nearby)",
		"  at a trainer, with the sheet open: 1-4 train a stat    0 sell salvage",
		"Tab map    T respawn    R reset world    Esc quit    wheel zoom",
		"F5 save    F9 saves panel (Up/Down select, Enter load)",
		"H host    J join localhost    F2 debug window    F3 diagnostic",
		"",
		"SHIP BLOCKS",
		"H helm (F pilots)    E engine (power)    P/V propeller    T turret",
		"D door (F opens/closes; closed stops bullets AND bodies)    | strut",
		"thin plank = platform — S+jump drops through",
		"pale = gasbag (lift)    pink = blubber    dark = ballast",
		"pink/red beast = sky whale — neutral; shoot it and it RAMS",
	])
	scroll.add_child(label)
	_help_scroll = scroll
	_help_label = label
	return panel


func _toggle_help() -> void:
	if _help_panel == null:
		return
	_help_panel.visible = not _help_panel.visible
	if _help_panel.visible:
		_cap_help_height()


## Cap the help scroller to the visible viewport (minus a margin) so the panel
## always fits and scrolls the overflow, but shrink to the content when it is
## shorter than the cap (no empty reserved space). Also (re)sets the font to a
## legible size for the current viewport — the fixed 13 px read as tiny on a
## hi-dpi display (owner 2026-08-23: "the F1 UI is still basically illegible").
## Done on open, when the viewport size is current.
func _cap_help_height() -> void:
	if _help_scroll == null or _help_label == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var ui := clampi(int(round(vp.y / 900.0)), 1, 3)
	_help_label.add_theme_font_size_override("font_size", 15 * ui)
	var cap := maxf(160.0, vp.y - 96.0)
	var content := _help_label.get_combined_minimum_size().y
	_help_scroll.custom_minimum_size.y = minf(cap, content)


func _toggle_map() -> void:
	if _map_view != null:
		_map_view.toggle()


func _toggle_character_sheet() -> void:
	if _character_sheet != null:
		_character_sheet.toggle()


# --- Save / load (save/save_game.gd) ---------------------------------------
#
# F5 quicksaves; F9 toggles the saves panel and loads the highlighted slot.
# Single-player / host only — on a client the world is the host's to persist.
# The heavy lifting (format, terrain seed+diffs, ship payloads, player state)
# lives in SaveGame; the world drives the scene-side rebuild (re-crewing
# hostiles, re-binding the local ship/player, resetting per-ship AI state).

## Can this peer save/load? Always in single-player; the host in a session; never
## a client (it does not own the world).
func _can_persist() -> bool:
	return not Net.is_online() or Net.is_server()


func _build_save_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.94)
	sb.border_color = Color(0.35, 0.42, 0.52, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(16)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	_save_panel_label = Label.new()
	_save_panel_label.add_theme_color_override("font_color", Color(0.85, 0.89, 0.96))
	_save_panel_label.add_theme_font_size_override("font_size", 13)
	panel.add_child(_save_panel_label)
	return panel


func _toggle_save_panel() -> void:
	if _save_panel == null:
		return
	_save_panel.visible = not _save_panel.visible
	if _save_panel.visible:
		_save_selected = 0
		_refresh_save_panel()


## Draw the saves list into the panel with the highlighted row marked. Read fresh
## from disk each time it opens (SaveGame.list_saves reads only headers — no full
## restore), so the metadata is always current.
func _refresh_save_panel() -> void:
	if _save_panel_label == null:
		return
	var saves := SaveGame.list_saves()
	_save_selected = clampi(_save_selected, 0, maxi(0, saves.size() - 1))
	var lines: Array = ["SAVES   (F9 close · Up/Down select · Enter load · F5 save)", ""]
	if saves.is_empty():
		lines.append("  (no saves yet — press F5 to save)")
	else:
		for i in saves.size():
			var s: Dictionary = saves[i]
			var marker := "> " if i == _save_selected else "  "
			var mins := int(float(s["playtime"]) / 60.0)
			var secs := int(float(s["playtime"])) % 60
			var tag := "" if s["valid"] else "   [unreadable]"
			lines.append("%s%s   %s   %dm%02ds   %s%s" % [
				marker, s["name"], s["timestamp_str"], mins, secs, s["location"], tag])
	_save_panel_label.text = "\n".join(lines)


func _save_panel_navigate(step: int) -> void:
	var count := SaveGame.list_saves().size()
	if count == 0:
		return
	_save_selected = clampi(_save_selected + step, 0, count - 1)
	_refresh_save_panel()


func _load_selected() -> void:
	var saves := SaveGame.list_saves()
	if saves.is_empty() or _save_selected >= saves.size():
		return
	var chosen: Dictionary = saves[_save_selected]
	if not chosen["valid"]:
		_notify("cannot load %s — unreadable save" % chosen["name"])
		return
	if load_game(chosen["name"]):
		if _save_panel != null:
			_save_panel.visible = false


## Quicksave the session to a fixed slot. Returns false (and notifies) if this
## peer cannot persist or the write failed.
func save_game(name := QUICKSAVE_NAME) -> bool:
	if not _can_persist():
		_notify("cannot save — only the host saves a session")
		return false
	var data := SaveGame.capture(self, name, _playtime)
	if not SaveGame.save_to(name, data):
		_notify("save failed — could not write the file")
		return false
	_notify("saved: %s" % name)
	return true


## Load a save by name, rebuilding the world. Returns false — leaving the game
## valid and untouched — if this peer cannot persist, the file is missing/corrupt,
## or its format is unsupported (graceful failure, never a crash).
func load_game(name: String) -> bool:
	if not _can_persist():
		_notify("cannot load — only the host loads a session")
		return false
	var data := SaveGame.load_from(name)
	if data.is_empty():
		_notify("load failed — %s is missing or corrupt" % name)
		return false
	if not SaveGame.restore(self, data):
		_notify("load failed — %s is an unsupported save version" % name)
		return false

	# Scene-side fix-up after the data restore (NPCs / camera / AI are the world's
	# domain, not the save format's). Old per-ship AI + crew referenced ships that
	# were just freed; clear them and re-crew the hostiles from the loaded fleet.
	_playtime = float(data.get("playtime", _playtime))
	_reset_after_load()
	_notify("loaded: %s" % name)
	return true


## Rebuild the transient scene state a load invalidates: drop per-ship AI/aggro
## keyed by the freed ships' ids, free stale NPCs, re-crew hostiles so their guns
## and helms work again, and re-bind the local ship/player references.
func _reset_after_load() -> void:
	_ship_ais.clear()
	_whale_ais.clear()
	_enemy_cooldowns.clear()
	_enemy_aggro.clear()
	_enemy_provoked_at.clear()
	_enemy_watched.clear()
	_collision_watched.clear()
	# NOT _player_death_watched: unlike ships (freed and respawned on load), the
	# player instance PERSISTS across a load (apply_player restores onto the same
	# body). Clearing it here would drop the guard while the `died` signal is still
	# connected, and the next frame's re-wire would raise "already connected".

	for npc in _npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_npcs.clear()

	# Re-crew hostiles: a driver at the helm, a gunner at the turret (the same
	# crewing the hulk gets at spawn). Faction-1 ships only; wildlife and the
	# player's own ship carry no crew. _spawn_crewman no-ops if the station is
	# absent, so a helmless/gunless hostile just stays uncrewed.
	if fleet != null:
		for ship in fleet.ships():
			if is_instance_valid(ship) and ship.faction == 1:
				_spawn_crewman(ship, "H", "driver")
				_spawn_crewman(ship, "T", "gunner")

	_refresh_local_ship()
	_refresh_local_player()


## Small transient feedback (a floating line over the player), reusing the pickup
## floats — no new HUD chrome for an occasional save/load message.
func _notify(text: String) -> void:
	if _pickups == null:
		return
	var at := SHIP_START
	if player != null and is_instance_valid(player):
		at = player.global_position
	_pickups.add(at, text, float(world_scale))


# --- The RPG progression + trainer shop ------------------------------------
#
# The character sheet (K) is the shop panel: while it is open and a trainer is in
# reach, 1–4 buy a stat level and 0 sells salvage. The KEY handlers below gate on
# the sheet being open; the try_* verbs gate on the trainer being in reach — split
# out (like try_mine / try_craft) so the buy/sell logic is testable without keys.

## Is the player standing at a trainer? The gate on every buy/sell.
func _near_trainer() -> bool:
	return _trainer != null and is_instance_valid(_trainer) \
		and player != null and is_instance_valid(player) \
		and _trainer.in_reach(player.global_position)


## Buy one level of stat index `i` (StatDB.names() order) from the trainer. Refuses
## off a trainer, maxed, or broke — Training.train enforces the money/cap rules.
func try_train(stat_index: int) -> bool:
	if not _near_trainer() or player == null or not is_instance_valid(player):
		return false
	var order: Array = StatDB.names()
	if stat_index < 0 or stat_index >= order.size():
		return false
	var stat: int = order[stat_index]
	var ok := Training.train(player.stats, player.wallet, stat)
	if ok and _pickups != null:
		_pickups.add(player.global_position,
			"%s L%d" % [StatDB.stat_name(stat), player.stats.level_of(stat)],
			float(world_scale))
	return ok


## Sell all salvage in the pack for money at the trainer (LORE trade bonus
## applied). Returns the money earned; 0 (and nothing sold) off a trainer or with
## nothing sellable.
func try_sell_salvage() -> int:
	if not _near_trainer() or player == null or not is_instance_valid(player):
		return 0
	var gained := Economy.sell_all(player.inventory, player.stats.trade_bonus())
	if gained > 0:
		player.wallet.add(gained)
		if _pickups != null:
			_pickups.add(player.global_position, "+$%d" % gained, float(world_scale))
	return gained


## Shop keys are live only while the sheet (the shop panel) is open.
func _train_from_sheet(stat_index: int) -> void:
	if _character_sheet != null and _character_sheet.visible:
		try_train(stat_index)


func _sell_from_sheet() -> void:
	if _character_sheet != null and _character_sheet.visible:
		try_sell_salvage()


## The whole character sheet, resolved to plain values for CharacterSheet to draw
## (the same node-free hand-off HudLayer/overlay use — no live Player handed into
## another node's _draw). Money, the four stats with their perk unlock states and
## next-level cost, whether a trainer is in reach, and the salvage on offer.
func character_sheet_model() -> Dictionary:
	var out := {
		"money": 0, "near_trainer": _near_trainer(),
		"salvage_value": 0, "taming": false, "stats": [],
	}
	if player == null or not is_instance_valid(player) or player.stats == null:
		return out
	out["money"] = player.wallet.balance
	out["taming"] = player.stats.taming_enabled()
	out["salvage_value"] = Economy.appraise(player.inventory, player.stats.trade_bonus())
	for stat in StatDB.names():
		var level: int = player.stats.level_of(stat)
		var perks: Array = []
		for n in range(1, StatDB.MAX_LEVEL + 1):
			perks.append({
				"name": StatDB.perk_name(stat, n),
				"unlocked": player.stats.has_perk(stat, n),
			})
		out["stats"].append({
			"name": StatDB.stat_name(stat),
			"level": level,
			"max": StatDB.MAX_LEVEL,
			"next_cost": Training.cost_to_raise(player.stats, stat),
			"perks": perks,
		})
	return out


## The player's money, for the tiny HUD indicator (HudLayer).
func player_money() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	return player.wallet.balance


## The local body's health, for the minimal always-on HUD health readout
## (HudLayer). Returns {health, max}; max <= 0 means "no player, draw nothing".
## The GRIT pool IS the player's life (combat/suffocation drain it), so a small
## bar for it is the one vital the owner asked to always see (2026-08-23).
func player_vitals() -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {"health": 0.0, "max": 0.0}
	return {"health": player.health, "max": player.max_health}


## The prevailing wind DIRECTION at the local player's position, for the HUD's
## drifting-particle wind cue (owner 2026-08-23: "some visual outside the map for
## wind going in a direction"). A unit Vector2 from the same pure circulation
## model the map draws (Airspace.wind_dir_at) — UP the centre updraft, DOWN the
## edge downdrafts, OUTWARD across the very top row, INWARD across the very bottom
## row — or ZERO in the calm interior. Airspace.bounds is empty in flight (generation-only
## this round), so we feed fractions off the framed world rect exactly like the
## suffocation gate, keeping HUD and map on one model without reviving live wind
## forces. ZERO when there is no world/player (the HUD then drifts nothing).
func wind_status() -> Vector2:
	if _world_rect.size.x <= 0.0 or _world_rect.size.y <= 0.0:
		return Vector2.ZERO
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	var p := player.global_position
	var fx := clampf((p.x - _world_rect.position.x) / _world_rect.size.x, 0.0, 1.0)
	var a := clampf((_world_rect.end.y - p.y) / _world_rect.size.y, 0.0, 1.0)
	return Airspace.wind_dir_at(fx, a)


## Reveal the fog around every focus (the player and every ship) — the same foci
## that stream terrain, so the map charts exactly what you have flown near.
func _update_discovery() -> void:
	if _discovery == null:
		return
	var foci: Array = []
	if player != null and is_instance_valid(player):
		foci.append(player.global_position)
	if fleet != null:
		for ship in fleet.ships():
			if is_instance_valid(ship):
				foci.append(ship.global_position)
	_discovery.reveal(foci)


# --- Session ---------------------------------------------------------------

func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		host_session()
	elif args.has("--client"):
		var idx := args.find("--client")
		var address := "127.0.0.1"
		if idx + 1 < args.size() and not args[idx + 1].begins_with("--"):
			address = args[idx + 1]
		join_session(address)


func host_session() -> void:
	if Net.is_online():
		return
	if Net.host() != OK:
		return

	# Everything that existed a moment ago was added to its container
	# DIRECTLY, and a MultiplayerSpawner only replicates what it spawned
	# itself. So the whole pre-host world has to be re-created through the
	# spawners, or a joiner arrives to an empty sky.
	_rehome_offline_ships()

	# The offline body was added directly, so the spawner never tracked
	# it and joiners would not receive it. Respawn through the spawner
	# in place — same position, now replicated.
	if player != null:
		var pos := player.global_position
		player.queue_free()
		player = crew.spawn_player(1, pos, _player_scale_mult())

	# Only hand out a vessel if the host does not already have one. Before
	# the rehoming above, hosting always minted a second ship and left the
	# host's original flying around untracked.
	if _ship_of(1) == null:
		_give_ship_to(1)


## Re-create every pre-host ship through the Fleet spawner: serialize, spawn,
## free the original — the same move the host's own body makes above. Without
## it a ship built or flown offline exists on the host alone, joiners never
## receive it, and `_refresh_local_ship` can bind the host to a hull that is
## invisible to everyone else.
##
## Everything a peer needs rides `Ship.to_payload()`; nothing is assigned to
## the returned Ship, because post-spawn field assignment is server-only and
## fails in silence (godot-quirks). That is what carries the whales' shared
## health pool across the switch.
func _rehome_offline_ships() -> void:
	for old in fleet.ships():  # snapshot: we add to the Fleet as we go
		var fresh := fleet.spawn_ship(old.to_payload())
		if fresh == null:
			continue  # spawner not ready — keep the original rather than lose it
		# Riders point at node instances, not at ships-in-general: an NPC whose
		# ship disappears deletes himself, which would quietly disarm the enemy
		# hulk the moment you pressed H.
		for npc in _npcs:
			if is_instance_valid(npc) and npc.ship == old:
				npc.ship = fresh
		if local_ship == old:
			local_ship = fresh
		# remove_child before queue_free: the free itself only lands at the end
		# of the frame, and until then fleet.ships() would report the ship
		# twice — enough to make the "does the host already have a ship?"
		# question below answer wrong.
		fleet.remove_child(old)
		old.queue_free()


func _ship_of(peer: int) -> Ship:
	for ship in fleet.ships():
		if ship.pilot_peer == peer:
			return ship
	return null


func join_session(address := "127.0.0.1") -> void:
	if Net.is_online():
		return
	Net.join(address)


## Server only: every peer gets their own vessel, offset so they do not spawn
## inside each other. Returns the ship's spawn position so the peer's body
## can be placed aboard it.
func _give_ship_to(peer: int) -> Vector2:
	if not Net.is_server():
		return SHIP_START
	var index := fleet.ships().size()
	var pos := SHIP_START + Vector2(index * _ship_spacing, 0)
	fleet.spawn_ship_from_cells(
		_starter_cells(),
		pos,
		peer,
		0.0,
		float(world_scale))
	return pos


func _on_peer_joined(id: int) -> void:
	var ship_pos := _give_ship_to(id)
	# And a body standing on its deck — players replicate exactly like
	# ships do, through the one place they are created.
	crew.spawn_player(id,
		ship_pos + Vector2(PLAYER_SPAWN_CELL) * Ship.CELL * world_scale,
		_player_scale_mult())


func _on_peer_left(id: int) -> void:
	if not Net.is_server():
		return
	crew.despawn(id)  # ships stay adrift; people do not linger
	for ship in fleet.ships():
		if ship.pilot_peer == id:
			ship.pilot_peer = 0  # abandoned, left adrift rather than deleted


## Client side: joining a live session means the server owns spawning —
## this machine's offline body is replaced by the replicated one.
func _on_connected_to_server() -> void:
	if player != null:
		player.queue_free()
		player = null
	# Terrain is seed + diffs: this client already regenerated the base world
	# from the shared seed, so catch up on the server's edits since generation.
	# The broadcast (Terrain._apply_edit) only covers edits made while connected;
	# this handshake covers everything dug/placed BEFORE we arrived.
	if terrain != null:
		terrain.request_diffs_on_join()


## The local body may arrive through replication after a delay (or be
## replaced on join), so it is resolved by polling, exactly like the ship.
func _refresh_local_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = crew.player_for(_my_id())


## Ships arrive asynchronously on clients, so the local ship is resolved by
## polling rather than assumed at startup.
func _refresh_local_ship() -> void:
	if is_instance_valid(local_ship) and local_ship.pilot_peer == _my_id():
		return
	local_ship = null
	for ship in fleet.ships():
		if ship.pilot_peer == _my_id():
			local_ship = ship
			return


func _my_id() -> int:
	return multiplayer.get_unique_id() if Net.is_online() else 1


# --- World -----------------------------------------------------------------

func _build_terrain() -> void:
	var body := StaticBody2D.new()
	for rect in _terrain_rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = rect.position + rect.size * 0.5
		body.add_child(cs)
	add_child(body)


## Generate the resident terrain grid: procedural, SEEDED, banded floating
## islands across the whole world region (terrain/island_gen.gd), replacing the
## old hand-placed floor + slabs. Deterministic (a fixed seed → a fixed world),
## data-only (writes cells; no nodes — chunks stay inert until a focus streams
## them in), and banded by altitude (common/lighter materials high, exotic ore
## deep; very sparse in the band gaps; clear in the wind columns). A guaranteed
## solid spawn floor sits under SHIP_START. Runs once — no per-frame cost.
func _build_generated_terrain() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.scale_unit = float(world_scale)
	# TERRAIN RESOLUTION (owner 2026-08-23: "I want to try full 8x"): SUBDIV
	# divides the terrain cell so the player spans ~8 tiles (Windforge
	# proportions) instead of ~1. Read ONCE at world build — F2 → change the
	# lever → R regenerates at the new resolution (a live A/B). Everything
	# pixel-anchored (ships, spawns, reach) is untouched; see Terrain.subdiv.
	terrain.subdiv = maxi(1, Tunables.get_int("terrain_subdiv"))
	add_child(terrain)
	# The authority emits `dug` when a cell is mined; the world credits the
	# miner's inventory and pops a pickup float. One connection for the life of
	# the terrain (it is never freed and re-made). `placed` is the inverse: the
	# authority spent one item to write a cell, so the world debits the placer.
	terrain.dug.connect(_on_terrain_dug)
	terrain.placed.connect(_on_terrain_placed)

	# The generator sets Airspace.bounds for band-aware PLACEMENT and restores it
	# afterwards (generation-only — wind/gravity/ceiling stay off in flight this
	# round). See IslandGen and docs/DECISIONS.md.
	IslandGen.generate(terrain, world_seed)

	# Hidden easter egg: plant the secret Cairn beacon after normal generation so
	# it always exists (maps/world/easter_eggs.gd → the Cairn). Not surfaced in
	# the HUD; documented dev-facing in docs/DECISIONS.md.
	EasterEggs.plant_cairn(terrain)


## Stream the resident terrain: promote chunks near any focus (the player and
## every ship), demote the rest. Cheap and synchronous — no loading screens.
func _stream_terrain() -> void:
	if terrain == null:
		return
	# RENDER RANGE = what the camera actually shows (owner 2026-08-24: a fixed
	# radius popped terrain at the screen edge whenever the pilot/ride zoom-out
	# or the wheel widened the view). Half the visible extent at the LIVE zoom,
	# largest axis — Terrain adds its own chunk margin and caps the extreme.
	if camera != null and is_instance_valid(camera):
		var half: Vector2 = get_viewport_rect().size * 0.5 / camera.zoom
		terrain.primary_range_px = maxf(half.x, half.y)
	# TIERED (the subdiv-8 lag fix): the PLAYER (+ their ship — the camera)
	# streams render-range terrain; every OTHER ship gets only a collision
	# bubble. See Terrain.update_streaming.
	var primary: Array = []
	var secondary: Array = []
	if player != null and is_instance_valid(player):
		primary.append(player.global_position)
	if fleet != null:
		for ship in fleet.ships():
			if not is_instance_valid(ship):
				continue
			if ship == local_ship or (player != null and is_instance_valid(player)
					and (player.piloting == ship or player.riding == ship)):
				primary.append(ship.global_position)
			else:
				secondary.append(ship.global_position)
	terrain.update_streaming(primary, secondary)


## Something to fight: an enemy hulk hangs mid-arena (faction 1), with a
## GUNNER aboard manning its slung turret — crewed, never automated
## (owner; the original's way). Living, moving enemies are Sprint 4's job.
func _spawn_enemy_hulk() -> void:
	_spawn_hulk_at(SHIP_START + Vector2(1100.0, -80.0) * world_scale)


## Spawn one crewed enemy hulk at `pos`, returning it (null if the spawner is not
## ready). The shared spawn path for the arena target range AND the debug window's
## "spawn bandit" button — crewed, never automated (owner rule), so the gun and
## helm actually work the instant it appears.
func _spawn_hulk_at(pos: Vector2) -> Ship:
	# Native-8× blueprint at the shipped scale; frozen 1× fixture for the
	# legacy test scene. Neither path upscales — both files are authored
	# at their own granularity (true component footprints at 8×).
	var hulk_path := "res://ships/hulk.ship" if world_scale > 1 \
		else "res://tests/fixtures/hulk_1x.ship"
	var hulk := fleet.spawn_ship_from_cells(
		ShipLayout.load_cells(hulk_path),
		pos, 0, 0.0, float(world_scale), 1)
	if hulk == null:
		return null
	# Crewed, never automated (owner): a driver stands at the panel, a
	# gunner at the gun. The gun fires only while its gunner is aboard.
	_spawn_crewman(hulk, "H", "driver")
	_spawn_crewman(hulk, "T", "gunner")
	return hulk


## The living whale's shared health pool (owner: one "whale unit" — no
## block breaks until it is dead). 5× the first tuning (owner 2026-08-21:
## "whales should have a LOT more health, they're made of paper") —
## roughly three minutes of sustained two-turret starter fire: hunting a
## whale is an undertaking, not a drive-by. Scale-free, since damage
## amounts are. THE health feel knob; ram lethality is PUSH_ACCEL
## (whale_ai) and hull toughness is per-cell hp (block_db).
const WHALE_HEALTH := 15000.0


## How many whales roam the sky at once — a small POD so variety is visible
## (owner: "a couple/few whales roaming"). Shared by the shipped scene and the
## legacy 1× scene, so the startup suites agree on the count (they assert it).
const WHALE_POD_SIZE := 3


## A POD of sky whales drifts far to port of spawn (faction 2, wildlife):
## neutral until damaged, then they RAM — see combat/whale_ai.gd. The pod is a
## WEIGHTED pick over the five authored body plans (combat/whale_spawn.gd) so a
## few whales read as different creatures, not clones; a deterministic RNG off
## the world seed makes a fixed world spawn a fixed pod (like the island field).
## The FIRST whale is always the reference blue (whale.ship) — it carries the
## ghost-whale easter egg and keeps the startup coarse-collider check on a known
## body — and the rest are the weighted variety.
func _spawn_whale() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "whales"])  # deterministic, distinct from the island field
	for i in Tunables.get_int("whale_pod_size"):
		var path := "res://ships/whale.ship" if i == 0 else WhaleSpawn.pick_plan(rng)
		# Spread the pod out to port and stagger altitude, so they do not spawn
		# stacked inside one another.
		var pos := SHIP_START + Vector2(-1500.0 - i * 520.0, -350.0 + (i - 1) * 220.0) * world_scale
		var whale := _spawn_one_whale(path, pos)
		if whale == null:
			continue
		# Hidden easter egg: a rare seed rolls the ghost whale — a cosmetic pale
		# tint overriding the natural one, nothing else (maps/world/easter_eggs.gd
		# → the Pale Wanderer). One ghost in the pod (the reference whale). Not
		# surfaced anywhere in play; documented dev-facing in docs/DECISIONS.md.
		if i == 0 and EasterEggs.is_ghost_whale(world_seed):
			whale.body_tint = EasterEggs.GHOST_WHALE_TINT


## Spawn ONE whale of body plan `path` at `pos`, returning it (null if the spawner
## is not ready). The shared path for the pod loop AND the debug window's "spawn
## whale" button. Sets the health pool from the live tunable, then REBUILDS — the
## coarse-collider ordering _spawn_whale needs: spawn_ship_from_cells built the
## collider while the whale still looked like a vessel (pool 0), so it must rebuild
## once it is a living creature or it keeps the precise 7-shape collider for life
## (owner 2026-08-22; see Ship._use_coarse_collider).
##
## Single-player / server path only today. If whales ever spawn in a live session,
## the pool must ride the spawn payload instead — post-spawn fields are server-only
## (godot-quirks).
func _spawn_one_whale(path: String, pos: Vector2) -> Ship:
	var whale := fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(ShipLayout.load_cells(path), world_scale),
		pos, 0, 0.0, float(world_scale), 2)
	if whale == null:
		return null
	var hp := Tunables.get_num("whale_health")
	whale.shared_health = hp
	whale.shared_health_max = hp
	# A whale is the HIGH taming tier (needs LORE Master Trader) and a mining-
	# capable mount — ride_mine_pulse only drills tame_level>=2 creatures.
	whale.tame_level = 2
	# Cosmetic per-variant tint gives the pod visible variety beyond silhouette
	# (WhaleSpawn.tint_for; body_tint is documented cosmetic).
	whale.body_tint = WhaleSpawn.tint_for(path)
	whale.rebuild()
	return whale


## How many small critters roam near spawn — a few so the early taming target is
## easy to find. Shared by the shipped scene and reset (the startup suites assert
## the total ship count includes these).
const CRITTER_COUNT := 2
## A critter's shared pool — a fraction of a whale's, so it is a light early
## target and a nimble ride, not a tank.
const CRITTER_HEALTH := 400.0


## A few SMALL tameable creatures near spawn (faction 2 wildlife, driven by the
## same WhaleAI as whales). They are the EARLY taming target: tameable at the
## lower Wisdom bar (LORE Beast Whisperer, tame_level 1) where a whale is refused,
## rideable and nimble, but they do NOT mine terrain. Single-player / server path,
## like whale spawning; deterministic off the world seed.
func _spawn_critters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "critters"])
	for i in CRITTER_COUNT:
		var pos := SHIP_START + Vector2(300.0 + i * 260.0, -140.0 + (i - 1) * 90.0) * world_scale
		_spawn_one_critter(pos)


## Spawn ONE critter at `pos`, returning it (null if the spawner is not ready).
## Mirrors _spawn_one_whale's pool-then-rebuild ordering; small pool, tame_level 1
## (the low taming bar), and a nimbler ride than a whale (ride_speed_mult > 1).
func _spawn_one_critter(pos: Vector2) -> Ship:
	var critter := fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(ShipLayout.load_cells("res://ships/critter.ship"), world_scale),
		pos, 0, 0.0, float(world_scale), 2)
	if critter == null:
		return null
	critter.shared_health = CRITTER_HEALTH
	critter.shared_health_max = CRITTER_HEALTH
	critter.tame_level = 1            # the LOW taming bar (Beast Whisperer)
	critter.ride_speed_mult = 1.6     # nimbler than a whale
	critter.body_tint = Color(0.80, 0.90, 0.78)
	critter.rebuild()
	return critter


## How many krakens haunt the deep. Few and far apart — they are extremely
## aggressive apex hunters (owner survey), not roaming wildlife you meet at spawn.
## Bumped 2→3 (owner 2026-08-23: "add krakens too") — a fuller deep, still spawned
## well ABOVE the lava core (frac 0.22 vs the core's 0.10) so they never melt on spawn.
const KRAKEN_COUNT := 3
## A kraken's shared pool. Tough, but the real defence is the SHELL casing (armor
## divides ram/crush damage): shots barely dent shell, so you must snipe the small
## exposed-meat mouth. THE kraken survivability knob (ram lethality is PUSH_ACCEL).
const KRAKEN_HEALTH := 12000.0
## The two owner-adopted kraken body plans (both shell-casing-surrounds-meat with a
## tiny exposed-meat mouth): kraken_b (giant squid) and kraken_c (ammonite conch).
const KRAKEN_PLANS := ["res://ships/kraken_c.ship", "res://ships/kraken_b.ship"]
## Altitude fraction the pod spawns at (0 = floor, 1 = ceiling). Well inside the
## DEEP band (Airspace.DEEP_TOP 0.34) but clear of the lava floor — where the
## thick fog lives and the oxygen gate bites (owner: krakens live deep).
const KRAKEN_SPAWN_FRAC := 0.22


## The KRAKENS: a small pod of deep hunters, faction-2 wildlife driven by the
## two-ended KrakenAI (mouth grab + shell-tip ram; hover-held aloft since they
## carry no lift — the wild-creature hover exception in WhaleAI). Spawned deep and
## spread across the world so a day-one player up in the MID band never meets one.
## Deterministic off the world seed, single-player / server path (like whales).
func _spawn_kraken() -> void:
	if _world_rect.size.y <= 0.0:
		return  # no framed world yet — nothing to place against
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "kraken"])  # distinct from the whale/critter seeds
	var y := _world_rect.end.y - KRAKEN_SPAWN_FRAC * _world_rect.size.y
	var cx := _world_rect.get_center().x
	for i in KRAKEN_COUNT:
		var path: String = KRAKEN_PLANS[i % KRAKEN_PLANS.size()]
		# Spread across the deep, staggered a little in altitude so they do not
		# spawn stacked; wide enough apart that two do not overlap on spawn.
		var pos := Vector2(cx + (float(i) - 0.5 * (KRAKEN_COUNT - 1)) * 3200.0 * world_scale,
			y + (i % 2) * 260.0 * world_scale)
		_spawn_one_kraken(path, pos)


## Spawn ONE kraken of body plan `path` at `pos` (null if the spawner is not ready).
## Mirrors _spawn_one_whale's pool-then-rebuild coarse-collider ordering; marks it a
## kraken (creature_kind → the KrakenAI + untameable) and leaves tame_level at the
## plain default (it never enters the taming filters, being untameable).
func _spawn_one_kraken(path: String, pos: Vector2) -> Ship:
	var kraken := fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(ShipLayout.load_cells(path), world_scale),
		pos, 0, 0.0, float(world_scale), 2)
	if kraken == null:
		return null
	kraken.shared_health = KRAKEN_HEALTH
	kraken.shared_health_max = KRAKEN_HEALTH
	kraken.creature_kind = "kraken"   # → KrakenAI (two-ended) + untameable
	# tame_level 0: a kraken is never tameable, so it must fall OUTSIDE both the
	# whale (>=2) and critter (==1) taming-tier filters the startup suites use.
	kraken.tame_level = 0
	kraken.body_tint = Color(0.78, 0.82, 0.74)
	kraken.rebuild()
	return kraken


## Plant the trainer station near spawn (rpg/trainer.gd). A world marker, not a
## ship — so it never touches fleet.ships() or the hosting rehome. Single-player /
## host only; joiners do not receive it yet (a seam — real trainers live in towns,
## Phase 6). Positioned just off the starter so the exchange is reachable.
func _spawn_trainer() -> void:
	if _trainer != null and is_instance_valid(_trainer):
		return
	_trainer = Trainer.new()
	_trainer.name = "Trainer"
	_trainer.reach = Ship.CELL * 3.0 * world_scale
	_trainer.position = SHIP_START + Vector2(6.0, 0.0) * Ship.CELL * world_scale
	add_child(_trainer)


# --- Debug window spawn/cheat actions (maps/world/debug_window.gd) ----------
#
# The window's Spawn/Player tabs call these. Authority-gated exactly like the
# other spawn paths (single-player / host): a client asking to spawn is a
# documented seam. Each spawn reuses the same crewed/coarse-collider path the
# arena uses, so a debug-spawned enemy is a real, crewed, correctly-collidered
# ship the instant it appears.

## Spawn `kind` ("hulk"/"bandit" or "whale") at world position `at`, returning the
## new ship (null off the authority or if the spawner is not ready).
func debug_spawn(kind: String, at: Vector2) -> Ship:
	if Net.is_online() and not Net.is_server():
		return null  # networked debug spawns are a seam — authority only
	match kind:
		"hulk", "bandit":
			return _spawn_hulk_at(at)
		"whale":
			return _spawn_whale_at(at)
	return null


## A single whale of a random body plan at `at` — the debug "spawn whale" button.
## Reuses _spawn_one_whale (pool-then-rebuild coarse-collider ordering).
func _spawn_whale_at(at: Vector2) -> Ship:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return _spawn_one_whale(WhaleSpawn.pick_plan(rng), at)


## Grant the local player money (debug Player tab).
func debug_grant_money(amount: int) -> void:
	if player != null and is_instance_valid(player) and player.wallet != null:
		player.wallet.add(amount)


## Heal the local player to full (debug Player tab).
func debug_heal_player() -> void:
	if player != null and is_instance_valid(player):
		player.health = player.max_health


## Max out every stat level on the local player (debug Player tab). Recomputes the
## health cap so the new GRIT level takes effect immediately.
func debug_max_stats() -> void:
	if player == null or not is_instance_valid(player) or player.stats == null:
		return
	for stat in StatDB.names():
		player.stats.set_level(stat, StatDB.MAX_LEVEL)
	player.max_health = player.stats.max_health()
	player.health = player.max_health


func _spawn_crewman(ship: Ship, station_key: String, role: String) -> void:
	var npc := Crewman.new()
	npc.ship = ship
	npc.role = role
	npc.body_size = Vector2(10.0, 18.0) * _player_scale_mult()
	npc.local_pos = Vector2.ZERO
	for cluster in ship._glyph_clusters:
		if cluster["key"] == station_key:
			var r := cluster["rect"] as Rect2
			if station_key == "T":
				# The gunner rides his slung gun — feet on top of the
				# barrel housing, not floating in the air beside it.
				npc.local_pos = r.get_center() \
					+ Vector2(0.0, -(r.size.y + npc.body_size.y) * 0.5)
			else:
				# The driver stands one pace to port of his panel, feet on
				# the cabin floor the blueprint gives him.
				npc.local_pos = r.get_center() + Vector2(-r.size.x, 0.0)
			break
	add_child(npc)
	_npcs.append(npc)


## True when an interactive UI (the F2 debug window, the F9 saves panel, the F1
## help) is under the cursor and should EAT the click instead of letting it fall
## through to the game (owner 2026-08-23: "clicking on the F2 UI should absorb
## clicks instead of also passing them through to the game"). The world polls the
## raw Input for LMB/RMB (not `_gui_input`), so a hovered Control does not stop it
## on its own — every mouse-driven world verb checks this first. The always-on HUD
## Controls use MOUSE_FILTER_IGNORE, so they never register as hovered here.
func _ui_wants_mouse() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_hovered_control() != null


## Q is the trigger everywhere (owner: "the player needs some small pew
## pew... the ship also needs turrets"). On foot it is a personal sidearm;
## at the helm it volleys every turret component toward the cursor. An
## underpowered ship's turrets fire proportionally slower — brownout
## stretches the cooldown, it never switches fire off (the wiki's graceful
## degradation rule).
func _handle_shooting(delta: float) -> void:
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_turret_cooldown = maxf(0.0, _turret_cooldown - delta)
	if player == null or not Input.is_action_pressed("shoot") or _ui_wants_mouse():
		return
	var aim := get_global_mouse_position()

	if player.is_piloting():
		if _turret_cooldown > 0.0:
			return
		var ship := player.piloting
		var ratio := clampf(
			ship.power_supply() / maxf(ship.active_draw(), 1.0), 0.0, 1.0)
		if ratio <= 0.01:
			return  # no power, no fire — same rule as the props
		var fired := _fire_turrets(ship, aim)
		if fired:
			# Brownout STRETCHES the cadence (an underpowered ship fires slower);
			# the F2 fire-rate lever SHORTENS it. The personal GRACE perk does not
			# reach the ship's guns — that is the sidearm's (Player.turret_interval).
			_turret_cooldown = Player.turret_interval(
				TURRET_COOLDOWN, ratio, Tunables.get_num("fire_rate_mult"))
		return

	if _shoot_cooldown > 0.0:
		return
	# Muzzle offset: the pew leaves from just outside the body on the aim
	# side, never from inside the shooter.
	# Shooter velocity: `Player.velocity` is DECK-RELATIVE by design (the
	# floor's carry is positional, see player.gd), so the platform term has
	# to be added back in — otherwise a pellet fired while riding a fast
	# deck is left behind by the ship and thumps into its own hull.
	_spawn_shot(player.global_position, aim,
		900.0 * player._scale_mult, Tunables.get_num("sidearm_damage"), 0, player._scale_mult,
		player.SIZE.x * 0.9, SIDEARM_MASS,
		player.velocity + player.get_platform_velocity(), player)
	# Fire-rate is a real, upgradable property: the GRACE quickness perk
	# (player.fire_rate_mult) AND the F2 fire_rate_mult lever both shorten the
	# interval between sidearm shots. A perked/levered player fires measurably
	# faster than base (Player.sidearm_interval; proven by test).
	_shoot_cooldown = player.sidearm_interval(
		SHOOT_COOLDOWN, Tunables.get_num("fire_rate_mult"))


## Slug masses (block-mass units): the sidearm spits pellets, turrets
## throw shells five times as heavy — same speeds as before (the muzzle
## impulse is derived as mass × speed), but the momentum on impact and
## the authority of the shove scale with the metal thrown.
const SIDEARM_MASS := 1.0
const SHELL_MASS := 5.0


## Felt-range ceiling for an in-game shot, as PATH LENGTH in UNSCALED px
## (Shot.max_travel = this × world_scale). It is the distance twin of the
## 30 s `Shot.life`: at ~10× the deaggro engagement envelope
## (`enemy_deaggro_range` 1100) a slug has flown well past anything on
## screen, so capping here frees the off-screen dead weight — the shot
## swarm behind the FPS sag — without touching the felt range the owner
## asked for (2026-08-21: "travel about 10x their current distance"). Live
## shots each cost a raycast + a sweep of every ship's prop wash per frame
## (O(shots × ships)); 30 s of missed fire otherwise piles up hundreds.
## Bare Shots (tests, the v0.13.0 range pin) stay uncapped — only the
## spawner sets this.
const SHOT_MAX_RANGE := 11000.0


## How much of the muzzle budget a gunner will spend leaning into his own
## crossrange drift. Past this the platform is out-drifting its own shells
## sideways and no barrel angle exists that puts them back on the sight
## line — the shots stream off, which is both honest and legible.
const CROSSRANGE_LIMIT := 0.9


func _spawn_shot(from: Vector2, toward: Vector2, speed: float, dmg: float,
		fac: int, vis: float, muzzle := 0.0, slug_mass := 1.0,
		platform_vel := Vector2.ZERO, shooter: Node2D = null) -> void:
	if from.distance_to(toward) < 1.0:
		return
	var shot_gravity := 980.0 * world_scale * Shot.GRAVITY_FACTOR
	# The shell now carries the shooter's velocity (Shot.fire), so the aim
	# has to account for that term twice over — otherwise inheritance fixes
	# the self-collision and breaks every gunner's lead.
	#
	# 1. TIME OF FLIGHT is set by the CLOSING speed, not the muzzle speed:
	#    a shell thrown forward off a fast ship arrives sooner and needs
	#    less hold-over; one thrown backwards loiters and needs more.
	#    First-order ballistic compensation otherwise unchanged — every
	#    gunner (player turrets and enemy crews alike) holds over for the
	#    arc, so the aim point is still roughly where the shell lands.
	#    t = d/v_closing, hold-over = ½gt².
	var los := (toward - from).normalized()
	var closing := maxf(speed + platform_vel.dot(los), 1.0)
	var t := from.distance_to(toward) / closing
	var compensated := toward + Vector2.UP * 0.5 * shot_gravity * t * t
	# 2. CROSSRANGE: the platform's sideways component would carry the shell
	#    off the sight line entirely. The barrel leans into it the way a
	#    real gunner aims into the wind — dir·speed absorbs −p_perp, so
	#    dir·speed + platform_vel comes out parallel to the sight line. The
	#    barrel still only has `speed` to spend, so what is left for closing
	#    the range is c = √(speed² − |p_perp|²).
	var sight := (compensated - from).normalized()
	var dir := sight
	var p_perp := platform_vel - sight * platform_vel.dot(sight)
	if p_perp.length() < speed * CROSSRANGE_LIMIT:
		var c := sqrt(maxf(speed * speed - p_perp.length_squared(), 1.0))
		dir = (sight * c - p_perp) / speed
	var s := Shot.new()
	s.position = from + dir * muzzle
	s.mass = slug_mass
	s.gravity = shot_gravity
	# impulse J = m·v — v survives, momentum scales; the platform term is
	# added on top of the muzzle velocity, not baked into the impulse.
	s.fire(dir * speed * slug_mass, platform_vel)
	s.faction = fac
	s.damage = dmg
	# Attribution: who to retaliate against (a creature rams its SHOOTER, not
	# the nearest player-side ship). Null for unattributed sources.
	if shooter != null and is_instance_valid(shooter):
		s.shooter_id = shooter.get_instance_id()
	# No per-shooter lifetime multiplier any more: `Shot.life` is 30 s for
	# everyone (owner 2026-08-21). The enemy's old ×10 existed only to give
	# bandits reach past their doubled eyesight; the shared 30 s covers that
	# and then some.
	s.visual_scale = vis
	# Distance ceiling twinned with the 30 s life: free the shot once it has
	# out-flown its felt range so the off-screen swarm can't accumulate (see
	# SHOT_MAX_RANGE). Scaled with the world so reach tracks ship size.
	s.max_travel = Tunables.get_num("shot_max_range") * world_scale
	add_child(s)


## Every turret that BEARS on the aim volleys from its own centre. A
## turret's arc is the 180° half-plane away from its mounting (owner;
## matches the original) — the stern gun cannot shoot up through the deck,
## and anything aimed across the hull is stopped harmlessly by the ship's
## own infrastructure.
func _fire_turrets(ship: Ship, aim: Vector2, speed_mult := 1.0) -> bool:
	var fired := false
	for cluster in ship._glyph_clusters:
		if cluster["key"] != "T":
			continue
		var muzzle: Vector2 = ship.to_global((cluster["rect"] as Rect2).get_center())
		var dir := aim - muzzle
		if dir.length() < 1.0:
			continue
		var facing: Vector2 = ship.transform.basis_xform(cluster["facing"])
		if dir.normalized().dot(facing) < 0.0:
			continue  # out of this gun's arc
		# The gun rides the ship: rotation is locked upright, so every point
		# on the hull shares `linear_velocity` exactly — no ω×r term to add.
		_spawn_shot(muzzle, aim, 700.0 * ship.scale_unit * speed_mult,
			Tunables.get_num("turret_damage"),
			ship.faction, ship.scale_unit, 0.0, SHELL_MASS,
			ship.linear_velocity, ship)
		fired = true
	return fired


## Enemy ships are CREWED, never automated (owner; matches the original):
## a turret returns fire only while a gunner is aboard to man it. The
## behaviour itself stays deliberately dumb — real NPCs are Sprint 4's
## world-anchored work. Player turrets stay manual (owner's call).
const ENEMY_FIRE_COOLDOWN := 1.2
## Aggro: hostiles open fire inside the aggro range and keep at it until
## the target breaks away past the larger de-aggro range (hysteresis, so
## the fight doesn't flicker at the boundary). Unscaled px, ×world_scale.
## Doubled 2026-08-20 (owner). The old ×10 enemy shell lifetime that went
## with it is retired — every shot lives 30 s now (`Shot.life`), which
## already outreaches any eyesight number here.
@export var enemy_aggro_range := 700.0
@export var enemy_deaggro_range := 1100.0
## The original's enemy fire is slow enough to dodge — 50% for now,
## a knob in case it's overridden later (owner).
@export var enemy_shot_speed_mult := 0.5
## Getting HIT is a provocation regardless of distance (owner 2026-08-20:
## "if their ship is hit, the NPCs should react"): the crew aggros on any
## damage — shots, rams — and won't calm down while the hits keep coming.
## Only after this many quiet seconds does the normal de-aggro range
## apply again.
const PROVOKED_SECONDS := 6.0
var _enemy_cooldowns := {}
var _enemy_aggro := {}
var _enemy_provoked_at := {}
## Instance ids whose `damaged` signal is already wired. A bound callable
## never compares equal to its base, so `is_connected(base)` cannot guard
## the lazy wiring — this set does.
var _enemy_watched := {}
var _npcs: Array = []


func _enemy_fire(delta: float) -> void:
	if not Net.is_server():
		return
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.faction != 1:
			continue  # only HOSTILES gun; wildlife has its own reactions
		# The crew feels its hull: any damage provokes (lazily wired so
		# severed faction-1 wrecks joining the fleet get watched too).
		if not _enemy_watched.has(ship.get_instance_id()):
			_enemy_watched[ship.get_instance_id()] = true
			ship.damaged.connect(_on_hostile_ship_damaged.bind(ship))
		if not _has_gunner(ship):
			continue  # nobody aboard to man the gun
		var id := ship.get_instance_id()
		var cd: float = _enemy_cooldowns.get(id, 0.0) - delta
		_enemy_cooldowns[id] = cd
		# Bandits hunt the PLAYER side, not the wildlife.
		var target := _nearest_ship_of_faction(ship, 0)
		if target == null:
			continue
		var d := ship.global_position.distance_to(target.global_position)
		var provoked: bool = Time.get_ticks_msec() \
			< _enemy_provoked_at.get(id, -1.0e12) + PROVOKED_SECONDS * 1000.0
		if _enemy_aggro.get(id, false):
			if d > Tunables.get_num("enemy_deaggro_range") * world_scale and not provoked:
				_enemy_aggro[id] = false
				continue
		elif d <= Tunables.get_num("enemy_aggro_range") * world_scale:
			_enemy_aggro[id] = true
		else:
			continue
		if cd > 0.0:
			continue
		var ratio := clampf(
			ship.power_supply() / maxf(ship.active_draw(), 1.0), 0.0, 1.0)
		if ratio <= 0.01:
			continue  # a powerless wreck's gun is scrap, same rule as props
		if _fire_turrets_at(ship, target, Tunables.get_num("enemy_shot_speed_mult")):
			_enemy_cooldowns[id] = Tunables.get_num("enemy_fire_cooldown") / maxf(ratio, 0.05)


## Enemy gunners shoot at whatever part of the target their gun can REACH
## (owner 2026-08-20): each turret picks a point on the target's solid
## bounds inside its own arc, so a belly gun engages a level ship by its
## lower hull instead of sulking because the ship's origin sits above the
## horizon. Player turrets stay on the cursor — aim is the player's job.
func _fire_turrets_at(ship: Ship, target: Ship, speed_mult: float) -> bool:
	var fired := false
	for cluster in ship._glyph_clusters:
		if cluster["key"] != "T":
			continue
		var muzzle: Vector2 = ship.to_global((cluster["rect"] as Rect2).get_center())
		var facing: Vector2 = ship.transform.basis_xform(cluster["facing"])
		var aim: Variant = ShipAI.arc_aim_point(muzzle, facing, target)
		if aim == null:
			continue
		# Same inheritance as the player's guns — a bandit that dives past
		# you must not shoot itself in its own keel.
		_spawn_shot(muzzle, aim as Vector2, 700.0 * ship.scale_unit * speed_mult,
			Tunables.get_num("turret_damage"), ship.faction, ship.scale_unit, 0.0, SHELL_MASS,
			ship.linear_velocity, ship)
		fired = true
	return fired


## Every hostile ship with a DRIVER at a live helm flies itself — crewed,
## never automated (owner): no driver or no panel means the ship coasts,
## exactly like a playerless helm. The AI itself lives in combat/ship_ai.gd.
var _ship_ais := {}


func _enemy_pilot(delta: float) -> void:
	if not Net.is_server():
		return
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.faction != 1:
			continue
		if not _has_driver(ship):
			continue
		var id := ship.get_instance_id()
		if not _ship_ais.has(id):
			var ai := ShipAI.new()
			ai.ship = ship
			ai.home = ship.global_position
			_ship_ais[id] = ai
		var target: Ship = null
		if _enemy_aggro.get(id, false):
			target = _nearest_ship_of_faction(ship, 0)
		(_ship_ais[id] as ShipAI).tick(delta, target,
			Tunables.get_num("enemy_aggro_range") * world_scale)


## Wildlife swims itself: every faction-2 grid gets a WhaleAI — roam,
## ram-when-provoked, drift-as-carcass. Damage is the provocation, wired
## once per whale via the same `damaged` signal the hostiles use.
var _whale_ais := {}


func _creature_swim(delta: float) -> void:
	if not Net.is_server():
		return
	for ship in fleet.ships():
		if not is_instance_valid(ship):
			continue
		# A creature is a wild whale (faction 2) OR one we already gave a brain
		# to — a TAMED whale flips to faction 0 (the player's side) but keeps
		# swimming, so it must still be ticked after the allegiance flip.
		if ship.faction != 2 and not _whale_ais.has(ship.get_instance_id()):
			continue
		var ai := _whale_ai_for(ship)
		# A wild whale hunts the player side; a tamed ally has no prey to ram.
		var target: Ship = null
		if not ai.tamed:
			target = _nearest_ship_of_faction(ship, 0)
		ai.tick(delta, target)


## The WhaleAI for `creature`, created (and its provoke wired to the creature's
## `damaged` signal) the first time it is asked for. One place so the swim loop,
## the taming path and the ride path all share the same brain per creature.
func _whale_ai_for(creature: Ship) -> WhaleAI:
	var id := creature.get_instance_id()
	if not _whale_ais.has(id):
		# A kraken gets the two-ended KrakenAI (mouth grab + shell-tip ram); every
		# other faction-2 creature (whale, critter) gets the plain WhaleAI. Both
		# are WhaleAI, so the swim loop / taming / riding paths are identical.
		var ai: WhaleAI = KrakenAI.new() if creature.creature_kind == "kraken" \
			else WhaleAI.new()
		ai.whale = creature
		ai.home = creature.global_position
		_whale_ais[id] = ai
		creature.damaged.connect(
			func(_cell: Vector2i, _amount: float) -> void:
				# Retaliate against the ACTUAL attacker: Shot stamps the
				# shooter's id onto the ship just before the damage lands, so
				# resolving it here hands the brain who to ram (the on-foot
				# player included). Null for unattributed damage — the AI then
				# falls back to nearest-ship, the old doctrine.
				ai.provoke(instance_from_id(creature.last_attacker_id) as Node2D))
	return _whale_ais[id]


# --- Taming & riding (the Wisdom-gated payoff) -----------------------------
#
# THE LOOP (grounded, reusing the grapple): latch the grapple onto a wild whale
# and HOLD it there. With the LORE Beast Whisperer perk (Stats.taming_enabled,
# level 3) the bond fills over TAME_BOND_SECONDS → the whale is TAMED: its
# allegiance flips to the player's side (faction 0) and its WhaleAI turns calm
# and unprovokable. Taming auto-mounts you onto its back; WASD then steers it
# (world routes input to the WhaleAI — a whale has no helm to take), and F (or
# jumping) dismounts, leaving it a calm allied roamer. WITHOUT the perk the
# attempt is REFUSED (the gate, break-the-fix in the suite).
#
# Single-player / server path only, exactly like whale spawning: taming edits
# server-authoritative state, and networked taming is a documented seam (scope).
const TAME_BOND_SECONDS := 3.0
var _tame_target: Ship = null
var _tame_progress := 0.0
## The creature we last refused to tame, so the "no perk" line is said once per
## grapple rather than every frame the hook is held.
var _tame_refused_id := 0


## Try to tame `creature` NOW (the testable gate). Refuses a non-creature, a
## carcass, or — the LORE gate — a player without Beast Whisperer. On success
## the allegiance flips to the player and the WhaleAI turns ally. Returns
## whether it was tamed. (Break-the-fix: drop the taming_enabled check and the
## "refused without the perk" test fails.)
func try_tame(creature: Ship) -> bool:
	if creature == null or not is_instance_valid(creature) \
			or creature.faction != 2 or creature.is_carcass():
		return false
	# Krakens are wild deep hunters, never tameable — no perk reaches them.
	if creature.creature_kind == "kraken":
		return false
	if player == null or not is_instance_valid(player) or player.stats == null \
			or player.stats.taming_level() < creature.tame_level:
		return false  # the Wisdom gate — a whale needs the higher perk than a critter
	creature.faction = 0             # allegiance flips to the player's side
	_whale_ai_for(creature).tame()   # calm ally: won't ram, ignores provoke
	return true


## Whether `creature` is an ALREADY-TAMED ridable ally — a creature we bonded
## with before (its WhaleAI exists and is tamed). Checked without creating an AI
## for it, so a non-creature (the player's own ship) can never match.
func _is_tamed_ally(creature: Ship) -> bool:
	if creature == null or not is_instance_valid(creature):
		return false
	var id := creature.get_instance_id()
	return _whale_ais.has(id) and (_whale_ais[id] as WhaleAI).tamed


## The grapple-and-hold bond, AND the ride lifecycle. Runs on the authority.
## Riding is now the LATCH itself (owner 2026-08-24): the grapple IS the leash, so
## a ride ENDS the instant the hook is no longer latched onto the ridden creature
## (release with RMB, jump-unlatch, or the rope broke) — no F, no separate mount
## toggle. A creature you already tamed re-mounts INSTANTLY on re-grapple (it is no
## longer inert); only a WILD creature needs the 3 s bond + the LORE gate.
func _handle_taming(delta: float) -> void:
	if not Net.is_server():
		return
	if player == null or not is_instance_valid(player):
		_tame_reset()
		return
	# Already riding: the only thing that matters is whether we still hold the
	# hook on this creature. Let go of the leash → step off.
	if player.is_riding():
		if player.grapple_target() != player.riding:
			dismount_creature()
		return
	var creature := player.grapple_target()
	if creature == null or not is_instance_valid(creature) or creature.is_carcass():
		_tame_reset()
		return
	# Re-mount a creature we already tamed — instant, no bond, no gate (it is our
	# ally). This is the fix for a tamed whale going "inert" after dismount.
	if _is_tamed_ally(creature):
		if player.mount(creature):
			_whale_ai_for(creature).mount()
			_notify("riding — release the hook (RMB) to let go")
		_tame_reset()
		return
	# Otherwise this must be a WILD, tameable creature to bond with.
	if creature.faction != 2 or creature.creature_kind == "kraken":
		_tame_reset()
		return
	# The gate, felt: without enough LORE for THIS creature's tier the bond never
	# starts (a critter needs Beast Whisperer, a whale needs Master Trader), and
	# we say so once.
	if player.stats == null or player.stats.taming_level() < creature.tame_level:
		if _tame_refused_id != creature.get_instance_id():
			_tame_refused_id = creature.get_instance_id()
			_notify("you lack the wisdom to tame it — train LORE (small beasts first)")
		_tame_progress = 0.0
		return
	if _tame_target != creature:
		_tame_target = creature
		_tame_progress = 0.0
	_tame_progress += delta
	if _tame_progress >= TAME_BOND_SECONDS:
		if try_tame(creature) and player.mount(creature):
			_whale_ai_for(creature).mount()
			_notify("tamed! steer with WASD   ·   release the hook (RMB) to let go")
		_tame_reset()


func _tame_reset() -> void:
	_tame_target = null
	_tame_progress = 0.0
	_tame_refused_id = 0


## Route the rider's input to the mounted creature's WhaleAI every frame (a
## whale has no helm, so this is the equivalent of net_set_controls). WASD =
## the ship axes, so steering a whale feels like flying a ship. Authority-side.
func _handle_riding(_delta: float) -> void:
	if not Net.is_server():
		return
	if player == null or not is_instance_valid(player) or not player.is_riding():
		return
	var creature: Ship = player.riding
	var ai := _whale_ai_for(creature)
	ai.ridden = true
	ai.steer = Vector2(
		Input.get_axis("ship_left", "ship_right"),
		# ship_up is screen-up (−y); steer is in screen coords (+y down).
		-Input.get_axis("ship_down", "ship_up"))
	# Marks a mining-capable mount (a whale, tame_level>=2) as actively ride-mining.
	# NOTE (owner 2026-08-23): this NO LONGER grants terrain immunity — a ridden
	# whale now takes ram damage (reduced by its nose's armor/collision_resist, so
	# a shell nose survives and a flesh one bruises). The flag is just the "is a
	# drilling mount" marker; a small critter (tame_level 1) keeps it false and only
	# rides. Ram-mining itself is gated on tame_level in ride_mine_pulse.
	creature.ridden_mining = creature.tame_level >= 2


## Step the rider off the creature (F while riding, or a jump) and return it to
## a calm allied roam. Split out so both input paths and tests share it.
func dismount_creature() -> void:
	if player == null or not is_instance_valid(player) or not player.is_riding():
		return
	var creature: Ship = player.riding
	player.dismount()
	if is_instance_valid(creature):
		creature.ridden_mining = false  # off the back: no longer a drilling mount
		_whale_ai_for(creature).dismount()


# --- Ridden-whale terrain mining (the taming PAYOFF) -----------------------
#
# While you RIDE a whale and drive it into terrain, the whale eats through the
# terrain: a swath of cells at its leading edge (along its travel) is dug and
# credited to YOU (the whale is a drilling tool that mines far faster/broader
# than by hand, and carries you to the deep). Detection reuses the whale's own
# geometry — its solid bounds' leading edge along the steer/velocity direction
# (RideMining.front_cells) — and the dig is the ordinary Terrain.net_dig, so the
# rider is credited through the same `dug` path as hand-mining. BLUNT FORCE
# (owner 2026-08-23): the whale RAMS the terrain — it is no longer immune, it takes
# ram damage reduced by its nose's armor (BlockDB.collision_resist), so a flesh
# whale bruises while a shell-nosed kraken chews through. A small critter (tame_
# level 1) just rides; only a whale (tame_level>=2) drills.

## Rate limiter between mining pulses (world ride-mining RATE lever).
var _ride_mine_cd := 0.0


## Throttle + drive the ridden-mining pulse. Authority-side, cheap when not
## riding a whale.
func _handle_ridden_mining(delta: float) -> void:
	if not Net.is_server():
		return
	if player == null or not is_instance_valid(player) or not player.is_riding():
		_ride_mine_cd = 0.0  # a fresh mount mines on its first frame
		return
	_ride_mine_cd -= delta
	if _ride_mine_cd > 0.0:
		return
	_ride_mine_cd = maxf(0.02, Tunables.get_num("whale_mine_interval"))
	ride_mine_pulse()


## Dig one swath of terrain at the ridden creature's mining front, crediting the
## rider, and return how many cells were dug. Only a mining-capable mount (a
## whale, tame_level>=2) drills; a critter or a carcass digs nothing. Public and
## cooldown-free so tests can drive a deterministic pulse (see world_startup).
func ride_mine_pulse() -> int:
	if terrain == null or not NetUtil.is_authority(self):
		return 0
	if player == null or not is_instance_valid(player) or not player.is_riding():
		return 0
	var creature: Ship = player.riding
	if creature == null or not is_instance_valid(creature) or creature.is_carcass():
		return 0
	if creature.tame_level < 2:
		return 0  # a small mount rides but does not mine
	# Travel intent: the rider's steer (what they are driving into), falling back
	# to the whale's actual velocity if they are coasting.
	var ai := _whale_ai_for(creature)
	var dir: Vector2 = ai.steer
	if dir.length() < 0.1:
		dir = creature.linear_velocity
	if dir.length() < 0.1:
		return 0
	# Reach and breadth-pad are OWNER LEVERS in coarse cells — ×subdiv keeps the
	# swath's PIXEL depth/padding constant at any terrain resolution (the whale's
	# own cross-section already comes out in fine cells via cell_px).
	var cells := RideMining.front_cells(
		creature.to_global(creature.solid_bounds.get_center()),
		creature.solid_bounds.size * 0.5, dir, terrain.cell_px(),
		Tunables.get_int("whale_mine_reach") * terrain.subdiv,
		Tunables.get_int("whale_mine_breadth") * terrain.subdiv)
	var dug := 0
	for cell in cells:
		if terrain.is_solid(cell):
			terrain.net_dig(cell, _my_id())  # credits the rider via `dug`
			dug += 1
	return dug


# --- Environmental hazards (maps/world/hazards.gd) --------------------------
#
# Meteors sweep the TOP band, the lava core erupts from the FLOOR. Gated to the
# authority (single-player / host) like whale spawning — networked hazard
# replication is a seam. Hazards.update itself early-outs unless a focus is in a
# hazard band, so this is free in the common case (mid-band flight, and the whole
# normal startup, since the arena spawn is mid-band).

func _update_hazards(delta: float) -> void:
	if _hazards == null:
		return
	if Net.is_online() and not Net.is_server():
		return
	_hazards.update(delta, _hazard_foci())


# --- Deep-air suffocation (player/life_support.gd) --------------------------
#
# The depth half of "equipment gates altitude in both directions" (WORLD_SPEC).
# Below the deep band the air is unbreathable; an unprotected person suffocates,
# taking periodic GRIT damage, unless they carry the craftable Aether Lung. The
# person's air, so it reads the player's own position (on foot, at the helm, or
# riding). OFF-COST: the tick early-outs unless the body is actually in the deep
# unprotected, so mid-band flight and the whole normal startup pay nothing.

## The LOCAL player's altitude fraction (0 = floor, 1 = ceiling) against this
## scale's world rect, or -1 when there is no world / no player — the same
## convention Airspace and Hazards use. Airspace.bounds is empty in flight, so the
## rect (framed in _ready) is the live source.
func _player_altitude_frac() -> float:
	if _world_rect.size.y <= 0.0 or player == null or not is_instance_valid(player):
		return -1.0
	return clampf((_world_rect.end.y - player.global_position.y) / _world_rect.size.y,
		0.0, 1.0)


## THE EARTH'S CORE (owner 2026-08-23): the bottom slice of the world is molten
## lava — touch it and "you can just say goodbye". Any SHIP whose lowest point
## dips into the core is consumed whole (no crush, no mining — instant); any PERSON
## in it dies and respawns at base. Authority / single-player only (the server owns
## ships; networked player-death is the same documented seam as suffocation). Cheap:
## a couple of comparisons per ship, no per-cell work (the owner's per-cell veto).
func _update_lava_core(delta: float) -> void:
	if _lava_core == null or _world_rect.size.y <= 0.0:
		return
	if Net.is_online() and not Net.is_server():
		return
	var frac := _lava_core.top_frac
	# Ships (the player's, enemies, creatures alike): consumed on contact. Measured
	# at the hull's LOWEST solid point (no rotation — the upright rule), so the sea
	# eats you when the keel touches, not only when the centre crosses.
	for ship in fleet.ships():
		if not is_instance_valid(ship):
			continue
		var bottom := ship.global_position.y + ship.solid_bounds.end.y
		if LavaCore.is_in_core(_world_rect, frac, bottom):
			_consume_in_lava(ship)
	# The on-foot player (a piloted/ridden body is handled when its ship is eaten).
	if player != null and is_instance_valid(player) \
			and not player.is_piloting() and not player.is_riding() \
			and LavaCore.is_in_core(_world_rect, frac, player.global_position.y):
		_notify("the core swallows you")
		respawn_player()


## Consume `ship` in the lava: a rider goes down with it (killed → respawn, which
## also nets them a fresh ship), then the hull is gone. Order matters — clear
## local_ship and the pilot claim FIRST so the respawn safety-net sees "no ship"
## and re-gives one, and _refresh_local_ship never re-binds the dying hull. The
## whale/kraken AI entry is dropped so a freed creature is never ticked. Instant
## and total — the "say goodbye" the owner asked for.
func _consume_in_lava(ship: Ship) -> void:
	var rider: bool = player != null and is_instance_valid(player) \
		and (player.piloting == ship or player.riding == ship)
	if ship == local_ship:
		local_ship = null
	ship.pilot_peer = 0   # so the respawn's _refresh_local_ship skips this dying hull
	_whale_ais.erase(ship.get_instance_id())
	if rider:
		_notify("your ship sinks into the core — say goodbye")
		respawn_player()   # disembarks/dismounts (ship still valid), re-ships, heals
	ship.destroyed.emit()
	ship.queue_free()


## Drive one frame of deep-air suffocation for the local player. Each machine
## drains its OWN body's pool (networked player-damage replication is a documented
## seam); LifeSupport.tick carries the whole off-cost gate + the possession check.
func _update_suffocation(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_locally_controlled():
		return
	_suffocate_cd = LifeSupport.tick(player, _player_altitude_frac(), delta, _suffocate_cd)


## Deep-air status for the HUD warning (HudLayer): {"deep": the local body is in
## unbreathable air, "protected": it carries life-support}. Only reports "deep"
## when the air is actually unbreathable, so the warning is silent everywhere
## else — the calm screen. Cheap (a couple of comparisons); no allocation to speak
## of beyond the small dict.
func depth_status() -> Dictionary:
	var out := {"deep": false, "protected": false}
	if player == null or not is_instance_valid(player):
		return out
	if not LifeSupport.air_unbreathable(_player_altitude_frac()):
		return out
	out["deep"] = true
	out["protected"] = LifeSupport.protected(player.inventory)
	return out


## Deep-band ember-haze density (0..1) at the local body's altitude, for DeepFog.
## 0 in the breathable bands, thickening through the deep to a murk at the floor.
## The pure ramp lives in DeepFog.density_at; 0 when there is no world/player.
func fog_density() -> float:
	var a := _player_altitude_frac()
	if a < 0.0:
		return 0.0
	return DeepFog.density_at(a)


## The hazard foci: the player and every ship — the same set that streams terrain
## and reveals the map. Hazards only fire near one of these (resident-world rule).
func _hazard_foci() -> Array:
	var foci: Array = []
	if player != null and is_instance_valid(player):
		foci.append(player.global_position)
	if fleet != null:
		for ship in fleet.ships():
			if is_instance_valid(ship):
				foci.append(ship.global_position)
	return foci


## Every ship (any faction — the player's included) gets its `collision_damage`
## signal wired to the floating-number manager, once. Lazily per frame like the
## enemy-provocation wiring, so severed wreckage and late-spawned whales are
## caught too; the guard set means a bound callable is never re-connected.
func _watch_collisions() -> void:
	if _damage_numbers == null or fleet == null:
		return
	for ship in fleet.ships():
		if not is_instance_valid(ship):
			continue
		var id := ship.get_instance_id()
		if _collision_watched.has(id):
			continue
		_collision_watched[id] = true
		ship.collision_damage.connect(_on_collision_damage.bind(ship))
		# Gunfire floats through the SAME coalescing manager — a whale soaking a
		# turret burst now shows one growing number, not silence (owner 2026-08-23).
		ship.combat_damage.connect(_on_collision_damage.bind(ship))


## Wire the local player's `died` signal once, so a 0-HP death respawns the body.
## Lazy per-frame (the body can be re-created) and guarded by id, exactly like the
## collision wiring above.
func _watch_player_death() -> void:
	if player == null or not is_instance_valid(player):
		return
	var id := player.get_instance_id()
	if _player_death_watched.has(id):
		return
	_player_death_watched[id] = true
	player.died.connect(_on_player_died.bind(player))


## The player's GRIT pool hit zero: respawn the body on the deck with a full pool
## (respawn_player restores it). Only THIS machine's local body respawns here —
## networked player-damage replication is a documented seam (BACKLOG).
func _on_player_died(dead: Player) -> void:
	if dead != player:
		return
	respawn_player()


## A collision bit `ship` at `world_pos`. Coalesce it into a floating number
## keyed by the ship plus a spatial bucket (see DamageNumbers).
func _on_collision_damage(world_pos: Vector2, amount: float, ship: Ship) -> void:
	if _damage_numbers == null or not is_instance_valid(ship):
		return
	_damage_numbers.add(ship.get_instance_id(), world_pos, amount, float(world_scale))


func _has_driver(ship: Ship) -> bool:
	for npc in _npcs:
		if is_instance_valid(npc) and npc.ship == ship and npc.role == "driver":
			return true
	return false


func _on_hostile_ship_damaged(_cell: Vector2i, _amount: float, ship: Ship) -> void:
	if not is_instance_valid(ship):
		return
	var id := ship.get_instance_id()
	_enemy_aggro[id] = true
	_enemy_provoked_at[id] = Time.get_ticks_msec()


func _has_gunner(ship: Ship) -> bool:
	for npc in _npcs:
		if is_instance_valid(npc) and npc.ship == ship and npc.role == "gunner":
			return true
	return false


func _nearest_ship_of_faction(from: Ship, faction: int) -> Ship:
	var best: Ship = null
	var best_d := INF
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship == from or ship.faction != faction:
			continue
		var d := from.global_position.distance_to(ship.global_position)
		if d < best_d:
			best_d = d
			best = ship
	return best


## The starter vessel is authored in res://ships/starter.ship — an editable
## ASCII blueprint, the shared talking point for layout discussion. Design
## rules (clear deck, doors both sides, hatch exit, near-neutral trim) are
## documented in the file itself and in docs/DECISIONS.md. The real file
## is native 8× (true component footprints, no upscale); the legacy 1×
## test scene loads the frozen fixture instead.
func _starter_cells() -> Dictionary:
	if world_scale > 1:
		return ShipLayout.load_cells("res://ships/starter.ship")
	return ShipLayout.load_cells("res://tests/fixtures/starter_1x.ship")


# --- Loop ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_refresh_local_ship()
	_refresh_local_player()
	_stream_terrain()
	_update_discovery()
	_watch_collisions()
	_watch_player_death()
	if _damage_numbers != null:
		_damage_numbers.update(delta)
	_enemy_fire(delta)
	_enemy_pilot(delta)
	_creature_swim(delta)
	_handle_taming(delta)
	_handle_riding(delta)
	_handle_ridden_mining(delta)
	_update_hazards(delta)
	_update_suffocation(delta)
	_update_lava_core(delta)

	# Whale/collision diagnostic: one row per whale per frame while ON. Gated
	# on a single bool so it costs nothing in normal play (see whale_diag.gd).
	if _whale_diag != null and _whale_diag.enabled:
		# The live-Shot population is the swarm the old whale-only log was blind
		# to; the group lookup runs ONLY while recording (see whale_diag.gd).
		_whale_diag.capture_frame(fleet.ships(), delta,
			get_tree().get_nodes_in_group("shots").size())

	# Losing the control panel means losing control (owner): if the helm
	# was shot away while you stood at it, you are dumped on deck and the
	# ship coasts until the panel is repaired.
	if player != null and player.is_piloting() and not player.piloting.has_helm():
		player.disembark()

	# WASD flies the ship only while you are actually at the helm. On foot it
	# walks and jumps — see player.gd.
	if player != null and player.is_piloting():
		# Propeller thrust vectors, as the original does it: A/D push the ship
		# left/right, W/S push it up/down. The ship stays level; it does not
		# steer like a car.
		player.piloting.net_set_controls(
			Input.get_axis("ship_left", "ship_right"),
			Input.get_axis("ship_down", "ship_up"))

	if player != null and player.global_position.y > WORLD_BOTTOM:
		respawn_player()

	_track_camera()


## Dead centre on the player, every frame, nothing else. The player is the
## subject on foot and at the helm alike. At the helm the view pulls back
## by pilot_zoom_out (position stays hard-locked — the smoothing veto was
## about camera *motion*, zoom eases scale only).
func _track_camera() -> void:
	if player != null:
		camera.global_position = player.global_position
	elif is_instance_valid(local_ship):
		camera.global_position = local_ship.global_position

	var target := camera_zoom * _zoom_user
	# Pull the view back both at the helm AND when riding a tamed whale — steering
	# a whale is piloting a (living) ship, and you want the same wide situational
	# view (owner 2026-08-23: "when a beast you're grappled on to is tamed it
	# should zoom out as if piloting a ship").
	if player != null and (player.is_piloting() or player.is_riding()):
		target /= pilot_zoom_out
	camera.zoom = camera.zoom.lerp(Vector2(target, target), 0.12)


## Scroll wheel zooms; everything else about the camera stays hard-locked.
## Global UI hotkeys are handled at the INPUT stage — BEFORE the GUI can swallow a
## key by focus — so a toggle always fires on the FIRST press. This fixes F9 (the
## saves panel) needing several presses (owner 2026-08-23): after touching a
## focusable debug-window control, keyboard focus lived on that control and ate the
## key before it reached _unhandled_key_input. Handled here and marked consumed, so
## it neither leaks to a focused control nor double-fires later. The saves-panel
## arrows/Enter are intercepted ONLY while the panel is open (scoped, so they do not
## hijack focus navigation elsewhere); everything else (H/J, the Konami salute, the
## trainer number row) stays in _unhandled_key_input.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not (event as InputEventKey).echo):
		return
	var keycode := (event as InputEventKey).keycode
	if _save_panel != null and _save_panel.visible:
		match keycode:
			KEY_UP:
				_save_panel_navigate(-1)
				get_viewport().set_input_as_handled()
				return
			KEY_DOWN:
				_save_panel_navigate(1)
				get_viewport().set_input_as_handled()
				return
			KEY_ENTER, KEY_KP_ENTER:
				_load_selected()
				get_viewport().set_input_as_handled()
				return
	match keycode:
		KEY_F1:
			_toggle_help()
		KEY_TAB:
			_toggle_map()
		KEY_K:
			_toggle_character_sheet()
		KEY_F2:
			_toggle_debug_window()
		KEY_F3:
			_toggle_whale_diag()
		KEY_F5:
			save_game()
		KEY_F9:
			_toggle_save_panel()
		_:
			return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_user = clampf(_zoom_user + 0.1, 0.5, 1.5)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_user = clampf(_zoom_user - 0.1, 0.5, 1.5)


func _process(_delta: float) -> void:
	# Wall-clock time played, for the save metadata. Carried across a load so the
	# counter continues from where the save left off (see load_game).
	_playtime += _delta
	_update_corner_status()
	# Inventory + pickup floats run every frame, ship or no ship — mining is an
	# on-foot activity and the readout (HudLayer) should never blank out.
	if _pickups != null:
		_pickups.update(_delta)
	_handle_mining(_delta)
	_handle_placing(_delta)
	if Input.is_action_just_pressed("mat_cycle"):
		_cycle_material()
	_handle_crafting()
	# Handled before anything else, so they still work when the rest is broken.
	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()
		return
	if Input.is_action_just_pressed("reset_world"):
		reset_world()
		return
	if Input.is_action_just_pressed("respawn_player"):
		respawn_player()

	if local_ship == null:
		hud.text = ("Connecting to host..." if Net.is_online()
			else "No ship — this is a bug. H host   J join localhost")
		_ghost_shown = false
		_ghost_label.visible = false
		return

	_handle_interact()

	if Input.is_action_just_pressed("build_cycle"):
		build_type = (build_type + 1) % BlockDB.type_count()
		if build_type == BlockDB.Type.DOOR:
			# Placed doors start CLOSED (owner): the open state is a
			# runtime state, never a thing you place.
			build_type = (build_type + 1) % BlockDB.type_count()

	# CARCASS-AS-AIRSHIP, the thrust half (owner: "bolt on lift+THRUST to fly a
	# corpse"): the build verbs target a CARCASS under the cursor (within arm's
	# reach) when there is one — place engines/props/a helm on a dead whale,
	# then board it and FLY it — and your own ship otherwise, exactly as before.
	var build_ship := _build_target(get_global_mouse_position())
	var cell := build_ship.cell_at_global(get_global_mouse_position())
	_update_build_ghost(build_ship, cell)

	var ui_mouse := _ui_wants_mouse()  # a hovered debug/saves/help panel eats clicks
	if Input.is_action_just_pressed("build_place") and not ui_mouse:
		build_ship.net_set_block(cell, build_type)
	if Input.is_action_just_pressed("build_remove") and not ui_mouse:
		build_ship.net_remove_block(cell)
	if Input.is_action_pressed("debug_damage") and not ui_mouse:
		build_ship.net_damage_cell(cell, 4.0)

	# RMB: the grapple, exactly as the original — fire toward the cursor; fire
	# again to let go early. On foot only; the helm has your hands. While RIDING,
	# the grapple is the leash: RMB releases it, which ends the ride (owner
	# 2026-08-24 — "unlatch my hook, not F"). _handle_taming sees the hook drop
	# next frame and steps you off.
	if Input.is_action_just_pressed("grapple") and not ui_mouse and player != null \
			and not player.is_piloting():
		if player.hook_active():
			player.release_grapple()
		elif not player.is_riding():
			player.fire_grapple(get_global_mouse_position() - player.global_position)

	_handle_shooting(get_process_delta_time())
	_handle_repair(get_process_delta_time())

	_update_hud(cell)
	queue_redraw()


# --- Build ghost -----------------------------------------------------------
#
# Show the block BEFORE it exists: a translucent preview at the cursor's
# cell, green when Q would really build there and red when it would be
# refused, plus what the placement would do to lift-to-weight. Entirely
# local — no RPC, no state, and `ship.blocks` is never touched. It is
# recomputed once per frame here so the HUD, the cursor label and the
# overlay all read one consistent answer instead of three.

var _ghost_shown := false
var _ghost_cell := Vector2i.ZERO
var _ghost_valid := false
var _ghost_ratio_now := 0.0
var _ghost_ratio_next := 0.0
## The ship the ghost (and Q/C/G) currently target — local_ship, or a CARCASS
## under the cursor (the carcass-as-airship build loop).
var _ghost_ship: Ship = null


## The ship the build verbs operate on this frame: a CARCASS whose grid is under
## the cursor — an occupied cell or a legal adjacent build spot — AND within
## arm's reach (corpse-building is reach-gated like harvesting; your own ship
## keeps its reach-free build, unchanged). Otherwise local_ship. This is the
## "thrust onto a corpse" seam: place engines/props/a helm on a dead whale,
## then board its helm and fly the body.
func _build_target(cursor: Vector2) -> Ship:
	if fleet != null and player != null and is_instance_valid(player):
		for ship in fleet.ships():
			if not is_instance_valid(ship) or not ship.is_carcass():
				continue
			var cell := (ship as Ship).cell_at_global(cursor)
			if (ship.has_block(cell) or ship.can_place_at(cell)) \
					and _carcass_cell_in_reach(ship, cell):
				return ship
	return local_ship


func _update_build_ghost(ship: Ship, cell: Vector2i) -> void:
	# Declutter (owner 2026-08-22): the ghost used to hang at the cursor across
	# the whole sky. Show it only where building is actually in play — over the
	# target ship (an occupied cell) or adjacent to it (can_place_at) — so open
	# sky stays calm. Never while piloting; the helm has your hands.
	_ghost_ship = ship
	_ghost_shown = is_instance_valid(ship) and player != null \
		and not player.is_piloting() \
		and (ship.can_place_at(cell) or ship.has_block(cell))
	if not _ghost_shown:
		_ghost_label.visible = false
		return
	_ghost_cell = cell
	# EXACTLY the condition net_set_block enforces (Ship.can_place_at):
	# occupied cell, or no neighbour to build off. The ghost is green if
	# and only if pressing Q would really place a block — anything else
	# teaches the player a rule the game does not have. Note the game
	# imposes no reach limit on building on YOUR ship; a carcass target is
	# already reach-gated by _build_target.
	_ghost_valid = ship.can_place_at(cell)
	_ghost_ratio_now = ship.lift_ratio()
	_ghost_ratio_next = BuildPreview.ratio_with(ship, build_type)

	_ghost_label.text = BuildPreview.readout(_ghost_ratio_now, _ghost_ratio_next)
	_ghost_label.add_theme_color_override("font_color", _ghost_tint())
	# Offset up-right of the pointer so the cursor itself stays unobscured.
	_ghost_label.position = get_viewport().get_mouse_position() + Vector2(16, -26)
	_ghost_label.visible = true


func _ghost_tint() -> Color:
	return Color(0.40, 1.0, 0.50) if _ghost_valid else Color(1.0, 0.40, 0.38)


## What WorldOverlay should draw, or null. The ship is resolved to plain
## values HERE rather than handed over as a node: passing live references
## into another node's _draw is what crashed the [F] prompt on freed
## instances (see interact_prompt).
func build_ghost() -> Variant:
	if not _ghost_shown or _ghost_ship == null or not is_instance_valid(_ghost_ship):
		return null
	var origin := _ghost_ship.local_pos_of(_ghost_cell) - Vector2.ONE * Ship.CELL * 0.5
	return [
		_ghost_ship.global_transform,
		Rect2(origin, Vector2.ONE * Ship.CELL),
		BlockDB.color_of(build_type),
		_ghost_tint(),
	]


## The repair wand (owner, from the original): hold X and sweep the mouse.
## Reach is effectively the screen — no distance check on purpose — and it
## slowly restores the ship toward its blueprint, including a shot-out
## control panel (the way back from "uncontrollable"). On foot only; at
## the helm your hands are full.
const REPAIR_RATE := 45.0  # hp per second under the cursor


func _handle_repair(delta: float) -> void:
	if player == null or player.is_piloting():
		return
	if not Input.is_action_pressed("repair") or _ui_wants_mouse():
		return
	if not is_instance_valid(local_ship):
		return
	local_ship.net_repair_near(
		local_ship.cell_at_global(get_global_mouse_position()),
		Tunables.get_num("repair_rate") * delta)


# --- Mining ----------------------------------------------------------------
#
# Dig terrain out of the world; the removed cell becomes an item you carry
# (player/inventory.gd). Sprint 2's payoff on the terrain foundation, judged
# for feel against Terraria (MARKET.md §3): tactile, fast, immediate.
#
# INPUT: hold Z (the `mine` action) and aim with the cursor — deliberately the
# same "hold + sweep the mouse" idiom as the repair wand (X), and a left-hand
# key beside build (Q) and deconstruct (C), its natural siblings. It does not
# collide with LMB shoot / RMB grapple, so you can carry a sidearm and a pick.
# On foot only; at the helm your hands fly the ship.
#
# RESPONSIVENESS: a per-cell DIG TIME set by the cell's hardness, not a flat
# cooldown — the more Terraria-tactile of the two options the brief offered.
# Dirt pops almost instantly, stone takes longer, ore longest, so the material
# you are cutting is legible in the FEEL of cutting it (and it gives ore its
# weight — a reason the pocket is worth digging for). It reuses TerrainDB's
# existing per-type hp as the hardness, so there is one number to tune per
# material and no parallel table. Progress accumulates on the targeted cell
# while Z is held; moving the cursor to a different cell resets it (you commit
# to one cell at a time, as in Terraria). The cell vanishing IS the feedback,
# the instant progress completes — plus a floating "+N Material" pickup.

## Mining speed in hardness-points per second. The dig time for a cell is its
## TerrainDB hp / this: at 240 that is dirt (40hp) ~0.17s, stone (120) ~0.5s,
## ore (200) ~0.83s — snappy on soft ground, weighty on ore. THE tactility knob.
const MINE_POWER := 240.0

## How far you can reach to mine, in cells (× world_scale) — arm's reach, the
## same idea as the interact/door reach (Ship.CELL * 1.5), a little longer so a
## cursor a few cells out still bites. A cell past this does nothing (the gate
## the break-the-fix test removes). Measured player-centre to cell-centre.
const MINE_REACH_CELLS := 4.5

## The cell currently being cut, and progress (hardness points) into it. Progress
## resets when the target changes or Z is released — you dig one cell at a time.
## The SAME cut machinery serves terrain mining and carcass harvesting: when
## `_harvest_ship` is non-null the current cut is a whale-product harvest on that
## carcass at `_mine_cell` (a ship-local cell); when it is null the cut is a
## terrain dig at `_mine_cell` (a terrain cell). One cut is active at a time, so
## Z never mines terrain and harvests a corpse in the same breath.
var _mine_cell := Vector2i.ZERO
var _mine_progress := 0.0
var _mine_active := false
var _harvest_ship: Ship = null

## PLACEMENT (the inverse of mining): hold V + aim to write a held terrain
## material into an empty, in-reach cell. Placing is instant per cell but rate-
## limited so a held key PAINTS a line rather than dumping a whole stack into one
## frame — the build/repair "hold + sweep" idiom, one cell at a time.
const PLACE_COOLDOWN := 0.08
var _place_cooldown := 0.0
## The material the place action lays down — a TerrainDB.Type item id the player
## carries. B cycles it through the placeable materials in the inventory.
var _held_material: int = TerrainDB.Type.DIRT

## CRAFTING: the selected recipe (index into Recipes.RECIPES). N cycles it, M
## crafts it if the inputs are present (items/recipes.gd). Deliberately tiny —
## the seam the economy grows on, not a recipe tree.
var _recipe_index := 0

# --- The SCOOP (terrain SUBDIV — one bite = one coarse cell) ----------------
#
# At terrain subdiv S every old cell is S×S fine cells. Mining and placing keep
# their OLD granularity and economy by operating in SCOOPS — the coarse-cell
# footprint containing the aimed fine cell: one completed cut digs the whole
# scoop, one placement paints it, and the credit/debit accumulators below turn
# S² fine cells into exactly ONE item either way. At subdiv 1 a scoop is a
# single cell and every accumulator step fires immediately — bit-for-bit the
# old behaviour. (An ITEM therefore stays "one coarse cell of material": no 64×
# inflation of the mining economy, recipes and trade values keep their meaning.)

## Fine-cell origin (top-left) of the scoop containing `cell`.
func _scoop_origin(cell: Vector2i) -> Vector2i:
	var s := terrain.subdiv
	return Vector2i(floori(float(cell.x) / s) * s, floori(float(cell.y) / s) * s)


## Every fine cell of the scoop containing `cell`.
func _scoop_cells(cell: Vector2i) -> Array:
	var o := _scoop_origin(cell)
	var s := terrain.subdiv
	var out: Array = []
	for dy in s:
		for dx in s:
			out.append(o + Vector2i(dx, dy))
	return out


## Dig-time threshold for a scoop: the hardest SOLID cell in it (uniform scoops
## — the common case — behave exactly like the old single cell).
func _scoop_max_hp(cell: Vector2i) -> float:
	var hp := 0.0
	for sc in _scoop_cells(cell):
		var t := terrain.cell_type(sc)
		if TerrainDB.is_solid(t):
			hp = maxf(hp, TerrainDB.max_hp(t))
	return maxf(hp, 1.0)


## Fine cells accumulated toward one ITEM, keyed Vector2i(peer_id, type) —
## dig credit and place debit kept separately. Remainders persist, so partial
## scoops (island edges) are never lost, just carried to the next dig.
var _dig_credit := {}
var _place_debt := {}


func _handle_mining(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.is_piloting() \
			or terrain == null:
		_mine_reset()
		return
	if not Input.is_action_pressed("mine") or _ui_wants_mouse():
		_mine_reset()
		return

	# One verb, two targets: dig SOLID terrain under the cursor, else HARVEST a
	# whale carcass under the cursor (the wiki's "the dismantle tool works on
	# corpses"). Terrain wins when it is solid and in reach, so mining ground you
	# are standing on never gets hijacked by a corpse drifting behind it.
	var cursor := get_global_mouse_position()
	var terrain_cell := terrain.world_to_cell(cursor)
	if terrain.is_solid(terrain_cell) and _cell_in_reach(terrain_cell):
		try_mine(terrain_cell, delta)
		return
	var target := _carcass_under(cursor)
	if not target.is_empty():
		try_harvest(target[0], target[1], delta)
		return
	_mine_reset()


## Advance mining on `target_cell` by `delta`; returns true if a cell was dug
## this call. Split out of _handle_mining — which only supplies the cursor cell
## and the held state — so the reach gate and the hardness dig-time are unit-
## testable without a mouse or an input map (see world_startup_test).
func try_mine(target_cell: Vector2i, delta: float) -> bool:
	if player == null or not is_instance_valid(player) or terrain == null:
		_mine_reset()
		return false
	# Reach gate + can't-mine-air: either one makes this a no-op (and stops any
	# progress), so an out-of-reach or empty cursor cell mines nothing.
	if not _cell_in_reach(target_cell) or not terrain.is_solid(target_cell):
		_mine_reset()
		return false

	# Commit to one SCOOP (the coarse-cell footprint — one fine cell at subdiv
	# 1): the anchor is the scoop origin, so the cursor wandering within the
	# same scoop keeps its progress, and moving to a new scoop — or away from a
	# harvest — restarts the cut.
	var anchor := _scoop_origin(target_cell)
	if not _mine_active or _harvest_ship != null or anchor != _mine_cell:
		_mine_cell = anchor
		_mine_progress = 0.0
		_mine_active = true
		_harvest_ship = null

	# BRAWN (Strong Arm / Quarryman / Juggernaut): dig speed scales with the perk.
	_mine_progress += Tunables.get_num("mine_power") * _mine_speed_mult() * delta
	if _mine_progress >= _scoop_max_hp(target_cell):
		# The dig is authority-owned (mirrors Ship.net_damage_cell): single-
		# player / server digs now and `dug` credits us (S² fine cells → one
		# item via the scoop accumulator); a client forwards each request.
		# Reset either way — a completed cut starts fresh on the next.
		for sc in _scoop_cells(target_cell):
			if terrain.is_solid(sc):
				terrain.net_dig(sc, _my_id())
		_mine_progress = 0.0
		_mine_active = false
		return true
	return false


## Advance HARVEST on `cell` of carcass `ship` by `delta`; returns true if a
## block was harvested this call. Mirrors try_mine exactly — same dig-time by
## hardness (the flesh block's hp), same reach gate, same shared progress — but
## on a corpse's flesh, yielding a whale-PRODUCT item rather than a terrain type.
## Only a CARCASS yields; a living whale returns nothing and keeps its blocks
## (Ship.harvest_cell enforces both). Authority-gated: grid mutation happens here
## in single-player / on the server; networked harvest is deferred (see Terrain).
func try_harvest(ship: Ship, cell: Vector2i, delta: float) -> bool:
	if player == null or not is_instance_valid(player) or ship == null \
			or not is_instance_valid(ship) or not ship.is_carcass() \
			or not ship.has_block(cell) \
			or ItemDB.whale_product_for(ship.blocks[cell]["type"]) < 0:
		_mine_reset()
		return false
	if not _carcass_cell_in_reach(ship, cell):
		_mine_reset()
		return false
	if not NetUtil.is_authority(self):
		# Networked harvest is deferred; a client never mutates the corpse grid.
		_mine_reset()
		return false

	# Commit to one (ship, cell): switching target — or away from terrain
	# mining — restarts the cut.
	if not _mine_active or _harvest_ship != ship or cell != _mine_cell:
		_mine_cell = cell
		_mine_progress = 0.0
		_mine_active = true
		_harvest_ship = ship

	# Harvest shares mining's dig-time, and BRAWN speeds it the same way.
	_mine_progress += Tunables.get_num("mine_power") * _mine_speed_mult() * delta
	if _mine_progress >= BlockDB.max_hp(ship.blocks[cell]["type"]):
		var world_pos := ship.to_global(ship.local_pos_of(cell))
		var item := ship.harvest_cell(cell)  # removes the block, returns the product
		if item >= 0 and player != null:
			player.inventory.add(item)
			if _pickups != null:
				_pickups.add(world_pos, "+1 %s" % ItemDB.name_of(item), float(world_scale))
			# Cracking the corpse spills its stomach cargo — once per carcass.
			var loot := ship.take_stomach_loot()
			if loot >= 0:
				player.inventory.add(loot)
				if _pickups != null:
					_pickups.add(world_pos, "+1 %s" % ItemDB.name_of(loot), float(world_scale))
		_mine_progress = 0.0
		_mine_active = false
		return true
	return false


func _mine_reset() -> void:
	_mine_active = false
	_mine_progress = 0.0
	_harvest_ship = null


## Is `cell` within mining reach of the player? Player-centre to cell-centre,
## in the same world-scaled cell units as the interact reach.
func _cell_in_reach(cell: Vector2i) -> bool:
	if player == null or terrain == null:
		return false
	var reach := _mine_reach_cells() * TerrainDB.CELL * world_scale
	return player.global_position.distance_to(terrain.cell_center(cell)) <= reach


## Mining/harvesting speed multiplier from the player's BRAWN perks (1.0 with no
## perk). One place so terrain mining and carcass harvesting scale together.
func _mine_speed_mult() -> float:
	if player == null or not is_instance_valid(player) or player.stats == null:
		return 1.0
	return player.stats.mine_power_mult()


## Effective mining/harvesting reach in cells: the base plus the BRAWN Long Reach
## bonus (0 without it). One place so both reach checks agree.
func _mine_reach_cells() -> float:
	var bonus := 0.0
	if player != null and is_instance_valid(player) and player.stats != null:
		bonus = player.stats.mine_reach_bonus()
	return Tunables.get_num("mine_reach_cells") + bonus


## Is a carcass `ship`'s `cell` within harvest reach? Same reach as mining, but
## measured to the block's world position on the corpse (which may be posed off
## level) rather than a terrain cell centre.
func _carcass_cell_in_reach(ship: Ship, cell: Vector2i) -> bool:
	if player == null or ship == null or not is_instance_valid(ship):
		return false
	var reach := _mine_reach_cells() * TerrainDB.CELL * world_scale
	return player.global_position.distance_to(
		ship.to_global(ship.local_pos_of(cell))) <= reach


## The carcass flesh cell under `cursor`, as [ship, cell], or [] if none. Scans
## the fleet for CARCASSES (only a dead creature yields; a living whale and a
## plain vessel are skipped) whose cell under the cursor is a harvestable flesh
## block. Nearest carcass wins so overlapping corpses disambiguate cleanly.
func _carcass_under(cursor: Vector2) -> Array:
	if fleet == null:
		return []
	var best: Ship = null
	var best_cell := Vector2i.ZERO
	var best_d := INF
	for ship in fleet.ships():
		if not is_instance_valid(ship) or not ship.is_carcass():
			continue
		var cell := ship.cell_at_global(cursor)
		if not ship.has_block(cell):
			continue
		if ItemDB.whale_product_for(ship.blocks[cell]["type"]) < 0:
			continue  # a component cell on the corpse — not harvestable flesh
		var d := cursor.distance_to(ship.to_global(ship.local_pos_of(cell)))
		if d < best_d:
			best_d = d
			best = ship
			best_cell = cell
	return [best, best_cell] if best != null else []


# --- Tethered balloons: carcass-as-airship (owner 2026-08-23) ----------------
#
# Buoyancy alone only makes a thing float; to FLY a corpse (which carries no lift)
# you bolt on helium balloons via cables. On foot, aim at any hull/corpse cell and
# press U to tether a balloon there (Y cycles small/large); its lift folds into the
# body's total (Ship.rebuild), so a mined-down carcass with a few balloons flies.
# Attaching is on-foot only (your hands do it) and authority-gated like the other
# grid edits; networked attach is a documented seam.

## The nearest ship with a solid cell under `cursor`, as [ship, cell] (or []).
## Any ship — your vessel, a carcass, a living creature — so you can balloon a
## corpse you are standing on or a hull you built.
func _ship_cell_under(cursor: Vector2) -> Array:
	if fleet == null:
		return []
	var best: Ship = null
	var best_cell := Vector2i.ZERO
	var best_d := INF
	for ship in fleet.ships():
		if not is_instance_valid(ship):
			continue
		var cell := ship.cell_at_global(cursor)
		if not ship.has_block(cell):
			continue
		var d := cursor.distance_to(ship.to_global(ship.local_pos_of(cell)))
		if d < best_d:
			best_d = d
			best = ship
			best_cell = cell
	return [best, best_cell] if best != null else []


func _attach_balloon_at_cursor() -> void:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return
	var target := _ship_cell_under(get_global_mouse_position())
	if target.is_empty():
		_notify("aim at a hull or corpse cell to tether a balloon")
		return
	try_attach_balloon(target[0], target[1], _balloon_size)


## Tether a balloon of `size` at (ship, cell). Reach-gated (arm's length, like
## mining/harvest) and authority-gated. Returns whether it attached.
func try_attach_balloon(ship: Ship, cell: Vector2i, size: int) -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.has_block(cell):
		return false
	if not _carcass_cell_in_reach(ship, cell):
		_notify("too far — get closer to tether a balloon")
		return false
	if not NetUtil.is_authority(self):
		return false  # networked balloon attach is a seam, like harvest
	if ship.attach_balloon(cell, size):
		_notify("balloon tethered (%s) — lift +%d"
			% ["large" if size == 1 else "small", int(Ship.BALLOON_LIFT[size])])
		return true
	return false


## Draw specs for every attached balloon, for WorldOverlay (which owns no ship
## references). Each: the anchor cell's world point, the balloon centre (above it
## on a taut cable, with a gentle decorative sway), its radius, and the cable count.
func balloons_to_draw() -> Array:
	var out: Array = []
	if fleet == null:
		return out
	var t := Time.get_ticks_msec() / 1000.0
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.balloons.is_empty():
			continue
		var i := 0
		for b in ship.balloons:
			var size := int(b["size"])
			var u: float = ship.scale_unit
			var anchor: Vector2 = ship.to_global(ship.local_pos_of(b["cell"]))
			var lc := Ship.BALLOON_CABLE_CELLS * Ship.CELL * u
			var sway := sin(t * 1.2 + anchor.x * 0.002 + float(i)) * Ship.CELL * u * 0.8
			out.append({
				"anchor": anchor,
				"center": anchor + Vector2(sway, -lc),
				"radius": Ship.BALLOON_RADIUS_CELLS[size] * Ship.CELL * u,
				"cables": int(Ship.BALLOON_CABLES[size]),
				"unit": u,
			})
			i += 1
	return out


## The authority mined `cell` (type) on behalf of `peer_id`. Credit that peer's
## inventory and pop a pickup float. Runs on the authority; in single-player the
## miner is always the local player. (Replicating the credit + the terrain edit
## to a requesting client is deferred networked-terrain work — see Terrain.)
func _on_terrain_dug(peer_id: int, cell: Vector2i, type: int) -> void:
	# SCOOP accumulator: S² fine cells of a material = ONE item (see "The
	# SCOOP"). At subdiv 1 the threshold is 1 and every dug cell credits
	# immediately — the old behaviour exactly. The pickup float pops only when
	# an item actually lands, so a scoop reads "+1 Stone", not 64 sparks.
	var sub2 := terrain.subdiv * terrain.subdiv
	var key := Vector2i(peer_id, type)
	_dig_credit[key] = int(_dig_credit.get(key, 0)) + 1
	if _dig_credit[key] < sub2:
		return
	_dig_credit[key] = int(_dig_credit[key]) - sub2
	var who: Player = _placer_for(peer_id)
	if who != null:
		who.inventory.add(type)
	if _pickups != null and terrain != null:
		_pickups.add(terrain.cell_center(cell),
			"+1 %s" % ItemDB.name_of(type), float(world_scale))


## The authority PLACED `cell` (type) on behalf of `peer_id` — the inverse of a
## dig. Debit ONE of that material per S² fine cells (the scoop accumulator,
## symmetric with the dig credit; at subdiv 1 that is every cell) and pop a
## "-1" float when the debit lands. (Replicating the debit + the terrain edit
## to a requesting client is deferred networked-terrain work — see Terrain.)
func _on_terrain_placed(peer_id: int, cell: Vector2i, type: int) -> void:
	var sub2 := terrain.subdiv * terrain.subdiv
	var key := Vector2i(peer_id, type)
	_place_debt[key] = int(_place_debt.get(key, 0)) + 1
	if _place_debt[key] < sub2:
		return
	_place_debt[key] = int(_place_debt[key]) - sub2
	var who: Player = _placer_for(peer_id)
	if who != null:
		who.inventory.remove(type, 1)
	if _pickups != null and terrain != null:
		_pickups.add(terrain.cell_center(cell),
			"-1 %s" % ItemDB.name_of(type), float(world_scale))


## The Player to credit/debit for a terrain edit by `peer_id`: the owning body in
## a live session, or the local player in single-player (the authority's own edit).
func _placer_for(peer_id: int) -> Player:
	var who: Player = null
	if crew != null:
		who = crew.player_for(peer_id)
	if who == null:
		who = player
	return who


## What the WorldOverlay should draw for the mine target, or null: the world-
## space cell rect, the cut progress 0..1, and whether it is in reach. Resolved
## to plain values here (never a live node handed into another node's _draw).
func mine_target() -> Variant:
	if player == null or not is_instance_valid(player) or player.is_piloting() \
			or terrain == null:
		return null
	if not Input.is_action_pressed("mine"):
		return null
	var cell := terrain.world_to_cell(get_global_mouse_position())
	if not terrain.is_solid(cell):
		return null
	var in_reach := _cell_in_reach(cell)
	var cp := terrain.cell_px()
	# The highlight is the SCOOP footprint (one coarse cell — S×S fine cells),
	# matching exactly what a completed cut digs. At subdiv 1 this is the old
	# single-cell rect.
	var anchor := _scoop_origin(cell)
	var side := cp * float(terrain.subdiv)
	var origin := terrain.to_global(Vector2(anchor) * cp)
	var progress := 0.0
	if in_reach and _mine_active and _harvest_ship == null and anchor == _mine_cell:
		progress = clampf(_mine_progress / _scoop_max_hp(cell), 0.0, 1.0)
	return [Rect2(origin, Vector2(side, side)), progress, in_reach]


# --- Placement (the inverse of mining) -------------------------------------
#
# Hold V + aim to lay the held terrain material back into the world: an empty,
# in-reach cell becomes solid terrain and one item leaves the inventory. It is
# authority-owned exactly like mining (Terrain.net_place mirrors net_dig): the
# server writes the cell and `placed` debits the placer; a client forwards the
# request. Ship building (Q hull) is a SEPARATE system — this writes TERRAIN.

func _handle_placing(delta: float) -> void:
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	if player == null or not is_instance_valid(player) or player.is_piloting() \
			or terrain == null:
		return
	if not Input.is_action_pressed("place_terrain") or _ui_wants_mouse():
		return
	if _place_cooldown > 0.0:
		return
	if try_place(terrain.world_to_cell(get_global_mouse_position())):
		_place_cooldown = PLACE_COOLDOWN


## Place the held material into `target_cell`; returns true if a block was
## written. A no-op (nothing consumed, nothing written) when: the held material
## is not carried (empty stack), the cell is out of reach, or the cell is already
## solid. Split out of _handle_placing so the reach/solid/stock gates are unit-
## testable without a mouse (mirrors try_mine; see world_startup_test).
func try_place(target_cell: Vector2i) -> bool:
	if player == null or not is_instance_valid(player) or terrain == null:
		return false
	var mat := _held_placeable()
	if mat == TerrainDB.Type.AIR:
		return false  # nothing placeable in the pack
	if player.inventory.count(mat) <= 0:
		return false  # empty stack — cannot place what you do not carry
	if not _cell_in_reach(target_cell):
		return false  # out of reach (the break-the-fix gate)
	if terrain.is_solid(target_cell):
		return false  # occupied — mine it first
	# Paint the whole SCOOP (the coarse-cell footprint — one fine cell at
	# subdiv 1): the authority writes each empty fine cell and `placed` debits
	# via the scoop accumulator, so a full scoop costs exactly ONE item — the
	# inverse of the dig credit. Cells already solid inside the scoop are left
	# alone (a partial paint accrues partial debt, carried forward).
	var wrote := false
	for sc in _scoop_cells(target_cell):
		if not terrain.is_solid(sc):
			if terrain.net_place(sc, mat, _my_id()):
				wrote = true
	return wrote


## The material the place action will actually lay down: the held one if the
## player still carries it and it is placeable terrain, else the first placeable
## material in the pack, else AIR (nothing to place). Keeps the selection honest
## as stacks run out.
func _held_placeable() -> int:
	if player == null or not is_instance_valid(player):
		return TerrainDB.Type.AIR
	var inv := player.inventory
	if ItemDB.is_placeable_terrain(_held_material) and inv.count(_held_material) > 0:
		return _held_material
	for id in inv.types():
		if ItemDB.is_placeable_terrain(id):
			return id
	return TerrainDB.Type.AIR


## Cycle the held material to the next placeable terrain type in the pack (B).
## Only real terrain materials are placeable, so whale products and crafted goods
## are skipped. Wraps; no-op with nothing placeable held.
func _cycle_material() -> void:
	if player == null or not is_instance_valid(player):
		return
	var placeable: Array = []
	for id in player.inventory.types():
		if ItemDB.is_placeable_terrain(id):
			placeable.append(id)
	if placeable.is_empty():
		return
	var idx := placeable.find(_held_material)
	_held_material = placeable[(idx + 1) % placeable.size()]


## What the WorldOverlay should draw for the place target, or null: the world-
## space cell rect and whether the placement is legal (in reach, empty, stocked).
## Green legal / red blocked, the mirror of the mine highlight. Plain values only.
func place_target() -> Variant:
	if player == null or not is_instance_valid(player) or player.is_piloting() \
			or terrain == null:
		return null
	if not Input.is_action_pressed("place_terrain"):
		return null
	var cell := terrain.world_to_cell(get_global_mouse_position())
	var cp := terrain.cell_px()
	# The ghost is the SCOOP footprint — what try_place actually paints.
	var anchor := _scoop_origin(cell)
	var side := cp * float(terrain.subdiv)
	var origin := terrain.to_global(Vector2(anchor) * cp)
	var mat := _held_placeable()
	var legal := mat != TerrainDB.Type.AIR and player.inventory.count(mat) > 0 \
		and _cell_in_reach(cell) and not terrain.is_solid(cell)
	return [Rect2(origin, Vector2(side, side)), legal]


# --- Crafting --------------------------------------------------------------
#
# A tiny, data-driven make step (items/recipes.gd): N cycles the selected recipe,
# M crafts it. Crafting consumes the inputs from the inventory and adds the
# output — or does nothing at all if an input is missing (no partial spend).

func _handle_crafting() -> void:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return
	if Input.is_action_just_pressed("craft_cycle"):
		_recipe_index = (_recipe_index + 1) % Recipes.RECIPES.size()
	if Input.is_action_just_pressed("craft"):
		try_craft()


## Craft the selected recipe; returns true if it was made. Unit-testable without
## input (the craft logic itself lives in Recipes.craft — this just wires the
## player's inventory to it).
func try_craft() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var recipe: Dictionary = Recipes.RECIPES[_recipe_index]
	var made := Recipes.craft(player.inventory, recipe)
	if made and _pickups != null:
		# Pop the output over the player as feedback (crafting has no world cell).
		_pickups.add(player.global_position,
			"+%d %s" % [int(recipe.get("count", 1)), ItemDB.name_of(int(recipe["output"]))],
			float(world_scale))
	return made


## Piloting is entered by walking up to a helm and using it, exactly as the
## original does with its control panel — not by the ship being the default
## thing you control. The same key opens and closes doors (owner spec,
## session 3): the NEAREST interactable wins, so standing in a doorway a
## couple of cells from the helm toggles the door instead of boarding.
var _nearby_helm: Array = []
var _nearby_door: Array = []


func _handle_interact() -> void:
	if player == null:
		_nearby_helm = []
		_nearby_door = []
		return
	# Riding a tamed creature: the ride ends by releasing the hook (RMB — see the
	# grapple handler), not F. F still steps off as a harmless fallback, but is no
	# longer required (owner 2026-08-24). No helm/door search while mounted — that
	# is for when you are on your own two feet.
	if player.is_riding():
		_nearby_helm = []
		_nearby_door = []
		if Input.is_action_just_pressed("interact"):
			dismount_creature()
		return
	_nearby_helm = Player.find_helm(fleet.ships(), player.global_position, player.HELM_REACH)
	_nearby_door = Player.find_door(fleet.ships(), player.global_position, _door_reach())

	if not Input.is_action_just_pressed("interact"):
		return
	if player.is_piloting():
		player.disembark()
		return
	if _door_wins():
		(_nearby_door[0] as Ship).net_toggle_door(_nearby_door[1])
	elif not _nearby_helm.is_empty():
		player.board(_nearby_helm[0], _nearby_helm[1])


## Doors answer the interact key only at arm's length — you work a door
## you are standing at, not one across the room. Short reach plus
## nearest-wins is what disambiguates F in a cramped cabin: at the helm
## (the spawn cell) the door is out of reach entirely; pressed against a
## closed door, the door is the nearest station by a wide margin.
func _door_reach() -> float:
	return Ship.CELL * 1.5 * world_scale


func _door_wins() -> bool:
	return _station_dist(_nearby_door) < _station_dist(_nearby_helm)


## Distance from the player to a [ship, cell] station, INF when invalid —
## so "nearest interactable" comparisons stay one-liners.
func _station_dist(station: Array) -> float:
	if station.is_empty() or not is_instance_valid(station[0]) or player == null:
		return INF
	var ship: Ship = station[0]
	if not ship.has_block(station[1]):
		return INF
	return player.global_position.distance_to(
		ship.to_global(ship.local_pos_of(station[1])))


func helm_in_reach() -> bool:
	return not _nearby_helm.is_empty()


## Where the overlay should float the [F] prompt and what it should say,
## as [pos, text] — or null. Validity checks live HERE: handing the raw
## player/ship references to another node's _draw crashed on freed
## instances (respawn races the redraw).
func interact_prompt() -> Variant:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return null
	if _door_wins():
		var ship: Ship = _nearby_door[0]
		var closed: bool = ship.blocks[_nearby_door[1]]["type"] == BlockDB.Type.DOOR_CLOSED
		return [ship.to_global(ship.local_pos_of(_nearby_door[1])),
			"[F] open the door" if closed else "[F] close the door"]
	if _nearby_helm.is_empty() or not is_instance_valid(_nearby_helm[0]):
		return null
	var helm: Ship = _nearby_helm[0]
	return [helm.to_global(helm.local_pos_of(_nearby_helm[1])), "[F] take the helm"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var keycode := (event as InputEventKey).keycode

	# The global UI toggles (F1/F2/F3/F5/F9, Tab, K) and the saves-panel arrows/Enter
	# are handled earlier in _input(), so a focused control can never starve them
	# (owner: "F9 needs multiple presses"). What remains here are keys that are fine
	# to let the GUI see first: host/join, the passive Konami salute, and the trainer
	# number row (only meaningful with the shop panel open).

	# Watch for the hidden Konami salute (passive — the keys still do their day
	# jobs). Keep only enough recent keys to match the sequence.
	_konami_recent.append(keycode)
	if _konami_recent.size() > EasterEggs.KONAMI.size():
		_konami_recent = _konami_recent.slice(
			_konami_recent.size() - EasterEggs.KONAMI.size())
	if EasterEggs.konami_matches(_konami_recent):
		_konami_salute()
		_konami_recent.clear()
	match keycode:
		KEY_H:
			host_session()
		KEY_J:
			join_session()
		# Carcass-as-airship (owner 2026-08-23): U tethers a helium balloon at the
		# aimed hull/corpse cell; Y cycles small/large. Raw keys (U/Y are unbound in
		# the action map), gated on not being over a UI panel.
		KEY_Y:
			_balloon_size = (_balloon_size + 1) % Ship.BALLOON_LIFT.size()
			_notify("balloon size: %s" % ("large" if _balloon_size == 1 else "small"))
		KEY_U:
			if not _ui_wants_mouse():
				_attach_balloon_at_cursor()
		# Trainer shop keys — active only while the character sheet (the shop
		# panel) is open. 1–4 buy a level of a stat; 0 sells all salvage. Raw
		# keys like H/J/F1/Tab, so no project.godot binding and no clash with the
		# game's action map (nothing binds the number row).
		KEY_1:
			_train_from_sheet(0)
		KEY_2:
			_train_from_sheet(1)
		KEY_3:
			_train_from_sheet(2)
		KEY_4:
			_train_from_sheet(3)
		KEY_0:
			_sell_from_sheet()
		# (KEY_L scale toggle removed — owner: 8× is the game. The 1× scene
		# survives only as a headless test fixture.)


## The Old Salute easter egg: a harmless burst of celebratory floats over the
## player, and one playful line. Touches nothing about play, balance or the
## inventory — pure fun (maps/world/easter_eggs.gd). Not surfaced in the HUD.
func _konami_salute() -> void:
	if _pickups == null or player == null or not is_instance_valid(player):
		return
	var here := player.global_position
	_pickups.add(here + Vector2(0, -Ship.CELL * 2.0 * world_scale),
		"the winds remember you", float(world_scale))
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var off := Vector2(cos(ang), sin(ang)) * Ship.CELL * 3.0 * world_scale
		_pickups.add(here + off, "+1 spark", float(world_scale))


## F2 toggles the dev debug window (maps/world/debug_window.gd). A raw key handled
## here like F1/F3, so it stays out of the rebindable game controls.
func _toggle_debug_window() -> void:
	if _debug_window != null:
		_debug_window.toggle()


## F3 starts/stops the whale/collision diagnostic (maps/world/whale_diag.gd).
## A raw key handled here rather than an input-map action, so it stays out of
## the rebindable game controls — it is a debug toggle, like H/J.
func _toggle_whale_diag() -> void:
	if _whale_diag == null:
		return
	_whale_diag.toggle(fleet.ships())
	if _whale_diag.enabled:
		_diag_label.text = "● DIAG ON — recording whales -> %s" \
			% _whale_diag.resolved_path()
	_diag_label.visible = _whale_diag.enabled


## Put the player back on their ship. Used by the respawn key and by falling
## out of the world.
func respawn_player() -> void:
	if player == null:
		return
	if player.is_piloting():
		player.disembark()
	# Get off any mount cleanly too (the core can eat a ridden whale) — dismount is
	# guarded on the creature still existing, so a freed mount is safe.
	if player.is_riding():
		var mount := player.riding
		player.dismount()
		if is_instance_valid(mount):
			_whale_ai_for(mount).dismount()
	player.velocity = Vector2.ZERO
	# Safety net: never strand the local player shipless — e.g., the core just ate
	# their ship (owner: "say goodbye"). Single-player / host only; a fresh starter
	# at base beats the "No ship — this is a bug" dead end. (No-op when they still
	# have a ship: the guard only fires when local_ship is gone.)
	if (not Net.is_online() or Net.is_server()) and not is_instance_valid(local_ship):
		_give_ship_to(_my_id())
		_refresh_local_ship()
	var anchor := SHIP_START
	if is_instance_valid(local_ship):
		anchor = local_ship.global_position
	player.global_position = anchor + Vector2(PLAYER_SPAWN_CELL) * Ship.CELL * world_scale
	# A fresh body starts whole: refill the GRIT pool (a respawn from death OR from
	# falling out of the world both come through here). The pack is KEPT — the
	# simplest sane choice; on-death loot drop is a documented seam (BACKLOG).
	if player.stats != null:
		player.max_health = player.stats.max_health()
	player.health = player.max_health


## Debug convenience: throw away every ship and start over. Server-side only —
## a client resetting the shared world would be a strange thing to allow.
func reset_world() -> void:
	if Net.is_server():
		for ship in fleet.ships():
			ship.queue_free()
		await get_tree().process_frame

		_give_ship_to(1)
		if Net.is_online():
			for id in multiplayer.get_peers():
				_give_ship_to(id)
		else:
			_spawn_enemy_hulk()  # the target range resets with the world
			_spawn_whale()
			_spawn_critters()
			_spawn_kraken()
		await get_tree().process_frame

	_refresh_local_ship()
	respawn_player()


## Small, gray bottom-right corner: build number + FPS, plus the one always-on
## trace of everything that moved to a toggle. The whole "wall of numbers" is gone
## — this is the only permanent chrome (owner 2026-08-22).
func _update_corner_status() -> void:
	if _corner_label == null:
		return
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
	_corner_label.text = "F1 help   Tab map\nv%s   %d fps" % [
		ver, Engine.get_frames_per_second()]


## The inventory, as plain [color, name, count] rows for the HUD strip to draw as
## colour swatches (ItemDB.color_of) + counts — icons, not sentences. Empty when
## you carry nothing (a calm, blank corner).
func inventory_swatches() -> Array:
	var out: Array = []
	if player == null or not is_instance_valid(player) or player.inventory == null:
		return out
	for id in player.inventory.types():
		out.append([ItemDB.color_of(id), ItemDB.name_of(id), player.inventory.count(id)])
	return out


## The contextual cue state — what is usable RIGHT NOW at the cursor — as plain
## booleans + the text bits each cue needs. Split from rendering so the DECISION
## (HudCues.active) is unit-testable without a mouse (see the HudCues test). The
## mine / harvest / place fields are read off the same cursor logic the mine/place
## targets use, so a cue never lies about what a keypress would do.
func _cue_state() -> Dictionary:
	var s := {
		"piloting": false, "near_helm": false,
		"mineable": false, "harvestable": false, "placeable": false,
		"craftable": false, "near_trainer": false,
		"mine_name": "", "harvest_name": "", "place_name": "", "craft_text": "",
	}
	if player == null or not is_instance_valid(player):
		return s
	if player.is_piloting():
		s["piloting"] = true
		return s
	s["near_helm"] = not _nearby_helm.is_empty() or not _nearby_door.is_empty()
	s["near_trainer"] = _near_trainer()

	# Craft: the selected recipe's inputs are present.
	if player.inventory != null and Recipes.RECIPES.size() > 0:
		var recipe: Dictionary = Recipes.RECIPES[_recipe_index]
		if Recipes.can_craft(player.inventory, recipe):
			s["craftable"] = true
			s["craft_text"] = Recipes.summary(recipe)

	# Cursor-driven cues (mutually exclusive by cell state). Only on foot.
	var cursor := get_global_mouse_position()
	if terrain != null:
		var tcell := terrain.world_to_cell(cursor)
		if terrain.is_solid(tcell) and _cell_in_reach(tcell):
			s["mineable"] = true
			s["mine_name"] = ItemDB.name_of(terrain.cell_type(tcell))
			return s
	var carc := _carcass_under(cursor)
	if not carc.is_empty() and _carcass_cell_in_reach(carc[0], carc[1]):
		var block_type: int = (carc[0] as Ship).blocks[carc[1]]["type"]
		s["harvestable"] = true
		s["harvest_name"] = ItemDB.name_of(ItemDB.whale_product_for(block_type))
		return s
	# Placement: an empty in-reach cell with a stocked, held material.
	if terrain != null:
		var pcell := terrain.world_to_cell(cursor)
		var mat := _held_placeable()
		if mat != TerrainDB.Type.AIR and player.inventory != null \
				and player.inventory.count(mat) > 0 \
				and _cell_in_reach(pcell) and not terrain.is_solid(pcell):
			s["placeable"] = true
			s["place_name"] = ItemDB.name_of(mat)
	return s


## The contextual cue lines the HUD bar draws — only the actions usable now, and
## nothing when none apply. The WHICH is HudCues.active (pure, tested); this maps
## each active cue to its text. HELM is left to the world-space floating prompt
## over the helm/door (interact_prompt), so it is not repeated in the bar.
func contextual_cue_lines() -> Array:
	var s := _cue_state()
	var lines: Array = []
	for cue in HudCues.active(s):
		match cue:
			HudCues.Cue.MINE:
				lines.append("[Z] mine %s" % s["mine_name"])
			HudCues.Cue.HARVEST:
				lines.append("[Z] harvest %s" % s["harvest_name"])
			HudCues.Cue.PLACE:
				lines.append("[V] place %s   ·   [B] cycle" % s["place_name"])
			HudCues.Cue.CRAFT:
				lines.append("[M] craft %s   ·   [N] cycle" % s["craft_text"])
			HudCues.Cue.TRAINER:
				lines.append("[K] trainer — train & sell salvage")
			# HELM is drawn by the floating prompt over the helm, not here.
	return lines


## Top-left status: ship stats ONLY while piloting (the wall of numbers is gone
## from foot play). On foot in single-player this is empty; connecting / no-ship
## messages are handled in _process.
func _update_hud(_cell: Vector2i) -> void:
	if player == null or not player.is_piloting() or not is_instance_valid(local_ship):
		var session := ""
		if Net.is_online():
			session = "%s  peers:%d  id:%d" % [
				"HOST" if multiplayer.is_server() else "CLIENT",
				Net.peer_count(), _my_id()]
		hud.text = session
		return

	hud.text = "\n".join([
		"AT THE HELM — WASD flies, F to step off",
		"Lift / weight: %.2f  (%s)" % [
			local_ship.lift_ratio(),
			"climbing" if local_ship.lift_ratio() > 1.0 else "sinking",
		],
		"Power:  %.0f / %.0f%s" % [
			local_ship.power_supply(),
			local_ship.active_draw(),
			"  (BROWNOUT)" if local_ship.active_draw() > local_ship.power_supply() else "",
		],
		"Altitude:  %.0f    Speed:  %.0f" % [
			-local_ship.global_position.y, local_ship.linear_velocity.length()],
		"Ceiling:  %.0f    Air:  %.2f" % [
			-local_ship.ceiling_estimate(),
			local_ship.air_density_at(local_ship.global_position.y)],
	])


func _draw() -> void:
	for rect in _terrain_rects:
		draw_rect(rect, Color(0.20, 0.24, 0.22))
		draw_rect(rect, Color(0.28, 0.34, 0.30), false, 2.0)

	# The [F] helm prompt lives on WorldOverlay (maps/world/overlay.gd):
	# this node's own drawing renders beneath its children, so text drawn
	# here would hide behind hulls (owner report).
