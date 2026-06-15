---
name: godot-p2p-asset-sync-and-effect-mirroring
description: Mirror locally-triggered visual effects to remote peers in an authority/intent RPC model, and transfer optional binary assets (card art) P2P-only with a manifest + progress + timeout skip.
source: auto-skill
extracted_at: '2026-06-12T17:50:46.436Z'
---

# Godot P2P Asset Sync & Effect Mirroring

Use this when a Godot multiplayer game shows a visual effect (splash art, animation, popup) correctly in single-player/hotseat but NOT online, and/or when you need to ship user-generated binary assets (images) between peers without a relay server.

## Authority/intent model silently skips local-only visual effects

In an authority + intent-RPC architecture, online actions do NOT run the same code path as single-player. Single-player calls `game.execute_attack(...)` then `_show_splash(card)` inline. Online, the same click instead sends `rpc_intent_attack` → the host runs `_host_apply_attack(...)` → broadcasts authoritative state. Those `_host_apply_*` functions resolve game logic but never call the visual-effect functions, so BOTH players see nothing — not even the text/fallback branch.

Symptom to recognize: "effect X works in single-player but not online, and even the no-asset fallback is missing." That last clue means the effect function isn't being *called* online, not that an asset failed to load.

Fix: add a dedicated effect RPC and fire it from the authority's apply functions.

1. New EventBus signal `rpc_splash_received(player, slot_index)` and a `NetworkManager` RPC:
```gdscript
@rpc("any_peer", "call_remote")
func rpc_splash(player: int, slot_index: int):
    EventBus.rpc_splash_received.emit(player, slot_index)
```
2. An authority-side helper that shows it locally AND broadcasts. Capture the acting entity BEFORE death/cleanup runs, or the slot may be empty by the time you read it:
```gdscript
func _authority_splash(player: int, slot_index: int) -> void:
    if slot_index < 0: return
    var field = game.player_field if player == 1 else game.player2_field
    var card = field.slots[slot_index]
    if card != null:
        _show_splash(card)                       # local
    if NetworkManager.is_online:
        NetworkManager.rpc_splash.rpc(player, slot_index)  # remote
```
   Call `_authority_splash(player, source_slot)` inside each `_host_apply_*` that should animate, placed right after the action resolves and **before** `_apply_deaths()`.
3. Receiver: do NOT blindly guard with `if player == my_player: return`. That guard assumes "I already showed it locally," which is only true for the *authority*. In a host-is-always-authority model, the non-authority **client never shows the splash locally on its own actions** — it only sends an intent and waits. Worse, since `rpc_splash` is `@rpc("any_peer","call_remote")` and only the authority ever broadcasts it, the authority never receives its own call, so the only peer that ever reaches the receiver is the client. The `player == my_player` guard therefore suppresses the client's splash for its OWN actions, producing the exact bug "host sees splashes, client sees nothing, ever." Fix: drop the guard — the receiver should always replay via the remote-effect helper. There is no double-play risk because `call_remote` never echoes to the sender.
4. Match the single-player trigger set exactly — e.g. if SP splashes on attacks and activated skills but not on summon-triggered skills, mirror only those same cases.
5. Gate the effect on a VALID action, not just a click. An attack against an empty/invalid target (clicking an empty enemy slot, own cards) should trigger nothing. Single-player code that calls `_show_splash` right after `game.execute_attack(...)` will fire even when `execute_attack` no-ops (returns `{}`), so add an explicit null-target check before sending the intent (`if their_field.slots[index] == null: cancel(); return`), and on the authority capture `execute_attack`'s return and only `_authority_splash` when it actually resolved. The targeting branches (summon/activate) usually already null-check; the plain-attack branch is the one that leaks.

This keeps existing serialized state sync untouched; the RPC is a fire-and-forget presentation cue, not gameplay state.

## Optional binary asset transfer: manifest-first, best-effort

To ship UGC images between players, first confirm the transport mode. Originally this project wanted **server/room-code multiplayer to avoid card-art byte transfer** (bandwidth) while direct P2P/LAN synced art. The user LATER approved adding card-art transfer to server-relay mode too, gated by a server-side enable/disable toggle (default OFF). So treat "server mode = no art" as a configurable default, not a hard rule — but never broaden a transport's behavior without explicit approval.

- **Direct P2P: always transfer art.** `DirectLobby.gd` owns the send/receive/ACK flow unconditionally.
- **Server-relay: transfer only when the server opted in.** Gate with `if is_dedicated_server and not server_allows_card_art: return` (see relay section below for the full toggle plumbing). When disabled, `Lobby.gd` skips `_send_card_arts()` and treats art transfer as complete/zero so battle start is not blocked.
- **Wire art handlers in BOTH lobbies.** `DirectLobby.gd` and `Lobby.gd` (relay) each own `_send_card_arts()`, `_on_card_art_manifest()`, `_on_card_art_received()`, `_update_art_progress_label()`, timeout handling, and `EventBus.rpc_card_art_*` connections. The relay lobby gates the send on the server toggle; direct sends unconditionally.
- **Always send a manifest first, even for zero assets.** The receiver can only know "transfer complete" if told the total. If a peer has 0 custom assets and you send nothing, the receiver's `total` stays `-1` and it waits until timeout every game. Send `rpc_card_art_manifest(total)` before any bytes; `total == 0` lets the receiver finish waiting instantly.
- **Direct P2P: explicit peer targeting. Relay: broadcast.** In direct P2P the host is ENet peer/server `1`; send with `rpc_id(opponent_peer_id, ...)` (a joining client falls back to peer `1` before `opponent_peer_id` is set) so host→client delivery is explicit. In relay mode the real opponent id is hidden (`opponent_peer_id == -1`), and the room server will NOT forward a targeted `rpc_id` to the other client — you MUST broadcast `.rpc()` (target peer `0`) and let the relay fan it out. Encode this in `_card_art_target_peer()`:
```gdscript
func _card_art_target_peer() -> int:
    # Relay hides the real opponent id; room server won't forward targeted rpc_id,
    # so broadcast (0) and let the relay fan out to the other client.
    if is_dedicated_server:
        return 0
    if opponent_peer_id > 0:
        return opponent_peer_id
    return 1 if not is_host else 0
```
```gdscript
func send_card_arts(arts: Array) -> void:
    # Direct P2P always allowed; relay only when the server opted in.
    if is_dedicated_server and not server_allows_card_art:
        return
    var target_peer := _card_art_target_peer()
    var total := arts.size()
    if target_peer > 0:
        rpc_id(target_peer, "rpc_card_art_manifest", total)
    else:
        rpc_card_art_manifest.rpc(total)
    for art in arts:
        if target_peer > 0:
            rpc_id(target_peer, "rpc_card_art", art.card_index, art.ext, art.bytes, total)
        else:
            rpc_card_art.rpc(art.card_index, art.ext, art.bytes, total)
```
- **Make ready/card-list RPC reliable.** The art bytes are mapped by `card_index` into the receiver's deserialized opponent deck, so `rpc_player_ready(card_data_list)` should be `@rpc("any_peer", "call_remote", "reliable")`. If ready arrives late or is dropped while art arrives, the receiver has no target cards to rewrite.
- **Cap per-asset size** before reading bytes (`MAX_ART_BYTES`), skip oversized files.
- **Dedup received bytes by content hash.** Name saved files `<md5>.<ext>` so identical assets collapse to one file; wipe the net-asset dir at launch since it's session-scoped.
- **Rewrite the deserialized opponent card's `art_path`** to the locally-saved path on receive, so the battle scene loads the local copy.

## Preserve local art after authority state sync — restore BOTH own and opponent local paths

In authority-state multiplayer, the host serializes and broadcasts full game state. The serialized `art_path` strings are the **authority's own local paths**, which are meaningless on the other machine. A non-authority client applying that state therefore loses the correct local path for EVERY card — both its own cards and the opponent's downloaded art. The downloaded opponent art already lives on the client's disk (saved to `user://net_arts/<hash>` in `PlayerData.opponent_battle_deck`), so the fix is to remap paths back to local copies after applying state.

Critical bug to avoid: building the restore lookup from `PlayerData.battle_deck` ONLY. That fixes the client's own cards but leaves opponent cards pointing at the authority's invalid local paths — producing the exact symptom **"non-authority client can't see the opponent's card art, while the authority sees both sides."** The lookup MUST also seed from `PlayerData.opponent_battle_deck`.

Fix by restoring local art paths immediately after applying authority state on the non-authority client:

1. Build a lookup keyed by card identity, seeded from BOTH `PlayerData.opponent_battle_deck` (downloaded opponent art) AND `PlayerData.battle_deck` (own cards). Seed opponent first, then own, so own cards win on identity collisions.
2. After `game.apply_initial_state(state)`, walk `player_hand`, `player2_hand`, `shared_deck`, `shared_discard`, and both field slot arrays.
3. For matching cards, copy back the local `art_path` before refreshing UI.
4. Match on a stable card identity key such as `name|cost|max_hp|atk|gender`; avoid relying on object identity because state deserialization creates new `CardData` instances.

```gdscript
func _restore_local_art_paths() -> void:
    if not NetworkManager.is_online or NetworkManager.is_authority():
        return
    var local_art_by_key := {}
    # Opponent arts were downloaded in the lobby and saved to local net_arts paths.
    # The authority state carries the authority's OWN paths, so remap to our local copies.
    for card in PlayerData.opponent_battle_deck:
        if card is CardData and card.art_path != "":
            local_art_by_key[_card_identity_key(card)] = card.art_path
    # Our own cards take precedence on identity collisions.
    for card in PlayerData.battle_deck:
        if card is CardData and card.art_path != "":
            local_art_by_key[_card_identity_key(card)] = card.art_path
    # ...walk hands / decks / slots and copy back matching art_path...
```

Only run this restoration on `NetworkManager.is_online and not NetworkManager.is_authority()`. The server room mode still should not receive opponent art; this restoration is for preserving local art paths that already exist on the client's disk.

## Diagnose delivery vs display before patching RPC direction

When opponent art is missing on one side, the instinct is to suspect "host→client RPC direction failure" and pile on ACK-gating / explicit `rpc_id` targeting / reliable flags. Before doing that, **prove whether the bytes actually arrive** — the bug is often in battle-side path restoration (above), not in RPC delivery.

Build a faithful two-process direct-P2P repro that exercises the REAL path (`host_game` / `join_game`, NOT the dedicated-server relay path, since `send_card_arts` early-returns on `is_dedicated_server` and the relay repro never触发s the P2P code):

- One headless script, role switched by `--role=host|join` via `OS.get_cmdline_user_args()`. Host calls `host_game()`, join calls `join_game("127.0.0.1")`.
- Both sides connect the real `EventBus.rpc_card_art_*` signals and, on connect, send `rpc_player_ready` then `send_card_arts`, ACKing each received art exactly like the lobby does.
- Use **realistic payloads (~800KB per art)** to force ENet packet fragmentation — a 16-byte synthetic payload won't surface size/fragmentation issues. The synthetic bytes bypass `read_art_bytes`/`MAX_ART_BYTES`, so you can exceed the cap freely for stress.
- Log per-step counters and a FINAL PASS/FAIL (`ready_recv`, `manifest`, `arts_recv/N`, `ack_recv/N`).

Run two instances from a single `.bat` (`start /B` the host, `timeout /t 2`, then `start /B` the join, then `timeout` to let them finish), redirecting each to its own log. On Windows cmd, redirect inside the batch file (`^> _host.log 2^>^&1`) rather than fighting shell-level redirection from the tool, which can fail with "文件名、目录名或卷标语法不正确".

If both directions report PASS (as happened here — bytes, manifest, and ACK all delivered bidirectionally even at 800KB), the RPC layer is NOT the bug. Pivot to the display/path-restore logic. Clean up the repro scripts, batch, and logs afterward.

## Completion / timeout UX: wait for receive + upload ACK, manual button only when stalled

Driven by user preference here: in direct P2P, both players should enter battle automatically only after two conditions are true: (1) this peer has received all opponent art, and (2) the opponent has ACKed all of this peer's uploaded art. If either direction stalls, wait up to a bounded timeout (10s in the latest implementation), then show a manual "enter game" button rather than force-starting.

- Add an explicit ACK signal/RPC path. On successful save of each incoming art, call back to the sender; the sender tracks unique ACKed `card_index` values.
```gdscript
# EventBus.gd
signal rpc_card_art_ack_received(card_index: int, total: int)

# NetworkManager.gd
func send_card_art_ack(card_index: int, total: int) -> void:
    if is_dedicated_server:
        return
    var target_peer := _card_art_target_peer()
    if target_peer > 0:
        rpc_id(target_peer, "rpc_card_art_ack", card_index, total)
    else:
        rpc_card_art_ack.rpc(card_index, total)

@rpc("any_peer", "call_remote", "reliable")
func rpc_card_art_ack(card_index: int, total: int):
    EventBus.rpc_card_art_ack_received.emit(card_index, total)
```
- Track both directions in the waiting-room script: `_opponent_arts_received/_opponent_arts_total` for downloads and `_my_arts_acked/_my_arts_total` plus `_acked_my_art_indices` for uploads. Set `_my_arts_total = arts.size()` right before `NetworkManager.send_card_arts(arts)`.
- Gate auto-start on both directions, not just receiving opponent art:
```gdscript
func _art_transfer_complete() -> bool:
    var opponent_done := _opponent_arts_total >= 0 and _opponent_arts_received >= _opponent_arts_total
    var mine_done := _my_arts_total >= 0 and _my_arts_acked >= _my_arts_total
    return opponent_done and mine_done
```
- Show combined progress text such as `卡面同步中：接收 %d/%d，上传确认 %d/%d...`. This makes the failure mode visible: if host art never reaches client, the host will stall at `上传确认 0/N` instead of entering battle with missing art.
- Keep the timeout behavior: when both players are ready but `_art_transfer_complete()` is false, start a deadline (`ART_WAIT_TIMEOUT := 10.0`), enable `_process`, and only show `StartNowButton` after expiry. The button calls the same `_begin_start()` path as auto-start.
- Do not apply this byte/ACK flow to server/room-code mode. In `Lobby.gd`, if `NetworkManager.is_dedicated_server`, skip `_send_card_arts()` and treat art transfer as complete/zero so server联机模式 remains no-card-art-transfer.

## Handle out-of-order ready vs art arrival

Reliable RPCs can still be observed in an order that makes the receiver's deck unavailable when art bytes arrive. If `_on_card_art_received()` runs before `_on_rpc_ready()` has deserialized `PlayerData.opponent_battle_deck`, do not drop the saved path.

- Keep a dictionary like `_pending_opponent_art_paths: Dictionary = {}` keyed by `card_index`.
- On art receive: save bytes, cache `card_index -> saved_path`, and if the opponent deck already exists, write the path immediately.
- On ready receive: build `PlayerData.opponent_battle_deck`, then call `_apply_pending_opponent_arts()` to backfill cached paths.
- Optionally `await get_tree().process_frame` between sending `rpc_player_ready.rpc(card_data_list)` and `_send_card_arts()` to reduce ordering races, but still keep the cache because timing is not guaranteed.

```gdscript
func _on_card_art_received(card_index: int, ext: String, bytes: PackedByteArray, total: int):
    _opponent_arts_total = total
    var saved_path := PlayerData.save_net_art(bytes, ext)
    if saved_path != "" and card_index >= 0:
        _pending_opponent_art_paths[card_index] = saved_path
        if card_index < PlayerData.opponent_battle_deck.size():
            PlayerData.opponent_battle_deck[card_index].art_path = saved_path
        NetworkManager.send_card_art_ack(card_index, total)
    _opponent_arts_received += 1
```

## Gotcha: dynamically-created Controls need explicit offsets on resize

A `Label`/`Button` created in code with only `anchor_left/right/top` set (no `anchor_bottom`, no `offset_*`) can collapse to zero height — text/content is invisible. Likewise, top-left toolbar buttons in a waiting room may look correct initially if positioned with `position = Vector2(...) * s`, but after fullscreen → windowed resize they can keep stale rect extents and not shrink correctly. Prefer explicit top-left anchors plus recomputed offsets in both creation and `_scale_*` handlers:
```gdscript
btn.anchor_left = 0.0; btn.anchor_right = 0.0
btn.anchor_top = 0.0;  btn.anchor_bottom = 0.0
btn.offset_left = 10.0 * s
btn.offset_top = 10.0 * s
btn.offset_right = btn.offset_left + 120.0 * s
btn.offset_bottom = btn.offset_top + 40.0 * s
btn.custom_minimum_size = Vector2(120, 40) * s
```
For centered/anchored controls, also set `anchor_bottom` + `offset_top/offset_bottom` + `custom_minimum_size`, and mirror those in any `_scale_waiting_room()` resize handler:
```gdscript
lbl.anchor_top = 0.05; lbl.anchor_bottom = 0.05
lbl.offset_top = 0.0;  lbl.offset_bottom = 60.0 * s
lbl.custom_minimum_size = Vector2(0, 60.0 * s)
```
If adding a dynamically-created timeout/skip button, assign a stable `name` (for example `StartNowButton`) so resize code can find it and scale it later.

## Verify (autoload-aware)

`--check-only --script Foo.gd` falsely reports `Identifier not found: EventBus/NetworkManager` because autoloads aren't registered in single-script mode — ignore those. Validate the whole project instead so autoloads exist:
```cmd
call "C:\path\Godot_console.exe" --headless --path "C:\proj" --editor --quit
```
On Windows cmd, wrap a spaced-path exe in `call "..."` (a bare quoted path can fail with "文件名、目录名或卷标语法不正确"). Exit code 0 with no `SCRIPT ERROR`/`Compile Error` lines means it compiled. Two-process P2P behavior (progress, mirrored effects, stall button) still needs manual two-client testing — state that clearly rather than claiming it verified.
