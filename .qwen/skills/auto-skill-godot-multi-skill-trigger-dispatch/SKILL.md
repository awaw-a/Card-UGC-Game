---
name: godot-multi-skill-trigger-dispatch
description: Fix lost effects when a card has multiple skills sharing one trigger (e.g. on_summon) and one requires target selection in this card game.
source: auto-skill
extracted_at: '2026-06-14T15:20:24.792Z'
---

# Godot Multi-Skill Trigger Dispatch

Use this when a card with two or more skills sharing the same trigger (commonly `on_summon`) only resolves one of them. Typical report: "the second skill doesn't take effect" / "only the first skill fires, the second is lost." A frequent shape is skill 1 = single-target needing player target selection (e.g. charm), skill 2 = area effect (e.g. damage all enemies).

## Root cause to look for

The trigger semantics are "fire ALL skills matching this trigger," but the target-selection UI path collapses to firing a single skill by index.

1. `SkillEngine` usually exposes two dispatchers:
   - `trigger_skills(trigger, card, context)` — loops the card's skills and runs every one whose `trigger` matches. Correct for trigger semantics.
   - `trigger_single_skill(card, skill_index, context)` — runs exactly one skill, and returns early if `skill_index < 0`.
2. Search for the GameState wrapper (e.g. `trigger_summon_skills`). If it calls `trigger_single_skill` with the `skill_index` captured during target selection, only that one skill ever fires.
3. Trace the UI target-selection flow (`Main.gd`): on summon it scans skills, and for the FIRST trigger-skill that `_skill_needs_targeting`, it sets `summon_targeting`/`summon_skill_idx` and `return`s. After the player picks a target, `_on_opponent_slot_clicked` calls the wrapper with that single skill index. The non-targeting fallback branch that would fire the rest (`trigger_summon_skills(slot, -1, -1)`) was skipped by the early `return`, and even if reached, `skill_index = -1` makes `trigger_single_skill` a no-op.

## CRITICAL: pick the right fix — they are NOT interchangeable

There are three fixes. Ask the user (or infer from the card design) which behavior they want BEFORE coding, because choosing wrong silently drops a requested feature:

- **Fix A (fire-all):** correct ONLY when at most one of the same-trigger skills needs target selection. All same-trigger skills share the ONE chosen `target_slot`. If two skills are single-target, both hit the SAME target — usually not what the user wants.
- **Fix B (per-skill walk):** auto-fires all same-trigger skills but pauses at each targeting one for its OWN target. More code, and the online handshake is fragile (see warning below).
- **Fix C (manual activation redesign):** stop auto-firing on_summon entirely; let the player click each skill manually on the summon turn, reusing the existing on_activate flow. **In practice this was the approach the user chose**, because it cleanly solves three problems Fix A/B do not.

Fix B subsumes Fix A. The original bug report (charm + damage-all) is satisfied by any. The follow-up "what if both need a target?" rules out Fix A.

### When the user reports MORE bugs after Fix A/B — go to Fix C

If after a walk-based fix the user reports any of these, Fix B's auto-walk is the wrong foundation; switch to Fix C:
- **Cancelling the first targeting skill drops the rest** — in the auto-walk, cancel (`cancel_attack()`) just clears state, so remaining skills never fire.
- **Two targeting skills: the second still won't trigger** in some path.
- **Online/server side has an extra one-sided failure** — the walk's pending-hint handshake is hard to get right and impossible to fully verify without two live clients.

Do NOT keep patching the auto-walk incrementally. These three symptoms share one root cause: auto-firing a multi-step, target-prompting sequence is inherently fragile across cancel + online replication. Fix C removes the sequencing problem instead of patching it.

## Fix A — fire-all (simplest, single-target-selection only)

Change the GameState wrapper to dispatch ALL matching-trigger skills via `trigger_skills`, ignoring the per-skill index:

```gdscript
func trigger_summon_skills(source_slot: int, target_slot: int, _skill_index: int = -1) -> void:
    var card: CardData = active_field().slots[source_slot]
    if card != null:
        SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_SUMMON, card, make_skill_context(source_slot, target_slot))
```

Why it's safe for the single-targeting case:
- Single-target resolvers read `context.target_slot`; area resolvers ignore it. One shared context serves mixed-target skills.
- Skills fire in `skills` array order, preserving sequencing (charm flips a unit BEFORE area damage hits remaining enemies).
- Keep `skill_index` as `_skill_index` (defaulted) so all ~4 call sites (online/offline x with/without targeting) compile unchanged and become correct automatically.
- Pitfall: ensure the targeting branch still `return`s before the non-targeting fallback so skills don't double-fire.

## Fix B — per-skill walk (multiple independent target selections)

Keep `trigger_summon_skills(slot, target, skill_index)` firing exactly ONE skill by index (the single-skill dispatcher). Drive the sequencing from `Main.gd` with a walk that fires non-targeting skills immediately and stops at each targeting skill to prompt:

```gdscript
# Offline: walk on_summon skills from start_idx; fire non-targeting ones,
# stop at the first that needs a target and enter targeting.
func _advance_summon_skills(source_slot: int, start_idx: int) -> void:
    var card: CardData = _my_field().slots[source_slot]
    if card != null:
        for skill_idx in range(start_idx, card.skills.size()):
            var skill: Dictionary = card.skills[skill_idx]
            if skill.get("trigger", "") != SkillEngine.TRIGGER_ON_SUMMON:
                continue
            if _skill_needs_targeting(skill) and game.turn_number > 1:
                summon_targeting = true
                summon_source_slot = source_slot
                summon_skill_idx = skill_idx
                # show arrow, _sync_targeting_state(), update_entire_screen()
                return
            game.trigger_summon_skills(source_slot, -1, skill_idx)
            _apply_deaths(); _check_charm_overflow()
    # walk finished: clear targeting state, refresh
```

After the player confirms a target in `_on_opponent_slot_clicked`, fire that one skill then RESUME the walk at the next index:

```gdscript
var fired_idx: int = summon_skill_idx
game.trigger_summon_skills(summon_source_slot, index, fired_idx)
_advance_summon_skills(summon_source_slot, fired_idx + 1)  # continue after it
```

### Online (authority/intent) is the hard part of Fix B

This game replicates by having the authority resolve effects and broadcast full state; the summoning client runs its own targeting UI via `_resume_pending_summon_targeting()`, gated on `current_player == my_player`.

- Mirror the offline walk on the authority with `_host_advance_summon_skills(source_slot, start_idx, player)`. `_host_apply_summon` calls it at index 0; `_host_apply_summon_skill` fires the chosen skill then calls it at `skill_index + 1`.
- The walk's pending hint (`pending_summon_target_slot` / `pending_summon_target_skill_idx`) lives only as authority-local vars and is NOT in `export_initial_state()`. To tell the summoning client which skill still needs a target, piggyback the hint onto the broadcast dictionary (NO RPC signature change needed):
  ```gdscript
  # in _broadcast_authority_state, authority side:
  var state: Dictionary = game.export_initial_state()  # NOTE: explicit type; export return is untyped, ":=" fails to infer
  state["_pending_summon_slot"] = pending_summon_target_slot
  state["_pending_summon_skill_idx"] = pending_summon_target_skill_idx
  # in _apply_authority_state, receiver side: read them back, then _resume_pending_summon_targeting()
  ```
- Latent bug this also fixes: the non-authority/joining player previously could not do on-summon targeting at all, because `pending_summon_target_skill_idx` was only ever set ≥ 0 inside the authority-gated `_host_apply_summon`. Carrying the hint in the broadcast fixes that.

## Latent bug present in BOTH the buggy original and worth checking

The no-targeting fallback `trigger_summon_skills(slot, -1, -1)` with single-skill dispatch is a no-op (index -1 returns early). So a card with ONLY non-targeting on_summon skills (e.g. a self-buff) silently fires nothing. Fix A and Fix B both resolve this.

## Fix C — manual activation redesign (RECOMMENDED; what the user ultimately chose)

Stop auto-firing on_summon at all. Make on_summon skills manually activatable on the summon turn, reusing the existing on_activate machinery (target selection, online RPC, `skills_used`). This removes the fragile auto-walk and fixes cancel + two-targeting + online with one model. Concrete steps that worked:

1. **`CardData`**: add `var summoned_this_turn: bool = false`. Clear it in `reset_to_base()` (runs on death/discard — this is what restores skill availability when the card returns to hand), and copy it in `duplicate_card()`.
2. **`BattleField.summon_card`**: set `card.summoned_this_turn = true` on success. Do NOT set it in `place_card` (initial pre-placement shouldn't grant on_summon use).
3. **`GameState.start_new_turn`**: in the per-slot reset loops set `slot.summoned_this_turn = false` — this is the "greys out from turn 2" switch. Keep `trigger_summon_skills` as the single-skill dispatcher (it must NOT set `has_acted`, so on_summon doesn't consume the card's action/attack).
4. **`PlayerData` serialize/deserialize**: persist `summoned_this_turn` so online state syncs it.
5. **`Main.gd`**: delete the auto-walk pieces (`_advance_summon_skills`, `_host_advance_summon_skills`, `_resume_pending_summon_targeting`, `pending_summon_target_*`, and the pending-hint fields in broadcast/apply state). Summon entry no longer fires anything — just refresh UI. In `_on_skill_activated`, allow `TRIGGER_ON_SUMMON` when `card.summoned_this_turn` (gate on `skills_used` per-skill, route to `trigger_summon_skills` NOT `trigger_activate_skills` so `has_acted` is untouched, and don't apply the `has_attacked` restriction). Repurpose the existing `summon_targeting` branch + `_host_apply_summon_skill` / `rpc_intent_summon_skill` for targeting/online.
6. **`CardUI._update_skill_buttons`**: grey + `disabled` a skill button when `skills_used.has(idx)`, OR on_summon outside its summon turn (`not summoned_this_turn`), OR on_activate when `has_attacked`.

Decisions to confirm with the user (they did): on_summon usable only ONCE on the summon turn (added to `skills_used`); independent of attack/action state; cancelling targeting does NOT consume the skill (retryable); charm's own logic unchanged.

Online note: Fix C reuses the mature activate sync path (authority resolves + broadcasts full state via `export_initial_state`), so the summoning client activates manually and `summoned_this_turn` rides along in state — no per-skill pending-hint handshake needed. Still can't be fully verified without two live clients; say so.

## Verify

Single-script `--check-only` fails with "Identifier not found: NetworkManager"/"EventBus" because autoloads aren't loaded — expected, not a real error. Two real verification methods:

1. Whole-project compile (catches parse/type errors across all scripts):
   ```cmd
   "C:\path\to\Godot_console.exe" --headless --editor --quit
   ```
   Exit code 0 with no `SCRIPT ERROR` lines = all compiled.

2. Headless logic test — MUST run as a SCENE, not `--script`, so autoloads load:
   ```cmd
   "C:\path\to\Godot_console.exe" --headless res://TestSummonWalk.tscn
   ```
   Build a throwaway `extends Node` scene that constructs `GameState`, places a summoner + enemies, replays the per-skill dispatch sequence (`game.trigger_summon_skills(slot, target_slot, skill_idx)` per skill), and asserts effects. Use `CardDatabase._fx_skill`/`_fx` to author skills. Charm removes the enemy from `player2_field.slots` and appends a copy to `player_hand`. Delete the test files (.gd/.tscn/.uid) afterward.

   Cases that matter: [single-target charm, damage-all-enemies] with one target → charmed unit flips AND remaining enemy takes AoE; [two single-target charms] with two DIFFERENT target slots → both removed, untargeted enemy untouched, two copies in hand.
