class_name ShopPopup extends BasePopup

@onready var title_label: Label = $Panel/TitleLabel
@onready var item_container = $Panel/ItemContainer
@onready var close_btn: Button = $Panel/CloseButton

var _pending_buy_target: Vector2i = Vector2i(-1, -1)
var _pending_buy_item_id: int = -1

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	CloudService.shop_items_loaded.connect(_on_shop_items_loaded)
	CloudService.buy_confirmed.connect(_on_buy_confirmed)
	CloudService.buy_rejected.connect(_on_buy_rejected)
	_refresh()

func _refresh() -> void:
	if not item_container:
		return
	_clear_items()

	if title_label:
		title_label.text = "商店"

	if CloudService.online:
		CloudService.fetch_shop_items()

func show_items(items: Array) -> void:
	if not item_container:
		return
	_clear_items()

	if items.is_empty():
		var hint := Label.new()
		hint.text = "暂无商品"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		item_container.add_child(hint)
		return

	for entry in items:
		var item_data := ConfigDatabase.get_item_data(entry.id)
		if item_data.is_empty():
			continue
		var btn := _build_item_button(item_data, entry.price)
		item_container.add_child(btn)

func _build_item_button(item_data: Dictionary, price: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(80, 110)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var widget := preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	vbox.add_child(widget)
	widget.setup(item_data)

	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if widget.name_label:
		widget.name_label.add_theme_font_size_override("font_size", 9)

	var price_label := Label.new()
	price_label.text = "%d灵石" % price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_font_size_override("font_size", 10)
	price_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
	vbox.add_child(price_label)

	var item_id: int = item_data.get("id", 0)
	btn.pressed.connect(func(): _on_buy_pressed(item_id, price))
	return btn

func _on_buy_pressed(item_id: int, price: int) -> void:
	if GameState.spirit_stones < price:
		EventBus.show_toast.emit("灵石不足")
		return
	var spawn_pos := GridManager.find_nearest_empty(Vector2i(3, 3))
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满")
		return
	_pending_buy_item_id = item_id
	_pending_buy_target = spawn_pos
	if CloudService.online:
		CloudService.submit_buy(item_id, spawn_pos.x, spawn_pos.y)

func _on_buy_confirmed(result: Dictionary) -> void:
	var item_id: int = _pending_buy_item_id
	var spawn_pos: Vector2i = _pending_buy_target
	_pending_buy_item_id = -1
	_pending_buy_target = Vector2i(-1, -1)

	if item_id > 0 and spawn_pos != Vector2i(-1, -1):
		var item_data := ConfigDatabase.get_item_data(item_id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			item["_uid"] = result.get("uid", 0)
			GridManager.add_item(item, spawn_pos)
	GameState.spirit_stones = result.get("spirit_stones", GameState.spirit_stones)
	GameState.spirit_stones_changed.emit(GameState.spirit_stones)
	EventBus.show_toast.emit("购买成功")

func _on_buy_rejected(reason: String) -> void:
	_pending_buy_item_id = -1
	_pending_buy_target = Vector2i(-1, -1)
	EventBus.show_toast.emit("购买失败：" + reason)

func _on_shop_items_loaded(items: Array) -> void:
	show_items(items)

func _clear_items() -> void:
	if item_container:
		for child in item_container.get_children():
			child.queue_free()

func _on_close() -> void:
	UIManager.hide_popup(self)
