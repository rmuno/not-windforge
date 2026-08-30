extends SceneTree

## THE LAUNCH DECK, WALKED. A headless probe of the one thing the unit suite
## cannot see: whether S+jump through a hatch actually PUTS YOU ON THE SHIP.
##
##   godot --headless --path . --script tools/deck_probe.gd
##
## It starts a run on the real 8× scene, then for every berth in
## ships/dive_deck.ship drops the body through the hatch twice — once from the
## middle, once from the lip — and reports how far it fell, how fast, and
## whether it landed on the hull.
##
## WHY IT EXISTS. The owner played v0.99.0 and reported *"player drops like a
## METEOR when getting on the ship"*. The cause was arithmetic no test was
## checking: ships/starter.ship is NATIVE 8× and ships/loft_test.ship is
## upscaled 8×, and the deck had been authored as though both were upscaled — so
## the starter's berth was 14,080 px wide for a 1,536 px hull and stepping off
## its edge dropped you a whole screen clear of the ship. This probe prints the
## difference in one line: 584 px onto the hull, or 38,000 px past it.
##
## A PROBE, not a test: it measures, it does not assert. The invariant it taught
## us (a hatch is hull + exactly BERTH_BUFFER_CELLS) is pinned in the unit suite.
##
## Names no `class_name` as a type on purpose: doing that inside a --script file
## compiles that script before the autoloads exist (CODEMAP §4).

const STEP := 1.0 / 60.0
var world: Node
var pl

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	world = packed.instantiate()
	root.add_child(world)
	await _frames(40)
	pl = world.get("player")
	world.call("begin_dive")
	await _frames(10)
	var berths: Array = world.call("dive_berth_positions")
	print("berths: %d" % berths.size())
	for b in berths:
		print("  centre %s  width %.0f" % [str((b as Dictionary)["pos"]), float((b as Dictionary)["width"])])
	print("player on deck: %s" % str(pl.global_position))
	var fleet = world.get("fleet")
	for s in fleet.ships():
		if s.get("is_nest"):
			print("deck ship at %s bounds %s frozen=%s" % [str(s.global_position), str(s.solid_bounds), str(s.freeze)])
		elif s.faction == 0 and s.creature_kind == "":
			print("candidate at %s bounds %s top=%.0f frozen=%s" % [str(s.global_position),
				str(s.solid_bounds), s.global_position.y + s.solid_bounds.position.y, str(s.freeze)])
	var fl = world.get("fleet")
	var deck_y: float = pl.global_position.y
	for bi in berths.size():
		var bx: float = float((berths[bi] as Dictionary)["pos"].x)
		var bw: float = float((berths[bi] as Dictionary)["width"])
		# The hull under this hatch, for the verdict.
		var target = null
		for s2 in fl.ships():
			if s2.get("is_nest") or s2.faction != 0 or s2.creature_kind != "":
				continue
			if absf(s2.global_position.x - bx) < bw:
				target = s2
		# Drop from the MIDDLE of the hatch and from one player-width inside
		# its lip — the lip is where an oversized hatch lets you miss.
		for spot in [0.0, bw * 0.5 - 45.0]:
			pl.global_position = Vector2(bx + spot, pl.global_position.y)
			pl.velocity = Vector2.ZERO
			await _frames(20)
			var y0: float = pl.global_position.y
			var t := 0.0
			var vmax := 0.0
			Input.action_press("move_down")
			Input.action_press("jump")
			await _frames(3)
			Input.action_release("jump")
			var frames := 0
			while frames < 900:
				await process_frame
				frames += 1
				t += 1.0 / 60.0
				vmax = maxf(vmax, absf(pl.velocity.y))
				if frames > 20 and pl.is_on_floor():
					break
			Input.action_release("move_down")
			var on_hull := false
			if target != null and is_instance_valid(target):
				var b = target.solid_bounds
				var lp = target.to_local(pl.global_position)
				on_hull = lp.x > b.position.x and lp.x < b.end.x 					and absf(lp.y - b.position.y) < 400.0
			print("  hatch %d, %+.0f px off centre: fell %.0f px in %.2f s, peak |vy| %.0f, landed=%s ON THE HULL=%s"
				% [bi, spot, pl.global_position.y - y0, t, vmax,
					str(pl.is_on_floor()), str(on_hull)])
			pl.global_position = Vector2(pl.global_position.x, deck_y)
			pl.velocity = Vector2.ZERO
			await _frames(30)
	quit()
