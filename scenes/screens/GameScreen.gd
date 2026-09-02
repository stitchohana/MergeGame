class_name GameScreen extends BaseScreen

@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var grid_view: GridView = $GridView
@onready var requirement_list: RequirementList = $RequirementList
@onready var battle_btn: Button = $BattleButton
@onready var home_btn: Button = $HomeButton
@onready var shop_btn: Button = $ShopButton
@onready var pouch_zone: PouchDropZone = $PouchDropZone
@onready var pending_bar: PendingRewardBar
@onready var top_bar: TopBar = $TopBar

var _pending_item_ids: Array = []
var _meridian_submit_pending: bool = false
var _display_index_map: Array = []
var _pending_stamina_uid: int = -1
var _pending_spirit_stone_uid: int = -1
var _item_use_pending: bool = false
var _load_token: int = -1
var _pending_order_animation: Dictionary = {}
var _order_animation_input_token: int = -1
var _is_initial_game_load: bool = true
var _initial_order_reset_token: int = 0
var _require_refresh_queued: bool = false

func _ready() -> void:
	randomize()

	GridManager.grid_updated.connect(_on_grid_changed)
	grid_view.set_pouch_zone(pouch_zone)
	requirement_list.setup_pending_reward_bar(grid_view)


	EventBus.restart_requested.connect(_on_restart)

	detail_panel.material_clicked.connect(_on_material_clicked)
	detail_panel.material_source_requested.connect(_on_material_source_requested)
	grid_view.item_clicked.connect(_on_item_clicked)
	if not CraftingService.table_state_changed.is_connected(_on_craft_table_state_changed):
		CraftingService.table_state_changed.connect(_on_craft_table_state_changed)

	grid_view.item_use_requested.connect(_on_item_use_requested)
	CloudService.board_switch_confirmed.connect(_on_main_board_switch_confirmed)
	CloudService.board_switch_rejected.connect(_on_main_board_switch_rejected)
	CloudService.craft_remove_confirmed.connect(_on_craft_remove_confirmed)
	CloudService.craft_remove_rejected.connect(_on_craft_remove_rejected)
	CloudService.stamina_restore_confirmed.connect(_on_stamina_restore_confirmed)
	CloudService.stamina_restore_rejected.connect(_on_stamina_restore_rejected)
	CloudService.spirit_stone_consume_confirmed.connect(_on_spirit_stone_consume_confirmed)
	CloudService.spirit_stone_consume_rejected.connect(_on_spirit_stone_consume_rejected)
	CloudService.state_loaded.connect(_on_state_loaded_for_orders)
	CultivationService.stage_changed.connect(_on_stage_changed_for_meridian)
	CloudService.breakthrough_confirmed.connect(func(_r): _item_use_pending = false)
	CloudService.breakthrough_rejected.connect(func(_r): _item_use_pending = false)
	CloudService.exp_pill_consume_confirmed.connect(func(_r): _item_use_pending = false)
	CloudService.exp_pill_consume_rejected.connect(func(_r): _item_use_pending = false)

	battle_btn.pressed.connect(_on_battle_pressed)
	home_btn.pressed.connect(_on_home_pressed)
	if shop_btn:
		shop_btn.pressed.connect(_on_shop_pressed)
	requirement_list.complete_clicked.connect(_on_meridian_complete)
	_refresh_meridian()
	_setup_extras()

	print("[GameScreen] Game initialized!")

func _on_state_loaded_for_orders(state: Dictionary) -> void:
	if not state.has("meridian_acupoints"):
		return
	var acupoints: Array = state.get("meridian_acupoints", []) as Array
	GameState.meridian_acupoints = acupoints.duplicate(true)
	GameState.meridian_threshold_idx = int(state.get("meridian_threshold_idx", GameState.meridian_threshold_idx))
	if is_inside_tree():
		_display_meridian()

func _setup_extras() -> void:
	# Design order: cultivation character -> order cards.
	for child: Node in requirement_list.container.get_children():
		if child is CharacterEntry:
			requirement_list.container.move_child(child, 0)
			return
	var character_entry: CharacterEntry = preload("res://scenes/ui/character/CharacterEntry.tscn").instantiate() as CharacterEntry
	requirement_list.container.add_child(character_entry)
	requirement_list.container.move_child(character_entry, 0)

func on_enter() -> void:
	print("[GameScreen] on_enter START")
	_initial_order_reset_token += 1
	_is_initial_game_load = true
	requirement_list.reset_scroll_to_start()
	GameState.current_board_type = Constants.BoardType.MAIN
	if not GridManager.grid_updated.is_connected(_on_grid_changed):
		GridManager.grid_updated.connect(_on_grid_changed)
	GridManager.init_grid(Constants.BoardType.MAIN)
	grid_view.visible = false
	print("[GameScreen] grid_view.visible=false, calling LoadingManager.begin")
	_load_token = LoadingManager.begin("加载棋盘数据...")
	if not CloudService.online and not GameState.main_grid_cache.is_empty():
		_render_main_grid_cache()
	if not CloudService.online and _load_token > 0:
		grid_view.visible = true
		LoadingManager.end(_load_token)
		_load_token = -1
	print("[GameScreen] _load_token=", _load_token, " online=", CloudService.online)
	if CloudService.online:
		CloudService.submit_board_switch(Constants.BoardType.MAIN)
	else:
		_schedule_initial_order_list_reset()
	requirement_list.reset_scroll_to_start()
	print("[GameScreen] on_enter DONE")

func _render_main_grid_cache() -> void:
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)

func on_exit() -> void:
	_initial_order_reset_token += 1
	_end_order_animation_input_lock()
	if GridManager.grid_updated.is_connected(_on_grid_changed):
		GridManager.grid_updated.disconnect(_on_grid_changed)
	grid_view._clear_all_item_nodes()
	detail_panel.clear()

func _on_main_board_switch_confirmed(result: Dictionary) -> void:
	print("[GameScreen] _on_main_board_switch_confirmed rebuilding board: board_type=", result.get("board_type", -1), " items=", result.get("grid", []).size(), " caller=", get_stack())
	if result.get("board_type", -1) != Constants.BoardType.MAIN:
		print("[GameScreen] board_type mismatch, returning")
		return
	GameState.main_grid_cache = result.get("grid", [])
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)
	grid_view.visible = true
	requirement_list.reset_scroll_to_start()
	_schedule_initial_order_list_reset()
	print("[GameScreen] grid_view.visible=true, ending token=", _load_token)
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1
	print("[GameScreen] board switch done")

func _on_main_board_switch_rejected(_reason: String) -> void:
	if not GameState.main_grid_cache.is_empty():
		_render_main_grid_cache()
	requirement_list.reset_scroll_to_start()
	_schedule_initial_order_list_reset()
	grid_view.visible = true
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1

func _schedule_initial_order_list_reset() -> void:
	_initial_order_reset_token += 1
	var reset_token: int = _initial_order_reset_token
	call_deferred("_finish_initial_order_list_reset", reset_token)

func _finish_initial_order_list_reset(reset_token: int) -> void:
	await get_tree().process_frame
	if reset_token != _initial_order_reset_token or not is_inside_tree():
		return
	requirement_list.reset_scroll_to_start()
	await get_tree().process_frame
	if reset_token != _initial_order_reset_token or not is_inside_tree():
		return
	_is_initial_game_load = false
	print("[GameScreen] initial order list locked to character area")

func _allow_available_order_focus() -> bool:
	return not _is_initial_game_load

func _on_material_clicked(uid: int, item_id: int) -> void:
	var table_pos := detail_panel.get_current_craft_pos()
	var table_item: Variant = GridManager.get_item(table_pos)
	if table_item == null:
		return
	var table_uid: int = table_item.get("_uid", 0)
	grid_view.run_after_action_sync(func():
		var synced_table_pos: Vector2i = GridManager.find_pos_by_uid(table_uid)
		if synced_table_pos.x < 0:
			EventBus.show_toast.emit("制作台状态已变化，请重试")
			return
		_submit_material_remove(synced_table_pos, uid, item_id)
	)

func _on_material_source_requested(item_id: int) -> void:
	if item_id <= 0:
		return
	requirement_list.show_item_source(item_id)

func _submit_material_remove(table_pos: Vector2i, _uid: int, item_id: int) -> void:
	var spawn_pos := GridManager.find_nearest_empty(table_pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满，无法取出材料")
		return
	if CloudService.online:
		grid_view.queue_craft_remove(table_pos, item_id, spawn_pos)

func _on_craft_remove_confirmed(result: Dictionary) -> void:
	var table_col: int = result.get("table_col", -1)
	var table_row: int = result.get("table_row", -1)
	var removed_id: int = result.get("removed_id", 0)
	var removed_uid: int = result.get("removed_uid", 0)
	var target_col: int = result.get("target_col", -1)
	var target_row: int = result.get("target_row", -1)
	if removed_id <= 0:
		return
	var table_item: Dictionary = GridManager.get_item(Vector2i(table_col, table_row))
	if table_item.is_empty():
		return
	CraftingService.remove_ingredient(table_item, removed_id)
	var full_data := ConfigDatabase.get_item_data(removed_id)
	var new_item: Dictionary = full_data.duplicate(true) if not full_data.is_empty() else {"id": removed_id}
	new_item["_uid"] = removed_uid
	GridManager.add_item(new_item, Vector2i(target_col, target_row))
	detail_panel._refresh_materials()

func _on_craft_remove_rejected(reason: String) -> void:
	EventBus.show_toast.emit("取出材料失败：" + reason)


func _on_item_use_requested(item_data: Dictionary, grid_pos: Vector2i) -> void:
	if _item_use_pending:
		return
	var effect_type: int = int(item_data.get("effect_type", 0))
	if effect_type <= 0:
		return
	var uid: int = item_data.get("_uid", 0)
	_item_use_pending = true
	match effect_type:
		Constants.EffectType.BREAKTHROUGH:
				print("[GameScreen] breakthrough click: uid=" + str(uid) + " pos=" + str(grid_pos))
				if uid <= 0:
					EventBus.show_toast.emit("物品数据异常，请重新登录")
					print("[GameScreen] breakthrough BLOCKED: uid=" + str(uid))
					return
				CultivationService.try_breakthrough(uid)
		Constants.EffectType.EXP:
			CultivationService.consume_exp_pill(item_data.get("id", 0), uid)
		Constants.EffectType.STAMINA:
			_pending_stamina_uid = uid
			CloudService.submit_restore_stamina(item_data.get("id", 0), uid)
		Constants.EffectType.SPIRIT_STONES:
			_pending_spirit_stone_uid = uid
			CloudService.submit_consume_spirit_stone(item_data.get("id", 0), uid)
		Constants.EffectType.QI:
			EventBus.show_toast.emit("灵力恢复")
		Constants.EffectType.QI:
			EventBus.show_toast.emit("灵力恢复")
		_:
			EventBus.show_toast.emit("此物品无法在此使用")

func _on_item_clicked(item_data: Dictionary, grid_pos: Vector2i) -> void:
	detail_panel.show_item(item_data, grid_pos)

func _on_home_pressed() -> void:
	EventBus.screen_change_requested.emit("home")

func _on_battle_pressed() -> void:
	GameState.previous_screen_name = "game"
	EventBus.screen_change_requested.emit("battle")

func _on_shop_pressed() -> void:
	var popup := preload("res://scenes/ui/shop/ShopPopup.tscn").instantiate() as ShopPopup
	UIManager.show_popup(popup)

func _on_restart() -> void:
	GameState.reset()
	GridManager.init_grid()

	detail_panel.clear()
	if CloudService.online:
		CloudService.fetch_state()

func _on_grid_changed() -> void:
	_queue_requirement_refresh()

func _on_craft_table_state_changed(_table_item: Dictionary, state: int) -> void:
	_refresh_requirement_crafting_badges()
	# IDLE is followed by a grid update when a material/result is moved.
	# Wait for that update so retrieval does not briefly re-mark ingredients.
	if state == CraftingService.TableState.IDLE:
		return
	_queue_requirement_refresh()

func _queue_requirement_refresh() -> void:
	if _require_refresh_queued:
		return
	_require_refresh_queued = true
	call_deferred("_flush_requirement_refresh")

func _flush_requirement_refresh() -> void:
	_require_refresh_queued = false
	if not is_inside_tree():
		return
	_refresh_requirement_buttons()

func _get_reserved_crafting_item_ids() -> Dictionary:
	var reserved_ids: Dictionary = {}
	for entry: Dictionary in GridManager.get_all_items():
		var table_item: Dictionary = entry.get("data", {}) as Dictionary
		if int(table_item.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		for stored_variant: Variant in table_item.get("_craft_stored", []):
			if not stored_variant is Dictionary:
				continue
			var stored_item: Dictionary = stored_variant as Dictionary
			var stored_id: int = int(stored_item.get("id", 0))
			if stored_id > 0:
				reserved_ids[stored_id] = true
		var craft_state: int = int(table_item.get("_craft_state", CraftingService.TableState.IDLE))
		if craft_state != CraftingService.TableState.CRAFTING and craft_state != CraftingService.TableState.READY:
			continue
		var active_recipe: Dictionary = table_item.get("_craft_recipe", {}) as Dictionary
		for ingredient_variant: Variant in active_recipe.get("ingredients", []):
			var ingredient_id: int = int(ingredient_variant)
			if ingredient_id > 0:
				reserved_ids[ingredient_id] = true
	return reserved_ids

func _get_finished_order_item_counts() -> Dictionary:
	var finished_counts: Dictionary = {}
	var board_item_ids: Array[int] = []
	var ready_result_ids: Array[int] = []
	var known_positions: Dictionary = {}
	for entry: Dictionary in GridManager.get_all_items():
		var item_data: Dictionary = entry.get("data", {}) as Dictionary
		var entry_pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
		known_positions["%d,%d" % [entry_pos.x, entry_pos.y]] = true
		var item_id: int = int(item_data.get("id", 0))
		var item_type: int = int(item_data.get("type", 0))
		# An order product can inherit an immovable flag from its board snapshot.
		# It is still an existing product; only crafting facilities are excluded.
		if item_id > 0 and item_type != Constants.ItemType.CRAFTING:
			board_item_ids.append(item_id)
			finished_counts[item_id] = int(finished_counts.get(item_id, 0)) + 1
		if int(item_data.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		if int(item_data.get("_craft_state", CraftingService.TableState.IDLE)) != CraftingService.TableState.READY:
			continue
		var result_id: int = int(item_data.get("_craft_result_id", 0))
		if result_id <= 0:
			var recipe: Dictionary = item_data.get("_craft_recipe", {}) as Dictionary
			result_id = int(recipe.get("result", 0))
		if result_id > 0:
			ready_result_ids.append(result_id)
			finished_counts[result_id] = int(finished_counts.get(result_id, 0)) + 1
	var ui_fallback_item_ids: Array[int] = []
	if grid_view != null and is_instance_valid(grid_view):
		for node_key: Variant in grid_view._item_nodes.keys():
			if known_positions.has(str(node_key)):
				continue
			var node: GridItem = grid_view._item_nodes[node_key] as GridItem
			if node == null or not is_instance_valid(node):
				continue
			var node_item_id: int = int(node.item_data.get("id", 0))
			var node_item_type: int = int(node.item_data.get("type", 0))
			if node_item_id <= 0 or node_item_type == Constants.ItemType.CRAFTING:
				continue
			ui_fallback_item_ids.append(node_item_id)
			finished_counts[node_item_id] = int(finished_counts.get(node_item_id, 0)) + 1
	print("[Require] finished_scan board_item_ids=", board_item_ids,
		" ready_result_ids=", ready_result_ids,
		" ui_fallback_item_ids=", ui_fallback_item_ids,
		" finished_counts=", finished_counts)
	return finished_counts

func _count_grid_item(item_id: int) -> int:
	var count := 0
	for entry in GridManager.get_all_items():
		var item_data: Dictionary = entry.data
		if not bool(item_data.get("immovable", false)) and int(item_data.get("id", 0)) == item_id:
			count += 1
	return count

func _check_can_complete(req: Dictionary) -> bool:
	return _get_requirement_priority(req) == 2

func _get_requirement_priority(req: Dictionary) -> int:
	var items: Array = req.get("items", [])
	if items.is_empty():
		return 0
	var required_counts: Dictionary = {}
	for item_variant: Variant in items:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant as Dictionary
		var item_id: int = int(item.get("item_id", 0))
		if item_id <= 0:
			continue
		required_counts[item_id] = int(required_counts.get(item_id, 0)) + 1
	if required_counts.is_empty():
		return 0
	var matched_count: int = 0
	var required_count: int = 0
	for item_id_variant: Variant in required_counts.keys():
		var item_id: int = int(item_id_variant)
		var item_required_count: int = int(required_counts[item_id])
		required_count += item_required_count
		matched_count += mini(_count_grid_item(item_id), item_required_count)
	if matched_count >= required_count:
		return 2
	if matched_count > 0:
		return 1
	return 0

func _refresh_requirement_buttons() -> void:
	_refresh_required_indicators()
	_refresh_requirement_item_selection()
	_refresh_requirement_crafting_badges()
	for i in range(_display_index_map.size()):
		var data_index: int = _display_index_map[i]
		if data_index < 0 or data_index >= GameState.meridian_acupoints.size():
			continue
		var req: Dictionary = GameState.meridian_acupoints[data_index]
		if not req.get("completed", false):
			var allow_available_focus: bool = _allow_available_order_focus()
			requirement_list.set_entry_priority(i, _get_requirement_priority(req), allow_available_focus)

func _refresh_requirement_item_selection() -> void:
	var present_item_ids: Dictionary = {}
	for entry in GridManager.get_all_items():
		var item_data: Dictionary = entry.data
		if bool(item_data.get("immovable", false)):
			continue
		var item_id: int = int(item_data.get("id", 0))
		if item_id > 0:
			present_item_ids[item_id] = true
	requirement_list.refresh_item_selection(present_item_ids)


func _refresh_requirement_crafting_badges() -> void:
	requirement_list.refresh_item_crafting(_get_crafting_result_item_ids())


func _get_crafting_result_item_ids() -> Dictionary:
	var crafting_item_ids: Dictionary = {}
	for entry in GridManager.get_all_items():
		var table_item: Dictionary = entry.get("data", {})
		if int(table_item.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		if int(table_item.get("_craft_state", CraftingService.TableState.IDLE)) != CraftingService.TableState.CRAFTING:
			continue
		var result_id: int = int(table_item.get("_craft_result_id", 0))
		if result_id <= 0:
			var recipe_variant: Variant = table_item.get("_craft_recipe", {})
			if recipe_variant is Dictionary:
				result_id = int((recipe_variant as Dictionary).get("result", 0))
		if result_id > 0:
			crafting_item_ids[result_id] = true
	return crafting_item_ids


func _refresh_required_indicators() -> void:
	if GameState.current_board_type != Constants.BoardType.MAIN:
		return
	var required_ids: Dictionary = {}
	var finished_order_item_ids: Dictionary = {}
	var reserved_crafting_ids: Dictionary = _get_reserved_crafting_item_ids()
	var finished_order_item_counts: Dictionary = _get_finished_order_item_counts()
	var order_targets: Array[int] = []
	print("[Require] refresh_begin board_type=", GameState.current_board_type,
		" grid_count=", GridManager.count_items(), " ui_node_count=", grid_view._item_nodes.size(),
		" finished_counts=", finished_order_item_counts)
	# An order product already on the board shows require itself. Its recipe
	# materials are already satisfied, so do not mark the material tree for that
	# order. Missing order products still collect every required material below.
	for req_variant: Variant in GameState.meridian_acupoints:
		var req: Dictionary = req_variant as Dictionary
		if bool(req.get("completed", false)):
			continue
		for it_variant: Variant in req.get("items", []):
			var it: Dictionary = it_variant as Dictionary
			var item_id: int = int(it.get("item_id", 0))
			order_targets.append(item_id)
			var finished_count: int = int(finished_order_item_counts.get(item_id, 0))
			if finished_count > 0:
				finished_order_item_counts[item_id] = finished_count - 1
				finished_order_item_ids[item_id] = true
				required_ids[item_id] = true
				print("[Require] target_skip_finished item_id=", item_id,
					" remaining_finished=", finished_count - 1,
					" mark_order_product=true")
				continue
			var required_before: Dictionary = required_ids.duplicate()
			_collect_recipe_material_ids(item_id, required_ids, reserved_crafting_ids)
			var target_added_ids: Array[int] = []
			for required_variant: Variant in required_ids.keys():
				if not required_before.has(required_variant):
					target_added_ids.append(int(required_variant))
			print("[Require] target_collect target_id=", item_id,
				" added_ids=", target_added_ids)
	print("[Require] refresh order_targets=", order_targets,
		" reserved_ids=", reserved_crafting_ids.keys(),
		" required_ids=", required_ids.keys())

	# Clear every live UI node first. A node can temporarily survive a grid
	# mutation while its position map is being reconciled; leaving it out of the
	# GridManager loop would otherwise preserve a stale require icon.
	if grid_view != null and is_instance_valid(grid_view):
		for node_key: Variant in grid_view._item_nodes.keys():
			var live_node: GridItem = grid_view._item_nodes[node_key] as GridItem
			if live_node != null and is_instance_valid(live_node):
				live_node.set_required(false)

	# Update all grid items
	for entry in GridManager.get_all_items():
		var node: GridItem = grid_view._item_nodes.get("%d,%d" % [entry.pos.x, entry.pos.y])
		if node and is_instance_valid(node):
			var item_data: Dictionary = entry.data
			var item_id: int = int(item_data.get("id", 0))
			var should_require: bool = (
				(finished_order_item_ids.has(item_id)
					or (not bool(item_data.get("immovable", false))
						and required_ids.has(item_id)))
			)
			node.set_required(should_require)
			if should_require:
				print("[Require] apply pos=", entry.pos, " item_id=", item_id, " required=true")
func _collect_recipe_material_ids(result_id: int, required_ids: Dictionary, reserved_ids: Dictionary) -> void:
	if result_id <= 0:
		return
	for recipe_variant: Variant in ConfigDatabase.get_recipes_for_result(result_id):
		if not recipe_variant is Dictionary:
			continue
		var recipe: Dictionary = recipe_variant as Dictionary
		for ingredient_variant: Variant in recipe.get("ingredients", []):
			_collect_recipe_dependency_ids(int(ingredient_variant), required_ids, reserved_ids)

func _collect_recipe_dependency_ids(item_id: int, required_ids: Dictionary, reserved_ids: Dictionary) -> void:
	if item_id <= 0 or required_ids.has(item_id) or reserved_ids.has(item_id):
		return
	required_ids[item_id] = true
	for recipe_variant: Variant in ConfigDatabase.get_recipes_for_result(item_id):
		if not recipe_variant is Dictionary:
			continue
		var recipe: Dictionary = recipe_variant as Dictionary
		for ingredient_variant: Variant in recipe.get("ingredients", []):
			_collect_recipe_dependency_ids(int(ingredient_variant), required_ids, reserved_ids)

func _refresh_meridian() -> void:
	if not GameState.meridian_acupoints.is_empty():
		_display_meridian()
		return
	if CloudService.online:
		CloudService.meridian_refresh_confirmed.connect(_on_meridian_refresh_confirmed, CONNECT_ONE_SHOT)
		CloudService.submit_meridian_refresh()

func _on_meridian_refresh_confirmed(result: Dictionary) -> void:
	GameState.meridian_acupoints = result.get("acupoints", [])
	GameState.meridian_threshold_idx = result.get("threshold_idx", 0)
	_display_meridian()

func _display_meridian() -> void:
	var completed: int = 0
	_display_index_map.clear()
	for req in GameState.meridian_acupoints:
		if req.get("completed", false):
			completed += 1
	requirement_list.set_title("修炼需求 %d/%d" % [completed, GameState.meridian_acupoints.size()])
	var display_reqs: Array = []
	var priority_indices: Dictionary = {}
	for i in range(GameState.meridian_acupoints.size()):
		var req: Dictionary = GameState.meridian_acupoints[i]
		if not req.get("completed", false):
			var display_index: int = display_reqs.size()
			display_reqs.append(req.duplicate())
			_display_index_map.append(i)
			priority_indices[display_index] = _get_requirement_priority(req)
	requirement_list.set_requirements(display_reqs, priority_indices)
	_refresh_requirement_buttons()

func _on_meridian_complete(display_index: int) -> void:
	if _meridian_submit_pending:
		return
	if display_index < 0 or display_index >= _display_index_map.size():
		return
	var data_index: int = _display_index_map[display_index]
	if data_index < 0 or data_index >= GameState.meridian_acupoints.size():
		return
	var requirement: Dictionary = GameState.meridian_acupoints[data_index]
	if bool(requirement.get("breakthrough_order", false)):
		GameState.pending_breakthrough_prompt = true
		EventBus.screen_change_requested.emit("home")
		return
	_pending_order_animation.clear()
	_capture_order_animation(display_index)
	grid_view.run_after_action_sync(_submit_meridian_complete.bind(display_index))

func _capture_order_animation(display_index: int) -> void:
	var entries: Array[RequirementEntry] = requirement_list.get_order_entries()
	var entry: RequirementEntry = null
	for candidate in entries:
		if candidate.get_display_index() == display_index:
			entry = candidate
			break
	if entry == null:
		print("[GameScreen] order animation: entry not found display_index=", display_index, " entries=", entries.size())
		return
	var sources: Array[Dictionary] = []
	var used_grid_keys: Dictionary = {}
	var required_ids: Array = []
	for item_variant in entry._items_setup:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		var item_id: int = int(item.get("item_id", 0))
		if item_id <= 0:
			continue
		required_ids.append(item_id)
		var source: Dictionary = _find_grid_item_source(item_id, used_grid_keys)
		if not source.is_empty():
			source["item_id"] = item_id
			source["to"] = entry.get_item_widget_center(item_id)
			sources.append(source)
	var previous_positions: Dictionary = {}
	# Capture the actual visual order because RequirementList may sort entries by
	# availability independently of their display/data indices.
	for visual_index in range(entries.size()):
		var old_entry: RequirementEntry = entries[visual_index]
		previous_positions[visual_index] = old_entry.position
	var completed_visual_index: int = entries.find(entry)
	_pending_order_animation = {"entry": entry, "sources": sources, "required_ids": required_ids, "completed_display_index": display_index, "completed_visual_index": completed_visual_index, "previous_positions": previous_positions, "start_qi": CultivationService.current_qi}
	print("[GameScreen] order animation: captured index=", display_index, " required_ids=", required_ids, " sources=", sources.size())
	if sources.is_empty():
		print("[GameScreen] order animation: no matching board items for ids=", required_ids, " grid_nodes=", grid_view._item_nodes.size())

func _find_grid_item_source(item_id: int, used_grid_keys: Dictionary) -> Dictionary:
	for key in grid_view._item_nodes:
		var key_string: String = str(key)
		if used_grid_keys.has(key_string):
			continue
		var node: GridItem = grid_view._item_nodes[key] as GridItem
		if node == null or not is_instance_valid(node) or bool(node.item_data.get("immovable", false)) or int(node.item_data.get("id", 0)) != item_id:
			continue
		var icon_rect: TextureRect = node.get_node_or_null("IconRect") as TextureRect
		var texture: Texture2D = icon_rect.texture if icon_rect else null
		var item_center: Vector2 = icon_rect.get_global_rect().get_center() if icon_rect else node.get_global_rect().get_center()
		used_grid_keys[key_string] = true
		return {"from": item_center, "texture": texture, "node": node, "grid_key": key_string}
	for grid_entry in GridManager.get_all_items():
		var item_data: Dictionary = grid_entry.data
		if not bool(item_data.get("immovable", false)) and int(item_data.get("id", 0)) == item_id:
			var fallback_center: Vector2 = grid_view.to_global(Vector2(grid_entry.pos.x * Constants.CELL_STEP, grid_entry.pos.y * Constants.CELL_STEP) + Vector2(Constants.CELL_SIZE * 0.5, Constants.CELL_SIZE * 0.5))
			return {"from": fallback_center}
	return {}

func _build_order_sources(entry: RequirementEntry, required_ids: Array) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var used_grid_keys: Dictionary = {}
	for item_id_variant in required_ids:
		var item_id: int = int(item_id_variant)
		if item_id <= 0:
			continue
		var source: Dictionary = _find_grid_item_source(item_id, used_grid_keys)
		if source.is_empty():
			continue
		source["item_id"] = item_id
		source["to"] = entry.get_item_widget_center(item_id)
		sources.append(source)
	return sources

func _submit_meridian_complete(display_index: int) -> void:
	if display_index < 0 or display_index >= _display_index_map.size():
		return
	var data_index: int = _display_index_map[display_index]
	var req: Dictionary = GameState.meridian_acupoints[data_index]
	if req.get("completed", false):
		return
	_pending_item_ids = req.get("item_ids", [])
	if CloudService.online:
		if _meridian_submit_pending:
			return
		if top_bar:
			top_bar.set_qi_updates_suppressed(true)
		_meridian_submit_pending = true
		CloudService.meridian_complete_confirmed.connect(_on_meridian_confirmed, CONNECT_ONE_SHOT)
		CloudService.meridian_complete_rejected.connect(_on_meridian_rejected, CONNECT_ONE_SHOT)
		CloudService.submit_meridian_complete(data_index, _pending_item_ids)

func _on_meridian_confirmed(result: Dictionary) -> void:
	if CloudService.meridian_complete_rejected.is_connected(_on_meridian_rejected):
		CloudService.meridian_complete_rejected.disconnect(_on_meridian_rejected)
	_begin_order_animation_input_lock()
	var animation: Dictionary = _pending_order_animation.duplicate(true)
	_pending_order_animation.clear()
	var animation_entry: RequirementEntry = animation.get("entry") as RequirementEntry
	var sources: Array = animation.get("sources", [])
	if sources.is_empty() and animation_entry and is_instance_valid(animation_entry):
		var required_ids: Array = animation.get("required_ids", [])
		if required_ids.is_empty():
			required_ids = _pending_item_ids
		sources = _build_order_sources(animation_entry, required_ids)
		animation["sources"] = sources
		print("[GameScreen] order animation: recovered sources=", sources.size(), " required_ids=", required_ids)
	print("[GameScreen] order animation: confirmed sources=", animation.get("sources", []).size(), " qi=", result.get("qi_gained", 0))
	var cult: Dictionary = result.get("cultivation", {})
	animation["target_qi"] = int(cult.get("current_qi", CultivationService.current_qi))
	var qi_from: Vector2 = top_bar.global_position
	if animation_entry and is_instance_valid(animation_entry):
		qi_from = animation_entry.get_global_rect().get_center()
	animation["qi_from"] = qi_from
	await _play_order_completion_animation(animation)
	if top_bar:
		top_bar.set_qi_updates_suppressed(false)
	_meridian_submit_pending = false

	var server_grid: Array = result.get("grid", [])
	print("[GameScreen] meridian confirmed, server grid size=", server_grid.size())
	grid_view.set_skip_animations(true)
	GridManager.init_grid()
	GridManager.populate_from_server(server_grid)
	grid_view.set_skip_animations(false)

	if not cult.is_empty():
		CultivationService.deserialize(cult)

	# Server returns updated list (completed order removed, new order added)
	GameState.meridian_acupoints = result.get("meridian_acupoints", [])
	_display_meridian()
	await requirement_list.animate_reflow_from(
		animation.get("previous_positions", {}),
		int(animation.get("completed_visual_index", -1))
	)
	var qi_animation_duration: float = _play_order_qi_animation(animation, int(result.get("qi_gained", 0)))
	if qi_animation_duration > 0.0:
		await get_tree().create_timer(qi_animation_duration + 0.05).timeout
	await get_tree().create_timer(0.3).timeout
	_end_order_animation_input_lock()

	var qi_gained: int = result.get("qi_gained", 0)
	if qi_gained > 0:
		EventBus.show_toast.emit("灵力 +%d" % qi_gained)
		if result.get("qi_full", false):
			EventBus.show_toast.emit("灵力已满，尽快使用！")



func _begin_order_animation_input_lock() -> void:
	if _order_animation_input_token >= 0:
		return
	_order_animation_input_token = UIManager.begin_input_block("order_completion")


func _end_order_animation_input_lock() -> void:
	if _order_animation_input_token < 0:
		return
	UIManager.end_input_block(_order_animation_input_token)
	_order_animation_input_token = -1


func _play_order_completion_animation(animation: Dictionary) -> void:
	if animation.is_empty():
		return
	var sources: Array = animation.get("sources", [])
	if not bool(animation.get("materials_played", false)) and not sources.is_empty():
		var hide_duration: float = Constants.ORDER_SOURCE_HIDE_DURATION
		var fly_duration: float = Constants.ORDER_ITEM_FLY_DURATION
		print("[GameScreen] order animation: hide sources=", sources.size(), " hide_duration=", hide_duration, " fly_duration=", fly_duration)
		_hide_order_source_items(animation, hide_duration)
		await get_tree().create_timer(hide_duration).timeout
		_play_order_material_fly(animation, fly_duration)
		await get_tree().create_timer(fly_duration).timeout
	var entry: RequirementEntry = animation.get("entry") as RequirementEntry
	if entry and is_instance_valid(entry):
		print("[GameScreen] order animation: empty state index=", entry.get_display_index())
		entry.show_completed_empty_state()

func _play_order_qi_animation(animation: Dictionary, qi_gained: int) -> float:
	if qi_gained <= 0 or top_bar == null:
		return 0.0
	var target_qi: int = int(animation.get("target_qi", CultivationService.current_qi))
	var start_qi: int = int(animation.get("start_qi", target_qi - qi_gained))
	top_bar.qi_resource.animate_value_from(start_qi, target_qi)
	var qi_icon: TextureRect = top_bar.qi_resource.get_node_or_null("Icon") as TextureRect
	if qi_icon == null or qi_icon.texture == null:
		return 0.0
	var from_pos: Vector2 = top_bar.global_position
	var stored_from: Variant = animation.get("qi_from", null)
	if stored_from is Vector2:
		from_pos = stored_from
	var to_pos: Vector2 = qi_icon.get_global_rect().get_center()
	_play_qi_reward_pile(qi_icon.texture, from_pos, to_pos)
	return Constants.QI_REWARD_FLY_DURATION + float(maxi(Constants.QI_REWARD_FLY_COUNT - 1, 0)) * Constants.QI_REWARD_FLY_STAGGER

func _hide_order_source_items(animation: Dictionary, duration: float) -> void:
	for source in animation.get("sources", []):
		var node: GridItem = source.get("node") as GridItem
		if node == null or not is_instance_valid(node):
			continue
		var tween: Tween = node.create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(node, "modulate:a", 0.0, duration)
		tween.tween_callback(node.hide)

func _play_order_material_fly(animation: Dictionary, duration: float) -> void:
	for source in animation.get("sources", []):
		var texture: Texture2D = source.get("texture") as Texture2D
		_play_flying_item(int(source.get("item_id", 0)), source.get("from", Vector2.ZERO), source.get("to", Vector2.ZERO), duration, texture)

func _play_flying_item(item_id: int, from_pos: Vector2, to_pos: Vector2, duration: float, texture_override: Texture2D = null) -> void:
	var texture: Texture2D = texture_override
	if texture == null:
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		if item_data.is_empty():
			print("[GameScreen] order animation: missing item data id=", item_id)
			return
		var icon_path: String = item_data.get("icon", "")
		texture = load(icon_path) as Texture2D
	if texture == null:
		print("[GameScreen] order animation: missing item texture id=", item_id)
		return
	var fly: TextureRect = TextureRect.new()
	fly.texture = texture
	fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly.size = Vector2(52, 52)
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.z_index = 1000
	var host: Control = _get_order_animation_host()
	host.add_child(fly)
	fly.show()
	var from_global: Vector2 = from_pos - fly.size / 2.0
	var to_global: Vector2 = to_pos - fly.size / 2.0
	fly.global_position = from_global
	print("[GameScreen] order animation: item fly id=", item_id, " from=", from_pos, " to=", to_pos)
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly, "global_position", to_global, duration)
	tween.tween_callback(fly.queue_free)

func _get_order_animation_host() -> Control:
	var overlay: Control = UIManager.get_layer(UIManager.Layer.OVERLAY)
	return overlay if overlay != null else self

func _play_qi_reward_pile(texture: Texture2D, from_pos: Vector2, to_pos: Vector2) -> void:
	if texture == null:
		return
	var count: int = maxi(Constants.QI_REWARD_FLY_COUNT, 1)
	print("[GameScreen] order animation: qi pile count=", count, " duration=", Constants.QI_REWARD_FLY_DURATION, " stagger=", Constants.QI_REWARD_FLY_STAGGER)
	for index in range(count):
		var angle: float = -PI * 0.5 + TAU * float(index) / float(count)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * Constants.QI_REWARD_FLY_SPREAD
		var delay: float = float(index) * Constants.QI_REWARD_FLY_STAGGER
		_play_flying_texture(
			texture,
			from_pos + offset,
			to_pos,
			Constants.QI_REWARD_FLY_DURATION,
			delay,
			Vector2(Constants.QI_REWARD_FLY_ICON_SIZE, Constants.QI_REWARD_FLY_ICON_SIZE)
		)

func _play_flying_texture(texture: Texture2D, from_pos: Vector2, to_pos: Vector2, duration: float, start_delay: float = 0.0, icon_size: Vector2 = Vector2(52.0, 52.0)) -> void:
	if texture == null:
		return
	var fly: TextureRect = TextureRect.new()
	fly.texture = texture
	fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly.size = icon_size
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.z_index = 1000
	var host: Control = _get_order_animation_host()
	host.add_child(fly)
	fly.show()
	var from_global: Vector2 = from_pos - fly.size / 2.0
	var to_global: Vector2 = to_pos - fly.size / 2.0
	fly.global_position = from_global
	print("[GameScreen] order animation: fly from=", from_pos, " to=", to_pos)
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.tween_property(fly, "global_position", to_global, duration)
	tween.tween_callback(fly.queue_free)

func _on_stage_changed_for_meridian(_level: int, _name: String) -> void:
	_refresh_meridian()

func _on_meridian_rejected(reason: String) -> void:
	_meridian_submit_pending = false
	if top_bar:
		top_bar.set_qi_updates_suppressed(false)
	_pending_order_animation.clear()
	if CloudService.meridian_complete_confirmed.is_connected(_on_meridian_confirmed):
		CloudService.meridian_complete_confirmed.disconnect(_on_meridian_confirmed)
	_pending_item_ids.clear()
	match reason:
		"insufficient_items": EventBus.show_toast.emit("物品不足")
		"already_completed": EventBus.show_toast.emit("该穴位已完成")
		"qi_full": EventBus.show_toast.emit("灵力已达上限，请先去使用吧")
		_: EventBus.show_toast.emit("修炼失败：" + reason)

func _on_stamina_restore_confirmed(result: Dictionary) -> void:
	_item_use_pending = false
	var stam: int = result.get("stamina", 0)
	if stam > 0:
		GameState.stamina = stam
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	if _pending_stamina_uid > 0:
		var pos := GridManager.find_pos_by_uid(_pending_stamina_uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)
		_pending_stamina_uid = -1

func _on_stamina_restore_rejected(reason: String) -> void:
	_item_use_pending = false
	EventBus.show_toast.emit("回复体力失败：" + reason)
	_pending_stamina_uid = -1

func _on_spirit_stone_consume_confirmed(result: Dictionary) -> void:
	_item_use_pending = false
	if _pending_spirit_stone_uid > 0:
		var pos: Vector2i = GridManager.find_pos_by_uid(_pending_spirit_stone_uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)
	_pending_spirit_stone_uid = -1
	EventBus.show_toast.emit("获得%d灵石" % int(result.get("amount", 0)))

func _on_spirit_stone_consume_rejected(reason: String) -> void:
	_item_use_pending = false
	_pending_spirit_stone_uid = -1
	EventBus.show_toast.emit("使用灵石失败：" + reason)

func _create_activity_entry(act: Dictionary) -> Control:
	var widget: String = act.get("widget", "")
	match widget:
		"WeeklyActivityEntry":
			var we := preload("res://scenes/ui/activity/WeeklyActivityEntry.tscn").instantiate() as WeeklyActivityEntry
			return we
	return null
