---
name: godot-fixed-card-ui-layout
description: Diagnose and fix oversized reusable Godot card controls while preserving container compatibility and drag previews.
source: auto-skill
extracted_at: '2026-06-11T03:51:06.457Z'
---

# Godot Fixed Card UI Layout

Use this procedure when a reusable card scene displays a `Panel` much larger than its intended card face.

## Diagnose the actual source of stretching

1. Read the card `.tscn` and identify the root `Control`, visual background, labels, buttons, and containers.
2. Search all `.gd` and `.tscn` files for scene instantiation before changing sizing. Check whether the card is inserted into `GridContainer`, `HBoxContainer`, `VBoxContainer`, buttons, battlefield slots, or free-positioned controls.
3. Distinguish minimum size from fixed size:
   - `custom_minimum_size` only constrains the minimum.
   - `anchors_preset = 15` with right and bottom anchors at `1.0` makes a control fill its parent.
   - A background `Panel` using the same full-rect anchors inherits the oversized parent rectangle.
4. Treat this as intentional only if the card is meant to fill its allocated slot. Otherwise, it is a layout mismatch rather than a useful responsiveness feature.

## Convert the card to a bounded reusable control

1. Pick one canonical card size based on all usage contexts, not just the card scene in isolation.
2. On the root `Control`:
   - Remove full-rect anchors.
   - Use top-left anchors (`anchors_preset = 0`).
   - Set `custom_minimum_size` to the canonical size for container participation.
   - Set `offset_right` and `offset_bottom` to the same dimensions for standalone instances.
3. On the background `Panel`:
   - Remove full-rect anchors if they can inherit an oversized parent.
   - Give it explicit offsets matching the canonical card dimensions.
4. Keep child labels and action controls inside an explicit inset. Reserve vertical bands for title, stats, status indicators, and action buttons so controls do not overlap or extend past the background.
5. Move dynamically created indicators in the script when static layout coordinates change.

## Keep dependent representations synchronized

Search scripts for hard-coded copies of the old dimensions. In particular, update drag-preview offsets to the canonical card size. Otherwise, the live card and drag preview will have different bounds.

Also inspect wrapper controls such as battlefield slot buttons. A fixed child card prevents its background from filling the wrapper, but the wrapper may still need centering or explicit sizing depending on the desired presentation.

## Fix mismatched card preview wrappers

When a card itself is correctly bounded at the canonical `120x160` size but a lobby/deck-selection slot still looks too large, the problem is usually the wrapper, not `CardUI.tscn`.

For this project, the waiting/preparation rooms and deck selection pages should use a tight preview wrapper around the card:

- Search for `card_box.custom_minimum_size`, `card_ui_scene.instantiate()`, and `apply_ui_scale(s)` in `Lobby.gd`, `DirectLobby.gd`, `BattleDeckSelect.gd`, `MyCards.gd`, and similar pages.
- If a `PanelContainer` is only a visual card preview frame, size it close to the scaled card face plus small padding, e.g. `Vector2(132, 172) * s` for a `120x160` card at scale `s`. Avoid oversized wrappers like `170x190` unless the extra space contains labels/buttons.
- Put the card inside a `CenterContainer` instead of a plain `VBoxContainer` when there is no extra text below/above the card. This keeps the card centered and avoids the impression that the slot and card sizes do not match.
- On responsive resize, update both the wrapper size and the nested card's `apply_ui_scale(s)`; do not only scale the card.
- For duplicate/import conflict popups, use a fixed preview holder (`CenterContainer`, around `120x150`) and scale the card down (around `0.82`) before hiding actions. This avoids squeezed previews while keeping the popup compact.
- Do not change `CardUI.tscn` canonical dimensions when only one page's preview frame is too large.

### When only the background is oversized

A recurring visual bug in this project is: labels/buttons scale down correctly, but the card background remains a larger rectangle behind them, especially in same-name conflict previews.

Check both the script and the scene:

- In `CardUI.gd::apply_ui_scale(...)`, explicitly sync the root and background sizes before child layout: set root `custom_minimum_size`, root `size`, `Background.custom_minimum_size`, and `Background.size` to `Vector2(120, 160) * ui_scale`, then set background offsets to `0,0,120,160` scaled.
- In `CardUI.tscn`, avoid leaving a fixed `custom_minimum_size = Vector2(120, 160)` on the `Background` child. A scaled root at `0.82` can still show a full-size background if the child minimum size forces it larger.
- In preview builders such as `_make_conflict_summary(...)`, instantiate the card, add it to the tree, call `set_card(card)`, then call `apply_ui_scale(0.82)`, and only then hide actions. This ensures type-specific layout and scaled background agree.
- If a previous fix only changes call order and the background still sticks out, inspect `CardUI.tscn` for child minimum sizes; the scene property can override the script's intended scaled layout.

## Verify safely

1. Re-read the changed scene and search for stale full-rect anchors or old dimensions.
2. Run Godot headlessly when the executable is available:

```cmd
godot --headless --path "C:\path\to\project" --quit
```

3. If `godot` is not on `PATH`, report that runtime validation was unavailable and ask for visual verification in the editor.
4. Verify at least these contexts in the editor: battlefield slots, hand containers, library grids, selection grids, hidden action-button mode, status indicators, and drag previews.

Do not assume the working directory is a Git repository. Check repository status before relying on `git diff`; if Git is unavailable, verify by rereading the exact files instead.
