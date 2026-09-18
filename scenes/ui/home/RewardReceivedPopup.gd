class_name RewardReceivedPopup extends BasePopup

const ITEM_WIDGET_SCENE: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
const REWARD_ITEM_SIZE: int = 92

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var message_label: Label = $Panel/VBox/MessageLabel
@onready var rewards_container: HBoxContainer = $Panel/VBox/RewardsPanel/RewardsScroll/RewardsContainer
@onready var empty_label: Label = $Panel/VBox/RewardsPanel/EmptyLabel
@onready var confirm_btn: Button = $Panel/VBox/ConfirmButton

var _pending_title: String = "收到奖励"
var _pending_message: String = ""
var _pending_rewards: Dictionary = {}
var _has_pending_setup: bool = false


func _ready() -> void:
	if not confirm_btn.pressed.is_connected(_on_confirm):
		confirm_btn.pressed.connect(_on_confirm)
	if _has_pending_setup:
		_apply_setup()


func setup(title: String, message: String, rewards: Dictionary) -> void:
	_pending_title = title
	_pending_message = message
	_pending_rewards = rewards.duplicate(true)
	_has_pending_setup = true
	if is_node_ready():
		_apply_setup()


func _apply_setup() -> void:
	_has_pending_setup = false
	title_label.text = _pending_title
	message_label.text = _pending_message
	_populate_rewards(_pending_rewards)


func _populate_rewards(reward_data: Dictionary) -> void:
	_clear_rewards()
	var reward_count: int = 0

	var tokens_variant: Variant = reward_data.get("tokens", [])
	if tokens_variant is Array:
		var token_rewards: Array = tokens_variant as Array
		for token_variant: Variant in token_rewards:
			if not token_variant is Dictionary:
				continue
			var token: Dictionary = token_variant as Dictionary
			var token_id: int = int(token.get("token", 0))
			var amount: int = int(token.get("amount", 0))
			var token_data: Dictionary = ConfigDatabase.get_token_data(token_id)
			if token_data.is_empty() or amount <= 0:
				continue
			if _append_reward_card(token_data, amount, reward_count):
				reward_count += 1

	var items_variant: Variant = reward_data.get("items", [])
	if items_variant is Array:
		var item_rewards: Array = items_variant as Array
		for item_variant: Variant in item_rewards:
			if not item_variant is Dictionary:
				continue
			var item_reward: Dictionary = item_variant as Dictionary
			var item_id: int = int(item_reward.get("id", 0))
			var amount: int = int(item_reward.get("count", 0))
			var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
			if item_data.is_empty() or amount <= 0:
				continue
			if _append_reward_card(item_data, amount, reward_count):
				reward_count += 1

	empty_label.visible = reward_count == 0
	if reward_count == 0:
		empty_label.text = "本次暂无可展示的奖励"


func _clear_rewards() -> void:
	for child: Node in rewards_container.get_children():
		rewards_container.remove_child(child)
		child.queue_free()
	empty_label.visible = false


func _append_reward_card(reward_data: Dictionary, amount: int, index: int) -> bool:
	var card := VBoxContainer.new()
	card.name = "RewardCard%d" % index
	card.custom_minimum_size = Vector2(128, 142)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 4)

	var widget: ItemWidget = ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	if widget == null:
		return false
	widget.custom_minimum_size = Vector2(REWARD_ITEM_SIZE, REWARD_ITEM_SIZE)
	widget.size = Vector2(REWARD_ITEM_SIZE, REWARD_ITEM_SIZE)
	widget.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	widget.setup(reward_data)
	widget.set_clickable(false)
	var reward_name: String = String(reward_data.get("name", "奖励"))
	widget.tooltip_text = "%s ×%d" % [reward_name, amount]
	card.add_child(widget)

	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(128, 32)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_label.text = "%s ×%d" % [reward_name, amount]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override("font_color", Color(0.30, 0.19, 0.10, 1.0))
	name_label.add_theme_font_size_override("font_size", 16)
	card.add_child(name_label)
	rewards_container.add_child(card)
	return true


func _on_confirm() -> void:
	UIManager.hide_popup(self)
