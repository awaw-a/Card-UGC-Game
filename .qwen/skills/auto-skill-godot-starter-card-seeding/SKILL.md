---
name: godot-starter-card-seeding
description: Seed a default card library on first launch and author skill cards programmatically in the editor's multi-effect format, with Godot headless verification.
source: auto-skill
extracted_at: '2026-06-14T13:57:29.941Z'
---

# Godot Starter Card Seeding + Programmatic Skill Authoring

Use this when you need to pre-populate a player's card collection with built-in
cards on first launch, and/or define cards whose skills must match exactly what
the in-game skill editor produces.

## Seed the library in the "no save file" branch

The collection is loaded by an autoload (here `PlayerData.load_library()`),
which has a first-launch branch when the save file is missing. Seed there, then
persist, so the cards survive subsequent launches:

```gdscript
func load_library():
	if not FileAccess.file_exists(save_path):
		print("No save file found (first launch?)")
		_seed_starter_library()
		return
	# ... normal load path ...

func _seed_starter_library() -> void:
	card_library = CardDatabase.starter_library()
	save_library()
```

Important details:

- Seeding only fires when the save file is absent. A player who already has a
  save (even an empty/1-card library) will NOT get seeded. If the requirement is
  "seed whenever the library is empty," gate on `card_library.is_empty()` after
  load instead — confirm which behavior is wanted before choosing.
- The save path is under `user://` (e.g.
  `%APPDATA%\Godot\app_userdata\<ProjectName>\card_library.json` on Windows). To
  test seeding on a machine that already has a save, delete that file.
- Put the catalog data in the existing preset file (here `CardDatabase.gd`) as a
  static function returning `Array[CardData]`, alongside the existing
  `player_starters()` / enemy presets.

## Author skills in the editor's multi-effect format, not the legacy format

This project has two skill dictionary shapes. The old `_sample_skill` helper
produces a flat single-effect dict (`{target, effect, value, buff_id, duration}`).
The skill editor (`SkillEditor._build_skill` / `_on_popup_ok`) produces the newer
shape with an `effects` array. Author new cards in the editor shape so they look
identical to user-created cards and render correctly in every summary surface:

```gdscript
static func _fx_skill(sname: String, trigger: String, effects: Array, probability: int = 100) -> Dictionary:
	return {"skill_name": sname, "trigger": trigger, "probability": probability, "effects": effects}

static func _fx(target: String, effect: String, value: int, buff: String = "", duration: int = 0, random_count: int = 0, probability: int = 100) -> Dictionary:
	return {"target": target, "effect": effect, "value": value, "buff_id": buff,
		"duration": duration, "random_count": random_count, "probability": probability}
```

Map the natural-language design spec onto engine concepts by reading
`SkillEngine.gd` constants first:

- Trigger words: `onsummon` -> `TRIGGER_ON_SUMMON`, `onactivate` -> `TRIGGER_ON_ACTIVATE`,
  `ondamage` -> `TRIGGER_ON_DAMAGED`, plus `ON_ATTACK` / `ON_DEATH`.
- "self and both sides" -> `TARGET_SELF_SIDES`; "an enemy target" -> `TARGET_SINGLE`.
- Shield -> `EFFECT_SHIELD` (adds `temp_hp`); heal -> `EFFECT_HEAL`;
  charm -> `EFFECT_CHARM`; "X% buff for N turns" -> `EFFECT_ADD_BUFF` with the
  buff constant, `value` = the percentage, `duration` = turns.
- "charm 1 target" -> set `random_count: 1` so only one of the matched targets is hit
  (0 means all matched targets).
- A skill described as two effects (e.g. "heal 1 and 50% chance to gain 50%
  damage reduction") becomes two entries in the `effects` array; the per-effect
  chance goes in that effect's `probability`, distinct from the skill-level
  `probability`.
- `EFFECT_ADD_BUFF` value semantics differ per buff: for `BUFF_DAMAGE_REDUCTION`
  and `BUFF_MISFORTUNE` the `value` is a percentage, not a flat amount.

When a spec is genuinely ambiguous about trigger timing or how to split effects,
confirm with the user before encoding it — these choices change gameplay and are
not recoverable from the code.

## Localizing a single hardcoded scene label

A label whose text is set in `.tscn` (e.g. `text = "DISCARD"`) is overridden at
runtime if any script assigns `.text` later. The responsive-layout function often
already fetches that node for font sizing — add the `Locale.t(...)` assignment
there rather than editing the `.tscn`:

```gdscript
var discard_label := $CanvasLayer/DiscardZone/DiscardLabel
discard_label.text = Locale.t("battle.discard_zone")
discard_label.add_theme_font_size_override("font_size", max(10, int(18 * s)))
```

Add the key to BOTH language tables in `Locale.gd`. Edits to CJK string tables
fail easily from mis-escaping; match the exact existing whitespace/quotes and edit
each language block separately.

## Verify with Godot headless (Windows gotchas)

1. The executable is usually not on `PATH`. Find it with
   `where /R C:\Users\<user> Godot*.exe`. The user may also supply a path.
2. Do NOT append `2>&1` — `cmd` rejects it here ("文件名、目录名或卷标语法不正确").
   Just run the command; stdout/stderr are captured anyway.
3. Passing `--path "<abs>"` failed in this environment. What worked was running
   from the project directory (set the shell `directory`) without `--path`:

```
"C:\path\Godot_..._console.exe" --headless --quit-after 5
```

   A clean boot (exit 0, no parser errors, and the autoload `print`s appear) proves
   every edited script compiles WITH autoloads present.

4. `--headless --script foo.gd` (SceneTree script) does NOT load autoloads, so
   references to `EventBus`, `SkillEngine`, `PlayerData`, etc. fail to compile and
   their methods are "nonexistent." For standalone checks, `load("res://X.gd")` the
   script resource to call its static functions; but treat autoload-dependent
   errors in `--script` mode as false negatives — rely on the full-project boot for
   those. Delete temporary verification scripts (and their `.uid`) when done.
