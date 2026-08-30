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
		var three := InputEventKey.new()
		three.keycode = KEY_3
		three.pressed = true
		panel._input(three)
		_ok(GameMode.pending == GameMode.DIVE, "[3] chooses the Dive")
		_ok(is_instance_valid(panel), "...and the panel survives choosing")
	GameMode.pending = GameMode.EXPEDITION

	# A panel with no owner must complain, not crash and not silently do nothing.
	var orphan := TitleScreen.new()
	root.add_child(orphan)
	orphan.open()
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	orphan._input(key)          # title page -> modes
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
