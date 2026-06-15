extends Panel

# ============================================
# Discard zone — relay drop to Main
# ============================================

signal card_discarded(card_data)


func _can_drop_data(_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("card_data"):
		return false
	return true


func _drop_data(_position: Vector2, data):
	var card_data: CardData = data["card_data"] as CardData
	emit_signal("card_discarded", card_data)
	# UI cleanup handled by Main after confirming the discard
