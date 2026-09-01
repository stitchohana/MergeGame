class_name BreakthroughRewardPreviewPopup extends BasePopup

const ITEM_WIDGET_SCENE: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
const REWARD_ITEM_SIZE: int = 112

@onready var title_label: Label = $Panel/Content/VBox/TitleLabel
@onready var stage_label: Label = $Panel/Content/VBox/StageLabel
@onready var rewards_container: HBoxContainer = $Panel/Content/VBox/RewardsPanel/RewardsContainer
@onready var empty_label: Label = $Panel/Content/VBox/RewardsPanel/EmptyLabel
@onready var close_btn: TextureButton = $Panel/CloseButton

var _pending_level: int = -1


func _ready() -> void:
	if close_btn and not close_btn.pressed.is_connected(_on_close):
		close_btn.pressed.connect(_on_close)
	if _pending_level > 0:
		var pending_level: int = _pending_level
		_pending_level = -1
		setup_for_level(pending_level)


func setup_for_current_level() -> void:
	setup_for_level(CultivationService.current_level)


func setup_for_level(level: int) -> void:
	if not is_node_ready():
		_pending_level = level
		return

	var stage_count: int = ConfigDatabase.get_stage_count()
	var display_level: int = clampi(level, 1, maxi(stage_count, 1))
	var current_stage_name: String = ConfigDatabase.get_stage_name(display_level)
	var next_stage_name: String = ConfigDatabase.get_stage_name(display_level + 1)
	if display_level >= stage_count or next_stage_name == "未知":
		next_stage_name = "最高境界"
	title_label.text = "突破奖励预览"
	stage_label.text = "%s  →  %s" % [current_stage_name, next_stage_name]
	_populate_rewards(ConfigDatabase.get_stage_breakthrough_reward(display_level))


func _populate_rewards(reward_id: int) -> void:
	_clear_rewards()
	var rewards: Dictionary = ConfigDatabase.get_reward_data(reward_id)
	var reward_count: int = 0

	var tokens_variant: Variant = rewards.get("tokens", [])
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
			_append_reward_card(token_data, amount, reward_count)
			reward_count += 1

	var items_variant: Variant = rewards.get("items", [])
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
			_append_reward_card(item_data, amount, reward_count)
			reward_count += 1

	empty_label.visible = reward_count == 0
	if reward_count == 0:
		empty_label.text = "本次突破暂无额外礼包奖励"


func _clear_rewards() -> void:
	for child: Node in rewards_container.get_children():
		rewards_container.remove_child(child)
		child.queue_free()
	empty_label.visible = false


func _append_reward_card(reward_data: Dictionary, amount: int, index: int) -> void:
	var card := VBoxContainer.new()
	card.name = "RewardCard%d" % index
	card.custom_minimum_size = Vector2(136, 166)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 6)

	var widget: ItemWidget = ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	if widget == null:
		return
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
	name_label.custom_minimum_size = Vector2(136, 34)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_label.text = "%s ×%d" % [reward_name, amount]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override("font_color", Color(0.30, 0.19, 0.10, 1.0))
	name_label.add_theme_font_size_override("font_size", 17)
	card.add_child(name_label)
	rewards_container.add_child(card)


func _on_close() -> void:
	UIManager.hide_popup(self)
