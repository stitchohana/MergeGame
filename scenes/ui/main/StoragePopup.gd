class_name StoragePopup extends BasePopup

var _pending_withdraw_uid: int = 0
var _pending_withdraw_item_id: int = 0

@onready var title_label: Label = $Panel/TitleLabel
@onready var item_container = $Panel/ItemContainer
@onready var close_btn: Button = $Panel/CloseButton

var _storage_pos: Vector2i = Vector2i(-1, -1)
var _items: Array = []

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	if not CloudService.storage_withdraw_confirmed.is_connected(_on_withdraw_confirmed):
		CloudService.storage_withdraw_confirmed.connect(_on_withdraw_confirmed)
	if not CloudService.storage_withdraw_rejected.is_connected(_on_withdraw_rejected):
		CloudService.storage_withdraw_rejected.connect(_on_withdraw_rejected)
	_refresh()

func setup(storage_pos: Vector2i, items: Array) -> void:
	_storage_pos = storage_pos
	_items = items
	if is_inside_tree():
		_refresh()

func _refresh() -> void:
	if not item_container:
		return
	_clear_items()

	if title_label:
		title_label.text = "仓库 (%d/%d)" % [_items.size(), 20]

	if _items.is_empty():
		var hint := Label.new()
		hint.text = "仓库为空"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		item_container.add_child(hint)
		return

	for slot in _items:
		var item_data := ConfigDatabase.get_item_data(slot.id)
		if item_data.is_empty():
			continue
		var btn := _build_item_button(item_data, slot.uid)
		item_container.add_child(btn)

func _build_item_button(item_data: Dictionary, slot_uid: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(80, 100)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var widget := preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	widget.setup(item_data)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(widget)

	btn.pressed.connect(func(): _on_item_pressed(slot_uid))
	return btn

func _on_item_pressed(slot_uid: int) -> void:
	if _pending_withdraw_uid > 0:
		EventBus.show_toast.emit("操作太频繁，请稍后再试")
		return
	var spawn_pos := GridManager.find_nearest_empty(_storage_pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满")
		return

	# Find the item by uid
	var idx := -1
	for i in range(_items.size()):
		if _items[i].get("uid", 0) == slot_uid:
			idx = i
			break
	if idx >= 0:
		_pending_withdraw_uid = slot_uid
		_pending_withdraw_item_id = _items[idx].get("id", 0)

	if CloudService.online:
		CloudService.submit_storage_withdraw(_storage_pos.x, _storage_pos.y, _pending_withdraw_uid, spawn_pos.x, spawn_pos.y)

func _on_withdraw_rejected(reason: String) -> void:
	EventBus.show_toast.emit("取出失败：" + reason)
	_pending_withdraw_uid = 0
	_pending_withdraw_item_id = 0

func _on_withdraw_confirmed(result: Dictionary) -> void:
	var storage_data = result.get("storage", null)
	if storage_data != null:
		_items = storage_data.items
		_refresh()
	var _sw_uid: int = result.get("uid", 0) as int
	if _sw_uid > 0 and _pending_withdraw_uid > 0:
		var _sw_col: int = result.get("col", 0) as int
		var _sw_row: int = result.get("row", 0) as int
		var item_data := ConfigDatabase.get_item_data(_pending_withdraw_item_id)
		if not item_data.is_empty():
			var new_item := item_data.duplicate(true)
			new_item["_uid"] = _sw_uid
			GridManager.add_item(new_item, Vector2i(_sw_col, _sw_row))
		_pending_withdraw_uid = 0
		_pending_withdraw_item_id = 0

func _clear_items() -> void:
	if item_container:
		for child in item_container.get_children():
			child.queue_free()

func _on_close() -> void:
	if CloudService.storage_withdraw_confirmed.is_connected(_on_withdraw_confirmed):
		CloudService.storage_withdraw_confirmed.disconnect(_on_withdraw_confirmed)
	if CloudService.storage_withdraw_rejected.is_connected(_on_withdraw_rejected):
		CloudService.storage_withdraw_rejected.disconnect(_on_withdraw_rejected)
	UIManager.hide_popup(self)
