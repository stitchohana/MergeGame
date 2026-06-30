class_name RequirementEntry extends Control

signal complete_pressed()

var _data: Dictionary = {}
var _items_setup: Array = []
var _index_setup: int = -1
var _completed_setup: bool = false
var _ready_done: bool = false

func _ready() -> void:
	_ready_done = true
	if not _items_setup.is_empty():
		_do_setup(_items_setup, _index_setup, _completed_setup)

func setup(items: Array, index: int, completed: bool) -> void:
	_items_setup = items
	_index_setup = index
	_completed_setup = completed
	if _ready_done:
		_do_setup(items, index, completed)

func _do_setup(items: Array, index: int, completed: bool) -> void:
	_data = {"items": items, "index": index, "completed": completed}

	var items_container: HBoxContainer = $Panel/ItemsContainer
	var complete_btn: Button = $Panel/CompleteButton

	for child in items_container.get_children():
		child.queue_free()

	for it in items:
		var item_id: int = int(it.get("item_id", 0))
		var item_data := ConfigDatabase.get_item_data(item_id)
		var widget := preload("res://scenes/ui/ItemWidget.tscn").instantiate() as ItemWidget
		items_container.add_child(widget)
		if not item_data.is_empty():
			widget.setup(item_data)
		else:
			widget.setup({"name": it.get("name", "?")})
		widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if widget.name_label:
			widget.name_label.visible = true
			widget.name_label.add_theme_font_size_override("font_size", 9)

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
		var btn: Button = $Panel/CompleteButton
		btn.visible = available

func _on_btn_pressed() -> void:
	complete_pressed.emit()

func mark_completed() -> void:
	var btn: Button = $Panel/CompleteButton
	btn.text = "✓"
	btn.disabled = true
	btn.visible = true
	var items_container: HBoxContainer = $Panel/ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			child.modulate = Color(0.5, 0.8, 0.5, 1)
