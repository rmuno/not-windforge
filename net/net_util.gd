class_name NetUtil
extends RefCounted

## The single place "am I networked?" is decided.
##
## **Godot assigns an `OfflineMultiplayerPeer` by default.** That means
## `multiplayer.has_multiplayer_peer()` returns **true in single-player**, and
## any code branching on it silently takes the network path with nobody on the
## other end. This shipped as "the game never gives you a ship", and it passed
## every test, because the offline peer also reports `is_server() == true` — so
## authority checks kept working while the online/offline check was inverted.
##
## Excluding that peer is the whole job. Never call `has_multiplayer_peer()`
## directly; call this.

static func is_online(node: Node) -> bool:
	if not node.is_inside_tree():
		return false
	var peer := node.multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


## True on the server, and true in single-player.
static func is_authority(node: Node) -> bool:
	return not is_online(node) or node.multiplayer.is_server()
