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

func _ready() -> void:
	modulate = Color.TRANSPARENT
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

	battle_btn.pressed.connect(_on_battle_pressed)
	home_btn.pressed.connect(_on_home_pressed)
	if shop_btn:
		shop_btn.pressed.connect(_on_shop_pressed)
	requirement_list.complete_clicked.connect(_on_meridian_complete)
	_refresh_meridian()
	_setup_extras()

	print("[GameScreen] Game initialized!")

func _setup_extras() -> void:
	# Add activity entry widgets for active activities with widgets configured
	for act in ActivityManager.get_active_activities():
		var widget: String = act.get("widget", "")
		if widget.is_empty():
			continue
		var entry := _create_activity_entry(act)
		if entry:
			requirement_list.container.add_child(entry)
			requirement_list.container.move_child(entry, 0)
			entry.setup(act)

	if not pending_bar:
		pending_bar = preload("res://scenes/ui/main/PendingRewardBar.tscn").instantiate() as PendingRewardBar
		requirement_list.container.add_child(pending_bar)
		requirement_list.container.move_child(pending_bar, 1)
		pending_bar.setup(grid_view)

func on_enter() -> void:
	GameState.current_board_type = Constants.BoardType.MAIN
	GridManager.init_grid(Constants.BoardType.MAIN)
	if CloudService.online:
		CloudService.submit_board_switch("main")


func on_exit() -> void:
	grid_view._clear_all_item_nodes()
	detail_panel.clear()

func _on_main_board_switch_confirmed(result: Dictionary) -> void:
	if result.get("board_type", "") != "main":
		return
	GameState.main_grid_cache = result.get("grid", [])
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GridManager.populate_from_server(GameState.main_grid_cache)
	grid_view.set_skip_animations(false)
	print("[GameScreen] Board synced from server: ", GameState.main_grid_cache.size(), " items")
	var fade := create_tween()
	fade.tween_property(self, "modulate", Color.WHITE, 0.15)

func _on_main_board_switch_rejected(_reason: String) -> void:
	pass

func _on_material_clicked(uid: int, item_id: int) -> void:
	var table_pos := detail_panel.get_current_craft_pos()
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
	var effect_id: int = int(item_data.get("use_effect_id", 0))
	print("[GameScreen] item_use: id=" + str(item_data.get("id",0)) + " effect=" + str(effect_id) + " uid=" + str(item_data.get("_uid", 0)))
	if effect_id <= 0:
		return
	var effect: Dictionary = ConfigDatabase.get_effect(effect_id)
	if effect.is_empty():
		return
	var uid: int = item_data.get("_uid", 0)
	match effect.get("type", ""):
		"breakthrough":
				print("[GameScreen] breakthrough click: pill_id=" + str(item_data.get("id",0)) + " uid=" + str(uid) + " pos=" + str(grid_pos))
				if uid <= 0:
					EventBus.show_toast.emit("物品数据异常，请重新登录")
					print("[GameScreen] breakthrough BLOCKED: uid=" + str(uid))
					return
				CultivationService.try_breakthrough(item_data.get("id", 0), uid)
		"exp": CultivationService.consume_exp_pill(item_data.get("id", 0), uid)
		"stamina":
			_pending_stamina_uid = uid
			CloudService.submit_restore_stamina(item_data.get("id", 0), uid)
		_: EventBus.show_toast.emit("此物品无法在此使用")

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
	for i in range(_display_index_map.size()):
		var data_index: int = _display_index_map[i]
		if data_index < 0 or data_index >= GameState.meridian_acupoints.size():
			continue
		var req: Dictionary = GameState.meridian_acupoints[data_index]
		if not req.get("completed", false):
			requirement_list.set_entry_available(i, _check_can_complete(req))

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
	for i in range(GameState.meridian_acupoints.size()):
		var req: Dictionary = GameState.meridian_acupoints[i]
		if not req.get("completed", false):
			display_reqs.append(req.duplicate())
			_display_index_map.append(i)
	requirement_list.set_requirements(display_reqs)
	_refresh_requirement_buttons()

func _on_meridian_complete(display_index: int) -> void:
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
	EventBus.show_toast.emit("回复体力失败：" + reason)
	_pending_stamina_uid = -1

func _create_activity_entry(act: Dictionary) -> Control:
	var widget: String = act.get("widget", "")
	match widget:
		"WeeklyActivityEntry":
			var we := preload("res://scenes/ui/activity/WeeklyActivityEntry.tscn").instantiate() as WeeklyActivityEntry
			return we
	return null
