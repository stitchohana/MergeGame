class_name ItemDetailPanel extends BaseHUD
signal material_clicked(uid: int, item_id: int)

@onready var default_label: Label = $DefaultLabel
@onready var header: NinePatchRect = $Header
@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var desc_label: Label = $DescLabel
@onready var recipe_btn: Button = $RecipeButton
@onready var view_btn: Button = $ViewButton
@onready var materials_label: Label = $MaterialsLabel
@onready var status_label: Label = $StatusLabel
@onready var materials_container: FlowContainer = $MaterialsContainer
@onready var sell_btn: Button = $SellButton
@onready var delete_btn: Button = $DeleteButton
@onready var sell_price_label: Label = $SellPriceLabel

var _current_item_data: Dictionary = {}
var _current_recipes: Array = []
var _countdown_timer: Timer = null
var _pending_sell_uid: int = -1

func _ready() -> void:
	clear()
	recipe_btn.pressed.connect(_on_recipe_btn_pressed)
	if sell_btn:
		sell_btn.pressed.connect(_on_sell_pressed)
	if delete_btn and not delete_btn.pressed.is_connected(_on_sell_pressed):
		delete_btn.pressed.connect(_on_sell_pressed)
	view_btn.pressed.connect(_on_view_pressed)
	if not CraftingService.table_state_changed.is_connected(_on_table_state_changed):
		CraftingService.table_state_changed.connect(_on_table_state_changed)
	CloudService.sell_confirmed.connect(_on_sell_server_confirmed)
	CloudService.sell_rejected.connect(_on_sell_server_rejected)

func show_item(item_data: Dictionary, grid_pos: Vector2i = Vector2i(-1, -1)) -> void:
	if item_data.is_empty():
		return
	_current_item_data = item_data
	_update_sell_btn()
	header.show()
	var item_name: String = item_data.get("name", "")
	var item_level: int = item_data.get("level", 0)
	var item_desc: String = item_data.get("describe", "")
	var item_type: int = item_data.get("type", 0)

	default_label.hide()
	view_btn.show()

	if name_label:
		name_label.text = item_name
		name_label.show()

	if level_label:
		level_label.text = "%d级" % item_level
		level_label.show()

	if desc_label:
		desc_label.text = item_desc if item_desc else "暂无描述"
		desc_label.show()
		var effect_type: int = item_data.get("effect_type", 0)
		if effect_type == Constants.EffectType.DAMAGE:
			var mult: int = item_data.get("effect_value", 1)
			var atk_base: int = item_data.get("atk_base", 0)
			var dmg := atk_base * mult
			var damage_text := ""
			if atk_base > 0:
				damage_text = "伤害：%d × %d = %d" % [atk_base, mult, dmg]
			else:
				damage_text = "伤害：? × %d（无基础攻击力）" % mult
			desc_label.text += "\n" + damage_text
	if item_type == Constants.ItemType.CRAFTING:
		_current_recipes = ConfigDatabase.get_recipes_for_item(item_data.get("id", 0))
		recipe_btn.hide()
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
		desc_label.hide()
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
		desc_label.hide()
		for child in materials_container.get_children():
			child.queue_free()
		return
	_stop_countdown_timer()
	status_label.hide()
	var stored: Array = CraftingService.get_stored_items(_current_item_data)
	materials_label.hide()
	materials_container.visible = not stored.is_empty()
	desc_label.visible = stored.is_empty()
	_populate_materials(stored)

func _populate_materials(items: Array) -> void:
	for child in materials_container.get_children():
		child.queue_free()
	if items.is_empty():
		return

	if items.is_empty():
		var hint := Label.new()
		hint.text = "拖动物品到制作台放入材料"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		materials_container.add_child(hint)
		return

	for item in items:
		var iid: int = item.get("id", 0) as int
		var data: Dictionary = ConfigDatabase.get_item_data(iid)
		var uid: int = item.get("uid", item.get("_uid", 0)) as int
		var entry: ItemWidget = _build_material_icon(data, uid)
		materials_container.add_child(entry)

	var matching_recipe: Dictionary = _find_order_recipe(items)
	if matching_recipe.is_empty():
		return
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	for ingredient_variant in matching_recipe.get("ingredients", []):
		var ingredient_id: int = int(ingredient_variant)
		var remaining: int = int(stored_counts.get(ingredient_id, 0))
		if remaining > 0:
			stored_counts[ingredient_id] = remaining - 1
			continue
		var ghost_data: Dictionary = ConfigDatabase.get_item_data(ingredient_id)
		var ghost: ItemWidget = _build_material_icon(ghost_data, -1, true)
		materials_container.add_child(ghost)

func _count_stored_item_ids(items: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item_variant in items:
		var item: Dictionary = item_variant as Dictionary
		var item_id: int = int(item.get("id", 0))
		counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts

func _count_recipe_ingredients(ingredients: Array) -> Dictionary:
	var counts: Dictionary = {}
	for ingredient_variant in ingredients:
		var ingredient_id: int = int(ingredient_variant)
		counts[ingredient_id] = int(counts.get(ingredient_id, 0)) + 1
	return counts

func _get_active_order_item_ids() -> Dictionary:
	var order_item_ids: Dictionary = {}
	for order_variant in GameState.meridian_acupoints:
		var order: Dictionary = order_variant as Dictionary
		if bool(order.get("completed", false)):
			continue
		for item_variant in order.get("items", []):
			var item: Dictionary = item_variant as Dictionary
			var item_id: int = int(item.get("item_id", 0))
			if item_id > 0:
				order_item_ids[item_id] = true
	return order_item_ids

func _find_order_recipe(items: Array) -> Dictionary:
	var order_item_ids: Dictionary = _get_active_order_item_ids()
	if order_item_ids.is_empty():
		return {}
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	var best_recipe: Dictionary = {}
	var fewest_missing: int = 2147483647
	for recipe_variant in _current_recipes:
		var recipe: Dictionary = recipe_variant as Dictionary
		if not order_item_ids.has(int(recipe.get("result", 0))):
			continue
		var recipe_ingredients: Array = recipe.get("ingredients", [])
		var required_counts: Dictionary = _count_recipe_ingredients(recipe_ingredients)
		var compatible: bool = true
		for item_id_variant in stored_counts.keys():
			var item_id: int = int(item_id_variant)
			if int(stored_counts[item_id]) > int(required_counts.get(item_id, 0)):
				compatible = false
				break
		if not compatible:
			continue
		var missing: int = recipe_ingredients.size() - items.size()
		if missing < fewest_missing:
			fewest_missing = missing
			best_recipe = recipe
	return best_recipe

func _build_material_icon(item_data: Dictionary, uid: int, ghost: bool = false) -> ItemWidget:
	var entry: ItemWidget = preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	entry.custom_minimum_size = Vector2(60, 60)
	entry.size = Vector2(60, 60)
	entry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	entry.setup(item_data)
	entry.set_clickable(not ghost)
	if ghost:
		entry.modulate = Color(1, 1, 1, 0.35)

	if not ghost:
		entry.pressed.connect(func(): material_clicked.emit(uid, int(item_data.get("id", 0))))
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
	var popup := preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(_current_item_data)

func _on_recipe_btn_pressed() -> void:
	if _current_recipes.is_empty():
		return
	var popup := preload("res://scenes/ui/main/RecipePopup.tscn").instantiate() as RecipePopup
	UIManager.show_popup(popup)
	popup.setup(_current_recipes, _current_item_data.get("name", ""))

func _on_sell_pressed() -> void:
	var uid: int = _get_current_uid()
	if uid <= 0:
		return
	if _current_item_data.get("immovable", false):
		EventBus.show_toast.emit("该物品无法出售")
		return
	var item_id: int = _current_item_data.get("id", 0)
	var price: int = _current_item_data.get("sell_price", 0)
	if price <= 0:
		return
	var item_name: String = _current_item_data.get("name", "")
	var popup := preload("res://scenes/ui/common/ConfirmPopup.tscn").instantiate() as ConfirmPopup
	UIManager.show_popup(popup)
	popup.setup("出售", "确定出售 %s？获得 %d 灵石" % [item_name, price], func(): _on_sell_confirmed(uid))

func _on_sell_confirmed(uid: int) -> void:
	if not CloudService.online:
		EventBus.show_toast.emit("离线无法出售")
		return
	if uid <= 0:
		return
	_pending_sell_uid = uid
	CloudService.submit_sell(uid)

func _on_sell_server_confirmed(_result: Dictionary) -> void:
	if _pending_sell_uid > 0:
		var pos := GridManager.find_pos_by_uid(_pending_sell_uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)
		_pending_sell_uid = -1
	clear()

func _on_sell_server_rejected(reason: String) -> void:
	_pending_sell_uid = -1
	EventBus.show_toast.emit("出售失败：" + reason)

func _update_sell_btn() -> void:
	if sell_btn:
		sell_btn.hide()
	if sell_price_label:
		sell_price_label.hide()
	if delete_btn:
		delete_btn.show()

func clear() -> void:
	_stop_countdown_timer()
	_current_item_data = {}
	_current_recipes = []
	header.hide()
	default_label.show()
	name_label.hide()
	level_label.hide()
	desc_label.hide()
	recipe_btn.hide()
	view_btn.hide()
	if sell_btn:
		sell_btn.hide()
	if sell_price_label:
		sell_price_label.hide()
	_hide_materials()
