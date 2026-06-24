class_name GameScreen extends BaseScreen

@onready var overlay: Overlay = $Overlay
@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var grid_view: GridView = $GridView
@onready var cultivation_panel: CultivationPanel = $CultivationPanel
@onready var battle_btn: Button = $BattleButton

func _ready() -> void:
	randomize()

	# Game initialization
	if not GridManager.grid_updated.is_connected(GameState.check_game_over):
		GridManager.grid_updated.connect(GameState.check_game_over)
	# Only load initial setup for a fresh game (server state already restored if logged in)
	if GridManager.count_items() == 0:
		_load_initial_setup()
	GameState.set_phase(GameState.GamePhase.IDLE)

	# EventBus action handlers
	EventBus.resume_requested.connect(_on_resume)
	EventBus.restart_requested.connect(_on_restart)
	EventBus.pause_requested.connect(_on_pause_requested)

	# Item detail panel
	# Material remove from crafting table
	detail_panel.material_clicked.connect(_on_material_clicked)
	grid_view.item_clicked.connect(_on_item_clicked)

	# Cultivation panel
	cultivation_panel.cultivation_clicked.connect(_on_cultivation_clicked)
	grid_view.item_use_requested.connect(_on_item_use_requested)
	CloudService.craft_remove_confirmed.connect(_on_craft_remove_confirmed)
	CloudService.craft_remove_rejected.connect(_on_craft_remove_rejected)

	battle_btn.pressed.connect(_on_battle_pressed)

	print("[GameScreen] Game initialized!")

func on_enter() -> void:
	if GameState.current_board_type != Constants.BoardType.MAIN:
		GameState.current_board_type = Constants.BoardType.MAIN
		if CloudService.online:
			CloudService.board_switch_confirmed.connect(_on_main_board_switch_confirmed, CONNECT_ONE_SHOT)
			CloudService.board_switch_rejected.connect(_on_main_board_switch_rejected, CONNECT_ONE_SHOT)
			CloudService.submit_board_switch("main")
		else:
			_sync_main_grid_local()

func _on_main_board_switch_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	GridManager.init_grid(Constants.BoardType.MAIN)
	var server_grid: Array = result.get("grid", [])
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	print("[GameScreen] Board switched to main: ", server_grid.size(), " items")

func _on_main_board_switch_rejected(reason: String) -> void:
	print("[GameScreen] Board switch rejected: ", reason)
	_sync_main_grid_local()

func _sync_main_grid_local() -> void:
	if GridManager.count_items() == 0:
		GameState.current_board_type = Constants.BoardType.MAIN
		_load_initial_setup()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameState.phase == GameState.GamePhase.IDLE:
			_on_pause_requested()
		elif GameState.phase == GameState.GamePhase.PAUSED and overlay.visible:
			_on_resume()

func _load_initial_setup() -> void:
	var setup = ConfigDatabase.get_initial_setup(GameState.current_board_type)
	for entry in setup:
		if not entry.has("id") or not entry.has("col") or not entry.has("row"):
			push_error("[GameScreen] Invalid initial_setup entry: ", entry)
			continue
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

	# Optimistic: remove from table + add to grid locally
	var removed := CraftingService.remove_ingredient(table_item, item_id)
	if removed.is_empty():
		return
	# Enrich with full item data from config (server stores only {id} in craft_stored)
	var full_data := ConfigDatabase.get_item_data(removed.get("id", 0))
	if not full_data.is_empty():
		GridManager.add_item(full_data.duplicate(true), spawn_pos)
	else:
		GridManager.add_item(removed.duplicate(true), spawn_pos)
	detail_panel._refresh_materials()

	# Sync to server
	if CloudService.online:
		CloudService.submit_craft_remove(table_pos.x, table_pos.y, item_id, spawn_pos.x, spawn_pos.y, GameState.version)
func _on_cultivation_clicked() -> void:
	var detail := preload("res://scenes/ui/CultivationDetail.tscn").instantiate()
	UIManager.show_popup(detail)

func _on_craft_remove_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	print("[GameScreen] Craft remove confirmed v", GameState.version)

func _on_craft_remove_rejected(reason: String) -> void:
	print("[GameScreen] Craft remove rejected: ", reason)
	EventBus.show_toast.emit("取出材料失败：" + reason)

func _on_item_use_requested(item_data: Dictionary, grid_pos: Vector2i) -> void:
	var effect_id: int = int(item_data.get("use_effect_id", 0))
	if effect_id <= 0:
		return
	var effect: Dictionary = ConfigDatabase.get_effect(effect_id)
	if effect.is_empty():
		return
	var effect_type: String = effect.get("type", "")
	match effect_type:
		"breakthrough":
			var pill_id: int = item_data.get("id", 0)
			CultivationService.try_breakthrough(pill_id)
		"buff":
			CultivationService.apply_buff(item_data)
		_:
			EventBus.show_toast.emit("此物品无法在此使用")

func _on_item_clicked(item_data: Dictionary, grid_pos: Vector2i) -> void:
	detail_panel.show_item(item_data, grid_pos)

func _on_battle_pressed() -> void:
	EventBus.screen_change_requested.emit("battle")

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
		overlay.show_pause_menu()
