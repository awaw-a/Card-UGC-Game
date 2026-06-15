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

## Verify safely

1. Re-read the changed scene and search for stale full-rect anchors or old dimensions.
2. Run Godot headlessly when the executable is available:

```cmd
godot --headless --path "C:\path\to\project" --quit
```

3. If `godot` is not on `PATH`, report that runtime validation was unavailable and ask for visual verification in the editor.
4. Verify at least these contexts in the editor: battlefield slots, hand containers, library grids, selection grids, hidden action-button mode, status indicators, and drag previews.

Do not assume the working directory is a Git repository. Check repository status before relying on `git diff`; if Git is unavailable, verify by rereading the exact files instead.
