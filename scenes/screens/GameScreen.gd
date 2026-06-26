class_name GameScreen extends BaseScreen

@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var grid_view: GridView = $GridView
@onready var cultivation_panel: CultivationPanel = $CultivationPanel
@onready var requirement_list: RequirementList = $RequirementList
@onready var battle_btn: Button = $BattleButton
@onready var home_btn: Button = $HomeButton
@onready var shop_btn: Button = $ShopButton
@onready var pouch_zone: PouchDropZone = $PouchDropZone

var _meridian_complete_exp: int = 50
var _pending_item_ids: Array = []
var _display_index_map: Array = []

func _ready() -> void:
	randomize()

	if not GridManager.grid_updated.is_connected(GameState.check_game_over):
		GridManager.grid_updated.connect(GameState.check_game_over)
	GridManager.grid_updated.connect(_on_grid_changed)
	grid_view.set_pouch_zone(pouch_zone)
	GameState.set_phase(GameState.GamePhase.IDLE)

	EventBus.resume_requested.connect(_on_resume)
	EventBus.restart_requested.connect(_on_restart)
	EventBus.pause_requested.connect(_on_pause_requested)

	detail_panel.material_clicked.connect(_on_material_clicked)
	grid_view.item_clicked.connect(_on_item_clicked)

	cultivation_panel.cultivation_clicked.connect(_on_cultivation_clicked)
	grid_view.item_use_requested.connect(_on_item_use_requested)
	CloudService.craft_remove_confirmed.connect(_on_craft_remove_confirmed)
	CloudService.craft_remove_rejected.connect(_on_craft_remove_rejected)

	battle_btn.pressed.connect(_on_battle_pressed)
	home_btn.pressed.connect(_on_home_pressed)
	if shop_btn:
		shop_btn.pressed.connect(_on_shop_pressed)
	requirement_list.complete_clicked.connect(_on_meridian_complete)
	_refresh_meridian()

	print("[GameScreen] Game initialized!")

func on_enter() -> void:
	if GameState.current_board_type != Constants.BoardType.MAIN:
		GameState.current_board_type = Constants.BoardType.MAIN
		if CloudService.online:
			if CloudService.board_switch_confirmed.is_connected(_on_main_board_switch_confirmed):
				CloudService.board_switch_confirmed.disconnect(_on_main_board_switch_confirmed)
			CloudService.board_switch_confirmed.connect(_on_main_board_switch_confirmed, CONNECT_ONE_SHOT)
			CloudService.board_switch_rejected.connect(_on_main_board_switch_rejected, CONNECT_ONE_SHOT)
			CloudService.submit_board_switch("main")

func _on_main_board_switch_confirmed(result: Dictionary) -> void:
	if result.get("board_type", "") != "main":
		return
	GameState.version = result.get("new_version", GameState.version)
	GridManager.init_grid(Constants.BoardType.MAIN)
	var server_grid: Array = result.get("grid", [])
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	print("[GameScreen] Board synced from server: ", server_grid.size(), " items")

func _on_main_board_switch_rejected(_reason: String) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameState.phase == GameState.GamePhase.IDLE:
			_on_pause_requested()
		elif GameState.phase == GameState.GamePhase.PAUSED:
			_on_resume()

func _load_initial_setup() -> void:
	for entry in ConfigDatabase.get_initial_setup(GameState.current_board_type):
		var item_data = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			GridManager.add_item(item_data.duplicate(true), Vector2i(entry.col, entry.row))

func _on_material_clicked(item_id: int) -> void:
	var table_item := detail_panel.get_current_craft_table()
	if table_item.is_empty():
		return
	var table_pos := detail_panel.get_current_craft_pos()
	var spawn_pos := GridManager.find_nearest_empty(table_pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满，无法取出材料")
		return
	var removed := CraftingService.remove_ingredient(table_item, item_id)
	if removed.is_empty():
		return
	var full_data := ConfigDatabase.get_item_data(removed.get("id", 0))
	if not full_data.is_empty():
		GridManager.add_item(full_data.duplicate(true), spawn_pos)
	else:
		GridManager.add_item(removed.duplicate(true), spawn_pos)
	detail_panel._refresh_materials()
	if CloudService.online:
		CloudService.submit_craft_remove(table_pos.x, table_pos.y, item_id, spawn_pos.x, spawn_pos.y, GameState.version)

func _on_cultivation_clicked() -> void:
	var detail := preload("res://scenes/ui/CultivationDetail.tscn").instantiate()
	UIManager.show_popup(detail)

func _on_craft_remove_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)

func _on_craft_remove_rejected(reason: String) -> void:
	EventBus.show_toast.emit("取出材料失败：" + reason)

func _on_item_use_requested(item_data: Dictionary, grid_pos: Vector2i) -> void:
	var effect_id: int = int(item_data.get("use_effect_id", 0))
	if effect_id <= 0:
		return
	var effect: Dictionary = ConfigDatabase.get_effect(effect_id)
	if effect.is_empty():
		return
	match effect.get("type", ""):
		"breakthrough": CultivationService.try_breakthrough(item_data.get("id", 0))
		"exp": CultivationService.consume_exp_pill(item_data.get("id", 0), grid_pos)
		_: EventBus.show_toast.emit("此物品无法在此使用")

func _on_item_clicked(item_data: Dictionary, grid_pos: Vector2i) -> void:
	detail_panel.show_item(item_data, grid_pos)

func _on_home_pressed() -> void:
	EventBus.screen_change_requested.emit("home")

func _on_battle_pressed() -> void:
	GameState.previous_screen_name = "game"
	EventBus.screen_change_requested.emit("battle")

func _on_shop_pressed() -> void:
	var popup := preload("res://scenes/ui/ShopPopup.tscn").instantiate() as ShopPopup
	UIManager.show_popup(popup)

func _on_restart() -> void:
	GameState.reset()
	GridManager.init_grid()
	_load_initial_setup()
	GameState.set_phase(GameState.GamePhase.IDLE)
	detail_panel.clear()

func _on_resume() -> void:
	GameState.set_phase(GameState.GamePhase.IDLE)

func _on_pause_requested() -> void:
	if GameState.phase == GameState.GamePhase.IDLE:
		GameState.set_phase(GameState.GamePhase.PAUSED)

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
	GameState.version = result.get("new_version", GameState.version)
	GameState.meridian_acupoints = result.get("acupoints", [])
	GameState.meridian_threshold_idx = result.get("threshold_idx", 0)
	_meridian_complete_exp = result.get("complete_exp", 50)
	_display_meridian()

func _display_meridian() -> void:
	var completed: int = 0
	_display_index_map.clear()
	for req in GameState.meridian_acupoints:
		if req.get("completed", false):
			completed += 1
	requirement_list.set_title("大周天 %d/%d (奖励 %d修为)" % [completed, GameState.meridian_acupoints.size(), _meridian_complete_exp])
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
		if CloudService.meridian_complete_confirmed.is_connected(_on_meridian_confirmed):
			CloudService.meridian_complete_confirmed.disconnect(_on_meridian_confirmed)
		if CloudService.meridian_complete_rejected.is_connected(_on_meridian_rejected):
			CloudService.meridian_complete_rejected.disconnect(_on_meridian_rejected)
		CloudService.meridian_complete_confirmed.connect(_on_meridian_confirmed, CONNECT_ONE_SHOT)
		CloudService.meridian_complete_rejected.connect(_on_meridian_rejected, CONNECT_ONE_SHOT)
		CloudService.submit_meridian_complete(data_index, _pending_item_ids)

func _on_meridian_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)

	var server_grid: Array = result.get("grid", [])
	print("[GameScreen] meridian confirmed, server grid size=", server_grid.size())
	grid_view.set_skip_animations(true)
	GridManager.init_grid()
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	grid_view.set_skip_animations(false)

	var cult: Dictionary = result.get("cultivation", {})
	if not cult.is_empty():
		CultivationService.deserialize(cult)

	for i in range(result.get("meridian_acupoints", []).size()):
		if i < GameState.meridian_acupoints.size():
			GameState.meridian_acupoints[i] = result.meridian_acupoints[i]
		if result.meridian_acupoints[i].get("completed", false):
			requirement_list.remove_entry(i)

	if result.get("circulation_completed", false):
		GameState.meridian_circulations += 1
		var exp: int = result.get("exp_gained", 0)
		EventBus.show_toast.emit("大周天完成！获得%d修为 (%d次)" % [exp, GameState.meridian_circulations])
		GameState.meridian_acupoints.clear()
		_refresh_meridian()
	_display_meridian()

	var qi_gained: int = result.get("qi_gained", 0)
	if qi_gained > 0:
		EventBus.show_toast.emit("灵力 +%d" % qi_gained)
		if result.get("qi_full", false):
			EventBus.show_toast.emit("灵力已满，尽快使用！")

func _on_meridian_rejected(reason: String) -> void:
	_pending_item_ids.clear()
	match reason:
		"insufficient_items": EventBus.show_toast.emit("物品不足")
		"already_completed": EventBus.show_toast.emit("该穴位已完成")
		_: EventBus.show_toast.emit("修炼失败：" + reason)
