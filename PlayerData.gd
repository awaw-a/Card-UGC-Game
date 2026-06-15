extends Node

# ============================================
# Player data autoload — local save & draft management
# ============================================

const SAVE_FILE_NAME := "card_library.json"
const NET_ARTS_DIR := "user://net_arts"
const MAX_ART_BYTES := 2 * 1024 * 1024  # 2 MB cap per card art sent over the network

var card_library: Array = []
var save_path: String = ""
var editing_index: int = -1
var card_draft: Dictionary = {}
var editing_skill_index: int = 0
var card_editor_return_scene: String = "res://MainMenu.tscn"
var return_to_waiting_room: bool = false
var battle_deck: Array = []
var opponent_battle_deck: Array = []


func _ready():
	save_path = "user://" + SAVE_FILE_NAME
	print("Save path: %s" % ProjectSettings.globalize_path(save_path))
	load_library()
	clear_net_arts()


# ============================================
# Serialization
# ============================================

static func serialize_card(card: CardData) -> Dictionary:
	var skills_data: Array = []
	for skill in card.skills:
		skills_data.append(skill.duplicate(true))

	return {
		"name": card.card_name,
		"cost": card.cost,
		"max_hp": card.max_hp,
		"hp": card.hp,
		"atk": card.atk,
		"base_cost": card.base_cost,
		"base_max_hp": card.base_max_hp,
		"base_atk": card.base_atk,
		"gender": card.gender,
		"art_path": card.art_path,
		"skills": skills_data,
		"has_acted": card.has_acted,
		"has_attacked": card.has_attacked,
		"summoned_this_turn": card.summoned_this_turn,
		"skills_used": card.skills_used.duplicate(),
		"charmed_slot": card.charmed_slot,
		"original_cost": card.original_cost,
		"temp_hp": card.temp_hp,
		"status_effects": card.status_effects.duplicate(true),
	}


static func deserialize_card(data: Dictionary) -> CardData:
	var name: String = data.get("name", "Unknown")
	var cost: int = data.get("cost", 0)
	var max_hp: int = data.get("max_hp", 1)
	var atk: int = data.get("atk", 0)
	var skills: Array = data.get("skills", [])

	var card := CardData.new(name, cost, max_hp, atk, skills)
	card.base_cost = int(data.get("base_cost", cost))
	card.base_max_hp = int(data.get("base_max_hp", max_hp))
	card.base_atk = int(data.get("base_atk", atk))
	card.hp = int(data.get("hp", max_hp))
	card.art_path = data.get("art_path", "")
	card.gender = data.get("gender", "female")
	card.has_acted = bool(data.get("has_acted", false))
	card.has_attacked = bool(data.get("has_attacked", false))
	card.summoned_this_turn = bool(data.get("summoned_this_turn", false))
	card.skills_used = data.get("skills_used", []).duplicate()
	card.charmed_slot = int(data.get("charmed_slot", -1))
	card.original_cost = int(data.get("original_cost", -1))
	card.temp_hp = int(data.get("temp_hp", 0))
	card.status_effects = data.get("status_effects", []).duplicate(true)
	return card


func serialize_library() -> String:
	var cards_array: Array = []
	for card in card_library:
		cards_array.append(serialize_card(card))
	var root := {"cards": cards_array, "version": 1}
	return JSON.stringify(root, "\t")


func deserialize_library(json_string: String) -> Array:
	var result: Array = []
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		print("JSON parse error: %s" % json.get_error_message())
		return result
	var root: Dictionary = json.get_data()
	if root.is_empty():
		return result
	var cards_array: Array = root.get("cards", [])
	for card_data in cards_array:
		result.append(deserialize_card(card_data))
	return result


# ============================================
# File I/O
# ============================================

func save_library():
	DirAccess.make_dir_recursive_absolute("user://")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		print("Cannot write save: %s" % FileAccess.get_open_error())
		return
	var json_string := serialize_library()
	file.store_string(json_string)
	file.close()
	print("Library saved (%d cards)" % card_library.size())


func load_library():
	if not FileAccess.file_exists(save_path):
		print("No save file found (first launch?)")
		_seed_starter_library()
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var json_string := file.get_as_text()
	file.close()
	card_library = deserialize_library(json_string)
	print("Library loaded (%d cards)" % card_library.size())


# Populate a fresh collection with the default starter cards, then persist it.
func _seed_starter_library() -> void:
	card_library = CardDatabase.starter_library()
	print("Seeded starter library (%d cards)" % card_library.size())
	save_library()


# ============================================
# Network card art (P2P only) — opponent arts stored by content hash
# ============================================

# Wipe opponent arts at launch; they only matter for the current session.
func clear_net_arts() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(NET_ARTS_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		var dir := DirAccess.open(abs_dir)
		if dir:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir():
					dir.remove(fname)
				fname = dir.get_next()
			dir.list_dir_end()
	DirAccess.make_dir_recursive_absolute(abs_dir)


# Read a local art file's bytes for sending. Returns empty if missing or over cap.
func read_art_bytes(art_path: String) -> PackedByteArray:
	if art_path == "":
		return PackedByteArray()
	var abs_path: String = art_path
	if abs_path.begins_with("user://") or abs_path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(abs_path)
	if not FileAccess.file_exists(abs_path):
		return PackedByteArray()
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var length := file.get_length()
	if length > MAX_ART_BYTES:
		file.close()
		print("Art over size cap, skipping transfer: %s (%d bytes)" % [art_path, length])
		return PackedByteArray()
	var bytes := file.get_buffer(length)
	file.close()
	return bytes


# Save received opponent art bytes named by content hash. Returns the user:// path,
# or "" on failure. Identical art (same bytes) maps to the same file — natural dedup.
func save_net_art(bytes: PackedByteArray, ext: String) -> String:
	if bytes.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NET_ARTS_DIR))
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_MD5)
	hash_ctx.update(bytes)
	var digest := hash_ctx.finish()
	var hash_str := digest.hex_encode()
	var safe_ext: String = ext.strip_edges().to_lower()
	if safe_ext == "":
		safe_ext = "png"
	var rel_path: String = "%s/%s.%s" % [NET_ARTS_DIR, hash_str, safe_ext]
	var abs_path: String = ProjectSettings.globalize_path(rel_path)
	if FileAccess.file_exists(abs_path):
		return rel_path  # already have this exact art
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		print("Cannot write net art: %s" % FileAccess.get_open_error())
		return ""
	file.store_buffer(bytes)
	file.close()
	return rel_path


# ============================================
# Card library management
# ============================================

func add_card_to_library(card_data: CardData):
	card_library.append(card_data)
	save_library()


func update_card_in_library(index: int, card_data: CardData) -> bool:
	if index < 0 or index >= card_library.size():
		return false
	card_library[index] = card_data
	save_library()
	return true


func remove_card_from_library(index: int) -> bool:
	if index < 0 or index >= card_library.size():
		return false
	card_library.pop_at(index)
	save_library()
	return true


func get_library_count() -> int:
	return card_library.size()


func clear_library():
	card_library.clear()
	save_library()


# ============================================
# Draft management (cross-scene)
# ============================================

func init_card_draft():
	card_draft = {
		"name": "",
		"cost": 0,
		"hp": 1,
		"atk": 0,
	"gender": "female",
		"art_path": "",
		"skill1": {},
		"skill2": {}
	}


func load_card_to_draft(card: CardData):
	card_draft = {
		"name": card.card_name,
		"cost": card.cost,
		"hp": card.max_hp,
		"atk": card.atk,
		"gender": card.gender,
		"art_path": card.art_path,
		"skill1": {},
		"skill2": {}
	}
	if card.skills.size() >= 1:
		card_draft["skill1"] = card.skills[0].duplicate(true)
	if card.skills.size() >= 2:
		card_draft["skill2"] = card.skills[1].duplicate(true)


func build_card_from_draft() -> CardData:
	var skills: Array = []
	if not card_draft.get("skill1", {}).is_empty():
		skills.append(card_draft["skill1"].duplicate(true))
	if not card_draft.get("skill2", {}).is_empty():
		skills.append(card_draft["skill2"].duplicate(true))

	var card := CardData.new(
		card_draft.get("name", "Unnamed"),
		card_draft.get("cost", 0),
		card_draft.get("hp", 1),
		card_draft.get("atk", 0),
		skills
	)
	card.art_path = card_draft.get("art_path", "")
	card.gender = card_draft.get("gender", "female")
	return card
