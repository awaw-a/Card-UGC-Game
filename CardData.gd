class_name CardData
extends RefCounted

# ============================================
# Card data model
# ============================================

# Base stats
var card_name: String = ""
var cost: int = 0
var max_hp: int = 0
var hp: int = 0
var atk: int = 0
var base_cost: int = 0
var base_max_hp: int = 0
var base_atk: int = 0
var gender: String = "female"
var has_acted: bool = false
var has_attacked: bool = false
var summoned_this_turn: bool = false
var skills_used: Array = []
var charmed_slot: int = -1
var original_cost: int = -1

# Temporary HP (shield replacement, resets each turn)
var temp_hp: int = 0

# Skill definitions (Array[Dictionary])
var skills: Array = []

# Splash art texture path (empty = no art)
var art_path: String = ""

# Runtime status effects / buffs
# Each buff: { "buff_id": String, "value": int, "duration": int }
var status_effects: Array = []


func _init(_name: String, _cost: int, _hp: int, _atk: int, _skills: Array = []):
	card_name = _name
	cost = _cost
	max_hp = _hp
	hp = _hp
	atk = _atk
	base_cost = _cost
	base_max_hp = _hp
	base_atk = _atk
	skills = _skills


func is_alive() -> bool:
	return hp > 0


func is_silenced() -> bool:
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_SILENCE and eff.get("value", 0) > 0:
			return true
	return false


# ============================================
# Charm state
# ============================================

func is_charmed() -> bool:
	return original_cost != -1


func reset_charm_cost() -> void:
	if original_cost >= 0:
		cost = original_cost
		original_cost = -1
		charmed_slot = -1


# ============================================
# Damage & healing
# ============================================

# Temp HP consumed first, then real HP. Damage reduction applied first.
func take_damage(amount: int) -> int:
	if amount <= 0:
		return hp

	# Damage reduction (floor)
	var reduction_pct := get_damage_reduction()
	if reduction_pct > 0:
		var reduced := int(floor(float(amount) * (1.0 - float(reduction_pct) / 100.0)))
		print("  [DmgCut] %s reduces %d -> %d (%d%%)" % [card_name, amount, reduced, reduction_pct])
		amount = reduced

	if amount <= 0:
		return hp

	var remaining: int = amount

	if temp_hp > 0:
		var blocked: int = min(remaining, temp_hp)
		temp_hp -= blocked
		remaining -= blocked
		print("  [TempHP] %s absorbs %d, temp left: %d" % [card_name, blocked, temp_hp])

	if remaining > 0:
		hp = max(0, hp - remaining)

	return hp


func heal(amount: int) -> int:
	if amount <= 0:
		return hp
	hp = min(max_hp, hp + amount)
	return hp


# ============================================
# Effective ATK
# ============================================

func effective_atk() -> int:
	var bonus: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_ATK_BOOST:
			bonus += eff.get("value", 0)
	return atk + bonus


func get_thorns_damage() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_THORNS:
			total += eff.get("value", 0)
	return total


func get_damage_reduction() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_DAMAGE_REDUCTION:
			total += eff.get("value", 0)
	return total


func get_misfortune() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_MISFORTUNE:
			total += eff.get("value", 0)
	return total


func get_mana_refund() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_MANA_REFUND:
			total += eff.get("value", 0)
	return total


func has_taunt() -> bool:
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_TAUNT and eff.get("value", 0) > 0:
			return true
	return false


# ============================================
# Buff management (no merging — each buff is independent)
# ============================================

func apply_buff(buff_id: String, value: int, duration: int, owner: int = 0) -> void:
	# Temp HP is not a buff — just add to scalar

	status_effects.append({"buff_id": buff_id, "value": value, "duration": duration, "owner": owner})
	print("  [Buff] %s gained %s: v=%d d=%d (owner P%d)" % [card_name, buff_id, value, duration, owner])


func process_mana_refund(owner_player: int) -> int:
	var total: int = 0
	var to_remove: Array = []
	for i in range(status_effects.size()):
		var eff: Dictionary = status_effects[i]
		if eff.get("owner", 0) != owner_player:
			continue
		if eff.get("buff_id", "") != SkillEngine.BUFF_MANA_REFUND:
			continue
		var refund_val: int = eff.get("value", 0)
		if refund_val > 0:
			total += refund_val
			print("  [Mana+] %s refunds %d mana" % [card_name, refund_val])
		eff["duration"] = eff.get("duration", 0) - 1
		if eff["duration"] <= 0 or refund_val <= 0:
			to_remove.append(i)

	for j in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[j]
		var expired: Dictionary = status_effects[idx]
		print("  [Buff] %s's %s expired" % [card_name, expired.get("buff_id", "")])
		status_effects.remove_at(idx)

	return total


# Tick buffs belonging to a specific player
func tick_buffs(owner_player: int) -> void:
	# Reset temp HP each turn

	var to_remove: Array = []
	for i in range(status_effects.size()):
		var eff: Dictionary = status_effects[i]
		if eff.get("owner", 0) != owner_player:
			continue
		var buff_id: String = eff.get("buff_id", "")
		if buff_id == SkillEngine.BUFF_MANA_REFUND:
			continue

		if buff_id == SkillEngine.BUFF_REGEN:
			var regen_val: int = eff.get("value", 0)
			if regen_val > 0 and hp > 0:
				heal(regen_val)
				print("  [Regen] %s heals %d (HP: %d)" % [card_name, regen_val, hp])

		eff["duration"] = eff.get("duration", 0) - 1
		if eff["duration"] <= 0 or eff.get("value", 0) <= 0:
			to_remove.append(i)

	for j in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[j]
		var expired: Dictionary = status_effects[idx]
		print("  [Buff] %s's %s expired" % [card_name, expired.get("buff_id", "")])
		status_effects.remove_at(idx)


# ============================================
# Reset
# ============================================

func reset_to_base() -> void:
	cost = base_cost
	max_hp = base_max_hp
	atk = base_atk
	hp = max_hp
	temp_hp = 0
	has_acted = false
	has_attacked = false
	summoned_this_turn = false
	skills_used.clear()
	status_effects.clear()
	original_cost = -1
	charmed_slot = -1


# ============================================
# Copy
# ============================================

func duplicate_card() -> CardData:
	var copy := CardData.new(card_name, base_cost, base_max_hp, base_atk, skills.duplicate(true))
	copy.cost = cost
	copy.max_hp = max_hp
	copy.hp = hp
	copy.atk = atk
	copy.temp_hp = temp_hp
	copy.has_acted = has_acted
	copy.has_attacked = has_attacked
	copy.summoned_this_turn = summoned_this_turn
	copy.gender = gender
	copy.charmed_slot = charmed_slot
	copy.original_cost = original_cost
	copy.skills_used = skills_used.duplicate()
	copy.art_path = art_path
	copy.status_effects = status_effects.duplicate(true)
	return copy


func get_status() -> String:
	var s: String = "%s | C:%d A:%d H:%d/%d" % [card_name, cost, effective_atk(), hp, max_hp]
	if temp_hp > 0:
		s += " +%dt" % temp_hp
	return s
