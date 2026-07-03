extends Control

# ============================================
# Skill Editor — popup effect editor with blur
# ============================================

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const UITheme = preload("res://UITheme.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

@onready var title_label = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TitleLabel
@onready var skill_name_input = $Panel/MarginContainer/ScrollContainer/VBoxContainer/SkillNameInput
@onready var trigger_select = $Panel/MarginContainer/ScrollContainer/VBoxContainer/TriggerSelect
@onready var effects_list = $Panel/MarginContainer/ScrollContainer/VBoxContainer/EffectsList
@onready var add_effect_btn = $Panel/MarginContainer/ScrollContainer/VBoxContainer/AddEffectButton
@onready var skill_summary = $Panel/MarginContainer/ScrollContainer/VBoxContainer/SkillSummary
@onready var save_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ButtonRow/SaveButton
@onready var cancel_button = $Panel/MarginContainer/ScrollContainer/VBoxContainer/ButtonRow/CancelButton

var effect_data: Array = []        # [{target, effect, value, buff_id, duration}, ...]
var editing_effect_idx: int = -1   # -1 = new, 0+ = editing existing
var popup_layer: CanvasLayer
var popup_form: Dictionary = {}    # refs to popup controls
var skill_prob_spin: SpinBox       # skill-level probability


func _apply_texts() -> void:
	var skill_index: int = PlayerData.editing_skill_index
	title_label.text = Locale.t("skill_editor.title", [skill_index + 1])
	$Panel/MarginContainer/ScrollContainer/VBoxContainer/SkillNameLabel.text = Locale.t("skill_editor.name")
	skill_name_input.placeholder_text = Locale.t("skill_editor.name_placeholder")
	$Panel/MarginContainer/ScrollContainer/VBoxContainer/TriggerLabel.text = Locale.t("skill_editor.trigger")
	$Panel/MarginContainer/ScrollContainer/VBoxContainer/EffectsLabel.text = Locale.t("skill_editor.effects")
	add_effect_btn.text = Locale.t("skill_editor.add_effect")
	save_button.text = Locale.t("skill_editor.save")
	cancel_button.text = Locale.t("skill_editor.cancel")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()

	# Panel (centered 450x600)
	var panel := $Panel
	panel.offset_left = -225.0 * s
	panel.offset_top = -300.0 * s
	panel.offset_right = 225.0 * s
	panel.offset_bottom = 300.0 * s

	# MarginContainer
	var margin := $Panel/MarginContainer
	margin.add_theme_constant_override("margin_left", int(12 * s))
	margin.add_theme_constant_override("margin_top", int(8 * s))
	margin.add_theme_constant_override("margin_right", int(12 * s))
	margin.add_theme_constant_override("margin_bottom", int(8 * s))

	# VBox
	var vbox := $Panel/MarginContainer/ScrollContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", int(6 * s))

	# Title
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(12, int(20 * s)))

	# EffectsList
	if effects_list:
		effects_list.add_theme_constant_override("separation", int(4 * s))

	# ButtonRow
	var button_row := vbox.get_node("ButtonRow") as HBoxContainer
	if button_row:
		button_row.add_theme_constant_override("separation", int(16 * s))

	# Skill prob row SpinBox
	if skill_prob_spin:
		skill_prob_spin.custom_minimum_size = Vector2(60 * s, 0)

	# All labels/inputs/buttons in the VBox
	for child in vbox.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is LineEdit or child is OptionButton:
			child.custom_minimum_size = Vector2(200 * s, 0)
		elif child is Button and child != add_effect_btn:
			child.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		elif child is HBoxContainer:
			child.add_theme_constant_override("separation", int(8 * s))

	# Add effect button
	if add_effect_btn:
		add_effect_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _apply_theme() -> void:
	UITheme.apply_app_background(self)
	UITheme.apply_panel($Panel, "gold")
	UITheme.apply_title(title_label, max(18, int(20 * _ui_scale())))
	UITheme.apply_input(skill_name_input)
	UITheme.apply_button(trigger_select, "secondary")
	UITheme.apply_button(add_effect_btn, "primary")
	UITheme.apply_button(save_button, "primary")
	UITheme.apply_button(cancel_button, "secondary")
	UITheme.apply_label(skill_summary, true)
	for path in ["SkillNameLabel", "TriggerLabel", "EffectsLabel"]:
		var label := $Panel/MarginContainer/ScrollContainer/VBoxContainer.get_node(path) as Label
		UITheme.apply_label(label)


func _ready():
	_apply_theme()
	_setup_trigger_dropdown()
	_setup_skill_probability_row()
	_connect_signals()
	_apply_texts()

	var skill_index: int = PlayerData.editing_skill_index
	var skill_key: String = "skill1" if skill_index == 0 else "skill2"
	if PlayerData.card_draft.has(skill_key) and not PlayerData.card_draft[skill_key].is_empty():
		_load_skill(PlayerData.card_draft[skill_key])

	_refresh_effect_list()
	_update_summary()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _setup_trigger_dropdown():
	trigger_select.clear()
	var trigger_keys := [
		SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE,
		SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED,
	]
	for i in range(trigger_keys.size()):
		trigger_select.add_item(Locale.term("trigger", trigger_keys[i]), i)


func _setup_skill_probability_row():
	var vbox = trigger_select.get_parent()
	var idx = trigger_select.get_index()

	var s := _ui_scale()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))

	var lbl := Label.new()
	lbl.text = Locale.t("skill_editor.probability")
	lbl.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_label(lbl)
	row.add_child(lbl)

	skill_prob_spin = SpinBox.new()
	skill_prob_spin.custom_minimum_size = Vector2(60 * s, 0)
	skill_prob_spin.min_value = 1.0
	skill_prob_spin.max_value = 100.0
	skill_prob_spin.value = 100.0
	UITheme.apply_input(skill_prob_spin)
	skill_prob_spin.value_changed.connect(func(_f: float): _update_summary())
	row.add_child(skill_prob_spin)

	var pct := Label.new()
	pct.text = "%"
	UITheme.apply_label(pct)
	row.add_child(pct)

	vbox.add_child(row)
	vbox.move_child(row, idx + 1)


func _connect_signals():
	skill_name_input.text_changed.connect(func(_t: String): _update_summary())
	trigger_select.item_selected.connect(func(_i: int): _update_summary())
	add_effect_btn.pressed.connect(func(): _open_effect_popup(-1))
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _apply_dynamic_theme(root: Node) -> void:
	for child in root.get_children():
		if child is Label:
			UITheme.apply_label(child)
		elif child is OptionButton or child is Button:
			UITheme.apply_button(child, "danger" if child is Button and child.text == "X" else "secondary")
		elif child is SpinBox or child is LineEdit:
			UITheme.apply_input(child)
		_apply_dynamic_theme(child)


# ============================================
# Effect list (compact summaries)
# ============================================

func _refresh_effect_list():
	var s := _ui_scale()
	for child in effects_list.get_children():
		child.queue_free()

	for i in range(effect_data.size()):
		var eff: Dictionary = effect_data[i]
		var idx: int = i

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(6 * s))

		var lbl := Label.new()
		lbl.text = _format_effect_short(eff, idx)
		lbl.size_flags_horizontal = 3
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		row.add_child(lbl)

		var edit_btn := Button.new()
		edit_btn.text = Locale.t("skill_editor.edit")
		edit_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		edit_btn.pressed.connect(_open_effect_popup.bind(idx))
		row.add_child(edit_btn)

		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		del_btn.pressed.connect(_delete_effect.bind(idx))
		row.add_child(del_btn)

		effects_list.add_child(row)
	_apply_dynamic_theme(effects_list)


func _format_effect_short(eff: Dictionary, idx: int) -> String:
	return "[%d] %s" % [idx + 1, _TextFormatter.format_effect_sentence(eff)]


func _delete_effect(idx: int):
	if idx < 0 or idx >= effect_data.size():
		return
	effect_data.remove_at(idx)
	_refresh_effect_list()
	_update_summary()


# ============================================
# Popup — blur overlay + effect form
# ============================================

func _open_effect_popup(idx: int):
	editing_effect_idx = idx
	var s := _ui_scale()

	# Create blur overlay layer
	popup_layer = CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	# Blur background
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	popup_layer.add_child(bg)

	# Centered popup panel
	var popup_size := Vector2(390, 380) * s
	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.custom_minimum_size = popup_size
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -popup_size.x / 2.0
	panel.offset_top = -popup_size.y / 2.0
	panel.offset_right = popup_size.x / 2.0
	panel.offset_bottom = popup_size.y / 2.0
	popup_layer.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(6 * s))
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 10 * s
	outer.offset_top = 10 * s
	outer.offset_right = -10 * s
	outer.offset_bottom = -10 * s
	panel.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(6 * s))
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# Target dropdown
	var target_label := Label.new()
	target_label.text = Locale.t("skill_editor.target")
	target_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	vb.add_child(target_label)
	var target_sel := OptionButton.new()
	target_sel.custom_minimum_size = Vector2(200 * s, 0)
	_setup_target_dropdown(target_sel)
	vb.add_child(target_sel)

	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", int(4 * s))
	var side_label := Label.new()
	side_label.text = Locale.t("skill_editor.target_side")
	side_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	side_row.add_child(side_label)
	var side_sel := OptionButton.new()
	side_sel.size_flags_horizontal = 3
	side_sel.custom_minimum_size = Vector2(120 * s, 0)
	_setup_target_side_dropdown(side_sel)
	side_row.add_child(side_sel)
	vb.add_child(side_row)

	var warning_label := Label.new()
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	UITheme.apply_label(warning_label, true)
	vb.add_child(warning_label)

	var _update_target_warning = func():
		var trigger_keys := [
			SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE,
			SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED,
		]
		var trigger_key: String = trigger_keys[trigger_select.selected]
		var target_key: String = TARGET_KEYS[target_sel.selected]
		var msg := _target_warning_for(trigger_key, target_key, target_sel.disabled)
		warning_label.text = msg
		warning_label.visible = msg != ""

	var _update_target_side = func():
		var target_key: String = TARGET_KEYS[target_sel.selected]
		var disabled := target_sel.disabled or _TargetResolver.is_directed_target(target_key)
		side_sel.disabled = disabled
		if disabled:
			side_sel.selected = _idx_of(SkillEngine.TARGET_SIDE_ALL, TARGET_SIDE_KEYS)
		_update_target_warning.call()
	target_sel.item_selected.connect(func(_i: int): _update_target_side.call())

	# Effect + Value row
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", int(4 * s))
	var effect_label := Label.new()
	effect_label.text = Locale.t("skill_editor.effect")
	effect_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	r1.add_child(effect_label)
	var effect_sel := OptionButton.new()
	_setup_effect_dropdown(effect_sel)
	effect_sel.size_flags_horizontal = 3
	effect_sel.custom_minimum_size = Vector2(100 * s, 0)
	r1.add_child(effect_sel)
	var val_label := Label.new()
	val_label.text = Locale.t("skill_editor.value")
	val_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	r1.add_child(val_label)
	var val_spin := SpinBox.new()
	val_spin.custom_minimum_size = Vector2(50 * s, 0)
	val_spin.min_value = 1.0
	val_spin.max_value = 100.0
	val_spin.value = 1.0
	r1.add_child(val_spin)
	var pct_label := Label.new()
	pct_label.text = "%"
	pct_label.visible = false
	r1.add_child(pct_label)
	vb.add_child(r1)

	# Value mode dropdown: fixed / random range / variable
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", int(4 * s))
	var mode_label := Label.new()
	mode_label.text = Locale.t("skill_editor.value_mode")
	mode_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	mode_row.add_child(mode_label)
	var mode_sel := OptionButton.new()
	mode_sel.add_item(Locale.t("skill_editor.value_mode_fixed"), 0)
	mode_sel.add_item(Locale.t("skill_editor.value_mode_random"), 1)
	mode_sel.add_item(Locale.t("skill_editor.value_mode_var"), 2)
	mode_sel.size_flags_horizontal = 3
	mode_row.add_child(mode_sel)
	vb.add_child(mode_row)

	# Random range row (min / max)
	var rand_row := HBoxContainer.new()
	rand_row.add_theme_constant_override("separation", int(4 * s))
	var min_label := Label.new()
	min_label.text = Locale.t("skill_editor.value_min")
	min_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	rand_row.add_child(min_label)
	var min_spin := SpinBox.new()
	min_spin.custom_minimum_size = Vector2(50 * s, 0)
	min_spin.min_value = 1.0
	min_spin.max_value = 100.0
	min_spin.value = 1.0
	rand_row.add_child(min_spin)
	var max_label := Label.new()
	max_label.text = Locale.t("skill_editor.value_max")
	max_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	rand_row.add_child(max_label)
	var max_spin := SpinBox.new()
	max_spin.custom_minimum_size = Vector2(50 * s, 0)
	max_spin.min_value = 1.0
	max_spin.max_value = 100.0
	max_spin.value = 3.0
	rand_row.add_child(max_spin)
	rand_row.visible = false
	vb.add_child(rand_row)

	# Variable row (variable dropdown + offset)
	var var_row := HBoxContainer.new()
	var_row.add_theme_constant_override("separation", int(4 * s))
	var var_label := Label.new()
	var_label.text = Locale.t("skill_editor.value_var")
	var_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	var_row.add_child(var_label)
	var var_sel := OptionButton.new()
	var_sel.size_flags_horizontal = 3
	_setup_var_dropdown(var_sel)
	var_row.add_child(var_sel)
	var off_label := Label.new()
	off_label.text = Locale.t("skill_editor.value_offset")
	off_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	var_row.add_child(off_label)
	var off_spin := SpinBox.new()
	off_spin.custom_minimum_size = Vector2(50 * s, 0)
	off_spin.min_value = -20.0
	off_spin.max_value = 20.0
	off_spin.value = 0.0
	var_row.add_child(off_spin)
	var_row.visible = false
	vb.add_child(var_row)

	# Effect probability row
	var prob_row := HBoxContainer.new()
	prob_row.add_theme_constant_override("separation", int(4 * s))
	var prob_label := Label.new()
	prob_label.text = Locale.t("skill_editor.effect_prob")
	prob_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	prob_row.add_child(prob_label)
	var eff_prob_spin := SpinBox.new()
	eff_prob_spin.custom_minimum_size = Vector2(55 * s, 0)
	eff_prob_spin.min_value = 1.0
	eff_prob_spin.max_value = 100.0
	eff_prob_spin.value = 100.0
	prob_row.add_child(eff_prob_spin)
	var prob_pct := Label.new()
	prob_pct.text = "%"
	prob_pct.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	prob_row.add_child(prob_pct)
	vb.add_child(prob_row)

	# Random target count
	var rcount_row := HBoxContainer.new()
	var rcount_label := Label.new()
	rcount_label.text = Locale.t("skill_editor.max_targets")
	rcount_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	rcount_row.add_child(rcount_label)
	var rcount_spin := SpinBox.new()
	rcount_spin.custom_minimum_size = Vector2(50 * s, 0)
	rcount_spin.min_value = 0.0
	rcount_spin.max_value = 10.0
	rcount_spin.value = 0.0
	rcount_row.add_child(rcount_spin)
	vb.add_child(rcount_row)

	# Effect condition row
	var condition_row := HBoxContainer.new()
	condition_row.add_theme_constant_override("separation", int(4 * s))
	var condition_label := Label.new()
	condition_label.text = Locale.t("skill_editor.condition")
	condition_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	condition_row.add_child(condition_label)
	var condition_sel := OptionButton.new()
	condition_sel.size_flags_horizontal = 3
	_setup_condition_dropdown(condition_sel)
	condition_row.add_child(condition_sel)
	vb.add_child(condition_row)

	var condition_detail_row := HBoxContainer.new()
	condition_detail_row.add_theme_constant_override("separation", int(4 * s))
	var condition_op_label := Label.new()
	condition_op_label.text = Locale.t("skill_editor.condition_op")
	condition_op_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	condition_detail_row.add_child(condition_op_label)
	var condition_op_sel := OptionButton.new()
	_setup_condition_op_dropdown(condition_op_sel)
	condition_detail_row.add_child(condition_op_sel)
	var condition_value_label := Label.new()
	condition_value_label.text = Locale.t("skill_editor.condition_value")
	condition_value_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	condition_detail_row.add_child(condition_value_label)
	var condition_value_spin := SpinBox.new()
	condition_value_spin.custom_minimum_size = Vector2(55 * s, 0)
	condition_value_spin.min_value = 0.0
	condition_value_spin.max_value = 100.0
	condition_value_spin.value = 1.0
	condition_detail_row.add_child(condition_value_spin)
	condition_detail_row.visible = false
	vb.add_child(condition_detail_row)

	var condition_buff_row := HBoxContainer.new()
	condition_buff_row.add_theme_constant_override("separation", int(4 * s))
	var condition_buff_label := Label.new()
	condition_buff_label.text = Locale.t("skill_editor.condition_buff")
	condition_buff_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	condition_buff_row.add_child(condition_buff_label)
	var condition_buff_sel := OptionButton.new()
	condition_buff_sel.size_flags_horizontal = 3
	_setup_buff_dropdown(condition_buff_sel)
	condition_buff_row.add_child(condition_buff_sel)
	condition_buff_row.visible = false
	vb.add_child(condition_buff_row)

	# Buff row (conditional)
	var buff_row := HBoxContainer.new()
	buff_row.add_theme_constant_override("separation", int(4 * s))
	var buff_sel := OptionButton.new()
	_setup_buff_dropdown(buff_sel)
	buff_sel.size_flags_horizontal = 3
	buff_sel.custom_minimum_size = Vector2(120 * s, 0)
	buff_row.add_child(buff_sel)
	var dur_label := Label.new()
	dur_label.text = Locale.t("skill_editor.duration")
	dur_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	buff_row.add_child(dur_label)
	var dur_spin := SpinBox.new()
	dur_spin.custom_minimum_size = Vector2(50 * s, 0)
	dur_spin.min_value = 1.0
	dur_spin.max_value = 10.0
	dur_spin.value = 2.0
	buff_row.add_child(dur_spin)
	buff_row.visible = false
	vb.add_child(buff_row)

	var _update_pct = func():
		var effect_key: String = EFFECT_KEYS[effect_sel.selected]
		var buff_key: String = BUFF_KEYS[buff_sel.selected]
		pct_label.visible = (effect_key == SkillEngine.EFFECT_ADD_BUFF and buff_key in [SkillEngine.BUFF_DAMAGE_REDUCTION, SkillEngine.BUFF_MISFORTUNE])

	# Value-mode toggle: 0=fixed (val_spin), 1=random (rand_row), 2=variable (var_row)
	var _update_value_mode = func(m: int):
		var effect_key: String = EFFECT_KEYS[effect_sel.selected]
		var uses_value := not effect_key in EFFECTS_NO_VALUE
		val_label.visible = uses_value and (m == 0)
		val_spin.visible = uses_value and (m == 0)
		rand_row.visible = uses_value and (m == 1)
		var_row.visible = uses_value and (m == 2)
		mode_row.visible = uses_value
	mode_sel.item_selected.connect(func(m: int): _update_value_mode.call(m))

	effect_sel.item_selected.connect(func(i: int):
		var effect_key: String = EFFECT_KEYS[i]
		buff_row.visible = (effect_key == SkillEngine.EFFECT_ADD_BUFF)
		target_sel.disabled = effect_key in EFFECTS_FORCE_SELF
		_update_target_side.call()
		mode_sel.disabled = effect_key in EFFECTS_NO_VALUE
		if effect_key != SkillEngine.EFFECT_ADD_BUFF:
			val_spin.editable = true
		else:
			val_spin.editable = not BUFF_KEYS[buff_sel.selected] in [SkillEngine.BUFF_TAUNT, SkillEngine.BUFF_SILENCE]
		_update_value_mode.call(mode_sel.selected)
		_update_pct.call()
	)
	buff_sel.item_selected.connect(func(_i: int):
		var buff_key: String = BUFF_KEYS[_i]
		if buff_key in [SkillEngine.BUFF_TAUNT, SkillEngine.BUFF_SILENCE]:
			val_spin.value = 1.0
			val_spin.editable = false
		else:
			val_spin.editable = true
		_update_pct.call()
	)

	var _update_condition_mode = func(_i: int):
		var condition_type: String = CONDITION_KEYS[condition_sel.selected]
		var has_condition := condition_type != SkillEngine.CONDITION_NONE
		var uses_buff := condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF
		condition_detail_row.visible = has_condition and not uses_buff
		condition_buff_row.visible = uses_buff
	condition_sel.item_selected.connect(func(i: int): _update_condition_mode.call(i))

	# Buttons
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", int(16 * s))
	var ok_btn := Button.new()
	ok_btn.text = Locale.t("skill_editor.ok")
	ok_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(ok_btn, "primary")
	ok_btn.pressed.connect(_on_popup_ok)
	btns.add_child(ok_btn)
	var cls_btn := Button.new()
	cls_btn.text = Locale.t("skill_editor.cancel")
	cls_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(cls_btn, "secondary")
	cls_btn.pressed.connect(_on_popup_cancel)
	btns.add_child(cls_btn)
	outer.add_child(btns)
	_apply_dynamic_theme(vb)
	UITheme.apply_button(ok_btn, "primary")
	UITheme.apply_button(cls_btn, "secondary")

	# Store refs for reading later
	popup_form = {
		"target_sel": target_sel, "side_sel": side_sel, "warning_label": warning_label, "effect_sel": effect_sel, "val_spin": val_spin,
		"buff_sel": buff_sel, "dur_spin": dur_spin, "buff_row": buff_row,
		"rcount_spin": rcount_spin, "pct_label": pct_label,
		"prob_spin": eff_prob_spin,
		"mode_sel": mode_sel, "min_spin": min_spin, "max_spin": max_spin,
		"var_sel": var_sel, "off_spin": off_spin,
		"condition_sel": condition_sel, "condition_op_sel": condition_op_sel,
		"condition_value_spin": condition_value_spin, "condition_buff_sel": condition_buff_sel,
	}

	# Load existing data if editing
	if idx >= 0 and idx < effect_data.size():
		var eff: Dictionary = _TargetResolver.normalize_effect_target(effect_data[idx])
		target_sel.selected = _idx_of(eff.get("target", SkillEngine.TARGET_SINGLE), TARGET_KEYS)
		side_sel.selected = _idx_of(eff.get("target_side", SkillEngine.TARGET_SIDE_ALL), TARGET_SIDE_KEYS)
		_update_target_side.call()
		effect_sel.selected = _idx_of(eff.get("effect", SkillEngine.EFFECT_DAMAGE), EFFECT_KEYS)
		val_spin.value = float(eff.get("value", 1))
		buff_sel.selected = _idx_of(eff.get("buff_id", SkillEngine.BUFF_ATK_BOOST), BUFF_KEYS)
		val_spin.editable = (buff_sel.selected not in [5, 6])
		target_sel.disabled = (effect_sel.selected == 2)
		_update_target_side.call()
		dur_spin.value = int(eff.get("duration", 2))
		rcount_spin.value = float(eff.get("random_count", 0))
		eff_prob_spin.value = float(eff.get("probability", 100))
		buff_row.visible = (effect_sel.selected == 5)
		# Detect value mode from which optional fields are present.
		var var_id: String = eff.get("value_var", "")
		if var_id != "":
			mode_sel.selected = 2
			var_sel.selected = _idx_of(var_id, VAR_KEYS)
			off_spin.value = float(eff.get("value_offset", 0))
		elif eff.has("value_min") and eff.has("value_max"):
			mode_sel.selected = 1
			min_spin.value = float(eff.get("value_min", 1))
			max_spin.value = float(eff.get("value_max", 1))
		else:
			mode_sel.selected = 0
		condition_sel.selected = _idx_of(eff.get("condition_type", SkillEngine.CONDITION_NONE), CONDITION_KEYS)
		condition_op_sel.selected = _idx_of(eff.get("condition_op", SkillEngine.CONDITION_OP_GTE), CONDITION_OP_KEYS)
		condition_value_spin.value = float(eff.get("condition_value", 1))
		condition_buff_sel.selected = _idx_of(eff.get("condition_buff_id", SkillEngine.BUFF_TAUNT), BUFF_KEYS)
		_update_condition_mode.call(condition_sel.selected)
		_update_value_mode.call(mode_sel.selected)
		_update_pct.call()
	else:
		_update_value_mode.call(0)
		_update_condition_mode.call(0)
		_update_target_side.call()


func _on_popup_ok():
	var eff := {
		"target": TARGET_KEYS[popup_form.target_sel.selected],
		"target_side": TARGET_SIDE_KEYS[popup_form.side_sel.selected],
		"effect": EFFECT_KEYS[popup_form.effect_sel.selected],
		"value": float(popup_form.val_spin.value),
		"buff_id": "",
		"duration": 0,
		"random_count": int(popup_form.rcount_spin.value),
		"probability": int(popup_form.prob_spin.value),
	}
	# Value mode: 0=fixed, 1=random range, 2=variable. Only the active mode's
	# fields are written so _resolve_value / _describe_value pick the right one.
	var vmode: int = popup_form.mode_sel.selected
	if vmode == 1:
		eff.value_min = int(popup_form.min_spin.value)
		eff.value_max = int(popup_form.max_spin.value)
	elif vmode == 2:
		eff.value_var = VAR_KEYS[popup_form.var_sel.selected]
		eff.value_offset = int(popup_form.off_spin.value)
	if popup_form.effect_sel.selected == 5:
		eff.buff_id = BUFF_KEYS[popup_form.buff_sel.selected]
		eff.duration = int(popup_form.dur_spin.value)
		eff.random_count = int(popup_form.rcount_spin.value)
	var condition_type: String = CONDITION_KEYS[popup_form.condition_sel.selected]
	if condition_type != SkillEngine.CONDITION_NONE:
		eff.condition_type = condition_type
		if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
			eff.condition_buff_id = BUFF_KEYS[popup_form.condition_buff_sel.selected]
		else:
			eff.condition_op = CONDITION_OP_KEYS[popup_form.condition_op_sel.selected]
			eff.condition_value = int(popup_form.condition_value_spin.value)
	if eff.effect in EFFECTS_FORCE_SELF:
		eff.target = SkillEngine.TARGET_SELF
		eff.target_side = SkillEngine.TARGET_SIDE_ALL
	if _TargetResolver.is_directed_target(eff.target):
		eff.target_side = SkillEngine.TARGET_SIDE_ALL
	eff = _TargetResolver.normalize_effect_target(eff)

	if editing_effect_idx >= 0:
		effect_data[editing_effect_idx] = eff
	else:
		effect_data.append(eff)

	_close_popup()
	_refresh_effect_list()
	_update_summary()


func _on_popup_cancel():
	_close_popup()


func _close_popup():
	if popup_layer:
		popup_layer.queue_free()
		popup_layer = null
	popup_form = {}
	editing_effect_idx = -1


# ============================================
# Dropdown helpers
# ============================================

const TARGET_KEYS := [
	SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES,
	SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES,
	SkillEngine.TARGET_ALL,
	SkillEngine.TARGET_MALE, SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN,
]
const TARGET_SIDE_KEYS := [
	SkillEngine.TARGET_SIDE_ENEMY, SkillEngine.TARGET_SIDE_ALLY, SkillEngine.TARGET_SIDE_ALL,
]
const EFFECT_KEYS := [
	SkillEngine.EFFECT_DAMAGE, SkillEngine.EFFECT_HEAL,
	SkillEngine.EFFECT_DRAW_CARDS, SkillEngine.EFFECT_SHIELD,
	SkillEngine.EFFECT_CHARM,
	SkillEngine.EFFECT_ADD_BUFF,
	SkillEngine.EFFECT_LIFESTEAL_DAMAGE,
	SkillEngine.EFFECT_EXECUTE,
	SkillEngine.EFFECT_CLEANSE,
	SkillEngine.EFFECT_DISPEL,
	SkillEngine.EFFECT_GAIN_MANA,
	SkillEngine.EFFECT_GAIN_ATTACK,
	SkillEngine.EFFECT_GAIN_MAX_HP,
]
const EFFECTS_FORCE_SELF := [SkillEngine.EFFECT_DRAW_CARDS, SkillEngine.EFFECT_GAIN_MANA]
const EFFECTS_NO_VALUE := [SkillEngine.EFFECT_CLEANSE, SkillEngine.EFFECT_DISPEL]
const BUFF_KEYS := [
	SkillEngine.BUFF_ATK_BOOST,
	SkillEngine.BUFF_REGEN,
	SkillEngine.BUFF_MANA_REFUND,
	SkillEngine.BUFF_THORNS,
	SkillEngine.BUFF_DAMAGE_REDUCTION,
	SkillEngine.BUFF_TAUNT,
	SkillEngine.BUFF_SILENCE,
	SkillEngine.BUFF_MISFORTUNE,
]
const VAR_KEYS := [
	SkillEngine.VAR_FIELD_TOTAL, SkillEngine.VAR_FIELD_ALLY, SkillEngine.VAR_FIELD_ENEMY,
	SkillEngine.VAR_EMPTY_ALLY, SkillEngine.VAR_EMPTY_ENEMY,
	SkillEngine.VAR_HAND_COUNT, SkillEngine.VAR_MANA_CURRENT,
]
const CONDITION_KEYS := [
	SkillEngine.CONDITION_NONE,
	SkillEngine.CONDITION_SOURCE_HP_PCT,
	SkillEngine.CONDITION_TARGET_HP_PCT,
	SkillEngine.CONDITION_FIELD_ALLY,
	SkillEngine.CONDITION_FIELD_ENEMY,
	SkillEngine.CONDITION_HAND_COUNT,
	SkillEngine.CONDITION_MANA_CURRENT,
	SkillEngine.CONDITION_TARGET_HAS_BUFF,
]
const CONDITION_OP_KEYS := [
	SkillEngine.CONDITION_OP_GTE, SkillEngine.CONDITION_OP_LTE, SkillEngine.CONDITION_OP_EQ,
]

func _target_warning_for(trigger_key: String, target_key: String, target_disabled: bool = false) -> String:
	if target_disabled:
		return Locale.t("skill_editor.warning_forced_self")
	if _TargetResolver.is_directed_target(target_key):
		if target_key in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] and trigger_key == SkillEngine.TRIGGER_ON_DEATH:
			return Locale.t("skill_editor.warning_death_directed")
		if target_key in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] and trigger_key in [SkillEngine.TRIGGER_ON_ACTIVATE, SkillEngine.TRIGGER_ON_SUMMON]:
			return Locale.t("skill_editor.warning_manual_target")
		return Locale.t("skill_editor.warning_side_ignored")
	if trigger_key == SkillEngine.TRIGGER_ON_DEATH:
		return Locale.t("skill_editor.warning_death_filter")
	return Locale.t("skill_editor.warning_side_filter")


func _setup_target_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(TARGET_KEYS.size()):
		dd.add_item(Locale.term("target", TARGET_KEYS[i]), i)

func _setup_target_side_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(TARGET_SIDE_KEYS.size()):
		dd.add_item(Locale.term("target_side", TARGET_SIDE_KEYS[i]), i)

func _setup_effect_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(EFFECT_KEYS.size()):
		dd.add_item(Locale.term("effect", EFFECT_KEYS[i]), i)

func _setup_buff_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(BUFF_KEYS.size()):
		dd.add_item(Locale.term("buff", BUFF_KEYS[i]), i)

func _setup_var_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(VAR_KEYS.size()):
		dd.add_item(Locale.term("value_var", VAR_KEYS[i]), i)

func _setup_condition_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(CONDITION_KEYS.size()):
		var key: String = CONDITION_KEYS[i]
		var label := Locale.t("skill_editor.condition_none") if key == SkillEngine.CONDITION_NONE else Locale.term("condition", key)
		dd.add_item(label, i)

func _setup_condition_op_dropdown(dd: OptionButton):
	dd.clear()
	for i in range(CONDITION_OP_KEYS.size()):
		dd.add_item(Locale.term("condition_op", CONDITION_OP_KEYS[i]), i)

func _idx_of(key: String, keys: Array) -> int:
	var i := keys.find(key)
	return i if i >= 0 else 0


# ============================================
# Build / Load / Summary
# ============================================

func _load_skill(skill: Dictionary):
	skill_name_input.text = skill.get("skill_name", "")
	trigger_select.selected = _idx_of(skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK), [
		SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE,
		SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED,
	])
	if skill_prob_spin:
		skill_prob_spin.value = float(skill.get("probability", 100))

	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and not skill.get("effect", "").is_empty():
		effects = [{
			"target": skill.get("target", SkillEngine.TARGET_SINGLE),
			"effect": skill.get("effect", SkillEngine.EFFECT_DAMAGE),
			"value": skill.get("value", 1),
			"buff_id": skill.get("buff_id", ""),
			"duration": skill.get("duration", 0),
		}]
	var normalized_effects: Array = []
	for eff in effects:
		normalized_effects.append(_TargetResolver.normalize_effect_target(eff))
	effect_data = normalized_effects
	_refresh_effect_list()


func _build_skill() -> Dictionary:
	if effect_data.is_empty():
		return {}
	var trigger_keys := [
		SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_ACTIVATE,
		SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TRIGGER_ON_DEATH, SkillEngine.TRIGGER_ON_DAMAGED,
	]
	return {
		"skill_name": skill_name_input.text.strip_edges(),
		"trigger": trigger_keys[trigger_select.selected],
		"probability": int(skill_prob_spin.value) if skill_prob_spin else 100,
		"effects": effect_data.duplicate(true),
	}


func _update_summary():
	var skill: Dictionary = _build_skill()
	skill_summary.text = _format_skill(skill)


func _format_skill(skill: Dictionary) -> String:
	var sname: String = skill.get("skill_name", "?")
	if sname == "":
		sname = Locale.t("skill.no_name")
	var tname: String = Locale.term("trigger", skill.get("trigger", SkillEngine.TRIGGER_ON_ATTACK))
	var lines: String = "[%s] %s\n" % [sname, tname]
	var sp: int = skill.get("probability", 100)
	if sp < 100:
		lines += "  %s\n" % Locale.t("skill.chance", [sp])
	var effects: Array = skill.get("effects", [])
	if effects.is_empty():
		lines += "  %s" % Locale.t("skill.no_effects")
	for i in range(effects.size()):
		var eff: Dictionary = effects[i]
		lines += "  %d. %s" % [i + 1, _TextFormatter.format_effect_sentence(eff)]
		if i < effects.size() - 1:
			lines += "\n"
	return lines


# ============================================
# Save / Cancel
# ============================================

func _on_save_pressed():
	var skill: Dictionary = _build_skill()
	var skill_key: String = "skill1" if PlayerData.editing_skill_index == 0 else "skill2"
	PlayerData.card_draft[skill_key] = skill
	print("Skill saved: %s" % skill.get("skill_name", ""))
	get_tree().change_scene_to_file("res://CardEditor.tscn")


func _on_cancel_pressed():
	get_tree().change_scene_to_file("res://CardEditor.tscn")
