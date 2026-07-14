extends RefCounted
class_name UITheme

const COLOR_BG := Color(0.055, 0.065, 0.085)
const COLOR_PANEL := Color(0.105, 0.12, 0.155, 0.96)
const COLOR_PANEL_SOFT := Color(0.13, 0.145, 0.18, 0.9)
const COLOR_PANEL_DARK := Color(0.075, 0.085, 0.11, 0.96)
const COLOR_GOLD := Color(0.82, 0.66, 0.34)
const COLOR_GOLD_SOFT := Color(0.54, 0.44, 0.24)
const COLOR_BLUE := Color(0.30, 0.43, 0.62)
const COLOR_TEXT := Color(0.92, 0.91, 0.86)
const COLOR_TEXT_MUTED := Color(0.64, 0.68, 0.74)
const COLOR_BUTTON := Color(0.17, 0.22, 0.31)
const COLOR_BUTTON_HOVER := Color(0.23, 0.30, 0.42)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.16, 0.24)
const COLOR_PRIMARY := Color(0.36, 0.28, 0.12)
const COLOR_PRIMARY_HOVER := Color(0.49, 0.38, 0.16)
const COLOR_PRIMARY_PRESSED := Color(0.25, 0.19, 0.09)


static func apply_app_background(control: Control) -> void:
	if control == null:
		return
	control.add_theme_stylebox_override("panel", panel_style(COLOR_BG, Color(0.10, 0.12, 0.16), 0, 0))


static func apply_panel(panel: Control, variant: String = "normal") -> void:
	if panel == null:
		return
	var fill := COLOR_PANEL
	var border := COLOR_GOLD_SOFT
	var radius := 12
	var width := 1
	match variant:
		"dark":
			fill = COLOR_PANEL_DARK
			border = Color(0.20, 0.24, 0.32)
		"soft":
			fill = COLOR_PANEL_SOFT
			border = Color(0.26, 0.31, 0.40)
		"gold":
			fill = COLOR_PANEL
			border = COLOR_GOLD
			width = 2
		"slot":
			fill = Color(0.08, 0.095, 0.125, 0.88)
			border = Color(0.26, 0.30, 0.38)
			radius = 8
	panel.add_theme_stylebox_override("panel", panel_style(fill, border, width, radius))


static func apply_button(button: BaseButton, variant: String = "secondary") -> void:
	if button == null:
		return
	var base := COLOR_BUTTON
	var hover := COLOR_BUTTON_HOVER
	var pressed := COLOR_BUTTON_PRESSED
	var border := COLOR_BLUE
	if variant == "primary":
		base = COLOR_PRIMARY
		hover = COLOR_PRIMARY_HOVER
		pressed = COLOR_PRIMARY_PRESSED
		border = COLOR_GOLD
	elif variant == "danger":
		base = Color(0.30, 0.11, 0.11)
		hover = Color(0.42, 0.15, 0.15)
		pressed = Color(0.20, 0.07, 0.07)
		border = Color(0.78, 0.34, 0.30)
	button.add_theme_stylebox_override("normal", panel_style(base, border, 1, 8))
	button.add_theme_stylebox_override("hover", panel_style(hover, border.lightened(0.15), 1, 8))
	button.add_theme_stylebox_override("pressed", panel_style(pressed, border.darkened(0.10), 1, 8))
	button.add_theme_stylebox_override("disabled", panel_style(Color(0.10, 0.11, 0.13), Color(0.20, 0.21, 0.24), 1, 8))
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.72))
	button.add_theme_color_override("font_pressed_color", Color(0.94, 0.82, 0.50))
	button.add_theme_color_override("font_disabled_color", Color(0.44, 0.46, 0.50))


static func apply_title(label: Label, size: int = 24) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.62))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)


static func apply_label(label: Label, muted: bool = false) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED if muted else COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


static func apply_input(control: Control) -> void:
	if control == null:
		return
	var style := panel_style(Color(0.075, 0.085, 0.11), Color(0.30, 0.35, 0.45), 1, 6)
	for key in ["normal", "focus", "read_only"]:
		control.add_theme_stylebox_override(key, style)
	control.add_theme_color_override("font_color", COLOR_TEXT)
	control.add_theme_color_override("font_placeholder_color", COLOR_TEXT_MUTED)


static func apply_overlay(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.color = Color(0.0, 0.0, 0.0, 0.58)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP


static func apply_popup_frame(panel: Control, variant: String = "gold") -> void:
	apply_panel(panel, variant)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP


static func theme_tree(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Label:
			apply_label(child)
		elif child is Button:
			var variant := "danger" if child.text == "X" else "secondary"
			apply_button(child, variant)
		elif child is OptionButton or child is CheckBox:
			apply_button(child, "secondary")
		elif child is LineEdit or child is SpinBox or child is TextEdit:
			apply_input(child)
		elif child is Panel or child is PanelContainer:
			apply_panel(child, "soft")
		theme_tree(child)


static func make_popup_layer(parent: Node, layer_index: int = 100) -> Dictionary:
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = layer_index
	parent.add_child(popup_layer)
	var bg := ColorRect.new()
	apply_overlay(bg)
	popup_layer.add_child(bg)
	return {"layer": popup_layer, "bg": bg}


static func panel_style(fill: Color, border: Color, width: int = 1, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
