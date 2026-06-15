extends Node

# Faithful repro of the REAL flow, but send ready on a timer (not on the
# opponent signal) and log the multiplayer peer list, to see whether two
# clients that went through lobby->reconnect can actually see each other.

var _player := 1
var _code := "test"
var _elapsed := 0.0
var _ready_sent := false
var _received := false
var _in_room := false
var _last_log := 0.0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--player="):
			_player = int(arg.split("=")[1])
		elif arg.begins_with("--code="):
			_code = arg.split("=")[1]
	print("[C%d] start" % _player)
	NetworkManager.lobby_connected.connect(_on_lobby_connected)
	NetworkManager.connected.connect(func(): print("[C%d] OPPONENT signal" % _player))
	multiplayer.peer_connected.connect(func(id): print("[C%d] peer_connected id=%d" % [_player, id]))
	multiplayer.peer_disconnected.connect(func(id): print("[C%d] peer_disconnected id=%d" % [_player, id]))
	EventBus.rpc_ready_received.connect(_on_ready)
	var err := NetworkManager.connect_to_lobby("127.0.0.1", Callable(self, "_on_lobby_resp"))
	print("[C%d] connect_to_lobby err=%d" % [_player, err])

func _on_lobby_connected() -> void:
	if _player == 1:
		NetworkManager.create_room(_code)
	else:
		NetworkManager.join_room(_code)

func _on_lobby_resp(data: Dictionary) -> void:
	print("[C%d] lobby resp: %s" % [_player, JSON.stringify(data)])
	if str(data.get("status", "")) == "ok":
		var port := int(data.get("port", 0))
		var pl := int(data.get("player", _player))
		await get_tree().create_timer(0.3).timeout
		var err := NetworkManager.connect_to_game_room("127.0.0.1", port, pl)
		print("[C%d] connect_to_game_room err=%d" % [_player, err])
		_in_room = true

func _on_ready(card_data_list: Array) -> void:
	_received = true
	print("[C%d] >>> RECEIVED opponent ready: %s" % [_player, JSON.stringify(card_data_list)])

func _process(delta: float) -> void:
	_elapsed += delta
	_last_log += delta
	if _in_room and _last_log > 2.0:
		_last_log = 0.0
		var mp := multiplayer.multiplayer_peer
		var st := (mp.get_connection_status() if mp else -1)
		print("[C%d] t=%.0f peers=%s conn_status=%s online=%s" % [
			_player, _elapsed, str(multiplayer.get_peers()), str(st), str(NetworkManager.is_online)])
	if _in_room and not _ready_sent and _elapsed >= 8.0:
		_ready_sent = true
		print("[C%d] sending ready ONCE at t=%.0f (peers=%s)" % [_player, _elapsed, str(multiplayer.get_peers())])
		NetworkManager.rpc_player_ready.rpc([{"name": "Card_from_C%d" % _player}])
	if _elapsed > 16.0:
		print("[C%d] FINAL: in_room=%s received=%s -> %s" % [
			_player, str(_in_room), str(_received), ("READY_OK" if _received else "READY_LOST")])
		get_tree().quit()
