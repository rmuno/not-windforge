class_name Crew
extends Node2D

## Container that owns every Player character, and the one place they are
## created — Fleet's pattern applied to people. Online it spawns through a
## MultiplayerSpawner so every peer sees every body; offline it just adds a
## child. Callers use spawn_player() either way and never branch on network
## state.
##
## Authority model differs from ships on purpose: a Ship is simulated by
## the server and followed by clients, but a Player character is driven by
## the peer who owns it (set_multiplayer_authority in player.gd), because
## walking must answer local input instantly — a server round-trip on every
## step is the clunk charter's enemy. The server still owns *spawning*.

var _spawner: MultiplayerSpawner
var _spawn_ready := false
var _pending: Array[Dictionary] = []


## Same reasoning as Fleet: the spawner must exist before any spawn packet
## can arrive, and _ready() is too late to guarantee that.
func _enter_tree() -> void:
	if _spawner == null:
		_spawner = MultiplayerSpawner.new()
		_spawner.name = "PlayerSpawner"
		_spawner.spawn_path = ^".."
		_spawner.spawn_function = _spawn_from_data
		add_child(_spawner)


func _ready() -> void:
	_spawn_ready = true
	var queued := _pending.duplicate()
	_pending.clear()
	for data in queued:
		_spawn(data)


## Server/single-player only. `scale` is the body multiplier from the
## world-scale experiment — it rides the payload because every peer must
## build the same-sized body from the same data.
func spawn_player(peer: int, pos: Vector2, scale := 1.0) -> Player:
	if not NetUtil.is_authority(self):
		return null
	return _spawn({"peer": peer, "pos": pos, "scale": scale})


func _spawn(data: Dictionary) -> Player:
	if NetUtil.is_online(self):
		if not _spawn_ready:
			_pending.append(data)
			return null
		return _spawner.spawn(data) as Player
	var p := _spawn_from_data(data) as Player
	add_child(p)
	return p


## Server-side: remove a departed peer's body. The spawner replicates the
## removal; ships stay adrift on disconnect, people do not linger.
func despawn(peer: int) -> void:
	if not NetUtil.is_authority(self):
		return
	var p := player_for(peer)
	if p != null:
		p.queue_free()


func players() -> Array[Player]:
	var out: Array[Player] = []
	for child in get_children():
		if child is Player:
			out.append(child)
	return out


func player_for(peer: int) -> Player:
	for p in players():
		if p.peer_id == peer:
			return p
	return null


## Runs on every peer with the same payload — identical bodies everywhere.
func _spawn_from_data(data: Variant) -> Node:
	var d := data as Dictionary
	var p := Player.new()
	p.peer_id = int(d["peer"])
	p.position = d["pos"]
	p.net_position = p.position  # seed the smoothing shadow (see Player)
	var scale_mult := float(d.get("scale", 1.0))
	if scale_mult != 1.0:
		p.scale_body(scale_mult)
	return p
