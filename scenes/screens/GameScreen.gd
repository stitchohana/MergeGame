class_name GameScreen extends BaseScreen

@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var grid_view: GridView = $GridView
@onready var requirement_list: RequirementList = $RequirementList
@onready var battle_pass_entry: BattlePassEntry = $RequirementList/Panel/ScrollContainer/HBoxContainer/BattlePassEntry
@onready var battle_btn: Button = $BattleButton
@onready var home_btn: Button = $HomeButton
@onready var shop_btn: Button = $ShopButton
@onready var pouch_zone: PouchDropZone = $PouchDropZone
@onready var pending_bar: PendingRewardBar
@onready var top_bar: TopBar = $TopBar
@onready var order_supply_entry: OrderSupplyEntry = $OrderSupplyEntry

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
var _initial_order_focus_token: int = 0
var _require_refresh_queued: bool = false
var _suppress_requirement_refresh: bool = false
var _order_supply_input_token: int = -1
var _order_supply_reward_tween: Tween = null
var _order_supply_flying_icons: Array[TextureRect] = []
var _order_supply_hidden_items: Dictionary = {}  # uid -> grid position
var _basin_controller: Node
var _furnace_controller: Node

func _ready() -> void:
	grid_view.scale = Vector2.ONE * Constants.BOARD_DISPLAY_SCALE
	randomize()

	GridManager.grid_updated.connect(_on_grid_changed)
	StoragePouch.pouch_updated.connect(func(_items: Array): _queue_requirement_refresh())
	grid_view.set_pouch_zone(pouch_zone)
	$GoldenFingerBar.artifact_pressed.connect(_on_artifact_pressed)
	requirement_list.setup_pending_reward_bar(grid_view)
	_basin_controller = preload("res://scenes/ui/main/BasinController.gd").new()
	add_child(_basin_controller)
	_basin_controller.setup(grid_view, $GoldenFingerBar.entries.basin.button,
		requirement_list.get_node("Panel/ScrollContainer/HBoxContainer/PendingRewardBar") as PendingRewardBar)
	_furnace_controller = preload("res://scenes/ui/main/BasinController.gd").new()
	_furnace_controller.artifact_id = "furnace"
	add_child(_furnace_controller)
	_furnace_controller.setup(grid_view, $GoldenFingerBar.entries.furnace.button,
		requirement_list.get_node("Panel/ScrollContainer/HBoxContainer/PendingRewardBar") as PendingRewardBar)


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
	GameState.meridian_updated.connect(_on_meridian_updated)
	ActivityManager.order_duel_updated.connect(_refresh_order_activity_rewards)
	CloudService.secret_realm_updated.connect(func(_view: Dictionary): _refresh_order_activity_rewards())
	if not GameState.battle_pass_changed.is_connected(_on_battle_pass_changed):
		GameState.battle_pass_changed.connect(_on_battle_pass_changed)
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
	order_supply_entry.claim_requested.connect(_on_order_supply_claim_requested)
	grid_view.action_sync_cancelled.connect(_on_order_supply_sync_cancelled)
	CloudService.order_supply_claim_confirmed.connect(_on_order_supply_claim_confirmed)
	CloudService.order_supply_claim_rejected.connect(_on_order_supply_claim_rejected)
	_refresh_meridian()
	_setup_extras()


func _on_artifact_pressed(artifact_id: String) -> void:
	grid_view.run_after_action_sync(func():
		var popup: BasePopup = preload("res://scenes/ui/main/GoldenFingerPopup.gd").new()
		popup.artifact_id = artifact_id
		UIManager.show_popup(popup)
	)


func _on_order_supply_claim_requested(activity_id: int, completed_rounds: int) -> void:
	grid_view.run_after_action_sync(func():
		if not CloudService.online or not visible or GameState.current_board_type != Constants.BoardType.MAIN:
			CloudService.order_supply_claim_rejected.emit("offline")
			return
		_order_supply_input_token = UIManager.begin_input_block("order_supply_claim")
		CloudService.submit_order_supply_claim(activity_id, completed_rounds)
	)


func _on_order_supply_sync_cancelled() -> void:
	order_supply_entry._on_claim_rejected("sync_cancelled")
	_end_order_supply_input_lock()


func _on_order_supply_claim_confirmed(result: Dictionary) -> void:
	_finish_order_supply_reward_animation()
	GameState.main_grid_cache = result.get("grid", [])
	var animating: bool = false
	if GameState.current_board_type == Constants.BoardType.MAIN and is_inside_tree() and visible:
		grid_view._sync_grid_from_server(result)
		grid_view._restore_crafting_timers()
		detail_panel.refresh_from_grid()
		animating = _play_order_supply_reward_animation(result.get("spawned_items", []))
	if not animating:
		_end_order_supply_input_lock()
	var pending_added: int = int(result.get("pending_rewards_added", 0))
	if pending_added > 0 and result.get("spawned_items", []).is_empty():
		EventBus.show_toast.emit("棋盘无空位，订单素材已放入暂存区")
	elif pending_added > 0:
		EventBus.show_toast.emit("订单素材已发到棋盘，剩余素材已放入暂存区")
	else:
		EventBus.show_toast.emit("订单素材已发到棋盘")
	if int(result.get("crafts_completed", 0)) > 0:
		EventBus.show_toast.emit("正在制作的物品已完成，可点击制作台取出")


func _play_order_supply_reward_animation(spawned_items: Array) -> bool:
	var from_pos: Vector2 = order_supply_entry.get_global_rect().get_center()
	var index: int = 0
	for entry_variant: Variant in spawned_items:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var pos := Vector2i(int(entry.get("col", -1)), int(entry.get("row", -1)))
		var uid: int = int(entry.get("uid", 0))
		var node: GridItem = grid_view._item_nodes.get("%d,%d" % [pos.x, pos.y]) as GridItem
		if not is_instance_valid(node) or int(node.item_data.get("_uid", 0)) != uid:
			continue
		var texture: Texture2D = node.icon_rect.texture
		if texture == null:
			continue
		if _order_supply_reward_tween == null:
			_order_supply_reward_tween = create_tween().set_parallel(true)
			if _order_supply_input_token < 0:
				_order_supply_input_token = UIManager.begin_input_block("order_supply_animation")
		var target_rect: Rect2 = node.icon_rect.get_global_rect()
		var fly := TextureRect.new()
		fly.texture = texture
		fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fly.size = target_rect.size
		fly.pivot_offset = fly.size / 2.0
		fly.scale = Vector2.ONE * 0.65
		fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fly.z_index = 1000
		add_child(fly)
		fly.global_position = from_pos - fly.size / 2.0
		fly.hide()
		_order_supply_flying_icons.append(fly)
		_order_supply_hidden_items[uid] = pos
		node.hide()
		var delay: float = float(index) * Constants.ORDER_SUPPLY_FLY_STAGGER
		var duration: float = Constants.ORDER_SUPPLY_FLY_DURATION
		_order_supply_reward_tween.tween_callback(fly.show).set_delay(delay)
		_order_supply_reward_tween.tween_property(fly, "global_position", target_rect.position, duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_order_supply_reward_tween.tween_property(fly, "scale", Vector2.ONE, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_order_supply_reward_tween.tween_callback(_on_order_supply_item_landed.bind(uid, fly)).set_delay(delay + duration)
		index += 1
	if _order_supply_reward_tween == null:
		return false
	_order_supply_reward_tween.finished.connect(_finish_order_supply_reward_animation)
	return true


func _on_order_supply_item_landed(uid: int, fly: TextureRect) -> void:
	var pos: Vector2i = _order_supply_hidden_items.get(uid, Vector2i(-1, -1))
	var node: GridItem = grid_view._item_nodes.get("%d,%d" % [pos.x, pos.y]) as GridItem
	if is_instance_valid(node) and int(node.item_data.get("_uid", 0)) == uid:
		node.show()
	_order_supply_hidden_items.erase(uid)
	_order_supply_flying_icons.erase(fly)
	if is_instance_valid(fly):
		fly.queue_free()


func _hide_order_supply_pending_items() -> void:
	for uid: int in _order_supply_hidden_items:
		var pos: Vector2i = _order_supply_hidden_items[uid]
		var node: GridItem = grid_view._item_nodes.get("%d,%d" % [pos.x, pos.y]) as GridItem
		if is_instance_valid(node) and int(node.item_data.get("_uid", 0)) == uid:
			node.hide()


func _finish_order_supply_reward_animation() -> void:
	if _order_supply_reward_tween != null:
		_order_supply_reward_tween.kill()
		_order_supply_reward_tween = null
	for uid: int in _order_supply_hidden_items.keys():
		_on_order_supply_item_landed(uid, null)
	for fly: TextureRect in _order_supply_flying_icons:
		if is_instance_valid(fly):
			fly.queue_free()
	_order_supply_flying_icons.clear()
	_end_order_supply_input_lock()


func _exit_tree() -> void:
	_finish_order_supply_reward_animation()


func _on_order_supply_claim_rejected(reason: String) -> void:
	_end_order_supply_input_lock()
	match reason:
		"board_full":
			EventBus.show_toast.emit("棋盘空位不足，请腾出空间后领取")
		"activity_not_completed":
			EventBus.show_toast.emit("生成、合成订单物品或开始制作订单成品，累计次数达标后可领取")
		"no_order_materials":
			EventBus.show_toast.emit("暂无可领取的订单素材")
		"offline", "network_error":
			EventBus.show_toast.emit("请联网后领取订单补给")
		_:
			EventBus.show_toast.emit("领取失败，请重试")
	if CloudService.online:
		grid_view._request_action_recovery_state()


func _end_order_supply_input_lock() -> void:
	if _order_supply_input_token >= 0:
		UIManager.end_input_block(_order_supply_input_token)
		_order_supply_input_token = -1


func _on_state_loaded_for_orders(state: Dictionary) -> void:
	if state.has("activity_current_day"):
		GameState.activity_current_day = int(state.get("activity_current_day", 0))
	_refresh_activity_entries()
	_refresh_battle_pass_entry()
	if not state.has("meridian_acupoints"):
		return
	var acupoints: Array = state.get("meridian_acupoints", []) as Array
	GameState.meridian_acupoints = acupoints.duplicate(true)
	GameState.meridian_threshold_idx = int(state.get("meridian_threshold_idx", GameState.meridian_threshold_idx))
	if is_inside_tree():
		_display_meridian()

func _on_meridian_updated() -> void:
	if is_node_ready() and is_inside_tree():
		_display_meridian()

func _setup_extras() -> void:
	# Keep activity entries ahead of the cultivation character and order cards.
	var has_character_entry: bool = false
	for child: Node in requirement_list.container.get_children():
		if child is CharacterEntry:
			requirement_list.container.move_child(child, 0)
			has_character_entry = true
			break
	if not has_character_entry:
		var character_entry: CharacterEntry = preload("res://scenes/ui/character/CharacterEntry.tscn").instantiate() as CharacterEntry
		requirement_list.container.add_child(character_entry)
		requirement_list.container.move_child(character_entry, 0)
	_refresh_activity_entries()
	requirement_list.sort_fixed_entries()
	_refresh_battle_pass_entry()


func _on_battle_pass_changed(_progress: Dictionary) -> void:
	_refresh_battle_pass_entry()


func _refresh_battle_pass_entry() -> void:
	if battle_pass_entry == null:
		return
	if not ActivityManager.is_unlocked():
		battle_pass_entry.visible = false
		requirement_list.sort_fixed_entries()
		return
	for activity_variant: Variant in GameState.activity_defs:
		if not activity_variant is Dictionary:
			continue
		var activity: Dictionary = activity_variant as Dictionary
		if str(activity.get("widget", "")) != "BattlePass":
			continue
		battle_pass_entry.visible = bool(activity.get("active", false))
		if battle_pass_entry.visible:
			battle_pass_entry.setup(activity)
		requirement_list.sort_fixed_entries()
		return
	battle_pass_entry.visible = false
	requirement_list.sort_fixed_entries()


func _refresh_activity_entries() -> void:
	for child: Node in requirement_list.container.get_children():
		if child is WeeklyActivityEntry or child is HomeActivityCard:
			requirement_list.container.remove_child(child)
			child.queue_free()

	var insert_index: int = 0
	for activity: Dictionary in ActivityManager.get_active_activities():
		if activity.get("widget", "").is_empty():
			continue
		var entry: Control = _create_activity_entry(activity)
		if entry == null:
			continue
		requirement_list.container.add_child(entry)
		requirement_list.container.move_child(entry, insert_index)
		entry.call("setup", activity)
		insert_index += 1

func on_enter() -> void:
	_initial_order_focus_token += 1
	_is_initial_game_load = true
	requirement_list.reset_scroll_to_start()
	GameState.current_board_type = Constants.BoardType.MAIN
	if not GridManager.grid_updated.is_connected(_on_grid_changed):
		GridManager.grid_updated.connect(_on_grid_changed)
	GridManager.init_grid(Constants.BoardType.MAIN)
	grid_view.visible = false
	_load_token = LoadingManager.begin("加载棋盘数据...")
	if not CloudService.online and not GameState.main_grid_cache.is_empty():
		_render_main_grid_cache()
	if not CloudService.online and _load_token > 0:
		grid_view.visible = true
		LoadingManager.end(_load_token)
		_load_token = -1
	if CloudService.online:
		CloudService.submit_board_switch(Constants.BoardType.MAIN)
	else:
		_schedule_initial_order_list_focus()
		requirement_list.reset_scroll_to_start()

func _render_main_grid_cache() -> void:
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)

func on_exit() -> void:
	if GridManager.current_board_type == Constants.BoardType.MAIN:
		GameState.main_grid_cache = GridManager.get_server_grid_snapshot()
	_initial_order_focus_token += 1
	_finish_order_supply_reward_animation()
	_end_order_animation_input_lock()
	if GridManager.grid_updated.is_connected(_on_grid_changed):
		GridManager.grid_updated.disconnect(_on_grid_changed)
	grid_view._clear_all_item_nodes()
	detail_panel.clear()

func _on_main_board_switch_confirmed(result: Dictionary) -> void:
	if result.get("board_type", -1) != Constants.BoardType.MAIN:
		return
	GameState.main_grid_cache = result.get("grid", [])
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)
	grid_view.visible = true
	requirement_list.reset_scroll_to_start()
	_schedule_initial_order_list_focus()
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1

func _on_main_board_switch_rejected(_reason: String) -> void:
	if not GameState.main_grid_cache.is_empty():
		_render_main_grid_cache()
	requirement_list.reset_scroll_to_start()
	_schedule_initial_order_list_focus()
	grid_view.visible = true
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1

func _schedule_initial_order_list_focus() -> void:
	_initial_order_focus_token += 1
	var focus_token: int = _initial_order_focus_token
	call_deferred("_finish_initial_order_list_focus", focus_token)

func _finish_initial_order_list_focus(focus_token: int) -> void:
	await get_tree().process_frame
	if focus_token != _initial_order_focus_token or not is_inside_tree():
		return
	await get_tree().process_frame
	if focus_token != _initial_order_focus_token or not is_inside_tree():
		return
	if requirement_list.get_order_entries().is_empty():
		return
	requirement_list.focus_next_order()
	_is_initial_game_load = false

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
				print("[PlayerAction] breakthrough_click uid=", uid, " pos=", grid_pos)
				if uid <= 0:
					EventBus.show_toast.emit("物品数据异常，请重新登录")
					print("[PlayerAction] breakthrough_blocked uid=", uid)
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
	if not _order_supply_hidden_items.is_empty():
		call_deferred("_hide_order_supply_pending_items")
	_queue_requirement_refresh()

func _on_craft_table_state_changed(_table_item: Dictionary, state: int) -> void:
	_refresh_requirement_crafting_badges()
	# IDLE is followed by a grid update when a material/result is moved.
	# Wait for that update so retrieval does not briefly re-mark ingredients.
	if state == CraftingService.TableState.IDLE:
		return
	_queue_requirement_refresh()

func _queue_requirement_refresh() -> void:
	if _suppress_requirement_refresh:
		return
	if _require_refresh_queued:
		return
	_require_refresh_queued = true
	call_deferred("_flush_requirement_refresh")

func _flush_requirement_refresh() -> void:
	_require_refresh_queued = false
	if _suppress_requirement_refresh or not is_inside_tree():
		return
	_refresh_requirement_buttons()

func _get_reserved_crafting_item_counts(result_id: int = 0, claimed_tables: Dictionary = {}) -> Dictionary:
	var reserved_counts: Dictionary = {}
	var required_recipe_ids: Dictionary = (
		CraftingService.get_recipe_dependency_ids(result_id) if result_id > 0
		else CraftingService.get_required_order_recipe_ids()
	)
	for entry: Dictionary in GridManager.get_inventory_items():
		var table_item: Dictionary = entry.get("data", {}) as Dictionary
		if int(table_item.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		var craft_state: int = int(table_item.get("_craft_state", CraftingService.TableState.IDLE))
		# A started craft reserves its output, not reusable ingredient quantities.
		if craft_state == CraftingService.TableState.CRAFTING or craft_state == CraftingService.TableState.READY:
			continue
		if not CraftingService.table_supports_order_materials(table_item, required_recipe_ids):
			continue
		var table_uid: int = int(table_item.get("_uid", 0))
		if table_uid > 0 and claimed_tables.has(table_uid):
			continue
		var table_counts: Dictionary = {}
		for stored_variant: Variant in table_item.get("_craft_stored", []):
			if not stored_variant is Dictionary:
				continue
			var stored_item: Dictionary = stored_variant as Dictionary
			var stored_id: int = int(stored_item.get("id", 0))
			if stored_id > 0:
				table_counts[stored_id] = int(table_counts.get(stored_id, 0)) + 1
		if table_counts.is_empty():
			continue
		# One loaded table can prepare one product, even when several orders
		# share ingredients. Do not lend its materials to another product.
		if table_uid > 0:
			claimed_tables[table_uid] = true
		for item_id_variant: Variant in table_counts.keys():
			var item_id: int = int(item_id_variant)
			reserved_counts[item_id] = (
				int(reserved_counts.get(item_id, 0)) + int(table_counts[item_id])
			)
		if result_id > 0:
			break
	return reserved_counts

func _get_finished_order_item_counts(include_crafting: bool = false) -> Dictionary:
	var finished_counts: Dictionary = {}
	var known_positions: Dictionary = {}
	var known_uids: Dictionary = {}
	for entry: Dictionary in GridManager.get_inventory_items():
		var item_data: Dictionary = entry.get("data", {}) as Dictionary
		var entry_pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
		known_positions["%d,%d" % [entry_pos.x, entry_pos.y]] = true
		var uid: int = int(item_data.get("_uid", 0))
		if uid > 0:
			known_uids[uid] = true
		var item_id: int = int(item_data.get("id", 0))
		var item_type: int = int(item_data.get("type", 0))
		# An order product can inherit an immovable flag from its board snapshot.
		# It is still an existing product; only crafting facilities are excluded.
		if item_id > 0 and item_type != Constants.ItemType.CRAFTING:
			finished_counts[item_id] = int(finished_counts.get(item_id, 0)) + 1
		if int(item_data.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		var craft_state: int = int(item_data.get("_craft_state", CraftingService.TableState.IDLE))
		if craft_state != CraftingService.TableState.READY and not (
			include_crafting and craft_state == CraftingService.TableState.CRAFTING
		):
			continue
		var result_id: int = int(item_data.get("_craft_result_id", 0))
		if result_id <= 0:
			var recipe: Dictionary = item_data.get("_craft_recipe", {}) as Dictionary
			result_id = int(recipe.get("result", 0))
		if result_id > 0:
			finished_counts[result_id] = int(finished_counts.get(result_id, 0)) + 1
	if grid_view != null and is_instance_valid(grid_view):
		for node_key: Variant in grid_view._item_nodes.keys():
			if known_positions.has(str(node_key)):
				continue
			var node: GridItem = grid_view._item_nodes[node_key] as GridItem
			if node == null or not is_instance_valid(node):
				continue
			if known_uids.has(int(node.item_data.get("_uid", 0))):
				continue
			var node_item_id: int = int(node.item_data.get("id", 0))
			var node_item_type: int = int(node.item_data.get("type", 0))
			if node_item_id <= 0 or node_item_type == Constants.ItemType.CRAFTING:
				continue
			finished_counts[node_item_id] = int(finished_counts.get(node_item_id, 0)) + 1
	return finished_counts

func _count_grid_item(item_id: int) -> int:
	var count := 0
	for entry in GridManager.get_inventory_items():
		var item_data: Dictionary = entry.data
		if not bool(item_data.get("immovable", false)) and int(item_data.get("id", 0)) == item_id:
			count += 1
	return count

func _check_can_complete(req: Dictionary) -> bool:
	return _get_requirement_priority(req) == 2

func _get_requirement_priority(req: Dictionary) -> int:
	var stats: Dictionary = _get_requirement_match_stats(req)
	return int(stats.get("priority", 0))

func _get_requirement_match_stats(req: Dictionary) -> Dictionary:
	var items: Array = req.get("items", [])
	if items.is_empty():
		return {"priority": 0, "matched_count": 0}
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
		return {"priority": 0, "matched_count": 0}
	var matched_count: int = 0
	var required_count: int = 0
	for item_id_variant: Variant in required_counts.keys():
		var item_id: int = int(item_id_variant)
		var item_required_count: int = int(required_counts[item_id])
		required_count += item_required_count
		matched_count += mini(_count_grid_item(item_id), item_required_count)
	if matched_count >= required_count:
		return {"priority": 2, "matched_count": matched_count}
	if matched_count > 0:
		return {"priority": 1, "matched_count": matched_count}
	return {"priority": 0, "matched_count": 0}

func _refresh_requirement_buttons() -> void:
	_refresh_required_indicators()
	_refresh_requirement_item_selection()
	_refresh_requirement_crafting_badges()
	var refreshed_stats: Dictionary = {}
	var focus_display_index: int = -1
	var focus_priority: int = -1
	var focus_match_count: int = -1
	for i in range(_display_index_map.size()):
		var data_index: int = _display_index_map[i]
		if data_index < 0 or data_index >= GameState.meridian_acupoints.size():
			continue
		var req: Dictionary = GameState.meridian_acupoints[data_index]
		if not req.get("completed", false):
			var stats: Dictionary = _get_requirement_match_stats(req)
			refreshed_stats[i] = stats
			var previous: Dictionary = requirement_list.get_entry_rank(i)
			var priority: int = int(stats.get("priority", 0))
			var match_count: int = int(stats.get("matched_count", 0))
			var previous_priority: int = int(previous.get("priority", 0))
			var previous_match_count: int = int(previous.get("matched_count", 0))
			var promoted: bool = (
				priority > previous_priority
				or (priority == previous_priority and match_count > previous_match_count)
			)
			if promoted and (
				priority > focus_priority
				or (priority == focus_priority and match_count > focus_match_count)
			):
				focus_display_index = i
				focus_priority = priority
				focus_match_count = match_count
	for i in range(_display_index_map.size()):
		if not refreshed_stats.has(i):
			continue
		var stats: Dictionary = refreshed_stats[i]
		var allow_available_focus: bool = (
			_allow_available_order_focus()
			and i == focus_display_index
		)
		requirement_list.set_entry_priority(
			i,
			int(stats.get("priority", 0)),
			allow_available_focus,
			int(stats.get("matched_count", 0))
		)

func _refresh_requirement_item_selection() -> void:
	requirement_list.refresh_item_selection(GridManager.get_inventory_item_counts())


func _refresh_requirement_crafting_badges() -> void:
	requirement_list.refresh_item_crafting(_get_crafting_result_item_ids())


func _get_crafting_result_item_ids() -> Dictionary:
	var crafting_item_ids: Dictionary = {}
	for entry in GridManager.get_inventory_items():
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
	var claimed_tables: Dictionary = {}
	var finished_order_item_counts: Dictionary = _get_finished_order_item_counts(true)
	var available_recipe_materials: Dictionary = _get_recipe_selection_material_counts()
	var recipe_assignments: Array[Dictionary] = preload("res://scripts/utils/CraftingRecipeHints.gd").build_assignments()
	var assigned_recipes: Dictionary = {}
	for assignment: Dictionary in recipe_assignments:
		var recipe: Dictionary = assignment.get("recipe", {}) as Dictionary
		if not recipe.is_empty():
			assigned_recipes[int(recipe.get("result", 0))] = recipe
	# Existing and in-progress products each cover one order target. Only expand
	# the recipes for the remaining copies, including alternative recipes.
	for req_variant: Variant in GameState.meridian_acupoints:
		var req: Dictionary = req_variant as Dictionary
		if bool(req.get("completed", false)):
			continue
		for it_variant: Variant in req.get("items", []):
			var it: Dictionary = it_variant as Dictionary
			var item_id: int = int(it.get("item_id", 0))
			var finished_count: int = int(finished_order_item_counts.get(item_id, 0))
			if finished_count > 0:
				finished_order_item_counts[item_id] = finished_count - 1
				finished_order_item_ids[item_id] = true
				required_ids[item_id] = true
				continue
			var reserved_crafting_counts: Dictionary = _get_reserved_crafting_item_counts(item_id, claimed_tables)
			_collect_recipe_material_ids(
				item_id, required_ids, reserved_crafting_counts, available_recipe_materials, assigned_recipes
			)

	# Update all grid items
	var seen_node_keys: Dictionary = {}
	for entry in GridManager.get_all_items():
		var node_key: String = "%d,%d" % [entry.pos.x, entry.pos.y]
		seen_node_keys[node_key] = true
		var node: GridItem = grid_view._item_nodes.get(node_key)
		if node and is_instance_valid(node):
			var item_data: Dictionary = entry.data
			var item_id: int = int(item_data.get("id", 0))
			var should_require: bool = (
				(finished_order_item_ids.has(item_id)
					or (not bool(item_data.get("immovable", false))
						and required_ids.has(item_id)))
			)
			node.set_required(should_require)
	# A node can temporarily survive a grid mutation while its position map is
	# being reconciled. Clear only such stale nodes; do not toggle live nodes off
	# before applying their final state, which causes a visible one-frame blink.
	if grid_view != null and is_instance_valid(grid_view):
		for node_key: Variant in grid_view._item_nodes.keys():
			if seen_node_keys.has(str(node_key)):
				continue
			var stale_node: GridItem = grid_view._item_nodes[node_key] as GridItem
			if stale_node != null and is_instance_valid(stale_node):
				stale_node.set_required(false)


func _get_recipe_selection_material_counts() -> Dictionary:
	var counts: Dictionary = {}
	for entry: Dictionary in GridManager.get_inventory_items():
		var item: Dictionary = entry.get("data", {}) as Dictionary
		if int(item.get("type", 0)) == Constants.ItemType.CRAFTING:
			continue
		if bool(item.get("immovable", false)):
			continue
		var item_id: int = int(item.get("id", 0))
		if item_id > 0:
			counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts


func _collect_recipe_material_ids(result_id: int, required_ids: Dictionary,
		reserved_counts: Dictionary, available_counts: Dictionary = {}, assigned_recipes: Dictionary = {}) -> void:
	if result_id <= 0:
		return
	var reserved_for_target: Dictionary = {}
	var recipes: Array = ConfigDatabase.get_recipes_for_result(result_id)
	var selected_recipe: Dictionary = _select_requirement_recipe(recipes, available_counts, assigned_recipes)
	if selected_recipe.is_empty():
		return
	for ingredient_variant: Variant in selected_recipe.get("ingredients", []):
		_collect_recipe_dependency_ids(
			int(ingredient_variant), required_ids, reserved_counts, reserved_for_target,
			available_counts, assigned_recipes
		)


func _select_requirement_recipe(recipes: Array, available_counts: Dictionary, assigned_recipes: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_water: int = 2147483647
	var best_missing: int = 2147483647
	for recipe_variant: Variant in recipes:
		if not recipe_variant is Dictionary:
			continue
		var recipe: Dictionary = recipe_variant as Dictionary
		var remaining: Dictionary = available_counts.duplicate()
		var missing: int = 0
		var water_count: int = 0
		for ingredient_variant: Variant in recipe.get("ingredients", []):
			var ingredient_id: int = int(ingredient_variant)
			if ingredient_id >= 9001 and ingredient_id <= 9004:
				water_count += 1
			var owned: int = int(remaining.get(ingredient_id, 0))
			if owned > 0:
				remaining[ingredient_id] = owned - 1
			else:
				missing += 1
		# Fallback for products without an assigned table: prefer fewer water
		# ingredients, then fewer missing materials. Assigned previews override it below.
		if water_count < best_water or (water_count == best_water and missing < best_missing):
			best = recipe
			best_missing = missing
			best_water = water_count
	# Preview, destination hints and require badges must follow the same path.
	# An alternative recipe cannot replace a recipe already assigned to a table.
	var assigned_recipe: Dictionary = assigned_recipes.get(int(best.get("result", 0)), {}) as Dictionary
	if not assigned_recipe.is_empty():
		best = assigned_recipe
	return best

func _collect_recipe_dependency_ids(item_id: int, required_ids: Dictionary,
		reserved_counts: Dictionary, reserved_for_target: Dictionary,
		available_counts: Dictionary = {}, assigned_recipes: Dictionary = {}) -> void:
	if item_id <= 0 or required_ids.has(item_id) or reserved_for_target.has(item_id):
		return
	var reserved_count: int = int(reserved_counts.get(item_id, 0))
	if reserved_count > 0:
		if reserved_count == 1:
			reserved_counts.erase(item_id)
		else:
			reserved_counts[item_id] = reserved_count - 1
		reserved_for_target[item_id] = true
		return
	required_ids[item_id] = true
	var recipes: Array = ConfigDatabase.get_recipes_for_result(item_id)
	var selected_recipe: Dictionary = _select_requirement_recipe(recipes, available_counts, assigned_recipes)
	for ingredient_variant: Variant in selected_recipe.get("ingredients", []):
		_collect_recipe_dependency_ids(
			int(ingredient_variant), required_ids, reserved_counts, reserved_for_target,
			available_counts, assigned_recipes
		)

func _refresh_meridian() -> void:
	_display_meridian()
	if not GameState.meridian_acupoints.is_empty():
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
	var match_counts: Dictionary = {}
	for i in range(GameState.meridian_acupoints.size()):
		var req: Dictionary = GameState.meridian_acupoints[i]
		if not req.get("completed", false):
			var display_index: int = display_reqs.size()
			display_reqs.append(_with_active_activity_rewards(req))
			_display_index_map.append(i)
			var stats: Dictionary = _get_requirement_match_stats(req)
			priority_indices[display_index] = int(stats.get("priority", 0))
			match_counts[display_index] = int(stats.get("matched_count", 0))
	requirement_list.set_requirements(display_reqs, priority_indices, match_counts)
	_refresh_requirement_buttons()
	if _is_initial_game_load and grid_view.visible:
		_schedule_initial_order_list_focus()


func _with_active_activity_rewards(req: Dictionary) -> Dictionary:
	if not ActivityManager.is_unlocked():
		var novice := req.duplicate(true)
		var rewards_variant: Variant = novice.get("rewards", {})
		if rewards_variant is Dictionary:
			var rewards: Dictionary = rewards_variant
			var activity_tokens: Array[int] = ConfigDatabase.get_activity_token_ids()
			rewards["tokens"] = (rewards.get("tokens", []) as Array).filter(func(t: Variant) -> bool: return t is Dictionary and not activity_tokens.has(int((t as Dictionary).get("token", 0))))
			rewards["items"] = (rewards.get("items", []) as Array).filter(func(i: Variant) -> bool: return i is Dictionary and ConfigDatabase.get_item_data(int((i as Dictionary).get("id", 0))).get("effect_type", -1) != Constants.EffectType.CARD_PACK)
			rewards.erase("stair_climb_points")
			rewards.erase("order_duel_points")
			rewards.erase("secret_realm_swords")
			novice["rewards"] = rewards
		return novice
	var display_req: Dictionary = req.duplicate(true)
	var total_value: int = int(req.get("total_value", 0))
	if bool(req.get("breakthrough_order", false)):
		return display_req
	var rewards_variant: Variant = display_req.get("rewards", {})
	var rewards: Dictionary = rewards_variant.duplicate(true) if rewards_variant is Dictionary else {}
	_append_order_card_pack_reward(rewards, total_value)
	rewards["stair_climb_points"] = _get_order_stair_climb_points(req)
	rewards["order_duel_points"] = _get_order_duel_points(req)
	rewards["secret_realm_swords"] = _get_order_secret_realm_swords(req)
	display_req["rewards"] = rewards
	var tokens_variant: Variant = rewards.get("tokens", [])
	var tokens: Array = tokens_variant.duplicate(true) if tokens_variant is Array else []
	var points_rate: float = float(ConfigDatabase.get_game_config("battle_pass.points_per_value", 0.0))
	if points_rate <= 0.0:
		return display_req
	for activity_variant: Variant in GameState.activity_defs:
		if not activity_variant is Dictionary:
			continue
		var activity: Dictionary = activity_variant as Dictionary
		if not bool(activity.get("active", false)):
			continue
		var activity_id: int = int(activity.get("id", 0))
		var pass_data: Dictionary = ConfigDatabase.get_battle_pass(activity_id)
		if pass_data.is_empty():
			continue
		var points: int = floori(float(total_value) * points_rate)
		if points <= 0:
			continue
		var points_token_id: int = int(pass_data.get("points_token_id", 0))
		if points_token_id <= 0:
			continue
		var already_present: bool = false
		for token_variant: Variant in tokens:
			if token_variant is Dictionary and int((token_variant as Dictionary).get("token", 0)) == points_token_id:
				var token: Dictionary = token_variant as Dictionary
				token["amount"] = int(token.get("amount", 0)) + points
				already_present = true
				break
		if not already_present:
			tokens.append({"token": points_token_id, "amount": points})
	if tokens.is_empty():
		return display_req
	rewards["tokens"] = tokens
	display_req["rewards"] = rewards
	return display_req


func _refresh_order_activity_rewards() -> void:
	# Update only activity rewards: polling must not rebuild orders or interrupt submission animations.
	for child: Node in requirement_list.container.get_children():
		if not child is RequirementEntry:
			continue
		var entry: RequirementEntry = child as RequirementEntry
		var display_index: int = entry.get_display_index()
		if display_index < 0 or display_index >= _display_index_map.size():
			continue
		var data_index: int = int(_display_index_map[display_index])
		if data_index < 0 or data_index >= GameState.meridian_acupoints.size():
			continue
		entry.set_order_duel_points(_get_order_duel_points(GameState.meridian_acupoints[data_index]))
		entry.set_secret_realm_swords(_get_order_secret_realm_swords(GameState.meridian_acupoints[data_index]))


func _get_order_secret_realm_swords(req: Dictionary) -> Array:
	if not ActivityManager.is_unlocked() or GameState.current_board_type != Constants.BoardType.MAIN or bool(req.get("breakthrough_order", false)) or bool(req.get("completed", false)):
		return []
	var config: Dictionary = ConfigDatabase.secret_realm
	var settings: Array = config.get("settings", [])
	if settings.is_empty():
		return []
	var view: Dictionary = CloudService.secret_realm_state
	if str(view.get("period", "")) == str(settings[0].get("period", "")) and bool(view.get("completed", false)):
		return []
	for activity: Dictionary in GameState.activity_defs:
		if str(activity.get("widget", "")) != "SecretRealm" or int(activity.get("id", 0)) != int(settings[0].get("activity_id", 0)):
			continue
		if not bool(activity.get("active", false)) or not bool(activity.get("enabled", true)):
			return []
		var now: float = Time.get_unix_time_from_system()
		var start: String = str(activity.get("start_time", ""))
		var end: String = str(activity.get("end_time", ""))
		if (not start.is_empty() and now < Time.get_unix_time_from_datetime_string(start)) or (not end.is_empty() and now >= Time.get_unix_time_from_datetime_string(end)):
			return []
		for rule: Dictionary in config.get("order_supply_realms", []):
			if CultivationService.current_level >= int(rule.get("cultivation_min", 0)) and CultivationService.current_level <= int(rule.get("cultivation_max", 0)):
				return rule.get("drops", []).duplicate(true)
		return config.get("order_supply", []).duplicate(true)
	return []


func _get_order_duel_points(req: Dictionary) -> int:
	if not ActivityManager.is_unlocked() or bool(req.get("breakthrough_order", false)) or bool(req.get("completed", false)):
		return 0
	var duel: Dictionary = ActivityManager.order_duel
	if not bool(duel.get("active", false)) or str(duel.get("status", "")) != "playing":
		return 0
	for activity: Dictionary in GameState.activity_defs:
		if str(activity.get("widget", "")) != "OrderDuel" or int(activity.get("id", 0)) != int(duel.get("activity_id", 0)):
			continue
		if not bool(activity.get("active", false)) or not bool(activity.get("enabled", true)):
			return 0
		var now: float = Time.get_unix_time_from_system()
		var start: String = str(activity.get("start_time", ""))
		var end: String = str(activity.get("end_time", ""))
		if (not start.is_empty() and now < Time.get_unix_time_from_datetime_string(start)) or (not end.is_empty() and now >= Time.get_unix_time_from_datetime_string(end)):
			return 0
		var settings: Dictionary = duel.get("settings", {})
		var ratio: float = float(settings.get("order_points_ratio", 0.0))
		var value: float = _get_order_item_value(req)
		if ratio <= 0.0 or not is_finite(ratio) or value <= 0.0:
			return 0
		var remaining: int = maxi(0, int(settings.get("target_points", 0)) - int(duel.get("my_points", 0)))
		return mini(remaining, maxi(1, floori(value * ratio + 0.000000001)))
	return 0


func _get_order_item_value(req: Dictionary) -> float:
	var item_ids: Array = req.get("item_ids", [])
	var value: float = 0.0
	for item_id: Variant in item_ids:
		value += float(ConfigDatabase.get_item_data(int(item_id)).get("value", 0))
	return value


func _get_order_stair_climb_points(req: Dictionary) -> int:
	if not ActivityManager.is_unlocked():
		return 0
	if bool(req.get("breakthrough_order", false)) or bool(req.get("completed", false)):
		return 0
	var order_value: float = _get_order_item_value(req)
	if order_value <= 0.0:
		return 0
	for activity: Dictionary in GameState.activity_defs:
		if str(activity.get("widget", "")) != "StairClimb":
			continue
		if not bool(activity.get("active", false)) or not bool(activity.get("enabled", true)):
			return 0
		var now: float = Time.get_unix_time_from_system()
		var start: float = Time.get_unix_time_from_datetime_string(str(activity.get("start_time", "")))
		var end: float = Time.get_unix_time_from_datetime_string(str(activity.get("end_time", "")))
		if now < start or now >= end:
			return 0
		var settings: Dictionary = activity.get("config", {})
		var ratio: float = float(settings.get("order_points_ratio", 0.0))
		if ratio <= 0.0 or not is_finite(ratio):
			return 0
		return maxi(1, floori(order_value * ratio + 0.000000001))
	return 0


func _append_order_card_pack_reward(rewards: Dictionary, total_value: int) -> void:
	if not ActivityManager.is_unlocked():
		return
	var items_variant: Variant = rewards.get("items", [])
	var items: Array = items_variant.duplicate(true) if items_variant is Array else []
	for collection: Dictionary in ConfigDatabase.card_collection.get("collections", []):
		var active: bool = GameState.activity_defs.any(func(activity: Dictionary) -> bool: return int(activity.get("id", 0)) == int(collection.get("activity_id", 0)) and bool(activity.get("active", false)))
		if not active:
			continue
		var best: Dictionary = {}
		for rule: Dictionary in ConfigDatabase.card_collection.get("source_rewards", []):
			if int(rule.get("collection_id", 0)) != int(collection.get("collection_id", 0)) or str(rule.get("source_type", "")) != "order" or int(rule.get("min_value", 0)) > total_value:
				continue
			if rule.has("source_id") and int(rule.source_id) != 0:
				continue
			if best.is_empty() or (rule.has("source_id") and not best.has("source_id")) or (rule.has("source_id") == best.has("source_id") and int(rule.min_value) > int(best.min_value)):
				best = rule
		if best.is_empty() or not bool(best.get("enabled", true)):
			continue
		var pack_item: Dictionary = ConfigDatabase.get_effect_item(Constants.EffectType.CARD_PACK, int(best.get("pack_id", 0)))
		if not pack_item.is_empty():
			items.append({"id": int(pack_item.get("id", 0)), "count": int(best.get("count", 1))})
	rewards["items"] = items

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
		return
	var required_ids: Array = []
	for item_variant in entry._items_setup:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		var item_id: int = int(item.get("item_id", 0))
		if item_id <= 0:
			continue
		required_ids.append(item_id)
	var sources: Array[Dictionary] = _build_order_sources(entry, required_ids)
	var previous_positions: Dictionary = {}
	# Capture the actual visual order because RequirementList may sort entries by
	# availability independently of their display/data indices.
	for visual_index in range(entries.size()):
		var old_entry: RequirementEntry = entries[visual_index]
		previous_positions[visual_index] = old_entry.position
	var completed_visual_index: int = entries.find(entry)
	_pending_order_animation = {"entry": entry, "sources": sources, "required_ids": required_ids, "completed_display_index": display_index, "completed_visual_index": completed_visual_index, "previous_positions": previous_positions, "start_qi": CultivationService.current_qi}

func _find_grid_item_source(item_id: int, used_grid_keys: Dictionary) -> Dictionary:
	var inventory: Array[Dictionary] = GridManager.get_inventory_items()
	for index: int in range(inventory.size()):
		var entry: Dictionary = inventory[index]
		var data: Dictionary = entry.data
		if bool(data.get("immovable", false)) or int(data.get("id", 0)) != item_id:
			continue
		var source: String = entry.source
		var pos: Vector2i = entry.pos
		var key: String = "%d,%d" % [pos.x, pos.y] if source == "grid" else "pouch:%d" % index
		if used_grid_keys.has(key):
			continue
		used_grid_keys[key] = true
		if source == "pouch":
			return {"from": pouch_zone.get_global_rect().get_center(), "source": "pouch",
				"uid": int(data.get("_uid", 0))}
		var node: GridItem = grid_view._item_nodes.get(key) as GridItem
		if node != null and is_instance_valid(node):
			var icon: TextureRect = node.get_node_or_null("IconRect") as TextureRect
			return {"from": icon.get_global_rect().get_center() if icon else node.get_global_rect().get_center(),
				"texture": icon.texture if icon else null, "node": node, "grid_key": key}
		return {"from": grid_view.to_global(Vector2(pos.x * Constants.CELL_STEP, pos.y * Constants.CELL_STEP) + Vector2.ONE * Constants.CELL_SIZE * 0.5)}
	return {}


func _build_order_sources(entry: RequirementEntry, required_ids: Array) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var used_grid_keys: Dictionary = {}
	var used_widgets: Dictionary = {}
	for item_id_variant in required_ids:
		var item_id: int = int(item_id_variant)
		if item_id <= 0:
			continue
		var source: Dictionary = _find_grid_item_source(item_id, used_grid_keys)
		if source.is_empty():
			continue
		var target_widget: ItemWidget = null
		for child: Node in entry.get_node("ItemsContainer").get_children():
			if child is ItemWidget and int(child.item_data.get("id", 0)) == item_id and not used_widgets.has(child):
				target_widget = child as ItemWidget
				used_widgets[child] = true
				break
		if target_widget == null:
			continue
		source["item_id"] = item_id
		source["target_icon"] = target_widget.icon_rect
		source["to"] = target_widget.icon_rect.get_global_rect().get_center()
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
	if _order_animation_input_token >= 0:
		return
	if CloudService.meridian_complete_rejected.is_connected(_on_meridian_rejected):
		CloudService.meridian_complete_rejected.disconnect(_on_meridian_rejected)
	_begin_order_animation_input_lock()
	# The list and inventory may have changed while waiting for synchronization
	# or the response. Capture the current card and sources before playing.
	var display_index: int = int(_pending_order_animation.get("completed_display_index", -1))
	if display_index >= 0:
		_capture_order_animation(display_index)
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
	print("[PlayerAction] order_complete item_count=", animation.get("sources", []).size(),
		" qi=", result.get("qi_gained", 0))
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
	_suppress_requirement_refresh = true
	GameState.main_grid_cache = server_grid.duplicate(true)
	if result.has("pouch"):
		StoragePouch.restore_from_server(result.pouch, result)
	grid_view.set_skip_animations(true)
	# The optimistic completion has already removed submitted items locally.
	# Reconcile the authoritative snapshot in place so surviving GridItem nodes
	# (and their status overlays) are not destroyed and recreated in one frame.
	var server_uids: Dictionary = {}
	for server_entry_variant: Variant in server_grid:
		if server_entry_variant is Dictionary:
			var server_entry: Dictionary = server_entry_variant
			server_uids[int(server_entry.get("uid", 0))] = true
	var stale_positions: Array[Vector2i] = []
	for local_entry: Dictionary in GridManager.get_all_items():
		var local_uid: int = int(local_entry.data.get("_uid", 0))
		if local_uid > 0 and not server_uids.has(local_uid):
			stale_positions.append(local_entry.pos)
	for stale_pos: Vector2i in stale_positions:
		GridManager.remove_item(stale_pos)
	var reconciled_in_place: bool = GridManager.reconcile_from_server(server_grid)
	if not reconciled_in_place:
		GridManager.init_grid()
		GridManager.populate_from_server(server_grid)
	grid_view.set_skip_animations(false)
	_suppress_requirement_refresh = false

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
	if animation.is_empty() or bool(animation.get("completion_started", false)):
		return
	animation["completion_started"] = true
	var sources: Array = animation.get("sources", [])
	if not bool(animation.get("materials_played", false)) and not sources.is_empty():
		var hide_duration: float = Constants.ORDER_SOURCE_HIDE_DURATION
		var fly_duration: float = Constants.ORDER_ITEM_FLY_DURATION
		_hide_order_source_items(animation, hide_duration)
		await get_tree().create_timer(hide_duration).timeout
		_play_order_material_fly(animation, fly_duration)
		await get_tree().create_timer(fly_duration).timeout
	var entry: RequirementEntry = animation.get("entry") as RequirementEntry
	if entry and is_instance_valid(entry):
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
	if bool(animation.get("materials_played", false)):
		return
	animation["materials_played"] = true
	for source in animation.get("sources", []):
		var texture: Texture2D = source.get("texture") as Texture2D
		var target_icon: TextureRect = source.get("target_icon") as TextureRect
		var from_pos: Vector2 = source.get("from", Vector2.ZERO)
		if str(source.get("source", "")) == "pouch":
			from_pos = pouch_zone.get_global_rect().get_center()
		else:
			var node: GridItem = source.get("node") as GridItem
			if is_instance_valid(node):
				var icon: TextureRect = node.get_node_or_null("IconRect") as TextureRect
				from_pos = icon.get_global_rect().get_center() if icon else node.get_global_rect().get_center()
		var fly: TextureRect = _play_flying_item(int(source.get("item_id", 0)), from_pos, source.get("to", Vector2.ZERO), duration, texture, target_icon)
		if fly != null and is_instance_valid(target_icon):
			# Preserve the slot's layout while replacing its icon with the flying copy.
			target_icon.self_modulate.a = 0.0

func _play_flying_item(item_id: int, from_pos: Vector2, to_pos: Vector2, duration: float, texture_override: Texture2D = null, target_icon: TextureRect = null) -> TextureRect:
	var texture: Texture2D = texture_override
	if texture == null:
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		if item_data.is_empty():
			return null
		var icon_path: String = item_data.get("icon", "")
		texture = load(icon_path) as Texture2D
	if texture == null:
		return null
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
	var tween: Tween = fly.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(target_icon):
		tween.tween_method(func(progress: float):
			if not is_instance_valid(fly):
				return
			if not is_instance_valid(target_icon):
				fly.queue_free()
				return
			var current_target: Vector2 = target_icon.get_global_rect().get_center() - fly.size / 2.0
			fly.global_position = from_global.lerp(current_target, progress)
		, 0.0, 1.0, duration)
	else:
		tween.tween_property(fly, "global_position", to_global, duration)
	tween.tween_callback(fly.queue_free)
	return fly

func _get_order_animation_host() -> Control:
	var overlay: Control = UIManager.get_layer(UIManager.Layer.OVERLAY)
	return overlay if overlay != null else self

func _play_qi_reward_pile(texture: Texture2D, from_pos: Vector2, to_pos: Vector2) -> void:
	if texture == null:
		return
	var count: int = maxi(Constants.QI_REWARD_FLY_COUNT, 1)
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
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.tween_property(fly, "global_position", to_global, duration)
	tween.tween_callback(fly.queue_free)

func _on_stage_changed_for_meridian(_level: int, _name: String) -> void:
	_refresh_activity_entries()
	_refresh_battle_pass_entry()
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
	GameState.sync_stamina_multiplier(result)
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
		"CardCollection", "StairClimb", "OrderDuel":
			var entry := preload("res://scenes/ui/activity/HomeActivityCard.tscn").instantiate() as HomeActivityCard
			entry.name = widget + "Entry"
			entry.custom_minimum_size = Vector2(176, 160)
			entry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return entry
	return null
