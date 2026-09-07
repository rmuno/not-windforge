extends SceneTree

## THE INTRO SCENE, booted for real.
##
## The old intro was a camera state inside the game world, and every bug it had
## was the same bug: something player-facing leaked onto the front page (a health
## bar, an edge marker, a helm prompt). This suite exists to prove that class of
## bug is now impossible rather than suppressed — the scene simply has no player,
## no HUD and no terrain to leak from.
##
## It also pins the two things the owner asked for by name: the procession runs
## in their order (whale varieties, then critters, then your ship and an enemy
## trading fire), and it LOOPS — an act that falls behind is sent to the back of
## the queue, so there is no end to reach and no cut to hide.
##
##   godot --headless --path . --script tests/intro_test.gd

var failures := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("    ok   %s" % what)
	else:
		failures += 1
		print("    FAIL %s" % what)


func _initialize() -> void:
	# THE OWNER'S REAL PROFILE IS NOT A FIXTURE: every suite writes through
	# the profile (creature sightings, the F2 forget buttons, card takes), and
	# a full run used to wipe the real bestiary + card gallery. Redirect first,
	# before anything can touch disk.
	Profile.path = "user://profile_test.json"
	# ...and the SAVED SHIPS shelf (Q-T): the Dive's launch deck moors what it
	# finds there, so every suite gets its own empty scratch directory rather
	# than the owner's real one (or another suite's fixtures).
	ShipLayout.user_dir = "user://ships_test_intro"
	print("\n=== intro scene ===\n")
	var packed: PackedScene = load("res://maps/intro/intro.tscn")
	_ok(packed != null, "maps/intro/intro.tscn loads")
	if packed == null:
		return _finish()

	# --- The running order, before anything is built -------------------------
	var plan: Array = IntroScene.cast_plan()
	_ok(plan.size() >= 10, "the procession has a real cast (%d acts)" % plan.size())
	var kinds: Array = []
	for e in plan:
		kinds.append(String((e as Dictionary)["kind"]))
	var first_critter := kinds.find("critter")
	var last_whale := 0
	for i in kinds.size():
		if kinds[i] == "whale":
			last_whale = i
	_ok(kinds.count("whale") == WhaleSpawn.PLANS.size(),
		"every whale variety walks past (%d)" % kinds.count("whale"))
	_ok(first_critter > last_whale, "...whales first, then the critters")
	_ok(kinds[kinds.size() - 1] == "duel",
		"...and your ship against an enemy brings up the rear")
	for e in plan:
		var d := e as Dictionary
		# .ship files are plain TEXT read through FileAccess (ShipLayout.load_cells),
		# never imported resources — ResourceLoader has never heard of them.
		_ok(FileAccess.file_exists(String(d["path"])),
			"the '%s' act loads a real blueprint" % d["kind"])
		_ok(float(d["drift"]) < 0.0,
			"...and drifts LEFT against the pan, so it sweeps past")

	# --- The scene itself ----------------------------------------------------
	var intro: Node = packed.instantiate()
	root.add_child(intro)
	for i in 20:
		await process_frame
	_ok(intro.get("camera") != null, "the intro has a camera")
	_ok(intro.get("fleet") != null, "...and a fleet to hold the cast")

	# THE TITLE SCREEN IS A SMALL SCENE, AND THAT IS A BUDGET (owner 2026-08-30:
	# "the game is still super laggy when loading it... Is the title screen a
	# small scene? (it should be)").
	#
	# It was not. It built all thirteen bodies UPSCALED 8x — **358,016 blocks**,
	# ~11.5 s before the first frame — and paid it again on every quit to the
	# title, because quitting reloads this scene. `upscale_cells` multiplies a
	# blueprint's GRANULARITY and never its shape, and an intro needs none of it:
	# nothing walks, mines, collides or is shot here, and at this pull-back one
	# 8x cell was 0.88 screen pixels.
	#
	# The budget is the point of the fix, so it is pinned. Add a body to the
	# procession and this still passes; upscale the cast again and it does not.
	var built := 0
	for ship in (intro.get("fleet").call("ships") as Array):
		if is_instance_valid(ship):
			built += (ship as Ship).blocks.size()
	_ok(built < 40000, "the title screen is a SMALL scene (%d blocks, was 358,016)" % built)
	_ok(IntroScene.SCALE == 1,
		"...because the cast is built at authored scale, not upscaled")
	# ...and the framing is a CONSTANT under that: the zoom is corrected by the
	# same factor the cast was NOT multiplied by. Change one without the other
	# and the picture silently moves.
	var eye := intro.get("camera") as Camera2D
	_ok(is_equal_approx(eye.zoom.x,
			IntroScene.ZOOM * float(IntroScene.SHIPPED_SCALE) / float(IntroScene.SCALE)),
		"...with the camera zoom corrected so the framing is unchanged (%.3f)" % eye.zoom.x)

	# The procession is not single file. Acts at one altitude could only fill the
	# screen by queueing nose to tail (owner: "I only see one whale going around
	# in the title screen, then it goes away").
	var lanes := {}
	for act in (intro.get("_acts") as Array):
		lanes[roundi(float((act as Dictionary)["base_y"]) / 100.0)] = true
	_ok(lanes.size() >= 4,
		"the cast is spread across altitudes, not single file (%d lanes)" % lanes.size())

	# NOTHING PLAYER-FACING EXISTS HERE. This is the whole reason the intro
	# became its own scene: the leaks it used to have are now unbuildable.
	_ok(not intro.has_method("player_vitals"), "no health readout to leak")
	_ok(not intro.has_method("edge_marker_targets"), "no edge markers to leak")
	_ok(not intro.has_method("interact_prompt"), "no helm prompt to leak")
	_ok(intro.get("player") == null, "and no player at all")
	var hud_found := false
	for node in _walk(intro):
		if node is HudLayer or node is EdgeMarkers or node is DiveHud:
			hud_found = true
	_ok(not hud_found, "no gameplay HUD layer is in the scene")
	# The backdrop IS wanted — it is the sky the whales are in.
	var backdrop := false
	for node in _walk(intro):
		if node is Backdrop:
			backdrop = true
	_ok(backdrop, "the layered sky is behind them")
	_ok(intro.call("backdrop_status") != null, "...and the intro feeds it")

	# The cast is really there, and really frozen (a live hull with lift climbs
	# out of frame inside a minute — the launch deck learned this the hard way).
	var fleet = intro.get("fleet")
	var ships: Array = fleet.ships()
	_ok(ships.size() >= plan.size(), "the cast is on stage (%d bodies)" % ships.size())
	var thawed := 0
	for sh in ships:
		if is_instance_valid(sh) and not sh.freeze:
			thawed += 1
	_ok(thawed == 0, "every body is held, not flying (%d loose)" % thawed)
	var foes := 0
	for sh in ships:
		if is_instance_valid(sh) and sh.faction == 1:
			foes += 1
	_ok(foes >= 1, "there is an enemy in the duel")

	# --- It moves, and it LOOPS ---------------------------------------------
	var cam = intro.get("camera")
	var was: float = cam.global_position.x
	var lead: Ship = ships[0]
	var lead_was: float = lead.global_position.x
	for i in 30:
		await intro.get_tree().physics_frame
	_ok(cam.global_position.x > was, "the camera pans right")
	_ok(lead.global_position.x < lead_was, "...and the cast drifts left past it")

	# Drive it long enough that the first act must have been recycled, and check
	# it went to the BACK rather than off the end of the world. Stepped DIRECTLY
	# with a coarse delta rather than through real frames: the cast is frozen and
	# moved by script, so nothing here needs the solver, and the first hand-over
	# is minutes of screen time away (the pan closes on an act at ~480 px/s at
	# scale 1, against a whale that is itself twenty-five thousand pixels long).
	var tail_before: float = float(intro.get("_tail_x"))
	for i in 600:
		intro.call("_physics_process", 0.5)
	_ok(float(intro.get("_tail_x")) > tail_before,
		"acts are recycled to the back of the queue (the procession never ends)")
	var ahead := 0
	for sh in ships:
		if is_instance_valid(sh) and sh.global_position.x > cam.global_position.x:
			ahead += 1
	_ok(ahead >= 2, "there is always something still to come (%d acts ahead)" % ahead)

	# --- The doors, driven by REAL KEYS -------------------------------------
	# This suite used to call choose_mode() directly, which is exactly the gap
	# that let a crash ship: the _input path a player actually walks was never
	# run. Drive the panel the way a person does — a key to leave the title, then
	# the door — and survive it.
	var panel: TitleScreen = null
	for node in _walk(intro):
		if node is TitleScreen:
			panel = node
	_ok(panel != null, "the intro carries the title panel")
	if panel != null:
		_ok(panel.visible and bool(panel.call("on_title_page")),
			"...showing the title page")
		# Both workshop logs are handed over from the PROFILE at build time — the
		# title has no world and no save, so a missing hand-off is a page that is
		# silently, permanently empty.
		_ok(typeof(panel.get("discovered")) == TYPE_DICTIONARY
				and typeof(panel.get("cards_taken")) == TYPE_DICTIONARY,
			"the intro hands it both profile logs (bestiary + cards)")
		# QUIT IS A DOOR HERE, and Escape is not it: Escape means "back", and
		# there is nothing behind the front page.
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		panel._input(esc)
		_ok(panel.visible and bool(panel.call("on_title_page")),
			"Escape on the title does nothing — it is not the way out")
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		panel._input(enter)
		_ok(panel.visible and not bool(panel.call("on_title_page")),
			"a key leaves the title and shows the doors, choosing nothing")
		_ok(GameMode.pending == GameMode.EXPEDITION,
			"...so the title's own keypress cannot have picked a mode")
		GameMode.pending = GameMode.EXPEDITION
		# The Dive moved to the FRONT of the doors (owner 2026-09-01), so the
		# first key is the Dive now.
		var one := InputEventKey.new()
		one.keycode = KEY_1
		one.pressed = true
		panel._input(one)
		_ok(GameMode.pending == GameMode.DIVE, "[1] chooses the Dive (first door)")
		_ok(is_instance_valid(panel), "...and the panel survives choosing")
	GameMode.pending = GameMode.EXPEDITION

	# --- WHICH SCENE EACH DOOR OPENS ----------------------------------------
	# The routing is a TABLE now (GameMode.scene_for) rather than a chain of
	# special cases inside choose_mode, which is the only reason it can be
	# asserted at all: a headless suite cannot change scenes to find out.
	_ok(GameMode.scene_for(GameMode.DIVE) == "res://maps/dive/dive.tscn",
		"THE DIVE opens its OWN scene, not the expedition's world with a flag")
	_ok(GameMode.scene_for(GameMode.EXPEDITION) == "res://maps/world/world.tscn"
			and GameMode.scene_for(GameMode.SANDBOX) == "res://maps/world/world.tscn",
		"...while the expedition and the sandbox share the world scene")
	_ok(GameMode.scene_for(GameMode.MAPROOM) == "res://maps/maproom/map_room.tscn",
		"the MAP ROOM is a screen off the workshop door")
	_ok(GameMode.scene_for(GameMode.BUILDER) == "res://maps/editor/ship_editor.tscn",
		"...as the drafting table already was")
	_ok(FileAccess.file_exists("res://maps/dive/dive.tscn")
			and FileAccess.file_exists("res://maps/maproom/map_room.tscn"),
		"...and both of those scenes are really on disk")
	_ok(GameMode.is_known(GameMode.MAPROOM) and GameMode.is_screen(GameMode.MAPROOM)
			and GameMode.is_screen(GameMode.BUILDER),
		"the screens are known doors, and known to be screens")
	_ok(not GameMode.is_screen(GameMode.DIVE)
			and not GameMode.is_screen(GameMode.EXPEDITION),
		"...and the worlds are not, so they still carry a pending choice")

	# A panel with no owner must complain, not crash and not silently do nothing.
	var orphan := TitleScreen.new()
	root.add_child(orphan)
	orphan.open()

	# THE WORKSHOP'S DOORS ARE REALLY THERE. A routing table nothing links to is
	# a room with no door, which is how a shipped tool stays invisible.
	orphan.call("_go", TitleScreen.Page.WORKSHOP)
	var doors: Array = []
	for node in _walk(orphan):
		if node is Button:
			doors.append((node as Button).text.strip_edges())
	_ok(doors.has("MAP ROOM"), "the WORKSHOP page offers the MAP ROOM (%s)"
		% ", ".join(PackedStringArray(doors)))
	_ok(doors.has("SHIP BUILDER") and doors.has("BESTIARY"),
		"...alongside the rooms that were already there")
	_ok(doors.has("CARD CODEX"), "...and the card gallery's door")

	# --- THE CARD GALLERY (owner 2026-09-01) --------------------------------
	# "The card screen from the title should display the individual known cards
	# based on what the user has selected. I'd like to see them as cards not as a
	# wall of text." So the page is TILES, one per card in the deck, and the ones
	# actually drafted are lit. A headless run cannot see a drawn tile, so the
	# panel hands its tiles over as rows (TitleScreen.card_tiles).
	orphan.set("cards_taken", {})
	orphan.call("_go", TitleScreen.Page.CARDS)
	var tiles: Array = orphan.call("card_tiles")
	_ok(tiles.size() == DiveCards.CATALOG.size(),
		"the CARDS page builds one tile per card in the deck (%d of %d)"
			% [tiles.size(), DiveCards.CATALOG.size()])
	var tile_ids := {}
	var lit := 0
	for t in tiles:
		tile_ids[String((t as Dictionary)["id"])] = true
		if bool((t as Dictionary)["taken"]):
			lit += 1
	_ok(tile_ids.size() == tiles.size(), "...each one a distinct card")
	_ok(lit == 0, "with an empty log every tile is dimmed, none lit (%d lit)" % lit)
	# A tile is not a wall of text: the page must really be built out of panels,
	# not one Label carrying the codex.
	var codex_wall := false
	for node in _walk(orphan):
		if node is Label and (node as Label).text.contains("Honed Edge") \
				and (node as Label).text.contains("Cluster Shells"):
			codex_wall = true
	_ok(not codex_wall, "the page is tiles, not one Label holding the whole codex")
	# ...and the whole deck has to fit a 720p window, so the grid lives in a scroll box.
	var scrolled := false
	for node in _walk(orphan):
		if node is ScrollContainer:
			scrolled = true
	_ok(scrolled, "the gallery scrolls, so the deck cannot run off a 720p screen")
	# THE TAKEN SET LIGHTS TILES. This is the whole feature: what YOU drafted.
	orphan.set("cards_taken", {"heavy_shells": true})
	orphan.call("_go", TitleScreen.Page.CARDS)
	var relit: Array = orphan.call("card_tiles")
	var lit_ids: Array = []
	for t in relit:
		if bool((t as Dictionary)["taken"]):
			lit_ids.append(String((t as Dictionary)["id"]))
	_ok(lit_ids == ["heavy_shells"],
		"a taken card lights exactly its own tile (%s)" % ", ".join(PackedStringArray(lit_ids)))
	_ok(relit.size() == DiveCards.CATALOG.size(),
		"...and the rest of the deck is still shown, dimmed, not hidden")
	# Escape still walks back out of the page.
	var back_key := InputEventKey.new()
	back_key.keycode = KEY_ESCAPE
	back_key.pressed = true
	orphan._input(back_key)
	_ok(int(orphan.get("page")) == TitleScreen.Page.WORKSHOP,
		"Escape backs the gallery out to the workshop")
	orphan.call("_go", TitleScreen.Page.TITLE)
	# A STRAY KEY DOES NOTHING (owner 2026-08-31: "no need to force 'any key'
	# to do things") — only the quiet conventions act.
	var stray := InputEventKey.new()
	stray.keycode = KEY_X
	stray.pressed = true
	orphan._input(stray)
	_ok(bool(orphan.call("on_title_page")),
		"a stray key on the title does nothing at all")
	var go := InputEventKey.new()
	go.keycode = KEY_ENTER
	go.pressed = true
	orphan._input(go)           # title page -> modes (Enter, the one way in)
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	orphan._input(key)          # modes -> choose, with nobody to tell
	_ok(is_instance_valid(orphan), "a panel with no owner does not take the game down")
	_ok(orphan.visible, "...and stays up rather than vanishing into nothing")
	orphan.queue_free()
	await process_frame

	# --- The handover ---------------------------------------------------------
	# The whole point of the scene split is that the intro picks and the WORLD
	# opens in what was picked. Boot the real world with a choice pending and
	# check it landed — this is the seam that replaced the in-world chooser, and
	# nothing else in the suite crosses it.
	intro.queue_free()
	await process_frame
	GameMode.pending = GameMode.DIVE
	var world_scene: PackedScene = load("res://maps/world/world.tscn")
	var world: Node = world_scene.instantiate()
	root.add_child(world)
	for i in 30:
		await process_frame
	_ok(world.get("dive") != null,
		"the world opens in the mode the intro chose")
	_ok(GameMode.pending == GameMode.EXPEDITION,
		"...and the choice is consumed, so a reset does not re-enter it")
	world.queue_free()
	await process_frame

	_finish()


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _finish() -> void:
	if failures == 0:
		print("\nINTRO: PASS")
		quit(0)
	else:
		print("\nINTRO: FAIL — %d problem(s)" % failures)
		quit(1)
