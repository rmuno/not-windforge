extends Node

## Autoload `Net` — connection lifecycle only.
##
## Deliberately thin. It owns the peer and nothing else; it does not know what
## a Ship is. Gameplay code asks its own node whether it has authority
## (`Ship.is_authority()`) rather than asking a global, so ships stay correct
## in tests and single-player where this autoload may not even be involved.
##
## Transport is ENet over UDP. For a Steam release this is the layer that would
## be swapped for SteamMultiplayerPeer — nothing above it should need to change,
## which is the reason for keeping it this small.

signal hosted
signal joined
signal join_failed
signal peer_joined(id: int)
signal peer_left(id: int)
signal disconnected

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 4

var _peer: ENetMultiplayerPeer = null


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.connected_to_server.connect(func() -> void: joined.emit())
	multiplayer.connection_failed.connect(func() -> void: join_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: disconnected.emit())


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Net: could not host on port %d (error %d)" % [port, err])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	print("Net: hosting on port %d" % port)
	hosted.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Net: could not reach %s:%d (error %d)" % [address, port, err])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	print("Net: connecting to %s:%d" % [address, port])
	return OK


func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null


func is_online() -> bool:
	return NetUtil.is_online(self)


func is_server() -> bool:
	return NetUtil.is_authority(self)


func peer_count() -> int:
	return multiplayer.get_peers().size() if is_online() else 0
