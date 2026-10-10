class_name PouchPopup extends BasePopup

# PouchPopup: Shows items in the storage pouch and allows withdrawing them.

var _items: Array = []

@onready var title_label: Label = $Panel/TitleLabel
@onready var item_container: GridContainer = $Panel/Scroll/ItemContainer
@onready var close_btn: Button = $Panel/CloseButton
@onready var unlock_button: Button = $Panel/UnlockButton
@onready var balance_label: Label = $Panel/BalanceLabel

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	if not StoragePouch.pouch_updated.is_connected(_on_pouch_changed):
		StoragePouch.pouch_updated.connect(_on_pouch_changed)
	unlock_button.pressed.connect(StoragePouch.unlock_slot)
	GameState.spirit_stones_changed.connect(_on_stones_changed)
	StoragePouch.withdraw_failed.connect(_on_withdraw_failed)
	_refresh()

func _on_stones_changed(_amount: int) -> void:
	_refresh_unlock()

func _refresh_unlock() -> void:
	balance_label.text = "持有灵石：%d" % GameState.spirit_stones
	unlock_button.text = "解锁 1 格 · %d 灵石" % StoragePouch.next_unlock_cost
	if StoragePouch.unlock_pending:
		unlock_button.text = "解锁中…"
	unlock_button.disabled = StoragePouch.unlock_pending or not CloudService.online or GameState.spirit_stones < StoragePouch.next_unlock_cost
	if not CloudService.online:
		unlock_button.tooltip_text = "请联网后解锁"
	elif GameState.spirit_stones < StoragePouch.next_unlock_cost:
		unlock_button.tooltip_text = "灵石不足"
	else:
		unlock_button.tooltip_text = "解锁后增加 1 个储物格子"

func _on_withdraw_failed(reason: String) -> void:
	if reason == "grid_full":
		EventBus.show_toast.emit("棋盘已满，请腾出空位后取出")
	else:
		EventBus.show_toast.emit("取出失败，请稍后重试")

func _on_pouch_changed(_items: Array) -> void:
	_refresh()

func _refresh() -> void:
	if not item_container:
		return
	_clear_items()
	_items = StoragePouch.items.duplicate()

	if title_label:
		title_label.text = "储物袋 (%d/%d)" % [_items.size(), StoragePouch.capacity]
	_refresh_unlock()
	for slot_index: int in range(StoragePouch.capacity):
		if slot_index >= _items.size():
			var slot := TextureRect.new()
			slot.custom_minimum_size = Vector2(74, 96)
			slot.texture = preload("res://assets/game/item_bg_atlas_texture.tres")
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item_container.add_child(slot)
			continue
		var entry: Dictionary = _items[slot_index]
		var item_id: int = entry.get("id", 0) as int
		var item_uid: int = entry.get("uid", 0) as int
		var item_data := ConfigDatabase.get_item_data(item_id)
		if item_data.is_empty():
			continue
		var widget := _build_item_widget(item_data, item_uid)
		item_container.add_child(widget)

func _build_item_widget(item_data: Dictionary, uid: int) -> ItemWidget:
	var widget := preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	widget.custom_minimum_size = Vector2(74, 96)
	widget.size = Vector2(74, 96)
	widget.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	widget.setup(item_data)
	widget.set_clickable(true)
	widget.pressed.connect(func(): _on_item_pressed(uid))
	return widget

func _on_item_pressed(uid: int) -> void:
	StoragePouch.withdraw(uid)

func _clear_items() -> void:
	if item_container:
		for child in item_container.get_children():
			item_container.remove_child(child)
			child.queue_free()

func _exit_tree() -> void:
	if StoragePouch.pouch_updated.is_connected(_on_pouch_changed):
		StoragePouch.pouch_updated.disconnect(_on_pouch_changed)
	if GameState.spirit_stones_changed.is_connected(_on_stones_changed):
		GameState.spirit_stones_changed.disconnect(_on_stones_changed)
	if StoragePouch.withdraw_failed.is_connected(_on_withdraw_failed):
		StoragePouch.withdraw_failed.disconnect(_on_withdraw_failed)

func _on_close() -> void:
	if StoragePouch.pouch_updated.is_connected(_on_pouch_changed):
		StoragePouch.pouch_updated.disconnect(_on_pouch_changed)
	UIManager.hide_popup(self)
