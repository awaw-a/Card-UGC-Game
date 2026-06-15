---
name: godot-localization-autoload-ui-skill-text
description: Add a Locale autoload to a Godot project, retrofit UI/runtime text and skill descriptions, and verify scenes headlessly.
source: auto-skill
extracted_at: '2026-06-13T15:49:00.239Z'
---

# Godot Localization Autoload UI + Skill Text

Use this when a Godot project has hardcoded English UI/status strings across scenes and scripts, and needs a language selector plus localized skill/buff/tooltips without breaking existing scene defaults.

## Start by mapping all text surfaces

Before editing, search both `.gd` and `.tscn` files for static text and runtime assignments:

- Static scene labels/buttons: `text =`, `placeholder_text =`, dialog `title`.
- Runtime UI: `.text =`, `.tooltip_text =`, status/error messages, popup labels, generated buttons.
- Compact skill summaries and full tooltips: trigger/target/effect/buff name maps often live in several places.
- Layout bugs nearby: localization may expose title sizing or centering problems, so inspect responsive layout functions too.

In this project the important formatting surfaces were `SkillEngine.format_skill_tooltip`, `SkillEditor._format_skill`, `CardEditor._format_skill_short`, and `CardUI._format_buff_tooltip`.

## Add a single `Locale` autoload

Create `Locale.gd` and register it in `project.godot` under `[autoload]`:

```gdscript
extends Node

signal language_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LANGUAGE := "zh"

var language: String = DEFAULT_LANGUAGE

const STRINGS := {
	"zh": {},
	"en": {},
}

const SKILL_TERMS := {
	"zh": {},
	"en": {},
}

func _ready() -> void:
	_load_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := str(cfg.get_value("locale", "language", DEFAULT_LANGUAGE))
		if STRINGS.has(saved):
			language = saved

func set_language(lang: String) -> void:
	if not STRINGS.has(lang):
		return
	language = lang
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("locale", "language", language)
	cfg.save(SETTINGS_PATH)
	language_changed.emit()

func t(key: String, args := []) -> String:
	var table: Dictionary = STRINGS.get(language, {})
	var text: String = table.get(key, "")
	if text == "":
		text = STRINGS["en"].get(key, key)
	return text if args.is_empty() else text % args

func term(category: String, value: String) -> String:
	var lang_tbl: Dictionary = SKILL_TERMS.get(language, {})
	var cat_tbl: Dictionary = lang_tbl.get(category, {})
	if cat_tbl.has(value):
		return cat_tbl[value]
	return SKILL_TERMS["en"].get(category, {}).get(value, value)
```

Use stable keys such as `menu.start`, `lobby.failed_join`, `battle.status_line`, `skill_editor.target`. Keep `.tscn` English text as a fallback; overwrite at runtime in `_apply_texts()`.

## Put language selection on the main menu

Add an `OptionButton` such as `LanguageOption`, populate it in `_ready()`, and connect it to `Locale.set_language()`:

```gdscript
const LANGUAGE_CODES := ["zh", "en"]
const LANGUAGE_LABELS := ["简体中文", "English"]

func _setup_language_option() -> void:
	language_option.clear()
	for label in LANGUAGE_LABELS:
		language_option.add_item(label)
	language_option.selected = max(0, LANGUAGE_CODES.find(Locale.language))
	language_option.text = Locale.t("menu.language_prompt")

func _ready():
	_setup_language_option()
	language_option.item_selected.connect(_on_language_selected)
	Locale.language_changed.connect(_apply_texts)
	_apply_texts()

func _apply_texts() -> void:
	start_battle_btn.text = Locale.t("menu.start")
	# Keep the closed dropdown as a prompt; the popup items are the actual choices.
	language_option.text = Locale.t("menu.language_prompt")

func _on_language_selected(index: int) -> void:
	if index >= 0 and index < LANGUAGE_CODES.size():
		Locale.set_language(LANGUAGE_CODES[index])
```

If the selector should read like a prompt when closed (for example `语言...` / `Language...`) while the opened dropdown shows `简体中文` / `English`, do not add a disabled prompt item. Add only the real choices, then override `OptionButton.text` after setup and after language changes.

Only the current page needs live refresh if language is changed only from the main menu. Other scenes can call `_apply_texts()` in `_ready()`.

## Retrofit scenes with `_apply_texts()`

For each UI script, add `@onready` refs for labels/buttons that were previously only defined in `.tscn`, then centralize runtime assignment:

```gdscript
func _apply_texts() -> void:
	title_label.text = Locale.t("editor.title")
	name_label.text = Locale.t("editor.name")
	save_button.text = Locale.t("editor.update_card") if PlayerData.editing_index >= 0 else Locale.t("editor.save_card")
	back_button.text = Locale.t("common.back")
```

Important details:

- For generated controls (waiting-room buttons, card list buttons, popups), call `Locale.t()` at creation time.
- For `OptionButton` lists, call `clear()` before adding localized items to avoid duplicates.
- For default/fallback values like empty art or unnamed card, localize the displayed string but keep serialized enum values (`"male"`, `"female"`, `"nonhuman"`) unchanged.
- Keep technical/log strings unchanged unless they are visible UI.

## Localize skill terms once, then reuse everywhere

Avoid duplicating `trigger_names`, `target_names`, `effect_names`, and `buff_names` dictionaries in each formatter. Put shared terms in `Locale.SKILL_TERMS`:

```gdscript
const SKILL_TERMS := {
	"zh": {
		"trigger": {"on_attack": "攻击时", "on_activate": "主动"},
		"target": {"target_single": "目标", "all_enemies": "全体敌方"},
		"effect": {"damage": "伤害", "heal": "治疗", "add_buff": "增益"},
		"effect_value": {"damage": "%s 伤害", "heal": "%s 治疗", "draw_cards": "抽 %s 张"},
		"buff": {"atk_boost": "攻击提升", "regen": "回血", "mana_refund": "圣水返还"},
	},
	"en": {
		"effect": {"damage": "Damage", "heal": "Heal", "add_buff": "Buff"},
		"buff": {"atk_boost": "Attack Boost", "regen": "Regeneration", "mana_refund": "Elixir Refund"},
	}
}
```

For descriptions that live in tooltips or separated list rows, prefer full terms and natural particles/prepositions instead of terse abbreviations. Keep compact text only for constrained button labels, such as `CardUI` skill buttons and card-library skill buttons.

A reusable pattern is to centralize effect sentence formatting in `SkillEngine` and call it from all summary surfaces:

```gdscript
static func _format_effect_sentence(eff: Dictionary) -> String:
	var target := Locale.term("target", eff.get("target", ""))
	var effect_id: String = eff.get("effect", "")
	var value := int(eff.get("value", 0))
	var is_zh := Locale.language == "zh"

	match effect_id:
		EFFECT_DAMAGE:
			return "对%s造成 %d 点伤害" % [target, value] if is_zh else "Deal %d damage to %s" % [value, target]
		EFFECT_HEAL:
			return "为%s恢复 %d 点生命" % [target, value] if is_zh else "Restore %d HP to %s" % [value, target]
		EFFECT_ADD_BUFF:
			var buff_name := Locale.term("buff", eff.get("buff_id", ""))
			var duration := int(eff.get("duration", 1))
			return "为%s添加%s，持续 %d 回合" % [target, buff_name, duration] if is_zh else "Apply %s to %s for %d turn(s)" % [buff_name, target, duration]
	return "%s %s %d" % [target, Locale.term("effect", effect_id), value]
```

Then update all formatters to reuse this helper:

```gdscript
# Tooltip / card library / in-game card tooltip.
result += "  %d. %s" % [i + 1, _format_effect_sentence(eff)]

# Skill editor list row.
return "[%d] %s" % [idx + 1, SkillEngine._format_effect_sentence(eff)]

# Card editor compact summary.
parts.append(SkillEngine._format_effect_sentence(eff))
result += "；".join(parts) if Locale.language == "zh" else "; ".join(parts)
```

Important details:

- `SkillEngine.format_skill_tooltip` is used by `CardUI` and `MyCards`; changing it updates both game and library tooltips.
- `SkillEditor._format_effect_short` and `SkillEditor._format_skill` can still be full wording because they are list/summary surfaces.
- `CardEditor._format_skill_short` can use full sentences separated by punctuation; if it gets too wide, keep the button/label constrained rather than reverting to cryptic abbreviations.
- Do not put full effect text on skill buttons; keep buttons as skill name or `S1`/`S2` and put details in tooltips.

## Fix incidental layout regressions while localizing

Localization often reveals text sizing issues:

- If a title does not scale while buttons do, add a font-size override in the scene's responsive layout function.
- If a panel appears off-center, check `anchor_top` and `anchor_bottom`; for centered panels they should usually both be `0.5` with symmetric offsets.

## Verify with Godot headless

Run a full project load and targeted scene loads. On Windows, `godot` may not be in `PATH`; use `where godot` or search for `Godot*_console.exe`, then quote through `cmd` carefully:

```bat
""C:\path\to\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\path\to\project" --quit-after 5"
""C:\path\to\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\path\to\project" res://SkillEditor.tscn --quit-after 3"
```

Load the scenes most likely to instantiate localized generated controls: main menu, card editor, skill editor, card library, lobby/direct lobby. Treat exit code 0 and no parser/runtime errors as the baseline; follow up with manual language switching for visual layout and copy checks.
