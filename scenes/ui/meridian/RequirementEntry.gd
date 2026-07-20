class_name RequirementEntry extends Control

signal complete_pressed()
signal item_pressed(item_id: int)

var _data: Dictionary = {}
var _items_setup: Array = []
var _index_setup: int = -1
var _completed_setup: bool = false
var _rewards_setup: Dictionary = {}
var _ready_done: bool = false
var _item_widget_scene := preload("res://scenes/ui/common/ItemWidget.tscn")
var _reward_slot_scene := preload("res://scenes/ui/meridian/RewardSlot.tscn")

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

	var items_container: HBoxContainer = $MarginContainer/VBox/ItemsContainer
	var reward_box: HBoxContainer = $MarginContainer/VBox/RewardRow/RewardBox
	var complete_btn: Button = $MarginContainer/VBox/CompleteButton

	for child in items_container.get_children():
		child.queue_free()
	for child in reward_box.get_children():
		child.queue_free()

	for it in items:
		var item_id: int = int(it.get("item_id", 0))
		var item_data := ConfigDatabase.get_item_data(item_id)
		var item_button := Button.new()
		item_button.custom_minimum_size = Vector2(68, 84)
		item_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item_button.flat = true
		item_button.tooltip_text = "查看获取方式"
		item_button.pressed.connect(_on_item_pressed.bind(item_id))
		items_container.add_child(item_button)
		var widget := _item_widget_scene.instantiate() as ItemWidget
		item_button.add_child(widget)
		widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_style_item_widget(widget)
		if not item_data.is_empty():
			widget.setup(item_data)
		else:
			widget.setup({"name": it.get("name", "?")})
		widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if widget.name_label:
			widget.name_label.visible = true
			widget.name_label.add_theme_font_size_override("font_size", 8)

	# Reward preview
	if not rewards.is_empty():
		if rewards.has("tokens"):
			for t in rewards.tokens:
				var token_type: int = int(t.get("token", 0))
				var amount: int = int(t.get("amount", 0))
				var slot := _reward_slot_scene.instantiate() as RewardSlot
				reward_box.add_child(slot)
				slot.setup(token_type, amount)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if rewards.has("items"):
			for ri in rewards.items:
				var item_id: int = int(ri.get("id", 0))
				var count: int = int(ri.get("count", 0))
				var slot := _reward_slot_scene.instantiate() as RewardSlot
				reward_box.add_child(slot)
				slot.setup(item_id, count)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if completed:
		complete_btn.text = "✓"
		complete_btn.disabled = true
		complete_btn.visible = true
	else:
		complete_btn.text = "完成"
		if complete_btn.pressed.is_connected(_on_btn_pressed):
			complete_btn.pressed.disconnect(_on_btn_pressed)
		complete_btn.pressed.connect(_on_btn_pressed)
		complete_btn.visible = false

func set_available(available: bool) -> void:
	if not _data.get("completed", false):
		var btn: Button = $MarginContainer/VBox/CompleteButton
		btn.visible = available

func _on_btn_pressed() -> void:
	complete_pressed.emit()

func _on_item_pressed(item_id: int) -> void:
	if item_id > 0:
		item_pressed.emit(item_id)

func mark_completed() -> void:
	var btn: Button = $MarginContainer/VBox/CompleteButton
	btn.text = "✓"
	btn.disabled = true
	btn.visible = true
	var items_container: HBoxContainer = $MarginContainer/VBox/ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			child.modulate = Color(0.5, 0.8, 0.5, 1)
		elif child is Button:
			var widget := child.get_child(0) as ItemWidget
			if widget:
				widget.modulate = Color(0.5, 0.8, 0.5, 1)

func _style_item_widget(widget: ItemWidget) -> void:
	var icon_bg: TextureRect = widget.get_node_or_null("IconBg") as TextureRect
	if icon_bg:
		icon_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		icon_bg.anchor_right = 1.0
		icon_bg.offset_bottom = 62.0
	var icon_rect: TextureRect = widget.get_node_or_null("IconRect") as TextureRect
	if icon_rect:
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		icon_rect.anchor_right = 1.0
		icon_rect.offset_left = 6.0
		icon_rect.offset_top = 6.0
		icon_rect.offset_right = -6.0
		icon_rect.offset_bottom = 59.0
	var name_label: Label = widget.get_node_or_null("NameLabel") as Label
	if name_label:
		name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		name_label.anchor_right = 1.0
		name_label.offset_top = 63.0
		name_label.offset_bottom = 83.0
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var level_label: Label = widget.get_node_or_null("LevelLabel") as Label
	if level_label:
		level_label.position = Vector2(5.0, 3.0)
		level_label.size = Vector2(18.0, 17.0)
		level_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.16, 1))
		level_label.add_theme_font_size_override("font_size", 13)
	var charge_label: Label = widget.get_node_or_null("ChargeLabel") as Label
	if charge_label:
		charge_label.hide()
