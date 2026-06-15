---
name: godot-directed-arrow-line
description: Replace a Godot Line2D with a custom _draw Node2D that renders a directed arrow while keeping the Line2D-style API, and verify via headless run.
source: auto-skill
extracted_at: '2026-06-12T04:24:20.529Z'
---

# Godot Directed Arrow Line

Use this when a targeting/aiming visual is a `Line2D` (straight segment only) and the
user wants a directed segment with an arrowhead, or any shape Line2D can't draw.

## Line2D can't draw arrowheads — swap to a custom `_draw` Node2D

`Line2D` only renders a polyline. To draw shaft + arrowhead with a controllable color,
make a small `Node2D` script that draws in `_draw()`. The key to a near-zero-diff change
is to **keep the same API the callers already use**, so call sites don't change at all.

In this project `attack_arrow` (`$CanvasLayer/AttackArrow`) was used only via `.points`,
`.visible`, `.width`, `.default_color`. The replacement reimplements those as exported
vars / a `points` property, each calling `queue_redraw()` on set:

```gdscript
extends Node2D

@export var width: float = 8.0:
    set(value): width = value; queue_redraw()
@export var default_color: Color = Color(1, 0, 0, 1):
    set(value): default_color = value; queue_redraw()
@export var arrow_length: float = 28.0
@export var arrow_width: float = 26.0
var points: PackedVector2Array = PackedVector2Array():
    set(value): points = value; queue_redraw()

func _draw() -> void:
    if points.size() < 2: return
    var start := to_local(points[0])
    var end := to_local(points[1])
    var dir := end - start
    var dist := dir.length()
    if dist <= 0.001: return
    dir /= dist
    var head_len: float = min(arrow_length, dist)
    var shaft_end := end - dir * head_len      # stop shaft where head begins (no overlap)
    draw_line(start, shaft_end, default_color, width, true)
    var perp := Vector2(-dir.y, dir.x)
    var p1 := end - dir * head_len + perp * (arrow_width * 0.5)
    var p2 := end - dir * head_len - perp * (arrow_width * 0.5)
    draw_colored_polygon(PackedVector2Array([end, p1, p2]), default_color)
```

Prefer this vector-drawing approach over an `arrow.png` sprite: color/width stay
adjustable and there's no rotation/scaling math or asset dependency. Offer the texture
route only if the user wants a specific art style.

## Edit the `.tscn` by hand: change node type + add ext_resource

Two edits to the scene file:

1. Add a script `ext_resource` in the header (a new id, e.g. `id="4_arrow"`).
   A hand-added script resource can omit `uid=`; Godot reimports it fine.
2. Change the node line `type="Line2D"` → `type="Node2D"` and add
   `script = ExtResource("4_arrow")` directly under it. Leave the property lines
   (`width`, `default_color`) — they map to the exported vars.

After editing, grep every `<node>.` call site to confirm only the preserved
properties are used, so `Main.gd`-style callers need no changes.

## Verify by actually loading the project headless

`_draw` output can't be asserted headless, but loading the project proves the new
script + retyped scene parse and load with no errors:

```cmd
<godot_console.exe> --headless --path "C:\path\to\project" --quit-after 120
```

Exit code 0 with no `SCRIPT ERROR` / `Parse Error` in output = scripts and scene loaded.
State plainly that visual appearance still needs an editor check.

## cmd gotcha: a Godot dir named like `*.exe` misparses as a command

The console build here lives at
`D:\...\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe` — the
*containing directory* ends in `.exe`. Running the full quoted path as the first command
token fails with "文件名、目录名或卷标语法不正确" (invalid filename/dir/volume syntax),
even though `if exist` confirms the file is there. Also, appending `2>&1` to that form
made it fail too.

Fix: `cd /d` into the directory first, then invoke the bare exe name:

```cmd
cd /d "D:\...\Godot_v4.6.3-stable_win64.exe" && Godot_v4.6.3-stable_win64_console.exe --headless --path "C:\proj" --quit-after 120
```

Note: a tool `directory`/cwd param may be restricted to workspace dirs, so the engine
folder can't be set as cwd that way — put the `cd /d` inside the command string instead.
