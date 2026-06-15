class_name BattleField
extends RefCounted

# ============================================
# 单侧战场 — 管理一方的血量、圣水、5个格子
# ============================================

# 战场所属方标识
var owner_name: String = ""

# 英雄血量
var player_hp: int = 30
var max_player_hp: int = 30

# 圣水系统
var current_mana: int = 4
var max_mana: int = 10

# 5个前台格子 [0..4]，存储 CardData 或 null
var slots: Array = [null, null, null, null, null]



func _init(_owner_name: String = "", _player_hp: int = 30, _max_mana: int = 10):
	owner_name = _owner_name
	player_hp = _player_hp
	max_player_hp = _player_hp
	max_mana = _max_mana
	current_mana = 4


# ========== 圣水系统 ==========

# 新回合开始：回复2滴（不超过上限）
func reset_mana_for_new_turn():
	current_mana = min(max_mana, current_mana + 2)


# 获得圣水
func add_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)


# 消耗圣水，成功返回 true
func spend_mana(amount: int) -> bool:
	if current_mana < amount:
		return false
	current_mana -= amount
	return true


# ========== 格子操作 ==========

# 尝试在指定格子召唤卡牌
func summon_card(card: CardData, slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx > 4:
		print("[%s] 错误：无效格子 %d" % [owner_name, slot_idx])
		return false

	if slots[slot_idx] != null:
		print("[%s] 错误：格子 %d 已有卡牌" % [owner_name, slot_idx])
		return false

	if current_mana < card.cost:
		print("[%s] 错误：圣水不足（需 %d，当前 %d）" % [owner_name, card.cost, current_mana])
		return false

	current_mana -= card.cost
	slots[slot_idx] = card
	card.summoned_this_turn = true
	print("[%s] 召唤 %s → 格子 %d | 剩余圣水: %d" % [owner_name, card.card_name, slot_idx, current_mana])
	return true


# 直接放置卡牌（不消耗圣水，用于初始部署）
func place_card(card: CardData, slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx > 4:
		return false
	slots[slot_idx] = card
	return true


# 移除卡牌（死亡时调用）
func remove_card(slot_idx: int):
	if slot_idx >= 0 and slot_idx <= 4:
		slots[slot_idx] = null


# 获取存活卡牌数量
func get_alive_count() -> int:
	var count := 0
	for slot in slots:
		if slot != null and slot.is_alive():
			count += 1
	return count


# 检查前台是否全空
func is_empty() -> bool:
	for slot in slots:
		if slot != null:
			return false
	return true


# 检查场上是否有嘲讽随从
func has_any_taunt() -> bool:
	for slot in slots:
		if slot != null and slot.is_alive() and slot.has_taunt():
			return true
	return false


# ========== 伤害/治疗 ==========

# 对英雄造成伤害
func damage_player(amount: int):
	player_hp = max(0, player_hp - amount)
	if player_hp <= 0:
		print("[%s] 💀 英雄被击败！" % owner_name)


# 治疗英雄
func heal_player(amount: int):
	player_hp = min(max_player_hp, player_hp + amount)


# ========== 牌库操作 ==========



# ========== 调试 ==========

func print_status():
	print("=== [%s] HP:%d/%d Mana:%d/%d ===" % [owner_name, player_hp, max_player_hp, current_mana, max_mana])
	for i in range(5):
		if slots[i] == null:
			print("  格子%d: [空]" % i)
		else:
			print("  格子%d: %s" % [i, slots[i].get_status()])
