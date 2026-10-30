extends Node

var _landings: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func _capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/" + name + ".png")

func _run() -> void:
	CloudService.online = false
	GameState.current_board_type = Constants.BoardType.MAIN
	GameState.main_grid_cache = []
	GameState.meridian_acupoints = []
	CultivationService.current_level = 6
	GridManager.init_grid()
	GridManager.populate_from_server([{"id": 5001, "uid": 998001, "col": 0, "row": 0}])
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: GridView = screen.grid_view
	var controller: Node = screen._basin_controller
	var button: Control = controller.basin_button
	var drops: Array[int] = []
	grid.basin_drop_requested.connect(func(uid: int): drops.append(uid))
	grid._start_drag(Vector2i.ZERO)
	assert(not grid._try_basin_drop(Vector2(-100, -100)))
	assert(grid._try_basin_drop(button.get_global_rect().get_center()))
	grid._is_dragging = false
	assert(drops == [998001])
	assert(controller._phase.is_empty(), "Offline drops must leave the source untouched")
	assert((grid._item_nodes["0,0"] as GridItem).visible)

	# Hold the real transport queue so this test never contacts a server.
	CloudService.online = true
	CloudService._busy = true
	controller._on_drop(998001)
	assert(controller._phase == "preview")
	assert(not (grid._item_nodes["0,0"] as GridItem).visible)
	grid._sync_all_items()
	assert(not (grid._item_nodes["0,0"] as GridItem).visible, "Refreshing the board must not reveal a submitted input")
	assert(UIManager.is_input_blocked())
	assert(CloudService._request_queue.back().tag == "golden_preview")
	CloudService._request_queue.clear()
	CloudService.golden_finger_failed.emit("no_uses")
	assert((grid._item_nodes["0,0"] as GridItem).visible)
	assert(GridManager.find_pos_by_uid(998001) == Vector2i.ZERO)
	assert(not UIManager.is_input_blocked())
	grid._action_sync_needed = true
	controller._on_drop(998001)
	assert(controller._phase == "sync")
	grid._cancel_action_sync_waiters("")
	grid._action_sync_needed = false
	assert(controller._phase.is_empty())
	assert((grid._item_nodes["0,0"] as GridItem).visible)

	controller._on_drop(998001)
	CloudService.golden_finger_preview.emit({"version": 7, "golden_finger": {"period_key": "2026-10-27"}, "quote": {"output_id": 5004}})
	assert(controller._phase == "use")
	assert(CloudService.golden_finger_retry.body.uids == [998001])
	assert(CloudService.golden_finger_retry.body.quote.output_id == 5004)
	CloudService._request_queue.clear()
	CloudService.online = false
	var outputs: Array = [{"id": 5004, "uid": 998002, "col": 0, "row": 0}, {"id": 5004, "uid": 998003, "col": 1, "row": 0}]
	var response: Dictionary = {"artifact": "basin", "action": "use", "storage_revision": 100,
		"grid": outputs, "spawned_items": outputs, "pending_items": [], "pending_rewards": []}
	CloudService._on_golden_action(response)
	assert(GridManager.find_pos_by_uid(998001).x < 0)
	assert(controller._flies.size() == 2)
	assert(controller._hidden.size() == 2)
	for index: int in range(2):
		var fly: TextureRect = controller._flies[index]
		assert(fly.size.x > 0 and fly.size.y > 0, "Outputs must be visible immediately, including after authoritative rebuild")
		assert(fly.get_global_rect().get_center().is_equal_approx(button.get_global_rect().get_center()))
		var target: GridItem = grid._item_nodes["%d,0" % index] as GridItem
		assert(not target.visible, "Do not display a second copy under the flying output")
		_track_landing(fly, target.icon_rect)
	CloudService._on_golden_action(response)
	assert(controller._flies.size() == 2, "Repeated confirmations must not duplicate flights")
	assert(not (grid._item_nodes["0,0"] as GridItem).visible)
	await get_tree().create_timer(0.2).timeout
	await _capture("basin_board_flight")
	await get_tree().create_timer(0.55).timeout
	assert(controller._flies.is_empty() and controller._hidden.is_empty())
	assert(not UIManager.is_input_blocked())
	assert(_landings.size() == 2)
	for landing: Dictionary in _landings:
		assert((landing.position as Vector2).distance_to(landing.target as Vector2) < 1.0, "Each output must land at the live icon center")
	assert((grid._item_nodes["0,0"] as GridItem).visible)
	assert((grid._item_nodes["1,0"] as GridItem).visible)

	# Full board: consuming the input makes room for one output; the other is pending.
	var full: Array = []
	for index: int in range(63):
		full.append({"id": 5001, "uid": 999000 + index, "col": index % 7, "row": floori(index / 7.0)})
	full[0] = {"id": 5004, "uid": 999100, "col": 0, "row": 0}
	var pending: Dictionary = {"id": 5004, "uid": 999101, "name": "米"}
	response = {"artifact": "basin", "action": "use", "storage_revision": 101,
		"grid": full, "spawned_items": [full[0]], "pending_items": [pending], "pending_rewards": [pending], "pending_rewards_added": 1}
	_landings.clear()
	CloudService._on_golden_action(response)
	assert(controller._flies.size() == 2)
	assert(controller.pending_bar.visible)
	_track_landing(controller._flies[1], controller.pending_bar)
	await get_tree().create_timer(0.2).timeout
	await _capture("basin_pending_flight")
	await get_tree().create_timer(0.55).timeout
	assert(_landings.size() == 1)
	assert((_landings[0].position as Vector2).distance_to(_landings[0].target as Vector2) < 1.0)
	assert(GridManager.count_items() == 63 and RewardManager.pending_rewards.size() == 1)
	assert(controller._input_token == -1)

	# Leaving during a flight cleans the overlay and its input lock, keeping server rewards.
	response.storage_revision = 102
	response.pending_items = [{"id": 5004, "uid": 999102}]
	CloudService._on_golden_action(response)
	assert(controller._flies.size() == 2)
	controller.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not UIManager.is_input_blocked())
	assert(GridManager.count_items() == 63 and RewardManager.pending_rewards.size() == 1)
	CloudService._busy = false
	print("BASIN_DRAG_UI_SMOKE_OK drop failure sync_cancel two_flights landing overflow replay cleanup")
	get_tree().quit(0)

func _track_landing(fly: TextureRect, target: Control) -> void:
	var target_position: Vector2 = target.get_global_rect().get_center()
	var target_ref: WeakRef = weakref(target)
	fly.tree_exiting.connect(func():
		var live_target: Control = target_ref.get_ref() as Control
		_landings.append({"position": fly.get_global_rect().get_center(), "target": live_target.get_global_rect().get_center() if live_target != null else target_position})
	)
