extends SceneTree

## Headless AGED-WORLD probe (the 3-FPS thread, 2026-08-25).
##
## The owner's F3 capture said the frame is the PHYSICS step, but a FRESH
## headless world costs ~1 ms/tick and never exceeds a handful of broadphase
## pairs. So the expensive ingredient is something a PLAYED session
## ACCUMULATES and a fresh one lacks. This probe ages a world on purpose, one
## accumulation at a time, and measures after each.
##
## TWO CORRECTIONS THIS PROBE IS BUILT ON.
##
## 1. `contacts=0` in the capture does NOT mean nothing was touching. That
##    field is `ship.get_colliding_bodies().size()` written on WHALE rows only
##    (`WhaleDiag.capture_frame`), so it says the whales were clear — nothing
##    about the player's hull, a carcass, or terrain. The penetration cliff was
##    ruled out on a whale-only signal.
## 2. Mining terrain with NO BODY NEARBY is free. Measured first: 702 dug cells
##    took the world's greedy terrain colliders from 51 rects to 1,333 and cost
##    +0.06 ms/tick, because a static shape that pairs with nothing costs
##    nothing. FRAGMENTATION ONLY BILLS WHERE A BODY IS. That is why the stages
##    below land bodies on the ground FIRST and then mine around them.
##
## MEASURING HONESTLY. Two traps, both already paid for:
##   * `Performance.TIME_PHYSICS_PROCESS` is meaningless headless (it has
##     reported values that ROSE as load was removed).
##   * At 60 Hz the main loop is PACED, so wall-clock per physics frame reads
##     ~16.6 ms whatever the load is.
## So the tick rate is raised to saturate the loop: at TICK_HZ the budget per
## step is 1000/TICK_HZ ms, and wall-clock per step above that floor is real
## work. The floor is printed with every row — the first run of this probe read
## the floor in EVERY stage (480 Hz, 2.08 ms), which says the loop was never
## saturated, not that the stages cost the same.
##
##   godot --headless --path . --script tools/aged_world_probe.gd

## 2000 Hz -> a 0.50 ms floor, under the cheapest thing worth seeing.
const TICK_HZ := 2000
const SAMPLE := 800
const SETTLE := 60

## Aging doses.
const LANDED := 6
const DIG_ROUNDS := 3
const DIG_PER_ROUND := 700
const SHOTS := 40


func _initialize() -> void:
	var world: Node = (load("res://maps/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame

	var terrain = world.get("terrain")
	print("subdiv %d   cell %.1f px   chunk %d cells" % [
		terrain.subdiv, terrain.cell_px(), Terrain.CHUNK])
	print("floor at %d Hz = %.2f ms/tick; a row AT the floor is UNLOADED\n"
		% [TICK_HZ, 1000.0 / TICK_HZ])
	_header()

	await _measure(world, "0. fresh world")

	# --- 1. bodies on the ground -----------------------------------------
	# A carcass is the expensive body shape: a dead creature drops off the
	# single coarse box onto the EXACT per-cell collider, so every kill
	# converts a cheap body into an expensive one, permanently. Landed, not
	# hovering: a wreck on an island is what a played session leaves behind.
	var landed: Array = await _land_bodies(world, terrain, LANDED)
	await _measure(world, "1. %d carcasses landed" % landed.size())

	# --- 2..N. mine the ground they are standing on -----------------------
	# The dose-response run. If fragmentation under a body is the bill, this
	# is where it appears, and it should grow with every round.
	var total := 0
	for r in DIG_ROUNDS:
		total += _dig_around(terrain, landed, DIG_PER_ROUND)
		terrain.flush_rebuilds()
		await _measure(world, "%d. +%d dug under them" % [r + 2, total])

	# --- N+1. swiss-cheese the bodies themselves --------------------------
	# The suspect the census's `worst` column was built to name. A carcass is
	# on the EXACT per-cell greedy merge, so a corpse that has been harvested
	# (or a hull that has been shot up) merges into hundreds of shapes instead
	# of tens — and it is DYNAMIC, resting on the fragmented ground above.
	# Shapes multiply against terrain rects in the broadphase, so this is the
	# one accumulation that can bill superlinearly with only 11 ships in play.
	var holes := _cheese_bodies(landed, 0.12)
	await _measure(world, "%d. +%d holes in the bodies" % [DIG_ROUNDS + 2, holes])
	_what_if_sealed(landed)

	# --- last. shots in flight -------------------------------------------
	var player = world.get("player")
	var at: Vector2 = player.global_position if player != null else Vector2.ZERO
	for i in SHOTS:
		world.call("_spawn_shot", at + Vector2(0, -400), at + Vector2(6000, -400),
			1200.0, 4.0, 9, 1.0)
	await _measure(world, "%d. +%d shots" % [DIG_ROUNDS + 3, SHOTS])

	# --- last+1. the SAME bodies, alone in empty sky ----------------------
	# The decisive split. If the bill is BROADPHASE PAIRS, lifting the holed
	# bodies away from all terrain drops it back to the intact number. If the
	# bill is PER-SHAPE (every shape's AABB re-inserted every step for a
	# moving body), it follows them into empty sky and the fix has to be the
	# shape COUNT, not the neighbourhood.
	for b in landed:
		if is_instance_valid(b):
			var ship := b as Ship
			ship.global_position += Vector2(0, -60000.0)
			ship.gravity_scale = 0.0
			ship.linear_velocity = Vector2.ZERO
	await _measure(world, "%d. holed, in empty sky" % [DIG_ROUNDS + 4])

	quit(0)


func _header() -> void:
	print("%-26s %9s %8s %9s %7s %6s %7s %9s %6s" % [
		"stage", "ms/tick", "pairs", "contacts", "active", "ships",
		"shapes", "chunkrect", "worst"])


func _measure(world: Node, label: String) -> void:
	for i in SETTLE:
		await physics_frame
	Engine.physics_ticks_per_second = TICK_HZ
	for i in 30:
		await physics_frame  # settle at the new rate before the clock starts
	var t0 := Time.get_ticks_usec()
	var pairs := 0.0
	var active := 0.0
	for i in SAMPLE:
		await physics_frame
		pairs += Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
		active += Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
	var per_tick := (Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE
	Engine.physics_ticks_per_second = 60

	var c := PhysicsCensus.of_world(world)
	var ships := 0
	var contacts := 0
	var fleet = world.get("fleet")
	if fleet != null:
		var list: Array = fleet.call("ships")
		ships = list.size()
		for s in list:
			if is_instance_valid(s):
				contacts += (s as Ship).get_colliding_bodies().size()
	print("%-26s %9.2f %8.0f %9d %7.0f %6d %7d %9d %6d" % [
		label, per_tick, pairs / SAMPLE, contacts, active / SAMPLE, ships,
		c["shapes"], _chunk_rects(world), c["worst"]])


## Remove `frac` of every body's cells at random and re-derive. Returns how
## many cells actually went. `remove_block(cell, false)` defers the rebuild so
## a body pays ONE merge for its whole dose, the way the batched edit verbs do.
func _cheese_bodies(bodies: Array, frac: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var gone := 0
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var ship := b as Ship
		var cells: Array = ship.blocks.keys()
		for cell in cells:
			if rng.randf() < frac:
				ship.remove_block(cell, false)
				gone += 1
		ship.rebuild()
	return gone


## Static collider rects across every promoted chunk — what the greedy merge
## collapses a solid slab into, and what mining blows apart.
func _chunk_rects(world: Node) -> int:
	var terrain = world.get("terrain")
	var n := 0
	if terrain != null:
		for c in (terrain as Node).get_children():
			if c is TerrainChunk:
				n += (c as TerrainChunk)._collider_rects.size()
	return n


## Drop `n` carcasses onto the terrain surface and let them come to rest.
## Returns the bodies that actually landed.
func _land_bodies(world: Node, terrain, n: int) -> Array:
	var spots := _surface_spots(terrain, n)
	var out: Array = []
	for p in spots:
		var body = world.call("debug_spawn", "carcass", p + Vector2(0, -900.0))
		if body != null:
			out.append(body)
		for f in 10:
			await process_frame
	for f in 180:  # fall + settle
		await physics_frame
	return out


## Up to `n` world positions on top of solid ground, spread across the
## promoted chunks that actually hold terrain.
func _surface_spots(terrain, n: int) -> Array:
	var coords: Array = []
	for c in (terrain as Node).get_children():
		if c is TerrainChunk and (c as TerrainChunk).collider_cell_count() > 0:
			coords.append((c as TerrainChunk).chunk_coord)
	coords.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	var out: Array = []
	for coord in coords:
		if out.size() >= n:
			break
		var cx: int = coord.x * Terrain.CHUNK + Terrain.CHUNK / 2
		for dy in Terrain.CHUNK:
			var cell := Vector2i(cx, coord.y * Terrain.CHUNK + dy)
			if terrain.is_solid(cell):
				out.append(terrain.cell_center(cell) + Vector2(0, -terrain.cell_px()))
				break
	return out


var _dig_round := 0


## Punch `want` random single-cell holes through the chunks the landed bodies
## are sitting in (and their neighbours) — the swiss cheese a session mines
## into the ground it is standing on. Returns how many removed something.
func _dig_around(terrain, bodies: Array, want: int) -> int:
	var rng := RandomNumberGenerator.new()
	# A fresh stream per round -- one seed for all of them re-dug the same
	# already-empty cells and reported the same dose three times.
	rng.seed = 20260825 + _dig_round
	_dig_round += 1
	var coords: Array = []
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var home: Vector2i = terrain.chunk_of_cell(
			terrain.world_to_cell((b as Node2D).global_position))
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				coords.append(home + Vector2i(dx, dy))
	if coords.is_empty():
		return 0
	var hit := 0
	for i in want:
		var coord: Vector2i = coords[rng.randi_range(0, coords.size() - 1)]
		var cell := Vector2i(
			coord.x * Terrain.CHUNK + rng.randi_range(0, Terrain.CHUNK - 1),
			coord.y * Terrain.CHUNK + rng.randi_range(0, Terrain.CHUNK - 1))
		if terrain.dig(cell) != TerrainDB.Type.AIR:
			hit += 1
	return hit


## WHAT-IF, counted not guessed: how many shapes would survive if the collider
## FILLED the body's sealed interior pockets before merging? An air cell that
## cannot be reached from outside the body is a cavity nothing can touch
## without first destroying hull, so covering it changes no silhouette and no
## reachable surface -- but it re-joins the long runs the greedy merge lives
## on. Pure arithmetic here; nothing is applied.
func _what_if_sealed(bodies: Array) -> void:
	print("
  what-if: sealing interior pockets before the merge")
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var ship := b as Ship
		var solid := {}
		for cell in ship.blocks:
			if BlockDB.get_def(ship.blocks[cell]["type"])["solid"]:
				solid[cell] = true
		if solid.is_empty():
			continue
		var exact: int = Ship._greedy_rects(solid.duplicate()).size()
		var sealed := _seal(solid)
		var filled: int = Ship._greedy_rects(sealed.duplicate()).size()
		print("    %5d solid cells   exact %5d rects -> sealed %5d rects  (+%d cells)"
			% [solid.size(), exact, filled, sealed.size() - solid.size()])


## The solid set plus every air cell inside its bounding box that cannot be
## reached from outside (4-connected flood from a one-cell margin).
func _seal(solid: Dictionary) -> Dictionary:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in solid:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var outside := {}
	var queue: Array[Vector2i] = [lo]
	outside[lo] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y:
				continue
			if outside.has(n) or solid.has(n):
				continue
			outside[n] = true
			queue.push_back(n)
	var out := solid.duplicate()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not solid.has(c) and not outside.has(c):
				out[c] = true
	return out
