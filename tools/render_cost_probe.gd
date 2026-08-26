extends SceneTree

## Headless RETAINED-COMMAND probe. The v0.48.1 terrain probe cleared
## streaming and generation as lag suspects and left one standing: the RENDER
## cost of the finer (subdiv 4) terrain. Nobody had measured it.
##
## A CanvasItem's draw calls are RETAINED -- the renderer replays every one,
## every frame, whether or not anything changed. So the per-frame cost of the
## world's placeholder art is a COUNT, and a count is measurable headless even
## though the drawing itself is not: `_draw` emits one filled rect plus one
## border rect per greedy-merged region, so
##
##     commands = 2 x regions
##
## exactly. This probe counts regions the same way both painters do -- through
## Ship._greedy_rects, the shared helper -- for every promoted terrain chunk
## and every ship, and times the merge itself.
##
##   godot --headless --path . --script tools/render_cost_probe.gd

const REPS := 8


func _initialize() -> void:
	var packed: PackedScene = load("res://maps/world/world.tscn")
	var world: Node = packed.instantiate()
	root.add_child(world)
	# Let the streamer promote the spawn neighbourhood the way play does.
	for i in 60:
		await process_frame

	var terrain = world.get("terrain")
	print("subdiv %d, chunk %d cells, cell_px %.1f"
		% [terrain.subdiv, Terrain.CHUNK, terrain.cell_px()])

	# --- terrain ----------------------------------------------------------
	var chunks: Array = []
	for c in terrain.get_children():
		if c is TerrainChunk:
			chunks.append(c)
	var t_regions := 0
	var t_solid := 0
	var t_collider := 0
	var worst := 0
	var t0 := Time.get_ticks_usec()
	for r in REPS:
		t_regions = 0
		for ch in chunks:
			t_regions += _regions_of(ch)
	var merge_ms := (Time.get_ticks_usec() - t0) / 1000.0 / REPS
	# (kept as a line so before/after runs line up; it reads a cached array
	# now, which is the point -- it used to re-merge on every repaint.)
	for ch in chunks:
		t_collider += ch._collider_rects.size()
		t_solid += ch.collider_cell_count()
		worst = maxi(worst, _regions_of(ch))
	print("\nTERRAIN  %d promoted chunks, %d solid cells resident"
		% [chunks.size(), t_solid])
	print("  draw regions      %6d   (%d retained commands: fill + border)"
		% [t_regions, t_regions * 2])
	print("  worst chunk       %6d regions" % worst)
	print("  collider rects    %6d" % t_collider)
	print("  region read       %8.3f ms for ALL chunks (was a re-merge per repaint)"
		% merge_ms)

	# --- the rebuild itself ----------------------------------------------
	# A promote and every dig pay this. The v0.48.1 terrain probe measured
	# promote at up to 8.70 ms/call and left it as the residual-lag suspect;
	# this is the part of it that lives in the chunk.
	var rb0 := Time.get_ticks_usec()
	for r in REPS:
		for ch in chunks:
			ch.rebuild()
	var rebuild_ms := (Time.get_ticks_usec() - rb0) / 1000.0 / REPS
	print("  chunk rebuild     %8.3f ms for ALL chunks  (%.3f ms each)"
		% [rebuild_ms, rebuild_ms / maxf(1.0, float(chunks.size()))])

	# How much of that is the per-cell cell_type() lookup path: same scan,
	# nothing else. Each call re-derives the chunk coord and re-hashes the
	# dictionary for a chunk the caller already knows.
	var sc0 := Time.get_ticks_usec()
	var seen := 0
	for r in REPS:
		for ch in chunks:
			var base: Vector2i = ch.chunk_coord * ch.chunk_cells
			for ly in ch.chunk_cells:
				for lx in ch.chunk_cells:
					if TerrainDB.is_solid(terrain.cell_type(base + Vector2i(lx, ly))):
						seen += 1
	var scan_ms := (Time.get_ticks_usec() - sc0) / 1000.0 / REPS
	print("  ...of which SCAN  %8.3f ms  (%d cell_type calls per pass)"
		% [scan_ms, chunks.size() * 32 * 32])

	# --- ships ------------------------------------------------------------
	var fleet = world.get("fleet")
	var s_regions := 0
	var s_cells := 0
	for ship in fleet.ships():
		s_cells += ship.blocks.size()
		for coord in ship._skin_sectors:
			var sec = ship._skin_sectors[coord]
			var plan: Dictionary = ship.sector_paint_plan(sec.cells)
			for key in plan["groups"]:
				s_regions += ship._greedy_rects(plan["groups"][key]["cells"]).size()
			# The wound overlay is retained too (v0.69.1).
			for shade in plan["wounds"]:
				s_regions += ship._greedy_rects(plan["wounds"][shade]["cells"]).size()
	print("\nSHIPS    %d bodies, %d cells" % [fleet.ships().size(), s_cells])
	print("  draw regions      %6d   (%d retained commands)"
		% [s_regions, s_regions * 2])

	var total := (t_regions + s_regions) * 2
	print("\nTOTAL retained rect commands: %d  (terrain %d%%, ships %d%%)"
		% [total,
			roundi(100.0 * t_regions / maxf(1.0, float(t_regions + s_regions))),
			roundi(100.0 * s_regions / maxf(1.0, float(t_regions + s_regions)))])
	quit(0)


## Regions one chunk's _draw emits -- merged once at rebuild since v0.55.2,
## so this is now a read rather than a re-derivation.
func _regions_of(chunk) -> int:
	return chunk._draw_regions.size()
