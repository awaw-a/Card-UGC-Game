extends Control

signal attack_requested
signal skill1_requested
signal skill2_requested

@onready var name_label = $NameLabel
@onready var cost_label = $CostLabel
@onready var hp_label = $HpLabel
@onready var atk_label = $AtkLabel
@onready var action_buttons = $ActionButtons
@onready var normal_atk_btn = $ActionButtons/NormalAtkButton
@onready var skill1_btn = $ActionButtons/Skill1Button
@onready var skill2_btn = $ActionButtons/Skill2Button

var current_card_data: CardData = null
var buff_dots: HBoxContainer
var silence_label: Label
var ui_scale: float = 1.0


func _scaled_rect(left: float, top: float, right: float, bottom: float) -> void:
	offset_left = left * ui_scale
	offset_top = top * ui_scale
	offset_right = right * ui_scale
	offset_bottom = bottom * ui_scale


func _scale_child_rect(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	if control == null:
		return
	control.offset_left = left * ui_scale
	control.offset_top = top * ui_scale
	control.offset_right = right * ui_scale
	control.offset_bottom = bottom * ui_scale


func apply_ui_scale(scale_value: float) -> void:
	ui_scale = scale_value
	custom_minimum_size = Vector2(120, 160) * ui_scale
	size = custom_minimum_size
	_scaled_rect(0, 0, 120, 160)
	_scale_child_rect($Background, 0, 0, 120, 160)
	_scale_child_rect(name_label, 6, 4, 114, 22)
	_scale_child_rect(cost_label, 6, 26, 58, 40)
	_scale_child_rect(hp_label, 6, 42, 94, 56)
	_scale_child_rect(atk_label, 6, 58, 94, 72)
	_scale_child_rect(action_buttons, 6, 82, 114, 154)
	if name_label:
		name_label.add_theme_font_size_override("font_size", max(10, int(13 * ui_scale)))
	for label in [cost_label, hp_label, atk_label]:
		if label:
			label.add_theme_font_size_override("font_size", max(9, int(11 * ui_scale)))
	for button in [normal_atk_btn, skill1_btn, skill2_btn]:
		if button:
			button.add_theme_font_size_override("font_size", max(9, int(11 * ui_scale)))
	if action_buttons:
		action_buttons.add_theme_constant_override("separation", max(1, int(2 * ui_scale)))
	if buff_dots:
		buff_dots.position = Vector2(6, 74) * ui_scale
		buff_dots.add_theme_constant_override("separation", max(1, int(2 * ui_scale)))
	if silence_label:
		silence_label.position = Vector2(6, 140) * ui_scale
		silence_label.add_theme_font_size_override("font_size", max(10, int(13 * ui_scale)))


func _ready():
	# Buff indicator dots
	buff_dots = HBoxContainer.new()
	buff_dots.add_theme_constant_override("separation", 2)
	buff_dots.position = Vector2(6, 74)
	add_child(buff_dots)

	# Silence indicator
	silence_label = Label.new()
	silence_label.text = Locale.t("card.silenced")
	silence_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	silence_label.add_theme_font_size_override("font_size", 13)
	silence_label.position = Vector2(6, 140)
	silence_label.visible = false
	add_child(silence_label)

	if normal_atk_btn:
		normal_atk_btn.pressed.connect(func(): attack_requested.emit())
		normal_atk_btn.tooltip_text = Locale.t("card.basic_attack")
	if skill1_btn:
		skill1_btn.pressed.connect(func(): skill1_requested.emit())
	if skill2_btn:
		skill2_btn.pressed.connect(func(): skill2_requested.emit())

	_auto_hide_if_enemy()


func set_card(card_data: CardData):
	current_card_data = card_data

	if card_data == null:
		if name_label: name_label.text = ""
		if cost_label: cost_label.text = ""
		if hp_label: hp_label.text = ""
		if atk_label: atk_label.text = ""
		if action_buttons: action_buttons.visible = false
		if silence_label: silence_label.visible = false
		self.modulate = Color.WHITE
		_clear_buff_dots()
		return

	name_label.text = card_data.card_name
	if card_data.is_charmed():
		cost_label.text = Locale.t("card.cost_charmed")
		cost_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))  # green for charmed
	else:
		cost_label.text = Locale.t("card.cost", [card_data.cost])
		cost_label.add_theme_color_override("font_color", Color.WHITE)

	# HP: show current/max, plus temp HP if any
	if card_data.temp_hp > 0:
		hp_label.text = Locale.t("card.hp_temp", [card_data.hp, card_data.max_hp, card_data.temp_hp])
	else:
		hp_label.text = Locale.t("card.hp", [card_data.hp, card_data.max_hp])

	# ATK: show effective, plus bonus
	var eff_atk: int = card_data.effective_atk()
	var bonus: int = eff_atk - card_data.atk
	if bonus > 0:
		atk_label.text = Locale.t("card.atk_bonus", [eff_atk, bonus])
	else:
		atk_label.text = Locale.t("card.atk", [eff_atk])

	_update_buff_dots()
	_update_skill_buttons()
	if silence_label:
		silence_label.visible = card_data.is_silenced()
	if action_buttons and card_data.is_silenced():
		action_buttons.visible = false
	self.modulate = Color(0.5, 0.5, 0.5) if card_data.is_silenced() else Color.WHITE
	_auto_hide_if_enemy()


func _clear_buff_dots():
	for child in buff_dots.get_children():
		child.queue_free()


func _update_buff_dots():
	_clear_buff_dots()
	for eff in current_card_data.status_effects:
		var val: int = eff.get("value", 0)
		if val <= 0:
			continue
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10) * ui_scale
		if eff.get("buff_id", "") == SkillEngine.BUFF_TAUNT:
			dot.color = Color(0.3, 0.5, 1.0)  # blue for taunt
		elif eff.get("buff_id", "") == SkillEngine.BUFF_SILENCE:
			dot.color = Color(0.9, 0.2, 0.2)  # red for silence
		elif eff.get("buff_id", "") == SkillEngine.BUFF_MANA_REFUND:
			dot.color = Color(0.2, 0.8, 1.0)
		elif eff.get("buff_id", "") == SkillEngine.BUFF_MISFORTUNE:
			dot.color = Color(0.3, 0.3, 0.3)  # dark grey for misfortune
		else:
			dot.color = Color.GREEN
		dot.tooltip_text = _format_buff_tooltip(eff)
		buff_dots.add_child(dot)


func _format_buff_tooltip(eff: Dictionary) -> String:
	var bid: String = eff.get("buff_id", "")
	var val: int = eff.get("value", 0)
	var dur: int = eff.get("duration", 0)
	var name: String = Locale.term("buff", bid)
	return Locale.t("card.buff_tooltip", [name, val, dur])


func _update_skill_buttons():
	if skill1_btn:
		if current_card_data.skills.size() >= 1:
			var s: Dictionary = current_card_data.skills[0]
			var sname: String = s.get("skill_name", "")
			skill1_btn.text = sname if sname != "" else "S1"
			skill1_btn.tooltip_text = SkillEngine.format_skill_tooltip(s)
			skill1_btn.visible = true
			_apply_skill_button_state(skill1_btn, s, 0)
		else:
			skill1_btn.visible = false

	if skill2_btn:
		if current_card_data.skills.size() >= 2:
			var s: Dictionary = current_card_data.skills[1]
			var sname: String = s.get("skill_name", "")
			skill2_btn.text = sname if sname != "" else "S2"
			skill2_btn.tooltip_text = SkillEngine.format_skill_tooltip(s)
			skill2_btn.visible = true
			_apply_skill_button_state(skill2_btn, s, 1)
		else:
			skill2_btn.visible = false


# Grey out + disable a skill button when its skill can't be activated now:
# already used this turn, an on_summon skill outside its summon turn, or an
# on_activate skill on a card that has already attacked.
func _apply_skill_button_state(btn: Button, skill: Dictionary, skill_index: int) -> void:
	var unavailable := false
	var trig: String = skill.get("trigger", "")
	if current_card_data.skills_used.has(skill_index):
		unavailable = true
	elif trig == SkillEngine.TRIGGER_ON_SUMMON and not current_card_data.summoned_this_turn:
		unavailable = true
	elif trig == SkillEngine.TRIGGER_ON_ACTIVATE and current_card_data.has_attacked:
		unavailable = true
	btn.disabled = unavailable
	btn.modulate = Color(0.5, 0.5, 0.5) if unavailable else Color.WHITE


func _auto_hide_if_enemy():
	pass  # 2P mode: buttons always visible


func set_actions_visible(visible: bool):
	if action_buttons:
		action_buttons.visible = visible


func _get_drag_data(_position: Vector2):
	if current_card_data == null:
		return null

	var preview_card = duplicate()
	preview_card.modulate.a = 0.6
	preview_card.anchor_right = 0.0
	preview_card.anchor_bottom = 0.0
	if preview_card.has_method("apply_ui_scale"):
		preview_card.call("apply_ui_scale", ui_scale)
	else:
		preview_card.offset_right = 120.0 * ui_scale
		preview_card.offset_bottom = 160.0 * ui_scale
	set_drag_preview(preview_card)

	return {
		"card_ui": self,
		"card_data": current_card_data
	}
