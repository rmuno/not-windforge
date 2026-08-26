class_name WhaleDiag
extends RefCounted

## Live whale / collision diagnostic (owner tool, session 5).
##
## The owner's standing reports are about whales being "extremely fragile"
## and the FPS dropping when a whale is sandwiched or grappled-and-shot. This
## is not a fix — it is a REUSABLE WINDOW into what the whale is experiencing,
## toggled live (F3 in world.gd) so the owner can reproduce a bug and hand
## back a log file.
##
## What it records, per living-or-carcass whale (faction 2, or any body with a
## shared-health pool — a former creature counts):
##   * one ROW every physics frame: frame #, dt/FPS, the whale's shared
##     health and how much it changed THIS frame, carcass flag, block count,
##     physics contact count, and the REBUILD COUNTER (how many times
##     Ship.rebuild() ran — the prime suspect for the FPS drop), plus a count
##     of the damage events applied this frame and their sources;
##   * one EVT line per damage/impact event on a whale (terrain crash,
##     ship-collision episode, or shot), with the amount, the contact normal,
##     whether the ram was forgiven (immune), and the resulting pool;
##   * one SUM line every SUMMARY_EVERY frames: average dt, worst dt, and
##     total rebuilds across the window — so an FPS drop reads as numbers.
##
## Cost when OFF: the world's per-frame call is gated on `enabled` (one bool),
## and every Ship-side hook is gated on `Ship.diag != null` (one reference
## check, no allocation). Nothing here changes collision, damage or rebuild
## behaviour — it only observes.
##
## Output: a shareable file at user://whale_diag.log (resolved path reported
## on-screen and to stdout), plus a compact stdout summary line per window.

const LOG_PATH := "user://whale_diag.log"
const SUMMARY_EVERY := 30  ## frames between rolling FRAME-TIME / rebuild summaries

var enabled := false

var _file: FileAccess = null
## Log lines are BUFFERED here and flushed to disk PERIODICALLY (once per SUM
## window, and on stop()), never per frame. A per-frame FileAccess.flush() cost
## ~26 ms/frame in a headless bench — it dwarfed everything else and inflated the
## very `proc` numbers F3 exists to read (the observer effect). Buffering makes
## the per-frame path pure in-memory string work: no disk I/O between flushes.
## The trade is bounded and documented: a crash mid-session loses at most the
## current unflushed window (< SUMMARY_EVERY frames + any EVTs since the last
## boundary). stop() always flushes, so a clean toggle-off never loses a line.
var _buf: PackedStringArray = PackedStringArray()
var _frame := 0
## Ships we set `.diag` on, so stop() can clear every one (weakly held: a
## whale freed mid-recording must not keep us pointing at it).
var _watched: Array = []
## The world being recorded, for the SUM line's physics census (set by
## world.gd when recording starts). Null-safe: a unit test driving
## capture_frame directly just gets a census of zeroes.
var world: Node = null

## instance_id -> shared_health at the last ROW, for the per-frame delta.
var _prev_health := {}
## instance_id -> Array of source strings recorded since the last ROW.
var _frame_events := {}

## Rolling FRAME-TIME / rebuild window.
var _win_dt_sum := 0.0
var _win_dt_max := 0.0
var _win_rebuilds := 0
var _win_frames := 0
## Peak live-Shot / ship population seen in the window, so a SUM shows the
## swarm size an FPS drop rode in on (the old whale-only log was blind to it).
var _win_shots_max := 0
var _win_ships_max := 0
## Engine frame counters at the last window boundary, for `ticks` (physics
## steps per rendered frame — the catch-up tell).
var _prev_phys_frames := 0
var _prev_drawn_frames := 0
## Last counts the caller handed us, echoed on every ROW.
var _last_shots := -1
var _last_ships := 0


## The shareable, absolute path — shown on-screen and echoed to stdout so the
## owner knows exactly which file to send back.
func resolved_path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


func toggle(ships: Array) -> void:
	if enabled:
		stop(ships)
	else:
		start(ships)


func start(ships: Array) -> void:
	if enabled:
		return
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_error("WhaleDiag: could not open %s (err %d)"
			% [LOG_PATH, FileAccess.get_open_error()])
		return
	enabled = true
	_frame = 0
	_buf.clear()
	_prev_health.clear()
	_frame_events.clear()
	_reset_window()
	_write("# not-windforge whale diagnostic")
	_write("# started %s" % Time.get_datetime_string_from_system())
	_write("# ROW f=<frame> dt=<ms> fps=<n> whale=<id> hp=<cur>/<max> "
		+ "d=<delta-this-frame> carcass=<0|1> blocks=<n> contacts=<n> "
		+ "rebuilds=<n> events=<n> shots=<live-Shot-nodes> ships=<n> srcs=<...>")
	_write("# EVT f=<frame> whale=<id> src=<terrain|ship-episode|shot> "
		+ "amt=<hp> pool=<resulting> immune=<0|1> n=<contact-normal>")
	_write("# SUM f=<frame> frames=<n> avg_dt=<ms> max_dt=<ms> rebuilds=<n> "
		+ "proc=<ms> phys=<ms> draws=<n> nodes=<n> shots=<peak> ships=<peak>")
	_write("#   proc/phys = Performance TIME_PROCESS / TIME_PHYSICS_PROCESS "
		+ "(engine-wide script cost); draws = render draw calls this frame. "
		+ "A drop with high phys/shots is the shot swarm; high draws is render.")
	_write("# PHY f=<frame> ... what the PHYSICS step is made of "
		+ "(debug/physics_census.gd)")
	_write("# SYS f=<frame> <name>=<ms/frame> ... total=<ms/frame> "
		+ "— the world's own systems inside the physics tick, in tick order. "
		+ "`phys` above MINUS `total` is everything else in the step: the "
		+ "solver, and every Ship's and the player's own _physics_process.")
	_write("# RND f=<frame> ... what the RENDERED frame is made of "
		+ "(debug/frame_census.gd). `ticks` is physics steps per drawn frame: "
		+ "1 is healthy, 8 is the catch-up ceiling. `regions` is the standing "
		+ "cost of the drawn skins — retained canvas items re-submit their "
		+ "whole command list every visible frame.")
	_flush_buffer()  # the header lands on disk immediately; rows are buffered
	_attach(ships)
	print("[whale-diag] ON  -> %s" % resolved_path())


func stop(ships: Array) -> void:
	if not enabled:
		return
	if _win_frames > 0:
		_write_summary()
	print("[whale-diag] OFF (flushed %d frames -> %s)" % [_frame, resolved_path()])
	_detach()
	if _file != null:
		_flush_buffer()  # flush the buffered tail (partial window + EVTs) — no loss
		_file.close()
		_file = null
	enabled = false


## Called once per physics frame from world._physics_process while ON. Writes
## a ROW per whale and, on the window boundary, a SUM. Rows are BUFFERED in
## memory and only flushed to disk on that same window boundary (see `_buf`), so
## the per-frame path never touches the disk. Reads and RESETS each
## whale's rebuild counter, so a ROW's `rebuilds` is "since the last ROW".
## `shot_count` is the live-Shot population that frame (world reads the "shots"
## group only while recording); -1 means "caller didn't say" (a unit test
## driving capture_frame directly), logged as a dash.
func capture_frame(ships: Array, dt: float, shot_count := -1) -> void:
	if not enabled or _file == null:
		return
	_frame += 1
	var fps := Engine.get_frames_per_second()
	_last_shots = shot_count
	_last_ships = ships.size()
	if shot_count >= 0:
		_win_shots_max = maxi(_win_shots_max, shot_count)
	_win_ships_max = maxi(_win_ships_max, ships.size())

	# Late-arriving whales (a reset_world respawn during recording) get hooked
	# here, so nothing spawned mid-session escapes the log.
	_attach(ships)

	var window_rebuilds := 0
	for ship in ships:
		if not is_instance_valid(ship) or not _is_whale(ship):
			continue
		var id: int = ship.get_instance_id()
		var hp: float = ship.shared_health
		var prev: float = _prev_health.get(id, hp)
		var delta_hp := hp - prev
		_prev_health[id] = hp
		var rebuilds: int = ship.rebuilds_this_frame
		ship.rebuilds_this_frame = 0  # read-and-reset (spec)
		window_rebuilds += rebuilds
		var srcs: Array = _frame_events.get(id, [])
		var carcass: bool = ship.shared_health_max > 0.0 and ship.shared_health <= 0.0
		_write("ROW f=%d dt=%.2f fps=%d whale=%d hp=%.1f/%.1f d=%.1f carcass=%d blocks=%d contacts=%d rebuilds=%d events=%d shots=%s ships=%d srcs=%s" % [
			_frame, dt * 1000.0, fps, id,
			hp, ship.shared_health_max, delta_hp,
			1 if carcass else 0,
			ship.blocks.size(),
			ship.get_colliding_bodies().size(),
			rebuilds, srcs.size(),
			str(shot_count) if shot_count >= 0 else "-", ships.size(),
			"|".join(PackedStringArray(srcs)) if not srcs.is_empty() else "-",
		])
		_frame_events[id] = []

	# Rolling frame-time / rebuild window, so an FPS drop is visible as numbers.
	_win_dt_sum += dt
	_win_dt_max = maxf(_win_dt_max, dt)
	_win_rebuilds += window_rebuilds
	_win_frames += 1
	if _win_frames >= SUMMARY_EVERY:
		_write_summary()
		_reset_window()
		_flush_buffer()  # one disk flush per window, not per frame


## Ship-side hook: one damage/impact event on a whale. Writes an EVT line and
## remembers the source for the frame's ROW summary. Called only when the ship
## has us as its `diag` sink (whales, while recording) — inert otherwise.
func on_whale_damage(ship: Object, source: String, amount: float,
		normal: Vector2, immune: bool, pool: float) -> void:
	if not enabled or _file == null:
		return
	var id: int = ship.get_instance_id()
	if not _frame_events.has(id):
		_frame_events[id] = []
	(_frame_events[id] as Array).append(source)
	_write("EVT f=%d whale=%d src=%s amt=%.1f pool=%.1f immune=%d n=(%.2f,%.2f)" % [
		_frame, id, source, amount, pool, 1 if immune else 0, normal.x, normal.y])


# --- internals ------------------------------------------------------------

func _is_whale(ship: Object) -> bool:
	return ship.faction == 2 or ship.shared_health_max > 0.0


func _attach(ships: Array) -> void:
	for ship in ships:
		if not is_instance_valid(ship) or not _is_whale(ship):
			continue
		if ship.diag != self:
			ship.diag = self
			_watched.append(ship)


func _detach() -> void:
	for ship in _watched:
		if is_instance_valid(ship) and ship.diag == self:
			ship.diag = null
	_watched.clear()


func _write_summary() -> void:
	var avg := (_win_dt_sum / _win_frames) if _win_frames > 0 else 0.0
	# Where the frame time actually goes, so an FPS drop is diagnosable from the
	# log alone: engine-wide script cost (process / physics), the render draw
	# calls, the node population, and the peak shot swarm the window saw. These
	# are global engine monitors — cheap, read only on the window boundary.
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var shots_str := str(_win_shots_max) if _win_shots_max > 0 or _last_shots >= 0 else "-"
	_write("SUM f=%d frames=%d avg_dt=%.2f max_dt=%.2f rebuilds=%d proc=%.2f phys=%.2f draws=%d nodes=%d shots=%s ships=%d" % [
		_frame, _win_frames, avg * 1000.0, _win_dt_max * 1000.0, _win_rebuilds,
		proc_ms, phys_ms, draws, nodes, shots_str, _win_ships_max])
	# PHY: what the physics step is made of. The 2026-08-25 capture proved the
	# frame was `phys` and then had nothing further to say, because no
	# physics-side number was recorded anywhere. See debug/physics_census.gd.
	_write("PHY f=%d %s" % [_frame, PhysicsCensus.line(world)])
	# SYS: WHICH of the world's systems the physics tick went into. The
	# 2026-08-26 capture ruled the solver out (pairs=4) and then had nothing
	# further to say, because no script-side number was recorded per system.
	_write("SYS f=%d %s" % [_frame, _system_line()])
	# RND: and what the RENDERED frame is made of. `phys` and `proc` together
	# accounted for ~36 ms of a ~250 ms frame in that capture; the rest was
	# never measured at all.
	_write("RND f=%d %s" % [_frame, FrameCensus.line(world, _ticks_per_frame())])
	# Compact stdout echo so an FPS drop shows up in the console too.
	print("[whale-diag] f=%d avg_dt=%.2fms max=%.2fms rebuilds/%df=%d proc=%.2f phys=%.2f draws=%d shots=%s" % [
		_frame, avg * 1000.0, _win_dt_max * 1000.0, _win_frames, _win_rebuilds,
		proc_ms, phys_ms, draws, shots_str])


## The world's per-system milliseconds, as ms PER FRAME over the window just
## closed, biggest first, with the total. Reads and RESETS the world's
## accumulator, so consecutive SYS lines never double-count.
func _system_line() -> String:
	if world == null or not is_instance_valid(world) or not world.has_method("take_system_ms"):
		return "(no world)"
	var acc: Dictionary = world.call("take_system_ms")
	var frames := maxi(_win_frames, 1)
	var rows: Array = []
	var total := 0.0
	for key in acc:
		var ms: float = float(acc[key]) / float(frames)
		total += ms
		rows.append([key, ms])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var parts: Array = []
	for r in rows:
		parts.append("%s=%.2f" % [r[0], r[1]])
	parts.append("total=%.2f" % total)
	return " ".join(PackedStringArray(parts))


## Physics steps per RENDERED frame across the window — 1 is healthy, 8 is
## Godot's catch-up ceiling and means the frame is losing the race. Both
## counters are engine-wide and monotonic, so the window's delta is exact.
func _ticks_per_frame() -> int:
	var phys := Engine.get_physics_frames()
	var drawn := Engine.get_frames_drawn()
	var d_phys := int(phys) - _prev_phys_frames
	var d_drawn := int(drawn) - _prev_drawn_frames
	_prev_phys_frames = int(phys)
	_prev_drawn_frames = int(drawn)
	if d_drawn <= 0:
		return 0
	return int(round(float(d_phys) / float(d_drawn)))


func _reset_window() -> void:
	_win_dt_sum = 0.0
	_win_dt_max = 0.0
	_win_rebuilds = 0
	_win_frames = 0
	_win_shots_max = 0
	_win_ships_max = 0


## Buffer a line in memory. The disk write happens in _flush_buffer, called only
## on the SUM-window boundary and on stop() — never per frame (see `_buf`).
func _write(line: String) -> void:
	_buf.append(line)


## Drain the in-memory buffer to disk in one batched write + one flush. This is
## the ONLY place that touches the file between start() and stop(), so the
## per-frame path stays pure in-memory work.
func _flush_buffer() -> void:
	if _file == null or _buf.is_empty():
		return
	_file.store_string("\n".join(_buf) + "\n")
	_file.flush()
	_buf.clear()
