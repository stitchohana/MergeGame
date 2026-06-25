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
		var item_box := VBoxContainer.new()
		item_box.custom_minimum_size = Vector2(40, 0)
		item_box.alignment = BoxContainer.ALIGNMENT_CENTER
		item_box.add_theme_constant_override("separation", 1)

		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		icon.color = _item_color(int(it.get("item_id", 0)))
		item_box.add_child(icon)

		var lbl := Label.new()
		lbl.text = it.get("name", "?")
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		item_box.add_child(lbl)

		items_container.add_child(item_box)

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
	for box in items_container.get_children():
		if box is VBoxContainer:
			for child in box.get_children():
				if child is ColorRect:
					child.modulate = Color(0.5, 0.8, 0.5, 1)

func _item_color(item_id: int) -> Color:
	match item_id:
		21: return Color(0.3, 0.7, 0.3)
		22: return Color(0.2, 0.6, 0.2)
		23: return Color(0.4, 0.8, 0.4)
		24: return Color(0.5, 0.9, 0.5)
		61: return Color(0.6, 0.4, 0.2)
		62: return Color(0.5, 0.5, 0.5)
		63: return Color(0.7, 0.7, 0.8)
		64: return Color(0.9, 0.8, 0.3)
		65: return Color(0.8, 0.5, 0.2)
		66: return Color(0.6, 0.6, 0.6)
		67: return Color(0.8, 0.8, 0.9)
		68: return Color(1.0, 0.9, 0.4)
		41: return Color(0.7, 0.3, 0.3)
		42: return Color(0.8, 0.3, 0.3)
		43: return Color(0.9, 0.3, 0.3)
		44: return Color(1.0, 0.3, 0.3)
		45: return Color(1.0, 0.2, 0.2)
		_: return Color(0.4, 0.4, 0.5)
