class_name GameScreen extends BaseScreen

@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var grid_view: GridView = $GridView
@onready var requirement_list: RequirementList = $RequirementList
@onready var battle_btn: Button = $BattleButton
@onready var home_btn: Button = $HomeButton
@onready var shop_btn: Button = $ShopButton
@onready var pouch_zone: PouchDropZone = $PouchDropZone
@onready var pending_bar: PendingRewardBar

var _pending_item_ids: Array = []
var _meridian_submit_pending: bool = false
var _display_index_map: Array = []
var _pending_stamina_uid: int = -1
var _meridian_waiting_breakthrough: bool = false
var _item_use_pending: bool = false
var _load_token: int = -1

func _ready() -> void:
	randomize()

	GridManager.grid_updated.connect(_on_grid_changed)
	grid_view.set_pouch_zone(pouch_zone)


	EventBus.restart_requested.connect(_on_restart)

	detail_panel.material_clicked.connect(_on_material_clicked)
	grid_view.item_clicked.connect(_on_item_clicked)

	grid_view.item_use_requested.connect(_on_item_use_requested)
	CloudService.board_switch_confirmed.connect(_on_main_board_switch_confirmed)
	CloudService.board_switch_rejected.connect(_on_main_board_switch_rejected)
	CloudService.craft_remove_confirmed.connect(_on_craft_remove_confirmed)
	CloudService.craft_remove_rejected.connect(_on_craft_remove_rejected)
	CloudService.stamina_restore_confirmed.connect(_on_stamina_restore_confirmed)
	CloudService.stamina_restore_rejected.connect(_on_stamina_restore_rejected)
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
	GameState.current_board_type = Constants.BoardType.MAIN
	if not GridManager.grid_updated.is_connected(_on_grid_changed):
		GridManager.grid_updated.connect(_on_grid_changed)
	GridManager.init_grid(Constants.BoardType.MAIN)
	grid_view.visible = false
	print("[GameScreen] grid_view.visible=false, calling LoadingManager.begin")
	_load_token = LoadingManager.begin("加载棋盘数据...")
	if not GameState.main_grid_cache.is_empty():
		if _load_token > 0:
			LoadingManager.end(_load_token)
			_load_token = -1
		_render_main_grid_cache()
		grid_view.visible = true
	print("[GameScreen] _load_token=", _load_token, " online=", CloudService.online)
	if CloudService.online:
		CloudService.submit_board_switch(Constants.BoardType.MAIN)
	print("[GameScreen] on_enter DONE")

func _render_main_grid_cache() -> void:
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)

func on_exit() -> void:
	if GridManager.grid_updated.is_connected(_on_grid_changed):
		GridManager.grid_updated.disconnect(_on_grid_changed)
	grid_view._clear_all_item_nodes()
	detail_panel.clear()

func _on_main_board_switch_confirmed(result: Dictionary) -> void:
	print("[GameScreen] _on_main_board_switch_confirmed: board_type=", result.get("board_type", -1), " items=", result.get("grid", []).size())
	if result.get("board_type", -1) != Constants.BoardType.MAIN:
		print("[GameScreen] board_type mismatch, returning")
		return
	GameState.main_grid_cache = result.get("grid", [])
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)
	grid_view.visible = true
	print("[GameScreen] grid_view.visible=true, ending token=", _load_token)
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1
	print("[GameScreen] board switch done")

func _on_main_board_switch_rejected(_reason: String) -> void:
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1

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

func _submit_material_remove(table_pos: Vector2i, _uid: int, item_id: int) -> void:
	var spawn_pos := GridManager.find_nearest_empty(table_pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满，无法取出材料")
		return
	if CloudService.online:
		CloudService.submit_craft_remove(table_pos.x, table_pos.y, item_id, spawn_pos.x, spawn_pos.y)

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
				print("[GameScreen] breakthrough click: pill_id=" + str(item_data.get("id",0)) + " uid=" + str(uid) + " pos=" + str(grid_pos))
				if uid <= 0:
					EventBus.show_toast.emit("物品数据异常，请重新登录")
					print("[GameScreen] breakthrough BLOCKED: uid=" + str(uid))
					return
				CultivationService.try_breakthrough(item_data.get("id", 0), uid)
		Constants.EffectType.EXP:
			CultivationService.consume_exp_pill(item_data.get("id", 0), uid)
		Constants.EffectType.STAMINA:
			_pending_stamina_uid = uid
			CloudService.submit_restore_stamina(item_data.get("id", 0), uid)
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
	_refresh_requirement_buttons()

func _count_grid_item(item_id: int) -> int:
	var count := 0
	for entry in GridManager.get_all_items():
		if entry.data.get("id", 0) == item_id:
			count += 1
	return count

func _check_can_complete(req: Dictionary) -> bool:
	var items: Array = req.get("items", [])
	if items.is_empty():
		return false
	for it in items:
		if _count_grid_item(int(it.get("item_id", 0))) < 1:
			return false
	return true

func _refresh_requirement_buttons() -> void:
	_refresh_required_indicators()
	_refresh_requirement_item_selection()
	for i in range(_display_index_map.size()):
		var data_index: int = _display_index_map[i]
		if data_index < 0 or data_index >= GameState.meridian_acupoints.size():
			continue
		var req: Dictionary = GameState.meridian_acupoints[data_index]
		if not req.get("completed", false):
			requirement_list.set_entry_available(i, _check_can_complete(req))

func _refresh_requirement_item_selection() -> void:
	var present_item_ids: Dictionary = {}
	for entry in GridManager.get_all_items():
		var item_id: int = int(entry.data.get("id", 0))
		if item_id > 0:
			present_item_ids[item_id] = true
	requirement_list.refresh_item_selection(present_item_ids)


func _refresh_required_indicators() -> void:
	if GameState.current_board_type != Constants.BoardType.MAIN:
		return
	var required_ids: Array = []
	# Collect all item IDs needed by incomplete acupoints
	for req in GameState.meridian_acupoints:
		for it in req.get("items", []):
			var item_id: int = int(it.get("item_id", 0))
			if item_id > 0 and not required_ids.has(item_id):
				required_ids.append(item_id)
	# Update all grid items
	for entry in GridManager.get_all_items():
		var node: GridItem = grid_view._item_nodes.get("%d,%d" % [entry.pos.x, entry.pos.y])
		if node and is_instance_valid(node):
			node.set_required(required_ids.has(entry.data.get("id", 0)))

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
	var available_indices: Dictionary = {}
	for i in range(GameState.meridian_acupoints.size()):
		var req: Dictionary = GameState.meridian_acupoints[i]
		if not req.get("completed", false):
			var display_index: int = display_reqs.size()
			display_reqs.append(req.duplicate())
			_display_index_map.append(i)
			available_indices[display_index] = _check_can_complete(req)
	requirement_list.set_requirements(display_reqs, available_indices)
	_refresh_requirement_buttons()

func _on_meridian_complete(display_index: int) -> void:
	grid_view.run_after_action_sync(_submit_meridian_complete.bind(display_index))

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
		_meridian_submit_pending = true
		CloudService.meridian_complete_confirmed.connect(_on_meridian_confirmed, CONNECT_ONE_SHOT)
		CloudService.meridian_complete_rejected.connect(_on_meridian_rejected, CONNECT_ONE_SHOT)
		CloudService.submit_meridian_complete(data_index, _pending_item_ids)

func _on_meridian_confirmed(result: Dictionary) -> void:
	_meridian_submit_pending = false
	if CloudService.meridian_complete_rejected.is_connected(_on_meridian_rejected):
		CloudService.meridian_complete_rejected.disconnect(_on_meridian_rejected)

	var server_grid: Array = result.get("grid", [])
	print("[GameScreen] meridian confirmed, server grid size=", server_grid.size())
	grid_view.set_skip_animations(true)
	GridManager.init_grid()
	GridManager.populate_from_server(server_grid)
	grid_view.set_skip_animations(false)

	var cult: Dictionary = result.get("cultivation", {})
	if not cult.is_empty():
		CultivationService.deserialize(cult)

	# Server returns updated list (completed order removed, new order added)
	GameState.meridian_acupoints = result.get("meridian_acupoints", [])
	_display_meridian()

	var qi_gained: int = result.get("qi_gained", 0)
	if qi_gained > 0:
		EventBus.show_toast.emit("灵力 +%d" % qi_gained)
		if result.get("qi_full", false):
			EventBus.show_toast.emit("灵力已满，尽快使用！")

func _on_stage_changed_for_meridian(_level: int, _name: String) -> void:
	if _meridian_waiting_breakthrough and not CultivationService._needs_breakthrough_pill():
		_meridian_waiting_breakthrough = false
		_refresh_meridian()

func _on_meridian_rejected(reason: String) -> void:
	_meridian_submit_pending = false
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

func _create_activity_entry(act: Dictionary) -> Control:
	var widget: String = act.get("widget", "")
	match widget:
		"WeeklyActivityEntry":
			var we := preload("res://scenes/ui/activity/WeeklyActivityEntry.tscn").instantiate() as WeeklyActivityEntry
			return we
	return null
