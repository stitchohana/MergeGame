class_name PouchPopup extends BasePopup

# PouchPopup: Shows items in the storage pouch and allows withdrawing them.

var _items: Array = []

@onready var title_label: Label = $Panel/TitleLabel
@onready var item_container = $Panel/ItemContainer
@onready var close_btn: Button = $Panel/CloseButton

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	if not StoragePouch.pouch_updated.is_connected(_on_pouch_changed):
		StoragePouch.pouch_updated.connect(_on_pouch_changed)
	_refresh()

func _on_pouch_changed(_items: Array) -> void:
	_refresh()

func _refresh() -> void:
	if not item_container:
		return
	_clear_items()
	_items = StoragePouch.items.duplicate()

	if title_label:
		title_label.text = "储物袋 (%d)" % _items.size()

	if _items.is_empty():
		var hint := Label.new()
		hint.text = "储物袋为空"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		item_container.add_child(hint)
		return

	for entry in _items:
		var item_id: int = entry.get("id", 0) as int
		var item_uid: int = entry.get("uid", 0) as int
		var item_data := ConfigDatabase.get_item_data(item_id)
		if item_data.is_empty():
			continue
		var btn := _build_item_button(item_data, item_uid)
		item_container.add_child(btn)

func _build_item_button(item_data: Dictionary, uid: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(80, 100)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var widget := preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	btn.add_child(widget)
	widget.setup(item_data)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE

	btn.pressed.connect(func(): _on_item_pressed(uid))
	return btn

func _on_item_pressed(uid: int) -> void:
	StoragePouch.withdraw(uid)

func _clear_items() -> void:
	if item_container:
		for child in item_container.get_children():
			child.queue_free()

func _on_close() -> void:
	UIManager.hide_popup(self)
