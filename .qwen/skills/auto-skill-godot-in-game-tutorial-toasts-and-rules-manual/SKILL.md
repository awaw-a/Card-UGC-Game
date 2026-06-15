---
name: godot-in-game-tutorial-toasts-and-rules-manual
description: Teach game mechanics in a Godot game via reusable fade-in/out tip toasts wired into existing rule-rejection points, plus a static scrollable rules-manual popup, all localized.
source: auto-skill
extracted_at: '2026-06-14T14:48:07.284Z'
---

# In-Game Tutorial: Contextual Toasts + Rules Manual

Use this when a game enforces rules in code but only surfaces rejections/feedback via `print()` (invisible to players), and the user wants to teach mechanics without a heavyweight scripted step-by-step tutorial. The recommended shape is **contextual fade toasts (teach-by-doing) + a static rules-manual popup (reference)**, with no forced first-run walkthrough unless asked.

## Decide scope first (it's a design question)

Before coding, present the tradeoff and let the user pick. Typical options, cheapest to most expensive:
- Toast-only (just surface the existing rule rejections in-game).
- Toasts + static rules manual (recommended default — small effort, fills the "no in-game feedback" gap, plus a browsable reference).
- Full scripted guided match (best teaching, but needs action-locking, a step state machine, and network handling — defer to later).

A separate "first-entry one-time core-loop intro" is an orthogonal add-on; ask separately whether it's wanted.

## Survey what the codebase already gives you

- **Existing rule-rejection points**: grep for `print(` near guard `return`s (e.g. taunt checks, turn gates, hand-full, deck reshuffle). These are exactly where a toast belongs — keep the `print` and add a toast alongside.
- **Localization system**: if a `Locale.t()` autoload exists, all tutorial text must route through it (add both languages). Never hardcode strings.
- **Existing popup pattern**: reuse the project's blur-overlay popup (e.g. a pile/card viewer) for the rules manual instead of inventing a new one — same `CanvasLayer` + `blur.gdshader` + close-on-background-click idiom.
- **No toast system**: this is the common gap. The project likely has floating combat numbers but no general message banner.

## Build a reusable toast banner

Add state vars and a self-initializing builder so the first `_show_toast` call lazily creates the label. Anchor it near the top-center, ignore mouse, scale with the project's `_ui_scale()`.

```gdscript
var toast_label: Label
var toast_tween: Tween

func _build_toast() -> void:
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 0.18
	toast_label.anchor_bottom = 0.18
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	toast_label.add_theme_stylebox_override("normal", style)
	toast_label.modulate.a = 0.0
	$CanvasLayer.add_child(toast_label)
	_scale_toast()

func _scale_toast() -> void:
	if toast_label == null: return
	var s := _ui_scale()
	toast_label.add_theme_font_size_override("font_size", max(12, int(20 * s)))
	toast_label.custom_minimum_size = Vector2(360 * s, 0)
	toast_label.offset_left = -180.0 * s
	toast_label.offset_right = 180.0 * s

# Pass a Locale key; args fill % placeholders.
func _show_toast(key: String, args := []) -> void:
	if toast_label == null:
		_build_toast()
	toast_label.text = Locale.t(key, args)
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_label.modulate.a = 0.0
	$CanvasLayer.move_child(toast_label, $CanvasLayer.get_child_count() - 1)  # keep on top
	toast_tween = create_tween()
	toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.15)
	toast_tween.tween_interval(1.8)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.4)
```

Call `_scale_toast()` from the responsive-layout function alongside the other scaled controls.

## Wire toasts into existing rule points (keep the print)

At each guard, add the toast without removing the log:

```gdscript
if game.turn_number <= 1:
	print("Turn 1: attacks are not allowed!")
	_show_toast("tip.no_attack_turn1")
	return
```

Watch for correctness traps when detecting outcomes:
- **Kill detection**: if `execute_attack` doesn't null the slot (death cleanup runs later in `_apply_deaths`), capture the victim *before* the call and test `victim != null and not victim.is_alive()` — don't check `slot == null` post-attack.
- **Reward feedback** (mana on kill / on discard): place the toast right after the action confirms success (`if game.discard_card(...): _show_toast(...)`).

## Add a static rules manual

Add a small "How to Play" button next to existing bottom-bar buttons (scale + position it in the responsive-layout function like its neighbors, and add a `BASE_*_BUTTON_SIZE` const). Open a blur popup cloned from the project's existing viewer:

```gdscript
func _show_help_popup():
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)
	var bg := ColorRect.new()
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	bg.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: popup_layer.queue_free())
	popup_layer.add_child(bg)
	# Panel > MarginContainer > VBox(title, ScrollContainer(body Label), close button)
	# body.text = Locale.t("help.body", [SkillEngine.MAX_HAND_SIZE])  # inject live constants
```

Manual-content tips:
- Group mechanics by theme (resource/cost, turn flow, combat rules, skill triggers).
- Inject live constants (hand cap, etc.) via `%d` args instead of hardcoding numbers that could drift.
- Use a `ScrollContainer` + word-wrapped `Label` so long text never overflows.

## Localize all tutorial text

Add `tip.*` and `help.*` keys in **both** language tables of the `Locale` autoload. When using `edit` to splice keys into the dictionary, double-check you didn't accidentally drop the line you anchored on (e.g. `card.cost`) — re-read the region after the edit.

## Network caveat (call it out)

Toasts wired into local hotseat/single-player action paths fire for the acting player. In online play, actions go through RPC/host-apply flows, so the *opponent* side won't see outcome toasts (e.g. their kill). If full online parity is needed, drive toasts off `EventBus` signals instead — flag this as a larger change and confirm before doing it.

## Verify headlessly

Boot the project and load the battle scene to confirm the new UI builds and runs without errors:

```bat
"<godot_console.exe>" --headless --quit-after 5
"<godot_console.exe>" --headless Main.tscn --quit-after 30
```

The Godot binary may not be on `PATH`; the user may supply an explicit path. Treat exit code 0 with no parser/runtime errors as the baseline, then confirm fade/positioning visually.
