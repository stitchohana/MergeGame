extends Control

# Main: Root scene that wires all game systems together.

@onready var grid_view = $GridView
@onready var top_bar = $TopBar
@onready var bottom_panel = $BottomPanel
@onready var overlay = $Overlay

const GRID_VIEW_WIDTH := 350  # 7 * 50
const GRID_VIEW_HEIGHT := 450  # 9 * 50

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameState.phase == GameState.GamePhase.IDLE:
			overlay.show_pause_menu()
		elif GameState.phase == GameState.GamePhase.PAUSED:
			_on_resume()

func _ready() -> void:
	randomize()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout()
	_load_initial_setup()
	GridManager.grid_updated.connect(GameState.check_game_over)
	GameState.set_phase(GameState.GamePhase.IDLE)
	overlay.restart_requested.connect(_on_restart)
	overlay.resume_requested.connect(_on_resume)
	top_bar.settings_pressed.connect(overlay.show_pause_menu)
	print("[Main] Game initialized!")

func _layout() -> void:
	# Get the current viewport size as fallback
	var view_size := get_viewport_rect().size
	var w = size.x if size.x > 0 else view_size.x
	var h = size.y if size.y > 0 else view_size.y

	# Position top bar at the top edge
	if top_bar:
		top_bar.position = Vector2(0, 0)

	# Position bottom panel at the bottom edge
	if bottom_panel:
		bottom_panel.position = Vector2(0, h - bottom_panel.size.y)

	# Center grid view in the remaining space
	if grid_view:
		var top_h = top_bar.size.y if top_bar else 0
		var bottom_h = bottom_panel.size.y if bottom_panel else 0
		var avail_h = h - top_h - bottom_h
		var gx = max(0, (w - GRID_VIEW_WIDTH) * 0.5)
		var gy = top_h + max(0, (avail_h - GRID_VIEW_HEIGHT) * 0.5)
		grid_view.position = Vector2(gx, gy)

func _on_viewport_size_changed() -> void:
	_layout()

func _load_initial_setup() -> void:
	var setup = ConfigDatabase.get_initial_setup()
	for entry in setup:
		if not entry.has("id") or not entry.has("col") or not entry.has("row"):
			push_error("[Main] Invalid initial_setup entry: ", entry)
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
