extends Control

# ============================================
# Card Editor
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)

@onready var title_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TitleLabel
@onready var art_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtLabel
@onready var browse_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/BrowseButton
@onready var clear_art_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/ClearArtButton
@onready var name_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/NameLabel
@onready var name_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/NameInput
@onready var cost_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/CostLabel
@onready var cost_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/CostInput
@onready var hp_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/HpLabel
@onready var hp_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/HpInput
@onready var atk_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AtkLabel
@onready var atk_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AtkInput
@onready var gender_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/GenderLabel
@onready var gender_select = $Panel/MarginContainer/ScrollContainer/VBoxContainer/GenderSelect
@onready var art_path_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ArtRow/ArtPathLabel
@onready var art_dialog = $ArtFileDialog

@onready var skill1_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill1Label
@onready var skill1_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill1Summary
@onready var skill2_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill2Label
@onready var skill2_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill2Summary
@onready var edit_skill1_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill1Button
@onready var edit_skill2_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EditSkill2Button
@onready var save_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/SaveButton
@onready var back_button = $BackButton

signal card_created(new_card_data: CardData)


func _apply_texts() -> void:
	title_label.text = Locale.t("editor.title")
	art_label.text = Locale.t("editor.card_art")
	browse_button.text = Locale.t("editor.browse")
	name_label.text = Locale.t("editor.name")
	cost_label.text = Locale.t("editor.cost")
	hp_label.text = Locale.t("editor.hp")
	atk_label.text = Locale.t("editor.atk")
	gender_label.text = Locale.t("editor.gender")
	skill1_label.text = Locale.t("editor.skill_1")
	skill2_label.text = Locale.t("editor.skill_2")
	edit_skill1_btn.text = Locale.t("editor.edit_skill_1")
	edit_skill2_btn.text = Locale.t("editor.edit_skill_2")
	save_button.text = Locale.t("editor.update_card") if PlayerData.editing_index >= 0 else Locale.t("editor.save_card")
	back_button.text = Locale.t("common.back")
	art_dialog.title = Locale.t("editor.select_art")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()

	# MarginContainer
	var margin := $Panel/MarginContainer
	margin.add_theme_constant_override("margin_left", int(120 * s))
	margin.add_theme_constant_override("margin_right", int(120 * s))
	margin.add_theme_constant_override("margin_top", int(40 * s))
	margin.add_theme_constant_override("margin_bottom", int(40 * s))

	# Back button
	var back_btn := $BackButton
	back_btn.position = Vector2(8, 8) * s
	back_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))

	# VBox container
	var vbox := $Panel/MarginContainer/ScrollContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", int(8 * s))
	var art_row := vbox.get_node("ArtRow") as HBoxContainer
	if art_row:
		art_row.add_theme_constant_override("separation", int(4 * s))

	# Scale all labels and inputs in the VBox
	for child in vbox.get_children():
		if child is Label:
			var base_font := 14
			if child.name == "TitleLabel":
				base_font = 22
			child.add_theme_font_size_override("font_size", max(10, int(base_font * s)))
		elif child is LineEdit or child is SpinBox or child is OptionButton:
			child.custom_minimum_size = Vector2(200 * s, 0)
		elif child is Button:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	_setup_gender_dropdown()
	var is_fresh_entry: bool = PlayerData.card_draft.is_empty()

	if is_fresh_entry:
		if PlayerData.editing_index >= 0:
			var card: CardData = PlayerData.card_library[PlayerData.editing_index]
			PlayerData.load_card_to_draft(card)
		else:
			PlayerData.init_card_draft()

	_apply_texts()
	_restore_form_from_draft()
	_update_skill_labels()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _setup_gender_dropdown():
	gender_select.clear()
	gender_select.add_item(Locale.t("editor.gender_male"), 0)
	gender_select.add_item(Locale.t("editor.gender_female"), 1)
	gender_select.add_item(Locale.t("editor.gender_nonhuman"), 2)


func _restore_form_from_draft():
	name_input.text = PlayerData.card_draft.get("name", "")
	cost_input.value = PlayerData.card_draft.get("cost", 0)
	hp_input.value = PlayerData.card_draft.get("hp", 1)
	atk_input.value = PlayerData.card_draft.get("atk", 0)
	var gmap: Dictionary = {"male": 0, "female": 1, "nonhuman": 2}
	gender_select.selected = gmap.get(PlayerData.card_draft.get("gender", "female"), 1)

	var art: String = PlayerData.card_draft.get("art_path", "")
	if art != "":
		art_path_label.text = art.get_file()
	else:
		art_path_label.text = Locale.t("editor.none")


func _save_form_to_draft():
	PlayerData.card_draft["name"] = name_input.text if name_input.text != "" else Locale.t("editor.unnamed")
	PlayerData.card_draft["cost"] = int(cost_input.value)
	PlayerData.card_draft["hp"] = int(hp_input.value)
	PlayerData.card_draft["atk"] = int(atk_input.value)
	var genders: Array = ["male", "female", "nonhuman"]
	PlayerData.card_draft["gender"] = genders[gender_select.selected]


# ============================================
# Art picker
# ============================================

func _on_browse_art_pressed():
	art_dialog.popup_centered()


func _on_art_file_selected(path: String):
	var fname: String = path.get_file()
	var dest_dir: String = ProjectSettings.globalize_path("user://arts")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest: String = dest_dir + "/" + fname

	var err = DirAccess.copy_absolute(path, dest)
	if err != OK:
		print("Failed to copy art: %d" % err)
		art_path_label.text = Locale.t("editor.copy_failed")
		return

	PlayerData.card_draft["art_path"] = "user://arts/" + fname
	art_path_label.text = fname
	print("Art saved: %s" % dest)


func _on_clear_art_pressed():
	PlayerData.card_draft["art_path"] = ""
	art_path_label.text = Locale.t("editor.none")


# ============================================
# Skill preview
# ============================================

func _update_skill_labels():
	skill1_summary.text = _format_skill_short(PlayerData.card_draft.get("skill1", {}))
	skill2_summary.text = _format_skill_short(PlayerData.card_draft.get("skill2", {}))


func _format_skill_short(skill: Dictionary) -> String:
	if skill.is_empty():
		return Locale.t("editor.empty")

	var sname: String = skill.get("skill_name", "")
	var name_prefix: String = ("[%s] " % sname) if sname != "" else ""
	var t: String = Locale.term("trigger", skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK))

	var result: String = "%s%s " % [name_prefix, t]
	var sp: int = skill.get("probability", 100)
	if sp < 100:
		result += "%s " % Locale.t("skill.chance", [sp])

	# Effects (backward compat)
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and not skill.get("effect", "").is_empty():
		effects = [{"target": skill.get("target", ""), "effect": skill.get("effect", ""),
			"value": skill.get("value", 1), "buff_id": skill.get("buff_id", ""), "duration": skill.get("duration", 0)}]

	if effects.is_empty():
		result += Locale.t("editor.no_fx")
	else:
		var parts: Array = []
		for eff in effects:
			parts.append(SkillEngine._format_effect_sentence(eff))
		result += "；".join(parts) if Locale.language == "zh" else "; ".join(parts)

	return result


# ============================================
# Skill editing
# ============================================

func _on_edit_skill1_pressed():
	_save_form_to_draft()
	PlayerData.editing_skill_index = 0
	get_tree().change_scene_to_file("res://SkillEditor.tscn")


func _on_edit_skill2_pressed():
	_save_form_to_draft()
	PlayerData.editing_skill_index = 1
	get_tree().change_scene_to_file("res://SkillEditor.tscn")


# ============================================
# Save
# ============================================

func _on_save_button_pressed():
	_save_form_to_draft()
	var new_card: CardData = PlayerData.build_card_from_draft()

	if PlayerData.editing_index >= 0:
		PlayerData.update_card_in_library(PlayerData.editing_index, new_card)
	else:
		PlayerData.add_card_to_library(new_card)

	PlayerData.editing_index = -1
	PlayerData.card_draft.clear()

	var return_scene := PlayerData.card_editor_return_scene
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	get_tree().change_scene_to_file(return_scene)


# ============================================
# Back
# ============================================

func _on_back_button_pressed():
	PlayerData.editing_index = -1
	PlayerData.card_draft.clear()
	var return_scene := PlayerData.card_editor_return_scene
	PlayerData.card_editor_return_scene = "res://MainMenu.tscn"
	get_tree().change_scene_to_file(return_scene)
