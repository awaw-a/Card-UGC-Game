---
name: godot-enet-connection-robustness
description: Add connection timeouts, failure signals, and input validation to Godot ENet multiplayer, and verify scripts that reference autoloads.
source: auto-skill
extracted_at: '2026-06-12T00:00:00.000Z'
---

# Godot ENet Connection Robustness

Use this when hardening Godot ENet multiplayer (lobby/dedicated-server or direct P2P) so that unreachable servers, refused connections, and bad input fail gracefully instead of hanging the UI.

## ENet connects are asynchronous — `OK` does not mean connected

`ENetMultiplayerPeer.create_client(address, port)` returns `OK` even when the server is unreachable. The UI will sit on "Connecting..." forever because nothing ever fires a failure. There is no built-in connect timeout.

Add a manual deadline tracked in `_process` on the network autoload:

```gdscript
const CONNECT_TIMEOUT := 8.0  # seconds
var _lobby_deadline: float = 0.0   # <= 0 means inactive
var _game_deadline: float = 0.0

func _now() -> float:
    return Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
    if _lobby_deadline > 0.0 and _now() > _lobby_deadline:
        _lobby_deadline = 0.0
        _fail_lobby_connection()
    if _game_deadline > 0.0 and _now() > _game_deadline:
        _game_deadline = 0.0
        _fail_game_connection()
```

- Set `_xxx_deadline = _now() + CONNECT_TIMEOUT` right after a successful `create_client`.
- Clear the deadline (`= 0.0`) the moment a real peer connection arrives (in `peer_connected`/`_on_peer_connected`), and in `close_connection`.
- Track separate deadlines per connection phase if matchmaking has multiple hops (e.g. connect to lobby port, then reconnect to an assigned game-room port).

## Emit dedicated failure signals, don't just reset state

Define signals like `lobby_connection_failed` / `game_connection_failed`. On timeout (and in `peer_disconnected` when the connection was still pending), close the peer, null it, set `is_online = false`, and emit. UI scenes connect these signals to re-enable buttons, restore the lobby panel, and show an actionable message ("Check the IP, port, and host firewall").

Distinguish a pending-failure from a normal disconnect by checking whether the deadline was still active:

```gdscript
func _on_lobby_disconnected(id):
    var was_pending := _lobby_deadline > 0.0
    _lobby_deadline = 0.0
    ...
    if was_pending:
        lobby_connection_failed.emit()
```

## RPC routes by NODE PATH — handler must live on the same node on both ends

This is the highest-impact, least-obvious failure mode. Godot routes an RPC to the node at the **same scene-tree path** on the receiver as the caller. When the client calls `rpc_id(1, "lobby_request", ...)` from the `NetworkManager` autoload (`/root/NetworkManager`), the packet is delivered to the server's `/root/NetworkManager.lobby_request` — NOT to a different node like `/root/Server` where the real handler lives.

Symptom: connection succeeds (so no timeout fires), the client shows "Checking..." / "Connecting..." forever, and the server never logs the request. The request was delivered to a stub function on the wrong node and silently dropped. The reverse path (server's response) breaks identically because the client has no matching node.

Fix: route lobby/matchmaking RPCs through a node that exists on BOTH ends — the shared network autoload — and forward to the real handler via a registered callback:

```gdscript
# On the shared autoload (exists on client AND server):
var lobby_request_handler: Callable  # server.gd registers this

@rpc("any_peer", "call_remote")
func lobby_request(json_str: String) -> void:
    if lobby_request_handler.is_valid():
        lobby_request_handler.call(multiplayer.get_remote_sender_id(), json_str)

func send_lobby_response(peer_id: int, json_str: String) -> void:
    rpc_id(peer_id, "lobby_response", json_str)  # reply through the shared node

# server.gd registers on startup:
NetworkManager.lobby_request_handler = Callable(self, "_handle_lobby_request")
```

A `@rpc` stub on a separate node that just does `pass` is a red flag — it means RPCs are being aimed at the wrong node.

## Verify RPC round-trips end-to-end with a headless test client

Compile-checking does not prove RPCs are routed correctly. Stand up the real dedicated server (`--headless server.tscn`) and a throwaway headless client scene that connects, sends one request, prints the response, and `get_tree().quit()`s with a hard timeout cap so it never hangs. Confirm the response arrives AND the server logs the request. Delete the temp `.gd`/`.tscn`/`.uid` after.

Diagnostic tip: if `create_server` fails with "Couldn't create an ENet host" (err 20), the port is already bound — often a previous instance still running. Check with `netstat -ano -p UDP | findstr <port>` and kill the stale PID before restarting. After changing server code, the old running instance still serves OLD code — restart it.

## Validate input on both client and server

Put validation in shared `static func`s on the network autoload so client and server use identical rules (room codes, addresses). Always validate again server-side — never trust the client. Reject with an explicit response status (`invalid_code`, `no_ports`) and log malformed/unknown requests rather than silently dropping them.

## Dedicated-server port allocation

- Check the return value of `create_server` — it can fail if the port is already bound. The original code ignored it.
- Prefer scanning a range for a genuinely free port (binding, skipping on error) over blind round-robin `next_port++`, which collides under churn. Track `used_ports` and release on room free.
- Make the port range configurable via command line so the same build deploys anywhere:

```gdscript
for arg in OS.get_cmdline_user_args():
    if arg.begins_with("--port-start="):
        game_port_start = int(arg.split("=")[1])
# launch: godot --headless server.tscn -- --port-start=5001 --port-end=5020
```

## Verifying scripts that reference autoloads (important gotcha)

`godot --headless --check-only --script Foo.gd` compiles the file in isolation and will FALSELY report `Identifier not found: EventBus` (or any autoload singleton), because autoloads aren't registered in single-script mode. Do not treat this as a real error.

Instead validate the whole project so autoloads are registered:

```cmd
"D:\path\Godot_console.exe" --headless --editor --quit
```

Exit code 0 with no `SCRIPT ERROR` / `Compile Error` lines means all scripts compiled, including ones that reference autoloads.

## Deployment note for this server architecture

A public-IP rental works only if UDP is open for BOTH the lobby port AND the whole game-room port range (e.g. 4567 + 5001-5020) in the host/cloud firewall/security group. On a cloud VM this is usually TWO layers: the provider's security group AND the OS firewall (Windows Defender inbound rules) — open both. The Windows `.bat` launcher won't run on Linux — use `godot --headless server.tscn` there.

Clients connect to a public server with NO code change if the lobby UI already has an IP input field that falls back to `127.0.0.1` only when blank — players just type the public IP. Grep for `connect_to_lobby` / `127.0.0.1` to confirm the field exists before planning any code change.

## Spawned room subprocess inherits project context — no `--path` needed

`server.gd` spawns rooms via `OS.create_process(OS.get_executable_path(), ["--headless", "res://room_server.tscn", "--", ...])` WITHOUT a `--path` arg. Worry: will the child find `res://` when the lobby is launched from some arbitrary cwd on the server? Verified answer: **yes, no change needed.** The child inherits the parent's project resolution, so `res://room_server.tscn` loads correctly even when the lobby itself was started from a non-project directory (e.g. `cd C:\Windows\Temp && godot --headless --path C:\proj server.tscn`).

How to verify this locally before touching server code (model "ship from binary + source", same as on the server): start the lobby from a non-project cwd with `--path` pointing at the project, run a throwaway headless client that connects and sends one `create_room`, then prove the room subprocess actually bound its port with `netstat -ano -p udp | findstr 5001` AND check the lobby log shows `Room 'xxxx' created on port 5001 (pid ...)`. A `status=ok` response alone is NOT proof — it only means the lobby replied; confirm a real process is listening on the room port. Clean up temp test files/scenes and kill leftover Godot PIDs afterward.

## One MultiplayerPeer per SceneTree — relaying needs a separate process per room

A single Godot process has exactly one `multiplayer.multiplayer_peer`. A lobby server bound to the lobby port therefore CANNOT also host/relay separate game rooms in the same process: extra `ENetMultiplayerPeer`s created for rooms are never polled by the SceneTree and can't forward game RPCs. Symptom: clients "connect" to the room port (`is_online=true`) but the room never sees the second peer, so matchmaking stalls and code falls through to a single-player branch.

For a broadcast-`.rpc()` + authority-model game (most hobby projects), the lowest-churn fix is **one dedicated relay subprocess per room**:

- Lobby `create` finds a free port, spawns a relay subprocess, and returns the port. Both players connect to it as clients; Godot's default server-relay forwards their broadcast RPCs to each other. Game code barely changes.
- The relay scene is a tiny `Node` that `create_server(port, 2)`, counts `peer_connected`, broadcasts a `notify_room_ready` RPC at 2/2, and `get_tree().quit()`s when empty.
- Spawn with the running executable so it works in-editor and exported:
```gdscript
var pid := OS.create_process(OS.get_executable_path(),
    PackedStringArray(["--headless", "res://room_server.tscn", "--",
        "--room-port=%d" % port, "--room-code=%s" % code]))
```

## `@rpc("authority")` breaks under a relay — player 1 is a client, not peer 1

In the relay model the room subprocess is peer 1 (the authority); the "host" player is just another client. Any gameplay RPC tagged `@rpc("authority")` will be rejected when a client calls it. Change those to `@rpc("any_peer")`. This is safe when every call site is already guarded by your own `is_authority()` check (e.g. `player_number == 1`). Keep `authority` only on RPCs the relay/server itself sends.

## Console-wrapper PID is unreliable for liveness — probe the port instead

`OS.get_executable_path()` on Windows (and exported builds) is a console-wrapper exe that launches the real engine as a short-lived child and exits. So the PID returned by `OS.create_process` dies almost immediately even though the spawned room keeps running. Tracking that PID with `OS.is_process_running(pid)` makes a reaper wrongly free rooms ~instantly after creation.

Robust, cross-platform liveness check: a running room holds its UDP port; a dead one frees it. Probe bindability, with a spawn grace period so a just-launched room isn't reaped before it binds:
```gdscript
func _is_port_free(port: int) -> bool:
    var probe := UDPServer.new()
    if probe.listen(port) == OK:
        probe.stop()
        return true
    return false
# only reap when now - created_at >= ROOM_SPAWN_GRACE (e.g. 8s) AND _is_port_free(port)
```

## GDScript `:=` fails to infer types from untyped returns (bites repeatedly)

`var x := some_call()` errors with "Cannot infer the type of 'x'" when the call's return is untyped Variant — e.g. `Control.get_combined_minimum_size()`, or arithmetic on a `Dictionary` value (`now - room["created_at"]`). Use an explicit type: `var content: Vector2 = ...`, `var age: float = now - float(room["created_at"])`. Watch for this specifically in deferred/helper functions.

Critical: this parse error makes the WHOLE script fail to load, so the autoload/server silently keeps running its LAST good compiled version. A `--editor --quit` pass exits 0 overall, so you must actually scan its output for `SCRIPT ERROR` / `Parse Error` lines — don't trust the exit code alone, and don't pipe the output through `findstr` on Windows cmd (the `2>&1 | findstr` combo often errors out and hides the result). Read the full output.

## Test-timing artifacts in headless multi-client tests

When verifying a relay room with two throwaway headless clients, launching them too far apart (or with too-short self-timers) can make the second miss the ENet handshake window, producing intermittent "only 1/2 connected" failures that look like a code bug but aren't. Give clients generous self-timeouts (~20s) and confirm the success path with both started close together. A human-paced real game has a safer gap. Have the spawned (console-less) relay mirror key events to a `user://` log file so you can inspect what it actually saw.
