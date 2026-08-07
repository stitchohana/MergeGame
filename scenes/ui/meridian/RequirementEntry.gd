class_name RequirementEntry extends Control

signal complete_pressed()
signal item_pressed(item_id: int)

var _data: Dictionary = {}
var _items_setup: Array = []
var _index_setup: int = -1
var _completed_setup: bool = false
var _rewards_setup: Dictionary = {}
var _ready_done: bool = false
var _available: bool = false
var _item_widget_scene: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
var _reward_slot_scene: PackedScene = preload("res://scenes/ui/meridian/RewardSlot.tscn")


func _ready() -> void:
	_ready_done = true
	if not _items_setup.is_empty():
		_do_setup(_items_setup, _index_setup, _completed_setup, _rewards_setup)


func setup(items: Array, index: int, completed: bool, rewards: Dictionary = {}) -> void:
	_items_setup = items
	_index_setup = index
	_completed_setup = completed
	_rewards_setup = rewards
	if _ready_done:
		_do_setup(items, index, completed, rewards)


func _do_setup(items: Array, index: int, completed: bool, rewards: Dictionary) -> void:
	_data = {"items": items, "index": index, "completed": completed}

	var items_container: HBoxContainer = $ItemsContainer
	var reward_box: HBoxContainer = $RewardRow/RewardBox
	var complete_btn: Button = $CompleteButton

	for child in items_container.get_children():
		items_container.remove_child(child)
		child.queue_free()
	for child in reward_box.get_children():
		child.queue_free()

	for item_variant in items:
		var item: Dictionary = item_variant
		var item_id: int = int(item.get("item_id", 0))
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		var widget: ItemWidget = _item_widget_scene.instantiate() as ItemWidget
		widget.custom_minimum_size = Vector2(68, 84)
		widget.size = Vector2(68, 84)
		widget.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_item_widget(widget)
		if not item_data.is_empty():
			widget.setup(item_data)
		else:
			widget.setup({"name": item.get("name", "?")})
		widget.set_clickable(true)
		widget.pressed.connect(_on_item_pressed.bind(item_id))
		var click_button: Button = widget.get_node_or_null("ClickButton") as Button
		if click_button:
			click_button.tooltip_text = "查看获取方式"
		items_container.add_child(widget)

	if not rewards.is_empty():
		if rewards.has("tokens"):
			for token_variant in rewards.tokens:
				var token: Dictionary = token_variant
				var token_type: int = int(token.get("token", 0))
				var amount: int = int(token.get("amount", 0))
				var slot: RewardSlot = _reward_slot_scene.instantiate() as RewardSlot
				reward_box.add_child(slot)
				slot.setup(token_type, amount)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if rewards.has("items"):
			for reward_variant in rewards.items:
				var reward: Dictionary = reward_variant
				var item_id: int = int(reward.get("id", 0))
				var count: int = int(reward.get("count", 0))
				var slot: RewardSlot = _reward_slot_scene.instantiate() as RewardSlot
				reward_box.add_child(slot)
				slot.setup(item_id, count)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if completed:
		complete_btn.text = ""
		complete_btn.disabled = true
		complete_btn.visible = true
	else:
		complete_btn.text = ""
		complete_btn.disabled = false
		if complete_btn.pressed.is_connected(_on_btn_pressed):
			complete_btn.pressed.disconnect(_on_btn_pressed)
		complete_btn.pressed.connect(_on_btn_pressed)
		complete_btn.visible = false


func set_available(available: bool) -> bool:
	var changed: bool = _available != available
	_available = available
	if not bool(_data.get("completed", false)):
		var btn: Button = $CompleteButton
		btn.visible = available
	return changed


func is_available() -> bool:
	return _available


func get_display_index() -> int:
	return int(_data.get("index", -1))


func refresh_item_selection(present_item_ids: Dictionary) -> void:
	var items_container: HBoxContainer = $ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			var widget: ItemWidget = child as ItemWidget
			var item_id: int = int(widget.item_data.get("id", 0))
			widget.set_selected(item_id > 0 and present_item_ids.has(item_id))

func get_item_widget_center(item_id: int) -> Vector2:
	for child in $ItemsContainer.get_children():
		if child is ItemWidget and int((child as ItemWidget).item_data.get("id", 0)) == item_id:
			return (child as Control).get_global_rect().get_center()
	return get_global_rect().get_center()

func play_complete_animation() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.22)


func _on_btn_pressed() -> void:
	complete_pressed.emit()


func _on_item_pressed(item_id: int) -> void:
	if item_id > 0:
		item_pressed.emit(item_id)


func mark_completed() -> void:
	var btn: Button = $CompleteButton
	btn.text = ""
	btn.disabled = true
	btn.visible = true
	var items_container: HBoxContainer = $ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			child.modulate = Color(0.5, 0.8, 0.5, 1)


func _style_item_widget(widget: ItemWidget) -> void:
	var icon_rect: TextureRect = widget.get_node_or_null("IconRect") as TextureRect
	if icon_rect:
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		icon_rect.offset_left = -28.0
		icon_rect.offset_top = -28.0
		icon_rect.offset_right = 28.0
		icon_rect.offset_bottom = 28.0
