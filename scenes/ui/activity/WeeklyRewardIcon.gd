class_name WeeklyRewardIcon extends Control

@onready var icon_rect: TextureRect = $Icon
@onready var count_label: Label = $CountBadge/CountLabel


func setup(item_id: int, amount: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		item_data = ConfigDatabase.get_token_data(item_id)
	var item_name: String = item_data.get("name", "奖励 #%d" % item_id)
	tooltip_text = "%s ×%d" % [item_name, amount]
	count_label.text = _format_amount(amount)
	var icon_path: String = item_data.get("icon", "")
	if not icon_path.is_empty():
		icon_rect.texture = load(icon_path) as Texture2D


func _format_amount(amount: int) -> String:
	if amount >= 10000:
		return "%.1f万" % (float(amount) / 10000.0)
	if amount >= 1000:
		return "%.1fk" % (float(amount) / 1000.0)
	return str(amount)
