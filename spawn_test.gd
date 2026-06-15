extends Node

# Replicate server.gd _spawn_room() EXACTLY and check whether the spawned
# room subprocess manages to bind UDP 5001 within a few seconds.

func _ready() -> void:
	var port := 5001
	var code := "spawntest"
	var exe := OS.get_executable_path()
	print("[SPAWN] OS.get_executable_path() = %s" % exe)
	var args := PackedStringArray([
		"--headless", "res://room_server.tscn", "--",
		"--room-port=%d" % port, "--room-code=%s" % code,
	])
	var pid := OS.create_process(exe, args)
	print("[SPAWN] OS.create_process returned pid=%d" % pid)
	# Poll the port for ~6 seconds.
	await get_tree().create_timer(6.0).timeout
	var probe := UDPServer.new()
	var err := probe.listen(port)
	if err == OK:
		probe.stop()
		print("[SPAWN] RESULT: port %d still FREE after 6s -> room subprocess FAILED to bind" % port)
	else:
		print("[SPAWN] RESULT: port %d is BUSY -> room subprocess bound OK (err=%d)" % [port, err])
	get_tree().quit()
