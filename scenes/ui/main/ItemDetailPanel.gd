class_name ItemDetailPanel extends BaseHUD
signal material_clicked(uid: int, item_id: int)
signal material_source_requested(item_id: int)

@onready var default_label: Label = $DefaultLabel
@onready var header: NinePatchRect = $Header
@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var desc_label: Label = $DescLabel
@onready var recipe_btn: Button = $RecipeButton
@onready var view_btn: Button = $ViewButton
@onready var materials_label: Label = $MaterialsLabel
@onready var status_label: Label = $StatusLabel
@onready var speedup_btn: Button = $SpeedupButton
@onready var materials_container: ScrollContainer = $MaterialsContainer
@onready var materials_row: HBoxContainer = $MaterialsContainer/MaterialsRow
@onready var output_label: Label = $OutputLabel
@onready var output_slot: ItemWidget = $OutputSlot
@onready var sell_btn: Button = $SellButton
@onready var delete_btn: Button = $DeleteButton
@onready var sell_price_label: Label = $SellPriceLabel

var _current_item_data: Dictionary = {}
var _current_recipes: Array = []
var _countdown_timer: Timer = null
var _pending_sell_uid: int = -1
var _output_item_id: int = 0
var _pending_speedup: String = ""
var _pending_speedup_uid: int = -1
var _displayed_speedup_cost: int = 0

const PREVIEW_GHOST_ALPHA: float = 0.35

func _ready() -> void:
	clear()
	recipe_btn.pressed.connect(_on_recipe_btn_pressed)
	if sell_btn:
		sell_btn.pressed.connect(_on_sell_pressed)
	if delete_btn and not delete_btn.pressed.is_connected(_on_sell_pressed):
		delete_btn.pressed.connect(_on_sell_pressed)
	view_btn.pressed.connect(_on_view_pressed)
	speedup_btn.pressed.connect(_on_speedup_pressed)
	if not CraftingService.table_state_changed.is_connected(_on_table_state_changed):
		CraftingService.table_state_changed.connect(_on_table_state_changed)
	CloudService.sell_confirmed.connect(_on_sell_server_confirmed)
	CloudService.sell_rejected.connect(_on_sell_server_rejected)
	CloudService.craft_speedup_confirmed.connect(_on_craft_speedup_confirmed)
	CloudService.craft_speedup_rejected.connect(_on_craft_speedup_rejected)
	CloudService.launcher_speedup_confirmed.connect(_on_launcher_speedup_confirmed)
	CloudService.launcher_speedup_rejected.connect(_on_launcher_speedup_rejected)
	GameState.spirit_stones_changed.connect(_on_spirit_stones_changed)
	if not EventBus.launcher_charge_changed.is_connected(_on_launcher_charge_changed):
		EventBus.launcher_charge_changed.connect(_on_launcher_charge_changed)

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
		_refresh_launcher_speedup()

func _refresh_materials() -> void:
	if _current_item_data.is_empty():
		_hide_materials()
		return
	_refresh_output_slot()
	var state: int = _current_item_data.get("_craft_state", CraftingService.TableState.IDLE)
	var timer_exists: bool = _countdown_timer != null and is_instance_valid(_countdown_timer)
	var timer_in_tree: bool = timer_exists and _countdown_timer.is_inside_tree()
	if state == CraftingService.TableState.CRAFTING:
		var remaining: float = CraftingService.get_remaining_craft_seconds(_current_item_data)
		if remaining > 0:
			status_label.text = "制作中... %s" % TimeUtils.format_countdown(remaining)
		else:
			status_label.text = "制作中..."
		status_label.show()
		materials_label.hide()
		materials_container.hide()
		desc_label.hide()
		_clear_material_slots()
		if not timer_exists or not timer_in_tree:
			_start_countdown_timer()
		_refresh_speedup_button("craft", remaining)
		return
	if state == CraftingService.TableState.READY:
		_stop_countdown_timer()
		_hide_speedup_button()
		status_label.text = "制作完成！点击取出"
		status_label.show()
		materials_label.hide()
		materials_container.hide()
		desc_label.hide()
		_clear_material_slots()
		return
	_stop_countdown_timer()
	_hide_speedup_button()
	status_label.hide()
	var stored: Array = CraftingService.get_stored_items(_current_item_data)
	materials_label.hide()
	materials_container.visible = not stored.is_empty()
	desc_label.visible = stored.is_empty()
	_populate_materials(stored)

func _populate_materials(items: Array) -> void:
	_clear_material_slots()
	if items.is_empty():
		return

	if items.is_empty():
		var hint := Label.new()
		hint.text = "拖动物品到制作台放入材料"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		materials_row.add_child(hint)
		return

	for item in items:
		var iid: int = item.get("id", 0) as int
		var data: Dictionary = ConfigDatabase.get_item_data(iid)
		var uid: int = item.get("uid", item.get("_uid", 0)) as int
		var entry: ItemWidget = _build_material_icon(data, uid)
		materials_row.add_child(entry)

	var matching_recipe: Dictionary = _find_order_recipe(items)
	if matching_recipe.is_empty():
		return
	_show_output_slot_for_recipe(matching_recipe, "candidate_recipe")
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	var has_ghost_material: bool = false
	for ingredient_variant in matching_recipe.get("ingredients", []):
		var ingredient_id: int = int(ingredient_variant)
		var remaining: int = int(stored_counts.get(ingredient_id, 0))
		if remaining > 0:
			stored_counts[ingredient_id] = remaining - 1
			continue
		var ghost_data: Dictionary = ConfigDatabase.get_item_data(ingredient_id)
		var ghost: ItemWidget = _build_material_icon(ghost_data, -1, true)
		has_ghost_material = true
		materials_row.add_child(ghost)
	_set_output_slot_ghost(has_ghost_material)

func _count_stored_item_ids(items: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item_variant in items:
		var item: Dictionary = item_variant as Dictionary
		var item_id: int = int(item.get("id", 0))
		counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts

func _count_board_available_item_ids() -> Dictionary:
	var counts: Dictionary = {}
	for entry in GridManager.get_all_items():
		var item_data: Dictionary = entry.get("data", {}) as Dictionary
		if item_data.is_empty():
			continue
		if int(item_data.get("type", -1)) == Constants.ItemType.CRAFTING:
			continue
		if bool(item_data.get("immovable", false)):
			continue
		var item_id: int = int(item_data.get("id", 0))
		if item_id <= 0:
			continue
		counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts

func _clear_material_slots() -> void:
	materials_container.scroll_horizontal = 0
	for child in materials_row.get_children():
		materials_row.remove_child(child)
		child.queue_free()

func _count_recipe_ingredients(ingredients: Array) -> Dictionary:
	var counts: Dictionary = {}
	for ingredient_variant in ingredients:
		var ingredient_id: int = int(ingredient_variant)
		counts[ingredient_id] = int(counts.get(ingredient_id, 0)) + 1
	return counts

func _get_active_order_item_ids() -> Dictionary:
	var order_item_ids: Dictionary = {}
	for item_id_variant: Variant in _get_active_order_item_counts().keys():
		order_item_ids[item_id_variant] = true
	return order_item_ids

func _get_active_order_item_counts() -> Dictionary:
	var order_item_counts: Dictionary = {}
	for order_index: int in range(GameState.meridian_acupoints.size()):
		var order_variant: Variant = GameState.meridian_acupoints[order_index]
		var order: Dictionary = order_variant as Dictionary
		if bool(order.get("completed", false)):
			continue
		var configured: Array = order.get("item_ids", []) as Array
		if configured.is_empty():
			configured = order.get("items", []) as Array
		for item_variant: Variant in configured:
			var item_id: int = (
				int((item_variant as Dictionary).get("item_id", 0))
				if item_variant is Dictionary
				else int(item_variant)
			)
			if item_id > 0:
				order_item_counts[item_id] = int(order_item_counts.get(item_id, 0)) + 1
	return order_item_counts

func _get_order_recipe_demand_counts(order_counts: Dictionary, board_counts: Dictionary) -> Dictionary:
	var demand_counts: Dictionary = {}
	var expanded_counts: Dictionary = {}
	for item_id_variant: Variant in order_counts.keys():
		_expand_order_recipe_demand(int(item_id_variant), int(order_counts[item_id_variant]),
			demand_counts, expanded_counts, board_counts, {})
	return demand_counts

func _expand_order_recipe_demand(item_id: int, count: int, demand_counts: Dictionary,
		expanded_counts: Dictionary, board_counts: Dictionary, path: Dictionary) -> void:
	if item_id <= 0 or count <= 0 or path.has(item_id):
		return
	demand_counts[item_id] = int(demand_counts.get(item_id, 0)) + count
	var shortage: int = maxi(0, int(demand_counts[item_id]) - int(board_counts.get(item_id, 0)))
	var to_expand: int = shortage - int(expanded_counts.get(item_id, 0))
	if to_expand <= 0:
		return
	expanded_counts[item_id] = shortage
	var ingredient_demands: Dictionary = {}
	for recipe_variant: Variant in ConfigDatabase.get_recipes_for_result(item_id):
		if not recipe_variant is Dictionary:
			continue
		var recipe_counts: Dictionary = _count_recipe_ingredients((recipe_variant as Dictionary).get("ingredients", []))
		for ingredient_id_variant: Variant in recipe_counts.keys():
			var ingredient_id: int = int(ingredient_id_variant)
			ingredient_demands[ingredient_id] = maxi(
				int(ingredient_demands.get(ingredient_id, 0)), int(recipe_counts[ingredient_id]))
	var next_path: Dictionary = path.duplicate()
	next_path[item_id] = true
	for ingredient_id_variant: Variant in ingredient_demands.keys():
		_expand_order_recipe_demand(int(ingredient_id_variant),
			to_expand * int(ingredient_demands[ingredient_id_variant]), demand_counts,
			expanded_counts, board_counts, next_path)

func _get_order_recipe_target_ids() -> Dictionary:
	var target_ids: Dictionary = _get_active_order_item_ids()
	var visited_item_ids: Dictionary = {}
	for item_id_variant: Variant in target_ids.keys():
		_collect_order_recipe_target_ids(
			int(item_id_variant), target_ids, visited_item_ids
		)
	return target_ids

func _collect_order_recipe_target_ids(
	item_id: int,
	target_ids: Dictionary,
	visited_item_ids: Dictionary
) -> void:
	if item_id <= 0 or visited_item_ids.has(item_id):
		return
	visited_item_ids[item_id] = true
	var result_recipes: Array = ConfigDatabase.get_recipes_for_result(item_id)
	for recipe_variant: Variant in result_recipes:
		if not recipe_variant is Dictionary:
			continue
		var recipe: Dictionary = recipe_variant as Dictionary
		for ingredient_variant: Variant in recipe.get("ingredients", []):
			var ingredient_id: int = int(ingredient_variant)
			var ingredient_recipes: Array = ConfigDatabase.get_recipes_for_result(ingredient_id)
			if ingredient_recipes.is_empty():
				continue
			target_ids[ingredient_id] = true
			_collect_order_recipe_target_ids(
				ingredient_id, target_ids, visited_item_ids
			)

func _find_order_recipe(items: Array) -> Dictionary:
	var active_order_counts: Dictionary = _get_active_order_item_counts()
	var active_order_item_ids: Dictionary = {}
	for item_id_variant: Variant in active_order_counts.keys():
		active_order_item_ids[item_id_variant] = true
	var order_target_ids: Dictionary = _get_order_recipe_target_ids()
	var has_order_filter: bool = not order_target_ids.is_empty()
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	var board_counts: Dictionary = _count_board_available_item_ids()
	var demand_counts: Dictionary = _get_order_recipe_demand_counts(active_order_counts, board_counts)
	var best_recipe: Dictionary = {}
	var best_order_priority: int = 2147483647
	var fewest_missing: int = 2147483647
	for recipe_variant in _current_recipes:
		var recipe: Dictionary = recipe_variant as Dictionary
		var result_id: int = int(recipe.get("result", 0))
		if has_order_filter and not order_target_ids.has(result_id):
			continue
		if int(board_counts.get(result_id, 0)) >= maxi(1, int(demand_counts.get(result_id, 0))):
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
		var available_counts: Dictionary = stored_counts.duplicate()
		for board_item_id_variant in board_counts.keys():
			var board_item_id: int = int(board_item_id_variant)
			available_counts[board_item_id] = int(available_counts.get(board_item_id, 0)) + int(board_counts[board_item_id])
		var missing: int = 0
		for ingredient_variant in recipe_ingredients:
			var ingredient_id: int = int(ingredient_variant)
			var available: int = int(available_counts.get(ingredient_id, 0))
			if available > 0:
				available_counts[ingredient_id] = available - 1
			else:
				missing += 1
		var order_priority: int = 0
		if has_order_filter and not active_order_item_ids.has(result_id):
			order_priority = 1
		if order_priority < best_order_priority or (order_priority == best_order_priority and missing < fewest_missing):
			best_order_priority = order_priority
			fewest_missing = missing
			best_recipe = recipe
	return best_recipe

func _build_material_icon(item_data: Dictionary, uid: int, ghost: bool = false) -> ItemWidget:
	var entry: ItemWidget = preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	entry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	entry.setup(item_data)
	entry.set_clickable(true)
	if ghost:
		entry.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA)
		entry.self_modulate = Color.WHITE

	if ghost:
		entry.pressed.connect(func(): material_source_requested.emit(int(item_data.get("id", 0))))
	else:
		entry.pressed.connect(func(): material_clicked.emit(uid, int(item_data.get("id", 0))))
	entry.call_deferred("_update_visuals")
	return entry

func _refresh_output_slot() -> void:
	var recipe: Dictionary = CraftingService.get_current_recipe(_current_item_data)
	var result_id: int = int(recipe.get("result", _current_item_data.get("_craft_result_id", 0)))
	_show_output_slot_for_result(result_id, "active_recipe")

func _show_output_slot_for_recipe(recipe: Dictionary, reason: String) -> void:
	_show_output_slot_for_result(int(recipe.get("result", 0)), reason)

func _show_output_slot_for_result(result_id: int, _reason: String) -> void:
	if result_id <= 0:
		_hide_output_slot()
		return
	var result_data: Dictionary = ConfigDatabase.get_item_data(result_id)
	if result_data.is_empty():
		_hide_output_slot()
		return
	_output_item_id = result_id
	output_slot.setup(result_data)
	output_slot.set_clickable(false)
	_set_output_slot_ghost(false)
	output_label.show()
	output_slot.show()

func _set_output_slot_ghost(ghost: bool) -> void:
	if output_slot == null:
		return
	output_slot.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA if ghost else 1.0)
	output_slot.self_modulate = Color.WHITE

func _hide_output_slot() -> void:
	_output_item_id = 0
	if output_label:
		output_label.hide()
	if output_slot:
		_set_output_slot_ghost(false)
		output_slot.hide()

func get_output_item_id() -> int:
	return _output_item_id

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
	var item_type: int = int(_current_item_data.get("type", 0))
	if item_type == Constants.ItemType.CRAFTING:
		var uid: int = int(_current_item_data.get("_uid", 0))
		if uid > 0:
			var latest: Dictionary = GridManager.find_by_uid(uid)
			if not latest.is_empty():
				_current_item_data = latest
		var state: int = _current_item_data.get("_craft_state", CraftingService.TableState.IDLE)
		if state != CraftingService.TableState.CRAFTING:
			_stop_countdown_timer()
			_hide_speedup_button()
			return
		var remaining: float = CraftingService.get_remaining_craft_seconds(_current_item_data)
		if remaining > 0:
			status_label.text = "制作中… %s" % TimeUtils.format_countdown(remaining)
			_refresh_speedup_button("craft", remaining)
		else:
			_hide_speedup_button()
		return
	_refresh_launcher_speedup()

func _hide_materials() -> void:
	_stop_countdown_timer()
	_hide_output_slot()
	status_label.hide()
	materials_label.hide()
	materials_container.hide()
	_clear_material_slots()

func _refresh_launcher_speedup() -> void:
	if _current_item_data.is_empty() or not Constants.has_launcher_config(_current_item_data):
		_hide_speedup_button()
		return
	var config: Dictionary = ConfigDatabase.get_item_data(int(_current_item_data.get("id", 0)))
	var max_charges: int = int(config.get("max_charges", 0))
	var charges: int = int(_current_item_data.get("charges", max_charges))
	var remaining_ms: float = float(_current_item_data.get("_recharge_remaining", 0.0))
	var remaining: float = maxf(0.0, remaining_ms / 1000.0)
	var is_recharging: bool = charges <= 0 and remaining > 0.0
	if not is_recharging:
		_stop_countdown_timer()
		_hide_speedup_button()
		status_label.hide()
		desc_label.show()
		return
	desc_label.hide()
	status_label.text = "充能中… %s" % TimeUtils.format_countdown(remaining)
	status_label.show()
	_refresh_speedup_button("launcher", remaining)
	if _countdown_timer == null or not is_instance_valid(_countdown_timer):
		_start_countdown_timer()

static func format_countdown_hms(seconds: float) -> String:
	return TimeUtils.format_countdown(seconds)

func _refresh_speedup_button(kind: String, remaining: float) -> void:
	var config_key: String = "craft_speedup_stone_cost_per_minute" if kind == "craft" else "launcher_speedup_stone_cost_per_minute"
	var cost_per_minute: float = float(ConfigDatabase.get_game_config(config_key, 1.0))
	_displayed_speedup_cost = calculate_speedup_cost(remaining, cost_per_minute)
	if _displayed_speedup_cost <= 0:
		_hide_speedup_button()
		return
	speedup_btn.text = "立即完成（%d灵石）" % _displayed_speedup_cost
	# The displayed cost is a client-side estimate. Let the authoritative server
	# decide affordability so a stale countdown cannot produce a false warning.
	speedup_btn.disabled = not _pending_speedup.is_empty()
	speedup_btn.show()

static func calculate_speedup_cost(remaining: float, cost_per_minute: float) -> int:
	var billed_minutes: int = int(ceil(maxf(0.0, remaining) / 60.0))
	return int(ceil(float(billed_minutes) * maxf(0.0, cost_per_minute)))

func _hide_speedup_button() -> void:
	_displayed_speedup_cost = 0
	if speedup_btn:
		speedup_btn.hide()

func _on_table_state_changed(table_item: Dictionary, _state: int) -> void:
	if _current_item_data.is_empty():
		return
	var current_uid: int = int(_current_item_data.get("_uid", 0))
	var changed_uid: int = int(table_item.get("_uid", -1))
	if current_uid <= 0 or current_uid != changed_uid:
		return
	# The signal payload can be a stale dictionary copy. Refresh from the grid
	# before reading _craft_state/_craft_end_time, otherwise the panel may stop
	# its timer while the table is already crafting.
	var latest: Dictionary = GridManager.find_by_uid(current_uid)
	if not latest.is_empty():
		_current_item_data = latest
	_refresh_materials()

func _on_speedup_pressed() -> void:
	if not _pending_speedup.is_empty():
		return
	if _displayed_speedup_cost <= 0:
		return
	if not CloudService.online:
		EventBus.show_toast.emit("离线状态无法加速")
		return
	if int(_current_item_data.get("type", 0)) == Constants.ItemType.CRAFTING:
		var table_pos: Vector2i = get_current_craft_pos()
		if table_pos.x < 0:
			return
		_pending_speedup = "craft"
		_pending_speedup_uid = _get_current_uid()
		CloudService.submit_craft_speedup(table_pos.x, table_pos.y)
	else:
		var uid: int = _get_current_uid()
		if uid <= 0:
			return
		_pending_speedup = "launcher"
		_pending_speedup_uid = uid
		CloudService.submit_launcher_speedup(uid)
	speedup_btn.disabled = true

func _on_craft_speedup_confirmed(result: Dictionary) -> void:
	if _pending_speedup != "craft":
		return
	var accelerated_uid: int = _pending_speedup_uid
	_pending_speedup = ""
	_pending_speedup_uid = -1
	var accelerated_item: Dictionary = GridManager.find_by_uid(accelerated_uid)
	if not accelerated_item.is_empty():
		CraftingService.complete_craft_now(accelerated_item)
	_reconcile_speedup_grid(result)
	_refresh_current_speedup_state()
	EventBus.show_toast.emit("消耗%d灵石，制作已完成" % int(result.get("cost", 0)))

func _on_craft_speedup_rejected(reason: String) -> void:
	if _pending_speedup != "craft":
		return
	_pending_speedup = ""
	_pending_speedup_uid = -1
	_refresh_current_speedup_state()
	_show_speedup_error(reason)

func _on_launcher_speedup_confirmed(result: Dictionary) -> void:
	if _pending_speedup != "launcher":
		return
	_pending_speedup = ""
	_pending_speedup_uid = -1
	_reconcile_speedup_grid(result)
	var refreshed: Dictionary = GridManager.find_by_uid(_get_current_uid())
	if not refreshed.is_empty():
		_current_item_data = refreshed
	_refresh_current_speedup_state()
	EventBus.show_toast.emit("消耗%d灵石，充能已完成" % int(result.get("cost", 0)))

func _on_launcher_speedup_rejected(reason: String) -> void:
	if _pending_speedup != "launcher":
		return
	_pending_speedup = ""
	_pending_speedup_uid = -1
	_refresh_current_speedup_state()
	_show_speedup_error(reason)

func _reconcile_speedup_grid(result: Dictionary) -> void:
	var server_grid: Array = result.get("grid", [])
	if server_grid.is_empty():
		return
	if not GridManager.reconcile_from_server(server_grid):
		CloudService.fetch_state()

func _show_speedup_error(reason: String) -> void:
	if reason == "insufficient_stones":
		EventBus.show_toast.emit("灵石不足")
	elif reason == "not_crafting" or reason == "not_recharging":
		EventBus.show_toast.emit("倒计时状态已变化")
	else:
		EventBus.show_toast.emit("加速失败：" + reason)

func _refresh_current_speedup_state() -> void:
	if _current_item_data.is_empty():
		return
	if int(_current_item_data.get("type", 0)) == Constants.ItemType.CRAFTING:
		_refresh_materials()
	else:
		_refresh_launcher_speedup()

func _on_spirit_stones_changed(_amount: int) -> void:
	if speedup_btn.visible:
		speedup_btn.disabled = not _pending_speedup.is_empty()

func _on_launcher_charge_changed(uid: int) -> void:
	if _current_item_data.is_empty() or int(_current_item_data.get("_uid", 0)) != uid:
		return
	var latest: Dictionary = GridManager.find_by_uid(uid)
	if not latest.is_empty():
		_current_item_data = latest
	_refresh_launcher_speedup()

func _on_view_pressed() -> void:
	if _current_item_data.is_empty():
		return
	var item_id: int = int(_current_item_data.get("id", 0))
	if not ConfigDatabase.get_recipes_for_result(item_id).is_empty():
		var source_popup := preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
		UIManager.show_popup(source_popup)
		source_popup.setup_for_item(item_id)
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
	_pending_speedup = ""
	_pending_speedup_uid = -1
	_hide_speedup_button()
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
