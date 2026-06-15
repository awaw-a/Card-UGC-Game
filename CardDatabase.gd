class_name CardDatabase
extends RefCounted

# ============================================
# Preset card database — all built-in cards defined here
# ============================================

# Player starter cards
static func player_starters() -> Array:
	return [
		CardData.new("Misaka",     3, 4, 3, []),
		CardData.new("Kuroko",     2, 3, 2, []),
		CardData.new("Uiharu",     1, 2, 1, []),
		CardData.new("Saten",      2, 4, 2, []),
	]


# Default library seeded into a player's collection on first launch.
# Five vanilla bodies plus five skill cards.
static func starter_library() -> Array:
	return [
		# --- No-skill bodies (cost / hp / atk) ---
		CardData.new("狂战士", 4, 4, 5, []),
		CardData.new("骑士",   3, 5, 3, []),
		CardData.new("哥布林", 1, 2, 2, []),
		CardData.new("巨人",   5, 8, 3, []),
		CardData.new("野蛮人", 3, 4, 4, []),

		# --- 精灵: 召唤时魅惑 1 个目标 ---
		CardData.new("精灵", 4, 3, 1, [
			_fx_skill("魅惑", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_CHARM, 1, "", 0, 1),
			]),
		]),

		# --- 牧师: 主动为自己及两边治疗 2 点生命 ---
		CardData.new("牧师", 2, 4, 1, [
			_fx_skill("祈祷", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_HEAL, 2),
			]),
		]),

		# --- 圣骑士: 主动为自己及两边提供 2 点护盾 ---
		CardData.new("圣骑士", 3, 3, 3, [
			_fx_skill("圣盾", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_SHIELD, 2),
			]),
		]),

		# --- 猎手: 受伤时回复 1 点生命，并有 50% 概率获得减伤 50% ---
		CardData.new("猎手", 2, 3, 2, [
			_fx_skill("闪躲", SkillEngine.TRIGGER_ON_DAMAGED, [
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_HEAL, 1),
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 50, SkillEngine.BUFF_DAMAGE_REDUCTION, 1, 0, 50),
			]),
		]),

		# --- 女巫: 主动为敌方目标添加霉运 75%，持续 1 回合 ---
		CardData.new("女巫", 3, 3, 1, [
			_fx_skill("诅咒", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_ADD_BUFF, 75, SkillEngine.BUFF_MISFORTUNE, 1),
			]),
		]),
	]


# Enemy presets by difficulty
static func goblin_warrior() -> CardData:
	return CardData.new("Goblin Warrior",  1, 2, 3, [])


static func goblin_archer() -> CardData:
	return CardData.new("Goblin Archer",   1, 3, 2, [])


static func goblin_shaman() -> CardData:
	return CardData.new("Goblin Shaman",   1, 2, 1, [
		_sample_skill("Heal Wave", SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_HEAL, 2),
	])


static func wolf_rider() -> CardData:
	return CardData.new("Wolf Rider",      3, 5, 4, [
		_sample_skill("Swipe", SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TARGET_SIDES, SkillEngine.EFFECT_DAMAGE, 2),
	])


static func boss_troll() -> CardData:
	return CardData.new("Boss Troll",      5, 12, 6, [
		_sample_skill("Roar", SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 4, SkillEngine.BUFF_ATK_BOOST, 2),
		_sample_skill("Thick Skin", SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TARGET_SELF, SkillEngine.EFFECT_SHIELD, 5),
	])


# Enemy waves
static func enemy_wave(difficulty: int) -> Array:
	match difficulty:
		1:
			return [goblin_warrior(), goblin_archer()]
		2:
			return [goblin_shaman(), goblin_warrior(), wolf_rider()]
		3:
			return [wolf_rider(), wolf_rider(), boss_troll()]
		_:
			return [goblin_warrior(), goblin_warrior()]


# ============================================
# Helpers
# ============================================

static func _sample_skill(sname: String, trigger: String, target: String, effect: String, value: int, buff: String = "", duration: int = 0) -> Dictionary:
	var s: Dictionary = {
		"skill_name": sname,
		"trigger": trigger,
		"target": target,
		"effect": effect,
		"value": value,
		"buff_id": buff,
		"duration": duration,
	}
	return s


# Build a skill in the multi-effect format the editor produces.
static func _fx_skill(sname: String, trigger: String, effects: Array, probability: int = 100) -> Dictionary:
	return {
		"skill_name": sname,
		"trigger": trigger,
		"probability": probability,
		"effects": effects,
	}


# Build a single effect entry. random_count = 0 means "all matched targets".
static func _fx(target: String, effect: String, value: int, buff: String = "", duration: int = 0, random_count: int = 0, probability: int = 100) -> Dictionary:
	return {
		"target": target,
		"effect": effect,
		"value": value,
		"buff_id": buff,
		"duration": duration,
		"random_count": random_count,
		"probability": probability,
	}
