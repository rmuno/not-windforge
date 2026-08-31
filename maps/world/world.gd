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

## TIGHTENED 30% IN THE SHIPPED SCENE (owner 2026-08-30: "kindly increase default
## and max zoom by a flat 30% on both foot and while on ship"). One number does
## all four, which is why it is the number that moved: the helm view is
## `camera_zoom / pilot_zoom_out` and the wheel is a multiplier on top, so
## raising `camera_zoom` by 30% raises the on-foot default, the at-helm default,
## AND both ends of the wheel's range by exactly 30% together. maps/world/world.tscn
## 0.198 -> 0.2574; the legacy 1x scene keeps 0.9, because its distances are what
## the older suites' thresholds were written against.
##
## Higher zoom = MORE MAGNIFIED = less world on screen: on foot the view goes
## from ~9,700 px wide to ~7,500, and at the helm from ~16,750 to ~12,900. That
## also cuts what streams, since `terrain.primary_range_px` is half the visible
## extent at the live zoom.

## Scroll-wheel zoom: a user multiplier on top of the scene defaults,
## clamped to ±50% of them (owner's first guess at the range). Left alone by the
## 30% pass on purpose — it is a RATIO, so the ends moved with `camera_zoom`.
var _zoom_user := 1.0

const SHIP_START := Vector2(0, -200)

## You wake up inside the cabin, AT the controls (the helm is furniture —
## standing in its cell reads as manning the panel). Moved off the old
## midpoint between door and helm when doors gained a closed state: spawn
## must be unambiguously the helm's spot, so E right after waking boards
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
## Name of the key that actually opens the help panel HERE — "F1" on desktop,
## the browser-safe alias on the web build (maps/world/web_keys.gd). Resolved
## once: the corner status reprints every frame.
var _help_key_name: String = WebKeys.label_for(KEY_F1, WebKeys.is_web())
## Controls + block legend, hidden by default, shown on F1 (the old 13-line
## always-on legend and the giant control line, folded into ONE on-demand panel).
var _help_panel: PanelContainer
## The scroller inside the help panel + its label — kept so the panel can be
## height-capped to the viewport when opened (it must never run off screen).
var _help_scroll: ScrollContainer
var _help_label: Label
## Engineering overlay (F): 0 off, 1 FLIGHT (CoM · lift-to-weight · thrust
## vectors), 2 SYSTEMS (the power grid — engines feed, props/turrets draw,
## brownout). One quick toggle CYCLES it (owner 2026-08-27: "toggleable... two
## separate modes to focus on" instead of one flat all-at-once read). It draws
## your LOCAL ship only, in the WorldOverlay (above every hull). Off is the
## default; nothing is painted until you ask.
var _eng_overlay_mode := 0
const ENG_OVERLAY_MODES := 3   ## off, FLIGHT, SYSTEMS
const ENG_OVERLAY_NAMES := ["", "FLIGHT", "SYSTEMS"]
## The calm HUD layer (maps/world/hud_layer.gd): reticle + inventory swatches +
## the contextual cue bar, drawn in screen space, all fed from this node.
var _hud_layer: HudLayer
## The layered parallax background (maps/world/backdrop.gd), on its own
## CanvasLayer BEHIND the world. Fed by backdrop_status(); pure scenery.
var _backdrop: Backdrop

## THE DIVE (owner arc Q-G): the live roguelite run, or null in the ordinary
## expedition/sandbox game. Everything mode-scoped is gated on this being
## non-null, so the full game is untouched when nobody is diving. The MODEL is
## `modes/dive_run.gd` — this node only drives it and gives it bodies.
var dive: DiveRun = null
var _dive_hud: DiveHud
## How long the local ship has been gone. Losing it ends the run, but
## `local_ship` blinks null for a frame during a rebind, so the verdict waits.
var _dive_shipless := 0.0
## Seconds the committed hull has spent pressing DOWN into something solid, and
## the cooldown on saying so. See `_dive_nudge_if_stuck`.
var _dive_pressing := 0.0
var _dive_nudge_cd := 0.0
## Every hull a surge has spawned this run, so the run can clean up after itself
## (`_dive_cull_the_wake`). Instance ids, because the ships die by other means too.
var _dive_surged: Array[int] = []
var _dive_cull_clock := 0.0
## The Blueprint-Loft hull parked on the launch deck as the second candidate.
## A run prop: made once, reused across runs, cleared with the run unless you
## chose it.
var _dive_loft: Ship = null
## Depths whose shelf has already been cut this run. One landing per depth
## (owner 2026-08-30: "every level having some landmass … guardrailed and semi
## forced progress"), cut lazily one rung ahead of you.
var _dive_landings := {}
## This run's shelf size, sized against the hulls (see _dive_shelf_span).
var _dive_shelf := Vector2.ZERO
## The launch deck this run raised, and the blueprint it was raised from — the
## berths are read out of the cells, so the owner moves a ship by moving a gap.
## The Escape menu (maps/world/pause_menu.gd). Nothing pauses — it is chrome
## like every other panel — but Escape goes through it rather than through
## `get_tree().quit()`.
var _pause_menu: PauseMenu = null
var _dive_deck: Ship = null
var _dive_deck_cells := {}
var _dive_berth_taken := {}
## The quartermasters standing on this run's outpost landings (Trainer nodes in a
## different coat — same reach idiom, different trade). Cleared with the run.
var _dive_outposts: Array = []
const DIVE_SHIPLESS_GRACE := 1.5
## The share of your pool the deep air can never take you below inside a run.
## Low enough that being down there unprotected is genuinely dangerous, above
## zero so the AIR is never the killer.
const DIVE_AIR_FLOOR := 0.12
## Air between the shelf's underside and a moored candidate's hull, px at
## scale 1. A step off the rim, not a plummet.
## Air between the deck's walking surface and a moored hull's top, px at scale 1.
## The owner sized this one (2026-08-30): *"ships to be a block or two BELOW the
## platforms so they're easy to reach"*. A deck cell is 8 Ship.CELLs once
## upscaled, so a block is 8 × Ship.CELL at scale 1 = 128 px; the deck itself is
## three rows thick. 72 → 576 px at 8×, which is the deck's own underside plus
## about a block and a half: the hull's roof is a short hop below the hatch you
## drop through, and it is in frame from where you stand.
const DIVE_DROP_GAP := 72.0
## (Platform widths and berth clearances used to be computed here. They are
## authored in ships/dive_deck.ship now — DiveDeck.fits carries the clearance
## rule, and the deck's own gaps carry the widths.)
## Half-width of the corridor a run holds you in, in shelf widths. The Dive is a
## shaft, not a country (owner 2026-08-30) — wander past this and the air pushes
## you back toward the ladder.
const DIVE_CORRIDOR_WIDTHS := 4.0
## Clear air between two pickets of a surge, px at scale 1 - on TOP of both their
## hulls, which is the part a flat spacing left out.
const DIVE_PICKET_AIR := 700.0
## How hard taking a helm shoves the hull out of its berth, px/s DOWNWARD at
## scale 1. See `_dive_thaw`.
##
## CUT 260 -> 70 (owner 2026-08-30: "it'd just be nice if it wasn't so FORCED to
## descend so fast"). Measured, the old shove was not a nudge out of a berth, it
## was the first push of a plunge: **2,099 px/s at the moment you took the helm
## and 7,090 px/s one second later.** It only has to clear a deck three rows
## thick; anything past that is the mode grabbing the stick.
const DIVE_CAST_OFF := 70.0
## Thick air: a run holds a committed hull to `dive_descent_max` (F2, px/s at
## scale 1). The arithmetic — how hard the excess bleeds off, and what a NEUTRAL
## stick costs — lives in `DiveRun` (DESCENT_BLEED / DRIFT_FRACTION), so it is
## testable without pulling this file into a test's compile graph.
## How hard the corridor pushes back, px/s² at scale 1 per shelf-width of
## trespass. Firm enough to turn you, gentle enough that it reads as weather.
##
## CUT 260 -> 16 (owner 2026-08-30: "my propeller thrust seems way nerfed, even
## sideways"). It was not the props — it was this. At 260 the corridor pushed at
## 260 × 8 × 4 = **8,320 px/s² against a hull whose own props manage about
## 1,000**: forty times the pilot's authority. Measured, holding `ship_right`
## inside a run carried the ship **19,865 px to the LEFT** over five seconds.
## That is not weather leaning on you, it is a rail with the stick disconnected —
## the exact thing the corridor was chosen INSTEAD of (DECISIONS, "the Dive is a
## CORRIDOR, not a rail").
##
## 16 puts the ceiling at 512 px/s², about half what the props can do, so it
## turns you if you drift and loses if you insist. `DIVE_CORRIDOR_MAX_WIDTHS`
## caps the ramp so straying twice as far cannot make it unbeatable again.
const DIVE_CORRIDOR_PUSH := 16.0
## The trespass ramp is capped here, in shelf widths: past this the corridor does
## not push any harder. A push that scales without limit is a wall wearing
## weather's coat.
const DIVE_CORRIDOR_MAX_WIDTHS := 4.0

## THE INTRO (TitleScreen): while the title page is up the camera drifts across
## the whale pod instead of following the body. `_title_anchor` is INF until the
## first frame computes the pod's centroid, so it is decided once the world is
## actually populated rather than at _ready.
## THE INTRO IS ITS OWN SCENE (maps/intro/intro.tscn), so the world no longer
## carries a title panel, a title camera, or the `hud_quiet()` predicate that
## kept the two from contradicting each other. Every bug that predicate existed
## to fix — edge markers over the title, a helm offering itself to nobody, a
## health bar on the front page — is now impossible rather than suppressed,
## because the intro has no player and no HUD to leak.
##
## What the world does instead is READ the choice the intro made, once, at boot.
## Is the world about to open as a RUN? A peek, not a take — `_apply_boot_mode`
## remains the single consumer of the choice. This exists because the mode has to
## be known BEFORE the world populates itself, and `take()` happens after.
func _booting_the_dive() -> bool:
	return GameMode.pending == GameMode.DIVE


func _apply_boot_mode() -> void:
	match GameMode.take():
		GameMode.SANDBOX:
			debug_sandbox_loadout()
		GameMode.DIVE:
			begin_dive()
		_:
			pass   # expedition: the world is already the world
## The edge POI markers (maps/world/edge_markers.gd): a pointing triangle with an
## icon in it for every near thing that is currently off-screen. Fed by
## edge_marker_targets(); paints nothing when that is empty.
var _edge_markers: EdgeMarkers
## The deep-band ember haze (maps/world/deep_fog.gd): a screen-space wash that
## thickens as you descend. Under the HUD, over the world; driven by fog_density().
var _deep_fog: DeepFog

## Which balloon SIZE Q tethers while the build palette selects "balloon"
## (Ship.BalloonSize; B cycles the palette). Carcass-as-airship: aim at a
## hull/corpse cell and place.
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
## Hold-B build picker (maps/world/build_picker.gd) + the press clock that
## tells a HOLD from a TAP. A tap cycles on RELEASE now (not on press), so the
## same key can disambiguate — an imperceptible change for a tap, and the only
## way one key serves both.
var _build_picker: BuildPicker
var _b_press_msec := -1.0
const B_HOLD_SECONDS := 0.16
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
	_build_systems()
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

	# The layered background, BEHIND the world: its own CanvasLayer at -1 so
	# every real thing (terrain, ships, the lot) draws over it.
	var back_layer := CanvasLayer.new()
	back_layer.layer = -1
	_backdrop = Backdrop.new()
	_backdrop.world = self
	back_layer.add_child(_backdrop)
	add_child(back_layer)

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
		# One map-cell = 512×512 FINE tiles (owner 2026-08-24) — two coarse
		# chunks. Constant px at any terrain resolution.
		_discovery.cell_px = terrain.chunk_px() * terrain.subdiv * 2.0
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

	# Edge POI markers: a pointing triangle + an icon for each near thing that is
	# off-screen. Above the calm HUD (it is the same glass) and below the map,
	# which is a mode that covers everything.
	_edge_markers = EdgeMarkers.new()
	_edge_markers.world = self
	layer.add_child(_edge_markers)

	# THE DIVE's depth gauge and its run-over ledger. Above the edge markers (it
	# is the mode's own read-out and must not be pointed over) and below the map,
	# which is a mode that covers everything. Draws NOTHING outside a run.
	_dive_hud = DiveHud.new()
	_dive_hud.world = self
	layer.add_child(_dive_hud)

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

	# The Escape menu: resume, or back to the front door. Hidden until Escape.
	_pause_menu = PauseMenu.new()
	_pause_menu.world = self
	layer.add_child(_pause_menu)

	# The saves panel (F9): the list of saves with their metadata, hidden by
	# default. Built once; only its visibility and text change.
	_save_panel = _build_save_panel()
	layer.add_child(_save_panel)

	# The build PICKER (hold B): the palette as a grid, hidden until held.
	_build_picker = BuildPicker.new()
	_build_picker.world = self
	layer.add_child(_build_picker)

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
		# THE DIVE IS A STREAMLINED MODE, NOT THE WORLD WITH A LADDER IN IT
		# (owner ruling 2026-08-30: "a dive is meant to be much quicker. the
		# other modes should remain as they are but this one would be a super
		# streamlined mode").
		#
		# A run used to open inside the FULLY POPULATED world — the whale pod,
		# the critters, the kraken pod, the target hulk, the trainer, and the
		# city-whale boss at its fixed lair: 11 ships and 79,532 blocks before
		# the run added a thing, across a x4-wide world the dive uses about a
		# tenth of. None of it is wanted. The mode brings its own threats (the
		# surge ladder, garrisoned at every rung) and wakes its own floor
		# resident at depth 8, and its shops are the outposts it plants on its
		# own landings. The world's population was never the Dive's content —
		# it was the substrate the mode was built on top of to get it playable
		# (v0.89.0, "expanding no scope"), and this is the bill for that.
		#
		# `_booting_the_dive` PEEKS at the pending choice; `_apply_boot_mode`
		# still TAKES it at the end of _ready, so there is exactly one consumer.
		# The other two modes are untouched, which is the owner's other half.
		if not _booting_the_dive():
			_spawn_enemy_hulk()
			_spawn_whale()
			_spawn_critters()
			_spawn_kraken()
			_spawn_boss()
			_spawn_trainer()

	# You are a person, not a ship. Spawn standing on the deck, as the original
	# does — see docs/ORIGINAL_PLAYTEST.md, "the opening sequence". Spawning
	# goes through Crew so the same body replicates when a session is live.
	if not Net.is_online() or Net.is_server():
		player = crew.spawn_player(_my_id(), _spawn_offset(), _player_scale_mult())

	# ...and open in whatever mode the intro scene picked. Last in _ready, so the
	# mode acts on a world that is fully built (the Dive re-parks hulls and cuts
	# terrain, and neither works against a half-made scene).
	if not Net.is_online() or Net.is_server():
		_apply_boot_mode()


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
	# The web build cannot use the F-row (the browser takes it — F5 reloads the
	# page), so it answers to letters instead; print whichever set actually works
	# on this platform rather than lying to the browser player.
	var web := WebKeys.is_web()
	var k_help := WebKeys.label_for(KEY_F1, web)
	var k_save := WebKeys.label_for(KEY_F5, web)
	var k_saves := WebKeys.label_for(KEY_F9, web)
	var k_diag := WebKeys.label_for(KEY_F3, web)
	label.text = "\n".join([
		"CONTROLS   (%s to close)" % k_help,
		"A/D walk    Space jump    E use — helm, door, step off",
		"LMB shoot    RMB grapple (W/S reel, jump to sling; hold a whale to TAME it, release to let go)",
		"RIDING: the HOOK is the reins — no helm, no panel. Hold a tamed beast",
		"  with RMB and WASD steers it; let go of the hook and you step off.",
		"Q place    B pick what to place (TAP cycles · HOLD for the grid · Shift+B back)    C remove",
		"Z mine / harvest (hold)    X repair AND smother fire (hold, sweep)",
		"M craft    N next recipe    Shift+M craft all — the deep's air needs an Aether Lung",
		"K character sheet (at a trainer: 1-4 train, 0 sell salvage)    Tab map",
		"EDGE MARKERS: a triangle at the screen edge points at each near thing that is",
		"  off-screen — whale, squid, flame (basilisk), fish (critter), ! (enemy),",
		"  blimp (your ship, green), anchor (the dock master), diamond (a place), crown (the boss).",
		"F engineering overlay — cycles FLIGHT (mass · lift · thrust) / SYSTEMS (power)",
		"T respawn    R reset world    Esc quit    wheel zoom",
		"%s save    %s saves panel (Up/Down, Enter)    H host    J join" % [k_save, k_saves],
		"F2 debug window    %s diagnostic" % k_diag,
		"",
		"SHIP BLOCKS",
		"H helm (F pilots)    E engine (power)    P/V propeller    T turret",
		"R repair station — E runs it; heals the ship slowly + radially, on ship power",
		"D door (F opens/closes; closed stops bullets AND bodies)    | strut",
		"thin plank = platform — S+jump drops through",
		"pale = gasbag (lift)    pink = blubber    dark = ballast",
		"pink/red beast = sky whale — neutral; shoot it and it RAMS",
		"",
		"THE SKY IS INHABITED",
		"places hold populations — nests, dens, roosts, eyries. Break the nest",
		"and nothing more comes from there (and its cache spills). Tab shows",
		"every place you have found; a struck-through one is a place you broke.",
		"basilisk = the fire-spitter up high; it REARS before every spit",
		"FIRE spreads cell to cell through what burns (gasbag, blubber, hull).",
		"X smothers it; a row of removed blocks is a firebreak; it burns out.",
		"a running propeller pushes what is behind it and CHOPS what stands in",
		"the blades — and it can blow an incoming fireball off course.",
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


## F cycles the engineering overlay: off -> FLIGHT -> SYSTEMS -> off. A quick
## toggle, deliberately two FOCUSED modes rather than one flat everything-at-once
## read (owner 2026-08-27). The WorldOverlay reads engineering_overlay() and
## paints it; the label it draws is the only feedback needed.
func _cycle_eng_overlay() -> void:
	_eng_overlay_mode = (_eng_overlay_mode + 1) % ENG_OVERLAY_MODES


## What the engineering overlay should paint this frame, or null when it is off
## or there is no local ship to read. Plain values only (the overlay must never
## touch a Ship), on the pattern build_ghost/interact_prompt use. The ship's
## global transform rides along so the overlay can draw CoM, thrust and the
## machine markers in the SHIP's frame (a posed hull would slide a world-space
## marker off its own grid). SYSTEMS adds the power markers; FLIGHT omits them.
## Ships within this UNSCALED range of the player get their readout painted — so
## F reads your OWN ship plus any nearby vessel or creature you can see (owner
## 2026-08-27), not just the one you fly.
const ENG_OVERLAY_RANGE := 2200.0


func engineering_overlay() -> Variant:
	if _eng_overlay_mode == 0:
		return null
	var focus: Vector2
	if player != null and is_instance_valid(player):
		focus = player.global_position
	elif is_instance_valid(local_ship):
		focus = local_ship.to_global(local_ship.solid_bounds.get_center())
	else:
		return null
	var reach := ENG_OVERLAY_RANGE * maxf(float(world_scale), 1.0)
	var range2 := reach * reach
	var out := {"mode": _eng_overlay_mode, "name": ENG_OVERLAY_NAMES[_eng_overlay_mode],
		"scale": world_scale, "ships": []}
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.solid_bounds.size == Vector2.ZERO:
			continue
		var center := ship.to_global(ship.solid_bounds.get_center())
		if focus.distance_squared_to(center) > range2:
			continue
		var d := ship.engineering_readout()
		d["xform"] = ship.global_transform
		d["is_local"] = ship == local_ship
		if _eng_overlay_mode == 2:
			d["machines"] = ship.power_markers()
		(out["ships"] as Array).append(d)
	if (out["ships"] as Array).is_empty():
		return null
	return out


# --- Edge POI markers (maps/world/edge_markers.gd) --------------------------
#
# "Something is over there": a triangle at the screen edge, pointing at a thing
# that is a screen or two away, with an icon saying WHAT it is (owner
# 2026-08-29). The world DECIDES — which things are near enough, what kind each
# is, what colour it wears — and EdgeMarkers only paints, the same split
# HudLayer and WorldOverlay use.
#
# Why it is not the map: Tab answers "where is everything in the world", which
# is a slower question asked in a mode that costs you the controls. This answers
# "what is just off my screen right now", continuously, for free.

## Most markers on screen at once. Past a handful the edge becomes a fence and
## stops being information (the clean-UI standing order). Nearest win.
const EDGE_MARKER_MAX := 10

## Fallback marker range (px at world_scale 1) for a viewport too degenerate to
## measure — headless, or the first frame before the camera has a size.
const EDGE_MARKER_FALLBACK := 840.0


## How far a thing may be and still earn a marker, in world px. Derived from the
## LIVE camera rather than a constant, because the owner asked for "about a
## screen or two away" and a screen is a zoom-dependent quantity: pulling back at
## the helm should widen what you are told about, exactly as it widens what you
## can see. `edge_marker_screens` (F2) is that multiplier.
func edge_marker_range_px() -> float:
	var screens: float = Tunables.get_num("edge_marker_screens")
	var span := EDGE_MARKER_FALLBACK * maxf(float(world_scale), 1.0)
	if camera != null and is_instance_valid(camera):
		var vp := get_viewport()
		if vp != null:
			var vs := vp.get_visible_rect().size
			if vs.length() > 1.0:
				span = vs.length() / maxf(camera.zoom.x, 0.0001)
	return span * maxf(screens, 0.0)


## The body the player is ON — piloted, ridden, or the hull they are claiming.
## It is never a marker: an arrow pointing at the deck under your feet is the
## purest possible clutter.
func _edge_marker_carrier() -> Ship:
	if player == null or not is_instance_valid(player):
		return null
	if player.is_piloting():
		return player.piloting
	if player.is_riding():
		return player.riding
	return null


## What kind of marker a body earns, or "" for a body that earns none.
## Creature FIRST, so a tamed whale is still read as a whale (it just wears the
## ally teal) rather than getting filed as one of your vessels.
func _edge_marker_kind(ship: Ship) -> String:
	if ship.is_nest:
		return ""        # its SITE already marks the place; two marks, one thing
	if ship.is_carcass():
		return ""        # a kill is a place you have already been (a seam, below)
	match ship.creature_kind:
		"whale_city":
			return "boss"
		"whale":
			return "whale"
		"kraken":
			return "kraken"
		"basilisk":
			return "basilisk"
		"critter":
			return "critter"
	if ship.faction == 1:
		return "enemy"
	if ship.faction == 2:
		return "critter"  # untagged wildlife — a body, not a threat
	return "ship"         # a hull on your side


## The marker's colour, in the SAME friend/foe language the map blips and the
## body casts speak (MapView.blip_color / Ship.attitude_cast). A tamed creature
## takes the ally teal it already wears everywhere else.
static func edge_marker_color(ship: Ship, kind: String) -> Color:
	if ship != null and ship.is_tamed_ally():
		return Ship.CAST_ALLY
	match kind:
		"ship":
			return Color(0.40, 0.95, 0.55)   # YOUR ship — green, as the Source had it
		"enemy":
			return Color(0.95, 0.40, 0.35)
		"boss":
			return Color(0.98, 0.80, 0.35)
		"basilisk":
			return Color(0.95, 0.62, 0.30)
		"kraken":
			return Color(0.70, 0.50, 0.85)
		"whale":
			return Color(0.60, 0.78, 0.95)
		"critter":
			return Color(0.60, 0.85, 0.55)
	return Color(0.85, 0.88, 0.95)


## Everything worth an edge marker right now, nearest first, capped. Each entry:
## {pos (world px), kind (one of EdgeMarkers.KINDS), color, dist, near}.
## `near` is 1 right beside you and 0 at the range limit — the layer fades on it,
## so distance is read without a number on the glass.
func edge_marker_targets() -> Array:
	var out: Array = []
	if Tunables.get_num("edge_markers_enabled") == 0.0:
		return out
	var focus: Vector2
	if player != null and is_instance_valid(player):
		focus = player.global_position
	elif is_instance_valid(local_ship):
		focus = local_ship.global_position
	else:
		return out

	var reach := edge_marker_range_px()
	if reach <= 0.0:
		return out
	var range2 := reach * reach
	var carrier := _edge_marker_carrier()

	if fleet != null:
		for ship in fleet.ships():
			if not is_instance_valid(ship) or ship == carrier:
				continue
			if ship.solid_bounds.size == Vector2.ZERO:
				continue
			var at := ship.to_global(ship.solid_bounds.get_center())
			var d2 := focus.distance_squared_to(at)
			if d2 > range2:
				continue
			var kind := _edge_marker_kind(ship)
			if kind == "":
				continue
			out.append({"pos": at, "kind": kind, "dist": sqrt(d2),
				"color": edge_marker_color(ship, kind)})

	# The DOCK MASTER. The source pointed an anchor at the port NPC; the nearest
	# thing this world has to a port is the trainer station, so that is what the
	# anchor points at until towns exist (Phase 6) and it can point at a real one.
	if _trainer != null and is_instance_valid(_trainer):
		var td2 := focus.distance_squared_to(_trainer.global_position)
		if td2 <= range2:
			out.append({"pos": _trainer.global_position, "kind": "dock",
				"dist": sqrt(td2), "color": Color(0.95, 0.86, 0.45)})

	# PLACES you have found. A place you BROKE gets no arrow — the map keeps that
	# record; the edge is for things that still want your attention.
	for site in discovered_sites():
		if bool(site.get("cleared", false)):
			continue
		var sp := site["pos"] as Vector2
		var sd2 := focus.distance_squared_to(sp)
		if sd2 > range2:
			continue
		out.append({"pos": sp, "kind": "site", "dist": sqrt(sd2),
			"color": SpawnSites.kind_color(site["kind"])})

	# THE NEXT LANDING DOWN. In a run this is the one thing you must be able to
	# find, so it ignores the range gate the rest of the markers obey and keeps a
	# floor under its fade — a landing you cannot see is a lift shaft with extra
	# steps. Reuses the "site" icon: it IS a place.
	if dive != null and dive.outcome == "" and dive.depth < DiveRun.DEPTHS:
		var lp := dive_landing_pos(dive.depth + 1)
		out.append({"pos": lp, "kind": "site", "dist": focus.distance_to(lp),
			"color": Color(0.62, 0.86, 0.78), "near_min": 0.55})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dist"]) < float(b["dist"]))
	if out.size() > EDGE_MARKER_MAX:
		out.resize(EDGE_MARKER_MAX)
	for m in out:
		var md := m as Dictionary
		md["near"] = maxf(clampf(1.0 - float(md["dist"]) / reach, 0.0, 1.0),
			float(md.get("near_min", 0.0)))
	return out


## What the Backdrop needs this frame, or null before the world is framed:
## the camera position (the parallax input), the CAMERA's altitude fraction
## (the palette input — the backdrop should read as where the VIEW is, which is
## the player's altitude in practice), the world seed (the motif input) and the
## map-grid cell size (the owner's "changes based on CELL in the map's grid"),
## and the LIVE zoom — the backdrop rides a fraction of the world's APPARENT
## motion, so pulling back at the helm must not drag the scenery forward
## (Backdrop.layer_step; the 2026-08-29 calm-down).
func backdrop_status() -> Variant:
	if _world_rect.size.y <= 0.0 or camera == null or not is_instance_valid(camera):
		return null
	var alt := clampf((_world_rect.end.y - camera.global_position.y)
		/ _world_rect.size.y, 0.0, 1.0)
	var map_px := 512.0 * maxf(float(world_scale), 1.0)
	if _discovery != null:
		map_px = _discovery.cell_px
	return {"cam": camera.global_position, "alt": alt, "seed": world_seed,
		"map_cell_px": map_px, "zoom": camera.zoom.x}


# --- THE DIVE (modes/dive_run.gd) — the roguelite mode ---------------------
#
# The world's half of the mode: it gives the run BODIES (where the ship starts,
# what a surge spawns, when the ship is gone) and reads its altitude. Every
# decision about the run itself lives in the DiveRun model, which has no nodes
# in it and is therefore drivable by a headless test for a whole ten minutes.
#
# Everything here is gated on `dive != null`. The expedition and sandbox games
# never touch a line of it.


## Start a run. Places the local ship (and the body aboard it) at depth 1's
## altitude over the middle of the world and hands the model a clean slate.
## Single-player / authority, like every other world verb.
func begin_dive() -> void:
	if Net.is_online() and not Net.is_server():
		return
	dive = DiveRun.new()
	_dive_shipless = 0.0
	_dive_landings.clear()
	_dive_shelf = Vector2.ZERO
	_dive_deck_cells = {}
	_dive_berth_taken = {}
	_build_launch_deck()
	_notify("THE LAUNCH DECK. Take a ship, or step off the edge with nothing. "
		+ "Down is richer and worse; climb back to this air to bank what you carry.")


## Abandon the run without a verdict (a reset, a load, a mode exit). The ledger
## is NOT shown — this is not an outcome, it is the run ceasing to exist.
func end_dive() -> void:
	_dive_strip_run_gear()
	dive = null
	_dive_shipless = 0.0
	_dive_pressing = 0.0
	_dive_nudge_cd = 0.0
	_dive_surged.clear()
	_dive_cull_clock = 0.0
	if is_instance_valid(_dive_deck):
		_dive_deck.queue_free()
	_dive_deck = null
	_dive_deck_cells = {}
	_dive_berth_taken = {}
	for post in _dive_outposts:
		if is_instance_valid(post):
			post.queue_free()
	_dive_outposts.clear()
	_dive_landings.clear()
	_dive_shelf = Vector2.ZERO
	# The unchosen candidate goes with the run — unless you took it, in which
	# case it is your ship now and stays.
	if is_instance_valid(_dive_loft) and _dive_loft != local_ship \
			and _dive_loft.pilot_peer == 0:
		_dive_loft.queue_free()
	_dive_loft = null


## Take back exactly what the run handed you. The outpost's stock is TEMPORARY
## (the owner's word), and if it were not, the Aether Lung would be bought once
## and the depth gate would stand open for every run after — which would quietly
## delete the reason the shops exist. Counted, so gear you owned before the run
## is never touched.
func _dive_strip_run_gear() -> void:
	if dive == null or player == null or not is_instance_valid(player) \
			or player.inventory == null:
		return
	for id in dive.granted:
		player.inventory.remove(int(id), int(dive.granted[id]))


## BACK TO THE FRONT DOOR. Abandons a run without a verdict (it was not
## finished, so there is no ledger to write) and loads the intro scene, which is
## where a next run starts from. Headless and online are left alone: the suites
## boot worlds directly and a session has no title to return to.
func quit_to_title() -> void:
	end_dive()
	if DisplayServer.get_name() == "headless" or Net.is_online():
		return
	get_tree().change_scene_to_file("res://maps/intro/intro.tscn")


## Dismiss the run-over ledger and return to an ordinary world. The run's coins
## were already banked (or burned) when the outcome landed, so this only clears
## the plate.
func dismiss_dive_ledger() -> void:
	if dive == null or dive.outcome == "":
		return
	end_dive()
	# BACK TO THE FRONT DOOR (owner 2026-08-30: "dying during dive mode seems to
	# change modes?? oh em gee"). It did — the ledger dropped you into an
	# ordinary world, shipless, a hundred thousand pixels up, with no sign that
	# the run had ended. A run ends at the intro scene, which is the loop every
	# roguelite has and the only place a next run can start from.
	if DisplayServer.get_name() != "headless" and not Net.is_online():
		get_tree().change_scene_to_file("res://maps/intro/intro.tscn")


## The world y of an altitude fraction (0 = lava floor, 1 = ceiling) — the
## ladder's only contact with real coordinates.
func dive_altitude_y(frac: float) -> float:
	if _world_rect.size.y <= 0.0:
		return SHIP_START.y
	return _world_rect.end.y - frac * _world_rect.size.y


## THE LAUNCH DECK (owner 2026-08-30: "what if you just start on a small island
## and that's where you can choose which ship to fall onto & pilot, or even to
## just fall without a ship?").
##
## A run does NOT hand you a hull. It cuts a small stone shelf at the top of the
## ladder, stands you on it, parks the sky's candidates either side, and lets
## the first decision of the run be which one you take — or whether you take
## one at all. Stepping off the edge with nothing is a legal run: the ship-loss
## ending simply cannot fire, and your body becomes the thing you can lose
## (`DiveRun.committed`).
##
## It also makes depth 1 a PLACE rather than an altitude, which is the shape the
## rest of the ladder is heading for (one landing per depth — BACKLOG).
## The shelf, at scale 1 (× world_scale in use). Depth 1 is the authored deck
## now, so this only sizes the LADDER'S LANDINGS — but it also sets the unit the
## slalom and the corridor are measured in (`DiveRun.LADDER_SPREAD`,
## `DIVE_CORRIDOR_WIDTHS`), so it is not a free number. Deliberately SMALL, and
## it has been wrong in both directions already:
##
##   * The first cut was 9000 wide. The headless playtest caught what that meant:
##     a boarded ship holding DOWN pressed into 5600 px of its own launch pad and
##     went nowhere for twelve simulated minutes.
##   * The second was 2500 wide with the hulls parked most of a hull-length out
##     into clear air — safe to fly off, and (owner 2026-08-30) "the starting
##     spot in dive mode has no accessible ships": you could see them and not
##     reach them without a grapple.
##
## So the shelf is now barely wider than the body that stands on it, and the
## hulls are moored with their inner edge exactly AT its rim (`_dive_park_x`):
## a few seconds' walk to the edge, one step onto a deck, and every hull still
## floats over open air so pushing the stick down drops you into sky.
const LAUNCH_SHELF_PX := Vector2(1400.0, 200.0)


## How many of the widest hull a LANDING is across. Two, and the number is load-
## bearing in a way "make it look right" is not — it is what makes a straight
## dive legal.
##
## The ladder's sidestep is measured in SHELF WIDTHS
## (`DiveRun.LANDING_STEP_MIN`, 1.5), but the thing that has to fit through the
## gap is a SHIP, whose width does not shrink when the shelf does. Cut the
## landings at 0.9 hulls — which is what shipped — and the geometry inverts: a
## rung is NARROWER than the ship diving past it, the minimum sidestep is only
## 1.24 hulls, and the ship clips the next slab and stops. That is the second
## half of the owner's *"stuck at depth 4 (no more falling)"*, and the headless
## probe caught it stalled on rung 2 with 379 px of hull resting on the slab's
## corner. At two hulls per landing every clearance is comfortable at both world
## scales, and a landing is also, finally, a place you can actually set a ship
## down on — which is what a landing is for.
const LANDING_HULL_WIDTHS := 2.0


## The shelf's real size this run — the size of every LANDING on the ladder, and
## the unit the slalom and the corridor are measured in. Sized against the widest
## hull in the sky (see LANDING_HULL_WIDTHS), capped by the constant above so a
## fleet of monsters cannot turn the shaft into a country.
##
## Cached per run so every landing is cut the same size — and the cache is
## DELIBERATELY CLEARED once the candidates are moored (`_build_launch_deck`),
## because the first call happens while the deck is still being raised and the
## Blueprint Loft hull does not exist yet. Measured before it lands, the "widest
## hull" is the starter alone and every landing on the ladder comes out sized for
## a ship that is not the biggest one you can be flying.
func _dive_shelf_span() -> Vector2:
	if _dive_shelf != Vector2.ZERO:
		return _dive_shelf
	var span := LAUNCH_SHELF_PX * float(world_scale)
	var widest := _dive_widest_hull()
	if widest > 0.0:
		span.x = minf(span.x, widest * LANDING_HULL_WIDTHS)
	_dive_shelf = span
	return _dive_shelf


## The widest player-side hull, IN WORLD PIXELS.
##
## `Ship.solid_bounds` is ALREADY world pixels and must never be multiplied by
## `world_scale`. The 8× world is built by UPSCALING THE CELL GRID
## (`ShipLayout.upscale_cells`), not by scaling the node — a `Ship` never sets
## `scale` — so an authored 96-column hull becomes 768 columns of `Ship.CELL`
## and its bounds come out at 12,288 px on their own.
##
## Scaling them again is an EIGHTFOLD error, and it is the one that kept the
## launch deck unreachable through four rewrites: the berths were computed
## 98,000 px wide instead of 16,000, which put the nearest hull most of a
## hundred thousand pixels to one side and twenty-five thousand below. Every
## other reader in this file already treats the bounds as world px
## (`_creature_bite_radius`, the lava check, the edge markers); the Dive code
## was the odd one out. The owner spotted it from the outside: "are you scaling
## to x8 for dive too, and could that influence".
func _dive_widest_hull() -> float:
	var widest := 0.0
	for ship in fleet.ships():
		if is_instance_valid(ship) and ship.faction == 0 and not ship.is_nest \
				and ship.creature_kind == "" and not ship.is_carcass():
			widest = maxf(widest, ship.solid_bounds.size.x)
	return widest
func _build_launch_deck() -> void:
	var at := dive_landing_pos(1)
	var span := _dive_shelf_span()
	_cut_landing(1)   # raises the deck, which is where the berths come from

	# NOBODY'S SHIP. Un-claim whatever the boot handed you and park it as one
	# of the candidates: `_refresh_local_ship` then leaves `local_ship` null until
	# you actually take a helm, which is what makes "or no ship at all" real.
	var parked: Array = []
	for ship in fleet.ships():
		if is_instance_valid(ship) and ship.pilot_peer == _my_id() and not ship.is_nest:
			ship.pilot_peer = 0
			parked.append(ship)
	local_ship = null
	# Candidates float in CLEAR AIR either side of the shelf, never over it: the
	# whole point of the deck is that taking a helm and pushing the stick down
	# drops you into open sky, not onto your own rock.
	var i := 0
	for ship in parked:
		_park_candidate(ship as Ship, _dive_park_at(ship as Ship, at, i))
		i += 1
	# ...and the owner's own Blueprint Loft ship as the second candidate, so
	# whatever they design in the Loft is a hull they can dive with. Made ONCE
	# and reused: a run prop that respawned per dive would litter the sky.
	if is_instance_valid(_dive_loft):
		_park_candidate(_dive_loft, _dive_park_at(_dive_loft, at, 1))
	else:
		_dive_loft = _spawn_loft_at(at + Vector2(span.x, span.y))
		if _dive_loft != null:
			_park_candidate(_dive_loft, _dive_park_at(_dive_loft, at, 1))

	# EVERY CANDIDATE IS IN THE SKY NOW, so re-measure the landing size before a
	# single rung of the ladder is cut. The first measurement happened above,
	# while the deck was still being raised and the Loft hull did not exist — and
	# a ladder sized for the starter alone is a ladder the Loft cannot fly down.
	_dive_shelf = Vector2.ZERO
	_cut_landing(2)   # one rung of lookahead, so you can SEE where you are going

	# Stand the body just above the deck, not high over it: the run opens with
	# a look around, not a fall. On the MIDDLE WALKWAY, with a hatch a short
	# stroll to either side (the blueprint's `origin` is what puts cell (0,0)
	# there — move it and the run stands you somewhere else).
	if player != null and is_instance_valid(player):
		player.velocity = Vector2.ZERO
		# Standing ON the platform, not dropped onto it from a storey up: the
		# body is 144 px tall at 8x, so 160 px of clearance is plenty.
		player.global_position = Vector2(at.x,
			at.y - 20.0 * float(world_scale))


## Where a candidate moors. FOURTH layout, and the first three are kept written
## down because each was "obviously fine" until somebody walked it:
##
##   1. Parked a hull-length out in clear air — visible, unreachable.
##   2. Moored abeam with its inner edge on the rim — a six-thousand-pixel wall
##      of hull in front of a hundred-and-forty-pixel person, and unfrozen, so
##      the starter climbed away at lift 1.07 while you walked toward it.
##   3. Hung below the rim, frozen — reachable at last, but BELOW THE SCREEN
##      ("you have to jump down and hope to land near one"), and worse: taking
##      one thawed a hull with lift under solid rock, which drove it up into the
##      launch platform and broke it ("I got propelled upward and immediately
##      broke the ship against the starting platform").
##
##   4. A row of narrow platforms with wide GAPS, a candidate hanging in each
##      gap. Reachable and visible at last — but the owner had drawn something
##      else, and walking it made the difference plain: a deck of holes is a
##      deck you jump across, and missing a jump is a run over.
##
## FIFTH, and it is the owner's own drawing (2026-08-30): *"`.` is a block and
## `-` a platform, which would allow for ships to be a block or two BELOW the
## platforms so they're easy to reach and you can just keep walking to the ship
## you want/have unlocked... and also the platforms can be as wide as whatever
## ship is right under it plus a small buffer of 2 blocks."* The deck is now ONE
## CONTINUOUS FLOOR — solid hull you can walk end to end — with a DROP-THROUGH
## PLATFORM over each moored ship. You stroll the deck, stand over the hull you
## want, and S+jump through. Nothing to jump across and nothing to miss.
##
## The roof this puts back over a candidate is the thing that broke a hull in
## v0.95.x, and it is harmless here for a reason worth writing down: a platform
## strip is an `AnimatableBody2D` on collision layer 3 with a one-way shape
## (`Ship._rebuild_platforms`), and a `Ship` is a `RigidBody2D` masking layer 1
## only — so a rising hull passes straight through its own hatch and never
## touches it. What it CAN hit is the walkway either side, which is ordinary
## solid hull, and that is what `DiveDeck.BERTH_BUFFER_CELLS` is for.
##
## Walk off either END of the deck and there is nothing under you, which is the
## shipless run.
func _dive_park_at(ship: Ship, at: Vector2, index: int) -> Vector2:
	# solid_bounds is ALREADY world px — see _dive_widest_hull. `roof` is the
	# offset from the ship's ORIGIN to the top of its hull, which is not
	# −half-height: a blueprint's `origin` puts cell (0,0) wherever the author
	# wanted it. Using half the height put the starter's deck 520 px under the
	# hatch and the Loft's 632 px under it — the same drop was two different
	# drops depending on which hull you chose.
	var roof := -2000.0 * float(world_scale)
	var wide := 0.0
	if ship != null and is_instance_valid(ship) and ship.solid_bounds.size.y > 0.0:
		roof = ship.solid_bounds.position.y
		wide = ship.solid_bounds.size.x
	# The berth the blueprint gave us — the WIDEST one this hull fits, so the
	# starter takes the big bay and a small hull takes the small one whichever
	# order they happen to be parked in.
	var berths := dive_berth_positions()
	var best := -1
	for i in berths.size():
		if _dive_berth_taken.has(i):
			continue
		var bw := float((berths[i] as Dictionary)["width"])
		if not DiveDeck.fits(wide, bw, Ship.CELL * float(world_scale)):
			continue
		if best < 0 or bw < float((berths[best] as Dictionary)["width"]):
			best = i   # the SNUGGEST berth that fits, so nothing hogs the big bay
	if best < 0:
		# Nothing fits (a hand-edited deck, or a hull bigger than every gap):
		# moor it off the end rather than dropping it through the floor, and say
		# so, because a silently missing candidate is the bug we keep fixing.
		push_warning("dive: no berth fits a %.0f px hull — check ships/dive_deck.ship"
			% wide)
		return Vector2(at.x + float(index + 1) * maxf(wide, 3000.0) * 1.2,
			at.y + DIVE_DROP_GAP * float(world_scale) - roof)
	_dive_berth_taken[best] = true
	# Centre the HULL in the hatch, not the ship's ORIGIN: a blueprint's `origin`
	# puts cell (0,0) where the author wanted it, so `solid_bounds` is rarely
	# centred on it. Subtracting the bounds' own centre is what makes the gap the
	# same on both sides — the other half of the owner's "off by 1 or 2 tiles".
	var mid := 0.0
	if ship != null and is_instance_valid(ship) and ship.solid_bounds.size.x > 0.0:
		mid = ship.solid_bounds.position.x + ship.solid_bounds.size.x * 0.5
	return Vector2(float((berths[best] as Dictionary)["pos"].x) - mid,
		at.y + DIVE_DROP_GAP * float(world_scale) - roof)


## How wide one berth is: the widest candidate plus air, so nothing is moored
## under an overhang.
## Where depth `d`'s landing is in the world. The ladder decides the altitude and
## this run's seed decides the drift, so the descent is a slalom you fly rather
## than a shaft you drop down (`DiveRun.landing_offset`).
func dive_landing_pos(d: int) -> Vector2:
	var cx: float = _world_rect.get_center().x if _world_rect.size.x > 0.0 else 0.0
	var span := _dive_shelf_span()
	var sv: int = dive.seed_v if dive != null else 0
	return Vector2(cx + DiveRun.landing_offset(sv, d) * span.x,
		dive_altitude_y(DiveRun.depth_altitude(d)))


## Cut depth `d`'s shelf, once per run. Generate the neighbourhood FIRST and
## stamp second: a region that has already been generated is never repainted, so
## this is what stops lazy island generation eating the shelf half a minute after
## you land on it (DECISIONS 2026-08-30).
func _cut_landing(d: int) -> void:
	if dive == null or terrain == null or _dive_landings.has(d):
		return
	if d < 1 or d > DiveRun.DEPTHS:
		return
	_dive_landings[d] = true
	var at := dive_landing_pos(d)
	var span := _dive_shelf_span()
	IslandGen.ensure_generated(terrain, world_seed, [at],
		maxf(span.x, _dive_deck_reach()), 64)
	if d == 1:
		_raise_launch_deck(at)
	else:
		_stone(at + Vector2(-span.x * 0.5, 0.0), span)
	terrain.flush_rebuilds()
	if DiveRun.is_outpost(dive.seed_v, d):
		_plant_outpost(at)


## Stamp one slab of stone: `at` is its top-left corner, `size` its extent in
## world px.
func _stone(at: Vector2, size: Vector2) -> void:
	var cp := maxf(terrain.cell_px(), 1.0)
	terrain.fill_rect(Rect2i(terrain.world_to_cell(at),
		Vector2i(maxi(1, int(size.x / cp)), maxi(1, int(size.y / cp)))),
		TerrainDB.Type.STONE)


## THE LAUNCH DECK IS AN AUTHORED BLUEPRINT (owner 2026-08-30: "you can just plan
## it out with ascii characters like we've done with the ship builder").
##
## `ships/dive_deck.ship` is the ground a run starts on, and the berths are read
## straight out of it (`DiveDeck.berth_offsets`) — move a gap in that file and
## the moored ship moves with it. It spawns FROZEN and marked as a structure, the
## same way a nest hangs where it was built, so it is scenery with a floor rather
## than a vessel anybody could fly.
##
## Authoring beat computing here for a reason worth remembering: this geometry
## was wrong four times running, and every version of it was arithmetic I could
## not see. A file the owner can look at is a file the owner can correct.
const DIVE_DECK_PATH := "res://ships/dive_deck.ship"
func _raise_launch_deck(at: Vector2) -> void:
	var cells := ShipLayout.load_cells(DIVE_DECK_PATH)
	if cells.is_empty():
		push_warning("dive: no launch deck blueprint at %s" % DIVE_DECK_PATH)
		return
	_dive_deck_cells = cells
	_dive_deck = fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(cells, world_scale), at, 0, 0.0,
		float(world_scale), 0, {"is_nest": true})


## Where each berth's middle sits in the world, left to right, read from the
## deck the run actually raised.
func dive_berth_positions() -> Array:
	var out: Array = []
	if not is_instance_valid(_dive_deck) or _dive_deck_cells.is_empty():
		return out
	for b in DiveDeck.berth_offsets(_dive_deck_cells, Ship.CELL * float(world_scale)):
		var d := b as Dictionary
		out.append({"pos": _dive_deck.to_global(Vector2(float(d["x"]), 0.0)),
			"width": float(d["width"])})
	return out


## How far the deck reaches from the centre line, for terrain generation. Read
## from the BLUEPRINT, because that is the thing that decides it: the deck is
## 80 characters of 128 px and the landing shelves are a tenth of that, so
## sizing this off the shelf left the deck's ends outside the region the run
## generates before it stamps (`_cut_landing`) — and an ungenerated region is
## one lazy island generation away from being repainted under your feet.
func _dive_deck_reach() -> float:
	var cells := _dive_deck_cells
	if cells.is_empty():
		cells = ShipLayout.load_cells(DIVE_DECK_PATH)
	if cells.is_empty():
		return _dive_shelf_span().x * 2.0
	var lo := 1 << 30
	var hi := -(1 << 30)
	for c in DiveDeck.occupied_columns(cells):
		lo = mini(lo, int(c))
		hi = maxi(hi, int(c))
	return maxf(absf(float(lo)), absf(float(hi)) + 1.0) * Ship.CELL * float(world_scale)


## Stand a quartermaster on a landing. Three of the eight rungs have one
## (`DiveRun.outpost_depths`); they are the run's only safe errand, and the only
## place the pot can be spent instead of banked.
func _plant_outpost(at: Vector2) -> void:
	var post := Trainer.new()
	post.name = "DiveOutpost"
	post.reach = Ship.CELL * 4.0 * world_scale
	post.coat = Color(0.62, 0.50, 0.34)   # a quartermaster, not a trainer
	post.position = at - Vector2(0.0, Ship.CELL * 1.2 * world_scale)
	add_child(post)
	_dive_outposts.append(post)


## The quartermaster you are standing at, or null. Same "are you close enough"
## idiom as helms, doors and trainers.
func near_outpost() -> Node2D:
	if dive == null or player == null or not is_instance_valid(player):
		return null
	for post in _dive_outposts:
		if is_instance_valid(post) and post.in_reach(player.global_position):
			return post
	return null


## The outpost's stock as plain rows for the sheet: label, cost, and whether the
## pot covers it. Empty when you are not standing at one.
func dive_stock() -> Array:
	var out: Array = []
	if dive == null or dive.outcome != "" or near_outpost() == null:
		return out
	var key := 1
	for row in DiveRun.STOCK:
		var r := row as Dictionary
		out.append({"key": key, "label": r["label"], "cost": int(r["cost"]),
			"afford": dive.pot >= int(r["cost"])})
		key += 1
	return out


## Buy stock row `index` (0-based) with the POT. Returns whether it happened.
## Refused off an outpost, on a finished run, or when the pot is short.
func try_buy_stock(index: int) -> bool:
	if dive == null or dive.outcome != "" or near_outpost() == null:
		return false
	if index < 0 or index >= DiveRun.STOCK.size():
		return false
	if player == null or not is_instance_valid(player):
		return false
	var row: Dictionary = DiveRun.STOCK[index]
	var cost := int(row["cost"])
	if not dive.spend(cost):
		_notify("Not enough on you — %d coins short." % (cost - dive.pot))
		return false
	match String(row["id"]):
		"lung":
			player.inventory.add(ItemDB.Crafted.LIFE_SUPPORT, 1)
			dive.grant(ItemDB.Crafted.LIFE_SUPPORT)
		"balloon":
			player.inventory.add(ItemDB.Crafted.BALLOON_LARGE, 1)
			dive.grant(ItemDB.Crafted.BALLOON_LARGE)
		"patch":
			_dive_patch_hull()   # spent the moment it is bought; nothing to take back
	if _pickups != null:
		_pickups.add(player.global_position, "-%d coins" % cost, float(world_scale))
	return true


## The hull patch: one sweep of the repair wand's effect over the WHOLE ship,
## paid for instead of held. Restores toward the blueprint exactly like the wand
## and the repair station do — nothing new can be built, only mended.
const DIVE_PATCH_AMOUNT := 400.0
func _dive_patch_hull() -> void:
	if not is_instance_valid(local_ship):
		return
	for cell in local_ship.blueprint_map().keys():
		local_ship.repair_cell(cell as Vector2i, DIVE_PATCH_AMOUNT)
	local_ship.rebuild()


## Moor one candidate and HOLD it there. The freeze is the important half: a
## parked hull is still a RigidBody2D with lift, and the starter's lift ratio is
## 1.07 — so the candidates were quietly climbing away while the player walked
## toward them. Frozen, they hang like a nest does (`Ship.is_nest` uses the same
## `freeze`), and taking a helm thaws the one you chose.
func _park_candidate(ship: Ship, at: Vector2) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	ship.global_position = at
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0
	ship.freeze = true


## Thaw the hull you took. Anything still moored stays frozen — change your mind
## and the other candidate is exactly where you left it.
func _dive_thaw(ship: Ship) -> void:
	if ship == null or not is_instance_valid(ship) or ship.is_nest:
		return
	# SHE CASTS OFF DOWNWARD (owner 2026-08-30: "getting on the dive ship jumps
	# the ship UP through the platform, then you start falling like a rock").
	#
	# That was the shipped behaviour working as built and reading as a bug. A
	# thawed hull is buoyant — the starter's lift ratio is 1.07 — so releasing it
	# at rest under its hatch made it CLIMB, up through the platform it was
	# moored beneath and out over the deck, before the pilot got a say. Taking a
	# helm in a dive is casting off INTO the dive: the hull leaves its berth
	# going down, the deck is behind you in a second, and the first thing the
	# mode does is the thing the mode is about.
	#
	# `DIVE_CAST_OFF` is a shove, not a plummet — about half a free dive, and
	# lift bleeds it off in a few seconds, so a pilot who does nothing ends up
	# hovering below the deck rather than pinned to its underside.
	ship.angular_velocity = 0.0
	ship.linear_velocity = Vector2(0.0, DIVE_CAST_OFF * float(world_scale))
	ship.freeze = false


## The run ends because YOU did, not because a ship did. Only reachable on a
## shipless run (owner 2026-08-30: "or even to just fall without a ship?") —
## with a hull under you there is a deck to wake up on, so death is a respawn and
## the run goes on. With none, there is nowhere to put you back.
func _dive_perish() -> bool:
	if dive == null or dive.outcome != "" or dive.committed:
		return false
	dive.lose(true)
	_notify(DiveRun.outcome_line(dive.ledger()))
	return true


## SOME OF THEM CAN KEEP UP (owner 2026-08-30: "there should be many more
## menacing threats on the way down ... some of which ideally can keep up with
## you?").
##
## They could not, and the reason is arithmetic rather than AI: a committed hull
## sinks at about 3,900 px/s with the stick down and a free-falling BODY reaches
## 6,400, while a powered vessel tops out near 2,720 px/s at 8x. Every brain in
## the game was chasing something it is physically unable to catch, so the whole
## descent reads as unopposed no matter how much is spawned into it.
##
## The fix is not a faster ship - it is that THEY ARE DIVING TOO. A picket the
## surge put in your path gets gravity's help the same way you do: while you are
## below it, its downward speed is floored at a share of your own, so it falls
## after you instead of hanging in the sky you just left. Closing sideways stays
## the AI's job - this only stops the vertical race being over before it starts.
##
## Bounded on purpose. It applies ONLY to what a surge spawned (`_dive_surged` -
## the world's own inhabitants keep their own physics), only while you are BELOW
## it, only downward, and never past DIVE_PURSUIT_MATCH of your speed - so a
## pursuer closes slowly if you dive straight and loses you if you turn. Running
## is still an answer; it is just no longer a free one.
const DIVE_PURSUIT_MATCH := 0.92
## Beyond this many rung-heights a pursuer has lost you and stops diving.
const DIVE_PURSUIT_RUNGS := 0.8
func _dive_pursue(delta: float) -> void:
	# NOT gated on `committed`: the owner's case for this is the SHIPLESS jump
	# ("if you just jump off without a ship"), and a body falls faster than any
	# hull — 6,400 px/s against 3,900 — so that is the line most in need of
	# something able to follow it down.
	if dive == null or dive.outcome != "" or player == null:
		return
	if not is_instance_valid(player) or _dive_surged.is_empty():
		return
	# How fast the thing they are chasing is actually going down.
	var mine := player.velocity.y
	if is_instance_valid(local_ship) and player.is_piloting():
		mine = local_ship.linear_velocity.y
	if mine <= 0.0:
		return   # climbing or hovering: nothing to keep up WITH
	var want := mine * DIVE_PURSUIT_MATCH
	var reach := absf(dive_altitude_y(DiveRun.depth_altitude(2))
		- dive_altitude_y(DiveRun.depth_altitude(1))) * DIVE_PURSUIT_RUNGS
	var at := player.global_position
	for id in _dive_surged:
		var ship := instance_from_id(id) as Ship
		if ship == null or not is_instance_valid(ship) or ship.freeze:
			continue
		if at.y <= ship.global_position.y:
			continue   # you are level with it or above it - no chase downward
		if ship.global_position.distance_to(at) > reach:
			continue
		if ship.linear_velocity.y >= want:
			continue   # already falling at least as fast
		# Ease toward the matched speed rather than snapping to it, so a picket
		# accelerates into the dive the way a body would.
		ship.linear_velocity.y = minf(want,
			ship.linear_velocity.y + want * 2.0 * delta)


## THE RUN CLEANS UP AFTER ITSELF (owner 2026-08-30: *"FPS really drops once I'm
## toward the final level. Perhaps for the Dive mode we can just allocate
## downward and remove layers above, since they'd no longer matter?"*).
##
## The owner's instinct is right and the target is not the terrain — extraction
## is CLIMBING BACK UP, so the layers above are exactly the ones a successful run
## still needs (and the streamer already demotes what is far away). What actually
## accumulates is the WAKE: every surge spawns a picket, a surge lands every
## `dive_surge_period` seconds, and nothing has ever removed one. By the floor a
## run is dragging every gunboat it out-flew at depth 2 — awake or dormant, they
## are still bodies, still colliders, still drawn.
##
## So only what a SURGE spawned is culled, and only once it is a ladder-rung and
## a half away — far enough that it is not the fight you are in, in either
## direction, so a climb home still meets what it left near it. The world's own
## inhabitants and the floor's resident are never touched: this list holds the
## run's litter and nothing else.
const DIVE_CULL_RUNGS := 1.5
func _dive_cull_the_wake(delta: float) -> void:
	_dive_cull_clock += delta
	if _dive_cull_clock < 1.0 or dive == null or player == null 			or not is_instance_valid(player):
		return
	_dive_cull_clock = 0.0
	if _dive_surged.is_empty():
		return
	var far := absf(dive_altitude_y(DiveRun.depth_altitude(2))
		- dive_altitude_y(DiveRun.depth_altitude(1))) * DIVE_CULL_RUNGS
	var kept: Array[int] = []
	for id in _dive_surged:
		var ship := instance_from_id(id) as Ship
		if ship == null or not is_instance_valid(ship):
			continue   # already dead by other means; drop the id
		if ship.global_position.distance_to(player.global_position) < far:
			kept.append(id)
			continue
		ship.queue_free()
	_dive_surged = kept


## THE DEEP IS THICK (owner 2026-08-30: "it'd just be nice if it wasn't so FORCED
## to descend so fast, then, on the ship during dive mode i guess. or it falls too
## fast").
##
## They were right, and the numbers are worse than the complaint. Measured on the
## shipped hull inside a run, holding the stick down in clear air:
##
##     t=1s  4,220 px/s     t=3s  6,499     t=5s  6,704 (terminal)
##
## A screen is about 4,200 px tall at the shipped zoom, so the hull was crossing
## **more than one and a half screens every second** — nothing on it is legible,
## nothing can be dodged, and the ladder's rungs go past as a flicker. Worse, with
## the stick NEUTRAL it still sank at 2,389 px/s and rising: at altitude the air
## is thin, lift is weak, and a hull that is buoyant at the surface simply falls.
## That is the "FORCED" half of the report — you were not choosing to descend
## that fast, the sky was choosing for you.
##
## So a run holds a hull to `dive_descent_max`. It is EASED, not clamped: the
## excess over the cap bleeds off at `DiveRun.DESCENT_BLEED` per second, so pushing
## down still accelerates you and the limit arrives as thick air rather than as a
## wall. Only DOWNWARD and only inside a run — climbing is the extraction and the
## other two modes keep their own physics, which is the standing owner ruling.
func _dive_hold_the_descent(delta: float) -> void:
	if dive == null or dive.outcome != "" or not is_instance_valid(local_ship):
		return
	var cap := Tunables.get_num("dive_descent_max") * float(world_scale) 		* DiveRun.descent_depth_mult(dive.depth)
	if cap <= 0.0:
		return
	# Driving down is three times the drift. `thrust_input.y` is the helm axis:
	# negative is DOWN (Input.get_axis("ship_down", "ship_up")).
	cap = DiveRun.descent_cap(cap, local_ship.thrust_input.y)
	local_ship.linear_velocity.y = DiveRun.bleed_descent(
		local_ship.linear_velocity.y, cap, delta)


## SAY WHY THE SHIP WILL NOT GO DOWN. The ladder is a slalom of solid slabs, so
## holding the stick down from one column eventually rests you on a rung — which
## is the mode working, but it reads as *"stuck at depth 4 (no more falling)"*
## when nothing says so and the marker you should be flying at is off to one
## side. Gated on the DOWN input actually being held, so a ship parked at an
## outpost (which stands ON a landing) is never nagged for parking; throttled so
## the answer is a sentence, not a drumbeat.
##
## `Input` is untouched headless, which is why this cannot fire in the suites —
## the wording is pinned through `DiveRun.stuck_hint` instead.
const DIVE_STUCK_AFTER := 2.5    ## seconds of pressing into rock before the hint
const DIVE_STUCK_COOLDOWN := 12.0
func _dive_nudge_if_stuck(delta: float) -> void:
	_dive_nudge_cd = maxf(0.0, _dive_nudge_cd - delta)
	if dive == null or not dive.committed or dive.depth >= DiveRun.DEPTHS 			or not is_instance_valid(local_ship):
		_dive_pressing = 0.0
		return
	if not Input.is_action_pressed("ship_down") 			or absf(local_ship.linear_velocity.y) > 40.0 * float(world_scale):
		_dive_pressing = 0.0
		return
	_dive_pressing += delta
	if _dive_pressing < DIVE_STUCK_AFTER or _dive_nudge_cd > 0.0:
		return
	_dive_pressing = 0.0
	_dive_nudge_cd = DIVE_STUCK_COOLDOWN
	_notify(DiveRun.stuck_hint(
		dive_landing_pos(dive.depth + 1).x - local_ship.global_position.x))


## THE DIVE HAS NO INTERIORS (owner 2026-08-30: "just getting off the helm
## placed you outside (above?) the ship, and perhaps you can just get on by being
## outside (e.g. disable doors)"). Three things make that true, and this is the
## first: every door on your ship is thrown OPEN when the run starts. The other
## two are `_helm_reach` (board from outside) and `_dive_step_out` (step off onto
## the hull). The expedition game keeps its doors, its cabin and its walk.
## ...and it costs ONE rebuild, not one per door (owner 2026-08-30: "there's also
## a moderate lag when getting on the ship"). `Ship.toggle_door` rebuilds the
## whole hull - colliders, merged rects, skin regions - and this called it once
## per closed door in a single frame. On a small starter that is a blink; on the
## owner's large hand-built ship it is a dozen full rebuilds of a few thousand
## blocks, all inside the frame you press E. `Ship.open_all_doors` flips them all
## and rebuilds once.
func _dive_open_doors() -> void:
	if not is_instance_valid(local_ship):
		return
	if local_ship.is_authority():
		local_ship.open_all_doors()
		return
	for cell in local_ship.door_cells.duplicate():
		if local_ship.has_block(cell) \
				and local_ship.blocks[cell]["type"] == BlockDB.Type.DOOR_CLOSED:
			local_ship.net_toggle_door(cell)


## THE ASSISTANT (owner 2026-08-30: "I'm not exactly sure if the repairs like
## that even make sense — perhaps we'd need a starting assistant recruit who just
## automatically mans the repair spot"). A run starts with a repair station on
## your hull (bolted on if the blueprint has none) and ONE crew member standing
## at it, keeping it running. You never hire, manage or lose them — so this is
## not the recruitment system the owner deferred for good (ROADMAP → Q-F); it is
## the repair station given a face and a hand, because holding X over your own
## hull mid-fight is the nuisance the mode exists to shed.
##
## The station still DRAWS SHIP POWER, so a shot-out grid still cannot keep up:
## the stakes stay where v0.79.0 put them (fragility, not attrition). F2 →
## `dive_assistant` turns the whole thing off.
func _dive_post_the_assistant() -> void:
	if not Tunables.get_bool("dive_assistant") or not is_instance_valid(local_ship):
		return
	if local_ship.repair_cells.is_empty():
		debug_add_mender()
	if local_ship.repair_cells.is_empty():
		return  # no room on this hull; the X wand is still the way
	local_ship.menders_running = true
	_spawn_crewman(local_ship, "R", "mender")


## How far the helm answers E OUTSIDE a run — the helm is a station you stand at,
## unchanged. In a run the answer is not a radius at all; see `_dive_helm`.
func _helm_reach() -> float:
	if player == null:
		return 0.0
	return player.HELM_REACH


## THE HELM IN A RUN IS THE SHIP, NOT A SPOT ON IT (owner 2026-08-30: *"the 'E
## take the helm' is WAY too reachable from above the platform even. It should be
## just basically within the boundaries of the ship + one or two more tiles"*).
##
## A radius around the helm CELL is the wrong shape twice over, and both showed
## up in one play session. On a small hull a 4× radius reaches far past the bow
## and answers from empty sky. On a BIG one it does the opposite — the owner's
## *"other massive ship … is unmannable"* — because standing on the far end of a
## long deck puts you outside a radius drawn from a cell buried amidships, no
## matter how generous the radius is. Radius scales with the wrong thing: the
## helm's position, not the hull.
##
## So a run asks the honest question instead: **are you ON this ship?** The body
## has to be inside the hull's own `solid_bounds` grown by
## `DIVE_HELM_MARGIN_CELLS` authored blocks, and then the nearest helm cell is
## yours however far away it is. Big hulls become boardable from anywhere on
## them; small hulls stop answering from off the bow.
##
## `solid_bounds` is in the ship's frame and is ALREADY world pixels at any
## scale (CODEMAP; the eightfold bug) — the margin is what carries the scale.
## The owner's number, in the units they said it in: BLOCKS of the deck, which at
## 8× is 8 × Ship.CELL each ("so it'd be 8 or 16 tiles").
const DIVE_HELM_MARGIN_CELLS := 2.0
func _dive_helm() -> Array:
	if player == null or not is_instance_valid(player):
		return []
	# Before you commit there is no `local_ship` — the candidates on the deck are
	# the ships that answer, which is how a run starts at all. After, it is only
	# yours (`_helm_candidates`).
	# One BLOCK is Ship.CELL x world_scale, because a blueprint cell upscales into
	# that many. Two blocks is 256 px at 8x and 32 px at 1x.
	var margin := DIVE_HELM_MARGIN_CELLS * Ship.CELL * float(world_scale)
	var here := player.global_position
	for s in _helm_candidates():
		var ship := s as Ship
		if ship == null or not is_instance_valid(ship) or ship.helm_cells.is_empty() 				or ship.faction != 0 or ship.is_carcass() 				or ship.creature_kind != "" or ship.is_nest:
			continue
		var b := ship.solid_bounds
		if b.size == Vector2.ZERO:
			continue
		var local := ship.to_local(here)
		if not DiveRun.helm_in_reach(b, local, margin):
			continue
		var best: Vector2i = ship.helm_cells[0]
		var best_d := INF
		for cell in ship.helm_cells:
			var d: float = ship.local_pos_of(cell as Vector2i).distance_squared_to(local)
			if d < best_d:
				best_d = d
				best = cell
		return [ship, best]
	return []


## Which ships offer a helm to E. In THE DIVE, only YOUR OWN — the extended
## reach would otherwise let you board a passing hulk from across the sky, and
## in a mode where the ship IS the run, boarding someone else's is not a verb.
func _helm_candidates() -> Array:
	if dive != null and is_instance_valid(local_ship):
		return [local_ship]
	return fleet.ships()


## Put the body ON the helm before boarding, so the ride pose is the helm rather
## than wherever you happened to be standing outside the hull. In-run only; the
## expedition game walks to its cabin.
func _dive_step_in(ship: Ship, cell: Vector2i) -> void:
	if ship == null or not is_instance_valid(ship) or player == null \
			or not is_instance_valid(player) or not ship.has_block(cell):
		return
	player.global_position = ship.to_global(ship.local_pos_of(cell))
	player.velocity = Vector2.ZERO
	player.forgive_fall()   # the mode moved you, so the mode pays for the landing


## Stepping off the helm in THE DIVE puts you on TOP of the hull, above where
## you were standing — not in a cabin whose door the mode just made pointless.
## `solid_bounds` and `local_pos_of` are in the ship's own frame, which at any
## world scale is ALREADY world pixels: the scale lives in the CELL COUNT
## (`ShipLayout.upscale_cells`), never in the node's transform. So the offset
## below is scaled explicitly and the bounds are not. (This comment used to say
## the opposite, and cost four rewrites of the launch deck.)
func _dive_step_out(ship: Ship) -> void:
	if ship == null or not is_instance_valid(ship) or player == null \
			or not is_instance_valid(player):
		return
	var b := ship.solid_bounds
	if b.size == Vector2.ZERO:
		return
	var local := Vector2(
		clampf(ship.to_local(player.global_position).x, b.position.x, b.end.x),
		b.position.y - Ship.CELL * float(world_scale) * 1.5)
	player.global_position = ship.to_global(local)
	player.velocity = Vector2.ZERO
	player.forgive_fall()   # stepping off the helm is not a fall you chose


## One frame of the run. Reads the altitude, hands it to the model, and gives
## the events bodies.
func _tick_dive(delta: float) -> void:
	if dive == null or dive.outcome != "":
		return
	if player == null or not is_instance_valid(player):
		return
	# TAKING A HULL IS THE FIRST DECISION OF THE RUN. Until you do, the run has
	# no ship to lose and the ship-loss ending cannot fire; the moment you take
	# one it becomes yours — doors open, the assistant posts, and from here
	# losing it is the ending.
	if not dive.committed:
		if is_instance_valid(local_ship) and player.is_piloting():
			dive.commit()
			_dive_thaw(local_ship)
			_dive_open_doors()
			_dive_post_the_assistant()
			_notify("She is yours. Lose her and the run ends with her.")
	elif is_instance_valid(local_ship) and local_ship.has_helm():
		# LOSING THE SHIP ENDS THE RUN (owner ruling). `local_ship` blinks null
		# for a frame whenever the binding is refreshed, so the verdict waits out
		# a grace — a run ended by a rebind would be the cruellest bug here.
		_dive_shipless = 0.0
	else:
		_dive_shipless += delta
		if _dive_shipless >= DIVE_SHIPLESS_GRACE:
			dive.lose()
			_notify(DiveRun.outcome_line(dive.ledger()))
			return
	# The assistant never downs tools: if the station stopped (a rebuild, a stray
	# E, a repaired hull), they start it again. That is what "automatically mans
	# the repair spot" means — you should never have to think about it again.
	if dive.committed and Tunables.get_bool("dive_assistant") \
			and is_instance_valid(local_ship) \
			and not local_ship.repair_cells.is_empty():
		local_ship.menders_running = true
	_dive_hold_the_descent(delta)
	_dive_nudge_if_stuck(delta)
	_dive_pursue(delta)
	_dive_cull_the_wake(delta)
	_hold_the_corridor(delta)
	for ev in dive.advance(delta, _player_altitude_frac(),
			Tunables.get_num("dive_surge_period")):
		match String(ev):
			"depth":
				# Cut the NEXT rung as you arrive at this one, so there is always
				# somewhere visible below to aim at.
				_cut_landing(dive.depth)
				_cut_landing(dive.depth + 1)
				_notify("%s. The air is worse down here." % DiveRun.depth_label(dive.depth))
				# EVERY RUNG IS GARRISONED (owner 2026-08-30: "does it sound
				# alright to simply jump down, get a few things, and die having
				# FULLY IGNORED the entire 8 levels?"). It did not, and a purely
				# TIMED surge is what allowed it: a full descent takes about two
				# minutes, `dive_surge_period` is 45 s, so a fast line down met
				# two pickets in eight rungs and out-fell both. Arriving at a
				# depth now spawns that depth's own picket, so what you meet is a
				# function of HOW DEEP YOU WENT, not how long you loitered. The
				# timer stays on top of it — that is the pressure to keep moving.
				if dive.depth > 1:
					_dive_surge()
			"surge":
				_dive_surge()
			"leviathan":
				_notify("THE FLOOR. Something enormous is down here with you.")
				_dive_wake_leviathan()
			"escaped":
				_dive_bank()


## Half the width of the shaft a run holds you in, in world px.
func dive_corridor_half() -> float:
	return DIVE_CORRIDOR_WIDTHS * _dive_shelf_span().x


## THE DIVE IS A SHAFT, NOT A COUNTRY (owner 2026-08-30: "I'm not sure how much
## sense it makes for the dive to have a FULL wide map if the purpose is to go
## straight down … just looking for ways to make things more linear").
##
## The answer is a CORRIDOR rather than a rail: nothing takes the stick away and
## nothing stops you climbing (the climb IS the extraction), but stray far enough
## sideways and the air leans on you until you come back. It reads as weather,
## it needs no wall to collide with, and it keeps the ladder's slalom — itself
## clamped to `DiveRun.LADDER_SPREAD` — comfortably inside what you can see.
func _hold_the_corridor(delta: float) -> void:
	if not is_instance_valid(local_ship):
		return
	var cx: float = _world_rect.get_center().x if _world_rect.size.x > 0.0 else 0.0
	var half := dive_corridor_half()
	if half <= 0.0:
		return
	var over := absf(local_ship.global_position.x - cx) - half
	if over <= 0.0:
		return
	var widths := over / maxf(_dive_shelf_span().x, 1.0)
	var push := -signf(local_ship.global_position.x - cx) \
		* DIVE_CORRIDOR_PUSH * float(world_scale) 		* minf(widths, DIVE_CORRIDOR_MAX_WIDTHS)
	local_ship.apply_central_force(Vector2(push, 0.0) * local_ship.mass)
	if player != null and is_instance_valid(player) and not player.is_piloting():
		player.velocity.x += push * delta


## A depth's den comes for you: hunters spawned AHEAD of you on your own line,
## as many as the ladder says, spread across it so you fly into a picket rather
## than a stack.
##
## Ahead, not abeam, and the measurement is why. `tools/dive_probe.gd` clocked a
## committed dive at about 1,950 px/s; a kraken closes at a fraction of that, so
## anything spawned beside you is scenery you have already left before its brain
## finishes waking. Putting the picket a few seconds down your travel vector
## means you meet it — and it is the honest fiction too: they live below you and
## come up. Nothing spawns ON you; the lead is always at least a hull length.
func _dive_surge() -> void:
	if dive == null or player == null or not is_instance_valid(player):
		return
	var n := DiveRun.surge_count(dive.depth)
	var kinds := DiveRun.surge_kinds(dive.depth)
	var ws := float(world_scale)
	# Your line: where you are actually going. A drifting or parked ship gets a
	# straight-down picket, which is where the deep is anyway.
	var vel := Vector2.DOWN
	var speed := 0.0
	if is_instance_valid(local_ship):
		speed = local_ship.linear_velocity.length()
		if speed > 200.0 * ws:
			vel = local_ship.linear_velocity / speed
	var lead := maxf(Tunables.get_num("dive_surge_lead") * maxf(speed, 900.0 * ws),
		1800.0 * ws)
	var ahead := player.global_position + vel * lead
	var across := Vector2(-vel.y, vel.x)
	# SPACE THEM BY WHAT THEY ACTUALLY ARE (owner 2026-08-30: "some enemies are
	# spawning way too close together, so their ships are literally stuck to each
	# other"). The spread was a flat 900 px x scale between pickets - a number
	# that knew nothing about the hulls it was separating. A kraken is several
	# times a gunboat, so at the bottom of the ladder the line spawned
	# interpenetrating. Each picket is now placed clear of the LAST one's real
	# solid_bounds, so the gap is measured in hulls and DiveRun.SURGE_LADDER can
	# hold anything without this needing a new number. They alternate sides of
	# your line, so the picket brackets your course instead of trailing off it.
	var air := DIVE_PICKET_AIR * ws
	var right := 0.0
	var left := 0.0
	for i in n:
		var born := debug_spawn(String(kinds[i % kinds.size()]),
			ahead + vel * float(i % 2) * 500.0 * ws)
		if born == null or not is_instance_valid(born):
			continue
		var half := 900.0 * ws
		if born.solid_bounds.size.x > 0.0:
			half = born.solid_bounds.size.x * 0.5
		var centre := 0.0
		if i == 0:
			right = half + air
			left = -half - air
		elif (i % 2) == 1:
			centre = right + half
			right = centre + half + air
		else:
			centre = left - half
			left = centre - half - air
		born.global_position = ahead + across * centre 			+ vel * float(i % 2) * 500.0 * ws
		_dive_surged.append(born.get_instance_id())
	# The top of the ladder is gunboats and the bottom is krakens, so the line
	# says which — "they come" reads the same whether it is a crewed vessel you
	# can out-fly or something from the floor.
	_notify("They come — %d %s." % [n, "out of the dark" if kinds.has("kraken")
		else "under sail"])


## The floor's resident. Until the Leviathan encounter is built (BACKLOG), the
## existing city-whale boss body stands in: it already lairs in every world and
## already has a boss-tier pool, so the depth-8 beat is playable now and the
## bespoke fight replaces this one call.
func _dive_wake_leviathan() -> void:
	if player == null or not is_instance_valid(player):
		return
	_spawn_boss_at(player.global_position
		+ Vector2(3400.0 * float(world_scale), 0.0))


## The escape landed: move the banked coins into the permanent wallet. THIS is
## the only path from a run's pot to the meta economy — dying pays nothing, and
## that is the whole tension of the mode.
func _dive_bank() -> void:
	if dive == null:
		return
	if player != null and is_instance_valid(player) and player.wallet != null:
		player.wallet.add(dive.banked)
	_notify(DiveRun.outcome_line(dive.ledger()))


## Credit a creature death to the run, if one is live. Called from the same
## place the ecology hears about a death, so anything with a brain counts.
## WHO killed it is not asked — a networked/attributed kill is the same seam
## harvesting already has (BACKLOG).
func _dive_credit_kill(kind: String) -> void:
	if dive == null or dive.outcome != "":
		return
	var coins := dive.credit_kill(kind)
	if coins > 0 and _pickups != null and player != null and is_instance_valid(player):
		_pickups.add(player.global_position + Vector2(0.0, -120.0 * world_scale),
			"+%d coins" % coins, float(world_scale))


## Is a run over and showing its ledger? The fall-out-of-the-world respawn is
## suppressed while it is: on a lost run the body FALLING is the run-over
## screen, and teleporting it back to a deck would delete the ending.
func dive_over() -> bool:
	return dive != null and dive.outcome != ""


## THE DIVE in plain values for DiveHud, or null when no run is live. The
## world-decides/layer-paints seam for the mode.
func dive_status() -> Variant:
	if dive == null:
		return null
	var out := dive.ledger()
	out["depths"] = DiveRun.DEPTHS
	out["shipless"] = not dive.committed
	out["depth_label"] = DiveRun.depth_label(dive.depth)
	out["headline"] = DiveRun.outcome_line(out)
	return out


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
		# AT AN OUTPOST the digits buy stock instead of stat levels. The two can
		# never both be in reach (a Dive landing has no trainer on it), so this
		# is a precedence rule with nothing to disambiguate.
		if near_outpost() != null:
			try_buy_stock(stat_index)
			return
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
		# THE OUTPOST takes over the sheet when you are standing at one: it is
		# the same panel, the same digits, a different trade. `pot` is what you
		# are spending — the coins you have NOT banked, which is what makes every
		# purchase a decision and not a formality.
		"outpost_stock": dive_stock(),
		"pot": 0 if dive == null else dive.pot,
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
	# THE HELM YOU HOLD IS YOUR SHIP (owner 2026-08-25): no claimed hull
	# anywhere — the starter cannibalized for corpse-airship parts, eaten by
	# a kraken, melted in the lava — but the player is PILOTING something.
	# Adopt it and stamp the claim, so the ghost/build/repair/HUD pipeline
	# (gated on local_ship) keeps serving the ship they actually fly, and a
	# save made aboard reloads it as theirs. On foot with truly no ship,
	# null stands — the HUD notice + respawn safety-net case.
	if player != null and is_instance_valid(player) and player.is_piloting() \
			and is_instance_valid(player.piloting):
		local_ship = player.piloting
		local_ship.pilot_peer = _my_id()


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

	# LAZY WORLD (the ×4 extent, 2026-08-24): build plants only the spawn floor;
	# islands generate region-by-region as foci approach (ensure_generated in
	# _stream_terrain). Eager generation of the full ×4 world was a ~25 s boot
	# stall — "no loading screens ever" is charter. See IslandGen.
	IslandGen.prime(terrain)
	# Give the immediate spawn neighbourhood its islands NOW (one bounded burst,
	# a handful of regions) so the first camera frame is never empty sky where
	# land belongs.
	IslandGen.ensure_generated(terrain, world_seed, [SHIP_START],
		terrain.chunk_px() * terrain.subdiv * 3.0, 64)

	# Hidden easter egg: plant the secret Cairn beacon after normal generation so
	# it always exists (maps/world/easter_eggs.gd → the Cairn). Not surfaced in
	# the HUD; documented dev-facing in docs/DECISIONS.md.
	EasterEggs.plant_cairn(terrain)
	EasterEggs.plant_high_cairn(terrain)  # egg 5: the bookend beacon


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
	# Lazy generation runs ahead of promotion: regions whose islands could
	# reach any focus generate first (amortized), so a chunk always promotes
	# with its data present. Budget 2/frame — a fresh area trickles in over a
	# few frames instead of hitching one.
	#
	# GENERATION HAS TO LEAD THE CAMERA (owner 2026-08-30: "terrain and creatures
	# generate kind of late - half way through the screen"). The radius was
	# `primary_range_px`, which IS half the visible extent - so the BEST case was
	# land appearing exactly at the screen edge, and with a 2-regions-per-frame
	# budget anything moving outran it and land appeared inside the frame. Two
	# changes, both about being EARLY rather than doing more work per frame:
	#
	#   * the radius is GEN_LOOKAHEAD x the render range, so a region generates
	#     while it is still off-screen and has frames to spare;
	#   * whatever the camera is following also asks for ground GEN_LEAD_SECONDS
	#     down its own velocity, so the direction you are actually travelling is
	#     generated FIRST. At a dive's ~3,900 px/s that is most of a screen of
	#     warning; standing still it costs nothing (the lead point is where you
	#     already are).
	var gen_foci: Array = []
	gen_foci.append_array(primary)
	gen_foci.append_array(secondary)
	gen_foci.append_array(_gen_lead_points())
	IslandGen.ensure_generated(terrain, world_seed, gen_foci,
		(terrain.primary_range_px if terrain.primary_range_px > 0.0
			else terrain.chunk_px() * terrain.subdiv * 2.0) * GEN_LOOKAHEAD)
	terrain.update_streaming(primary, secondary)


## How much wider than the visible half-extent terrain generates (`_stream_terrain`).
const GEN_LOOKAHEAD := 1.75
## How far down its own travel vector a moving camera asks for ground, seconds.
const GEN_LEAD_SECONDS := 1.2


## Where the camera-carrying body is HEADING, as an extra generation focus. Only
## what the camera follows - a distant whale's course is nobody's problem.
func _gen_lead_points() -> Array:
	var out: Array = []
	if player == null or not is_instance_valid(player):
		return out
	if is_instance_valid(local_ship) and player.is_piloting():
		out.append(local_ship.global_position
			+ local_ship.linear_velocity * GEN_LEAD_SECONDS)
	else:
		out.append(player.global_position + player.velocity * GEN_LEAD_SECONDS)
	return out


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
## block breaks until it is dead).
##
## THE 30-SECOND CEILING (owner 2026-08-26, on reading balance_probe's
## seconds): "5 full minutes of sustained fire to kill something is not ok.
## at most it should be 30 seconds, for now, if anything, for something that
## just continuously takes damage." At 15,000 this pool measured ~6 MINUTES
## against the starter's 40 dps (turret_damage 20 / TURRET_COOLDOWN 0.5) —
## the tuning before it was three minutes, and both were an undertaking
## nobody asked for. Every authored pool in the game now sits under
## CEILING_SECONDS × 40 dps = 1,200 hp — the ladder is `tools/balance_probe.gd`
## output, and the guard is run_tests' `_test_no_target_outlives_the_ceiling`.
## Scale-free, since damage amounts are. THE health feel knob; ram lethality
## is PUSH_ACCEL (whale_ai) and hull toughness is per-cell hp (block_db).
##
## ANCHORED TO THIS NUMBER: Ship.CREATURE_IMPACT_FACTOR and
## CREATURE_TERRAIN_IMPACT_FACTOR are absolute-hp knobs tuned as a PERCENT of
## this pool ("a bruise, never a death"). Both were divided by the same 15
## when this went 15,000 → 1,000, so a crash still costs the same ~3%.
const WHALE_HEALTH := 1000.0


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
	# TAGGED "whale" (the boss overrides to "whale_city" post-spawn): whale-family
	# deaths feed the ecology meter, and the tag has to ride the payload so it
	# survives the wire and a save (from_data reads it), not a server-only field.
	# Every whale-family kind still routes to WhaleAI (the _whale_ai_for default).
	var whale := fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(ShipLayout.load_cells(path), world_scale),
		pos, 0, 0.0, float(world_scale), 2, {"creature_kind": "whale"})
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


## The city-whale BOSS (ships/whale_city.ship) lairs at a FIXED fraction of the
## world — far to starboard and DEEP — so it stands in EVERY world like the
## Cairns, never gated behind a rare seed. Dormant until you fly out to it, so
## it is a genuine "what IS that" you stumble on in the overworld.
const BOSS_PATH := "res://ships/whale_city.ship"
const BOSS_SPAWN_FRAC := Vector2(0.72, 0.16)   # x across from port; y up from the floor


## The owner's Blueprint-Loft test ship (ships/loft_test.ship), spawned beside the
## player via F2 so they can walk onto / grapple it. Upscaled 8x like a creature
## body so the 1x-authored doors become player-height and the helm is boardable.
## Faction 0 (your side), UNPILOTED until you take its helm. It has no lift blocks,
## so it falls — grapple to it (RMB) or add gasbags in the Loft.
const LOFT_PATH := "res://ships/loft_test.ship"
func _spawn_loft_at(at: Vector2) -> Ship:
	return fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(ShipLayout.load_cells(LOFT_PATH), world_scale),
		at, 0, 0.0, float(world_scale), 0)


## Spawn a ship from PASTED .ship text (the Blueprint Loft's export) beside the
## player — closes the design→fly loop with no file round-trip (owner 2026-08-27).
## Parses the same format load_cells does, upscales 8x so it is boardable, faction
## 0. Returns null on empty/garbled text. Authority only, like debug_spawn.
func debug_spawn_text(text: String, at: Vector2) -> Ship:
	if Net.is_online() and not Net.is_server():
		return null
	var cells := ShipLayout.parse(text)
	if cells.is_empty():
		return null
	return fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(cells, world_scale),
		at, 0, 0.0, float(world_scale), 0)


## Plant the boss at its lair. Called once at world build, after the pod.
func _spawn_boss() -> void:
	if _world_rect.size.y <= 0.0:
		return
	_spawn_boss_at(Vector2(
		_world_rect.position.x + BOSS_SPAWN_FRAC.x * _world_rect.size.x,
		_world_rect.end.y - BOSS_SPAWN_FRAC.y * _world_rect.size.y))


## Spawn the LEVIATHAN ARCOLOGY at `at`, cleared of terrain (its footprint is
## city-sized). A whale-family creature — WhaleAI roam, whale-tier tameable — with
## a BOSS pool (its own lever, defaulting to the 30-s ceiling max). Shared by the
## lair plant and the F2 button. Returns it (null if the spawner is not up).
func _spawn_boss_at(at: Vector2) -> Ship:
	var cells := ShipLayout.upscale_cells(ShipLayout.load_cells(BOSS_PATH), world_scale)
	var pos := WhaleSpawn.clear_spawn_pos(
		terrain, at, WhaleSpawn.footprint_of(cells), float(world_scale))
	var boss := _spawn_one_whale(BOSS_PATH, pos)
	if boss == null:
		return null
	boss.creature_kind = "whale_city"   # id only; the AI still defaults to WhaleAI
	var hp := Tunables.get_num("boss_health")
	boss.shared_health = hp
	boss.shared_health_max = hp
	boss.rebuild()
	return boss


## How many small critters roam near spawn — a few so the early taming target is
## easy to find. Shared by the shipped scene and reset (the startup suites assert
## the total ship count includes these).
const CRITTER_COUNT := 2
## A critter's shared pool — the FLOOR of the balance ladder: ~10 s of starter
## fire, the shortest fight in the game, so the first creature you ever shoot
## at dies while you are still learning the guns. Unchanged by the 30-second
## ceiling (2026-08-26) because it was already well inside it; what changed is
## that it is now 40% of a whale rather than 2.7% of one.
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
	# Tagged "critter" so a meadow death is never miscounted as a whale by the
	# ecology meter (both were "" before and both use WhaleAI). Rides the payload
	# for the same wire/save reasons as the whale tag.
	var critter := fleet.spawn_ship_from_cells(
		ShipLayout.upscale_cells(ShipLayout.load_cells("res://ships/critter.ship"), world_scale),
		pos, 0, 0.0, float(world_scale), 2, {"creature_kind": "critter"})
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
##
## 12,000 → 1,200 under the owner's 30-second ceiling (2026-08-26): the deep
## hunter sits AT the ceiling, the toughest single body in the game at ~30 s
## of unbroken starter fire — and that is the floor of a real kraken fight,
## since the shell casing means most shots never reach the pool at all.
const KRAKEN_HEALTH := 1200.0
## The two owner-adopted kraken body plans (both shell-casing-surrounds-meat with a
## tiny exposed-meat mouth): kraken_b (giant squid) and kraken_c (ammonite conch).
const KRAKEN_PLANS := ["res://ships/kraken_c.ship", "res://ships/kraken_b.ship",
	# Design jam #2 (2026-08-26): three new shell-cased silhouettes, each with a
	# tiny exposed-meat weak spot (snipe the gap; the casing shrugs off shots).
	"res://ships/kraken_urchin.ship", "res://ships/kraken_angler.ship",
	"res://ships/kraken_nautilus.ship"]
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
		var sovereign := i == 0 and EasterEggs.is_sovereign_kraken(world_seed)
		# Spread across the deep, staggered a little in altitude so they do not
		# spawn stacked; wide enough apart that two do not overlap on spawn.
		var pos := Vector2(cx + (float(i) - 0.5 * (KRAKEN_COUNT - 1)) * 3200.0 * world_scale,
			y + (i % 2) * 260.0 * world_scale)
		var k := _spawn_one_kraken(path, pos)
		# Egg 4: a rare seed dresses the lead kraken as the Deep Sovereign. Set
		# AFTER the spawn's own tint, and the tint is cosmetic (rides body_tint,
		# never mass/collision/damage — the same rule the ghost whale follows).
		if k != null and sovereign:
			k.body_tint = EasterEggs.SOVEREIGN_KRAKEN_TINT


## Spawn ONE kraken of body plan `path` at `pos` (null if the spawner is not ready).
## Mirrors _spawn_one_whale's pool-then-rebuild coarse-collider ordering; marks it a
## kraken (creature_kind → the two-ended KrakenAI) and sets its taming tier to 3 —
## the top one, above the whale's 2 and the critter's 1 (owner 2026-08-24).
##
## DEEP-SPAWN KEEP-OUT: the deep band is where the island field is thickest, so
## the computed `pos` can be inside rock. The footprint is probed and scattered
## (deterministically — WhaleSpawn.clear_spawn_pos) BEFORE the spawn, never moved
## after it: `pos` rides the spawn payload, and a post-spawn nudge would exist on
## the server only (godot-quirks).
func _spawn_one_kraken(path: String, pos: Vector2) -> Ship:
	var cells := ShipLayout.upscale_cells(ShipLayout.load_cells(path), world_scale)
	var spawn_pos := WhaleSpawn.clear_spawn_pos(
		terrain, pos, WhaleSpawn.footprint_of(cells), float(world_scale))
	var kraken := fleet.spawn_ship_from_cells(cells, spawn_pos, 0, 0.0, float(world_scale), 2)
	if kraken == null:
		return null
	kraken.shared_health = KRAKEN_HEALTH
	kraken.shared_health_max = KRAKEN_HEALTH
	kraken.creature_kind = "kraken"   # → KrakenAI (two-ended)
	# TAMEABLE at the TOP tier (owner 2026-08-24, reversing the untameable
	# ruling: "you can tame krakens, they just are a little wild in their
	# movement and always do damage if you touch their mouth parts"). tame_level
	# 3 keeps it OUTSIDE the whale (==2) and critter (==1) startup filters while
	# gating on Master Trader + — Stats.taming_level() must reach it.
	kraken.tame_level = 3
	kraken.body_tint = Color(0.78, 0.82, 0.74)
	kraken.rebuild()
	# Latch the sealed LOOT CAVITY now, while the body is whole. The map cannot be
	# taken after a breach (the flood reaches the pocket then and it stops reading
	# as sealed), and combat can crack the wall long before the first harvest asks.
	kraken.cavity_cells()
	return kraken


## Spawn ONE basilisk at `pos` — the top-band fire-spitter. Same pool-then-
## rebuild ordering as every other creature (a living creature must rebuild after
## its pool is set or it keeps the precise collider for life), and the same
## deep-spawn keep-out, since an eyrie can sit against an island.
func _spawn_one_basilisk(pos: Vector2) -> Ship:
	var cells := ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/basilisk.ship"), world_scale)
	var spawn_pos := WhaleSpawn.clear_spawn_pos(
		terrain, pos, WhaleSpawn.footprint_of(cells), float(world_scale))
	var beast := fleet.spawn_ship_from_cells(cells, spawn_pos, 0, 0.0,
		float(world_scale), 2)
	if beast == null:
		return null
	var hp := Tunables.get_num("basilisk_health")
	beast.shared_health = hp
	beast.shared_health_max = hp
	beast.creature_kind = "basilisk"   # → BasiliskAI (stand off and spit)
	# Top taming tier, like a kraken: a fire-breathing serpent is not an early
	# mount. It stays outside the whale (2) and critter (1) startup filters.
	beast.tame_level = 3
	beast.body_tint = Color(0.86, 0.72, 0.52)
	beast.rebuild()
	return beast


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

## Spawn `kind` ("hulk"/"bandit", "whale", "critter", "kraken", "carcass") at
## world position `at`, returning the new ship (null off the authority or if
## the spawner is not ready). STANDING ORDER (owner 2026-08-24): every new
## spawnable added to the game gets a kind here + a button in DebugWindow, in
## the same round.
func debug_spawn(kind: String, at: Vector2) -> Ship:
	if Net.is_online() and not Net.is_server():
		return null  # networked debug spawns are a seam — authority only
	match kind:
		"hulk", "bandit":
			return _spawn_hulk_at(at)
		"whale":
			return _spawn_whale_at(at)
		"critter":
			return _spawn_one_critter(at)
		"basilisk":
			return _spawn_one_basilisk(at)
		"boss", "city":
			return _spawn_boss_at(at)
		"loft":
			return _spawn_loft_at(at)
		"kraken":
			# Alternate the two adopted bodies — the deep hunter on demand
			# (owner 2026-08-24: "I can't find krakens").
			_debug_kraken_flip = not _debug_kraken_flip
			return _spawn_one_kraken("res://ships/kraken_%s.ship"
				% ("b" if _debug_kraken_flip else "c"), at)
		"carcass":
			# A DEAD whale on demand — the corpse-airship / harvest / cavity
			# test bench (bolt on thrust and fly it). A real variant body whose
			# pool is drained AFTER the spawn ordering, then rebuilt so it
			# flips to the precise, breakable carcass collider.
			var corpse := _spawn_whale_at(at)
			if corpse != null:
				corpse.shared_health = 0.0
				corpse.rebuild()
			return corpse
	return null


## Alternates the debug kraken spawn between the two adopted bodies (b/c).
var _debug_kraken_flip := false


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


## Grant `n` of EVERY crafted balloon size to the local player (debug Player tab).
## STANDING ORDER (owner 2026-08-24): a feature F2 cannot reach is invisible —
## balloons cost crafted items from v0.49.0, so the playtest bench needs a way to
## get stock without first hunting a whale for blubber and smelting copper.
func debug_grant_balloons(n: int = 3) -> void:
	if player == null or not is_instance_valid(player) or player.inventory == null:
		return
	for size in Ship.BALLOON_LIFT.size():
		player.inventory.add(ItemDB.balloon_item_for(size), n)


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


## SANDBOX LOADOUT (owner 2026-08-28): the "avenue to cut the fluff and focus on
## one thing". One button drops you into the meat — every gate open, nothing
## scarce — so combat / flight / taming can be FELT on their own without the
## craft-and-grind setup the Source buries its game behind. It EXPANDS NO SCOPE:
## it only unlocks what is already built, and the full crafting game is one toggle
## away (sandbox_mode off). Idempotent — press it as often as you like.
##
## What it does: turns sandbox_mode ON (deep-air gate off), maxes every stat (so
## taming / mining / double-jump / trade gates open), fills the wallet, heals, and
## grants a deep stack of every obtainable item (materials to build with, products
## to craft with, balloons to fly with). Authority / single-player, like every
## other debug hook.
const SANDBOX_STACK := 99
func debug_sandbox_loadout() -> void:
	if Net.is_online() and not Net.is_server():
		return
	Tunables.set_value("sandbox_mode", true)
	debug_max_stats()
	debug_heal_player()
	if player != null and is_instance_valid(player):
		if player.wallet != null:
			player.wallet.add(5000)
		if player.inventory != null:
			# Every mined MATERIAL (to build/paint) and every product/crafted good
			# (to satisfy any recipe), so crafting is optional rather than a wall.
			for t in TerrainDB.Type.values():
				if TerrainDB.is_solid(t):
					player.inventory.add(t, SANDBOX_STACK)
			for id in ItemDB.ITEMS:
				player.inventory.add(id, SANDBOX_STACK)
	_notify("SANDBOX: kitted out — every gate open, nothing scarce. Spawn what you want (F2) and play.")


## Bolt a repair station onto the local ship (debug Player tab) so the mender can
## be tried without mining the parts. Stamps a REPAIR bundle at the first legal
## spot found near existing structure — best-effort, sampling seed cells across
## the hull so a busy deck still finds room. Returns whether one was placed.
func debug_add_mender() -> bool:
	if not is_instance_valid(local_ship):
		return false
	var t := BlockDB.Type.REPAIR
	# Seed cells to try. A BUNDLE (8×) snaps to the nearest legal spot around an
	# OCCUPIED seed; a PRIMITIVE (1×, the test scale) needs an EMPTY cell touching
	# structure — so offer both: occupied cells and their empty neighbours.
	var seeds: Array = []
	seeds.append_array(local_ship.helm_cells)
	var keys: Array = local_ship.blocks.keys()
	var stride := maxi(1, int(keys.size() / 40))
	for i in range(0, keys.size(), stride):
		seeds.append(keys[i])
	for i in range(0, keys.size(), stride):
		for off in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = (keys[i] as Vector2i) + off
			if not local_ship.blocks.has(n):
				seeds.append(n)
	for seed in seeds:
		var order := BuildPreview.stamp_order(local_ship,
			BuildPreview.snapped_stamp(local_ship, seed as Vector2i, t, false))
		if not order.is_empty():
			local_ship.net_set_blocks(order, t)
			return true
	push_warning("debug_add_mender: no legal spot for a 4x4 repair station")
	return false


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
	if _build_picker != null and _build_picker.is_open():
		return true  # the grid owns the cursor: no shooting/placing THROUGH it
	var vp := get_viewport()
	return vp != null and vp.gui_get_hovered_control() != null


## LMB is the trigger everywhere (owner: "the player needs some small pew
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
		if not is_instance_valid(ship) or ship.faction != 1 or ship.dormant:
			continue  # only HOSTILES gun; wildlife has its own reactions.
			# Dormant: out of the simulation, so out of the fight too — a body
			# nothing can shoot back at must not be shooting (the same rule
			# _creature_swim follows).
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
		# Bandits hunt the PLAYER side, not the wildlife — and only a hull that
		# READS AS CREWED (owner 2026-08-26). A crew that has already been shot
		# at drops the filter: it knows who did it. See _looks_crewed.
		var provoked: bool = _is_provoked(id)
		var target := _nearest_ship_of_faction(ship, 0, not provoked)
		if target == null:
			continue
		var d := ship.global_position.distance_to(target.global_position)
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
		if not is_instance_valid(ship) or ship.faction != 1 or ship.dormant:
			continue  # dormant hulls coast on the slow tick, not on their AI
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
			# Same rule as the guns: a parked, empty hull is scenery to fly
			# past, not a thing to run down — unless we have been shot at.
			target = _nearest_ship_of_faction(ship, 0, not _is_provoked(id))
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
		# A kraken's mouth chews PEOPLE as well as hulls, so the world hands it the
		# on-foot player each tick. Re-handed every tick rather than latched, so a
		# body that dies, respawns or takes a helm is never a stale reference.
		if ai is KrakenAI:
			(ai as KrakenAI).prey_player = _on_foot_player()
		if ship.dormant:
			# OUT of the simulation: its forces would be ignored anyway, and a
			# dormant body that still runs its brain can SHOOT — a basilisk
			# beyond the dormancy range kept spitting at a ship it was drifting
			# away from (tools/threat_probe.gd). Dormancy's slow tick is what a
			# far creature gets instead. The prey reference above is still kept
			# current: it is a pointer, not an action, and a stale one would
			# dangle the moment the body woke.
			continue
		ai.tick(delta, target)
		# A basilisk's spit is a PROJECTILE, and projectiles are spawned by the
		# world — one spawn path, as with every gun. The brain raises a request
		# and the world takes it.
		if ai is BasiliskAI:
			var at: Vector2 = (ai as BasiliskAI).take_spit()
			if at.x != INF:
				_spit_fire(ship, at)


## --- Dormancy -------------------------------------------------------------
## Seconds since the last sleep/wake DECISION scan, and since the last slow
## tick of the bodies that are already under. Two cadences on purpose: the
## decision has to be responsive (you should not out-fly the wake), while the
## slow tick is the whole point of the feature and wants to be rare.
var _dormancy_scan_t := 0.0
var _dormancy_tick_t := 0.0
const DORMANCY_SCAN_SECONDS := 0.25

## How many bodies are currently out of the simulation — surfaced in the F2
## physics census, because a feature that silently removes things from the
## world must be countable while you play.
var dormant_count := 0


## Put distant bodies out of the physics simulation, and advance the ones that
## are already out (owner 2026-08-25: let more things "exist, persevere, and
## act" while far away). See maps/world/dormancy.gd for why this leaves the
## SIMULATION rather than merely ticking less often — the measurement said
## script was ~2 ms and physics was 30–87 ms.
##
## Authority only. A client never decides what exists; it receives poses.
## The world clock a dormant migration is a function of. Advanced only by the
## dormant tick, so the circuit is deterministic in (anchor, clock) — no RNG
## state to save and no divergence between peers.
var _dormant_clock := 0.0


func _update_dormancy(delta: float) -> void:
	if not Net.is_server() or fleet == null:
		return
	if not Tunables.get_bool("dormancy_enabled"):
		if dormant_count > 0:
			for ship in fleet.ships():
				if is_instance_valid(ship) and ship.dormant:
					ship.set_dormant(false)
			dormant_count = 0
		return

	_dormancy_scan_t += delta
	_dormancy_tick_t += delta
	var do_scan := _dormancy_scan_t >= DORMANCY_SCAN_SECONDS
	var tick_every := maxf(0.1, Tunables.get_num("dormant_tick_seconds"))
	var do_tick := _dormancy_tick_t >= tick_every
	if not do_scan and not do_tick:
		return

	var points := Dormancy.foci(self)
	var sleep_at := Tunables.get_num("dormant_range_px")
	# HYSTERESIS: wake closer in than you sleep out, or a body hovering on the
	# boundary flips every scan — and each flip is a physics-space entry, the
	# one thing this feature exists to avoid.
	var wake_at := sleep_at * 0.8
	var elapsed := _dormancy_tick_t
	if do_tick:
		_dormant_clock += elapsed
	var count := 0
	var awake: Array = []  # [dist, ship] of simulated bodies, for the budget cap

	for ship in fleet.ships():
		if not is_instance_valid(ship):
			continue
		if Dormancy.is_exempt(ship, self):
			if ship.dormant:
				ship.set_dormant(false)
			continue
		var d := Dormancy.distance_to_nearest(ship.global_position, points)
		if d < 0.0:
			# No focus at all: nothing to be far from, so nothing sleeps.
			if ship.dormant:
				_wake(ship)
			continue
		if do_scan:
			if ship.dormant and d <= wake_at:
				_wake(ship)
			elif not ship.dormant and d > sleep_at:
				ship.set_dormant(true)
		# Awake, in range, and not something a person is on: a candidate to be
		# capped below if the vicinity is crowded (owner: "it might be a lot").
		if do_scan and not ship.dormant:
			awake.append([d, ship])
		if ship.dormant and do_tick:
			_tick_dormant(ship, elapsed)
		if ship.dormant:
			count += 1

	# THE AWAKE BUDGET (owner 2026-08-26: prioritise the vicinity — "it might be
	# a lot though"). Distance dormancy alone bounds how FAR a body can be and
	# stay simulated, not how MANY: a crowded neighbourhood (a nest's residents,
	# a pod, a spawn site right on you) could still put dozens of bodies in the
	# space at once. This caps the simulated set to the NEAREST `dormant_max_awake`
	# and sleeps the rest — so the worst case is bounded no matter how populous
	# the sky gets. 0 disables the cap. Exempt bodies (piloted/ridden) were never
	# added to `awake`, so they never count against it or get slept.
	if do_scan:
		for far_v in Dormancy.beyond_budget(awake, Tunables.get_int("dormant_max_awake")):
			var far := far_v as Ship
			if is_instance_valid(far) and not far.dormant:
				far.set_dormant(true)
				count += 1

	if do_scan:
		_dormancy_scan_t = 0.0
	if do_tick:
		_dormancy_tick_t = 0.0
	dormant_count = count


## One slow step for a body that is out of the simulation. Nothing here may
## touch the physics server — the body is not in the space — so the motion is a
## plain transform write.
##
## A LIVING creature MIGRATES: it walks a slow circuit around where it went
## under (Dormancy — the "act while far away" half of the owner's request), and
## mends while nobody is watching. Everything else COASTS to a stop, with drag
## standing in for the solver so a wreck does not sail forever in a straight
## line unobserved.
func _tick_dormant(ship: Ship, elapsed: float) -> void:
	if Dormancy.migrates(ship):
		_migrate_dormant(ship, elapsed)
		return
	ship.dormant_velocity = ship.dormant_velocity.lerp(
		Vector2.ZERO, clampf(elapsed * 0.35, 0.0, 1.0))
	if ship.dormant_velocity.length_squared() < 1.0:
		return
	ship.global_position += ship.dormant_velocity * elapsed


## A dormant creature's slow step: move along its circuit, keep to its sky, and
## mend. The creature's brain gets its new position as `home` so waking does not
## make it swim all the way back to where you last saw it — the roam resumes
## where the migration arrived.
func _migrate_dormant(ship: Ship, elapsed: float) -> void:
	var drift := Tunables.get_num("dormant_drift_mult")
	if drift > 0.0:
		var v := Dormancy.migrate_velocity(
			ship.dormant_anchor, _dormant_clock, ship.scale_unit) * drift
		ship.global_position = Dormancy.keep_in_world(
			ship.global_position + v * elapsed)
		# It arrives moving, not stopped: waking restores dormant_velocity.
		ship.dormant_velocity = v
		if ship.faction == 2:
			_whale_ai_for(ship).home = ship.global_position
	# PERSEVERE: a wounded creature mends out of sight. Only the shared pool —
	# a carcass never comes back (migrates() already excluded one), and
	# per-cell damage stays where the fight left it.
	var heal := Tunables.get_num("dormant_heal_per_min") / 60.0 * elapsed
	if heal > 0.0 and ship.shared_health < ship.shared_health_max:
		ship.shared_health = minf(ship.shared_health_max,
			ship.shared_health + heal * ship.shared_health_max)


## Rejoin the simulation, but never INSIDE the ground. A dormant body coasts
## without collision, so it can drift into an island that was not there (or
## not solid) when it went under; waking it in place would hand the solver a
## deep penetration, which is precisely the cliff v0.41.1 was fixed for. So:
## lift it clear first, using the terrain DATA (cheap, and correct even where
## no chunk is promoted).
func _wake(ship: Ship) -> void:
	if terrain != null and is_instance_valid(terrain):
		var lift := 0
		while lift < 64 and terrain.is_solid(
				terrain.world_to_cell(ship.global_position)):
			ship.global_position.y -= terrain.cell_px()
			lift += 1
	ship.set_dormant(false)


# --- World-anchored spawn sites (charter §4) --------------------------------
#
# "Population lives in the world, never around the camera." Until this, every
# living thing in the game spawned ONCE, at world build, beside the player's
# ship: fly an hour in any direction and the sky was empty, so danger was not a
# property of place but a property of the starting room.
#
# A site is a pure function of the world seed and a lattice cell
# (combat/spawn_sites.gd) — never a node, never saved. What lives here is the
# small amount of state a VISITED site accumulates: how many residents it has
# out, how much stock it has left to give, and when it may give the next one.
# Sites the player has never approached have no entry and cost nothing.
#
# The two interlocks that keep it honest:
#   * ACTIVATION is inside dormancy's wake range, so a new resident is awake and
#     simulated, and far outside the camera, so nothing is ever seen appearing.
#   * RECLAIM frees a wild resident that ends up far from every focus and gives
#     its stock back. Without it a long flight leaves a trail of dormant bodies
#     and the node count only ever grows — the resident-world rule (far regions
#     completely inert) applied to population instead of terrain.

## Seconds between site passes. Sites change on the scale of minutes; a pass
## walks a bounded box of lattice cells and must not run every frame.
const SITE_SCAN_SECONDS := 1.0

## Visited sites: lattice coord -> {stock, residents (instance ids), next_release,
## seen_at}. Also the DISCOVERY record the map reads — a site is in here exactly
## because the player has been near it. Session state today; carrying it into the
## save file is a documented seam (like the tunable overrides).
var _site_state := {}
var _site_scan_t := 0.0
## The site clock. Regen is computed from time ELAPSED between visits rather than
## ticked per site, so a site the player has not seen for ten minutes recovers
## correctly the moment they come back without anything having run meanwhile.
var _site_clock := 0.0

# --- Ecology: the deep stirs (Q-C, owner 2026-08-27) ------------------------
#
# The reviews' "smartest criticism": whale oil should MATTER ecologically —
# overhunt and the world visibly changes. Grounded in the real predator/prey it
# already has: SPERM WHALES HUNT GIANT SQUID, so whales are what keeps the
# krakens down. Kill the whales and nothing holds the deep in check — so the
# consequence the owner pictured ("krakens start taking over if you just kill
# whales") falls out one-sidedly and correctly: your greed empties the profitable
# high sky AND unleashes the dangerous deep into it.
#
# GLOBAL CREEP (owner's call over regional): one world-wide scalar, not per-site.
# `kraken_ascendancy` in [0,1] RISES a step per whale killed and DECAYS slowly
# over time (whales breeding back → predators return → the deep is pushed down).
# That decay is the SUSTAINABLE-HARVEST BUDGET expressed as a flow, not a quota:
# hunt slower than it recovers and the meter never climbs (the deep stays quiet);
# hunt faster and krakens rise. Slow decay because real whales are long-lived —
# overhunting has lasting-but-not-permanent consequences.
#
# THE SURGE: while the meter is up, every kraken den in the world fields MORE
# krakens, FASTER (`_kraken_surge_pool`). The global resident cap still bounds
# the total, so an ascendant deep crowds the awake budget with krakens — which is
# exactly "the deep taking over". No fuel anywhere: engines stay power-only
# (owner ruling 2026-08-20), so this is pure ecology.
#
# SEAM (towns): the owner's "kraken zone envelops a TOWN → they besiege it" beat
# is logged, not built — towns do not exist yet (Phase 5/6). When a settlement /
# safe-zone system lands, a high ascendancy is the trigger it reads.
var kraken_ascendancy := 0.0
## Coarse level last announced, so a crossing narrates once (not every scan).
## 0 quiet · 1 stirring · 2 rising · 3 ascendant — thresholds in `_eco_level`.
var _eco_level := 0


## The four ecology bands the meter narrates as it crosses them. A whole level of
## hysteresis is unnecessary — the meter moves in slow steps — but announcing only
## on a CHANGE keeps the notices rare.
func _eco_level_of(v: float) -> int:
	if v >= 0.75:
		return 3
	if v >= 0.5:
		return 2
	if v >= 0.25:
		return 1
	return 0


func _update_spawn_sites(delta: float) -> void:
	if not Net.is_server() or fleet == null or not is_instance_valid(fleet):
		return
	if _world_rect.size.y <= 0.0:
		return  # no framed world yet — nothing to anchor to
	_site_scan_t += delta
	if _site_scan_t < SITE_SCAN_SECONDS:
		return
	var elapsed := _site_scan_t
	_site_scan_t = 0.0
	_site_clock += elapsed
	# Ecology decays on the same slow scan cadence but is NOT gated by the
	# spawn-sites toggle: overhunting has a consequence whether or not the debug
	# lever that fills the sky with sites is on (it has its own eco_enabled).
	_tick_ecology(elapsed)

	if not Tunables.get_bool("spawn_sites_enabled"):
		return
	var points := Dormancy.foci(self)
	if points.is_empty():
		return
	# RAW px, deliberately NOT scaled by world_scale: this is a perception
	# range, and it has to stay inside dormancy's wake range (which is raw px
	# too) or a site would put its residents out already asleep and keep going.
	var radius := Tunables.get_num("site_activate_px")
	var budget := Tunables.get_int("site_max_residents") - _resident_count()
	for site in SpawnSites.near(points, radius, world_seed, _world_rect,
			float(world_scale)):
		if _tick_site(site, points, radius, budget > 0):
			budget -= 1
	_reclaim_far_residents(points)


## How many site residents are alive right now, anywhere. The GLOBAL cap this
## feeds is the safety net under the per-site pools: the lattice spacing and the
## activation range together decide how many sites can ever be live at once, and
## a tuning slip in either (or a 1x world small enough that everything overlaps)
## would otherwise let the population climb until the physics step felt it.
func _resident_count() -> int:
	var n := 0
	for ship in fleet.ships():
		if is_instance_valid(ship) and ship.from_spawn_site:
			n += 1
	return n


## Whale-family kinds — the ones whose death lets the deep off its leash. The
## city-whale boss counts too (it IS a whale); critters/krakens/basilisks do not.
const WHALE_KINDS := ["whale", "whale_city"]


## One ecology step: DECAY the meter toward quiet, and narrate a band crossing.
## Called from the site scan (server, ~1 Hz) with the elapsed seconds since the
## last pass, so recovery is correct however the scan is spaced. Rising is an
## EVENT (`_on_creature_perished`); only the slow recovery is time-driven.
func _tick_ecology(elapsed: float) -> void:
	if not Tunables.get_bool("eco_enabled"):
		return
	var recover := Tunables.get_num("eco_recover_per_min") / 60.0 * elapsed
	if recover > 0.0 and kraken_ascendancy > 0.0:
		kraken_ascendancy = maxf(0.0, kraken_ascendancy - recover)
	_announce_eco()


## Announce a band crossing once, up or down. The message names the CONSEQUENCE
## (krakens), not the meter, because the meter is an engineering detail and the
## krakens are the thing the player feels.
func _announce_eco() -> void:
	var lvl := _eco_level_of(kraken_ascendancy)
	if lvl == _eco_level:
		return
	var rising := lvl > _eco_level
	_eco_level = lvl
	if rising:
		match lvl:
			1: _notify("The deep stirs — krakens grow bolder.")
			2: _notify("The krakens are rising — the deep is spilling upward.")
			3: _notify("The krakens are ASCENDANT — you have hunted the whales too hard.")
	else:
		match lvl:
			2: _notify("The deep settles a little — the whales are recovering.")
			1: _notify("The krakens recede as the whale grounds refill.")
			0: _notify("The deep is quiet again. The whales have come back.")


## A whale-family body just died: let the deep off its leash a notch. Wired once
## per creature in `_whale_ai_for` (the one place every brain is set up), server-
## side like all spawning. A non-whale death is ignored.
func _on_creature_perished(kind: String) -> void:
	# THE DIVE pays coins for ANY creature death (the ecology below cares only
	# about whales) — the mode's whole economy is "kill things on the way down".
	_dive_credit_kill(kind)
	if not Tunables.get_bool("eco_enabled") or not WHALE_KINDS.has(kind):
		return
	kraken_ascendancy = clampf(
		kraken_ascendancy + Tunables.get_num("eco_kill_rise"), 0.0, 1.0)
	_announce_eco()


## A kraken den's EFFECTIVE pool under the current ascendancy: its base pool grows
## by up to `eco_kraken_gain`× as the meter climbs, so an ascendant deep fields
## whole extra krakens per den, everywhere at once (the global creep). The global
## resident cap (`site_max_residents`) still bounds the world total — an ascendant
## deep therefore CROWDS the awake budget with krakens rather than growing it
## without limit. Non-kraken sites are unchanged.
func _kraken_surge_pool(kind: int, base_pool: int) -> int:
	if kind != SpawnSites.Kind.KRAKEN_DEN or not Tunables.get_bool("eco_enabled"):
		return base_pool
	var gain := Tunables.get_num("eco_kraken_gain")
	return base_pool + int(round(base_pool * gain * kraken_ascendancy))


## Re-sync the narration band to the current meter WITHOUT announcing — a load
## restores `kraken_ascendancy` directly, and the player should not be told the
## deep "stirred" the instant they open a save.
func resync_eco_level() -> void:
	_eco_level = _eco_level_of(kraken_ascendancy)


## Debug: shove the meter up (F2 → Spawn), so the surge is playtestable without
## hunting a pod first. Authority-only, clamped like every other write.
func debug_stir_deep(amount: float) -> void:
	if Net.is_online() and not Net.is_server():
		return
	kraken_ascendancy = clampf(kraken_ascendancy + amount, 0.0, 1.0)
	_announce_eco()


## One site's pass: recover what it grew while unwatched, forget residents that
## have died, and release one more if it is owed one.
## Returns whether it released a resident this pass.
func _tick_site(site: Dictionary, points: Array, radius: float,
		may_release: bool) -> bool:
	var coord: Vector2i = site["coord"]
	# THE SURGE (ecology): a kraken den fields more, faster, as the deep grows
	# ascendant — everywhere at once, so overhunting whales anywhere makes every
	# den in the world tougher. Non-kraken sites pass through unchanged.
	var pool: int = _kraken_surge_pool(site["kind"], int(site["pool"]))
	var st: Dictionary = _site_state.get(coord, {
		"stock": pool, "pool": pool, "residents": [], "next_release": 0.0,
		"seen_at": _site_clock})

	# REGEN. Whole units only, with the remainder carried, so stock recovers at
	# exactly one per regen interval however the visits are spaced.
	var regen := maxf(1.0, Tunables.get_num("site_regen_seconds"))
	var away: float = _site_clock - float(st["seen_at"])
	var gained := int(away / regen)
	if gained > 0:
		st["stock"] = mini(pool, int(st["stock"]) + gained)
		st["seen_at"] = float(st["seen_at"]) + gained * regen
	if int(st["stock"]) >= pool:
		st["seen_at"] = _site_clock  # full: nothing to carry

	# Residents that no longer exist are no longer this site's problem. Stock is
	# NOT returned here — a killed resident stays killed until the site regrows
	# it, which is what makes clearing a nest mean something.
	var live: Array = []
	for id in st["residents"]:
		var body := instance_from_id(int(id))
		if body != null and is_instance_valid(body) and (body as Node).is_inside_tree():
			live.append(id)
	st["residents"] = live

	var d := Dormancy.distance_to_nearest(site["pos"] as Vector2, points)

	# THE NEST (charter §4's second half: "destroying the nest structure clears
	# it for good"). Some places have a structure — a roost, a den, a hive — and
	# breaking half of it ends the place permanently. A whale ground has none:
	# it is open sky on a migration route, and there is nothing there to break.
	var nest := instance_from_id(int(st.get("nest", 0))) as Ship
	if nest != null and not is_instance_valid(nest):
		nest = null
	# Broken = less than half the body it was RAISED with. Measured against the
	# count stored when it was built, not against its blueprint: `remove_block`
	# (the deconstruct key) edits the blueprint as it goes, so a nest taken
	# apart by hand would shrink both sides of that comparison and never read as
	# broken. Shot apart or dismantled, half is half.
	var raised: int = int(st.get("nest_cells", 0))
	if raised <= 0 and nest != null:
		raised = nest.blueprint_map().size()
	# BROKEN is the pool running out — or, for a nest with no pool (a legacy
	# one, or a kind that never had one), half the body it was raised with.
	var spent := nest != null and nest.shared_health_max > 0.0 		and nest.shared_health <= 0.0
	if nest != null and (spent or nest.blocks.size() * 2 < raised):
		st["cleared"] = true
		st["stock"] = 0
		_notify("%s broken — nothing more will come from here"
			% SpawnSites.kind_name(site["kind"]).capitalize())
		_award_nest_cache(site, nest.global_position)
		nest.is_nest = false      # a wreck now: reclaimable like anything else
		nest.from_spawn_site = true
		st["nest"] = 0
		nest = null
	var cleared: bool = bool(st.get("cleared", false))
	if nest == null and not cleared and d >= 0.0 and d <= radius:
		var path := SpawnSites.nest_for(site["kind"])
		if path != "":
			var built := _build_nest(site, path)
			if built != null:
				st["nest"] = built.get_instance_id()
				st["nest_cells"] = built.blocks.size()

	var released := false
	if cleared:
		_site_state[coord] = st
		return false   # a cleared place gives nothing, ever again
	if may_release and d >= 0.0 and d <= radius and live.size() < pool \
			and int(st["stock"]) > 0 and _site_clock >= float(st["next_release"]):
		var body := _release_resident(site, live.size())
		if body != null:
			st["stock"] = int(st["stock"]) - 1
			st["next_release"] = _site_clock \
				+ maxf(0.0, Tunables.get_num("site_release_seconds"))
			live.append(body.get_instance_id())
			released = true
	_site_state[coord] = st
	return released


## Put one resident of the site's kind into the world. Reuses the same spawn
## paths the arena and the debug window use, so a site resident is an ordinary,
## correctly-collidered, correctly-crewed body from the instant it appears.
func _release_resident(site: Dictionary, index: int) -> Ship:
	var pos := SpawnSites.resident_pos(site, index, world_seed, float(world_scale))
	var body: Ship = null
	match site["kind"]:
		SpawnSites.Kind.WHALE_GROUND:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([world_seed, site["coord"], index])
			body = _spawn_one_whale(WhaleSpawn.pick_plan(rng), pos)
		SpawnSites.Kind.CRITTER_MEADOW:
			body = _spawn_one_critter(pos)
		SpawnSites.Kind.BANDIT_ROOST:
			body = _spawn_hulk_at(pos)
		SpawnSites.Kind.BASILISK_EYRIE:
			body = _spawn_one_basilisk(pos)
		SpawnSites.Kind.KRAKEN_DEN:
			body = _spawn_one_kraken(
				KRAKEN_PLANS[index % KRAKEN_PLANS.size()], pos)
	if body != null:
		# Same reasoning as the nest: residency decides whether the world may
		# later RECLAIM this body, so it has to survive a rehome or a load. It
		# rides `to_payload` for those; the assignment here is what the local
		# spawn needs, since the creature helpers do not take payload extras.
		body.spawn_site = site["coord"]
		body.from_spawn_site = true
	return body


## Pay out a broken nest's cache, once. Charter §4 wants clearing a place to
## MEAN something, and safety alone is a thin reward for a fight — so the wreck
## spills goods that already exist in the economy (no new item ids while the
## item budget is still an open owner question).
##
## Awarded to the local player, like every other pickup today; a networked
## "whoever broke it" is the same seam harvesting already has.
func _award_nest_cache(site: Dictionary, at: Vector2) -> void:
	if player == null or not is_instance_valid(player) or player.inventory == null:
		return
	var cache: Array = SpawnSites.nest_cache(site["kind"])
	var i := 0
	while i + 1 < cache.size():
		var item: int = cache[i]
		var n: int = cache[i + 1]
		player.inventory.add(item, n)
		if _pickups != null:
			_pickups.add(at + Vector2(0.0, -60.0 * i * world_scale),
				"+%d %s" % [n, ItemDB.name_of(item)], float(world_scale))
		i += 2


## Raise a site's structure. FROZEN: a nest hangs where it was built rather
## than flying or falling, so its gasbags read as what holds it up instead of
## lift the physics has to balance. It is a real Ship otherwise — shot apart
## block by block, severable, and it shows on the map like anything else.
func _build_nest(site: Dictionary, path: String) -> Ship:
	var cells := ShipLayout.upscale_cells(ShipLayout.load_cells(path), world_scale)
	if cells.is_empty():
		return null
	var pos := WhaleSpawn.clear_spawn_pos(terrain, site["pos"] as Vector2,
		WhaleSpawn.footprint_of(cells), float(world_scale))
	# Nest-hood rides the PAYLOAD, not a post-spawn assignment: `is_nest` is
	# what makes the receiver freeze it, and a post-spawn field exists on the
	# server only — so a client saw the structure of a site tumbling out of the
	# sky (net_smoke caught it, 2026-08-26).
	var coord: Vector2i = site["coord"]
	# ONE UNIT UNTIL IT BREAKS. The pool rides the payload alongside nest-hood
	# (both are `shared`/`shared_max`, which the wire and the save already
	# carry), so a client and a reloaded world agree on how much fight is left
	# in a place.
	var pool := SpawnSites.nest_pool(site["kind"])
	var nest := fleet.spawn_ship_from_cells(cells, pos, 0, 0.0, float(world_scale),
		SpawnSites.nest_faction(site["kind"]),
		{"is_nest": true, "site_x": coord.x, "site_y": coord.y,
			"shared": pool, "shared_max": pool})
	if nest == null:
		return null
	nest.freeze = true
	nest.rebuild()   # pool-then-rebuild, the same ordering every creature needs
	return nest


## Free wild residents that have ended up far from everyone, returning their
## stock to the site that made them. Never touches something the player has a
## relationship with: a tamed creature, a carcass (that is loot the player
## left), or anything still awake.
func _reclaim_far_residents(points: Array) -> void:
	var limit := Tunables.get_num("site_reclaim_px")  # raw px, as above
	for ship in fleet.ships():
		if not is_instance_valid(ship) or not ship.from_spawn_site:
			continue
		if ship.is_nest:
			continue  # a nest IS the place — it is never carried off
		if not ship.dormant:
			continue
		if ship.faction == 0 or ship.is_carcass():
			continue  # tamed, captured, or a corpse someone may come back for
		if Dormancy.distance_to_nearest(ship.global_position, points) <= limit:
			continue
		# The stock goes back: this resident was never killed, only carried
		# out of the world's reach, and a site the player merely flew past
		# must not end up permanently thinned.
		var st: Variant = _site_state.get(ship.spawn_site)
		if st != null:
			var d: Dictionary = st
			d["stock"] = mini(int(d.get("pool", 1)), int(d["stock"]) + 1)
			_site_state[ship.spawn_site] = d
		ship.queue_free()


## Every site the player has been near, for the map. The state dictionary IS the
## discovery record — an entry exists exactly because a pass found the site
## within activation range of a focus.
func discovered_sites() -> Array:
	var out: Array = []
	if _world_rect.size.y <= 0.0:
		return out
	for coord in _site_state:
		var site := SpawnSites.site_at(coord, world_seed, _world_rect,
			float(world_scale))
		if not site.is_empty():
			site["cleared"] = bool((_site_state[coord] as Dictionary).get(
				"cleared", false))
			out.append(site)
	return out


## The sites the player has BROKEN, as flat [x, y, ...] ints — the one piece of
## site state worth carrying in a save. Everything else about a site is derived
## from the seed, but "I cleared this nest" is a thing the player DID, and a
## world that forgot it would erase the only permanent mark they can leave on
## the population.
func cleared_sites() -> PackedInt32Array:
	var out := PackedInt32Array()
	for coord in _site_state:
		if bool((_site_state[coord] as Dictionary).get("cleared", false)):
			out.append((coord as Vector2i).x)
			out.append((coord as Vector2i).y)
	return out


## Restore them on load.
func set_cleared_sites(flat: PackedInt32Array) -> void:
	var i := 0
	while i + 1 < flat.size():
		var coord := Vector2i(flat[i], flat[i + 1])
		var st: Dictionary = _site_state.get(coord, {
			"stock": 0, "pool": 0, "residents": [], "next_release": 0.0,
			"seen_at": _site_clock})
		st["cleared"] = true
		st["stock"] = 0
		_site_state[coord] = st
		i += 2


## The player as BITEABLE prey: their body when they are standing in the open,
## null when there is nobody or they are PILOTING. A pilot rides inside the hull,
## and that hull is already what the mouth is chewing — billing the same grab to
## both would eat them straight through the deck.
func _on_foot_player() -> Node2D:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return null
	return player


## The WhaleAI for `creature`, created (and its provoke wired to the creature's
## `damaged` signal) the first time it is asked for. One place so the swim loop,
## the taming path and the ride path all share the same brain per creature.
func _whale_ai_for(creature: Ship) -> WhaleAI:
	var id := creature.get_instance_id()
	if not _whale_ais.has(id):
		# A kraken gets the two-ended KrakenAI (mouth grab + shell-tip ram); every
		# other faction-2 creature (whale, critter) gets the plain WhaleAI. Both
		# are WhaleAI, so the swim loop / taming / riding paths are identical.
		var ai: WhaleAI
		match creature.creature_kind:
			"kraken":
				ai = KrakenAI.new()      # two-ended deep hunter: ram + mouth grab
			"basilisk":
				ai = BasiliskAI.new()    # stands off and spits fire
			_:
				ai = WhaleAI.new()       # whale, critter: roam and ram
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
		# The ecology hook: a whale-family death lets the deep off its leash. Wired
		# here because this is the one place every creature's brain is set up — and
		# a creature being simulated enough to be KILLED already has one.
		creature.creature_perished.connect(_on_creature_perished)
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


## One basilisk fireball, from `beast` toward `at`. It is the SAME slug the sky
## already throws — meteors and lava bombs are HazardFireball too — so it
## damages through the same path, digs ground through the same seam, and rolls
## to set what it hits alight through the same rule. A creature that invented
## its own projectile would be a second physics model to keep honest.
func _spit_fire(beast: Ship, at: Vector2) -> HazardFireball:
	var speed := Tunables.get_num("basilisk_spit_speed") * world_scale
	var g := 980.0 * world_scale * 0.25
	var centre := beast.global_position
	# Lofted, not flat: the slug arcs, so a basilisk's fire has to be READ and
	# dodged rather than merely out-ranged. Same first-order compensation every
	# gunner in this game uses.
	var t := centre.distance_to(at) / maxf(speed, 1.0)
	var lead := at + Vector2.UP * 0.5 * g * t * t
	var dir := (lead - centre).normalized()
	if dir == Vector2.ZERO:
		return null
	# THE MUZZLE IS ALONG THE LINE OF FIRE, clear of the beast's own body.
	# Placing it on the "facing" side instead let a slug fired at something
	# above or below cross straight back through the shooter — and a living
	# creature absorbs that into its shared pool without losing a cell, so the
	# symptom was "the shots miss" plus a basilisk mysteriously setting ITSELF
	# on fire. (tools/threat_probe.gd, twice.)
	var radius := beast.solid_bounds.size.length() * 0.5 + Ship.CELL * world_scale
	var fb := HazardFireball.new()
	fb.kind = HazardFireball.Kind.LAVA   # the arcing, glowing one
	fb.position = centre + dir * radius
	fb.gravity = g
	fb.velocity = dir * speed
	fb.damage = Tunables.get_num("basilisk_spit_damage")
	fb.terrain = terrain
	fb.visual_scale = float(world_scale)
	add_child(fb)
	return fb


## Try to tame `creature` NOW (the testable gate). Refuses a non-creature, a
## carcass, or — the LORE gate — a player without Beast Whisperer. On success
## the allegiance flips to the player and the WhaleAI turns ally. Returns
## whether it was tamed. (Break-the-fix: drop the taming_enabled check and the
## "refused without the perk" test fails.)
func try_tame(creature: Ship) -> bool:
	if creature == null or not is_instance_valid(creature) \
			or creature.faction != 2 or creature.is_carcass():
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
	# Otherwise this must be a WILD, tameable creature to bond with. (Krakens
	# qualify since 2026-08-24 — tame_level 3, Master Trader — they just stay
	# wild-mannered and their mouth still bites; see KrakenAI.)
	if creature.faction != 2:
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
		Tunables.get_int("whale_mine_breadth") * terrain.subdiv,
		creature.rotation)
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

# --- Propeller wash on BODIES (owner survey 2026-08-18) ---------------------
#
# "Just past a propeller's facing direction there is finnickiness — props
# pull/push nearby things and CHOP THEM UP." Shells and hazard slugs already
# sample `Ship.wash_accel_at`; this is the half that reaches things with mass.
#
# Two effects, deliberately different in reach:
#   * PUSH, the whole length of the jet. A running propeller shoves creatures,
#     hulls and people. It is the same acceleration the projectiles feel,
#     applied as a force, so a light critter is thrown and a whale barely
#     notices — which is the mass doing the work, not a table of exceptions.
#   * CHOP, only the near third. Standing in the draught is weather; standing
#     in the BLADES is an injury. It bites creatures and people, never hulls:
#     a ship shredding its own structure with its own propellers is the
#     "far too easy to damage your own ship" clunk the playtest complained of.
#
# Cost: only ships whose props are actually turning emit, and each emitter
# tests a handful of bodies with a distance early-out. A fleet of twenty is a
# few hundred cheap checks a frame, and a fleet with no throttle open is none.

## How far into the jet the blades reach, as a fraction of its length.
const WASH_CHOP_FRAC := 0.34


## Does a prop wash CHOP a body, given the two sides? (owner 2026-08-26: "should
## it bite your own crew?" — no.) The blades spare your own side; a tamed
## creature is faction 0, the player's side, so this covers allies too. Push is
## unaffected — shoving is physics, not friendly fire. `wash_chop_friendly`
## (default off) turns everyone-bleeds back on. One place, so the two chop sites
## and the test cannot drift.
func _wash_chops(emitter_faction: int, victim_faction: int) -> bool:
	return emitter_faction != victim_faction 		or Tunables.get_bool("wash_chop_friendly")


func _apply_prop_wash(delta: float) -> void:
	if not Net.is_server() or fleet == null or not is_instance_valid(fleet):
		return
	var push_mult := Tunables.get_num("wash_push_mult")
	var chop_dps := Tunables.get_num("wash_chop_dps")
	if push_mult <= 0.0 and chop_dps <= 0.0:
		return
	var ships: Array = fleet.ships()
	var reach := Ship.WASH_RANGE_CELLS * Ship.CELL * world_scale * 1.5
	for emitter in ships:
		if not is_instance_valid(emitter) or emitter.dormant:
			continue
		if emitter.wash_accel_at(emitter.global_position + Vector2(0.0, 1.0)) 				== Vector2.ZERO and not emitter.has_running_props():
			continue
		# Other bodies in the draught.
		for body in ships:
			if body == emitter or not is_instance_valid(body) or body.dormant:
				continue
			if body.global_position.distance_to(emitter.global_position) > reach 					+ body.solid_bounds.size.length():
				continue
			var a: Vector2 = emitter.wash_accel_at(body.global_position)
			if a == Vector2.ZERO:
				continue
			if push_mult > 0.0:
				body.apply_central_force(a * push_mult * body.mass)
			# The CHOP spares your own side (see _wash_chops); the PUSH above is
			# universal.
			if chop_dps > 0.0 and _wash_chops(emitter.faction, body.faction) 					and body.shared_health_max > 0.0 					and body.shared_health > 0.0 					and emitter.is_in_near_wash(body.global_position, WASH_CHOP_FRAC):
				# A living creature only: a hull is not chopped by a fan, and a
				# carcass in the blades is already salvage.
				body.net_damage_cell(body.cell_at_global(body.global_position),
					chop_dps * delta)
		# And the person standing in it. Your OWN ship's blades do not chop you
		# (emitter.faction 0 == the player's side); a stranger's still do,
		# unless wash_chop_friendly turns friendly fire back on.
		if player != null and is_instance_valid(player) and not player.is_piloting():
			var pa: Vector2 = emitter.wash_accel_at(player.global_position)
			if pa != Vector2.ZERO:
				if push_mult > 0.0:
					player.velocity += pa * push_mult * delta
				if chop_dps > 0.0 and _wash_chops(emitter.faction, 0) 						and emitter.is_in_near_wash(
						player.global_position, WASH_CHOP_FRAC):
					player.take_damage(chop_dps * delta)


# --- Fire (roadmap Phase 4; combat/fire.gd) ---------------------------------
#
# The source's fire was its main threat multiplier and its buggiest system, so
# ours is a grid BLOCK-STATE: a dictionary of burning cells on the Ship, ticked
# here on a slow cadence. Never a node, never a particle, never a body.
#
# The cadence matters. Fire is a fight the player is supposed to be able to
# win, so it has to be legible: five steps a second is fast enough that a
# spreading fire reads as alive and slow enough that a hull's worth of burning
# cells is a handful of damage calls per second rather than hundreds. Damage
# goes through net_damage_cell — the shot path — so a burning ship uses the
# incremental combat machinery instead of rebuilding once per burning cell.

const FIRE_STEP_SECONDS := 0.2
var _fire_t := 0.0
var _fire_clock := 0.0
var _fire_rng := RandomNumberGenerator.new()

## Repair stations mend on a SLOW clock (8 Hz), not per frame — repair is
## deliberately unhurried, and a per-frame blueprint scan on every running ship
## is waste. Authority only (Net.is_server, like fire); each ship's tick_menders
## self-gates on menders_running/repair_cells, so an idle sky costs one loop.
const MENDER_TICK := 0.125
var _mender_clock := 0.0


func _update_menders(delta: float) -> void:
	if not Net.is_server() or fleet == null or not is_instance_valid(fleet):
		return
	_mender_clock += delta
	if _mender_clock < MENDER_TICK:
		return
	var dt := _mender_clock
	_mender_clock = 0.0
	for ship in fleet.ships():
		if is_instance_valid(ship) and ship.menders_running:
			ship.tick_menders(dt)


func _update_fires(delta: float) -> void:
	if not Net.is_server() or fleet == null or not is_instance_valid(fleet):
		return
	if not Tunables.get_bool("fire_enabled"):
		return
	_fire_t += delta
	if _fire_t < FIRE_STEP_SECONDS:
		return
	var dt := _fire_t
	_fire_t = 0.0
	_fire_clock += dt
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.burning.is_empty():
			continue
		if ship.dormant:
			continue  # out of the simulation: its fire waits with it
		var scaled := dt * Tunables.get_num("fire_rate_scale")
		Fire.step(ship, scaled, _fire_clock, _fire_rng)
		# ...and it can cross to a body it is TOUCHING (a burning wreck against
		# your hull). Contact only, and much rarer than the cell-to-cell spread.
		Fire.jump_between(ship, scaled, _fire_clock, _fire_rng)


## Try to set a cell alight — the one entry point every ignition source uses
## (hazard strikes, the debug button, and eventually incendiary weapons), so
## the "does it catch?" rule lives in exactly one place.
func ignite_cell(ship: Ship, cell: Vector2i) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if not Tunables.get_bool("fire_enabled"):
		return false
	return Fire.ignite(ship, cell, _fire_clock)


## A hazard strike (meteor, lava bomb) may set what it hit alight. Rolled here
## rather than in the fireball so the chance is one tunable in one place, and
## so a hull that simply cannot burn silently declines.
func hazard_ignite(ship: Ship, cell: Vector2i) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if randf() > Tunables.get_num("fire_ignite_chance"):
		return false
	if ignite_cell(ship, cell):
		return true
	# THE STRUCK CELL IS USUALLY GONE. A hazard damages before it ignites, and
	# a slug that punches through leaves nothing at the point of impact to set
	# alight — so the roll succeeded and nothing burned. (Found by
	# tools/threat_probe.gd walking the whole basilisk → strike → fire chain:
	# eleven hits, ignite chance 1.0, zero fires.) A hole should light its own
	# EDGE, which is both what a fireball does and what makes the hazard→fire
	# link reliable instead of a coin flip.
	for d in Fire.NEIGHBOURS:
		if ignite_cell(ship, cell + d):
			return true
	return false


## Every burning cell near the camera, as world points — what the fire overlay
## draws. Nothing else reads it; a cell that is on fire is not a node, so this
## is the only way to see one.
func burning_points(limit := 400) -> Array:
	var out: Array = []
	if fleet == null or not is_instance_valid(fleet):
		return out
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.burning.is_empty() or ship.dormant:
			continue
		for cell in ship.burning:
			out.append(ship.to_global(ship.local_pos_of(cell)))
			if out.size() >= limit:
				return out
	return out


## Debug: set the nearest burnable ship cell to `at` alight (F2 → Spawn).
func debug_ignite(at: Vector2) -> bool:
	var best: Ship = null
	var best_d := INF
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.blocks.is_empty():
			continue
		var d := ship.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = ship
	if best == null:
		return false
	var cell := best.cell_at_global(at)
	if not best.blocks.has(cell):
		# Nothing under the cursor: light whatever of it burns, so the button
		# always does something visible.
		for c in best.blocks:
			if Fire.burns(int(best.blocks[c]["type"])):
				cell = c
				break
	return ignite_cell(best, cell)


func _update_hazards(delta: float) -> void:
	if _hazards == null:
		return
	if Net.is_online() and not Net.is_server():
		return
	# METEORS DO NOT MINE IN A RUN (owner 2026-08-30: "meteor thingies should
	# NOT mine anything during dive mode"). A fireball digs only when it HAS a
	# terrain reference — `HazardFireball.terrain` is documented nullable for
	# exactly this — so dropping it in a run leaves the meteors falling and still
	# dangerous to a hull, while the landings you are trying to stand on stop
	# being chewed out from under you.
	_hazards.terrain = null if dive_style() else terrain
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
	# SANDBOX: the deep-air gate is one of the "fluff" gates the sandbox toggle
	# removes, so you can go anywhere and play the thing without hunting copper for
	# an Aether Lung first (owner 2026-08-28). The full game keeps the gate.
	if Tunables.get_bool("sandbox_mode"):
		_suffocate_cd = 0.0
		return
	_suffocate_cd = LifeSupport.tick(player, _player_altitude_frac(), delta, _suffocate_cd)
	# THE DEEP AIR DOES NOT KILL YOU IN A RUN (owner 2026-08-30: "the player
	# should be able to survive the nasty air during dive mode"). It still HURTS
	# — it drains you to a sliver and holds you there, so diving past the line
	# without an Aether Lung leaves you one kraken away from the ledger — but the
	# air itself can no longer be the thing that ends a run. That keeps the Lung
	# worth its 220 coins without making the gate a wall you die against.
	if dive != null and dive.outcome == "":
		player.health = maxf(player.health, player.max_health * DIVE_AIR_FLOOR)


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
		# A balloon bursting is a moment: one loud float at the bulb, since the
		# lift it was holding vanishes the same frame.
		ship.balloon_popped.connect(_on_balloon_popped)


## A tethered balloon BURST (Ship.balloon_popped): float a cue at the bulb. The
## lift is already gone (the pop rebuilds the body), so this is the read on why
## the airship just sagged.
func _on_balloon_popped(at: Vector2, size: int) -> void:
	if _pickups != null:
		_pickups.add(at, "%s balloon POPPED" % _balloon_size_name(size).capitalize(),
			float(world_scale))


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
	if _dive_perish():
		return
	# Dying with a deck under you costs part of the pot, and the third one ends
	# the run — without the cap, unbreathable air at depth 6 is a place you die
	# in forever (the headless playtest found exactly that).
	if dive != null and dive.outcome == "" and dive.committed:
		if dive.perish_aboard():
			_notify(DiveRun.outcome_line(dive.ledger()))
			return
		_notify("You went down. %d of %d — and it cost you coin."
			% [dive.deaths, DiveRun.DEATH_LIMIT])
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


## Minimum speed at which a hull reads as UNDER WAY to a lookout — unscaled
## px/s, x world_scale like every other world distance. A ship under power
## crosses this in the first second; a derelict shoved by wind or a bump does
## not hold it.
const UNDER_WAY_SPEED := 40.0


## DOES THIS HULL READ AS CREWED? (owner 2026-08-26: "enemies shouldn't randomly
## aggress to a ship unless it's moving + manned — why would they attack
## something that doesn't look like is even manned?")
##
## A bandit is a person with eyes, not a trigger on a proximity switch. What a
## person can SEE from another deck is: somebody aboard, or a hull that is going
## somewhere — and a ship that is going somewhere must have a hand on it, which
## is why movement counts as EVIDENCE of a crew rather than a second condition
## to satisfy. An empty hull parked in the sky is scenery, and scenery does not
## get shot at.
##
## Not a pacifism switch: shooting a bandit still provokes it (PROVOKED_SECONDS,
## `_on_hostile_ship_damaged`) and a provoked crew hunts whatever hurt it,
## parked or not — see the provoked branch in _enemy_fire.
func _looks_crewed(ship: Ship) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.linear_velocity.length() > UNDER_WAY_SPEED * world_scale:
		return true          # under way — somebody has a hand on it
	if player != null and is_instance_valid(player):
		if player.piloting == ship or player.riding == ship:
			return true      # at the helm, or on its back
		if FrameCensus.body_rect(ship).has_point(player.global_position):
			return true      # a person standing on the deck is visible
	for npc in _npcs:
		if is_instance_valid(npc) and npc.ship == ship:
			return true      # crewed by somebody who is not you
	return false


## The nearest ship of `faction`. `crewed_only` applies the lookout's test
## above — a hostile choosing a victim uses it; a PROVOKED one does not, since
## it already knows who shot at it.
## Has this hostile crew been shot at recently? The one place the provocation
## clock is read, so the guns and the helm can never disagree about it.
func _is_provoked(id: int) -> bool:
	var since: float = _enemy_provoked_at.get(id, -1.0e12)
	return Time.get_ticks_msec() < since + PROVOKED_SECONDS * 1000.0


func _nearest_ship_of_faction(from: Ship, faction: int,
		crewed_only := false) -> Ship:
	var best: Ship = null
	var best_d := INF
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship == from or ship.faction != faction:
			continue
		if crewed_only and not _looks_crewed(ship):
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
#
# THE PER-SYSTEM STOPWATCH (owner capture, 2026-08-26). The world's physics
# tick is a fixed sequence of systems, and the second 3-FPS capture proved the
# frame was NOT the solver — `pairs=4 shapes=45` is an empty physics world —
# which leaves our own script inside the physics frame as the thing to measure.
# So the sequence lives in ONE named list instead of a flat call block, and
# while the F3 diagnostic is recording each entry is timed into `_sys_ms`.
#
# The list is built once (no per-tick allocation) and the untimed path is a
# plain loop of `Callable.call` — about 20 calls per tick, microseconds — so
# normal play pays nothing measurable for the ability to answer this question
# the next time it is asked. Order is behaviour: it is the order the flat block
# ran in, and it must stay that way.

## [name, Callable(delta)] in tick order. Built in _ready.
var _systems: Array = []
## name -> ms accumulated since the last take_system_ms(). Only written while
## the F3 diagnostic is recording.
var _sys_ms := {}
var _sys_timing := false
## Probes (tools/tick_probe.gd) turn the stopwatch on WITHOUT starting a
## recording, so measuring the tick never overwrites the owner's capture file.
var sys_timing_forced := false


func _build_systems() -> void:
	_systems = [
		["local", func(_d: float) -> void:
			_refresh_local_ship()
			_refresh_local_player()],
		["terrain", func(_d: float) -> void: _stream_terrain()],
		["discovery", func(_d: float) -> void: _update_discovery()],
		["collisions", func(_d: float) -> void: _watch_collisions()],
		["death", func(_d: float) -> void: _watch_player_death()],
		["damagenums", func(d: float) -> void:
			if _damage_numbers != null:
				_damage_numbers.update(d)],
		["enemyfire", func(d: float) -> void: _enemy_fire(d)],
		["enemypilot", func(d: float) -> void: _enemy_pilot(d)],
		["swim", func(d: float) -> void: _creature_swim(d)],
		["dormancy", func(d: float) -> void: _update_dormancy(d)],
		["sites", func(d: float) -> void: _update_spawn_sites(d)],
		["taming", func(d: float) -> void: _handle_taming(d)],
		["riding", func(d: float) -> void: _handle_riding(d)],
		["ridemine", func(d: float) -> void: _handle_ridden_mining(d)],
		["wash", func(d: float) -> void: _apply_prop_wash(d)],
		["fire", func(d: float) -> void: _update_fires(d)],
		["menders", func(d: float) -> void: _update_menders(d)],
		["hazards", func(d: float) -> void: _update_hazards(d)],
		["suffocation", func(d: float) -> void: _update_suffocation(d)],
		["lava", func(d: float) -> void: _update_lava_core(d)],
		["dive", func(d: float) -> void: _tick_dive(d)],
	]


func _step_systems(delta: float) -> void:
	if not _sys_timing:
		for e in _systems:
			(e[1] as Callable).call(delta)
		return
	for e in _systems:
		var t0 := Time.get_ticks_usec()
		(e[1] as Callable).call(delta)
		var ms := float(Time.get_ticks_usec() - t0) * 0.001
		_sys_ms[e[0]] = float(_sys_ms.get(e[0], 0.0)) + ms


## The accumulated per-system milliseconds, and RESET — the diagnostic calls
## this on its window boundary, so each SYS line covers exactly one window.
func take_system_ms() -> Dictionary:
	var out := _sys_ms.duplicate()
	_sys_ms.clear()
	return out


func _physics_process(delta: float) -> void:
	var recording: bool = _whale_diag != null and _whale_diag.enabled
	_sys_timing = sys_timing_forced or recording
	_step_systems(delta)

	# Whale/collision diagnostic: one row per whale per frame while ON. Gated
	# on a single bool so it costs nothing in normal play (see whale_diag.gd).
	if _sys_timing:
		# The live-Shot population is the swarm the old whale-only log was blind
		# to; the group lookup runs ONLY while recording (see whale_diag.gd).
		_whale_diag.world = self  # for the SUM's physics census (cheap, idempotent)
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

	# Falling out of the world normally respawns you. On a LOST dive it must not:
	# the body dropping through the haze is the run-over screen the ledger is
	# written over (owner: "do you just fall until you die and that's that?").
	if player != null and player.global_position.y > WORLD_BOTTOM and not dive_over():
		if not _dive_perish():
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
	# The run-over ledger eats the next key, whatever it is — the same "any key"
	# idiom as the boot chooser, and it must not also fire that key's verb.
	if dive_over():
		dismiss_dive_ledger()
		get_viewport().set_input_as_handled()
		return
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
	# On the web build the browser owns the F-row before the canvas sees it — F5
	# reloaded the page instead of quicksaving. Fold a browser-safe alias back
	# onto its F-key here (maps/world/web_keys.gd), so on web BOTH reach the same
	# toggle and on desktop this is the identity.
	keycode = WebKeys.unalias(keycode)
	match keycode:
		KEY_F1:
			_toggle_help()
		KEY_TAB:
			_toggle_map()
		KEY_K:
			_toggle_character_sheet()
		KEY_F:
			_cycle_eng_overlay()
		KEY_F2:
			_toggle_debug_window()
		KEY_F3:
			_toggle_whale_diag()
		KEY_F5:
			# A run you can quicksave in front of the Leviathan is not a run.
			if not _refuse_in_run("Not in a run — the ledger is the only record."):
				save_game()
		KEY_F9:
			if not _refuse_in_run("Not in a run — the ledger is the only record."):
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
	# B -- TAP cycles, HOLD opens the picker (owner 2026-08-26). Both place what
	# Q places; the weapon is never in here (LMB shoots unconditionally). Before
	# the no-ship return, so the palette works on foot in an empty sky too.
	_update_build_picker()
	_handle_crafting()
	# Handled before anything else, so they still work when the rest is broken.
	# ESCAPE NO LONGER QUITS WHERE YOU STAND (owner 2026-08-30). It was the one
	# keypress that could throw away ten minutes of a run by accident, with no
	# confirmation and no way back. It opens the menu instead — same key, same
	# verb, one step less abrupt.
	# ...and ONLY to OPEN it. Closing is the panel's own `_input`, which marks the
	# event handled — but `Input.is_action_just_pressed` does not care about
	# handled events, so this line ran on the same press and toggled it straight
	# back open. Owner: *"hitting escape again mid-game does NOT unpause"*. It
	# was closing and reopening in one frame.
	if Input.is_action_just_pressed("quit_game"):
		if _pause_menu != null and is_instance_valid(_pause_menu) 				and not _pause_menu.visible:
			_pause_menu.open()
		return
	# THE SESSION VERBS ARE NOT RUN VERBS (owner 2026-08-30: "the keybindings
	# from the regular game are still active during the dive — you can hit T to
	# teleport way down (and your ship is still there!)"). R rebuilds the world,
	# T teleports you to the world's original spawn, and both of them walk
	# straight through a run: R deletes it, T abandons your hull at depth 1 and
	# drops your body a hundred thousand pixels away, for free. In a run they are
	# refused out loud rather than silently — a dead key reads as a bug.
	if Input.is_action_just_pressed("reset_world"):
		if not _refuse_in_run("Not in a run — climb out or go down."):
			reset_world()
		return
	if Input.is_action_just_pressed("respawn_player"):
		if not _refuse_in_run("Not in a run — you go where you fly."):
			respawn_player()

	# INTERACT RUNS UNCONDITIONALLY (owner 2026-08-25, the stranded corpse
	# pilot): this used to sit below the no-ship gate, so losing local_ship
	# (starter cannibalized for parts, eaten, melted) while PILOTING a built
	# corpse killed the E key entirely — the pilot could never step off. The
	# one reliable use key stays alive in every state.
	_handle_interact()

	# LOSING YOUR SHIP IS NOT LOSING YOUR HANDS (owner 2026-08-26: "controls
	# just seem to hang when the player's ship is destroyed or disappears...
	# I wasn't able to continue building because my ship got destroyed, so it
	# looks like build mode was fully disabled").
	#
	# Everything below this point used to sit behind an early `return` on
	# `local_ship == null`, which took LMB, RMB, Q, C and X with it — shot down
	# and you could not shoot back, grapple away, salvage a wreck or repair the
	# corpse you were standing on. E was rescued from the same trap on
	# 2026-08-25 (the stranded corpse pilot) one key at a time; this is the
	# general fix. The ONLY thing a missing ship may disable is the verbs that
	# need a hull to act on, and even those fall back to a CARCASS under the
	# cursor (`_build_target`) — which is how you rebuild after losing
	# everything.
	#
	# CARCASS-AS-AIRSHIP, the thrust half (owner: "bolt on lift+THRUST to fly a
	# corpse"): the build verbs target a CARCASS under the cursor (within arm's
	# reach) when there is one — place engines/props/a helm on a dead whale,
	# then board it and FLY it — and your own ship otherwise, exactly as before.
	var build_ship := _build_target(get_global_mouse_position())
	var cell := Vector2i.ZERO
	if build_ship != null:
		cell = build_ship.cell_at_global(get_global_mouse_position())
	# The ghost follows the SELECTION: the block preview only while a ship block
	# is what Q would place -- terrain and balloons draw their own targets, and
	# exactly one ghost is ever on screen (clean-UI rule). With no hull under
	# the cursor and none of your own there is nothing to preview.
	if _sel_kind == "block" and build_ship != null:
		_update_build_ghost(build_ship, cell)
	else:
		_ghost_shown = false
		_ghost_label.visible = false

	var ui_mouse := _ui_wants_mouse()  # a hovered debug/saves/help panel eats clicks
	# Q -- THE place key (owner 2026-08-25: "only ONE key for placing things").
	# It places the palette selection: a ship block here, a balloon here, and
	# terrain via _handle_placing (hold-to-paint keeps its own cooldown).
	# (The old G damage-block dev verb is GONE -- LMB already damages blocks.)
	if Input.is_action_just_pressed("build_place") and not ui_mouse:
		match _sel_kind:
			"block":
				if build_ship != null:
					try_build_block(build_ship, cell)
				else:
					_notify("nothing to build on — a hull or a carcass, "
						+ "or T for a fresh ship")
			"balloon":
				_attach_balloon_at_cursor()
	if Input.is_action_just_pressed("build_remove") and not ui_mouse:
		if build_ship != null:
			try_remove_block(build_ship, cell)

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
## The stamp's width×height in cells (1×1 for primitives) — build_ghost
## stretches the preview rect by it.
var _ghost_dims := Vector2i.ONE
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


## Q with a block selected: place the block's whole STAMP (owner 2026-08-25:
## "an engine will never be a single block, but a rectangle or square").
## Primitives (hull, gasbag, flesh...) stamp their one cell, exactly as
## before; machines stamp their BlockDB.BUNDLE_8X rectangle, all or nothing
## — BuildPreview.stamp_order guarantees each cell lands with a neighbour, so
## per-cell can_place_at holds down the whole chain. Returns whether the
## stamp was placed.
func try_build_block(ship: Ship, cell: Vector2i) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	# snapped_stamp magnetises a bundle to the nearest legal spot around the
	# cursor (owner 2026-08-25: "almost impossible to place... does not snap");
	# the ghost runs through the same call, so what it shows is what lands.
	var order := BuildPreview.stamp_order(
		ship, BuildPreview.snapped_stamp(ship, cell, build_type, build_rot))
	if order.is_empty():
		return false  # nothing legal near the cursor — nothing placed
	# One bulk call, ONE rebuild — per-cell net_set_block paid a full O(cells)
	# rebuild for every cell of the stamp (owner lag audit 2026-08-25).
	ship.net_set_blocks(order, build_type)
	return true


## C: deconstruct. A PRIMITIVE removes its one cell (freeform sculpting); a
## MACHINE removes its whole 4-connected region — "never a single block"
## cuts both ways, so no whittling an engine down to a sliver. Region is
## snapshotted first: removals can sever, and severing mid-walk must not
## re-derive the machine.
func try_remove_block(ship: Ship, cell: Vector2i) -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.has_block(cell):
		return false
	var type: int = ship.blocks[cell]["type"]
	# deconstructs_whole, not is_bundle: the gasbag is bundle-PLACED but bulk
	# — C sculpts it cell by cell (an authored ship's bag is one huge region;
	# whole-region removal there turns a misclick into deleting the lift).
	if not BlockDB.deconstructs_whole(type, ship.scale_unit):
		ship.net_remove_block(cell)
		return true
	# One bulk call, ONE rebuild + ONE severance pass for the whole machine.
	ship.net_remove_blocks(BuildPreview.machine_region(ship, cell))
	return true


func _update_build_ghost(ship: Ship, cell: Vector2i) -> void:
	# Declutter (owner 2026-08-22): the ghost used to hang at the cursor across
	# the whole sky. Show it only where building is actually in play — over the
	# target ship (an occupied cell) or adjacent to it (can_place_at) — so open
	# sky stays calm. Never while piloting; the helm has your hands.
	_ghost_ship = ship
	# The ghost is the whole STAMP now — one cell for a primitive, the
	# machine's rectangle for a bundle — and it is green if and only if
	# pressing Q would really place it (BuildPreview.stamp_valid, the same
	# all-or-nothing rule the verb enforces). Anything else teaches the
	# player a rule the game does not have. Note the game imposes no reach
	# limit on building on YOUR ship; a carcass target is already
	# reach-gated by _build_target.
	# The SNAPPED stamp — the same call the verb places through, so the green
	# preview sits exactly where Q will land (possibly magnetised a few cells
	# off the cursor). When even the snap finds nothing, fall back to the raw
	# cursor stamp so the red preview still shows what was refused.
	var stamp: Array = []
	if is_instance_valid(ship):
		stamp = BuildPreview.snapped_stamp(ship, cell, build_type, build_rot)
	_ghost_valid = not stamp.is_empty()
	if stamp.is_empty():
		stamp = BuildPreview.stamp_cells(ship, cell, build_type, build_rot)
	_ghost_shown = is_instance_valid(ship) and player != null \
		and not player.is_piloting() \
		and (_ghost_valid or ship.has_block(cell))
	if not _ghost_shown:
		_ghost_label.visible = false
		return
	_ghost_cell = stamp[0]  # the stamp's top-left — build_ghost draws from it
	_ghost_dims = BlockDB.bundle_dims(build_type, ship.scale_unit, build_rot)
	_ghost_ratio_now = ship.lift_ratio()
	_ghost_ratio_next = BuildPreview.ratio_with(ship, build_type, stamp.size())

	_ghost_label.text = BuildPreview.readout(_ghost_ratio_now, _ghost_ratio_next)
	_ghost_label.add_theme_color_override("font_color", _ghost_tint())
	# Offset up-right of the pointer so the cursor itself stays unobscured.
	_ghost_label.position = get_viewport().get_mouse_position() + Vector2(16, -26)
	_ghost_label.visible = true


func _ghost_tint() -> Color:
	return Color(0.40, 1.0, 0.50) if _ghost_valid else Color(1.0, 0.40, 0.38)


## What WorldOverlay should draw, or null. The ship is resolved to plain
## values HERE rather than handed over as a node: passing live references
## into another node's _draw is what crashed the interact prompt on freed
## instances (see interact_prompt).
func build_ghost() -> Variant:
	if dive_style():
		return null   # nothing to place, so nothing to preview
	if not _ghost_shown or _ghost_ship == null or not is_instance_valid(_ghost_ship):
		return null
	var origin := _ghost_ship.local_pos_of(_ghost_cell) - Vector2.ONE * Ship.CELL * 0.5
	return [
		_ghost_ship.global_transform,
		Rect2(origin, Vector2(_ghost_dims) * Ship.CELL),
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
	var at := get_global_mouse_position()
	# THE SAME SWEEP SMOTHERS FIRE. No new key and no new tool (the owner's
	# one-key-per-verb standing order): X already means "put this right", and
	# a fire you cannot fight is a verdict rather than a fight. It douses on
	# every ship in reach, not just your own — you can save a tamed whale.
	if Tunables.get_bool("fire_enabled"):
		var reach := Ship.CELL * 4.0 * world_scale
		for ship in fleet.ships():
			if is_instance_valid(ship) and not ship.burning.is_empty():
				Fire.douse(ship, at, reach, delta, _fire_clock)
	local_ship.net_repair_near(
		local_ship.cell_at_global(at),
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
	# THE DIVE IS NOT A BUILDING GAME (owner 2026-08-30: "digging should not be
	# enabled in dive mode, and I wanna say the same should go for placing
	# blocks — it's a totally different style"). A run is flying, shooting and
	# spending; the expedition game keeps every one of these verbs. See
	# docs/KEYBINDINGS.md for the whole table, mode by mode.
	if dive_style():
		_mine_reset()
		return
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
			# And mining THROUGH into a sealed loot CAVITY (the kraken's walled
			# pocket) spills its bundle — also once per carcass. A bundle, not one
			# item, so it credits per entry; Ship decides the breach, not the world.
			for entry in ship.take_cavity_loot():
				var cavity_item: int = entry[0]
				var cavity_n: int = entry[1]
				player.inventory.add(cavity_item, cavity_n)
				if _pickups != null:
					_pickups.add(world_pos, "+%d %s" % [cavity_n, ItemDB.name_of(cavity_item)],
						float(world_scale))
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


## Display name for a Ship.BalloonSize — one place, so the cycle cue, the attach
## cue and the HUD never disagree about what "medium" is called.
static func _balloon_size_name(size: int) -> String:
	match size:
		Ship.BalloonSize.SMALL: return "small"
		Ship.BalloonSize.MEDIUM: return "medium"
	return "large"


func _attach_balloon_at_cursor() -> void:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return
	var target := _ship_cell_under(get_global_mouse_position())
	if target.is_empty():
		_notify("aim at a hull or corpse cell to tether a balloon")
		return
	try_attach_balloon(target[0], target[1], _balloon_size)


## Tether a balloon of `size` at (ship, cell). Reach-gated (arm's length, like
## mining/harvest), authority-gated, and — since v0.49.0 — PAID FOR: it spends
## one crafted balloon of that size out of the player's pack (items/recipes.gd).
## Returns whether it attached.
##
## The charge is deliberately here, in the world VERB, and not in
## `Ship.attach_balloon`: the ship layer is the mechanism (a save, a joining
## peer and the tests all attach balloons that were paid for long ago, or never
## cost anything at all), while the verb is the one place a PLAYER spends. Same
## split as terrain placement (try_place debits; Terrain.net_place does not).
##
## Order matters: every gate is checked BEFORE the stock is touched, and the item
## comes out only after `attach_balloon` reports success — so a refused attach
## can never eat the balloon.
func try_attach_balloon(ship: Ship, cell: Vector2i, size: int) -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.has_block(cell):
		return false
	if not _carcass_cell_in_reach(ship, cell):
		_notify("too far — get closer to tether a balloon")
		return false
	if not NetUtil.is_authority(self):
		return false  # networked balloon attach is a seam, like harvest
	var item := ItemDB.balloon_item_for(size)
	if not _has_balloon(size):
		_notify("no %s in the pack — craft one (N/M): %s"
			% [ItemDB.name_of(item), _balloon_recipe_cost(size)])
		return false
	if ship.attach_balloon(cell, size):
		if player != null and is_instance_valid(player):
			player.inventory.remove(item, 1)
		_notify("balloon tethered (%s) — lift +%d   [%d left]"
			% [_balloon_size_name(size), int(Ship.BALLOON_LIFT[size]),
				_balloon_stock(size)])
		return true
	return false


## How many crafted balloons of `size` the local player carries (0 with no body).
func _balloon_stock(size: int) -> int:
	if player == null or not is_instance_valid(player) or player.inventory == null:
		return 0
	return player.inventory.count(ItemDB.balloon_item_for(size))


## Does the local player carry a balloon of `size` to spend?
func _has_balloon(size: int) -> bool:
	return _balloon_stock(size) > 0


## The "2 Blubber + 1 Copper Ingot" half of the recipe that makes `size`, for the
## empty-pack cue — read off items/recipes.gd rather than restated here, so the
## cue can never quote a price the crafting table does not charge.
func _balloon_recipe_cost(size: int) -> String:
	var want := ItemDB.balloon_item_for(size)
	for r in Recipes.RECIPES:
		if int(r["output"]) == want:
			var parts: Array[String] = []
			for id in r["inputs"]:
				parts.append("%d %s" % [int(r["inputs"][id]), ItemDB.name_of(id)])
			return " + ".join(parts)
	return "?"


## Draw specs for every attached balloon, for WorldOverlay (which owns no ship
## references). Each: the anchor cell's world point, the balloon centre (above it
## on a taut cable, with a gentle decorative sway), its radius, and the cable count.
func balloons_to_draw() -> Array:
	var out: Array = []
	if fleet == null:
		return out
	for ship in fleet.ships():
		if not is_instance_valid(ship) or ship.balloons.is_empty():
			continue
		for b in ship.balloons:
			var size := int(b["size"])
			var u: float = ship.scale_unit
			var anchor: Vector2 = ship.to_global(ship.local_pos_of(b["cell"]))
			var lc := Ship.BALLOON_CABLE_CELLS * Ship.CELL * u
			# STATIC, straight up the taut cable — no decorative sway (owner
			# 2026-08-25: "they can be static and immobile (as source)").
			out.append({
				"anchor": anchor,
				"center": anchor + Vector2(0.0, -lc),
				"radius": Ship.BALLOON_RADIUS_CELLS[size] * Ship.CELL * u,
				"cables": int(Ship.BALLOON_CABLES[size]),
				"unit": u,
				# 1.0 = pristine, 0 = about to burst. The bulb darkens as it takes
				# hits, so a balloon you have been shooting reads as nearly gone
				# (it is ONE placeable — any hit hurts all of it).
				"health": clampf(float(b.get("hp", Ship.BALLOON_HP[size]))
					/ Ship.BALLOON_HP[size], 0.0, 1.0),
			})
	return out


## The balloon BUILD GHOST, or null: what tethering the selected size at the cell
## under the cursor would put there. Same geometry as a real balloon (so what you
## see is what you get) minus the sway — a ghost that drifts reads as alive.
##
## It appears only when the verb would actually be offered: on foot, not piloting,
## not over a UI panel, with the cursor on a real hull/corpse cell. `ok` folds the
## two ways it can still refuse — out of reach, or no balloon of that size in the
## pack — into ONE flag for the overlay to colour by, because the player does not
## need two shades of "no" (the cue on U says which). Keeping the ghost off the
## screen the rest of the time is the clean-UI rule: it is an answer to "where
## will this go", asked only while you are aiming at something.
## `cursor` defaults to INF, meaning "wherever the mouse actually is" — the
## overlay's case. A caller (the startup test) can aim it explicitly instead,
## because the live mouse is un-aimable headless and the camera moves the world
## point under a fixed screen pixel every time the player does.
func balloon_ghost_to_draw(cursor := Vector2.INF) -> Variant:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return null
	# Only while the palette selects a balloon (Q would tether one) — otherwise
	# the block ghost owns the cursor and exactly one preview is ever on screen.
	if _sel_kind != "balloon":
		return null
	if _ui_wants_mouse():
		return null
	var at := get_global_mouse_position() if cursor == Vector2.INF else cursor
	var target := _ship_cell_under(at)
	if target.is_empty():
		return null
	var ship: Ship = target[0]
	var cell: Vector2i = target[1]
	var size := _balloon_size
	var u: float = ship.scale_unit
	var anchor_pos: Vector2 = ship.to_global(ship.local_pos_of(cell))
	return {
		"anchor": anchor_pos,
		"center": anchor_pos + Vector2(0.0, -Ship.BALLOON_CABLE_CELLS * Ship.CELL * u),
		"radius": Ship.BALLOON_RADIUS_CELLS[size] * Ship.CELL * u,
		"cables": int(Ship.BALLOON_CABLES[size]),
		"unit": u,
		"ok": _carcass_cell_in_reach(ship, cell) and _has_balloon(size),
	}


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
# With a terrain material SELECTED (B), hold Q + aim to lay it back into the
# world: an empty, in-reach cell becomes solid terrain and one item leaves the
# inventory. It is authority-owned exactly like mining (Terrain.net_place
# mirrors net_dig): the server writes the cell and `placed` debits the placer; a
# client forwards the request. Ship building (Q with a block selected) writes
# the SHIP grid; this writes TERRAIN — one key, dispatched by the palette.

func _handle_placing(delta: float) -> void:
	if dive_style():
		return   # a run does not build (see _handle_mining)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	if player == null or not is_instance_valid(player) or player.is_piloting() \
			or terrain == null:
		return
	if _sel_kind != "terrain":
		return  # Q is placing a block or a balloon right now
	if not Input.is_action_pressed("build_place") or _ui_wants_mouse():
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


# --- The BUILD PALETTE: one key places, one key cycles (owner 2026-08-25) --
#
# "There should be only ONE key for placing things." Q places whatever is
# SELECTED; B cycles the selection (Shift+B backwards). The palette is one flat
# list: every buildable ship block, then each terrain material actually
# carried (empty stacks skipped — materials are discovered by mining), then
# the three tethered balloon sizes ALWAYS (hiding them while unstocked made
# the feature undiscoverable — owner 2026-08-25). Ship blocks are free-build
# today (BACKLOG) so they are always listed too.
#
# The selection is stored as a KIND plus the per-kind id (build_type /
# _held_material / _balloon_size), never as a list index: stacks appear and
# vanish as you mine and spend, and an index into a list that just changed
# under you would silently select something else.

## What Q places right now: "block" (the ship grid), "terrain" (the world), or
## "balloon" (a crafted tether). B moves it through _build_palette().
var _sel_kind := "block"

## Bundle orientation for the selected block (BlockDB.bundle_dims rot): the
## propeller mounts 6×2 or 2×6 in the source, so the palette lists it twice
## and B picks the mounting — no extra key.
var build_rot := false


## The flat cycle list: every {kind, id} Q could place, in order.
func _build_palette() -> Array:
	var out: Array = []
	for t in BlockDB.type_count():
		if t == BlockDB.Type.DOOR:
			continue  # doors are placed CLOSED; open is runtime state, never built
		out.append({"kind": "block", "id": t})
		# A machine whose bundle is a true rectangle mounts either way (the
		# source's propeller): one more palette entry, rotated — the cycle
		# key picks the mounting, no new key.
		var dims := BlockDB.bundle_dims(t, float(world_scale))
		if dims != Vector2i.ONE and dims.x != dims.y and t == BlockDB.Type.PROPELLER:
			out.append({"kind": "block", "id": t, "rot": true})
	if player != null and is_instance_valid(player) and player.inventory != null:
		for id in player.inventory.types():
			if ItemDB.is_placeable_terrain(id) and player.inventory.count(id) > 0:
				out.append({"kind": "terrain", "id": id})
	# The three TETHERED BALLOONS are ALWAYS in the cycle, stock or no stock
	# (owner 2026-08-25: "I can't find the latched helium balloon — it was
	# available in one of the previous iterations"). They used to be hidden
	# while unstocked, which made the whole feature invisible to anyone who
	# had not already crafted one. An empty size shows its x0 in the cue,
	# reads RED in the ghost, and Q answers with the recipe to sew one —
	# the path to the feature instead of its absence. Terrain stays
	# skip-when-empty: materials are discovered by mining, and the carried
	# pack is their natural roster.
	for size in Ship.BALLOON_LIFT.size():
		out.append({"kind": "balloon", "id": size})
	return out


## Point the palette at (kind, id) — the cycle lands here, and tests/debug can
## jump straight to an entry. Writes the per-kind memory too, so each kind keeps
## its last choice while another kind is selected.
func select_build(kind: String, id: int, rot := false) -> void:
	_sel_kind = kind
	match kind:
		"terrain":
			_held_material = id
		"balloon":
			_balloon_size = id
		_:
			build_type = id
			build_rot = rot


## The current selection's per-kind id (what select_build would need to recreate it).
func _sel_id() -> int:
	match _sel_kind:
		"terrain":
			return _held_material
		"balloon":
			return _balloon_size
	return build_type


## Where the selection sits in `palette`, or -1 (the selected stack was spent —
## cycling recovers by stepping from the list head).
func _palette_index(palette: Array) -> int:
	var id := _sel_id()
	for i in palette.size():
		if palette[i]["kind"] == _sel_kind and int(palette[i]["id"]) == id \
				and (_sel_kind != "block"
					or bool(palette[i].get("rot", false)) == build_rot):
			return i
	return -1


## Drive the hold-B picker: a press starts the clock, crossing B_HOLD_SECONDS
## opens the grid, and RELEASE either commits the hovered cell (if the grid is
## up) or — for a quick tap — cycles one step. Shift+tap cycles backward.
## Is the game in THE DIVE's reduced verb set right now? One predicate, so the
## mining, placing, ghost and palette paths can never disagree about whether
## building is a thing. (The intro's twin of this used to be `hud_quiet`;
## it is gone — the intro has no HUD to quiet now that it is its own scene.)
func dive_style() -> bool:
	return dive != null and dive.outcome == ""


func _update_build_picker() -> void:
	if dive_style():
		if _build_picker != null:
			_build_picker.visible = false
		return
	if _build_picker == null:
		return
	if Input.is_action_just_pressed("build_cycle"):
		_b_press_msec = Time.get_ticks_msec()
	# Held long enough, and no other modal owns the screen → open.
	if _b_press_msec >= 0.0 and not _build_picker.is_open() and _modal_open() == false:
		var held := Input.is_action_pressed("build_cycle")
		var elapsed := Time.get_ticks_msec() - _b_press_msec
		if held and elapsed >= B_HOLD_SECONDS * 1000.0:
			_build_picker.open()
	if Input.is_action_just_released("build_cycle"):
		if _build_picker.is_open():
			var pick := _build_picker.hovered_entry()
			if not pick.is_empty():
				select_build(pick["kind"], int(pick["id"]),
					bool(pick.get("rot", false)))
				_notify(build_selection_label())
			_build_picker.close()
		elif _b_press_msec >= 0.0:
			# A tap (released before the grid opened): cycle, as B always did.
			_cycle_build(-1 if Input.is_key_pressed(KEY_SHIFT) else 1)
		_b_press_msec = -1.0


## Is a full-screen panel already up? The picker yields to them rather than
## drawing over the help/saves/character overlays.
func _modal_open() -> bool:
	if _help_panel != null and _help_panel.visible:
		return true
	if _save_panel != null and _save_panel.visible:
		return true
	return _character_sheet != null and _character_sheet.visible


## The palette as GROUPED, labelled, swatched entries for the hold-B picker —
## the same `_build_palette` the cycle walks, sorted into the grid's rows and
## annotated with what the cell has to show (name, colour, stock, and whether
## it is the current pick). Presentation data only; committing goes through
## select_build, exactly like the cycle.
func build_picker_model() -> Array:
	var groups := {
		"block": {"title": "BLOCKS", "entries": []},
		"terrain": {"title": "MATERIALS", "entries": []},
		"balloon": {"title": "BALLOONS", "entries": []},
	}
	for e in _build_palette():
		var kind: String = e["kind"]
		if groups.has(kind):
			(groups[kind]["entries"] as Array).append(_picker_entry(e))
	var out: Array = []
	for kind in ["block", "terrain", "balloon"]:
		if not (groups[kind]["entries"] as Array).is_empty():
			out.append(groups[kind])
	return out


## One palette entry, dressed for the grid: label (with a bundle's dims and a
## rotated tag), swatch colour, a stock count where one applies (-1 = none),
## and whether it is what Q places right now.
func _picker_entry(e: Dictionary) -> Dictionary:
	var kind: String = e["kind"]
	var id := int(e["id"])
	var rot := bool(e.get("rot", false))
	var label := "?"
	var color := Color.WHITE
	var count := -1
	match kind:
		"block":
			label = str(BlockDB.get_def(id)["name"])
			var dims := BlockDB.bundle_dims(id, float(world_scale), rot)
			if dims != Vector2i.ONE:
				label += "  %dx%d" % [dims.x, dims.y]
			color = BlockDB.color_of(id)
		"terrain":
			label = ItemDB.name_of(id)
			color = ItemDB.color_of(id)
			count = 0
			if player != null and is_instance_valid(player) and player.inventory != null:
				count = player.inventory.count(id)
		"balloon":
			label = _balloon_size_name(id).capitalize()
			color = Color(0.70, 0.80, 0.92)
			count = _balloon_stock(id)
	var same_rot: bool = kind != "block" or rot == build_rot
	var current: bool = kind == _sel_kind and id == _sel_id() and same_rot
	return {"kind": kind, "id": id, "rot": rot, "label": label,
		"color": color, "count": count, "current": current}


## B: step the selection through the palette (dir = +-1), with a one-line cue so
## you always know what Q now places — no panel, no wall of keys.
func _cycle_build(dir: int) -> void:
	var palette := _build_palette()
	if palette.is_empty():
		return
	var next: Dictionary = palette[wrapi(_palette_index(palette) + dir, 0, palette.size())]
	select_build(next["kind"], int(next["id"]), bool(next.get("rot", false)))
	_notify(build_selection_label())


## "build: Engine" / "place: Stone (x12)" / "balloon: small (1 tether, lift 250) x2"
## — one line the cycle cue and any readout share, so they cannot disagree.
func build_selection_label() -> String:
	match _sel_kind:
		"terrain":
			var n := 0
			if player != null and is_instance_valid(player) and player.inventory != null:
				n = player.inventory.count(_held_material)
			return "place: %s (x%d)" % [ItemDB.name_of(_held_material), n]
		"balloon":
			return "balloon: %s (%d tether%s, lift %d) x%d" % [
				_balloon_size_name(_balloon_size),
				Ship.BALLOON_CABLES[_balloon_size],
				"" if int(Ship.BALLOON_CABLES[_balloon_size]) == 1 else "s",
				int(Ship.BALLOON_LIFT[_balloon_size]),
				_balloon_stock(_balloon_size)]
	# A bundle says its shape ("Engine 4×4") so the cycle cue doubles as the
	# footprint readout; primitives stay a bare name.
	var dims := BlockDB.bundle_dims(build_type, float(world_scale), build_rot)
	if dims != Vector2i.ONE:
		return "build: %s %d×%d" % [BlockDB.get_def(build_type)["name"], dims.x, dims.y]
	return "build: %s" % BlockDB.get_def(build_type)["name"]


## What the WorldOverlay should draw for the place target, or null: the world-
## space cell rect and whether the placement is legal (in reach, empty, stocked).
## Green legal / red blocked, the mirror of the mine highlight. Plain values only.
func place_target() -> Variant:
	if player == null or not is_instance_valid(player) or player.is_piloting() \
			or terrain == null:
		return null
	if _sel_kind != "terrain" or not Input.is_action_pressed("build_place"):
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
#
# SHIFT+M crafts the whole affordable stack in one action (owner's "crafting
# without repetition" charter — the original's reviews hated spam-clicking a
# recipe). The "craft" action is bound to bare M, but Godot's action matching
# ignores modifiers unless the check is exact, so Shift+M ALSO fires "craft" —
# hence one keypress branch here rather than a second action.

func _handle_crafting() -> void:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return
	if Input.is_action_just_pressed("craft_cycle"):
		_recipe_index = (_recipe_index + 1) % Recipes.RECIPES.size()
	if Input.is_action_just_pressed("craft"):
		if Input.is_key_pressed(KEY_SHIFT):
			try_craft_all()
		else:
			try_craft()


## Craft the selected recipe; returns true if it was made. Unit-testable without
## input (the craft logic itself lives in Recipes.craft — this just wires the
## player's inventory to it).
func try_craft() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var recipe: Dictionary = Recipes.RECIPES[_recipe_index]
	var made := Recipes.craft(player.inventory, recipe)
	if made:
		_craft_feedback(recipe, 1)
	return made


## Craft the selected recipe as many times as the inventory affords; returns how
## many were made. Same seam as try_craft — input-free so it is unit-testable.
func try_craft_all() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var recipe: Dictionary = Recipes.RECIPES[_recipe_index]
	var made := Recipes.craft_all(player.inventory, recipe)
	if made > 0:
		_craft_feedback(recipe, made)
	return made


## One float over the player saying what the craft produced — "+6 Whale Oil" for a
## batch, the same path single-craft has always used (crafting has no world cell to
## pop the number over, so it rides the player).
func _craft_feedback(recipe: Dictionary, batches: int) -> void:
	if _pickups == null:
		return
	_pickups.add(player.global_position,
		"+%d %s" % [int(recipe.get("count", 1)) * batches, ItemDB.name_of(int(recipe["output"]))],
		float(world_scale))


## Piloting is entered by walking up to a helm and using it, exactly as the
## original does with its control panel — not by the ship being the default
## thing you control. The same key opens and closes doors (owner spec,
## session 3): the NEAREST interactable wins, so standing in a doorway a
## couple of cells from the helm toggles the door instead of boarding.
var _nearby_helm: Array = []
var _nearby_door: Array = []
var _nearby_mender: Array = []


func _handle_interact() -> void:
	if player == null:
		_nearby_helm = []
		_nearby_door = []
		return
	# Riding a tamed creature: the ride ends by releasing the hook (RMB — see the
	# grapple handler), not the use key. E still steps off as a harmless
	# fallback, but is no longer required (owner 2026-08-24). No helm/door search while mounted — that
	# is for when you are on your own two feet.
	if player.is_riding():
		_nearby_helm = []
		_nearby_door = []
		if Input.is_action_just_pressed("interact"):
			dismount_creature()
		return
	_nearby_helm = _dive_helm() if dive != null 		else Player.find_helm(_helm_candidates(), player.global_position, _helm_reach())
	# THE DIVE has no doors to work: they are opened at the start of a run and E
	# never offers one again, so the use key means helm (or station) and nothing
	# else — the "heavily simplify the nuisances" the mode was asked for.
	_nearby_door = [] if dive != null \
		else Player.find_door(fleet.ships(), player.global_position, _door_reach())
	_nearby_mender = Player.find_mender(fleet.ships(), player.global_position, _mender_reach())

	if not Input.is_action_just_pressed("interact"):
		return
	if player.is_piloting():
		var left := player.piloting
		player.disembark()
		if dive != null:
			_dive_step_out(left)
		return
	# One use-key, three interactables: act on whichever is NEAREST (the same
	# nearest-wins that disambiguates a helm from a doorway in a cramped cabin).
	match _nearest_interactable():
		"door":
			(_nearby_door[0] as Ship).net_toggle_door(_nearby_door[1])
		"mender":
			(_nearby_mender[0] as Ship).net_toggle_mender()
		"helm":
			# IN A RUN, E FROM OUTSIDE PUTS YOU AT THE HELM (owner 2026-08-30:
			# "hitting E next to a ship should place the player INSIDE the ship
			# on top of the helm"). The Dive lets you board from anywhere on the
			# hull, and `Player.board` rides you where you were STANDING — so
			# without this you pilot from outside the hull, floating alongside
			# your own ship. The mirror of `_dive_step_out`.
			if dive != null:
				_dive_step_in(_nearby_helm[0], _nearby_helm[1])
			player.board(_nearby_helm[0], _nearby_helm[1])


## Doors answer the interact key only at arm's length — you work a door
## you are standing at, not one across the room. Short reach plus
## nearest-wins is what disambiguates E in a cramped cabin: at the helm
## (the spawn cell) the door is out of reach entirely; pressed against a
## closed door, the door is the nearest station by a wide margin.
func _door_reach() -> float:
	return Ship.CELL * 1.5 * world_scale


## You operate a repair station you are STANDING at, like a door — short reach
## plus nearest-wins is what keeps E unambiguous when a station sits near a helm.
func _mender_reach() -> float:
	return Ship.CELL * 2.5 * world_scale


## Which of the three interactables (door / helm / repair station) is nearest —
## "" when none is in reach. One place decides it, so the prompt and the action
## can never disagree about what E will do.
func _nearest_interactable() -> String:
	var dd := _station_dist(_nearby_door)
	var dh := _station_dist(_nearby_helm)
	var dm := _station_dist(_nearby_mender)
	var best := minf(dd, minf(dh, dm))
	if best == INF:
		return ""
	if best == dm:
		return "mender"
	if best == dd:
		return "door"
	return "helm"


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


## Where the overlay should float the [E] prompt and what it should say,
## as [pos, text] — or null. Validity checks live HERE: handing the raw
## player/ship references to another node's _draw crashed on freed
## instances (respawn races the redraw).
func interact_prompt() -> Variant:
	if player == null or not is_instance_valid(player) or player.is_piloting():
		return null
	match _nearest_interactable():
		"door":
			var dship: Ship = _nearby_door[0]
			var closed: bool = dship.blocks[_nearby_door[1]]["type"] == BlockDB.Type.DOOR_CLOSED
			return [dship.to_global(dship.local_pos_of(_nearby_door[1])),
				"[E] open the door" if closed else "[E] close the door"]
		"mender":
			var mship: Ship = _nearby_mender[0]
			return [mship.to_global(mship.local_pos_of(_nearby_mender[1])),
				"[E] stop the repair station" if mship.menders_running
					else "[E] run the repair station"]
		"helm":
			var hship: Ship = _nearby_helm[0]
			return [hship.to_global(hship.local_pos_of(_nearby_helm[1])), "[E] take the helm"]
	return null


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
			if not _refuse_in_run("Not in a run — the Dive is single-player."):
				host_session()
		KEY_J:
			if not _refuse_in_run("Not in a run — the Dive is single-player."):
				join_session()
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
	# LET GO OF THE ROPE (owner 2026-08-30: "player dying should unhook/reset
	# their grappling hook"). A fresh body inherits a hook that was latched to
	# something a world away — the tether is drawn across the screen and the reel
	# fights every step you take. Death is a reset; the rope is part of it.
	player.release_grapple()
	# ...and do not bill the drop this respawn is about to cause. A fresh body
	# placed above ground did not choose that fall, and charging it is a DEATH
	# LOOP: killed by the landing, respawned, dropped, killed again.
	player.forgive_fall()
	# Safety net: never strand the local player shipless — e.g., the core just ate
	# their ship (owner: "say goodbye"). Single-player / host only; a fresh starter
	# at base beats the "No ship — this is a bug" dead end. (No-op when they still
	# have a ship: the guard only fires when local_ship is gone.)
	# ...except in THE DIVE, where losing the ship IS the run ending (owner
	# ruling). Handing over a fresh starter here would quietly undo the mode's
	# only stake, so the run is left to reach its own verdict.
	if (not Net.is_online() or Net.is_server()) and not is_instance_valid(local_ship) 			and dive == null:
		_give_ship_to(_my_id())
		_refresh_local_ship()
	# Where a fresh body appears. Your own deck if you have one; otherwise the
	# world's original spawn — except inside a run, where "the original spawn"
	# is a hundred thousand pixels from anything the run built, so the LAUNCH
	# DECK is the only sane ground to put you back on.
	var anchor := SHIP_START
	if dive != null and dive.outcome == "":
		anchor = dive_landing_pos(1) - Vector2(PLAYER_SPAWN_CELL) * Ship.CELL * world_scale \
			- Vector2(0.0, 150.0 * float(world_scale))
	if is_instance_valid(local_ship):
		anchor = local_ship.global_position
	player.global_position = anchor + Vector2(PLAYER_SPAWN_CELL) * Ship.CELL * world_scale
	# A fresh body starts whole: refill the GRIT pool (a respawn from death OR from
	# falling out of the world both come through here). The pack is KEPT — the
	# simplest sane choice; on-death loot drop is a documented seam (BACKLOG).
	if player.stats != null:
		player.max_health = player.stats.max_health()
	player.health = player.max_health


## Refuse a session verb while a run is live, saying so. Returns whether it was
## refused, so the call site reads as one line. Anything that would teleport,
## rebuild or rewind the world belongs here: a roguelite run whose world can be
## reset, whose body can be recalled to spawn, or whose state can be reloaded
## from disk has no stakes left in it.
func _refuse_in_run(why: String) -> bool:
	if dive == null or dive.outcome != "":
		return false
	_notify(why)
	return true


## Debug convenience: throw away every ship and start over. Server-side only —
## a client resetting the shared world would be a strange thing to allow.
func reset_world() -> void:
	if Net.is_server():
		for ship in fleet.ships():
			ship.queue_free()
		# WAIT until they are actually gone, not just one frame (2026-08-26). A
		# single process_frame after queue_free races: a ship freed from inside
		# a physics tick is reaped at idle, and under a busy run_all the respawn
		# below could land before the reap, leaving the fleet at 15 instead of
		# 10 — a rare, real flake in the reset test. Poll the fleet empty (a
		# bounded wait, so a stuck free can never hang the reset).
		var guard := 0
		while not fleet.ships().is_empty() and guard < 30:
			await get_tree().process_frame
			guard += 1

		_give_ship_to(1)
		if Net.is_online():
			for id in multiplayer.get_peers():
				_give_ship_to(id)
		else:
			_spawn_enemy_hulk()  # the target range resets with the world
			_spawn_whale()
			_spawn_critters()
			_spawn_kraken()
			_spawn_boss()
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
	# FPS first, version second (owner 2026-08-30: "invert placement of version
	# and FPS") — the build number is the thing you read deliberately, so it sits
	# at the end of the line where the eye stops.
	var status := "%d fps   v%s" % [Engine.get_frames_per_second(), ver]
	# Same platform split as the help panel: name the key that actually works here.
	_corner_label.text = "%s help   Tab map\n%s" % [_help_key_name, status]


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

	# Craft: the selected recipe's inputs are present. The "(xN)" suffix is how
	# many the stock affords — the one hint that Shift+M is worth pressing. A
	# short suffix on a line that already exists, deliberately not a new readout.
	if player.inventory != null and Recipes.RECIPES.size() > 0:
		var recipe: Dictionary = Recipes.RECIPES[_recipe_index]
		var affordable := Recipes.craftable_count(player.inventory, recipe)
		if Recipes.can_craft(player.inventory, recipe):
			s["craftable"] = true
			s["craft_text"] = Recipes.summary(recipe)
			if affordable > 0:
				s["craft_text"] = "%s (x%d)" % [s["craft_text"], affordable]

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
	# Placement: a terrain material SELECTED (the palette — otherwise Q is
	# placing a block/balloon and the cue would lie), aimed at an empty
	# in-reach cell, with stock to spend.
	if terrain != null and _sel_kind == "terrain":
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
				lines.append("[Q] place %s   ·   [B] next" % s["place_name"])
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
	# The ship whose numbers the helm HUD shows is the one being PILOTED —
	# which need not be local_ship: flying a built corpse-airship while the
	# starter still lives used to show the STARTER's lift/power up here.
	# RIDING IS A CONTROL MODE, and it says so (owner 2026-08-26: "rideable
	# creatures don't need a PANEL to be controlled from — the grappling hook
	# is the override"). It never did: the ride has been the LATCH itself since
	# 2026-08-24 and a creature has no helm at all (world._handle_riding routes
	# WASD straight into its AI). What was missing was any sign of it up here —
	# the only status line the game had said AT THE HELM, so a mount read as a
	# thing you were merely stuck to.
	if player != null and is_instance_valid(player) and player.is_riding():
		var mount: Ship = player.riding
		if is_instance_valid(mount):
			hud.text = "\n".join([
				"RIDING — WASD steers   ·   release the hook (RMB) to let go",
				"Beast:  %.0f / %.0f%s" % [mount.shared_health,
					mount.shared_health_max,
					"   ·   DRILLING (ram terrain to dig)" if mount.ridden_mining
						else ""],
				"Altitude:  %.0f    Speed:  %.0f" % [
					-mount.global_position.y, mount.linear_velocity.length()],
			])
			return
	# No hull of your own and not flying or riding anything: say so, and say what to do
	# about it. (Lives here because _update_hud OWNS hud.text — written above
	# this point it was overwritten the same frame.)
	if local_ship == null and (player == null or not is_instance_valid(player)
			or not player.is_piloting()):
		if Net.is_online():
			hud.text = "Connecting to host..."
		elif dive != null and dive.outcome == "":
			# T is refused in a run, so do not offer it. On the launch deck the
			# answer is always the same one: go and take a hull.
			hud.text = "No ship — walk to a hull and press E"
		else:
			hud.text = "No ship — build on a carcass, walk to a helm and press E, " \
				+ "or T to respawn"
		return
	var flown: Ship = player.piloting if (player != null
		and is_instance_valid(player) and player.is_piloting()) else null
	if flown == null or not is_instance_valid(flown):
		var session := ""
		if Net.is_online():
			session = "%s  peers:%d  id:%d" % [
				"HOST" if multiplayer.is_server() else "CLIENT",
				Net.peer_count(), _my_id()]
		hud.text = session
		return

	# THE RUN DOES NOT WANT THE WALL OF NUMBERS (owner 2026-08-30: "all the extra
	# info that we see on the left under the health is not really needed in dive
	# mode either"). The Dive has its own read-out — the depth gauge on the right
	# — and the one number here that can actually kill you, the air, still shouts
	# for itself through the deep-air warning in HudLayer. So in a run this
	# corner says the one thing worth saying and stops.
	if dive != null and dive.outcome == "":
		hud.text = "AT THE HELM — WASD flies, E to step off"
		return

	hud.text = "\n".join([
		"AT THE HELM — WASD flies, E to step off",
		"Lift / weight: %.2f  (%s)" % [
			flown.lift_ratio(),
			"climbing" if flown.lift_ratio() > 1.0 else "sinking",
		],
		"Power:  %.0f / %.0f%s" % [
			flown.power_supply(),
			flown.active_draw(),
			"  (BROWNOUT)" if flown.active_draw() > flown.power_supply() else "",
		],
		"Altitude:  %.0f    Speed:  %.0f" % [
			-flown.global_position.y, flown.linear_velocity.length()],
		"Ceiling:  %.0f    Air:  %.2f" % [
			-flown.ceiling_estimate(),
			flown.air_density_at(flown.global_position.y)],
	])


func _draw() -> void:
	for rect in _terrain_rects:
		draw_rect(rect, Color(0.20, 0.24, 0.22))
		draw_rect(rect, Color(0.28, 0.34, 0.30), false, 2.0)

	# The [E] helm prompt lives on WorldOverlay (maps/world/overlay.gd):
	# this node's own drawing renders beneath its children, so text drawn
	# here would hide behind hulls (owner report).
