class_name AcupointActivatePopup extends BasePopup

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var cost_label: Label = $Panel/VBox/CostLabel
@onready var rewards_box: HBoxContainer = $Panel/VBox/RewardsBox
@onready var action_btn: Button = $Panel/VBox/BtnBox/ActionButton
@onready var cancel_btn: Button = $Panel/VBox/BtnBox/CancelButton

var _on_action: Callable = Callable()
var _reward_slot_scene := preload("res://scenes/ui/meridian/RewardSlot.tscn")


func _ready() -> void:
	CloudService.home_meridian_light_confirmed.connect(_on_success)
	CloudService.home_meridian_light_rejected.connect(_on_rejected_handler)


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
	action_btn.text = "激活"
	if reason == "insufficient_qi":
		EventBus.show_toast.emit("灵气不足")
	elif reason == "breakthrough_needed":
		EventBus.show_toast.emit("请先突破境界")
	elif reason == "out_of_order":
		EventBus.show_toast.emit("请按顺序激活穴位")
	else:
		EventBus.show_toast.emit("激活失败")


func _on_cancel() -> void:
	_disconnect_signals()
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
					var tw := _reward_slot_scene.instantiate() as RewardSlot
					rewards_box.add_child(tw)
					tw.setup(token_type, amount)
		if rewards.has("items"):
			for reward_item in rewards.items:
				var item_id: int = int(reward_item.get("id", 0))
				var count: int = int(reward_item.get("count", 0))
				var item_data := ConfigDatabase.get_item_data(item_id)
				if not item_data.is_empty():
					var iw := _reward_slot_scene.instantiate() as RewardSlot
					rewards_box.add_child(iw)
					iw.setup(item_id, count)

	if not action_btn.pressed.is_connected(_on_action_btn):
		action_btn.pressed.connect(_on_action_btn)
	if not cancel_btn.pressed.is_connected(_on_cancel):
		cancel_btn.pressed.connect(_on_cancel)


func _on_action_btn() -> void:
	action_btn.disabled = true
	action_btn.text = "..."
	if _on_action.is_valid():
		_on_action.call()


func _on_close() -> void:
	_disconnect_signals()
	UIManager.hide_popup(self)
