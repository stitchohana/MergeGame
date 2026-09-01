class_name AcupointActivatePopup extends BasePopup

const ITEM_WIDGET_SCENE: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
const DEFAULT_ACTION_TEXT: String = "激活"

@onready var title_label: Label = $PopupFrame/PopupPanel/Content/TaskOverview/TaskCopy/TitleLabel
@onready var rewards_box: HBoxContainer = $PopupFrame/PopupPanel/Content/RewardsBox
@onready var progress_label: Label = $PopupFrame/PopupPanel/Content/ProgressArea/ProgressMargin/ProgressVBox/ProgressHeader/ProgressLabel
@onready var progress_bar: ProgressBar = $PopupFrame/PopupPanel/Content/ProgressArea/ProgressMargin/ProgressVBox/ProgressRow/ProgressBar
@onready var action_btn: Button = $PopupFrame/PopupPanel/Content/OperationArea/ActionButton
@onready var action_text_label: Label = $PopupFrame/PopupPanel/Content/OperationArea/ActionButton/ActionContent/ActionTextLabel
@onready var action_cost_icon: TextureRect = $PopupFrame/PopupPanel/Content/OperationArea/ActionButton/ActionContent/ActionCostIcon
@onready var action_cost_label: Label = $PopupFrame/PopupPanel/Content/OperationArea/ActionButton/ActionContent/ActionCostLabel
@onready var close_btn: Button = $PopupFrame/CloseButton
@onready var gift_button: TextureButton = $PopupFrame/PopupPanel/Content/ProgressArea/ProgressMargin/ProgressVBox/ProgressRow/GiftFrame/GiftIcon

var _on_action: Callable = Callable()
var _action_text: String = DEFAULT_ACTION_TEXT
var _action_cost_text: String = ""


func _ready() -> void:
	CloudService.home_meridian_light_confirmed.connect(_on_success)
	CloudService.home_meridian_light_rejected.connect(_on_rejected_handler)
	if gift_button and not gift_button.pressed.is_connected(_on_gift_button_pressed):
		gift_button.pressed.connect(_on_gift_button_pressed)
	if not action_btn.pressed.is_connected(_on_action_btn):
		action_btn.pressed.connect(_on_action_btn)
	if not close_btn.pressed.is_connected(_on_close):
		close_btn.pressed.connect(_on_close)


func _exit_tree() -> void:
	_disconnect_signals()


func _on_success(_result: Dictionary) -> void:
	_disconnect_signals()
	UIManager.hide_popup(self)


func _disconnect_signals() -> void:
	if CloudService.home_meridian_light_confirmed.is_connected(_on_success):
		CloudService.home_meridian_light_confirmed.disconnect(_on_success)
	if CloudService.home_meridian_light_rejected.is_connected(_on_rejected_handler):
		CloudService.home_meridian_light_rejected.disconnect(_on_rejected_handler)


func _on_rejected_handler(reason: String) -> void:
	action_btn.disabled = false
	_set_action_visual(_action_text, true)
	if reason == "insufficient_qi":
		EventBus.show_toast.emit("灵气不足")
	elif reason == "breakthrough_needed":
		EventBus.show_toast.emit("请先突破境界")
	elif reason == "out_of_order":
		EventBus.show_toast.emit("请按顺序激活穴位")
	else:
		EventBus.show_toast.emit("激活失败")


func setup(title: String, cost: String, rewards: Dictionary, action_text: String, on_action: Callable) -> void:
	title_label.text = title
	_action_text = action_text if not action_text.is_empty() else DEFAULT_ACTION_TEXT
	_action_cost_text = _extract_cost_amount(cost)
	_set_action_visual(_action_text, true)
	action_btn.disabled = false
	_on_action = on_action
	_update_progress(cost)
	_clear_reward_cards()
	_populate_reward_cards(rewards)


func _update_progress(cost: String) -> void:
	progress_label.text = "0/0"
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	var progress_text: String = _extract_progress_text(cost)
	if progress_text.is_empty():
		return
	progress_label.text = progress_text
	var parts: PackedStringArray = progress_text.split("/")
	if parts.size() != 2:
		return
	var current: float = maxf(0.0, float(parts[0].strip_edges()))
	var total: float = maxf(1.0, float(parts[1].strip_edges()))
	progress_bar.max_value = total
	progress_bar.value = clampf(current, 0.0, total)


func _extract_progress_text(cost: String) -> String:
	var lines: PackedStringArray = cost.split("\n")
	for line in lines:
		for marker_text in PackedStringArray(["进度：", "进度:"]):
			var marker: int = line.find(marker_text)
			if marker < 0:
				continue
			var progress: String = line.substr(marker + marker_text.length()).strip_edges()
			if progress.contains("/"):
				return progress
	return ""


func _extract_cost_amount(cost: String) -> String:
	var marker_text: String = ""
	var marker: int = -1
	for candidate in PackedStringArray(["消耗灵气：", "消耗灵气:"]):
		marker = cost.find(candidate)
		if marker >= 0:
			marker_text = candidate
			break
	if marker < 0:
		var standalone_cost: String = cost.strip_edges()
		return standalone_cost if standalone_cost.is_valid_int() else ""
	var amount: String = cost.substr(marker + marker_text.length()).strip_edges()
	var separator_index: int = amount.find("　")
	if separator_index < 0:
		separator_index = amount.find(" ")
	if separator_index < 0:
		separator_index = amount.find("\n")
	if separator_index >= 0:
		amount = amount.substr(0, separator_index)
	return amount.strip_edges()


func _set_action_visual(label_text: String, show_cost: bool) -> void:
	action_text_label.text = label_text
	var has_cost: bool = show_cost and not _action_cost_text.is_empty()
	action_cost_icon.visible = has_cost
	action_cost_label.visible = has_cost
	action_cost_label.text = _action_cost_text if has_cost else ""
	action_btn.tooltip_text = label_text + (" · 消耗灵气 " + _action_cost_text if has_cost else "")


func _clear_reward_cards() -> void:
	for child in rewards_box.get_children():
		rewards_box.remove_child(child)
		child.queue_free()


func _populate_reward_cards(rewards: Dictionary) -> void:
	var tokens_variant: Variant = rewards.get("tokens", [])
	var token_rewards: Array = []
	if tokens_variant is Array:
		token_rewards = tokens_variant as Array
	var items_variant: Variant = rewards.get("items", [])
	var item_rewards: Array = []
	if items_variant is Array:
		item_rewards = items_variant as Array

	for token_value in token_rewards:
		if not token_value is Dictionary:
			continue
		var token: Dictionary = token_value as Dictionary
		var token_id: int = int(token.get("token", 0))
		var amount: int = int(token.get("amount", 0))
		var token_data: Dictionary = ConfigDatabase.get_token_data(token_id)
		if not token_data.is_empty():
			_append_reward_widget(amount, token_data)

	for item_value in item_rewards:
		if not item_value is Dictionary:
			continue
		var reward: Dictionary = item_value as Dictionary
		var item_id: int = int(reward.get("id", 0))
		var count: int = int(reward.get("count", 0))
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		if not item_data.is_empty():
			_append_reward_widget(count, item_data)


func _append_reward_widget(amount: int, reward_data: Dictionary) -> void:
	var widget: ItemWidget = ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	if widget == null:
		return
	widget.custom_minimum_size = Vector2(112, 112)
	widget.size = Vector2(112, 112)
	widget.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	widget.setup(reward_data)
	widget.set_clickable(false)

	var reward_name: String = String(reward_data.get("name", "奖励"))
	widget.tooltip_text = "%s ×%d" % [reward_name, amount]
	var count_label: Label = Label.new()
	count_label.text = "×%d" % amount
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.offset_left = -62.0
	count_label.offset_top = -34.0
	count_label.offset_right = -4.0
	count_label.offset_bottom = -4.0
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	count_label.add_theme_color_override("font_outline_color", Color(0.32, 0.2, 0.08, 1))
	count_label.add_theme_constant_override("outline_size", 3)
	count_label.add_theme_font_size_override("font_size", 21)
	widget.add_child(count_label)
	rewards_box.add_child(widget)


func _on_action_btn() -> void:
	action_btn.disabled = true
	_set_action_visual("处理中…", false)
	if _on_action.is_valid():
		_on_action.call()


func _on_close() -> void:
	_disconnect_signals()
	UIManager.hide_popup(self)


func _on_gift_button_pressed() -> void:
	var popup := preload("res://scenes/ui/home/BreakthroughRewardPreviewPopup.tscn").instantiate() as BreakthroughRewardPreviewPopup
	UIManager.show_popup(popup)
	popup.setup_for_current_level()
