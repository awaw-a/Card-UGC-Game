class_name SkillEngine
extends RefCounted

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
const TARGET_ALL_ENEMIES  := "all_enemies"
const TARGET_ALL_ALLIES   := "all_allies"
const TARGET_MALE         := "target_male"
const TARGET_FEMALE       := "target_female"
const TARGET_NONHUMAN     := "target_nonhuman"

const EFFECT_DAMAGE       := "damage"
const EFFECT_HEAL         := "heal"
const EFFECT_ADD_BUFF     := "add_buff"
const EFFECT_DRAW_CARDS   := "draw_cards"
const EFFECT_SHIELD        := "shield"
const EFFECT_CHARM        := "charm"
const BUFF_SILENCE         := "silence"
const BUFF_MISFORTUNE      := "misfortune"

const BUFF_ATK_BOOST        := "atk_boost"
const BUFF_REGEN            := "regen"
const BUFF_MANA_REFUND      := "mana_refund"
const BUFF_THORNS           := "thorns"
const BUFF_DAMAGE_REDUCTION := "damage_reduction"
const BUFF_TAUNT           := "taunt"

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


# ============================================
# Main entry
# ============================================

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
		var j :int = rng.randi_range(0, i)
		var temp = targets[i]
		targets[i] = targets[j]
		targets[j] = temp


# Resolves an effect's numeric value at execution time. Supports three modes,
# chosen by which optional fields are present (backward compatible with a plain
# integer "value"):
#   variable: value_var set  -> _var_value(var) + value_offset
#   random:   value_min/max  -> rng.randi_range(min, max)
#   fixed:    value          -> int(value)
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


static func _count_cards(field: BattleField) -> int:
	if field == null:
		return 0
	var n := 0
	for slot in field.slots:
		if slot != null:
			n += 1
	return n


# Computes a dynamic variable's current value from the skill context.
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


static func trigger_skills(trigger: String, source_card: CardData, context: Dictionary) -> void:
	if source_card == null or source_card.skills.is_empty():
		return
	if source_card.is_silenced():
		return

	for skill in source_card.skills:
		var skill_dict: Dictionary = skill
		if skill_dict.get("trigger", "") == trigger:
			var prob: int = skill_dict.get("probability", 100)
			var misfortune: int = source_card.get_misfortune()
			if misfortune > 0:
				prob = max(0, prob - misfortune)
				print("[SkillEngine] %s: misfortune -%d%% (eff: %d%%)" % [skill_dict.get("skill_name", "???"), misfortune, prob])
			if prob < 100 and _roll_percent(context) > float(prob):
				print("[SkillEngine] %s: %d%% roll failed — skipped" % [skill_dict.get("skill_name", "???"), prob])
				continue
			_execute_skill(skill_dict, source_card, context)
static func trigger_single_skill(card: CardData, skill_index: int, context: Dictionary) -> void:
	if card == null or skill_index < 0 or skill_index >= card.skills.size():
		return
	if card.is_silenced():
		return
	var skill_dict: Dictionary = card.skills[skill_index]
	var prob: int = skill_dict.get("probability", 100)
	var misfortune2: int = card.get_misfortune()
	if misfortune2 > 0:
		prob = max(0, prob - misfortune2)
		print("[SkillEngine] %s: misfortune -%d%% (eff: %d%%)" % [skill_dict.get("skill_name", "???"), misfortune2, prob])
	if prob < 100 and _roll_percent(context) > float(prob):
		print("[SkillEngine] %s: %d%% roll failed — skipped" % [skill_dict.get("skill_name", "???"), prob])
		return
	_execute_skill(skill_dict, card, context)


static func _execute_skill(skill: Dictionary, source_card: CardData, context: Dictionary) -> void:
	var skill_name: String = skill.get("skill_name", "???")
	var effects: Array = skill.get("effects", [])

	# Backward compat: old single-effect format
	if effects.is_empty():
		var single := {
			"target": skill.get("target", TARGET_SINGLE),
			"effect": skill.get("effect", EFFECT_DAMAGE),
			"value": skill.get("value", 1),
			"buff_id": skill.get("buff_id", ""),
			"duration": skill.get("duration", 0),
		}
		effects = [single]

	for eff_dict in effects:
		var eff: Dictionary = eff_dict
		var eff_prob: int = eff.get("probability", 100)
		var misfortune3: int = source_card.get_misfortune()
		if misfortune3 > 0:
			eff_prob = max(0, eff_prob - misfortune3)
		if eff_prob < 100 and _roll_percent(context) > float(eff_prob):
			print("[SkillEngine] Effect skipped: %d%% roll failed" % eff_prob)
			continue
		var target_str: String = eff.get("target", TARGET_SINGLE)
		var effect_str: String = eff.get("effect", EFFECT_DAMAGE)
		var value: int = _resolve_value(eff, source_card, context)

		var targets: Array = _resolve_targets(target_str, source_card, context)
		var rcount: int = int(eff.get("random_count", 0))
		if rcount > 0 and targets.size() > rcount:
			_shuffle_targets(targets, context)
			targets = targets.slice(0, rcount)

		# Turn 1 rule: neither side may affect enemy cards. If any resolved
		# target belongs to the source's enemy field, skip the whole effect.
		var turn_no: int = int(context.get("turn_number", 99))
		if turn_no <= 1 and _targets_include_enemy(targets, source_card, context):
			print("[SkillEngine] Turn 1: '%s' enemy-targeting effect skipped" % skill_name)
			continue

		print("[SkillEngine] %s: %s -> %s x%d on %d target(s)" % [skill_name, effect_str, target_str, value, targets.size()])

		for target_card in targets:
			if target_card == null or not target_card.is_alive():
				continue
			_apply_effect(effect_str, target_card, value, eff, context)


# Returns the battlefield opposing the skill's source card, so the turn-1 rule
# is evaluated from the acting card's perspective (works for reactive triggers).
static func _enemy_field_of_source(source_card: CardData, context: Dictionary) -> BattleField:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	if pf != null and source_card in pf.slots:
		return ef
	if ef != null and source_card in ef.slots:
		return pf
	return ef


static func _targets_include_enemy(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	var enemy_field: BattleField = _enemy_field_of_source(source_card, context)
	if enemy_field == null:
		return false
	for t in targets:
		if t != null and t in enemy_field.slots:
			return true
	return false


static func _resolve_targets(target_str: String, source_card: CardData, context: Dictionary) -> Array:
	match target_str:
		TARGET_SELF:
			return [source_card]
		TARGET_SINGLE:
			return _resolve_single_target(source_card, context)
		TARGET_SIDES:
			return _resolve_adjacent(source_card, context, false)
		TARGET_SELF_SIDES:
			return _resolve_adjacent(source_card, context, true)
		TARGET_ALL_ENEMIES:
			return _resolve_all_enemies(context)
		TARGET_ALL_ALLIES:
			return _resolve_all_allies(context)
		TARGET_MALE:
			return _resolve_by_gender(context, "male")
		TARGET_FEMALE:
			return _resolve_by_gender(context, "female")
		TARGET_NONHUMAN:
			return _resolve_by_gender(context, "nonhuman")
	return []


# ============================================
# Target resolvers
# ============================================

static func _resolve_single_target(source_card: CardData, context: Dictionary) -> Array:
	var target_slot: int = context.get("target_slot", -1)
	var enemy_field: BattleField = context.get("enemy_field")
	if target_slot >= 0:
		if enemy_field and enemy_field.slots[target_slot] != null:
			return [enemy_field.slots[target_slot]]
	# No specific target — pick any alive enemy
	if enemy_field:
		for slot in enemy_field.slots:
			if slot != null and slot.is_alive():
				return [slot]
	return []


static func _resolve_adjacent(source_card: CardData, context: Dictionary, include_self: bool) -> Array:
	var result: Array = []

	if include_self:
		var center: int = context.get("source_slot", -1)
		if center < 0:
			return result
		var field: BattleField = context.get("player_field")
		if field == null:
			return result
		if field.slots[center] != null:
			result.append(field.slots[center])
		for offset in [-1, 1]:
			var adj: int = center + offset
			if adj >= 0 and adj < 5 and field.slots[adj] != null:
				result.append(field.slots[adj])
	else:
		var center: int = context.get("target_slot", -1)
		if center < 0:
			return result
		var field: BattleField = context.get("enemy_field")
		if field == null:
			return result
		# Include the target itself
		if field.slots[center] != null:
			result.append(field.slots[center])
		for offset in [-1, 1]:
			var adj: int = center + offset
			if adj >= 0 and adj < 5 and field.slots[adj] != null:
				result.append(field.slots[adj])

	return result


static func _resolve_all_enemies(context: Dictionary) -> Array:
	var result: Array = []
	var enemy_field: BattleField = context.get("enemy_field")
	if enemy_field:
		for slot in enemy_field.slots:
			if slot != null and slot.is_alive():
				result.append(slot)
	return result


static func _resolve_all_allies(context: Dictionary) -> Array:
	var result: Array = []
	var player_field: BattleField = context.get("player_field")
	if player_field:
		for slot in player_field.slots:
			if slot != null and slot.is_alive():
				result.append(slot)
	return result


static func _resolve_by_gender(context: Dictionary, gender: String) -> Array:
	var result: Array = []
	var enemy_field: BattleField = context.get("enemy_field")
	if enemy_field:
		for slot in enemy_field.slots:
			if slot != null and slot.is_alive() and slot.gender == gender:
				result.append(slot)
	var player_field: BattleField = context.get("player_field")
	if player_field:
		for slot in player_field.slots:
			if slot != null and slot.is_alive() and slot.gender == gender:
				result.append(slot)
	return result


# ============================================
# Effect appliers
# ============================================

static func _apply_effect(effect_str: String, target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	match effect_str:
		EFFECT_DAMAGE:
			target.take_damage(value)
			EventBus.hp_changed.emit(target, -value, target.hp)
			print("  -> %s takes %d dmg (HP: %d)" % [target.card_name, value, target.hp])

		EFFECT_HEAL:
			target.heal(value)
			EventBus.hp_changed.emit(target, value, target.hp)
			print("  -> %s healed %d (HP: %d)" % [target.card_name, value, target.hp])

		EFFECT_DRAW_CARDS:
			var cb: Callable = context.get("draw_callable", Callable())
			if cb.is_valid():
				cb.call(value)
			print("  -> Draw %d cards" % value)
		EFFECT_SHIELD:
			target.temp_hp += value
			print("  -> %s gains %d temp HP (total: %d)" % [target.card_name, value, target.temp_hp])


		EFFECT_CHARM:
			_apply_charm(target, context)
		EFFECT_ADD_BUFF:
			var buff_id: String = skill.get("buff_id", "")
			var duration: int = skill.get("duration", 1)
			if buff_id != "":
				target.apply_buff(buff_id, value, duration, context.get("current_player", 0))



# ============================================
# Charm helpers
# ============================================

static func _apply_charm(target: CardData, context: Dictionary) -> void:
	var enemy_field: BattleField = context.get("enemy_field")
	var hand: Array = context.get("active_hand", [])
	if enemy_field == null or hand == null:
		return

	# Find target slot
	var slot_idx := -1
	for i in range(enemy_field.slots.size()):
		if enemy_field.slots[i] == target:
			slot_idx = i
			break
	if slot_idx < 0:
		return

	# Create copy preserving state
	var copy := target.duplicate_card()
	copy.original_cost = target.original_cost if target.original_cost >= 0 else target.cost
	copy.cost = 0
	copy.charmed_slot = slot_idx

	# Remove from enemy field
	enemy_field.slots[slot_idx] = null
	print("  -> %s charmed! (slot %d) cost 0 this turn" % [copy.card_name, slot_idx])

	# Add to hand
	hand.append(copy)

# ============================================
# Tooltip
# ============================================

static func _format_effect_sentence(eff: Dictionary) -> String:
	var target: String = Locale.term("target", eff.get("target", ""))
	var effect_id: String = eff.get("effect", "")
	var vstr: String = _describe_value(eff)
	var probability: int = int(eff.get("probability", 100))
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
		EFFECT_ADD_BUFF:
			var buff_name: String = Locale.term("buff", eff.get("buff_id", ""))
			var duration: int = int(eff.get("duration", 1))
			if is_zh:
				sentence = "为%s添加%s，持续 %d 回合" % [target, buff_name, duration]
			else:
				sentence = "Apply %s to %s for %d turn(s)" % [buff_name, target, duration]
		_:
			sentence = "%s %s %s" % [target, Locale.term("effect", effect_id), vstr]

	if probability < 100:
		sentence += " %s" % Locale.t("skill.chance", [probability])
	return sentence


# Human-readable value description for tooltips/editor (no live context).
# Mirrors _resolve_value's mode selection: variable, random range, or fixed.
static func _describe_value(eff: Dictionary) -> String:
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


static func format_skill_tooltip(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""

	var sname: String = skill.get("skill_name", Locale.t("editor.unnamed"))
	var trig: String = Locale.term("trigger", skill.get("trigger", ""))
	var result: String = "[%s] %s
" % [sname, trig]

	# Effects array (with backward compat)
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and not skill.get("effect", "").is_empty():
		effects = [{"target": skill.get("target", ""), "effect": skill.get("effect", ""),
			"value": skill.get("value", 0), "buff_id": skill.get("buff_id", ""), "duration": skill.get("duration", 0)}]

	if effects.is_empty():
		result += "  %s" % Locale.t("skill.no_effects")
	for i in range(effects.size()):
		var eff: Dictionary = effects[i]
		result += "  %d. %s" % [i + 1, _format_effect_sentence(eff)]
		if i < effects.size() - 1:
			result += "
"

	return result
