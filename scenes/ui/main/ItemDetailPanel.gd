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
		print("[CraftDetail] refresh_abort reason=current_item_empty")
		_hide_materials()
		return
	_refresh_output_slot()
	var state: int = _current_item_data.get("_craft_state", CraftingService.TableState.IDLE)
	var stored_debug: Array = CraftingService.get_stored_items(_current_item_data)
	print("[CraftDetail] refresh table_id=", int(_current_item_data.get("id", 0)),
		" uid=", int(_current_item_data.get("_uid", 0)), " state=", state,
		" stored_count=", stored_debug.size(), " table_recipe_count=", _current_recipes.size(),
		" active_order_count=", GameState.meridian_acupoints.size())
	var timer_exists: bool = _countdown_timer != null and is_instance_valid(_countdown_timer)
	var timer_in_tree: bool = timer_exists and _countdown_timer.is_inside_tree()
	if state == CraftingService.TableState.CRAFTING:
		print("[CraftDetail] materials_hidden reason=table_crafting")
		var remaining: float = CraftingService.get_remaining_craft_seconds(_current_item_data)
		if remaining > 0:
			status_label.text = "制作中... %d秒" % int(ceil(remaining))
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
		print("[CraftDetail] materials_hidden reason=table_ready")
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
	print("[CraftDetail] container_prepare visible=", materials_container.visible,
		" size=", materials_container.size, " stored_count=", stored.size(),
		" children_before_rebuild=", materials_row.get_child_count())
	_populate_materials(stored)

func _populate_materials(items: Array) -> void:
	print("[CraftDetail] populate_begin items=", items.size(),
		" container_visible=", materials_container.visible,
		" children_to_clear=", materials_row.get_child_count())
	_clear_material_slots()
	if items.is_empty():
		print("[CraftDetail] populate_abort reason=no_stored_items container_visible=", materials_container.visible)
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
		print("[CraftDetail] stored_added item_id=", iid, " uid=", uid,
			" child_count=", materials_row.get_child_count())
		call_deferred("_log_material_slot_runtime", entry, "stored", iid)

	var matching_recipe: Dictionary = _find_order_recipe(items)
	if matching_recipe.is_empty():
		print("[CraftDetail] ghost_abort reason=no_matching_recipe stored_ids=", _count_stored_item_ids(items),
			" active_order_ids=", _get_active_order_item_ids().keys())
		return
	print("[CraftDetail] recipe_selected recipe_id=", int(matching_recipe.get("id", 0)),
		" result_id=", int(matching_recipe.get("result", 0)),
		" ingredients=", matching_recipe.get("ingredients", []))
	_show_output_slot_for_recipe(matching_recipe, "candidate_recipe")
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	var board_counts: Dictionary = _count_board_available_item_ids()
	print("[CraftDetail] material_availability stored_counts=", stored_counts,
		" board_counts=", board_counts)
	var has_ghost_material: bool = false
	for ingredient_variant in matching_recipe.get("ingredients", []):
		var ingredient_id: int = int(ingredient_variant)
		var remaining: int = int(stored_counts.get(ingredient_id, 0))
		if remaining > 0:
			stored_counts[ingredient_id] = remaining - 1
			continue
		var board_remaining: int = int(board_counts.get(ingredient_id, 0))
		if board_remaining > 0:
			board_counts[ingredient_id] = board_remaining - 1
			print("[CraftDetail] ghost_skipped reason=board_item_available item_id=",
				ingredient_id, " remaining_board=", board_counts[ingredient_id])
			continue
		var ghost_data: Dictionary = ConfigDatabase.get_item_data(ingredient_id)
		var ghost: ItemWidget = _build_material_icon(ghost_data, -1, true)
		has_ghost_material = true
		materials_row.add_child(ghost)
		print("[CraftDetail] ghost_added item_id=", ingredient_id,
			" data_found=", not ghost_data.is_empty(), " modulate_a=", ghost.modulate.a,
			" self_modulate_a=", ghost.self_modulate.a,
			" child_count=", materials_row.get_child_count())
		call_deferred("_log_material_slot_runtime", ghost, "ghost", ingredient_id)
	_set_output_slot_ghost(has_ghost_material)
	call_deferred("_log_output_slot_runtime", "materials_populated")

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

func _get_order_recipe_target_ids() -> Dictionary:
	var target_ids: Dictionary = _get_active_order_item_ids()
	if target_ids.is_empty():
		return target_ids
	var craftable_result_ids: Dictionary = {}
	for recipe_variant in _current_recipes:
		var recipe: Dictionary = recipe_variant as Dictionary
		var result_id: int = int(recipe.get("result", 0))
		if result_id > 0:
			craftable_result_ids[result_id] = true
	var changed: bool = true
	while changed:
		changed = false
		for recipe_variant in _current_recipes:
			var recipe: Dictionary = recipe_variant as Dictionary
			var result_id: int = int(recipe.get("result", 0))
			if not target_ids.has(result_id):
				continue
			for ingredient_variant in recipe.get("ingredients", []):
				var ingredient_id: int = int(ingredient_variant)
				if craftable_result_ids.has(ingredient_id) and not target_ids.has(ingredient_id):
					target_ids[ingredient_id] = true
					changed = true
	return target_ids

func _find_order_recipe(items: Array) -> Dictionary:
	var active_order_item_ids: Dictionary = _get_active_order_item_ids()
	var order_target_ids: Dictionary = _get_order_recipe_target_ids()
	var has_order_filter: bool = not order_target_ids.is_empty()
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	var board_counts: Dictionary = _count_board_available_item_ids()
	var best_recipe: Dictionary = {}
	var best_order_priority: int = 2147483647
	var fewest_missing: int = 2147483647
	var compatible_count: int = 0
	for recipe_variant in _current_recipes:
		var recipe: Dictionary = recipe_variant as Dictionary
		var result_id: int = int(recipe.get("result", 0))
		if has_order_filter and not order_target_ids.has(result_id):
			continue
		if int(board_counts.get(result_id, 0)) > 0:
			print("[CraftDetail] recipe_skipped reason=result_already_on_board result_id=",
				result_id, " board_count=", board_counts[result_id])
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
		compatible_count += 1
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
	print("[CraftDetail] recipe_match_summary stored_ids=", stored_counts,
		" order_filter=", has_order_filter, " active_order_ids=", active_order_item_ids.keys(),
		" order_target_ids=", order_target_ids.keys(),
		" board_counts=", board_counts,
		" candidates=", compatible_count, " selected_recipe_id=", int(best_recipe.get("id", 0)),
		" selected_result_id=", int(best_recipe.get("result", 0)),
		" selected_order_priority=", best_order_priority if not best_recipe.is_empty() else -1,
		" missing=", fewest_missing if not best_recipe.is_empty() else -1)
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
	return entry

func _log_material_slot_runtime(slot: ItemWidget, role: String, item_id: int) -> void:
	if slot == null or not is_instance_valid(slot):
		print("[CraftDetail] slot_runtime role=", role, " item_id=", item_id,
			" valid=false")
		return
	var icon: TextureRect = slot.get_node_or_null("IconRect") as TextureRect
	var click_button: Button = slot.get_node_or_null("ClickButton") as Button
	var icon_path: String = ""
	var icon_visible: bool = false
	var slot_rect: Rect2 = slot.get_global_rect()
	var container_rect: Rect2 = materials_container.get_global_rect()
	if icon != null:
		icon_visible = icon.visible
		if icon.texture != null:
			icon_path = icon.texture.resource_path
	print("[CraftDetail] slot_runtime role=", role, " item_id=", item_id,
		" valid=true visible=", slot.visible, " visible_in_tree=", slot.is_visible_in_tree(),
		" size=", slot.size, " global_rect=", slot_rect,
		" container_rect=", container_rect, " inside_container=", container_rect.encloses(slot_rect),
		" intersects_container=", container_rect.intersects(slot_rect),
	" child_index=", slot.get_index(), " child_count=", materials_row.get_child_count(),
		" modulate=", slot.modulate, " self_modulate=", slot.self_modulate,
		" icon_visible=", icon_visible, " icon_path=", icon_path,
		" click_mouse_filter=", click_button.mouse_filter if click_button != null else -1,
		" container_visible=", materials_container.visible,
		" container_visible_in_tree=", materials_container.is_visible_in_tree())

func _refresh_output_slot() -> void:
	var recipe: Dictionary = CraftingService.get_current_recipe(_current_item_data)
	var result_id: int = int(recipe.get("result", _current_item_data.get("_craft_result_id", 0)))
	print("[CraftDetail][OutputPreview] initial_refresh table_id=", int(_current_item_data.get("id", 0)),
		" state=", int(_current_item_data.get("_craft_state", CraftingService.TableState.IDLE)),
		" stored_count=", CraftingService.get_stored_items(_current_item_data).size(),
		" active_recipe_id=", int(recipe.get("id", 0)), " result_id=", result_id)
	_show_output_slot_for_result(result_id, "active_recipe")

func _show_output_slot_for_recipe(recipe: Dictionary, reason: String) -> void:
	_show_output_slot_for_result(int(recipe.get("result", 0)), reason)

func _show_output_slot_for_result(result_id: int, reason: String) -> void:
	if result_id <= 0:
		print("[CraftDetail][OutputPreview] hide reason=", reason, " result_id=", result_id)
		_hide_output_slot()
		return
	var result_data: Dictionary = ConfigDatabase.get_item_data(result_id)
	if result_data.is_empty():
		print("[CraftDetail][OutputPreview] hide reason=missing_result_data result_id=", result_id)
		_hide_output_slot()
		return
	_output_item_id = result_id
	output_slot.setup(result_data)
	output_slot.set_clickable(false)
	_set_output_slot_ghost(false)
	output_label.show()
	output_slot.show()
	print("[CraftDetail][OutputPreview] show reason=", reason, " result_id=", result_id,
		" visible=", output_slot.visible, " alpha=", output_slot.modulate.a)

func _set_output_slot_ghost(ghost: bool) -> void:
	if output_slot == null:
		return
	var previous_alpha: float = output_slot.modulate.a
	output_slot.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA if ghost else 1.0)
	output_slot.self_modulate = Color.WHITE
	print("[CraftDetail][OutputPreview] ghost_apply requested=", ghost,
		" output_id=", _output_item_id, " visible=", output_slot.visible,
		" alpha_before=", previous_alpha, " alpha_after=", output_slot.modulate.a)

func _log_output_slot_runtime(reason: String) -> void:
	if output_slot == null or not is_instance_valid(output_slot):
		print("[CraftDetail][OutputPreview] runtime reason=", reason, " valid=false")
		return
	var icon: TextureRect = output_slot.get_node_or_null("IconRect") as TextureRect
	var icon_path: String = ""
	if icon != null and icon.texture != null:
		icon_path = icon.texture.resource_path
	print("[CraftDetail][OutputPreview] runtime reason=", reason,
		" output_id=", _output_item_id, " visible=", output_slot.visible,
		" visible_in_tree=", output_slot.is_visible_in_tree(),
		" modulate=", output_slot.modulate, " self_modulate=", output_slot.self_modulate,
		" icon_modulate=", icon.modulate if icon != null else Color.WHITE,
		" icon_self_modulate=", icon.self_modulate if icon != null else Color.WHITE,
		" icon_path=", icon_path, " rect=", output_slot.get_global_rect())

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
		var state: int = _current_item_data.get("_craft_state", CraftingService.TableState.IDLE)
		if state != CraftingService.TableState.CRAFTING:
			_stop_countdown_timer()
			_hide_speedup_button()
			return
		var remaining: float = CraftingService.get_remaining_craft_seconds(_current_item_data)
		if remaining > 0:
			status_label.text = "制作中… %d秒" % int(ceil(remaining))
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
	print("[CraftDetail][Launcher] detail_state item_id=", int(_current_item_data.get("id", 0)),
		" charges=", charges, "/", max_charges, " remaining_ms=", remaining_ms,
		" is_recharging=", is_recharging)
	if not is_recharging:
		_stop_countdown_timer()
		_hide_speedup_button()
		status_label.hide()
		desc_label.show()
		return
	desc_label.hide()
	status_label.text = "充能中… %s" % format_countdown_hms(remaining)
	status_label.show()
	_refresh_speedup_button("launcher", remaining)
	if _countdown_timer == null or not is_instance_valid(_countdown_timer):
		_start_countdown_timer()

static func format_countdown_hms(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(ceil(seconds)))
	var hours: int = int(total_seconds / 3600)
	var minutes: int = int((total_seconds % 3600) / 60)
	var remaining_seconds: int = total_seconds % 60
	var parts: Array[String] = []
	if hours > 0:
		parts.append("%d时" % hours)
	if minutes > 0:
		parts.append("%d分" % minutes)
	if remaining_seconds > 0 or parts.is_empty():
		parts.append("%d秒" % remaining_seconds)
	return "".join(parts)

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

func _on_table_state_changed(table_item: Dictionary, state: int) -> void:
	if not _current_item_data.is_empty() and _current_item_data.get("_uid", 0) == table_item.get("_uid", -1):
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
