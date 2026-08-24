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

	t.queue_free()
