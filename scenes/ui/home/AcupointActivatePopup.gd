class_name AcupointActivatePopup extends BasePopup

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var cost_label: Label = $Panel/VBox/CostLabel
@onready var rewards_box: HBoxContainer = $Panel/VBox/RewardsBox
@onready var action_btn: Button = $Panel/VBox/BtnBox/ActionButton
@onready var cancel_btn: Button = $Panel/VBox/BtnBox/CancelButton

var _on_action: Callable = Callable()
var _on_rejected: Callable = Callable()
var _item_widget_scene := preload("res://scenes/ui/common/ItemWidget.tscn")


func _ready() -> void:
	CloudService.home_meridian_light_confirmed.connect(_on_success)
	CloudService.home_meridian_light_rejected.connect(_on_rejected_handler)


func _on_success(_result: Dictionary) -> void:
	UIManager.hide_popup(self)


func _on_rejected_handler(reason: String) -> void:
	action_btn.disabled = false
	action_btn.text = "激活"
	if reason == "insufficient_qi":
		EventBus.show_toast.emit("灵气不足")
	elif reason == "breakthrough_needed":
		EventBus.show_toast.emit("请先突破境界")


func _on_cancel() -> void:
	if CloudService.home_meridian_light_confirmed.is_connected(_on_success):
		CloudService.home_meridian_light_confirmed.disconnect(_on_success)
	if CloudService.home_meridian_light_rejected.is_connected(_on_rejected_handler):
		CloudService.home_meridian_light_rejected.disconnect(_on_rejected_handler)
	UIManager.hide_popup(self)


func setup(title: String, cost: String, rewards: Dictionary, action_text: String, on_action: Callable) -> void:
	title_label.text = title
	cost_label.text = cost
	action_btn.text = action_text
	_on_action = on_action

	for child in rewards_box.get_children():
		child.queue_free()
	if not rewards.is_empty():
		if rewards.has("tokens"):
			for t in rewards.tokens:
				var token_type: int = int(t.get("token", 0))
				var amount: int = int(t.get("amount", 0))
				var token_data := ConfigDatabase.get_token_data(token_type)
				if not token_data.is_empty():
					var tw := _item_widget_scene.instantiate() as ItemWidget
					tw.setup(token_data, Vector2i(-1, -1), 24)
					tw.custom_minimum_size = Vector2(24, 24)
					tw.size = Vector2(24, 24)
					tw.tooltip_text = "%s x%d" % [token_data.get("name", "?"), amount]
					rewards_box.add_child(tw)
		if rewards.has("items"):
			for ri in rewards.items:
				var item_id: int = int(ri.get("id", 0))
				var count: int = int(ri.get("count", 0))
				var item_data := ConfigDatabase.get_item_data(item_id)
				if not item_data.is_empty():
					var iw := _item_widget_scene.instantiate() as ItemWidget
					iw.setup(item_data, Vector2i(-1, -1), 24)
					iw.custom_minimum_size = Vector2(24, 24)
					iw.size = Vector2(24, 24)
					iw.tooltip_text = "%s x%d" % [item_data.get("name", "?"), count]
					rewards_box.add_child(iw)

	action_btn.pressed.connect(_on_action_btn)
	cancel_btn.pressed.connect(_on_cancel)


func _on_action_btn() -> void:
	action_btn.disabled = true
	action_btn.text = "..."
	if _on_action.is_valid():
		_on_action.call()


func _on_close() -> void:
	UIManager.hide_popup(self)
