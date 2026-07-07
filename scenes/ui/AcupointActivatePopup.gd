class_name AcupointActivatePopup extends BasePopup

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var cost_label: Label = $Panel/VBox/CostLabel
@onready var rewards_box: HBoxContainer = $Panel/VBox/RewardsBox
@onready var activate_btn: Button = $Panel/VBox/ActivateButton
@onready var close_btn: Button = $Panel/VBox/CloseButton

var _stage_idx: int = -1
var _acupoint_idx: int = -1
var _item_widget_scene := preload("res://scenes/ui/ItemWidget.tscn")


func setup(stage_idx: int, acupoint_idx: int, def: Dictionary, is_last: bool = false) -> void:
	_stage_idx = stage_idx
	_acupoint_idx = acupoint_idx

	var qi_cost: int = def.get("qi_cost", 0)
	title_label.text = def.get("name", "穴位") + " 第%d穴" % (acupoint_idx + 1)
	cost_label.text = "消耗灵气：%d" % qi_cost

	for child in rewards_box.get_children():
		child.queue_free()

	var acupoint_rewards: Variant = def.get("acupoint_rewards", {})
	_add_reward_preview(acupoint_rewards)

	if is_last:
		var circulation_rewards: Variant = def.get("circulation_rewards", {})
		if circulation_rewards is Dictionary and not circulation_rewards.is_empty():
			var sep := Label.new()
			sep.text = "周天奖励："
			sep.add_theme_font_size_override("font_size", 13)
			sep.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
			rewards_box.add_child(sep)
			_add_reward_preview(circulation_rewards)

	activate_btn.pressed.connect(_on_activate)
	close_btn.pressed.connect(_on_close)


func _add_reward_preview(rewards_config) -> void:
	if rewards_config == null:
		return
	var config: Dictionary = rewards_config if rewards_config is Dictionary else {}
	if config.is_empty():
		return

	if config.has("tokens"):
		for t in config.tokens:
			var token_type: int = t.get("token", 0)
			var amount: int = t.get("amount", 0)
			var token_data: Dictionary = ConfigDatabase.get_token_data(token_type)
			if not token_data.is_empty():
				var tw := _item_widget_scene.instantiate() as ItemWidget
				tw.setup(token_data, Vector2i(-1, -1), 24)
				tw.custom_minimum_size = Vector2(24, 24)
				tw.size = Vector2(24, 24)
				tw.tooltip_text = "%s x%d" % [token_data.get("name", "?"), amount]
				rewards_box.add_child(tw)

	if config.has("items"):
		for ri in config.items:
			var item_id: int = ri.get("id", 0)
			var count: int = ri.get("count", 0)
			var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
			if not item_data.is_empty():
				var iw := _item_widget_scene.instantiate() as ItemWidget
				iw.setup(item_data, Vector2i(-1, -1), 24)
				iw.custom_minimum_size = Vector2(24, 24)
				iw.size = Vector2(24, 24)
				iw.tooltip_text = "%s x%d" % [item_data.get("name", "?"), count]
				rewards_box.add_child(iw)


func _ready() -> void:
	CloudService.home_meridian_light_confirmed.connect(_on_light_done)
	CloudService.home_meridian_light_rejected.connect(_on_light_fail)


func _on_activate() -> void:
	if _stage_idx < 0:
		return
	activate_btn.disabled = true
	activate_btn.text = "..."
	CloudService.submit_light_home_acupoint(_stage_idx, _acupoint_idx)


func _on_light_done(_result: Dictionary) -> void:
	UIManager.hide_popup(self)


func _on_light_fail(_reason: String) -> void:
	activate_btn.disabled = false
	activate_btn.text = "激活"
	EventBus.show_toast.emit("灵气不足或已点亮")


func _on_close() -> void:
	if CloudService.home_meridian_light_confirmed.is_connected(_on_light_done):
		CloudService.home_meridian_light_confirmed.disconnect(_on_light_done)
	if CloudService.home_meridian_light_rejected.is_connected(_on_light_fail):
		CloudService.home_meridian_light_rejected.disconnect(_on_light_fail)
	UIManager.hide_popup(self)
