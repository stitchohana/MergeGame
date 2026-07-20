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
	var fallback := Panel.new()
	fallback.custom_minimum_size = Vector2(14, 14)
	fallback.size = Vector2(14, 14)
	var fallback_style := StyleBoxFlat.new()
	fallback_style.bg_color = Color(0.38, 0.62, 0.38, 1)
	fallback_style.border_color = Color(0.2, 0.38, 0.22, 1)
	fallback_style.set_border_width_all(1)
	fallback_style.set_corner_radius_all(7)
	fallback.add_theme_stylebox_override("panel", fallback_style)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)
	move_child(fallback, 0)

	var name: String = item_data.get("name", "#" + str(item_id))
	tooltip_text = "%s x%d" % [name, amount]
