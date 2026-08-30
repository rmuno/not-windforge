extends SceneTree

## THE DIVE, PLAYED. A headless playtest of a whole run on the REAL shipped 8x
## scene: start a run on the launch deck, take a hull, fly it down the ladder
## with real input, and report what the run actually felt like in numbers —
## seconds per depth, when the dens attacked, what the pot did, whether the
## hull survived.
##
##   godot --headless --path . --script tools/dive_probe.gd
##
## This is a PROBE, not a test: it measures, it does not assert. The numbers it
## prints are the ones nothing but arithmetic has judged — how long a depth
## takes at ship speed, whether `dive_surge_period` is the right pulse, whether
## a run fits the owner's ten minutes.
##
## Names no `class_name` as a type on purpose: doing that inside a --script file
## compiles that script before the autoloads exist (CODEMAP §4).

const STEP := 1.0 / 60.0

var world: Node
var fleet
var pl


func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	world = packed.instantiate()
	root.add_child(world)
	for i in 40:
		await process_frame
	fleet = world.get("fleet")
	pl = world.get("player")
	print("\n=== THE DIVE — headless playtest (8x, the shipped scene) ===")
	print("boot: %d ships, player at %s" % [fleet.ships().size(), str(pl.global_position)])

	world.call("begin_dive")
	await _frames(10)
	_report("on the launch deck")

	# --- Take a hull, the way a player does: walk to a helm and use it -------
	var hull = _nearest_hull()
	if hull == null:
		print("!! no candidate hull on the deck — a run would have to be shipless")
		return quit()
	pl.global_position = hull.to_global(hull.local_pos_of(hull.helm_cells[0]))
	await _frames(2)
	var took: bool = pl.board(hull, hull.helm_cells[0])
	await _frames(4)
	print("took the helm: %s   committed: %s" % [str(took),
		str((world.get("dive") as Object).get("committed"))])

	# --- Fly DOWN, holding the dive, and log every rung ---------------------
	var t := 0.0
	var last_depth := 1
	var depth_started := 0.0
	var log_lines: Array[String] = []
	Input.action_press("ship_down")
	var guard := 0
	while guard < 60 * 60 * 12:   # 12 simulated minutes, hard stop
		guard += 1
		await world.get_tree().physics_frame
		t += STEP
		var run = world.get("dive")
		if run == null or String(run.get("outcome")) != "":
			break
		var d := int(run.get("depth"))
		if d != last_depth:
			log_lines.append("  depth %d -> %d after %5.1f s   (pot %d, kills %d, surges %d)"
				% [last_depth, d, t - depth_started, int(run.get("pot")),
					int(run.get("kills")), int(run.get("surges"))])
			last_depth = d
			depth_started = t
		if d >= 8:
			break
	Input.action_release("ship_down")

	print("\n--- the descent ---")
	for l in log_lines:
		print(l)
	if log_lines.is_empty():
		print("  never left depth 1 in %.0f s — the ship is not descending" % t)
	_report("after %.0f s of diving" % t)

	# --- Turn around and climb home -----------------------------------------
	var run2 = world.get("dive")
	if run2 != null and String(run2.get("outcome")) == "":
		Input.action_press("ship_up")
		var up := 0.0
		while up < 60.0 * 8.0:
			await world.get_tree().physics_frame
			up += STEP
			if String((world.get("dive") as Object).get("outcome")) != "":
				break
		Input.action_release("ship_up")
		print("\nclimbed for %.0f s" % up)
	_report("at the end")
	var fin = world.get("dive")
	if fin != null:
		print("LEDGER: %s" % str(fin.call("ledger")))
	quit()


func _frames(n: int) -> void:
	for i in n:
		await world.get_tree().physics_frame


func _nearest_hull():
	var best = null
	var bd := INF
	for s in fleet.ships():
		if not is_instance_valid(s) or s.faction != 0 or s.creature_kind != "":
			continue
		if s.is_carcass() or not s.has_helm() or s.helm_cells.is_empty():
			continue
		var d: float = s.global_position.distance_to(pl.global_position)
		if d < bd:
			bd = d
			best = s
	return best


func _report(when: String) -> void:
	var run = world.get("dive")
	var ship = world.get("local_ship")
	var st := "no run"
	if run != null:
		st = "depth %d (deepest %d) pot %d kills %d surges %d  %.0f s" % [
			int(run.get("depth")), int(run.get("deepest")), int(run.get("pot")),
			int(run.get("kills")), int(run.get("surges")), float(run.get("elapsed"))]
	print("%-28s %s | ships %d | hull %s | body y %.0f" % [
		when, st, fleet.ships().size(),
		"none" if ship == null or not is_instance_valid(ship)
			else "%d blocks" % ship.blocks.size(),
		pl.global_position.y if is_instance_valid(pl) else 0.0])
