extends SceneTree

## Headless SKIN probe (lag audit fix 3, phase B follow-up). Answers the two
## questions the sectored skin left open, with numbers instead of argument:
##
##   1. What does a repaint COST, whole-body and per-sector, at each
##      candidate sector size?
##   2. What does sectoring cost in RETAINED DRAW COMMANDS? Greedy region
##      merging stops at a sector boundary, so a smaller tile means more
##      rects -- and the owner's original 22-FPS report was a retained-
##      command problem (~23k across the 8x ships), so this is not free.
##
## Draw calls only exist inside _draw, so the emission itself cannot be timed
## headless. Ship.sector_paint_plan is everything BUT the emission -- the
## grouping scan -- and _greedy_rects turns a group into the rects that would
## be emitted, so rect count is an exact command count, not an estimate.
##
##   godot --headless --path . --script tools/skin_probe.gd

const SIZES := [16, 32, 64, 128, 256]
const REPS := 12


func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	var world: Node = packed.instantiate()
	root.add_child(world)
	for i in 20:
		await process_frame

	var fleet = world.get("fleet")
	var ships: Array = fleet.ships()
	ships.sort_custom(func(a, b): return a.blocks.size() > b.blocks.size())
	print("%d ships in the live world\n" % ships.size())

	for ship in ships:
		if ship.blocks.size() < 200:
			continue  # scenery-sized bodies say nothing about the cost
		_probe(ship)
	quit(0)


func _probe(ship) -> void:
	var n: int = ship.blocks.size()
	print("--- ship %d cells, bounds %s, unit %.0fx ---"
		% [n, str(ship.solid_bounds.size), ship.scale_unit])

	# The pre-phase-B design: ONE canvas item, so a repaint groups the whole
	# body and merges regions across the entire grid. This is the baseline
	# both questions are measured against.
	var t0 := Time.get_ticks_usec()
	var whole := {}
	for r in REPS:
		whole = ship.sector_paint_plan(ship.blocks)
	var whole_ms := (Time.get_ticks_usec() - t0) / 1000.0 / REPS
	var whole_rects := _rects_of(ship, whole)
	print("  single canvas (v0.54.0)   %8.3f ms whole-body   %6d rects"
		% [whole_ms, whole_rects])

	for size in SIZES:
		var parts := _partition(ship.blocks, size)
		# Whole-body repaint = every tile replans (a rebuild, a facing flip,
		# a creature's wound shade). Per-tile = the common single-cell edit.
		var total_ms := 0.0
		var worst_ms := 0.0
		var rects := 0
		for coord in parts:
			var cells: Dictionary = parts[coord]
			var s0 := Time.get_ticks_usec()
			var plan := {}
			for r in REPS:
				plan = ship.sector_paint_plan(cells)
			var ms := (Time.get_ticks_usec() - s0) / 1000.0 / REPS
			total_ms += ms
			worst_ms = maxf(worst_ms, ms)
			rects += _rects_of(ship, plan)
		print("  sector %3d  tiles %4d   whole %8.3f ms   worst tile %7.3f ms   %6d rects (%+.0f%%)"
			% [size, parts.size(), total_ms, worst_ms, rects,
				100.0 * (float(rects) / maxf(1.0, float(whole_rects)) - 1.0)])
	print("")


## Rects a plan would emit -- the retained canvas command count (one filled
## rect + one border per region; a strut region emits one pair per column,
## which _greedy_rects does not know, so this counts REGIONS: the ratio
## between designs is what matters and it is unaffected).
## Base art PLUS the wound overlay — both are rects the canvas item retains.
## Counting only `groups` would flatter the v0.69.1 split, which moved the
## damage shading out of the base merge and into its own pass.
func _rects_of(ship, plan: Dictionary) -> int:
	var n := 0
	for key in plan["groups"]:
		n += ship._greedy_rects(plan["groups"][key]["cells"]).size()
	for shade in plan["wounds"]:
		n += ship._greedy_rects(plan["wounds"][shade]["cells"]).size()
	return n


func _partition(blocks: Dictionary, size: int) -> Dictionary:
	var out := {}
	for cell in blocks:
		var coord := Vector2i(floori(float(cell.x) / size), floori(float(cell.y) / size))
		if not out.has(coord):
			out[coord] = {}
		(out[coord] as Dictionary)[cell] = true
	return out
