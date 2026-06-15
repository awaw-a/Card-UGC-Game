extends Node

# ============================================
# Room server subprocess — pure ENet relay for one room.
# Spawned by server.gd via OS.create_process. Listens on a single port,
# accepts up to 2 player clients, and relies on Godot's default
# server-relay so the two clients' broadcast RPCs reach each other.
#
# Command line:
#   godot --headless room_server.tscn -- --room-port=5001 --room-code=1234
# ============================================

const DEFAULT_ROOM_PORT := 5001
const EMPTY_SHUTDOWN_DELAY := 5.0  # seconds to wait, after the room empties, before quitting

var room_port: int = DEFAULT_ROOM_PORT
var room_code: String = ""

var peer: ENetMultiplayerPeer
var player_count: int = 0
var had_players: bool = false


func _ready() -> void:
	_parse_args()
	if not _start():
		push_error("[ROOM %s] Failed to bind port %d — exiting" % [room_code, room_port])
		get_tree().quit(1)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-port="):
			room_port = int(arg.split("=")[1])
		elif arg.begins_with("--room-code="):
			room_code = arg.split("=")[1]


func _start() -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(room_port, 2)
	if err != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[ROOM %s] Relay listening on port %d" % [room_code, room_port])
	return true


func _on_peer_connected(id: int) -> void:
	player_count += 1
	had_players = true
	print("[ROOM %s] Peer %d connected (%d/2)" % [room_code, id, player_count])
	if player_count >= 2:
		# Tell both clients the room is full so they can show "opponent connected".
		NetworkManager.notify_room_ready.rpc()
		print("[ROOM %s] Room full — notified clients" % room_code)


func _on_peer_disconnected(id: int) -> void:
	player_count = max(0, player_count - 1)
	print("[ROOM %s] Peer %d disconnected (%d/2)" % [room_code, id, player_count])
	if player_count <= 0:
		_shutdown_if_empty()


func _shutdown_if_empty() -> void:
	await get_tree().create_timer(EMPTY_SHUTDOWN_DELAY).timeout
	if player_count <= 0:
		print("[ROOM %s] Empty — shutting down" % room_code)
		get_tree().quit(0)
