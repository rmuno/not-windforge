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
## takes at ship speed, how many PICKETS a depth actually puts in your way now
## that the timer surge is retired (v0.141.0) and a depth's garrison is
## `surge_count(d)` around its landing column, whether a run fits the owner's
## ten minutes.
##
## Names no `class_name` as a type on purpose: doing that inside a --script file
## compiles that script before the autoloads exist (CODEMAP §4).

const STEP := 1.0 / 60.0

var world: Node
var fleet
var pl

# Combat scorecard tallies (Q-O). `_seen_shots` tracks Shot instance ids so a
# shell is counted once at birth; faction 1 = hostile fire.
var hits_taken := 0
var damage_taken := 0.0
var _seen_shots := {}
var enemy_shots := 0

# --- THE KRAKEN SCORECARD (DESIGN_KRAKEN §7 slice 2) -----------------------
# "Every later round tunes against them": four numbers the deep has never been
# measured by. All four are read off the LIVE brains and bodies, so they answer
# for what the fight did, not for what the spawn tables intended.
#
#   * TIME TO FIRST CONTACT — entering a depth, to the first frame a kraken has
#     hold of you or is standing on your hull. Infinite at every depth is the
#     bug this whole slice is about (designer C's arithmetic: the old
#     horizontal-only heave cannot reach a hull that is falling).
#   * GRABS — rising edges of `KrakenAI.grabbing`, per minute, longest hold.
#   * INTEGRITY LOST TO KRAKENS — the grab's drain and the ram's bruise, split
#     out of the total by "was a kraken on us this frame".
#   * CULLED ALIVE — krakens the wake cull FREED while they still had a pool.
#     Measured from outside `_dive_cull_the_wake` on purpose (a body that
#     vanishes with health left was deleted, not killed), so this line reads
#     the same before and after that function is ever touched.
var kraken_first_contact := {}     ## depth -> seconds from entering it
var kraken_contact_frames := 0
var kraken_grabs := 0
var kraken_grab_frames := 0
var kraken_hold := 0.0
var kraken_longest_hold := 0.0
var kraken_damage := 0.0
var krakens_culled_alive := 0
var krakens_perished := 0
## instance id -> the last pool we saw it with. A kraken that leaves this list
## without its pool having reached zero was freed alive.
var _kraken_pools := {}
var _kraken_grabbing := {}
## True while a kraken is grabbing us or in contact with our hull — the
## attribution the `damaged` handler reads (designer C's own fallback: "else by
## 'a mouth was in reach this frame'").
var _kraken_on_us := false


## Is this body one of the deep's hunters? Matches the Leviathan too, whatever
## the concurrent slice ends up calling it, without needing its name here.
func _is_kraken(s) -> bool:
	return String(s.get("creature_kind")).begins_with("kraken")


## One frame of the kraken scorecard: who is alive, who has hold of us, who
## disappeared while still alive.
func _tally_krakens(t: float, depth: int, depth_started: float) -> void:
	var hull = world.get("local_ship")
	var brains: Dictionary = world.get("_whale_ais")
	var touching := {}
	if hull != null and is_instance_valid(hull):
		for body in hull.get_colliding_bodies():
			touching[body.get_instance_id()] = true
	var live := {}
	var on_us := false
	var holding := false
	for s in fleet.ships():
		if not is_instance_valid(s) or not _is_kraken(s):
			continue
		var id: int = s.get_instance_id()
		live[id] = true
		_kraken_pools[id] = float(s.get("shared_health"))
		if float(s.get("shared_health")) <= 0.0:
			continue   # a carcass neither grabs nor counts as a hunter
		var ai = brains.get(id)
		var grabbing: bool = ai != null and (bool(ai.get("grabbing"))
			or bool(ai.get("grabbing_player")))
		if grabbing:
			holding = true
			if not bool(_kraken_grabbing.get(id, false)):
				kraken_grabs += 1
		_kraken_grabbing[id] = grabbing
		if grabbing or touching.has(id):
			on_us = true
	# Anything that was in the books last frame and is not alive now: killed if
	# its pool had emptied, FREED BY THE CULL if it had not.
	for id in _kraken_pools.keys():
		if live.has(id):
			continue
		if float(_kraken_pools[id]) > 0.0:
			krakens_culled_alive += 1
		else:
			krakens_perished += 1
		_kraken_pools.erase(id)
		_kraken_grabbing.erase(id)
	_kraken_on_us = on_us
	if holding:
		kraken_grab_frames += 1
		kraken_hold += STEP
		kraken_longest_hold = maxf(kraken_longest_hold, kraken_hold)
	else:
		kraken_hold = 0.0
	if on_us:
		kraken_contact_frames += 1
		if not kraken_first_contact.has(depth):
			kraken_first_contact[depth] = t - depth_started


## Count NEW hostile shells this frame. The shots group is small (live shells
## only), so the per-frame scan is cheap.
func _count_enemy_fire() -> void:
	for node in world.get_tree().get_nodes_in_group("shots"):
		var id := node.get_instance_id()
		if _seen_shots.has(id):
			continue
		_seen_shots[id] = true
		if int(node.get("faction")) == 1:
			enemy_shots += 1


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
	print("GEAR:   %s" % _gear(world.get("local_ship")))
	# THE COMBAT SCORECARD (Q-O, measure first): every hit that lands on OUR
	# hull, counted and summed off the ship's own damaged signal — the number
	# enemy-shell-speed tuning has to answer to.
	var hull_now = world.get("local_ship")
	if hull_now != null and is_instance_valid(hull_now):
		hull_now.damaged.connect(func(_cell: Vector2i, amount: float) -> void:
			hits_taken += 1
			damage_taken += amount
			# ...and how much of it the deep took. `_kraken_on_us` is stamped
			# once a frame by `_tally_krakens`, which is the only attribution
			# the ram bruise admits of: a collision carries no shooter id.
			if _kraken_on_us:
				kraken_damage += amount)

	# --- Shop, the way a player who found an outpost would -----------------
	# Depths 6-8 are below Airspace.DEEP_TOP, so a run without a Lung dies at
	# the gate (this probe proved that). Buy one through the REAL counter so the
	# rest of the descent measures the game a prepared player actually plays.
	var run0 = world.get("dive")
	run0.pot = 600
	world.call("_plant_outpost", pl.global_position)
	var bought: bool = world.call("try_buy_stock", 0)
	print("bought a Lung at the counter: %s   (pot now %d)" % [str(bought),
		int(run0.get("pot"))])

	# --- Fly DOWN, holding the dive, and log every rung ---------------------
	var t := 0.0
	var last_depth := 1
	var depth_started := 0.0
	var log_lines: Array[String] = []
	var closest := INF
	var engaged := 0
	## Hostile instance id -> the depth it first came within engagement range at,
	## and the tally per depth. See the booking site in the loop below.
	var met_ids := {}
	var met_by_depth := {}
	var hp0 := 0.0
	var hull0 = world.get("local_ship")
	if hull0 != null and is_instance_valid(hull0):
		hp0 = float(hull0.blocks.size())
	# FLY THE LADDER, DO NOT JUST FALL DOWN IT. The descent is a SLALOM — every
	# rung is a solid slab about two hulls wide, laid a sidestep off the one
	# above — so a pilot who only holds DOWN eventually rests on a rung's corner
	# and stops. That is not a bug and this probe used to report it as one: it
	# stalled at depth 2, 3 and 4 on three different seeds, each time with a few
	# hundred px of hull on a slab edge. A player reads the edge marker at the
	# next landing and steers; so does this now, which is what makes the seconds-
	# per-depth numbers below mean anything.
	Input.action_press("ship_down")
	var steer := 0
	var guard := 0
	var beat := 0.0
	# THE UNSTICK (2026-08-31, diagnosed by the gear line): the hull kept
	# stalling on a landing slab WITH full thrust available — holding DOWN pins
	# it to the slab and lateral thrust never breaks the pin, while the moment
	# the climb phase released DOWN it came free at once. A person lets go of
	# the stick and slides off; this pilot never did, so seven of the eight
	# probe minutes measured a keyboard habit, not the game. Now: stuck for
	# 3 s -> release DOWN (steer keeps running) until moving again, then dive on.
	var stuck_t := 0.0
	var unsticking := false
	while guard < 60 * 60 * 8:    # 8 simulated minutes, hard stop
		guard += 1
		await world.get_tree().physics_frame
		t += STEP
		var run = world.get("dive")
		if run == null or String(run.get("outcome")) != "":
			break
		var d := int(run.get("depth"))
		var helm0 = world.get("local_ship")
		var moving: bool = helm0 != null and is_instance_valid(helm0) \
			and helm0.linear_velocity.length() > 60.0 * 8.0
		if moving:
			stuck_t = 0.0
			if unsticking:
				unsticking = false
				Input.action_press("ship_down")
		else:
			stuck_t += STEP
			if stuck_t > 3.0 and not unsticking:
				unsticking = true
				Input.action_release("ship_down")
		# Steer toward the rung below, the way the edge marker points.
		var helm = world.get("local_ship")
		var want := 0
		if helm != null and is_instance_valid(helm) and d < 8:
			var aim: Vector2 = world.call("dive_landing_pos", d + 1)
			var off: float = aim.x - helm.global_position.x
			if absf(off) > helm.solid_bounds.size.x * 0.5:
				want = 1 if off > 0.0 else -1
		if want != steer:
			if steer != 0:
				Input.action_release("ship_right" if steer > 0 else "ship_left")
			if want != 0:
				Input.action_press("ship_right" if want > 0 else "ship_left")
			steer = want
		if d != last_depth:
			log_lines.append("  depth %d -> %d after %5.1f s   (pot %d, kills %d, surges %d)"
				% [last_depth, d, t - depth_started, int(run.get("pot")),
					int(run.get("kills")), int(run.get("surges"))])
			last_depth = d
			depth_started = t
		_count_enemy_fire()
		_tally_krakens(t, d, depth_started)
		# THREAT: did anything actually reach us? A garrison you never met is
		# a spawn count, not a fight.
		for sh in fleet.ships():
			if not is_instance_valid(sh) or sh.faction == 0 or sh.is_carcass():
				continue
			var dd: float = sh.global_position.distance_to(pl.global_position)
			closest = minf(closest, dd)
			if dd < 4000.0 * 8.0:
				engaged += 1
				# PICKETS MET PER DEPTH (v0.141.0). With the timer surge retired,
				# "how many did the sky actually put in your way" is THE pacing
				# number, and it is a count of BODIES, not of events. Each
				# hostile is booked once, at the depth where it first closed.
				var hid: int = sh.get_instance_id()
				if not met_ids.has(hid):
					met_ids[hid] = d
					met_by_depth[d] = int(met_by_depth.get(d, 0)) + 1
		beat += STEP
		if beat >= 30.0:
			beat = 0.0
			var hull2 = world.get("local_ship")
			print("   t=%5.1f  depth %d  y %.0f  vy %.0f  blocks %d  [%s]" % [t, d,
				pl.global_position.y,
				0.0 if hull2 == null or not is_instance_valid(hull2) else hull2.linear_velocity.y,
				0 if hull2 == null or not is_instance_valid(hull2) else hull2.blocks.size(),
				_gear(hull2)])
		if d >= 8:
			break
	Input.action_release("ship_down")
	if steer != 0:
		Input.action_release("ship_right" if steer > 0 else "ship_left")

	var hull1 = world.get("local_ship")
	var hp1 := 0.0
	if hull1 != null and is_instance_valid(hull1):
		hp1 = float(hull1.blocks.size())
	print("\nTHREAT: nearest hostile ever %.0f px | frames with one within 4k*8: %d"
		% [closest, engaged])
	# THE GARRISON, AS MET (v0.141.0). The model says a depth is worth
	# `DiveRun.surge_count(d)` pickets around its landing column; this is how many
	# of them a real descent actually flew into.
	var met_line := ""
	var met_total := 0
	for dd2 in range(1, 9):
		var got := int(met_by_depth.get(dd2, 0))
		met_total += got
		met_line += "d%d:%d " % [dd2, got]
	print("PICKETS MET: %s| total %d distinct hostiles" % [met_line, met_total])
	# THE COMBAT SCORECARD (Q-O): what the fight actually did, in numbers.
	# Per-picket, not per-surge: the surge timer is retired, so the denominator
	# that means something is how many hostiles actually reached us.
	var per_n := maxi(met_total, 1)
	var hull3 = world.get("local_ship")
	var integ := "unarmed"
	if hull3 != null and is_instance_valid(hull3) and hull3.hull_integrity_max > 0.0:
		integ = "%.0f/%.0f" % [hull3.hull_integrity, hull3.hull_integrity_max]
	print("COMBAT: enemy shells fired %d | hits on us %d (%.0f%% of shells) | damage %.0f (%.0f per picket met) | integrity %s"
		% [enemy_shots, hits_taken,
			(100.0 * float(hits_taken) / float(maxi(enemy_shots, 1))),
			damage_taken, damage_taken / float(per_n), integ])
	# THE KRAKEN SCORECARD (DESIGN_KRAKEN §7 slice 2). Targets, from the design:
	# first contact under 25 s at d4-d7, 1.5-3 grabs a minute, krakens taking
	# 15-25 % of the 3,000 integrity pool over a descent, and culled-alive 0.
	var ttc := ""
	for dd in range(1, 9):
		ttc += "d%d:%s " % [dd, ("%.1f" % float(kraken_first_contact[dd]))
			if kraken_first_contact.has(dd) else "-"]
	var mins := maxf(t / 60.0, 0.001)
	print("KRAKEN CONTACT: %s| %.1f s of contact in %.0f s of diving" % [ttc,
		float(kraken_contact_frames) * STEP, t])
	print("KRAKEN GRABS:   %d | %.2f per minute | held %.1f s total, longest %.1f s"
		% [kraken_grabs, float(kraken_grabs) / mins,
			float(kraken_grab_frames) * STEP, kraken_longest_hold])
	print("KRAKEN BILL:    %.0f of %.0f damage taken (%.0f%%) | %d killed | %d CULLED ALIVE"
		% [kraken_damage, damage_taken,
			100.0 * kraken_damage / maxf(damage_taken, 1.0),
			krakens_perished, krakens_culled_alive])
	print("HULL:   %.0f blocks -> %.0f (%.0f lost)" % [hp0, hp1, hp0 - hp1])
	print("GEAR:   %s" % _gear(hull1))
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
		print("GEAR:   %s" % _gear(world.get("local_ship")))
	_report("at the end")
	var fin = world.get("dive")
	if fin != null:
		print("LEDGER: %s" % str(fin.call("ledger")))
	quit()


func _frames(n: int) -> void:
	for i in n:
		await world.get_tree().physics_frame


## WHAT CAN THIS HULL STILL DO — the line the stall diagnosis was missing. The
## 2026-08-31 baseline ended with a hull that could neither descend nor CLIMB
## (vy 0 through 480 s of held ship_up) after losing 547 blocks, and nothing in
## the log said WHICH blocks: a wedge and a hull whose engines were shot off
## print identically without this. Thrust totals are the authority that actually
## moves a ship; the counts say what the pickets ate.
func _gear(hull) -> String:
	if hull == null or not is_instance_valid(hull):
		return "no hull"
	var props := 0
	var engines := 0
	var turrets := 0
	for cell in hull.blocks:
		match int(hull.blocks[cell]["type"]):
			BlockDB.Type.PROPELLER: props += 1
			BlockDB.Type.ENGINE: engines += 1
			BlockDB.Type.TURRET: turrets += 1
	return "thrust h=%.0f v=%.0f | props %d engines %d turrets %d | power %.0f vs draw %.0f" % [
		hull.get("_total_hthrust"), hull.get("_total_vthrust"),
		props, engines, turrets,
		hull.power_supply(), hull.active_draw()]


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
