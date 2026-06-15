---
name: godot-turn-gated-action-restriction
description: Enforce a turn-based gameplay restriction (e.g. no attacks / no enemy-targeting effects on turn 1) across the engine, game-state, and UI layers in this card game.
source: auto-skill
extracted_at: '2026-06-14T14:24:33.409Z'
---

# Godot Turn-Gated Action Restriction

Use this when a rule must forbid certain actions based on the turn counter —
for example "neither side may attack or use enemy-targeting effects on turn 1."
The pattern generalizes to any "during turn N, action X is blocked" rule.

## Understand the turn counter first

Read `GameState.gd` before assuming what the counter means. Here:

- `turn_number` starts at 1 and only increments when play returns to player 1
  (`if current_player == 1: turn_number += 1` in `start_new_turn`). So
  `turn_number` stays `1` for BOTH players' first turns. `turn_number <= 1`
  therefore correctly means "either side's first turn" — do not try to track
  first-turn state per player separately.
- `current_player` is 1 or 2; `active_field()` / `opponent_field()` are relative
  to it. But reactive triggers (on_damaged, on_death) can fire for the NON-active
  player, so do not assume the acting card belongs to `current_player`.

## Enforce authoritatively in the engine, not just the UI

The rule must hold for hotseat, network intents, AND auto-triggered skills
(on_summon, on_damaged). Put the real enforcement at the lowest common point:

1. `GameState.execute_attack`: early-return `{}` when `turn_number <= 1`. This
   covers every attack path (local, `_host_apply_attack`, RPC intents).
2. `SkillEngine._execute_skill`: thread the turn number through the skill context
   and skip individual effects whose resolved targets land on the enemy.

Pass the turn number into the context where it is built
(`GameState.make_skill_context_for_player`):

```gdscript
return {
	... existing keys ...,
	"turn_number": turn_number,
}
```

In `_execute_skill`, AFTER `_resolve_targets` (and after any `random_count`
slicing), skip the whole effect if it would hit an enemy of the SOURCE card:

```gdscript
var turn_no: int = int(context.get("turn_number", 99))
if turn_no <= 1 and _targets_include_enemy(targets, source_card, context):
	print("[SkillEngine] Turn 1: '%s' enemy-targeting effect skipped" % skill_name)
	continue
```

Determine "enemy" relative to the source card's own field, NOT
`context.enemy_field` (which is keyed to the acting player). This makes the rule
correct for reactive triggers:

```gdscript
static func _enemy_field_of_source(source_card: CardData, context: Dictionary) -> BattleField:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	if pf != null and source_card in pf.slots: return ef
	if ef != null and source_card in ef.slots: return pf
	return ef

static func _targets_include_enemy(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	var enemy_field: BattleField = _enemy_field_of_source(source_card, context)
	if enemy_field == null: return false
	for t in targets:
		if t != null and t in enemy_field.slots: return true
	return false
```

Skipping per-effect (rather than per-skill) is deliberate: a mixed skill like
"heal self + damage enemy" still resolves its friendly effects on turn 1 and only
drops the enemy effect. Default `turn_number` to a large number (99) so contexts
built without it are never accidentally gated.

## Add UI guards only to avoid wasted actions / dangling target arrows

The engine already enforces the rule, so the UI layer (`Main.gd`) only needs to
stop the player from entering a doomed targeting state. Add `turn_number <= 1`
checks at action entry points:

- `_on_attack_requested`: return before setting `current_attacker_idx` / showing
  the arrow.
- `_on_skill_activated`: when `_skill_needs_targeting(skill)` is true, block on
  turn 1 before entering `activate_targeting`. In this engine, manual targeting
  (`TARGET_SINGLE` / `TARGET_SIDES`) ALWAYS points at the enemy field, so that
  predicate cleanly identifies the skills to block.
- Drag-summon on_summon skills: only enter `summon_targeting` when
  `_skill_needs_targeting(skill) and game.turn_number > 1`; otherwise let the
  summon complete and the engine silently drops the enemy effect.

Do NOT broadly block auto-resolved skills (TARGET_ALL_ENEMIES, gender targets) in
the UI. They go through the non-targeting branch where the engine surgically skips
only enemy targets while still applying friendly parts — a UI block would over-
restrict them. Match feedback to the project's existing convention: this codebase
signals blocked actions with `print()` (same as the taunt checks); there is no
toast/status-message system, so do not invent one unless asked.

## Verify the rule with a headless Node scene (autoloads needed)

Effect appliers call `EventBus`, and the engine references `SkillEngine`/
`CardData`, so a `--script` SceneTree run gives false "nonexistent function" /
"Identifier not found" errors. Run a real scene instead so autoloads load:

1. Write `_verify_*.gd extends Node`, do the work in `_ready()`, end with
   `get_tree().quit()`.
2. Write a one-node `_verify_*.tscn` referencing it.
3. Run from the project directory (set shell `directory`), no `--path`, no
   `2>&1` (cmd rejects it on Windows):

```
"C:\path\Godot_..._console.exe" --headless _verify_turn1.tscn
```

Assert the three cases that matter: enemy-target effect skipped on turn 1 but
lands on turn 2; self/ally effect still works on turn 1; an enemy-only mechanic
like charm is a no-op on turn 1 (target stays on field, hand unchanged). Then
boot the full project (`--headless --quit-after 5`, exit 0, no parser errors) to
confirm every edited script compiles with autoloads present. Delete the temp
`.gd`, `.tscn`, and `.uid` files when done.
