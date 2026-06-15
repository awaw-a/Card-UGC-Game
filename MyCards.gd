extends Control

# ============================================
# My Cards — library browser with skill tooltips
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)

var card_ui_scene = preload("res://CardUI.tscn")

@onready var card_grid = $Panel/VBoxContainer/ScrollContainer/CardGrid
@onready var create_new_button = $Panel/VBoxContainer/TopBar/CreateNewButton
@onready var back_button = $Panel/VBoxContainer/TopBar/BackButton
@onready var title_label = $Panel/VBoxContainer/TopBar/TitleLabel


func _apply_texts() -> void:
	title_label.text = Locale.t("mycards.title")
	create_new_button.text = Locale.t("mycards.create_new")
	back_button.text = Locale.t("common.back")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var card_size := Vector2(120, 160) * s
	var card_width := card_size.x

	# Top bar
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	for btn in [create_new_button, back_button]:
		if btn:
			btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))

	# Grid children
	for card_box in card_grid.get_children():
		if not (card_box is VBoxContainer):
			continue
		card_box.custom_minimum_size = Vector2(card_width, 250 * s)
		card_box.add_theme_constant_override("separation", max(2, int(4 * s)))
		for child in card_box.get_children():
			if child.has_method("apply_ui_scale"):
				child.apply_ui_scale(s)
			elif child is HBoxContainer:
				child.custom_minimum_size = Vector2(card_width, 28 * s)
				child.add_theme_constant_override("separation", max(1, int(2 * s)))
				for row_btn in child.get_children():
					if row_btn is Button:
						row_btn.custom_minimum_size = Vector2((card_width - max(1, int(2 * s))) / 2.0, 28 * s)
						row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						row_btn.add_theme_font_size_override("font_size", max(9, int(11 * s)))
			elif child is VBoxContainer:
				child.custom_minimum_size = Vector2(card_width, 54 * s)
				child.add_theme_constant_override("separation", max(1, int(2 * s)))
				for skill_btn in child.get_children():
					if skill_btn is Button:
						skill_btn.custom_minimum_size = Vector2(card_width, 26 * s)
						skill_btn.add_theme_font_size_override("font_size", max(9, int(11 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	create_new_button.pressed.connect(_on_create_new_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	render_my_library()


func render_my_library():
	var s := _ui_scale()
	print("Render library: %d cards" % PlayerData.card_library.size())

	for child in card_grid.get_children():
		child.queue_free()

	if PlayerData.card_library.size() == 0:
		print("Library is empty")
		return

	for i in range(PlayerData.card_library.size()):
		var card_data: CardData = PlayerData.card_library[i]
		var card_index: int = i
		var card_width: float = 120.0 * s
		var row_gap: int = max(1, int(2 * s))

		var card_box := VBoxContainer.new()
		card_box.custom_minimum_size = Vector2(card_width, 250 * s)
		card_box.add_theme_constant_override("separation", max(2, int(4 * s)))

		# 1. Card preview (add to tree first so @onready works)
		card_grid.add_child(card_box)
		var card_ui_instance = card_ui_scene.instantiate()
		card_box.add_child(card_ui_instance)
		card_ui_instance.set_card(card_data)
		card_ui_instance.set_actions_visible(false)
		card_ui_instance.apply_ui_scale(s)

		# 2. Skill info buttons, styled like the in-game skill area without ATK.
		var skill_box := VBoxContainer.new()
		skill_box.custom_minimum_size = Vector2(card_width, 54 * s)
		skill_box.add_theme_constant_override("separation", row_gap)
		card_box.add_child(skill_box)
		for s_idx in range(card_data.skills.size()):
			var skill: Dictionary = card_data.skills[s_idx]
			var skill_btn := Button.new()
			var fallback := "S%d" % (s_idx + 1)
			var skill_name: String = skill.get("skill_name", "")
			skill_btn.text = skill_name if skill_name != "" else fallback
			skill_btn.tooltip_text = SkillEngine.format_skill_tooltip(skill)
			skill_btn.disabled = true
			skill_btn.clip_text = true
			skill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			skill_btn.custom_minimum_size = Vector2(card_width, 26 * s)
			skill_btn.add_theme_font_size_override("font_size", max(9, int(11 * s)))
			skill_box.add_child(skill_btn)

		# 3. Edit / Delete buttons fill the exact card width below the card.
		var btn_row := HBoxContainer.new()
		btn_row.custom_minimum_size = Vector2(card_width, 28 * s)
		btn_row.add_theme_constant_override("separation", row_gap)

		var edit_btn := Button.new()
		edit_btn.text = Locale.t("mycards.edit")
		edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit_btn.custom_minimum_size = Vector2((card_width - row_gap) / 2.0, 28 * s)
		edit_btn.add_theme_font_size_override("font_size", max(9, int(11 * s)))
		edit_btn.pressed.connect(_on_edit_pressed.bind(card_index))
		btn_row.add_child(edit_btn)

		var delete_btn := Button.new()
		delete_btn.text = Locale.t("mycards.delete")
		delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		delete_btn.custom_minimum_size = Vector2((card_width - row_gap) / 2.0, 28 * s)
		delete_btn.add_theme_font_size_override("font_size", max(9, int(11 * s)))
		delete_btn.pressed.connect(_on_delete_pressed.bind(card_index))
		btn_row.add_child(delete_btn)

		card_box.add_child(btn_row)

		print("  Loaded: %s" % card_data.card_name)


func _on_create_new_pressed():
	PlayerData.editing_index = -1
	get_tree().change_scene_to_file("res://CardEditor.tscn")


func _on_edit_pressed(index: int):
	PlayerData.editing_index = index
	get_tree().change_scene_to_file("res://CardEditor.tscn")


func _on_delete_pressed(index: int):
	PlayerData.remove_card_from_library(index)
	render_my_library()


func _on_back_pressed():
	get_tree().change_scene_to_file("res://MainMenu.tscn")
