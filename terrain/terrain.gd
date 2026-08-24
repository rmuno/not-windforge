class_name Terrain
extends Node2D

## The resident, chunked, destructible terrain — Sprint 2's load-bearing piece
## ("somewhere to fly to, made of blocks you can mine").
##
## THE RESIDENT WORLD, NO LOADING SCREENS EVER (DECISIONS 2026-08-18). The whole
## map is ONE resident data grid, pure data. Regions far from every player are
## COMPLETELY INERT: no nodes, no colliders, no rendering — they are not even
## instantiated. A chunk is promoted to live scenery + physics (a TerrainChunk)
## only when a focus (player or ship) comes near, and demoted (freed) on leave.
##
## DATA MODEL — Dictionary of chunk_coord -> PackedByteArray, one byte per cell
## (TerrainDB.Type). Chosen over one flat PackedByteArray for the whole map
## because:
##   * SPARSE. A sky world is mostly air; a chunk with no terrain has NO entry
##     at all, costing nothing — the far-region inertness the spec demands falls
##     out for free (only chunks that hold terrain can ever be promoted). A flat
##     full-map array would have to allocate the entire (open, unbounded) map up
##     front, and the final map size is still an owner call — this parameterises
##     size instead of hardcoding it.
##   * O(1) DIG. A cell is (chunk lookup)+(index into a byte array) — no search.
##   * COMPACT. One byte per cell; a full 32×32 chunk is 1 KiB.
## The bytes are the SINGLE SOURCE OF TRUTH; a promoted chunk is a derived view,
## like a ship's collider is derived from `ship.blocks`.
##
## SCALE-AGNOSTIC. Cell size in px is TerrainDB.CELL × scale_unit, read from the
## world exactly like Ship.scale_unit. Cells and chunks are defined in
## cell/chunk coordinates; only the px projection scales.

## Cells per chunk edge. 32 → 1024 cells (1 KiB) per chunk. At world_scale 8 one
## chunk is 32×16×8 = 4096 px square, ~half a screen — a natural promotion
## granularity: big enough that we manage tens of nodes not thousands, small
## enough that a promote (a ≤1024-cell greedy merge, cf. the 11k-cell ship hull)
## is imperceptible and a dig re-merges one chunk, not the map.
const CHUNK := 32

## Promote a chunk when its chunk-grid Chebyshev distance to any focus is within
## PROMOTE_RADIUS; demote only past DEMOTE_RADIUS. The gap is HYSTERESIS: a focus
## hovering a chunk boundary oscillates within one chunk, but a promoted chunk
## survives from distance 2 until it exceeds 3, so it never thrashes
## promote/demote. In chunks so the behaviour holds at any world scale.
const PROMOTE_RADIUS := 2
const DEMOTE_RADIUS := 3

## AMORTIZE promotion: promote at most this many chunks per update_streaming
## call. When a player first flies up to terrain, every chunk inside
## PROMOTE_RADIUS wants to promote in the SAME frame — several greedy merges +
## node creations + first draws at once, a measured ~73 ms hitch for a 25-chunk
## burst. Spreading them K per frame keeps approaching terrain smooth; a focus
## that sits still for a few frames still ends fully promoted, just over frames.
## Demotion stays immediate (freeing is cheap and starving it risks colliders
## lingering where a body has already left). K small so no single frame hitches;
## nearest-first (below) so the chunk you are flying INTO promotes first.
const PROMOTE_PER_CALL := 2

## World feel multiplier, read from the world like Ship.scale_unit. 1 changes
## nothing; at S every terrain cell is S× bigger on screen.
var scale_unit := 1.0

## chunk_coord (Vector2i) -> PackedByteArray of CHUNK*CHUNK cell types.
var _chunks := {}
## chunk_coord (Vector2i) -> live TerrainChunk node (the promoted view).
var _live := {}

## Runtime EDITS since generation — cell (Vector2i) -> final type (int). Recorded
## by the destructible seam only (`dig`/`place`), never by generation
## (IslandGen/EasterEggs write through `set_cell`/`fill_rect`, which are NOT
## recorded). This is what a save stores instead of the whole grid: the world is
## deterministic from `world_seed`, so a save is SEED + these diffs, and load
## regenerates then re-applies them (save/save_game.gd). A cell dug then placed
## back records its FINAL state, so the diff is always the delta from a fresh gen.
var _edits := {}

## A cell was mined by `peer_id` at `cell`, yielding `type` (a TerrainDB.Type).
## The world credits the miner's inventory and pops a pickup float. Emitted from
## the AUTHORITY only (net_dig / _request_dig), so the item is minted once, where
## the terrain edit is truth — never on a client that merely predicted a dig.
signal dug(peer_id: int, cell: Vector2i, type: int)

## A cell was PLACED by `peer_id` at `cell` with `type` (a TerrainDB.Type) — the
## inverse of `dug`. The world consumes one of that material from the placer's
## inventory (net_place / _request_place). AUTHORITY-only, same as `dug`, so the
## item is spent once where the terrain edit is truth.
signal placed(peer_id: int, cell: Vector2i, type: int)


func cell_px() -> float:
	return TerrainDB.CELL * scale_unit


func chunk_px() -> float:
	return CHUNK * cell_px()


# --- Coordinates ----------------------------------------------------------
# Terrain uses a TOP-LEFT cell origin (cleaner for a tile grid than the ship's
# CoM-centred cells): cell (cx, cy) covers local rect [cx, cy]..[cx+1, cy+1] in
# cell units. floori (not int division, which truncates toward zero) keeps the
# grid correct across the origin into negative coordinates.

func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))


func _index_in_chunk(cell: Vector2i, chunk: Vector2i) -> int:
	var lx := cell.x - chunk.x * CHUNK
	var ly := cell.y - chunk.y * CHUNK
	return ly * CHUNK + lx


## World position -> terrain cell. Via the node transform so it stays correct
## if the Terrain node is ever offset (today it sits at the world origin).
func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local := to_local(world_pos)
	var cp := cell_px()
	return Vector2i(floori(local.x / cp), floori(local.y / cp))


func chunk_of_cell(cell: Vector2i) -> Vector2i:
	return _chunk_of(cell)


## World position of a cell's CENTRE — the mining reach check measures to this,
## and the target highlight draws from it. Via the node transform so it stays
## correct if the Terrain node is ever offset.
func cell_center(cell: Vector2i) -> Vector2:
	var cp := cell_px()
	return to_global((Vector2(cell) + Vector2(0.5, 0.5)) * cp)


# --- Resident data (the single source of truth) ---------------------------

func cell_type(cell: Vector2i) -> int:
	var ch := _chunk_of(cell)
	if not _chunks.has(ch):
		return TerrainDB.Type.AIR
	return (_chunks[ch] as PackedByteArray)[_index_in_chunk(cell, ch)]


func is_solid(cell: Vector2i) -> bool:
	return TerrainDB.is_solid(cell_type(cell))


## Write a cell into the resident data. Allocates the chunk's byte array lazily
## (a chunk stays absent — fully inert — until something solid is written into
## it). PackedByteArray is copy-on-write, so the modified array is written back
## explicitly rather than trusting an in-place index assignment through the
## dictionary.
func set_cell(cell: Vector2i, type: int) -> void:
	var ch := _chunk_of(cell)
	if not _chunks.has(ch):
		if type == TerrainDB.Type.AIR:
			return
		var arr := PackedByteArray()
		arr.resize(CHUNK * CHUNK)  # resize zero-fills → all AIR
		_chunks[ch] = arr
	var a: PackedByteArray = _chunks[ch]
	a[_index_in_chunk(cell, ch)] = type
	_chunks[ch] = a
	# Keep a live view honest if this chunk happens to be promoted.
	if _live.has(ch):
		(_live[ch] as TerrainChunk).rebuild()


## Paint a solid rectangle of cells [cell_rect) — the generation primitive.
func fill_rect(cell_rect: Rect2i, type: int) -> void:
	for y in range(cell_rect.position.y, cell_rect.end.y):
		for x in range(cell_rect.position.x, cell_rect.end.x):
			set_cell(Vector2i(x, y), type)


# --- The destructible seam (the ONLY hook mining needs) -------------------

## Remove a cell from the resident data and, if its chunk is live, from the
## promoted collider (chunk-scoped re-merge — cheap). Returns the TYPE that was
## removed (TerrainDB.Type.AIR if the cell was already empty) so the mining
## chunk can turn it into an inventory item. This is the whole seam: mining is
## `var t := terrain.dig(cell)` then spawn an item of type `t`.
func dig(cell: Vector2i) -> int:
	var t := cell_type(cell)
	if not TerrainDB.is_solid(t):
		return TerrainDB.Type.AIR
	set_cell(cell, TerrainDB.Type.AIR)  # set_cell rebuilds the live chunk
	_edits[cell] = TerrainDB.Type.AIR  # a real removal — record the diff for saves
	return t


## Convenience: dig by world position (e.g. the cell under the mining cursor).
func remove_cell(world_pos: Vector2) -> int:
	return dig(world_to_cell(world_pos))


## Write a solid material into an EMPTY cell — the inverse of `dig`, the make/use
## loop's placement (v0.25.0). Refuses to place into a solid cell (mine it first)
## or to place a non-solid type (AIR is not a material). Returns true only when
## the cell was actually written; set_cell re-merges the live chunk if promoted,
## so the placed cell gains a collider immediately. Kept beside `dig` because they
## are the same seam read both ways.
func place(cell: Vector2i, type: int) -> bool:
	if not TerrainDB.is_solid(type):
		return false  # AIR / invalid is not a placeable material
	if is_solid(cell):
		return false  # occupied — cannot stack a material onto solid terrain
	set_cell(cell, type)  # set_cell rebuilds the live chunk
	_edits[cell] = type  # a real placement — record the diff for saves
	return true


# --- Mining / placement (authority-owned + REPLICATED) ---------------------
#
# The AUTHORITY (the server, and single-player, which NetUtil.is_authority
# treats as one) owns every terrain edit, exactly like a Ship owns its
# structural changes (AGENTS.md → authority model). Mining routes through here
# so a client can never mutate its own grid: it forwards a request to the server
# and lets the server be the truth.
#
# REPLICATION (this round — the deferred networked-terrain flag, now closed):
# when the authority digs or places (single-player-local OR on a client's
# request), it BROADCASTS the edit (cell + new type) to every peer via
# `_apply_edit`, which writes the peer's resident grid through `set_cell` — and
# `set_cell` re-merges the affected promoted chunk (collider + redraw) if it is
# live, so every peer sees the same world change. Late joiners catch up on the
# whole DIFF SET via the join handshake (request_diffs_on_join, below): a client
# regenerates from the seed and re-applies the server's edits, since terrain is
# seed + diffs (the same shape the save format uses).
#
# RESIDUAL SEAM — inventory. The credited/charged ITEM is authority-correct: the
# server's `dug`/`placed` fires for the requesting peer, so the item lands on
# that peer's server-side body and single-player is fully correct. It is NOT
# replicated to the requesting CLIENT's local inventory (the inventory does not
# ride the wire at all — Player bodies replicate transform, not their pack), so a
# client's own mined item shows on the server's copy of it, not on the client's
# HUD. Full inventory replication is a separate chunk; the WORLD state (the grid)
# now replicates in full.

## Mine the cell — the seam the world's mine action calls. On the authority this
## digs immediately, emits `dug` (so the world credits the miner), BROADCASTS the
## edit to peers, and returns the removed type. On a client it forwards the
## request to the server and returns AIR locally (no client-side grid mutation —
## authority model). `requester` is the peer to credit; defaults to single-player.
func net_dig(cell: Vector2i, requester := 1) -> int:
	if NetUtil.is_authority(self):
		return _authority_dig(cell, requester)
	_request_dig.rpc_id(1, cell)
	return TerrainDB.Type.AIR


## A client asked the server to mine `cell`. The server digs authoritatively,
## credits the requesting peer, and broadcasts the edit to all peers.
@rpc("any_peer", "reliable")
func _request_dig(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return  # a client must never act on another peer's dig request
	_authority_dig(cell, multiplayer.get_remote_sender_id())


## The authority-side dig, shared by net_dig (local) and _request_dig (a client's
## request): mutate the grid, credit the requester, and mirror the edit to every
## peer. Returns the removed type (AIR if the cell was already empty).
func _authority_dig(cell: Vector2i, requester: int) -> int:
	var t := dig(cell)
	if TerrainDB.is_solid(t):
		dug.emit(requester, cell, t)
		_broadcast_edit(cell, TerrainDB.Type.AIR)
	return t


## Place `type` into `cell` — the placement twin of net_dig, same authority
## model. On the authority this writes the cell now, emits `placed` (so the world
## spends one item from the placer), broadcasts the edit, and returns true; on a
## client it forwards the request and returns false (no client-side grid
## mutation). `requester` is the peer to charge; defaults to single-player.
func net_place(cell: Vector2i, type: int, requester := 1) -> bool:
	if NetUtil.is_authority(self):
		return _authority_place(cell, type, requester)
	_request_place.rpc_id(1, cell, type)
	return false


## A client asked the server to place `type` at `cell`. The server places
## authoritatively, charges the requesting peer via `placed`, and broadcasts.
@rpc("any_peer", "reliable")
func _request_place(cell: Vector2i, type: int) -> void:
	if not multiplayer.is_server():
		return  # a client must never act on another peer's place request
	_authority_place(cell, type, multiplayer.get_remote_sender_id())


## The authority-side place, shared by net_place (local) and _request_place (a
## client's request): write the cell, charge the placer, mirror to every peer.
func _authority_place(cell: Vector2i, type: int, requester: int) -> bool:
	if place(cell, type):
		placed.emit(requester, cell, type)
		_broadcast_edit(cell, type)
		return true
	return false


# --- Replication (broadcast one edit; late-join the whole diff set) ---------

## Mirror one authoritative terrain edit (a dug or placed cell → its NEW type) to
## every other peer. No-op offline — single-player has nobody to tell. Reliable
## because a dropped terrain edit would desync a client's grid permanently, and
## `authority` because only the server may originate one.
func _broadcast_edit(cell: Vector2i, type: int) -> void:
	if NetUtil.is_online(self) and multiplayer.is_server():
		_apply_edit.rpc(cell, type)


## Apply one broadcast edit on a peer: write the cell into the resident grid (and
## record it into `_edits` so a peer's diff set stays consistent). set_cell
## re-merges the promoted chunk's collider + redraw if this chunk is live, so the
## world change shows immediately; if the chunk is not promoted, the data updates
## and the next promote reflects it. Runs on every peer BUT the server (which
## already applied the edit directly), because .rpc() does not call_local.
@rpc("authority", "reliable")
func _apply_edit(cell: Vector2i, type: int) -> void:
	set_cell(cell, type)
	_edits[cell] = type


## Late-join: a client asks the server for the current terrain diff set. Called
## once the client is connected (world._on_connected_to_server). Terrain is
## SEED + DIFFS: the client already regenerated the base world from the shared
## seed, so all it is missing is the server's edits since generation. No-op on
## the server / single-player.
func request_diffs_on_join() -> void:
	if NetUtil.is_online(self) and not multiplayer.is_server():
		_request_diffs.rpc_id(1)


## Server side of the join handshake: send the asking client the whole diff set
## (flat [x, y, type, ...]). The sender id comes from the multiplayer API, never
## an argument, so no peer can request on another's behalf.
@rpc("any_peer", "reliable")
func _request_diffs() -> void:
	if not multiplayer.is_server():
		return
	_receive_diffs.rpc_id(multiplayer.get_remote_sender_id(), _encode_diffs())


## Client side of the join handshake: apply the server's diff set onto the
## already-regenerated base world. Idempotent with any broadcasts that raced in
## (set_cell to the same value is a no-op), so the ordering is safe.
@rpc("authority", "reliable")
func _receive_diffs(flat: PackedInt32Array) -> void:
	var i := 0
	while i + 2 < flat.size():
		set_cell(Vector2i(flat[i], flat[i + 1]), flat[i + 2])
		_edits[Vector2i(flat[i], flat[i + 1])] = flat[i + 2]
		i += 3


## The runtime edits as a flat PackedInt32Array [x, y, type, ...] — the wire
## shape for the late-join diff push (mirrors save/save_game's flat diff array).
func _encode_diffs() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(_edits.size() * 3)
	var i := 0
	for cell in _edits:
		out[i] = cell.x
		out[i + 1] = cell.y
		out[i + 2] = int(_edits[cell])
		i += 3
	return out


# --- Promote / demote -----------------------------------------------------

## Given the world positions of every focus (players and ships), promote the
## chunks that hold terrain within PROMOTE_RADIUS and demote live chunks that
## have drifted past DEMOTE_RADIUS of every focus. Synchronous and cheap — each
## promote is one chunk's greedy merge — so there is never a loading screen.
## Call once per physics frame from the world.
func update_streaming(foci: Array) -> void:
	var cpx := chunk_px()
	var focus_chunks: Array[Vector2i] = []
	for f in foci:
		var local: Vector2 = to_local(f)
		focus_chunks.append(Vector2i(
			floori(local.x / cpx), floori(local.y / cpx)))

	# Promote: only chunks that actually hold terrain data (air chunks have no
	# entry and stay inert forever — the resident-world guarantee). Gather every
	# candidate in radius, then promote at most PROMOTE_PER_CALL of them,
	# NEAREST-first — so a burst of chunks entering the radius spreads across
	# frames instead of hitching one frame (see PROMOTE_PER_CALL). The candidate
	# set is recomputed each call, so a still focus drains it K per frame until
	# it is fully promoted; no persistent queue to keep in sync.
	var candidates: Array = []
	var seen := {}
	for fc in focus_chunks:
		for dy in range(-PROMOTE_RADIUS, PROMOTE_RADIUS + 1):
			for dx in range(-PROMOTE_RADIUS, PROMOTE_RADIUS + 1):
				var c := fc + Vector2i(dx, dy)
				if seen.has(c):
					continue
				if _chunks.has(c) and not _live.has(c):
					seen[c] = true
					candidates.append(c)
	if not candidates.is_empty():
		# Nearest-first by Chebyshev distance to the closest focus.
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _focus_distance(a, focus_chunks) < _focus_distance(b, focus_chunks))
		var promoted := 0
		for c in candidates:
			if promoted >= PROMOTE_PER_CALL:
				break
			_promote(c)
			promoted += 1

	# Demote: any live chunk beyond DEMOTE_RADIUS of every focus (hysteresis).
	var to_demote: Array[Vector2i] = []
	for c in _live:
		var keep := false
		for fc in focus_chunks:
			if maxi(absi(c.x - fc.x), absi(c.y - fc.y)) <= DEMOTE_RADIUS:
				keep = true
				break
		if not keep:
			to_demote.append(c)
	for c in to_demote:
		_demote(c)


## Chunk-grid Chebyshev distance from a chunk to the nearest focus — the key the
## promotion queue drains by, so the chunk a focus is flying into promotes first.
func _focus_distance(coord: Vector2i, focus_chunks: Array) -> int:
	var best := 1 << 30
	for fc in focus_chunks:
		best = mini(best, maxi(absi(coord.x - fc.x), absi(coord.y - fc.y)))
	return best


func _promote(coord: Vector2i) -> void:
	var node := TerrainChunk.new()
	node.terrain = self
	node.chunk_coord = coord
	node.chunk_cells = CHUNK
	node.cell_px = cell_px()
	node.position = Vector2(coord * CHUNK) * cell_px()
	add_child(node)
	node.rebuild()
	_live[coord] = node


func _demote(coord: Vector2i) -> void:
	var node: TerrainChunk = _live[coord]
	_live.erase(coord)
	node.queue_free()


# --- Save / load (seed + diffs) -------------------------------------------
#
# A save stores world_seed + these runtime edits, not the whole grid: the world
# regenerates deterministically from the seed, so only the DELTA from a fresh
# generation has to be persisted (save/save_game.gd). Load calls clear_all(),
# regenerates from the seed (IslandGen + the Cairn), then apply_diffs().

## The runtime edits since generation, cell -> final type. A copy, so a caller
## (the save) cannot mutate the live map by holding the returned dict.
func edit_diffs() -> Dictionary:
	return _edits.duplicate()


## Replay a set of edits (cell -> type) onto the resident grid — the load path's
## last step after regenerating from the seed. Each write goes through set_cell
## (so a promoted chunk re-merges) and is recorded back into `_edits`, so the
## loaded world can be saved again and produce the same diff set.
func apply_diffs(diffs: Dictionary) -> void:
	for cell in diffs:
		var type: int = int(diffs[cell])
		set_cell(cell, type)
		_edits[cell] = type


## Wipe the world back to empty: demote every live chunk, drop all resident data
## and all recorded edits. The load path calls this before regenerating from the
## saved seed, so a loaded world never carries cells from the world it replaced.
func clear_all() -> void:
	for coord in _live.keys():
		(_live[coord] as TerrainChunk).queue_free()
	_live.clear()
	_chunks.clear()
	_edits.clear()


# --- Introspection (streaming loop + tests) -------------------------------

## Every chunk coordinate that holds resident data — the map view reads this to
## mark which coarse regions contain terrain (an island blip) versus open sky.
## Cheap: it is the sparse dictionary's keys, only chunks ever written solid.
func chunk_coords() -> Array:
	return _chunks.keys()


func live_chunk_count() -> int:
	return _live.size()


func promoted_chunk(coord: Vector2i) -> TerrainChunk:
	return _live.get(coord, null)


func is_promoted(coord: Vector2i) -> bool:
	return _live.has(coord)


## Solid cells stored in a chunk's resident data — the number a promoted chunk's
## collider coverage must equal.
func solid_cells_in_chunk(coord: Vector2i) -> int:
	if not _chunks.has(coord):
		return 0
	var n := 0
	for b in (_chunks[coord] as PackedByteArray):
		if TerrainDB.is_solid(b):
			n += 1
	return n


## Total solid cells across the whole resident map (data only — independent of
## what is promoted). Used to prove promote/demote never touches the truth.
func total_solid_cells() -> int:
	var n := 0
	for c in _chunks:
		n += solid_cells_in_chunk(c)
	return n
