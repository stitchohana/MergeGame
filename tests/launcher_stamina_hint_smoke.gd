extends Node

var _toasts: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.current_board_type = Constants.BoardType.MAIN
	GameState.meridian_acupoints = []
	GameState.stamina_multiplier_max = 1
	GameState.stamina_multiplier_selected = 1
	GameState.stamina_multiplier_expires_at = 0
	GameState.stamina = 0
	var launcher: Dictionary = ConfigDatabase.get_item_data(11001).duplicate(true)
	launcher["_uid"] = 993001
	launcher["charges"] = int(launcher.get("max_charges", 3))
	assert(GridManager.add_item(launcher, Vector2i(0, 0)))
	var grid_view: GridView = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	add_child(grid_view)
	await get_tree().process_frame
	EventBus.show_toast.connect(func(message: String): _toasts.append(message))
	var controller: LauncherController = grid_view._launcher_ctrl as LauncherController
	var requests_before: int = CloudService._request_queue.size()
	var sequence_before: int = GameState.spawn_sequence

	# First click selects; subsequent clicks use the selected launcher.
	grid_view._select_item(Vector2i(0, 0))
	assert(_toasts.is_empty())
	grid_view._select_item(Vector2i(0, 0))
	assert(_toasts == ["体力不足"])
	assert(controller._pending_spawns.is_empty())
	assert(GameState.stamina == 0)
	assert(int(launcher["charges"]) == int(launcher.get("max_charges", 3)))
	assert(GridManager.get_all_items().size() == 1)
	assert(CloudService._request_queue.size() == requests_before)
	assert(GameState.spawn_sequence == sequence_before)

	# Having some stamina still fails when the selected multiplier costs more.
	GameState.stamina_multiplier_max = 4
	GameState.stamina_multiplier_selected = 4
	GameState.stamina_multiplier_expires_at = int(Time.get_unix_time_from_system() * 1000.0) + 3600000
	GameState.stamina = 3
	_toasts.clear()
	grid_view._select_item(Vector2i(0, 0))
	assert(_toasts == ["体力不足"])
	assert(controller._pending_spawns.is_empty())
	assert(GameState.stamina == 3)
	assert(CloudService._request_queue.size() == requests_before)

	# Pending requests reserve stamina, so a repeated click must also notify.
	GameState.stamina_multiplier_selected = 1
	GameState.stamina = 1
	controller._pending_spawns = [{
		"board_type": Constants.BoardType.MAIN,
		"launcher_uid": 993001,
		"is_no_cost": false,
		"stamina_cost": 1,
	}]
	_toasts.clear()
	grid_view._select_item(Vector2i(0, 0))
	assert(_toasts == ["体力不足"])
	assert(controller._pending_spawns.size() == 1)
	assert(GameState.stamina == 1)
	assert(CloudService._request_queue.size() == requests_before)
	controller._pending_spawns.clear()

	# A server rejection rolls back the predicted item and shows the same hint.
	var predicted_item: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	predicted_item["_uid"] = -993002
	predicted_item["_pending_spawn"] = true
	assert(GridManager.add_item(predicted_item, Vector2i(1, 0)))
	controller._pending_spawns = [{"temp_uid": -993002}]
	_toasts.clear()
	CloudService.spawn_rejected.emit("insufficient_stamina")
	assert(_toasts == ["体力不足"])
	assert(controller._pending_spawns.is_empty())
	assert(GridManager.is_empty(Vector2i(1, 0)))
	assert(not grid_view._action_recovery_in_flight)
	print("LAUNCHER_STAMINA_HINT_SMOKE_OK zero=true multiplier=true reserved=true server_rejection=true")
	get_tree().quit(0)
