class_name ShopPopup extends BasePopup

@onready var title_label: Label = $Panel/TitleLabel
@onready var item_container = $Panel/ItemContainer
@onready var close_btn: Button = $Panel/CloseButton

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	CloudService.shop_items_loaded.connect(_on_shop_items_loaded)
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

	var icon_rect := ColorRect.new()
	icon_rect.custom_minimum_size = Vector2(40, 40)
	icon_rect.size = Vector2(40, 40)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gid: int = item_data.get("group_id", 0)
	var lv: int = item_data.get("level", 0)
	var hue := 0.0
	match gid:
		3: hue = float(lv - 1) / 8.0
		4: hue = 0.25 + float(lv - 1) / 6.0 * 0.15
		5: hue = 0.55 + float(lv - 1) / 6.0 * 0.15
		_: hue = float(lv - 1) / 8.0
	icon_rect.color = Color.from_hsv(hue, 0.6, 0.7)
	vbox.add_child(icon_rect)

	var name_label := Label.new()
	name_label.text = item_data.get("name", "")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%d灵石" % price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_font_size_override("font_size", 10)
	price_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
	vbox.add_child(price_label)

	btn.add_child(vbox)

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
	if CloudService.online:
		var item_data := ConfigDatabase.get_item_data(item_id)
		if not item_data.is_empty():
			GridManager.add_item(item_data.duplicate(true), spawn_pos)
			GameState.spirit_stones -= price
			GameState.spirit_stones_changed.emit(GameState.spirit_stones)
		CloudService.submit_buy(item_id, spawn_pos.x, spawn_pos.y)

func _on_shop_items_loaded(items: Array) -> void:
	show_items(items)

func _clear_items() -> void:
	if item_container:
		for child in item_container.get_children():
			child.queue_free()

func _on_close() -> void:
	UIManager.hide_popup(self)
