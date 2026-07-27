class_name RewardSlot extends HBoxContainer

const FALLBACK_ICON: Texture2D = preload("res://assets/home/ui/reward_fallback.svg")

@onready var icon_rect: TextureRect = $IconRect
@onready var count_label: Label = $CountLabel


func setup(item_id: int, amount: int) -> void:
	icon_rect.texture = FALLBACK_ICON
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		item_data = ConfigDatabase.get_token_data(item_id)
	if item_data.is_empty():
		push_warning("[RewardSlot] Unknown item/token id: ", item_id)
		count_label.text = str(amount)
		tooltip_text = "Reward x%d" % amount
		return
	count_label.text = str(amount)
	var name: String = item_data.get("name", "#" + str(item_id))
	tooltip_text = "%s x%d" % [name, amount]

	var icon_path: String = item_data.get("icon", "")
	if not icon_path.is_empty():
		var tex := load(icon_path) as Texture2D
		if tex:
			icon_rect.texture = tex
