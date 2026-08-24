extends SceneTree

## Headless perf probe for the terrain-resolution (SUBDIV 8) round — the
## BACKLOG's blocking gate: generation cost, promotion burst cost, and resident
## memory at the full-8× grid, measured before the default ships.
##
##   godot --headless --path . --script tools/terrain_probe.gd
##
## Numbers to watch:
##   * generate: the world-build stall the fill_row fast path exists to kill.
##   * promote worst-call: must stay well inside a 16.6 ms frame (amortized
##     PROMOTE_PER_CALL=2, so this is ~2 greedy merges + node adds).
##   * steady-state update_streaming with everything promoted: the per-frame
##     scan cost of the subdiv-scaled radii.


func _initialize() -> void:
	for sub in [1, 8]:
		_probe(sub)
	quit(0)


func _probe(sub: int) -> void:
	print("\n=== terrain probe @ subdiv %d ===" % sub)
	var t := Terrain.new()
	t.subdiv = sub
	t.scale_unit = 8.0  # the shipped world scale
	root.add_child(t)

	var t0 := Time.get_ticks_usec()
	IslandGen.generate(t)
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var chunks := t.chunk_coords().size()
	var cells := t.total_solid_cells()
	print("generate: %8.1f ms   solid cells: %9d   chunks: %6d (~%.1f MiB resident)"
		% [gen_ms, cells, chunks, chunks * Terrain.CHUNK * Terrain.CHUNK / 1048576.0])

	# Promotion burst: drop a focus onto the densest spot we can find cheaply
	# (the spawn floor) and drain the promotion queue, timing every call.
	var focus := t.cell_center(Vector2i(0, 10 * sub))
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
	var secondary: Array = []
	for i in 14:
		secondary.append(focus + Vector2(
			(i - 7) * 2600.0 * t.scale_unit / 8.0 * 8.0, (i % 3 - 1) * 1800.0))
	for i in 900:  # let promotion drain fully for the whole fleet
		t.update_streaming([focus], secondary)
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
	# 8×). Can promotion keep up, and what does each frame cost?
	var p := focus + Vector2(0.0, -3000.0)
	var worst_fly := 0.0
	var total_fly := 0.0
	for i in 300:
		p.x += 7000.0 * (1.0 / 60.0)
		t0 = Time.get_ticks_usec()
		t.update_streaming([p])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst_fly = maxf(worst_fly, ms)
		total_fly += ms
	print("fast flight (300 frames): worst %.2f ms, avg %.2f ms   live: %d"
		% [worst_fly, total_fly / 300.0, t.live_chunk_count()])

	t.queue_free()
