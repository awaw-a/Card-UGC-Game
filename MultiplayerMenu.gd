extends Control

const BASE_VIEWPORT_SIZE := Vector2(1152, 648)

@onready var server_btn = $CenterContainer/VBoxContainer/ServerButton
@onready var direct_btn = $CenterContainer/VBoxContainer/DirectButton
@onready var back_btn = $CenterContainer/VBoxContainer/BackButton
@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel


func _apply_texts() -> void:
	title_label.text = Locale.t("mp.title")
	server_btn.text = Locale.t("mp.connect_server")
	direct_btn.text = Locale.t("mp.direct")
	back_btn.text = Locale.t("common.back")


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var btn_size := Vector2(240, 50) * s
	for btn in [server_btn, direct_btn, back_btn]:
		if btn:
			btn.custom_minimum_size = btn_size
			btn.add_theme_font_size_override("font_size", max(12, int(18 * s)))
	if title_label:
		title_label.add_theme_font_size_override("font_size", max(14, int(24 * s)))
	var vbox := $CenterContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", int(16 * s))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _ready():
	server_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://Lobby.tscn"))
	direct_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://DirectLobby.tscn"))
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://MainMenu.tscn"))
	_apply_texts()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
