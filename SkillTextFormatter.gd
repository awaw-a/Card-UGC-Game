class_name SkillTextFormatter
extends RefCounted

const _TargetResolver = preload("res://SkillTargetResolver.gd")

const TARGET_SIDE_ALL := "all"

const EFFECT_DAMAGE := "damage"
const EFFECT_HEAL := "heal"
const EFFECT_ADD_BUFF := "add_buff"
const EFFECT_DRAW_CARDS := "draw_cards"
const EFFECT_SHIELD := "shield"
const EFFECT_CHARM := "charm"
const EFFECT_LIFESTEAL_DAMAGE := "lifesteal_damage"
const EFFECT_EXECUTE := "execute"
const EFFECT_CLEANSE := "cleanse"
const EFFECT_DISPEL := "dispel"
const EFFECT_GAIN_MANA := "gain_mana"
const EFFECT_GAIN_ATTACK := "gain_attack"
const EFFECT_GAIN_MAX_HP := "gain_max_hp"

const BUFF_SILENCE := "silence"
const BUFF_MISFORTUNE := "misfortune"
const BUFF_ATK_BOOST := "atk_boost"
const BUFF_REGEN := "regen"
const BUFF_MANA_REFUND := "mana_refund"
const BUFF_THORNS := "thorns"
const BUFF_DAMAGE_REDUCTION := "damage_reduction"
const BUFF_TAUNT := "taunt"

# ============================================
# Skill tooltip and editor text formatting
# ============================================

static func format_buff_value(buff_id: String, value_text: String, is_zh: bool = Locale.language == "zh") -> String:
	match buff_id:
		BUFF_ATK_BOOST:
			return "攻击 +%s" % value_text if is_zh else "+%s attack" % value_text
		BUFF_REGEN:
			return "每回合恢复 %s" % value_text if is_zh else "restore %s HP each turn" % value_text
		BUFF_MANA_REFUND:
			return "回合结束返还 %s 圣水" % value_text if is_zh else "refund %s elixir at turn end" % value_text
		BUFF_THORNS:
			return "反伤 %s" % value_text if is_zh else "%s thorns damage" % value_text
		BUFF_DAMAGE_REDUCTION:
			return "减伤 %s%%" % value_text if is_zh else "%s%% damage reduction" % value_text
		BUFF_TAUNT:
			return "嘲讽" if is_zh else "taunt"
		BUFF_SILENCE:
			return "沉默" if is_zh else "silence"
		BUFF_MISFORTUNE:
			return "触发概率 -%s%%" % value_text if is_zh else "-%s%% trigger chance" % value_text
	return value_text


static func format_effect_sentence(eff: Dictionary) -> String:
	var normalized := _TargetResolver.normalize_effect_target(eff)
	var target: String = _format_target_name(normalized)
	var effect_id: String = normalized.get("effect", "")
	var vstr: String = describe_value(normalized)
	var probability: int = int(normalized.get("probability", 100))
	var sentence := ""
	var is_zh := Locale.language == "zh"

	match effect_id:
		EFFECT_DAMAGE:
			sentence = "对%s造成 %s 点伤害" % [target, vstr] if is_zh else "Deal %s damage to %s" % [vstr, target]
		EFFECT_HEAL:
			sentence = "为%s恢复 %s 点生命" % [target, vstr] if is_zh else "Restore %s HP to %s" % [vstr, target]
		EFFECT_DRAW_CARDS:
			sentence = "为%s抽 %s 张牌" % [target, vstr] if is_zh else "Draw %s card(s) for %s" % [vstr, target]
		EFFECT_SHIELD:
			sentence = "为%s获得 %s 点护盾" % [target, vstr] if is_zh else "Give %s %s shield" % [target, vstr]
		EFFECT_CHARM:
			sentence = "魅惑%s" % target if is_zh else "Charm %s" % target
		EFFECT_LIFESTEAL_DAMAGE:
			sentence = "对%s造成 %s 点吸血伤害" % [target, vstr] if is_zh else "Deal %s lifesteal damage to %s" % [vstr, target]
		EFFECT_EXECUTE:
			sentence = "处决生命 ≤ %s 的%s" % [vstr, target] if is_zh else "Execute %s if HP is at most %s" % [target, vstr]
		EFFECT_CLEANSE:
			sentence = "清除%s的负面状态" % target if is_zh else "Cleanse negative statuses from %s" % target
		EFFECT_DISPEL:
			sentence = "驱散%s的正面状态" % target if is_zh else "Dispel positive statuses from %s" % target
		EFFECT_GAIN_MANA:
			sentence = "获得 %s 点圣水" % vstr if is_zh else "Gain %s elixir" % vstr
		EFFECT_GAIN_ATTACK:
			sentence = "使%s攻击永久 +%s" % [target, vstr] if is_zh else "Give %s +%s permanent attack" % [target, vstr]
		EFFECT_GAIN_MAX_HP:
			sentence = "使%s生命上限永久 +%s，并恢复等量生命" % [target, vstr] if is_zh else "Give %s +%s max HP and restore that much HP" % [target, vstr]
		EFFECT_ADD_BUFF:
			var buff_name: String = Locale.term("buff", normalized.get("buff_id", ""))
			var buff_value := format_buff_value(normalized.get("buff_id", ""), vstr, is_zh)
			var duration: int = int(normalized.get("duration", 1))
			if is_zh:
				sentence = "为%s添加%s（%s），持续 %d 回合" % [target, buff_name, buff_value, duration]
			else:
				sentence = "Apply %s (%s) to %s for %d turn(s)" % [buff_name, buff_value, target, duration]
		_:
			sentence = "%s %s %s" % [target, Locale.term("effect", effect_id), vstr]

	var rcount: int = int(eff.get("random_count", 0))
	if rcount > 0:
		sentence += "，%s" % Locale.t("skill.max_targets", [rcount]) if is_zh else ", %s" % Locale.t("skill.max_targets", [rcount])
	var condition_text := format_condition_sentence(normalized)
	if condition_text != "":
		sentence += "，%s" % condition_text if is_zh else ", %s" % condition_text
	if probability < 100:
		sentence += " %s" % Locale.t("skill.chance", [probability])
	return sentence


static func format_condition_sentence(eff: Dictionary) -> String:
	var condition_type: String = eff.get("condition_type", SkillEngine.CONDITION_NONE)
	if condition_type == "" or condition_type == SkillEngine.CONDITION_NONE:
		return ""
	var is_zh := Locale.language == "zh"
	if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
		var buff_name := Locale.term("buff", eff.get("condition_buff_id", ""))
		return "若目标拥有%s" % buff_name if is_zh else "if the target has %s" % buff_name
	var cname := Locale.term("condition", condition_type)
	var opname := Locale.term("condition_op", eff.get("condition_op", SkillEngine.CONDITION_OP_GTE))
	var value_text := str(int(eff.get("condition_value", 0)))
	if condition_type in [SkillEngine.CONDITION_SOURCE_HP_PCT, SkillEngine.CONDITION_TARGET_HP_PCT]:
		value_text += "%"
	return "若%s %s %s" % [cname, opname, value_text] if is_zh else "if %s %s %s" % [cname, opname, value_text]


static func format_skill_tooltip(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""

	var sname: String = skill.get("skill_name", Locale.t("editor.unnamed"))
	var trig: String = Locale.term("trigger", skill.get("trigger", ""))
	var result: String = "[%s] %s\n" % [sname, trig]

	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and not skill.get("effect", "").is_empty():
		effects = [{"target": skill.get("target", ""), "target_side": skill.get("target_side", TARGET_SIDE_ALL), "effect": skill.get("effect", ""),
			"value": skill.get("value", 0), "buff_id": skill.get("buff_id", ""), "duration": skill.get("duration", 0)}]

	if effects.is_empty():
		result += "  %s" % Locale.t("skill.no_effects")
	for i in range(effects.size()):
		var eff: Dictionary = effects[i]
		result += "  %d. %s" % [i + 1, format_effect_sentence(eff)]
		if i < effects.size() - 1:
			result += "\n"

	return result


static func _format_target_name(eff: Dictionary) -> String:
	var normalized := _TargetResolver.normalize_effect_target(eff)
	var target_id: String = normalized.get("target", "")
	var side_id: String = normalized.get("target_side", _TargetResolver.default_target_side(target_id))
	if _TargetResolver.is_directed_target(target_id):
		return Locale.term("target", target_id)
	var target_name := Locale.term("target", target_id)
	var side_name := Locale.term("target_side", side_id)
	if side_id == TARGET_SIDE_ALL:
		return target_name
	return "%s%s" % [side_name, target_name] if Locale.language == "zh" else "%s %s" % [side_name, target_name]


static func describe_value(eff: Dictionary) -> String:
	var var_id: String = eff.get("value_var", "")
	if var_id != "":
		var offset: int = int(eff.get("value_offset", 0))
		var vname: String = Locale.term("value_var", var_id)
		if offset > 0:
			return "(%s+%d)" % [vname, offset]
		elif offset < 0:
			return "(%s-%d)" % [vname, -offset]
		return "(%s)" % vname
	if eff.has("value_min") and eff.has("value_max"):
		var vmin: int = int(eff.get("value_min", 1))
		var vmax: int = int(eff.get("value_max", 1))
		if vmin == vmax:
			return str(vmin)
		return "%d-%d" % [vmin, vmax]
	return str(int(eff.get("value", 0)))
