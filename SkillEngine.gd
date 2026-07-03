class_name SkillEngine
extends RefCounted

const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _EffectApplier = preload("res://SkillEffectApplier.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

const MAX_HAND_SIZE = 6

# ============================================
# Skill execution engine
# ============================================

const TRIGGER_ON_ATTACK   := "on_attack"
const TRIGGER_ON_ACTIVATE := "on_activate"
const TRIGGER_ON_SUMMON   := "on_summon"
const TRIGGER_ON_DEATH    := "on_death"
const TRIGGER_ON_DAMAGED  := "on_damaged"

const TARGET_SINGLE       := "target_single"
const TARGET_SIDES        := "target_sides"
const TARGET_SELF         := "self"
const TARGET_SELF_SIDES   := "self_sides"
const TARGET_ALL          := "all"
const TARGET_ALL_ENEMIES  := "all_enemies"
const TARGET_ALL_ALLIES   := "all_allies"
const TARGET_MALE         := "target_male"
const TARGET_FEMALE       := "target_female"
const TARGET_NONHUMAN     := "target_nonhuman"

const TARGET_SIDE_ENEMY   := "enemy"
const TARGET_SIDE_ALLY    := "ally"
const TARGET_SIDE_ALL     := "all"

const EFFECT_DAMAGE       := "damage"
const EFFECT_HEAL         := "heal"
const EFFECT_ADD_BUFF     := "add_buff"
const EFFECT_DRAW_CARDS   := "draw_cards"
const EFFECT_SHIELD       := "shield"
const EFFECT_CHARM        := "charm"
const EFFECT_LIFESTEAL_DAMAGE := "lifesteal_damage"
const EFFECT_EXECUTE      := "execute"
const EFFECT_CLEANSE      := "cleanse"
const EFFECT_DISPEL       := "dispel"
const EFFECT_GAIN_MANA    := "gain_mana"
const EFFECT_GAIN_ATTACK  := "gain_attack"
const EFFECT_GAIN_MAX_HP  := "gain_max_hp"
const BUFF_SILENCE        := "silence"
const BUFF_MISFORTUNE     := "misfortune"

const BUFF_ATK_BOOST        := "atk_boost"
const BUFF_REGEN            := "regen"
const BUFF_MANA_REFUND      := "mana_refund"
const BUFF_THORNS           := "thorns"
const BUFF_DAMAGE_REDUCTION := "damage_reduction"
const BUFF_TAUNT            := "taunt"

# Dynamic value variables (resolved at execution time from skill context).
const VAR_FIELD_TOTAL   := "field_total"
const VAR_FIELD_ALLY    := "field_ally"
const VAR_FIELD_ENEMY   := "field_enemy"
const VAR_EMPTY_ALLY    := "empty_ally"
const VAR_EMPTY_ENEMY   := "empty_enemy"
const VAR_HAND_COUNT    := "hand_count"
const VAR_MANA_CURRENT  := "mana_current"

const VALUE_VARS := [
	VAR_FIELD_TOTAL, VAR_FIELD_ALLY, VAR_FIELD_ENEMY,
	VAR_EMPTY_ALLY, VAR_EMPTY_ENEMY, VAR_HAND_COUNT, VAR_MANA_CURRENT,
]

const CONDITION_NONE            := "none"
const CONDITION_SOURCE_HP_PCT   := "source_hp_pct"
const CONDITION_TARGET_HP_PCT   := "target_hp_pct"
const CONDITION_FIELD_ALLY      := "field_ally_count"
const CONDITION_FIELD_ENEMY     := "field_enemy_count"
const CONDITION_HAND_COUNT      := "hand_count"
const CONDITION_MANA_CURRENT    := "mana_current"
const CONDITION_TARGET_HAS_BUFF := "target_has_buff"

const CONDITION_OP_GTE := ">="
const CONDITION_OP_LTE := "<="
const CONDITION_OP_EQ  := "=="

const CONDITION_TYPES := [
	CONDITION_NONE, CONDITION_SOURCE_HP_PCT, CONDITION_TARGET_HP_PCT,
	CONDITION_FIELD_ALLY, CONDITION_FIELD_ENEMY, CONDITION_HAND_COUNT,
	CONDITION_MANA_CURRENT, CONDITION_TARGET_HAS_BUFF,
]
const CONDITION_OPS := [CONDITION_OP_GTE, CONDITION_OP_LTE, CONDITION_OP_EQ]


# ============================================
# Main entry
# ============================================

static func trigger_skills(trigger: String, source_card: CardData, context: Dictionary) -> void:
	if source_card == null or source_card.skills.is_empty():
		return
	if source_card.is_silenced():
		return
	var trigger_context := context.duplicate()
	trigger_context["trigger"] = trigger

	for skill in source_card.skills:
		var skill_dict: Dictionary = skill
		if skill_dict.get("trigger", "") == trigger and _passes_skill_roll(skill_dict, source_card, trigger_context):
			_execute_skill(skill_dict, source_card, trigger_context)


static func trigger_single_skill(card: CardData, skill_index: int, context: Dictionary) -> void:
	if card == null or skill_index < 0 or skill_index >= card.skills.size():
		return
	if card.is_silenced():
		return
	var skill_dict: Dictionary = card.skills[skill_index]
	var single_context := context.duplicate()
	single_context["trigger"] = skill_dict.get("trigger", "")
	if _passes_skill_roll(skill_dict, card, single_context):
		_execute_skill(skill_dict, card, single_context)


static func _execute_skill(skill: Dictionary, source_card: CardData, context: Dictionary) -> void:
	var skill_name: String = skill.get("skill_name", "???")
	for eff in _effects_for_skill(skill):
		var eff_dict: Dictionary = eff
		if not _passes_effect_roll(eff_dict, source_card, context):
			continue

		var target_str: String = eff_dict.get("target", TARGET_SINGLE)
		var target_side: String = eff_dict.get("target_side", _TargetResolver.default_target_side(target_str))
		var effect_str: String = eff_dict.get("effect", EFFECT_DAMAGE)
		var value: int = _resolve_value(eff_dict, source_card, context)
		var targets: Array = _TargetResolver.resolve_targets(target_str, source_card, context, target_side)
		targets = _limit_random_targets(targets, int(eff_dict.get("random_count", 0)), context)

		if _is_enemy_effect_blocked_on_turn_one(targets, source_card, context):
			print("[SkillEngine] Turn 1: '%s' enemy-targeting effect skipped" % skill_name)
			continue

		print("[SkillEngine] %s: %s -> %s x%d on %d target(s)" % [skill_name, effect_str, target_str, value, targets.size()])
		var effect_context := context.duplicate()
		effect_context["source_card"] = source_card
		for target_card in targets:
			if target_card == null or not target_card.is_alive():
				continue
			if not _passes_effect_condition(eff_dict, source_card, target_card, context):
				continue
			_EffectApplier.apply_effect(effect_str, target_card, value, eff_dict, effect_context)


static func _effects_for_skill(skill: Dictionary) -> Array:
	var effects: Array = skill.get("effects", [])
	if not effects.is_empty():
		return effects
	return [{
		"target": skill.get("target", TARGET_SINGLE),
		"target_side": skill.get("target_side", TARGET_SIDE_ALL),
		"effect": skill.get("effect", EFFECT_DAMAGE),
		"value": skill.get("value", 1),
		"buff_id": skill.get("buff_id", ""),
		"duration": skill.get("duration", 0),
	}]


# ============================================
# Chance and targeting rules
# ============================================

static func _passes_skill_roll(skill: Dictionary, source_card: CardData, context: Dictionary) -> bool:
	var prob: int = skill.get("probability", 100)
	var misfortune: int = source_card.get_misfortune()
	if misfortune > 0:
		prob = max(0, prob - misfortune)
		print("[SkillEngine] %s: misfortune -%d%% (eff: %d%%)" % [skill.get("skill_name", "???"), misfortune, prob])
	if prob < 100 and _roll_percent(context) > float(prob):
		print("[SkillEngine] %s: %d%% roll failed — skipped" % [skill.get("skill_name", "???"), prob])
		return false
	return true


static func _passes_effect_roll(eff: Dictionary, source_card: CardData, context: Dictionary) -> bool:
	var prob: int = eff.get("probability", 100)
	var misfortune: int = source_card.get_misfortune()
	if misfortune > 0:
		prob = max(0, prob - misfortune)
	if prob < 100 and _roll_percent(context) > float(prob):
		print("[SkillEngine] Effect skipped: %d%% roll failed" % prob)
		return false
	return true


static func _passes_effect_condition(eff: Dictionary, source_card: CardData, target_card: CardData, context: Dictionary) -> bool:
	var condition_type: String = eff.get("condition_type", CONDITION_NONE)
	if condition_type == "" or condition_type == CONDITION_NONE:
		return true
	var op: String = eff.get("condition_op", CONDITION_OP_GTE)
	if condition_type == CONDITION_TARGET_HAS_BUFF:
		var buff_id: String = eff.get("condition_buff_id", "")
		return buff_id != "" and _card_has_buff(target_card, buff_id)
	var actual: int = _condition_value(condition_type, source_card, target_card, context)
	var expected: int = int(eff.get("condition_value", 0))
	return _compare_condition(actual, expected, op)


static func _condition_value(condition_type: String, source_card: CardData, target_card: CardData, context: Dictionary) -> int:
	match condition_type:
		CONDITION_SOURCE_HP_PCT:
			return _hp_percent(source_card)
		CONDITION_TARGET_HP_PCT:
			return _hp_percent(target_card)
		CONDITION_FIELD_ALLY:
			return _count_cards(context.get("player_field"))
		CONDITION_FIELD_ENEMY:
			return _count_cards(context.get("enemy_field"))
		CONDITION_HAND_COUNT:
			var hand: Array = context.get("active_hand", [])
			return hand.size() if hand != null else 0
		CONDITION_MANA_CURRENT:
			var pf: BattleField = context.get("player_field")
			return pf.current_mana if pf != null else 0
	return 0


static func _hp_percent(card: CardData) -> int:
	if card == null or card.max_hp <= 0:
		return 0
	return int(round(float(card.hp) * 100.0 / float(card.max_hp)))


static func _card_has_buff(card: CardData, buff_id: String) -> bool:
	if card == null:
		return false
	for eff in card.status_effects:
		if eff.get("buff_id", "") == buff_id and eff.get("value", 0) > 0:
			return true
	return false


static func _compare_condition(actual: int, expected: int, op: String) -> bool:
	match op:
		CONDITION_OP_LTE:
			return actual <= expected
		CONDITION_OP_EQ:
			return actual == expected
	return actual >= expected


static func _limit_random_targets(targets: Array, random_count: int, context: Dictionary) -> Array:
	if random_count <= 0 or targets.size() <= random_count:
		return targets
	_shuffle_targets(targets, context)
	return targets.slice(0, random_count)


static func _is_enemy_effect_blocked_on_turn_one(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	var turn_no: int = int(context.get("turn_number", 99))
	return turn_no <= 1 and _TargetResolver.targets_include_enemy(targets, source_card, context)


static func _roll_percent(context: Dictionary) -> float:
	var rng = context.get("rng", null)
	if rng is RandomNumberGenerator:
		return rng.randf() * 100.0
	return randf() * 100.0


static func _shuffle_targets(targets: Array, context: Dictionary) -> void:
	var rng = context.get("rng", null)
	if not (rng is RandomNumberGenerator):
		targets.shuffle()
		return
	for i in range(targets.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = targets[i]
		targets[i] = targets[j]
		targets[j] = temp


# ============================================
# Dynamic values
# ============================================

static func _resolve_value(eff: Dictionary, source_card: CardData, context: Dictionary) -> int:
	var var_id: String = eff.get("value_var", "")
	if var_id != "":
		var offset: int = int(eff.get("value_offset", 0))
		return _var_value(var_id, source_card, context) + offset
	if eff.has("value_min") and eff.has("value_max"):
		var vmin: int = int(eff.get("value_min", 1))
		var vmax: int = int(eff.get("value_max", 1))
		if vmax < vmin:
			var t := vmin
			vmin = vmax
			vmax = t
		var rng = context.get("rng", null)
		if rng is RandomNumberGenerator:
			return rng.randi_range(vmin, vmax)
		return randi_range(vmin, vmax)
	return int(eff.get("value", 1))


static func _var_value(var_id: String, _source_card: CardData, context: Dictionary) -> int:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	var hand: Array = context.get("active_hand", [])
	match var_id:
		VAR_FIELD_TOTAL:
			return _count_cards(pf) + _count_cards(ef)
		VAR_FIELD_ALLY:
			return _count_cards(pf)
		VAR_FIELD_ENEMY:
			return _count_cards(ef)
		VAR_EMPTY_ALLY:
			return (pf.slots.size() - _count_cards(pf)) if pf != null else 0
		VAR_EMPTY_ENEMY:
			return (ef.slots.size() - _count_cards(ef)) if ef != null else 0
		VAR_HAND_COUNT:
			return hand.size() if hand != null else 0
		VAR_MANA_CURRENT:
			return pf.current_mana if pf != null else 0
	return 0


static func _count_cards(field: BattleField) -> int:
	if field == null:
		return 0
	var n := 0
	for slot in field.slots:
		if slot != null:
			n += 1
	return n


# ============================================
# Compatibility wrappers
# ============================================

static func _is_directed_target(target_str: String) -> bool:
	return _TargetResolver.is_directed_target(target_str)


static func _default_target_side(target_str: String) -> String:
	return _TargetResolver.default_target_side(target_str)


static func normalize_effect_target(eff: Dictionary) -> Dictionary:
	return _TargetResolver.normalize_effect_target(eff)


static func _resolve_targets(target_str: String, source_card: CardData, context: Dictionary, target_side: String = TARGET_SIDE_ALL) -> Array:
	return _TargetResolver.resolve_targets(target_str, source_card, context, target_side)


static func _targets_include_enemy(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	return _TargetResolver.targets_include_enemy(targets, source_card, context)


static func _enemy_field_of_source(source_card: CardData, context: Dictionary) -> BattleField:
	return _TargetResolver.enemy_field_of_source(source_card, context)


static func _apply_effect(effect_str: String, target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	_EffectApplier.apply_effect(effect_str, target, value, skill, context)


static func format_buff_value(buff_id: String, value_text: String, is_zh: bool = Locale.language == "zh") -> String:
	return _TextFormatter.format_buff_value(buff_id, value_text, is_zh)


static func _format_effect_sentence(eff: Dictionary) -> String:
	return _TextFormatter.format_effect_sentence(eff)


static func _describe_value(eff: Dictionary) -> String:
	return _TextFormatter.describe_value(eff)


static func format_skill_tooltip(skill: Dictionary) -> String:
	return _TextFormatter.format_skill_tooltip(skill)
