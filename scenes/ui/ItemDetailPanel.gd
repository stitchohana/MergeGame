class_name ItemDetailPanel extends BaseHUD
signal material_clicked(item_id: int)

@onready var default_label: Label = $DefaultLabel
@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var desc_label: Label = $DescLabel
@onready var recipe_btn: Button = $RecipeButton
@onready var materials_label: Label = $MaterialsLabel
@onready var status_label: Label = $StatusLabel
@onready var materials_container: FlowContainer = $MaterialsContainer
@onready var sell_btn: Button = $SellButton
@onready var sell_price_label: Label = $SellPriceLabel

var _current_item_data: Dictionary = {}
var _current_recipes: Array = []
var _countdown_timer: Timer = null
var _sell_prices: Dictionary = {}

func _ready() -> void:
	clear()
	recipe_btn.pressed.connect(_on_recipe_btn_pressed)
	if sell_btn:
		sell_btn.pressed.connect(_on_sell_pressed)
	if $ViewButton:
		$ViewButton.pressed.connect(_on_view_pressed)
	if not CraftingService.table_state_changed.is_connected(_on_table_state_changed):
		CraftingService.table_state_changed.connect(_on_table_state_changed)

func show_item(item_data: Dictionary, grid_pos: Vector2i = Vector2i(-1, -1)) -> void:
	if item_data.is_empty():
		clear()
		return
	_current_item_data = item_data
	_update_sell_btn()
	var item_name: String = item_data.get("name", "")
	var item_level: int = item_data.get("level", 0)
	var item_desc: String = item_data.get("describe", "")
	var item_type: String = item_data.get("type", "regular")

	default_label.hide()

	if name_label:
		name_label.text = item_name
		name_label.show()

	if level_label:
		var type_name := ""
		match item_type:
			"launcher": type_name = "发射器"
			"crafting": type_name = "制作台"
			_: type_name = "物品"
		level_label.text = "Lv.%d  %s" % [item_level, type_name]
		level_label.show()

	if desc_label:
		desc_label.text = item_desc if item_desc else "暂无描述"
		desc_label.show()

	if item_type == "crafting":
		_current_recipes = ConfigDatabase.get_recipes_for_item(item_data.get("id", 0))
		recipe_btn.visible = not _current_recipes.is_empty()
		_refresh_materials()
	else:
		_current_recipes = []
		recipe_btn.hide()
		_hide_materials()

func _refresh_materials() -> void:
	if _current_item_data.is_empty():
		_hide_materials()
		return
	var state: int = _current_item_data.get("_craft_state", CraftingService.TableState.IDLE)
	var timer_exists: bool = _countdown_timer != null and is_instance_valid(_countdown_timer)
	var timer_in_tree: bool = timer_exists and _countdown_timer.is_inside_tree()
	if state == CraftingService.TableState.CRAFTING:
		var remaining := CraftingService.get_remaining_craft_seconds(_current_item_data)
		if remaining > 0:
			status_label.text = "制作中... %d秒" % int(ceil(remaining))
		else:
			status_label.text = "制作中..."
		status_label.show()
		materials_label.hide()
		materials_container.hide()
		for child in materials_container.get_children():
			child.queue_free()
		if not timer_exists or not timer_in_tree:
			_start_countdown_timer()
		return
	if state == CraftingService.TableState.READY:
		_stop_countdown_timer()
		status_label.text = "制作完成！点击取出"
		status_label.show()
		materials_label.hide()
		materials_container.hide()
		for child in materials_container.get_children():
			child.queue_free()
		return
	_stop_countdown_timer()
	status_label.hide()
	var stored: Array = CraftingService.get_stored_items(_current_item_data)
	materials_label.visible = true
	materials_container.visible = true
	_populate_materials(stored)

func _populate_materials(items: Array) -> void:
	for child in materials_container.get_children():
		child.queue_free()

	if items.is_empty():
		var hint := Label.new()
		hint.text = "拖动物品到制作台放入材料"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		materials_container.add_child(hint)
		return

	var count_map: Dictionary = {}
	for item in items:
		var iid: int = item.get("id", 0)
		count_map[iid] = count_map.get(iid, 0) + 1

	for iid in count_map:
		var count: int = count_map[iid]
		var data := ConfigDatabase.get_item_data(iid)
		var entry := _build_material_icon(data, count)
		materials_container.add_child(entry)

func _build_material_icon(item_data: Dictionary, count: int) -> Button:
	var entry := Button.new()
	entry.flat = true
	entry.custom_minimum_size = Vector2(60, 60)
	entry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(36, 36)
	rect.size = Vector2(36, 36)
	rect.position = Vector2(12, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var group_id: int = item_data.get("group_id", 0)
	var level: int = item_data.get("level", 0)
	if item_data.get("type", "") == "launcher":
		match group_id:
			1: rect.color = Color(0.6, 0.3, 0.8, 1)
			2: rect.color = Color(1.0, 0.6, 0.2, 1)
			_: rect.color = Color(0.5, 0.5, 0.5, 1)
	else:
		var hue := 0.0
		match group_id:
			1: hue = float(level - 1) / 8.0
			2: hue = 0.25 + float(level - 1) / 6.0 * 0.15
			_: hue = float(level - 1) / 8.0
		rect.color = Color.from_hsv(hue, 0.6, 0.7)

	var name_label := Label.new()
	name_label.text = item_data.get("name", "")
	name_label.position = Vector2(0, 38)
	name_label.size = Vector2(60, 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var count_label := Label.new()
	count_label.text = "x%d" % count
	count_label.position = Vector2(0, 50)
	count_label.size = Vector2(60, 12)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 10)
	count_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	entry.add_child(rect)
	entry.add_child(name_label)
	entry.add_child(count_label)
	entry.pressed.connect(func(): material_clicked.emit(item_data.get("id", 0)))
	return entry

func get_current_craft_table() -> Dictionary:
	return _current_item_data

# Derive position from uid instead of storing it
func get_current_craft_pos() -> Vector2i:
	if _current_item_data.is_empty():
		return Vector2i(-1, -1)
	var uid: int = _current_item_data.get("_uid", 0)
	if uid <= 0:
		return Vector2i(-1, -1)
	var item: Dictionary = GridManager.find_by_uid(uid)
	if item.is_empty():
		return Vector2i(-1, -1)
	# Scan grid to find position of this item
	for entry in GridManager.get_all_items():
		if entry.data.get("_uid", 0) == uid:
			return entry.pos
	return Vector2i(-1, -1)

func _get_current_uid() -> int:
	if _current_item_data.is_empty():
		return -1
	return _current_item_data.get("_uid", -1)

func _start_countdown_timer() -> void:
	_stop_countdown_timer()
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.one_shot = false
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)
	_countdown_timer.start()

func _stop_countdown_timer() -> void:
	if _countdown_timer and is_instance_valid(_countdown_timer):
		_countdown_timer.stop()
		_countdown_timer.queue_free()
		_countdown_timer = null

func _on_countdown_tick() -> void:
	if _current_item_data.is_empty():
		_stop_countdown_timer()
		return
	var state: int = _current_item_data.get("_craft_state", CraftingService.TableState.IDLE)
	if state != CraftingService.TableState.CRAFTING:
		_stop_countdown_timer()
		status_label.text = "制作完成！点击取出"
		return
	var remaining := CraftingService.get_remaining_craft_seconds(_current_item_data)
	if remaining > 0:
		status_label.text = "制作中... %d秒" % int(ceil(remaining))
	else:
		status_label.text = "制作中..."

func _hide_materials() -> void:
	_stop_countdown_timer()
	status_label.hide()
	materials_label.hide()
	materials_container.hide()
	for child in materials_container.get_children():
		child.queue_free()

func _on_table_state_changed(table_item: Dictionary, state: int) -> void:
	if not _current_item_data.is_empty() and _current_item_data.get("_uid", 0) == table_item.get("_uid", -1):
		_refresh_materials()

func _on_view_pressed() -> void:
	if _current_item_data.is_empty():
		return
	var popup := preload("res://scenes/ui/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(_current_item_data)

func _on_recipe_btn_pressed() -> void:
	if _current_recipes.is_empty():
		return
	var popup := preload("res://scenes/ui/RecipePopup.tscn").instantiate() as RecipePopup
	UIManager.show_popup(popup)
	popup.setup(_current_recipes, _current_item_data.get("name", ""))

func _on_sell_pressed() -> void:
	var uid: int = _get_current_uid()
	if uid <= 0:
		return
	var item_id: int = _current_item_data.get("id", 0)
	var price: int = _sell_prices.get(str(item_id), 0)
	if price <= 0:
		return
	var item_name: String = _current_item_data.get("name", "")
	var popup := preload("res://scenes/ui/ConfirmPopup.tscn").instantiate() as ConfirmPopup
	popup.setup("确定出售 %s？获得 %d 灵石" % [item_name, price])
	popup.confirmed.connect(_on_sell_confirmed.bind(uid), CONNECT_ONE_SHOT)
	UIManager.show_popup(popup)

func _on_sell_confirmed(uid: int) -> void:
	if CloudService.online:
		if uid <= 0:
			return
		var pos := get_current_craft_pos()
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)
		clear()
		CloudService.submit_sell(uid)
	else:
		EventBus.show_toast.emit("离线无法出售")

func _load_sell_prices() -> void:
	if not _sell_prices.is_empty():
		return
	var file := FileAccess.open("res://config/shop.json", FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(text) == OK:
			_sell_prices = json.data.get("sell_prices", {})
			print("[Shop] Loaded ", _sell_prices.size(), " prices")
			return
	print("[Shop] Failed to load sell prices from res://config/shop.json")

func _update_sell_btn() -> void:
	if not sell_btn or not sell_price_label:
		return
	var item_type: String = _current_item_data.get("type", "")
	if item_type != "regular":
		sell_btn.hide()
		sell_price_label.hide()
		return
	_load_sell_prices()
	var item_id: int = _current_item_data.get("id", 0)
	var price: int = _sell_prices.get(str(item_id), 0)
	if price <= 0:
		sell_btn.hide()
		sell_price_label.hide()
		return
	sell_price_label.text = "灵石 x%d" % price
	sell_price_label.show()
	sell_btn.show()

func clear() -> void:
	_stop_countdown_timer()
	_current_item_data = {}
	_current_recipes = []
	default_label.show()
	name_label.hide()
	level_label.hide()
	desc_label.hide()
	recipe_btn.hide()
	if sell_btn:
		sell_btn.hide()
	if sell_price_label:
		sell_price_label.hide()
	_hide_materials()
