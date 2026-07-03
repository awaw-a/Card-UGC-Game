class_name SkillEffectApplier
extends RefCounted

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

const NEGATIVE_BUFFS := ["silence", "misfortune"]
const POSITIVE_BUFFS := ["atk_boost", "regen", "mana_refund", "thorns", "damage_reduction", "taunt"]

# ============================================
# Skill effect application
# ============================================

static func apply_effect(effect_str: String, target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	match effect_str:
		EFFECT_DAMAGE:
			_apply_damage(target, value)
		EFFECT_HEAL:
			_apply_heal(target, value)
		EFFECT_DRAW_CARDS:
			_apply_draw_cards(value, context)
		EFFECT_SHIELD:
			_apply_shield(target, value)
		EFFECT_CHARM:
			_apply_charm(target, context)
		EFFECT_ADD_BUFF:
			_apply_buff(target, value, skill, context)
		EFFECT_LIFESTEAL_DAMAGE:
			_apply_lifesteal_damage(target, value, context)
		EFFECT_EXECUTE:
			_apply_execute(target, value)
		EFFECT_CLEANSE:
			_apply_remove_statuses(target, NEGATIVE_BUFFS, "cleanse")
		EFFECT_DISPEL:
			_apply_remove_statuses(target, POSITIVE_BUFFS, "dispel")
		EFFECT_GAIN_MANA:
			_apply_gain_mana(value, context)
		EFFECT_GAIN_ATTACK:
			_apply_gain_attack(target, value)
		EFFECT_GAIN_MAX_HP:
			_apply_gain_max_hp(target, value)


static func _apply_damage(target: CardData, value: int) -> void:
	var actual := target.take_damage(value)
	EventBus.hp_changed.emit(target, -actual, target.hp)
	print("  -> %s takes %d dmg (HP: %d)" % [target.card_name, actual, target.hp])


static func _apply_heal(target: CardData, value: int) -> void:
	target.heal(value)
	EventBus.hp_changed.emit(target, value, target.hp)
	print("  -> %s healed %d (HP: %d)" % [target.card_name, value, target.hp])


static func _apply_draw_cards(value: int, context: Dictionary) -> void:
	var cb: Callable = context.get("draw_callable", Callable())
	if cb.is_valid():
		cb.call(value)
	print("  -> Draw %d cards" % value)


static func _apply_shield(target: CardData, value: int) -> void:
	target.temp_hp += value
	print("  -> %s gains %d temp HP (total: %d)" % [target.card_name, value, target.temp_hp])


static func _apply_buff(target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	var buff_id: String = skill.get("buff_id", "")
	var duration: int = skill.get("duration", 1)
	if buff_id != "":
		target.apply_buff(buff_id, value, duration, context.get("current_player", 0))


static func _apply_lifesteal_damage(target: CardData, value: int, context: Dictionary) -> void:
	var source: CardData = context.get("source_card")
	var actual := target.take_damage(value)
	EventBus.hp_changed.emit(target, -actual, target.hp)
	if source != null and actual > 0 and source.is_alive():
		source.heal(actual)
		EventBus.hp_changed.emit(source, actual, source.hp)
		print("  -> %s takes %d lifesteal dmg; %s heals %d (HP: %d)" % [target.card_name, actual, source.card_name, actual, source.hp])
	else:
		print("  -> %s takes %d lifesteal dmg" % [target.card_name, actual])


static func _apply_execute(target: CardData, value: int) -> void:
	if target.hp <= value:
		var actual := target.hp
		target.hp = 0
		EventBus.hp_changed.emit(target, -actual, target.hp)
		print("  -> %s executed" % target.card_name)
	else:
		print("  -> %s resisted execute (HP: %d > %d)" % [target.card_name, target.hp, value])


static func _apply_remove_statuses(target: CardData, buff_ids: Array, label: String) -> void:
	var removed := 0
	for i in range(target.status_effects.size() - 1, -1, -1):
		var eff: Dictionary = target.status_effects[i]
		if eff.get("buff_id", "") in buff_ids:
			target.status_effects.remove_at(i)
			removed += 1
	print("  -> %s %s removed %d status(es)" % [target.card_name, label, removed])


static func _apply_gain_mana(value: int, context: Dictionary) -> void:
	var field: BattleField = context.get("player_field")
	if field == null:
		return
	var before := field.current_mana
	field.add_mana(value)
	print("  -> Gain %d mana (%d -> %d)" % [value, before, field.current_mana])


static func _apply_gain_attack(target: CardData, value: int) -> void:
	target.atk += value
	target.base_atk += value
	print("  -> %s gains %d permanent attack (ATK: %d)" % [target.card_name, value, target.atk])


static func _apply_gain_max_hp(target: CardData, value: int) -> void:
	target.max_hp += value
	target.base_max_hp += value
	target.hp = min(target.max_hp, target.hp + value)
	EventBus.hp_changed.emit(target, value, target.hp)
	print("  -> %s gains %d max HP (HP: %d/%d)" % [target.card_name, value, target.hp, target.max_hp])


static func _apply_charm(target: CardData, context: Dictionary) -> void:
	var enemy_field: BattleField = context.get("enemy_field")
	var hand: Array = context.get("active_hand", [])
	if enemy_field == null or hand == null:
		return

	var slot_idx := -1
	for i in range(enemy_field.slots.size()):
		if enemy_field.slots[i] == target:
			slot_idx = i
			break
	if slot_idx < 0:
		return

	var copy := target.duplicate_card()
	copy.original_cost = target.original_cost if target.original_cost >= 0 else target.cost
	copy.cost = 0
	copy.charmed_slot = slot_idx

	enemy_field.slots[slot_idx] = null
	print("  -> %s charmed! (slot %d) cost 0 this turn" % [copy.card_name, slot_idx])

	hand.append(copy)
