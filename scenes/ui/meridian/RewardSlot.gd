class_name RewardSlot extends HBoxContainer

@onready var icon_rect: TextureRect = $IconRect
@onready var count_label: Label = $CountLabel


func setup(item_id: int, amount: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		item_data = ConfigDatabase.get_token_data(item_id)
	if item_data.is_empty():
		push_warning("[RewardSlot] Unknown item/token id: ", item_id)
		count_label.text = str(amount)
		return
	count_label.text = str(amount)

	var icon_path: String = item_data.get("icon", "")
	if not icon_path.is_empty():
		var tex := load(icon_path) as Texture2D
		if tex:
			icon_rect.texture = tex
			return

	# Fallback: colored rect based on item name
	var fallback := ColorRect.new()
	fallback.custom_minimum_size = Vector2(18, 18)
	fallback.size = Vector2(18, 18)
	fallback.color = Color.from_hsv(float(item_id % 13) / 13.0, 0.5, 0.6)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)
	move_child(fallback, 0)

	var name: String = item_data.get("name", "#" + str(item_id))
	tooltip_text = "%s x%d" % [name, amount]
