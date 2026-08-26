extends SceneTree

## Two-process multiplayer integration test. Run via tests/net_smoke.ps1.
##
##   server:  godot --headless --path . --script res://tests/net_smoke.gd -- --server
##   client:  godot --headless --path . --script res://tests/net_smoke.gd -- --client
##
## The client does the asserting and carries the exit code; the server is a
## fixture that gets killed by the runner. This exercises the things a
## single-process test cannot: that a real ENet peer connects, that
## MultiplayerSpawner replicates a ship's grid, that a server-side structural
## change reaches the client, and — the part that matters — that the client
## *derives* correct physics from the replicated grid rather than being told.

const PORT := 27777
const TIMEOUT := 20.0

## helm + 2 hull + 1 gasbag = 4 blocks, mass 8 + 10 + 10 + 4 = 32.
const START_MASS := 32.0
const START_BLOCKS := 4
## Server bolts on one more hull: 5 blocks, mass 42.
const GROWN_MASS := 42.0
const GROWN_BLOCKS := 5

## Tags so the client can tell the ships apart.
const PILOT_EARLY := 1   # spawned before the client connected
const PILOT_LIVE := 99   # spawned while the client was connected
## A nest (a spawn-site STRUCTURE) and the site it belongs to — v0.62.0.
const PILOT_NEST := 44
const NEST_SITE := Vector2i(-7, 3)
const PILOT_SEVER := 77  # the ship the server cuts in half over the wire
const PILOT_WRECK := 0   # what _island_data stamps on severed pieces

## The severing fixture: a five-cell bar with the helm at one end. Removing
## the middle cell (block AND wall — deconstruction is the only path to
## severing) leaves two islands. The helm's island stays the original ship;
## the far pair becomes its own vessel, spawned through Fleet, which is what
## makes it replicate at all.
const SEVER_CUT := Vector2i(2, 0)
const SEVER_KEEP_BLOCKS := 2
const SEVER_KEEP_MASS := 18.0    ## helm 8 + hull 10
const SEVER_PIECE_BLOCKS := 2
const SEVER_PIECE_MASS := 20.0   ## hull 10 + hull 10

## Bolted onto the early ship BEFORE anyone connects, so the payload the
## spawner replays to a late joiner is a block short of the truth. Seeing this
## cell on the client is what proves the late-join grid push actually landed —
## the ready handshake's whole job.
const LATE_JOIN_CELL := Vector2i(0, 1)

## Networked terrain fixture. Both peers build the SAME base slab (generation,
## which is NOT recorded as a diff), so the only thing a client is missing on
## join is the server's edits. All cells sit in chunk (0,0), clear of the ships.
const T_BASE := Rect2i(0, 0, 8, 4)      # a 32-cell STONE slab
const T_BASE_SOLID := 32
const T_PRECONNECT_A := Vector2i(0, 0)  # dug BEFORE the client connects
const T_PRECONNECT_B := Vector2i(1, 0)  # — only join diff-sync can carry these
const T_LIVE_DIG := Vector2i(2, 0)      # dug WHILE connected → broadcast
const T_LIVE_PLACE := Vector2i(6, 5)    # placed while connected (empty cell)
const T_CLIENT_DIG := Vector2i(3, 0)    # dug by the CLIENT → server → back
const T_CHUNK := Vector2i(0, 0)

var role := "client"
var fleet: Fleet
var crew: Crew
var terrain: Terrain
var failures := 0


func _initialize() -> void:
	role = "server" if OS.get_cmdline_user_args().has("--server") else "client"
	print("[%s] starting" % role)

	fleet = Fleet.new()
	fleet.name = "Fleet"  # same node path on both peers, required by the spawner
	root.add_child(fleet)

	crew = Crew.new()
	crew.name = "Crew"
	root.add_child(crew)

	# Same node path on both peers (required for the terrain RPCs), and the same
	# base slab generated identically on each — the terrain-as-seed+diffs model,
	# so a joiner only ever needs the DIFFS, never the whole grid.
	terrain = Terrain.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.fill_rect(T_BASE, TerrainDB.Type.STONE)

	var peer := ENetMultiplayerPeer.new()
	if role == "server":
		var err := peer.create_server(PORT, 4)
		if err != OK:
			print("[server] could not bind port %d: %d" % [PORT, err])
			quit(2)
			return
		get_multiplayer().multiplayer_peer = peer
		_run_server()
	else:
		var err := peer.create_client("127.0.0.1", PORT)
		if err != OK:
			print("[client] could not create client: %d" % err)
			quit(2)
			return
		get_multiplayer().multiplayer_peer = peer
		_run_client()


func _cells() -> Dictionary:
	return {
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
	}


## A bar the server can cut in two. Kept clear of the other ships so the
## halves cannot bump anything on their way down (two ships at one spot ruin
## measurements — godot-quirks).
func _sever_cells() -> Dictionary:
	return {
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(3, 0): BlockDB.Type.HULL,
		Vector2i(4, 0): BlockDB.Type.HULL,
	}


# --- Server ---------------------------------------------------------------

func _run_server() -> void:
	await process_frame  # let Fleet finish entering the tree before spawning

	# Ship A exists before anyone connects — exercises late-join replication.
	var early := fleet.spawn_ship_from_cells(_cells(), Vector2(0, -200), PILOT_EARLY)
	print("[server] pre-connect ship: %d blocks, mass %.0f" % [early.blocks.size(), early.mass])
	# ...and is then modified while still alone, so its spawn payload goes
	# stale before the client has even dialled in. Only the ready-handshake
	# catch-up push can bring the joiner level with this.
	await process_frame  # let the ship finish entering the tree first
	early.set_block(LATE_JOIN_CELL, BlockDB.Type.HULL)
	print("[server] pre-connect edit: early ship now %d blocks" % early.blocks.size())

	# The server's own body also exists pre-connect — late-join for people.
	# Spawned in empty sky, clear of both ships, so it free-falls forever:
	# the client uses that endless motion to prove the movement sync flows.
	var own_body := crew.spawn_player(1, Vector2(-2000, -300))
	print("[server] own body spawned at %s" % own_body.position)

	# Terrain dug BEFORE anyone connects — like the early ship's stale payload,
	# only the join diff-sync can carry these to a late joiner (net_dig records
	# the diff; the broadcast reaches nobody yet).
	terrain.net_dig(T_PRECONNECT_A, 1)
	terrain.net_dig(T_PRECONNECT_B, 1)
	print("[server] pre-connect terrain: dug %s and %s" % [T_PRECONNECT_A, T_PRECONNECT_B])

	var client_id: int = await get_multiplayer().peer_connected
	print("[server] client connected as %d" % client_id)
	await _sleep(1.0)

	# Every peer gets a body, exactly as the world does on join.
	crew.spawn_player(client_id, Vector2(400, -300))

	# Terrain edited WHILE the client is connected — these BROADCAST to it.
	terrain.net_dig(T_LIVE_DIG, 1)
	terrain.net_place(T_LIVE_PLACE, TerrainDB.Type.STONE, 1)
	print("[server] live terrain: dug %s, placed %s" % [T_LIVE_DIG, T_LIVE_PLACE])

	# Ship B is spawned with the client already present — the live path.
	var live := fleet.spawn_ship_from_cells(_cells(), Vector2(400, -200), PILOT_LIVE)
	print("[server] post-connect ship: %d blocks, node '%s'" % [live.blocks.size(), live.name])

	# A NEST — the one body whose IDENTITY changes what the receiver does with
	# it. `is_nest` rides the spawn payload, and on the far side `Ship.from_data`
	# freezes it: get that wrong and every client sees a site's structure
	# tumbling out of the sky. Tagged with a site coord too, because residency
	# was lost on the hosting rehome once already (v0.61.0).
	var nest := fleet.spawn_ship_from_cells(_cells(), Vector2(1200, -260),
		PILOT_NEST, 0.0, 1.0, 1,
		{"is_nest": true, "site_x": NEST_SITE.x, "site_y": NEST_SITE.y})
	nest.freeze = true
	print("[server] nest spawned at %s (site %s)" % [nest.position, NEST_SITE])

	# Ship C is the severing fixture, parked well clear of the others.
	var sever := fleet.spawn_ship_from_cells(_sever_cells(), Vector2(-800, -200), PILOT_SEVER)
	print("[server] sever fixture: %d blocks" % sever.blocks.size())

	await _sleep(1.0)
	# Only the LIVE ship grows from here. The early ship is deliberately left
	# alone after the client connects, so the pre-connect edit above can only
	# ever reach the client through the late-join catch-up push — an ordinary
	# broadcast would carry the whole grid and mask a broken handshake.
	live.set_block(Vector2i(3, 0), BlockDB.Type.HULL)
	print("[server] grew the live ship to %d blocks" % live.blocks.size())

	# Severing over the wire. The cut goes through the REAL gameplay path —
	# remove_block, the same call deconstruct/mining makes — so this exercises
	# the wall layer, the island flood-fill and the Fleet spawn of the piece,
	# not a hand-rolled split. Everything about it is server-only, so the
	# client should end up with two ships it never simulated.
	await _sleep(1.0)
	sever.remove_block(SEVER_CUT)
	print("[server] cut %s: keeper %d blocks, fleet now %d ships"
		% [SEVER_CUT, sever.blocks.size(), fleet.ships().size()])

	await _sleep(10.0)  # stay up until the runner kills us
	quit(0)


func _find_ship(pilot: int) -> Ship:
	for ship in fleet.ships():
		if ship.pilot_peer == pilot:
			return ship
	return null


# --- Client ---------------------------------------------------------------

func _run_client() -> void:
	if not await _wait_until(func() -> bool: return get_multiplayer().get_unique_id() != 1):
		_fail("never connected to the server")
		return _finish()
	print("[client] connected as peer %d" % get_multiplayer().get_unique_id())
	fleet.child_entered_tree.connect(func(n: Node) -> void:
		print("[client] Fleet gained child '%s' (%s)" % [n.name, n.get_class()]))

	if not await _wait_until(func() -> bool: return fleet.ships().size() >= 2, 12.0):
		print("[client] only %d ship(s) arrived" % fleet.ships().size())
	for s in fleet.ships():
		print("[client]   ship pilot=%d blocks=%d" % [s.pilot_peer, s.blocks.size()])

	_ok(_find_ship(PILOT_LIVE) != null, "ship spawned while connected replicated")
	# The nest crossed the wire AS A NEST. Identity that only exists on the
	# server is identity the client renders wrong — a structure that should
	# hang in place would fall.
	# WAIT for it rather than assume it has landed: this check sits right after
	# the join burst, and under the full suite's load (four Godots at once) the
	# spawn can arrive a beat later. An immediate assertion made it flaky —
	# which is worse than no test, because a flaky red teaches you to ignore it.
	var nest := _find_ship(PILOT_NEST)
	var waited := 0.0
	while nest == null and waited < 5.0:
		await _sleep(0.25)
		waited += 0.25
		nest = _find_ship(PILOT_NEST)
	_ok(nest != null, "a NEST replicated to the client (after %.2fs)" % waited)
	if nest != null:
		_ok(nest.is_nest, "...as a nest — the flag rode the spawn payload")
		_ok(nest.spawn_site == NEST_SITE,
			"...still tagged to its site (%s)" % str(nest.spawn_site))
		_ok(nest.freeze, "...and frozen, so it hangs where it was raised")
	_ok(_find_ship(PILOT_EARLY) != null, "ship spawned before connecting replicated (late join)")

	var ship := _find_ship(PILOT_LIVE)
	if ship == null:
		_fail("no live-spawned ship to inspect")
		return _finish()
	print("[client] inspecting live-spawned ship")

	# The spawn payload carried the grid; everything else is derived locally.
	_ok(ship.blocks.size() == START_BLOCKS,
		"replicated grid has %d blocks" % ship.blocks.size())
	_ok(is_equal_approx(ship.mass, START_MASS),
		"client derived mass %.0f from the grid" % ship.mass)
	_ok(ship.get_children().any(func(c: Node) -> bool: return c is CollisionShape2D),
		"client built its own collider")
	_ok(ship.pilot_peer == PILOT_LIVE, "pilot replicated through the spawn payload")
	_ok(ship.freeze, "client ship is frozen — the server simulates, we follow")

	# Now the live path: a structural change made on the server.
	if not await _wait_until(func() -> bool: return ship.blocks.size() == GROWN_BLOCKS):
		_fail("server's block addition never arrived (still %d blocks)" % ship.blocks.size())
		return _finish()

	print("[client] grid sync received")
	_ok(ship.has_block(Vector2i(3, 0)), "the correct cell arrived")
	_ok(is_equal_approx(ship.mass, GROWN_MASS),
		"client re-derived mass %.0f after the sync" % ship.mass)
	_ok(ship.lift_ratio() > 0.0, "client derived flight characteristics too")

	# --- The ready handshake (task A) ---
	# The early ship was edited before we connected and never touched since,
	# so the payload the spawner replayed to us is stale by exactly one block
	# and no ordinary broadcast can cover for it. Checked here, after the live
	# ship's sync has already proved the wire is flowing, so a failure points
	# at the catch-up push and nothing else.
	var early := _find_ship(PILOT_EARLY)
	if early == null:
		_fail("no early ship to check the late-join catch-up on")
	else:
		var caught_up := await _wait_until(
			func() -> bool: return early.has_block(LATE_JOIN_CELL), 4.0)
		_ok(caught_up, "pre-connect grid edit arrived (ready-handshake catch-up)")

	await _check_severing()
	await _check_interpolation()
	await _check_terrain()

	# --- Players replicate too (owner: "they see the world move, just not
	# the people existing"). ---
	var my_id := get_multiplayer().get_unique_id()
	if not await _wait_until(func() -> bool: return crew.players().size() >= 2, 12.0):
		print("[client] only %d player(s) arrived" % crew.players().size())
	_ok(crew.player_for(1) != null, "the server's body replicated (late join)")
	_ok(crew.player_for(my_id) != null, "this peer's own body replicated back")

	var mine := crew.player_for(my_id)
	var theirs := crew.player_for(1)
	if mine != null:
		_ok(mine.is_locally_controlled(), "this peer drives its own body")
	if theirs != null:
		_ok(not theirs.is_locally_controlled(), "and only renders the server's")
		# The server body free-falls under its own simulation; any motion
		# on our replica proves the movement synchroniser is flowing.
		var y0: float = theirs.global_position.y
		var moved := await _wait_until(
			func() -> bool: return absf(theirs.global_position.y - y0) > 5.0, 8.0)
		_ok(moved, "the server body's movement reaches the client")

	_finish()


## Severing over the wire. The server cut its bar in half through the ordinary
## deconstruct path; every part of that — the flood-fill, the choice of which
## island keeps the hull, the Fleet spawn of the loose piece — happens on the
## server alone. The client should therefore end up with TWO vessels it never
## simulated, each with the right cells, and each re-deriving its own mass from
## the grid rather than being told what it weighs.
func _check_severing() -> void:
	print("[client] waiting for the sever")
	if not await _wait_until(func() -> bool: return _find_ship(PILOT_SEVER) != null, 12.0):
		_fail("the ship to be severed never replicated")
		return
	var keeper := _find_ship(PILOT_SEVER)

	# Two halves: the keeper shrinks (grid sync) and the piece appears (spawn).
	var split := await _wait_until(func() -> bool:
		return keeper.blocks.size() == SEVER_KEEP_BLOCKS \
			and _find_ship(PILOT_WRECK) != null, 12.0)
	_ok(split, "the server's sever produced two ships on the client")
	if not split:
		print("[client]   keeper has %d blocks, wreck %s"
			% [keeper.blocks.size(), "present" if _find_ship(PILOT_WRECK) != null else "missing"])
		return
	var piece := _find_ship(PILOT_WRECK)

	# The keeper: the helm's island, minus the cut cell and everything past it.
	_ok(keeper.has_block(Vector2i(0, 0)) and keeper.has_block(Vector2i(1, 0)),
		"the helm half kept its own cells")
	_ok(not keeper.has_block(SEVER_CUT) and not keeper.has_block(Vector2i(3, 0)),
		"and lost the cut cell and everything beyond it")
	_ok(is_equal_approx(keeper.mass, SEVER_KEEP_MASS),
		"client re-derived the helm half's mass %.0f" % keeper.mass)

	# The loose piece: a real, independent, client-side ship — its own grid,
	# its own collider, its own mass, and frozen like every remote hull.
	_ok(piece.blocks.size() == SEVER_PIECE_BLOCKS,
		"the severed piece replicated with %d blocks" % piece.blocks.size())
	_ok(piece.has_block(Vector2i(3, 0)) and piece.has_block(Vector2i(4, 0)),
		"the piece carries exactly the far cells")
	_ok(is_equal_approx(piece.mass, SEVER_PIECE_MASS),
		"client re-derived the piece's mass %.0f" % piece.mass)
	_ok(piece.get_children().any(func(c: Node) -> bool: return c is CollisionShape2D),
		"the piece built its own collider client-side")
	_ok(piece.freeze, "the piece is frozen — wreckage is simulated by the server too")
	_ok(not piece.assist_enabled, "and does not fly itself")


## Client-side interpolation. How SMOOTH a remote hull looks is a judgement
## call no headless assertion can make; what a test can pin down is that
## moving the smoothing in front of the transform did not break the transport,
## and that the easing is really running. So: the wire pose must keep
## arriving, the visible hull must keep following it, and the hull must TRAIL
## the wire pose by a bounded amount — a body that snapped would sit exactly
## on it, and a body that had come adrift would be past the snap threshold.
##
## Measured on the severed wreck: no lift, no assist, so it free-falls at a
## speed that makes the trailing distance unambiguous.
func _check_interpolation() -> void:
	var wreck := _find_ship(PILOT_WRECK)
	if wreck == null:
		_fail("no wreck to measure interpolation on")
		return
	# A generous window: the wire pose has to travel far enough that a body
	# which failed to follow is unmistakable. (A one-frame window is not a
	# test — the synchroniser and _physics_process land on different ticks.)
	var pose0: float = wreck.net_position.y
	var seen0: float = wreck.position.y
	var flowing := await _wait_until(func() -> bool:
		return absf(wreck.net_position.y - pose0) > 600.0, 8.0)
	_ok(flowing, "the server's ship transform still reaches the client")
	# Comfortably more than the worst-case trailing distance, so a body that
	# stopped following is unambiguous while a merely-eased one always passes.
	_ok(absf(wreck.position.y - seen0) > 300.0,
		"and the visible hull follows it (%.0f px of %.0f)"
		% [absf(wreck.position.y - seen0), absf(wreck.net_position.y - pose0)])

	# Trailing, never leading, and never far enough behind to be adrift: the
	# easing only ever closes a fraction of the error toward the server.
	var lag: float = wreck.net_position.y - wreck.position.y  # falling: +y
	var snap: float = Ship.NET_SNAP_CELLS * Ship.CELL * wreck.scale_unit
	_ok(lag >= 0.0 and lag < snap,
		"the hull trails the wire pose by %.1f px (snap at %.0f)" % [lag, snap])


## Networked terrain (task A). The client shares the base slab (generated
## identically from the same source), then proves the three replication paths:
##   * LATE JOIN — the server's pre-connect digs arrive via the diff-sync
##     handshake (request_diffs_on_join), which an ordinary broadcast could not
##     carry (the client wasn't there for it).
##   * BROADCAST — an edit the server makes while the client is connected shows
##     on the client's resident grid AND its promoted chunk's collider.
##   * CLIENT REQUEST — a dig the client initiates reaches the server and
##     replicates back to the client's own grid + collider.
func _check_terrain() -> void:
	print("[client] checking networked terrain")
	_ok(terrain.solid_cells_in_chunk(T_CHUNK) == T_BASE_SOLID,
		"the client generated the same %d-cell base slab" % T_BASE_SOLID)

	# LATE JOIN: ask the server for its diff set (as world._on_connected_to_server
	# does), then the pre-connect digs must land.
	terrain.request_diffs_on_join()
	var caught_up := await _wait_until(func() -> bool:
		return not terrain.is_solid(T_PRECONNECT_A) \
			and not terrain.is_solid(T_PRECONNECT_B), 8.0)
	_ok(caught_up, "pre-connect terrain diffs arrived on join (late-join diff-sync)")

	# BROADCAST: the server's live dig + place reach the resident grid.
	var live_dig := await _wait_until(func() -> bool: return not terrain.is_solid(T_LIVE_DIG), 8.0)
	_ok(live_dig, "the server's live dig replicated to the client's grid")
	var live_place := await _wait_until(func() -> bool: return terrain.is_solid(T_LIVE_PLACE), 8.0)
	_ok(live_place, "the server's live place replicated to the client's grid")

	# The promoted chunk's collider tracks the resident data exactly (a broadcast
	# edit re-merges the live chunk, godot-quirks: outside the physics step).
	terrain.update_streaming([_chunk_centre(T_CHUNK)])
	var chunk: TerrainChunk = terrain.promoted_chunk(T_CHUNK)
	_ok(chunk != null, "the client promoted the edited chunk")
	if chunk == null:
		return
	_ok(chunk.collider_cell_count() == terrain.solid_cells_in_chunk(T_CHUNK),
		"the promoted collider matches the replicated data (%d cells)"
			% chunk.collider_cell_count())
	var before := chunk.collider_cell_count()

	# CLIENT REQUEST: the client digs; the request reaches the server and the
	# result replicates back, updating the client's grid AND live collider.
	_ok(terrain.is_solid(T_CLIENT_DIG), "the client-dig target is solid before the dig")
	terrain.net_dig(T_CLIENT_DIG, get_multiplayer().get_unique_id())
	var round_tripped := await _wait_until(func() -> bool:
		return not terrain.is_solid(T_CLIENT_DIG), 8.0)
	_ok(round_tripped, "a client-requested dig reached the server and replicated back")
	terrain.flush_rebuilds()  # batched per frame since 2026-08-25; force it for the assert
	_ok(chunk.collider_cell_count() == before - 1,
		"and the client's promoted collider shrank by the one dug cell (%d → %d)"
			% [before, chunk.collider_cell_count()])


## Centre of a chunk in world px, for aiming a streaming focus at it.
func _chunk_centre(coord: Vector2i) -> Vector2:
	var cp := terrain.chunk_px()
	return (Vector2(coord) + Vector2(0.5, 0.5)) * cp


# --- Plumbing -------------------------------------------------------------

func _ok(condition: bool, detail: String) -> void:
	if condition:
		print("    ok   %s" % detail)
	else:
		failures += 1
		print("    FAIL %s" % detail)


func _fail(reason: String) -> void:
	failures += 1
	print("    FAIL %s" % reason)


func _finish() -> void:
	if failures == 0:
		print("\n[client] PASS\n")
		quit(0)
	else:
		print("\n[client] FAIL — %d problem(s)\n" % failures)
		quit(1)


func _wait_until(predicate: Callable, timeout := TIMEOUT) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _sleep(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
