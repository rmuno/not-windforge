class_name Fleet
extends Node2D

## Container that owns every Ship in the world, and the one place ships are
## created. Online it spawns through a MultiplayerSpawner; offline it just adds
## a child. Callers use `spawn_ship(data)` either way and never branch on
## network state.
##
## Using MultiplayerSpawner rather than hand-rolled RPCs buys late-join for
## free: a player connecting mid-session receives every existing ship, grid and
## all, because the spawn payload *is* the ship.

var _spawner: MultiplayerSpawner
var _spawn_ready := false
var _pending: Array[Dictionary] = []
## Client side: the readiness announcement is sent exactly once per session.
var _ready_announced := false


## Built in _enter_tree(), not _ready(). _ready() can be deferred, and a client
## whose spawner does not exist yet silently drops the server's spawn packets —
## the ship simply never appears. _enter_tree() runs synchronously inside
## add_child(), so the spawner is always in place before any traffic arrives.
func _enter_tree() -> void:
	if _spawner == null:
		_spawner = MultiplayerSpawner.new()
		_spawner.name = "ShipSpawner"
		_spawner.spawn_path = ^".."  # spawned ships become children of this Fleet
		_spawner.spawn_function = _spawn_from_data
		add_child(_spawner)

	# Wired here for the same reason the spawner is: the signal can fire the
	# moment the peer finishes its handshake, which may be before _ready().
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)


## MultiplayerSpawner does not begin tracking its spawn node until it has fully
## entered the tree. A ship spawned before that point is created on the server
## and **never replicated** — no error, no warning, it simply does not exist for
## anyone else. Spawns that arrive too early are queued and flushed here.
func _ready() -> void:
	_spawn_ready = true
	var queued := _pending.duplicate()
	_pending.clear()
	for data in queued:
		spawn_ship(data)
	# A Fleet that entered the tree on an already-connected peer never sees
	# connected_to_server fire, so readiness is also evaluated right here.
	_announce_ready_if_possible()


# --- Late-join handshake --------------------------------------------------
#
# The spawner replays each ship's ORIGINAL payload to a joiner, which is stale
# for any ship built on, mined or shot since — so the server follows up with
# the current grid. That follow-up is an RPC addressed to a node the joiner
# only has once the spawn packets have been processed, and a Godot RPC to a
# node that does not exist yet is dropped in silence.
#
# This used to be papered over with `await create_timer(0.5)` on the server:
# a bet that half a second is longer than the spawn traffic takes. It wins on
# localhost and loses on a real link — the exact class of race this project
# keeps paying for. The CLIENT is the only peer that can actually know, so it
# tells the server: once its own Fleet is fully in the tree (spawner tracking,
# spawn packets accepted) and the connection is up, it announces readiness and
# the server answers with grids. No timing assumptions anywhere in the path.


func _on_connected_to_server() -> void:
	_announce_ready_if_possible()


func _announce_ready_if_possible() -> void:
	if _ready_announced or not _spawn_ready:
		return
	if not _is_online() or multiplayer.is_server():
		return
	# Ask the peer, not the id. A Godot ENet client owns a unique id from the
	# moment create_client() returns, so "id != 1" says nothing about whether
	# the socket is up — announcing then is an RPC into a hole ("Trying to
	# call an RPC via a multiplayer peer which is not connected"). This path
	# runs on whichever of _ready()/connected_to_server comes second.
	if multiplayer.multiplayer_peer.get_connection_status() \
			!= MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ready_announced = true
	_client_ready.rpc_id(1)


## Server side of the handshake. `any_peer` because it is the joiner calling;
## the sender id is taken from the multiplayer API, never from an argument, so
## no peer can ask for another peer's catch-up.
@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	for ship in ships():
		if is_instance_valid(ship):
			ship.push_grid_to(id)


## Server/single-player only. Returns the new Ship on the authority; clients
## receive theirs through replication and get null here.
func spawn_ship(data: Dictionary) -> Ship:
	if not _is_authority():
		return null
	if _is_online():
		if not _spawn_ready:
			_pending.append(data)  # flushed in _ready(); see the note above
			return null
		return _spawner.spawn(data) as Ship
	var ship := _spawn_from_data(data) as Ship
	add_child(ship)
	return ship


## Convenience for authoring a ship from a cell layout rather than a payload.
## `pilot` must be passed here rather than assigned to the returned Ship —
## anything not in the payload never reaches the clients, which would leave
## every remote peer thinking the ship belonged to someone else.
## `extra` is merged into the payload for the fields that are NOT arguments —
## site residency, nest-hood, creature identity. It exists because "assign it on
## the Ship afterwards" is the trap AGENTS.md names: a post-spawn field exists
## on the server ONLY, so a nest arrived at every client as an ordinary ship and
## fell out of the sky (caught by net_smoke, 2026-08-26). If a value changes
## what the RECEIVER does with the body, it belongs in here.
func spawn_ship_from_cells(cells: Dictionary, pos: Vector2, pilot := 1, rot := 0.0, unit := 1.0, faction := 0, extra := {}) -> Ship:
	var grid := PackedInt32Array()
	grid.resize(cells.size() * 4)
	var i := 0
	for cell in cells:
		var type: int = cells[cell]
		grid[i] = cell.x
		grid[i + 1] = cell.y
		grid[i + 2] = type
		grid[i + 3] = roundi(BlockDB.max_hp(type))
		i += 4

	var payload := {
		"grid": grid,
		"pos": pos,
		"rot": rot,
		"linvel": Vector2.ZERO,
		"angvel": 0.0,
		"assist": true,
		"pilot": pilot,
		"unit": unit,  # world-scale feel multiplier — see Ship.scale_unit
		"faction": faction,
	}
	for key in extra:
		payload[key] = extra[key]
	return spawn_ship(payload)


func ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for child in get_children():
		if child is Ship:
			out.append(child)
	return out


## MultiplayerSpawner calls this on every peer with the same payload, so every
## peer derives an identical ship from identical data.
func _spawn_from_data(data: Variant) -> Node:
	return Ship.from_data(data as Dictionary)


func _is_online() -> bool:
	return NetUtil.is_online(self)


func _is_authority() -> bool:
	return NetUtil.is_authority(self)
