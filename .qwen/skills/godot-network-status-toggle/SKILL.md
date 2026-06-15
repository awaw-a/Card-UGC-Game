---
name: godot-network-status-toggle
description: Add a non-invasive Godot UI toggle for viewing local vs opponent multiplayer status without changing control perspective.
source: auto-skill
extracted_at: '2026-06-11T06:45:53.397Z'
---

# Godot Network Status Toggle

Use this procedure when a multiplayer Godot card game needs to let the player quickly inspect opponent public resources such as HP, mana, and hand count, while preserving the local player's board orientation and permissions.

## Clarify the interaction first

If several UX patterns are possible, ask which one the user wants before editing:

- Always show both players' status in the middle bar.
- Show opponent status only on hover/hold.
- Add a button that toggles the status bar between local and opponent info.

A toggle button is useful when screen space is limited and the player wants explicit control over what the central status bar displays.

## Keep viewing status separate from gameplay perspective

Do not change existing functions that define ownership, board orientation, hand visibility, or operation authority just to show opponent resources. In this project, keep helpers such as `_view_player()`, `_my_field()`, `_their_field()`, `_my_hand()`, `is_my_turn()`, and slot UI mapping intact.

Instead, add a separate UI-only state, for example:

```gdscript
var show_enemy_status: bool = false
```

Use that state only when choosing which field/hand count to display in the status label.

## Add the UI control in the existing info bar

1. Locate the existing status label and end-turn button in the scene, such as `MiddleInfoBar/InfoHBox/ManaLabel` and `EndTurnButton`.
2. Add a small `StatusToggleButton` beside the status label in the same container so it inherits the existing layout.
3. Add an `@onready` reference in the main script and connect `pressed` in `_ready()`.
4. The button handler should only flip the UI-only state and call `update_entire_screen()`.

Example handler:

```gdscript
func _on_status_toggle_pressed():
	show_enemy_status = not show_enemy_status
	update_entire_screen()
```

## Format the status label without changing controls

In `update_entire_screen()`:

1. In hotseat/offline mode, hide the toggle button and keep the existing behavior of showing the current player's status.
2. In online mode, show the toggle button.
3. Choose the displayed player from the UI-only toggle:

```gdscript
var viewed_player := _view_player()
if NetworkManager.is_online and show_enemy_status:
	viewed_player = _opponent_player()
var f = _field_for_player(viewed_player)
var hand_size := _hand_for_player(viewed_player).size()
```

4. Use text that makes it clear this is only a status view, not a control-side switch, such as `Viewing P2 Enemy | Mana: ...`.
5. Update the button text to indicate the next action, for example `Enemy Info` when currently viewing self and `My Info` when currently viewing opponent.

## Verification

1. Run a headless Godot load check after editing.
2. On Windows, if the executable path contains unusual segments or spaces, call it through PowerShell's `&` operator rather than relying on `cmd` quoting:

```cmd
powershell -NoProfile -Command "& 'D:\path\to\Godot_console.exe' --headless --path 'C:\path\to\project' --quit"
```

3. Manually verify hotseat mode: the toggle is hidden and the status bar still follows the current player.
4. Manually verify online mode from both host and client: the toggle switches only HP/mana/hand-count display; board orientation, hand contents, targeting, and end-turn authority remain tied to the local player.
