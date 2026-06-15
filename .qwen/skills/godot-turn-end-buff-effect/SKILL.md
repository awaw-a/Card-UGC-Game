---
name: godot-turn-end-buff-effect
description: Add a new Godot card buff that resolves at turn end, decrements duration independently, and appears in editors/UI.
source: auto-skill
extracted_at: '2026-06-11T05:09:50.077Z'
---

# Godot Turn-End Buff Effect

Use this procedure when adding a new status effect/buff that must resolve during the turn system rather than only changing card stats.

## Trace the existing buff lifecycle first

1. Search for these concepts before editing: `BUFF_`, `status_effects`, `apply_buff`, `tick_buffs`, `end_player_turn`, skill editor buff lists, card UI buff indicators, and serialization.
2. Identify which player owns a buff. In this project, buffs include an `owner` field when applied, so turn-end effects should filter by owner rather than by board side alone.
3. Check whether `tick_buffs(owner_player)` already decrements duration. If a new buff needs custom timing, prevent it from being decremented twice.
4. Locate UI/editor mappings separately from engine logic; adding only the constant makes existing cards unable to select or recognize the buff in summaries.

## Implement a turn-end resolving buff

1. Add a new `SkillEngine.BUFF_*` constant with a stable string id.
2. Add any card-level aggregator/helper needed for the effect, such as summing values across multiple independent buff instances.
3. For buffs that perform a side effect at end of the owning player's turn:
   - Add a dedicated method on `CardData`, e.g. `process_<buff_name>(owner_player) -> int`.
   - Iterate `status_effects`, skip effects with a different `owner`, and skip other `buff_id`s.
   - Apply or return the effect value once per matching buff instance.
   - Decrement that buff instance's `duration` after resolving.
   - Remove expired or non-positive instances after the loop, iterating removal indexes in reverse.
4. In `tick_buffs`, explicitly `continue` for the custom-timed buff so generic duration ticking does not also decrement it.
5. In `GameState.end_player_turn`, run the custom processing before the generic tick. Use `current_player` as the owner for effects that trigger at the active player's turn end.
6. Apply resource changes through existing field methods such as `BattleField.add_mana()` so caps and invariants remain centralized.

## Expose the buff everywhere cards are authored or displayed

1. Add the buff to `SkillEngine.format_skill_tooltip` or equivalent tooltip maps.
2. Add it to `SkillEditor.BUFF_KEYS` in the exact same order as all buff-name arrays and dropdown items.
3. Update dropdown item ids and any index-based special cases after inserting the new buff. Index-sensitive logic often controls whether value is editable or whether a percent label is shown.
4. Update short/long summary name arrays in skill and card editors.
5. Update `CardUI` indicator colors and tooltip name maps so active buffs are visible and understandable.

## Verify

1. Search for stale buff name arrays and index literals after editing.
2. Re-read changed sections to ensure the new `BUFF_KEYS` order matches all display arrays.
3. Run Godot headlessly when the executable is available:

```cmd
"C:\path\to\Godot.exe" --headless --path "C:\path\to\project" --quit
```

4. If headless launch fails because the executable path is invalid or unavailable, report that runtime validation could not be completed and ask for an editor test.
5. Manual scenario to test: create a card that applies the new buff with value `N` and duration `D`; end that card owner's turn; verify the resource increases by `N`, duration decreases by one, and the buff disappears after `D` owner end-turn resolutions.
