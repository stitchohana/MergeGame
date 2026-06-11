class_name GameScreen extends BaseScreen

@onready var overlay = $Overlay

func _ready() -> void:
	randomize()

	# Game initialization
	GridManager.grid_updated.connect(GameState.check_game_over)
	_load_initial_setup()
	GameState.set_phase(GameState.GamePhase.IDLE)

	# EventBus action handlers
	EventBus.resume_requested.connect(_on_resume)
	EventBus.restart_requested.connect(_on_restart)
	EventBus.pause_requested.connect(_on_pause_requested)

	print("[GameScreen] Game initialized!")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameState.phase == GameState.GamePhase.IDLE:
			_on_pause_requested()
		elif GameState.phase == GameState.GamePhase.PAUSED and overlay.visible:
			_on_resume()

func _load_initial_setup() -> void:
	var setup = ConfigDatabase.get_initial_setup()
	for entry in setup:
		if not entry.has("id") or not entry.has("col") or not entry.has("row"):
			push_error("[GameScreen] Invalid initial_setup entry: ", entry)
			continue
		var item_data = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			GridManager.add_item(item_data.duplicate(true), Vector2i(entry.col, entry.row))

func _on_restart() -> void:
	GameState.reset()
	GridManager.init_grid()
	_load_initial_setup()
	GameState.set_phase(GameState.GamePhase.IDLE)

func _on_resume() -> void:
	GameState.set_phase(GameState.GamePhase.IDLE)

func _on_pause_requested() -> void:
	if GameState.phase == GameState.GamePhase.IDLE:
		overlay.show_pause_menu()
