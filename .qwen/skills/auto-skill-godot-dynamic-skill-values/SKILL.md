---
name: godot-dynamic-skill-values
description: Add random-range and dynamic-variable numeric values to card skill effects (editor + engine + tooltip) in this Godot card game, backward-compatibly.
source: auto-skill
extracted_at: '2026-06-15T04:23:43.173Z'
---

# Godot Dynamic / Random Skill Values

Use when the user wants skill effect numbers to be more than a fixed integer — e.g. "let me enter 2-4 and roll a random value each time" and/or "damage equal to total cards on field + 1". The clean approach is a single resolver the engine calls, plus an editor value-mode switch. Do NOT scatter the logic across every effect type.

## Architecture (key insight)

A skill effect's `value` is read in exactly TWO places, and both must agree:
1. **Execution** — `SkillEngine._execute_skill`, the `var value: int = int(eff.get("value", 1))` line.
2. **Tooltip/editor text** — `SkillEngine._format_effect_sentence`, the `var value: int = int(eff.get("value", 0))` line.

Introduce two helpers so behavior and display stay in sync:
- `_resolve_value(eff, source_card, context) -> int` — computes the live number at execution time.
- `_describe_value(eff) -> String` — produces human text ("3", "2-4", "(total cards on field+1)") for tooltips, which have NO live context.

## Data format (must stay backward compatible)

Keep `value` as a plain int for old cards. Add OPTIONAL fields, and select mode by which are present (this avoids a separate "mode" enum in the data and keeps old saves valid):
- random range: `value_min`, `value_max`
- variable: `value_var` (string id), `value_offset` (int, can be negative)

Resolution priority in `_resolve_value`: if `value_var` set → `_var_value(var) + value_offset`; else if `value_min`/`value_max` present → `rng.randi_range(min,max)` (swap if min>max); else → `int(eff.get("value", 1))`. Make random vs variable mutually exclusive in the UI; offset only stacks with variable.

```gdscript
static func _resolve_value(eff: Dictionary, source_card: CardData, context: Dictionary) -> int:
    var var_id: String = eff.get("value_var", "")
    if var_id != "":
        return _var_value(var_id, source_card, context) + int(eff.get("value_offset", 0))
    if eff.has("value_min") and eff.has("value_max"):
        var vmin := int(eff.get("value_min", 1)); var vmax := int(eff.get("value_max", 1))
        if vmax < vmin: var t := vmin; vmin = vmax; vmax = t
        var rng = context.get("rng", null)
        return rng.randi_range(vmin, vmax) if rng is RandomNumberGenerator else randi_range(vmin, vmax)
    return int(eff.get("value", 1))
```

## Determinism for online play

Use the RNG already in the skill context (`context.get("rng")`, which is `GameState.game_rng`) — NOT global `randi_range` — so both clients roll identically. The context already exists and is passed everywhere effects resolve. The existing `_roll_percent`/`_shuffle_targets` helpers already use this rng; follow the same pattern.

## Variables come from the skill context (no new plumbing)

`make_skill_context` already carries `player_field`, `enemy_field`, `active_hand`. That's enough for the common variable set — define it as `const` ids on `SkillEngine` and compute in `_var_value`:
- `field_total` = ally + enemy card count; `field_ally`; `field_enemy`
- `empty_ally` = `pf.slots.size() - count`; `empty_enemy`
- `hand_count` = `active_hand.size()`; `mana_current` = `pf.current_mana`

Count cards with a helper that skips null slots. Guard every field for null.

## Tooltip text

`_describe_value` returns: variable → `"(name+offset)"` using `Locale.term("value_var", id)` (sign-aware: `+`, `-`, or bare); range → `"min-max"` (or just the number if equal); else `str(value)`. Then change `_format_effect_sentence` to use this STRING in place of the int — switch its `%d` value placeholders to `%s` for every effect branch (damage/heal/draw/shield/the default), keeping the zh/en split intact.

## Editor UI (SkillEditor.gd popup)

The effect popup builds controls in code. Add after the existing Effect+Value row:
- a "value mode" `OptionButton`: 0=fixed, 1=random, 2=variable;
- a random row (min/max SpinBox), a variable row (variable OptionButton + offset SpinBox), both `visible = false` initially;
- a local toggle lambda connected to the mode dropdown that shows the matching row and hides the fixed `val_spin`/label.

Store the new control refs in `popup_form`. On load (editing existing effect), detect mode from the present fields and set the dropdown + call the toggle. In `_on_popup_ok`, write ONLY the active mode's fields (`value_min/max` OR `value_var/value_offset`) so `_resolve_value`/`_describe_value` pick the right branch. Add a `VAR_KEYS` const + `_setup_var_dropdown` mirroring the existing `BUFF_KEYS`/`_setup_buff_dropdown` pattern, and `Locale` `value_var` term entries (zh+en) plus `skill_editor.value_mode*`/`value_min`/`value_max`/`value_var`/`value_offset` UI strings.

## Scope note

`cost`/`hp`/`atk` are plain ints used in mana checks, summon validation, card rendering, and serialization — NOT routed through the skill engine. Making THOSE dynamic is far more invasive (timing: when recomputed? how shown in hand? online sync) and is a separate, larger task. Confirm scope before attempting; the user here deliberately kept cost fixed.

## Verify

Whole-project compile catches type errors (e.g. `var state := game.export_initial_state()` fails because the export return is untyped — use explicit `: Dictionary`):
```cmd
"C:\path\to\Godot_console.exe" --headless --editor --quit
```
Exit code 0, no `SCRIPT ERROR` = good.

Headless logic test — run as a SCENE (not `--script`, so autoloads load):
```cmd
"C:\path\to\Godot_console.exe" --headless res://TestDynamicValue.tscn
```
Throwaway `extends Node` scene that calls `SkillEngine._resolve_value`/`_describe_value` directly with hand-built contexts (`BattleField.new`, fill slots, set `current_mana`, pass a seeded `RandomNumberGenerator`). Assert: fixed value unchanged (backward compat); 50 random rolls all in [min,max] AND vary; each variable computes correctly with + and - offsets; `_describe_value` text in both `Locale.language = "zh"` and `"en"`. Delete the .gd/.tscn/.uid afterward.
