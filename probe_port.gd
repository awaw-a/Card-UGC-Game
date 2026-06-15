extends Node

# Probe test: is UDPServer.listen() a reliable "is this ENet port free" check?
# If listen() succeeds while a room_server ENet server is bound to the same
# port, then server.gd's _is_port_free() gives false positives and reaps live rooms.

func _ready() -> void:
	var port := 5001
	print("[PROBE] testing UDPServer.listen(%d) while ENet room_server should hold it" % port)
	var probe := UDPServer.new()
	var err := probe.listen(port)
	if err == OK:
		probe.stop()
		print("[PROBE] RESULT: listen() SUCCEEDED -> _is_port_free returns TRUE (FALSE POSITIVE: live room would be reaped)")
	else:
		print("[PROBE] RESULT: listen() failed err=%d -> _is_port_free returns FALSE (correct: port seen as busy)" % err)
	get_tree().quit()
