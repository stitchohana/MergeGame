class_name BattleScreen extends BaseScreen

@onready var grid_view: GridView = $GridView
@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var leave_btn: Button = $LeaveButton

func _ready() -> void:
	grid_view.item_clicked.connect(_on_item_clicked)
	if not GridManager.grid_updated.is_connected(GameState.check_game_over):
		GridManager.grid_updated.connect(GameState.check_game_over)
	leave_btn.pressed.connect(_on_leave_pressed)

func on_enter() -> void:
	GameState.current_board_type = Constants.BoardType.BATTLE
	if CloudService.online:
		CloudService.board_switch_confirmed.connect(_on_board_switch_confirmed, CONNECT_ONE_SHOT)
		CloudService.board_switch_rejected.connect(_on_board_switch_rejected, CONNECT_ONE_SHOT)
		CloudService.submit_board_switch("battle")
	else:
		_init_battle_grid()

func _on_board_switch_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	GridManager.init_grid(Constants.BoardType.BATTLE)
	var server_grid: Array = result.get("grid", [])
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	GameState.set_phase(GameState.GamePhase.IDLE)
	print("[BattleScreen] Board switched to battle: ", server_grid.size(), " items")

func _on_board_switch_rejected(reason: String) -> void:
	print("[BattleScreen] Board switch rejected: ", reason)
	_init_battle_grid()

func _init_battle_grid() -> void:
	GridManager.init_grid(Constants.BoardType.BATTLE)
	_load_battle_setup()
	GameState.set_phase(GameState.GamePhase.IDLE)

func on_exit() -> void:
	detail_panel.clear()
	# Board switch to main is handled by GameScreen.on_enter()

func _load_battle_setup() -> void:
	var setup: Array = ConfigDatabase.get_initial_setup(Constants.BoardType.BATTLE)
	for entry in setup:
		if not entry.has("id") or not entry.has("col") or not entry.has("row"):
			push_error("[BattleScreen] Invalid battle setup entry: ", entry)
			continue
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			GridManager.add_item(item_data.duplicate(true), Vector2i(entry.col, entry.row))

func _on_leave_pressed() -> void:
	EventBus.screen_change_requested.emit("game")

func _on_item_clicked(item_data: Dictionary, grid_pos: Vector2i) -> void:
	detail_panel.show_item(item_data, grid_pos)
