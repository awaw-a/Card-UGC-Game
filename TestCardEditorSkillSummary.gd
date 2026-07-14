extends Node


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.card_draft = {
		"name": "测试卡",
		"cost": 2,
		"hp": 4,
		"atk": 2,
		"gender": "male",
		"card_type": "minion",
		"art_path": "",
		"skill1": {},
		"skill2": {
			"skill_name": "第二技能",
			"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
			"probability": 100,
			"effects": [{
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value": 2,
			}],
		},
	}
	var scene: PackedScene = load("res://CardEditor.tscn")
	var editor: Node = scene.instantiate()
	add_child(editor)
	await get_tree().process_frame
	var summary: Label = editor.get_node("Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill2Summary")
	if summary.text == Locale.t("editor.empty") or not summary.text.contains("第二技能") or not summary.text.contains("2"):
		push_error("Skill2 summary did not render saved second skill: %s" % summary.text)
		get_tree().quit(1)
		return
	print("TEST_CARD_EDITOR_SKILL_SUMMARY_OK")
	get_tree().quit(0)
