class_name BreakthroughRewardPreviewPopup extends BasePopup

const ITEM_WIDGET_SCENE: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
const REWARD_ITEM_SIZE: int = 112

@onready var title_label: Label = $Panel/Content/VBox/TitleLabel
@onready var stage_label: Label = $Panel/Content/VBox/StageLabel
@onready var rewards_container: HBoxContainer = $Panel/Content/VBox/RewardsPanel/RewardsScroll/RewardsContainer
@onready var empty_label: Label = $Panel/Content/VBox/RewardsPanel/EmptyLabel
@onready var close_btn: TextureButton = $Panel/CloseButton

var _pending_stage_index: int = -1


func _ready() -> void:
	if close_btn and not close_btn.pressed.is_connected(_on_close):
		close_btn.pressed.connect(_on_close)
	if _pending_stage_index >= 0:
		var pending_stage_index: int = _pending_stage_index
		_pending_stage_index = -1
		setup_for_stage_index(pending_stage_index)


func setup_for_current_level() -> void:
	setup_for_current_stage()


func setup_for_level(level: int) -> void:
	# Backward-compatible entry point for callers that only know cultivation
	# level. The gift now previews the corresponding home-meridian cycle reward.
	var stages: Array = _get_home_meridian_defs()
	setup_for_stage_index(_get_home_stage_index_for_level(level, stages.size()))


func setup_for_current_stage() -> void:
	var stages: Array = _get_home_meridian_defs()
	setup_for_stage_index(_get_current_home_stage_index(stages))


func setup_for_stage_index(stage_index: int) -> void:
	if not is_node_ready():
		_pending_stage_index = stage_index
		return

	var stages: Array = _get_home_meridian_defs()
	var display_index: int = clampi(stage_index, -1, stages.size() - 1)
	var stage_data: Dictionary = {}
	if display_index >= 0 and display_index < stages.size() and stages[display_index] is Dictionary:
		stage_data = stages[display_index] as Dictionary
	title_label.text = "周天奖励预览"
	var stage_name: String = String(stage_data.get("name", "当前周天"))
	stage_label.text = "当前周天：%s" % stage_name
	_populate_rewards(_get_circulation_reward(stage_data))


func _get_home_meridian_defs() -> Array:
	if not GameState.home_meridian_defs.is_empty():
		return GameState.home_meridian_defs.duplicate(true)
	return ConfigDatabase.get_home_meridian_stages()


func _get_current_home_stage_index(stages: Array) -> int:
	if stages.is_empty():
		return -1
	var max_unlocked_index: int = _max_unlocked_home_stage_index()
	for stage_index: int in range(stages.size()):
		var progress: Dictionary = _get_home_stage_progress(stage_index)
		if progress.is_empty() or not bool(progress.get("circulation_completed", false)):
			return clampi(stage_index, 0, mini(max_unlocked_index, stages.size() - 1))
	return clampi(stages.size() - 1, 0, mini(max_unlocked_index, stages.size() - 1))


func _get_home_stage_progress(stage_index: int) -> Dictionary:
	for progress_variant: Variant in GameState.home_meridian_progress:
		if not progress_variant is Dictionary:
			continue
		var progress: Dictionary = progress_variant as Dictionary
		if int(progress.get("stage", -1)) == stage_index:
			return progress
	return {}


func _get_home_stage_index_for_level(level: int, stage_count: int) -> int:
	if stage_count <= 0:
		return -1
	var max_index: int = ConfigDatabase.get_max_unlocked_home_meridian_stage_index(level)
	return clampi(max_index, 0, stage_count - 1)


func _max_unlocked_home_stage_index() -> int:
	return ConfigDatabase.get_max_unlocked_home_meridian_stage_index(CultivationService.current_level)


func _get_circulation_reward(stage_data: Dictionary) -> Dictionary:
	var reward_variant: Variant = stage_data.get("circulation_reward", {})
	if reward_variant is Dictionary:
		return (reward_variant as Dictionary).duplicate(true)
	if reward_variant is int:
		return ConfigDatabase.get_reward_data(int(reward_variant))
	return {}


func _populate_rewards(rewards: Dictionary) -> void:
	_clear_rewards()
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
		empty_label.text = "本周天暂无额外奖励"


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
