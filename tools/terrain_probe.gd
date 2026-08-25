extends SceneTree

## Headless perf probe for the terrain-resolution work — generation cost,
## promotion burst cost, streaming cost and resident memory at the shipped grid,
## measured on the SAME code path the live world uses.
##
##   godot --headless --path . --script tools/terrain_probe.gd
##
## LAZY PATH (fixed 2026-08-25): this used to call `IslandGen.generate()`, the
## EAGER whole-world paint the live game stopped using in v0.46.0 — at ×4 extent
## that is a ~25 s stall nobody ever pays, so every number below it was measured
## against a world twice removed from the real one (and the run took minutes).
## It now mirrors `world._build_world` / `world._stream_terrain`: prime the spawn
## floor, burst-generate the spawn neighbourhood, then let regions arrive as the
## foci move — which is also what makes "generate" a per-frame number rather
## than a boot number.
##
## Numbers to watch:
##   * spawn burst: the one bounded burst world build pays before frame one.
##   * promote worst-call: must stay well inside a 16.6 ms frame (amortized
##     PROMOTE_PER_CALL, so this is a couple of greedy merges + node adds).
##   * steady-state update_streaming with everything promoted: the per-frame
##     scan cost of the subdiv-scaled radii.
##   * fast flight: generation AND promotion racing a ram-speed focus.

## The subdivisions worth a look: 1 (legacy coarse), 4 (SHIPPED — the Tunables
## default), 8 (the full-8× the owner walked back from as "WAY too many blocks").
const PROBE_SUBDIVS := [1, 4, 8]

## What world build hands ensure_generated for the spawn neighbourhood
## (maps/world/world.gd — keep in step with it).
const SPAWN_BURST_BUDGET := 64


func _initialize() -> void:
	for sub in PROBE_SUBDIVS:
		_probe(sub)
	quit(0)


func _probe(sub: int) -> void:
	print("\n=== terrain probe @ subdiv %d ===" % sub)
	var t := Terrain.new()
	t.subdiv = sub
	t.scale_unit = 8.0  # the shipped world scale
	root.add_child(t)

	# --- World build: prime the floor, then the one bounded spawn burst ------
	var t0 := Time.get_ticks_usec()
	IslandGen.prime(t)
	var prime_ms := (Time.get_ticks_usec() - t0) / 1000.0

	var focus := t.cell_center(Vector2i(0, 10 * sub))
	t0 = Time.get_ticks_usec()
	var burst_regions := IslandGen.ensure_generated(
		t, IslandGen.DEFAULT_SEED, [focus],
		t.chunk_px() * t.subdiv * 3.0, SPAWN_BURST_BUDGET)
	var burst_ms := (Time.get_ticks_usec() - t0) / 1000.0
	# 0 regions is CORRECT, not a broken burst: IslandGen's SPAWN_CLEAR keep-out
	# leaves the starting neighbourhood as clear sky, and the live world's burst
	# (at SHIP_START) sits inside exactly that hole. The islands arrive as soon
	# as a focus moves off the pad — see the settle/flight numbers below.
	print("world build: prime %.1f ms + spawn burst %.1f ms (%d regions) = %.1f ms"
		% [prime_ms, burst_ms, burst_regions, prime_ms + burst_ms])
	print("resident after build: %9d solid cells   %6d chunks (~%.1f MiB)"
		% [t.total_solid_cells(), t.chunk_coords().size(),
			t.chunk_coords().size() * Terrain.CHUNK * Terrain.CHUNK / 1048576.0])

	# Promotion burst: drop a focus onto the densest spot we can find cheaply
	# (the spawn floor) and drain the promotion queue, timing every call.
	var worst := 0.0
	var total := 0.0
	var calls := 0
	while calls < 2000:
		t0 = Time.get_ticks_usec()
		t.update_streaming([focus])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		calls += 1
		if calls > 4 and ms < 0.05 and t.live_chunk_count() > 0:
			break  # queue drained — everything near the focus is promoted
	print("promotion: %d calls to drain, worst %.2f ms/call, avg %.2f ms   live chunks: %d"
		% [calls, worst, total / calls, t.live_chunk_count()])

	# Steady state: everything promoted, the focus still — pure scan cost.
	t0 = Time.get_ticks_usec()
	for i in 120:
		t.update_streaming([focus])
	print("steady update_streaming: %.3f ms/call" % ((Time.get_ticks_usec() - t0) / 1000.0 / 120.0))

	# THE REAL LOAD (the owner's "so heckin' laggy"): the live world streams for
	# ~15 foci (player + ships + the whale pod + critters + krakens), spread the
	# way the spawn actually spreads them. Measure the per-frame streaming cost
	# and — the render-side proxy — how many live chunk NODES exist at once.
	# Each frame runs generation FIRST, exactly as world._stream_terrain does:
	# the fleet is scattered across ungenerated regions, and that generation is
	# part of what a live frame pays.
	var secondary: Array = []
	for i in 14:
		secondary.append(focus + Vector2(
			(i - 7) * 2600.0 * t.scale_unit / 8.0 * 8.0, (i % 3 - 1) * 1800.0))
	var gen_ms := 0.0
	for i in 900:  # let generation + promotion drain fully for the whole fleet
		t0 = Time.get_ticks_usec()
		IslandGen.ensure_generated(t, IslandGen.DEFAULT_SEED, [focus] + secondary,
			t.chunk_px() * t.subdiv * 2.0)
		gen_ms += (Time.get_ticks_usec() - t0) / 1000.0
		t.update_streaming([focus], secondary)
	print("15-foci settle: %.1f ms of lazy generation over 900 frames" % gen_ms)
	t0 = Time.get_ticks_usec()
	for i in 120:
		t.update_streaming([focus], secondary)
	print("15-foci steady: %.3f ms/call   live chunk NODES: %d"
		% [(Time.get_ticks_usec() - t0) / 1000.0 / 120.0, t.live_chunk_count()])
	# Wiggle one secondary focus every frame (a roaming whale mid-chunk-crossing
	# worst case): the scan runs, but on the small tiered radii.
	t0 = Time.get_ticks_usec()
	for i in 120:
		secondary[0] += Vector2(600.0, 0.0)  # crosses a fine chunk every frame
		t.update_streaming([focus], secondary)
	print("15-foci, 1 crossing/frame: %.3f ms/call" % ((Time.get_ticks_usec() - t0) / 1000.0 / 120.0))

	# Fast flight: a focus crossing fresh terrain at ram speed (~7000 px/s at
	# 8×). Can GENERATION and promotion keep up, and what does each frame cost?
	# This is the lazy world's headline risk — the eager probe could not see it.
	var p := focus + Vector2(0.0, -3000.0)
	var worst_fly := 0.0
	var total_fly := 0.0
	for i in 300:
		p.x += 7000.0 * (1.0 / 60.0)
		t0 = Time.get_ticks_usec()
		IslandGen.ensure_generated(t, IslandGen.DEFAULT_SEED, [p],
			t.chunk_px() * t.subdiv * 2.0)
		t.update_streaming([p])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst_fly = maxf(worst_fly, ms)
		total_fly += ms
	print("fast flight (300 frames, gen+stream): worst %.2f ms, avg %.2f ms   live: %d"
		% [worst_fly, total_fly / 300.0, t.live_chunk_count()])
	print("resident after flight: %9d solid cells   %6d chunks"
		% [t.total_solid_cells(), t.chunk_coords().size()])

	t.queue_free()
