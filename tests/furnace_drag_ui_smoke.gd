extends Node

func _ready() -> void:
	call_deferred("_run")

func _info(materials: Array) -> Dictionary:
	return {"version": 4, "storage_revision": 1, "grid": [{"id": 1001, "uid": 997001, "col": 0, "row": 0}],
		"materials": materials, "golden_finger": {"period_key": "2026-10-27", "artifacts": [{"id": "furnace", "unlocked": true,
		"remaining": 3, "free_remaining": 3, "purchases_remaining": 5, "next_cost": 100}]}}

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
	GridManager.populate_from_server([{"id": 1001, "uid": 997001, "col": 0, "row": 0}])
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: GridView = screen.grid_view
	var controller: Node = screen._furnace_controller
	grid._start_drag(Vector2i.ZERO)
	assert(grid._try_furnace_drop(controller.basin_button.get_global_rect().get_center()))
	grid._is_dragging = false
	assert(controller._phase.is_empty(), "Offline drop must preserve the material")
	assert((grid._item_nodes["0,0"] as GridItem).visible)
	# Hold both transport queues, then feed authoritative responses without networking.
	CloudService._query_requests = {-1: {}, -2: {}, -3: {}, -4: {}}
	controller._uid = 997001
	controller._phase = "sync"
	CloudService.online = true
	CloudService._busy = true
	controller._request_preview()
	await get_tree().process_frame
	var popup: Control = controller._choice_popup
	var materials: Array = [{"id": 1001, "level": 1, "name": "雾芽草"}, {"id": 5001, "level": 1, "name": "露芽米"}, {"id": 5002, "level": 2, "name": "青禾米"}, {"id": 9001, "level": 1, "name": "石隙清泉"}]
	popup._on_info(_info(materials))
	assert(popup.candidate_buttons.size() == 2)
	assert(popup.candidate_buttons.has(5001) and popup.candidate_buttons.has(9001))
	assert(not popup.candidate_buttons.has(1001) and not popup.candidate_buttons.has(5002))
	assert(popup.use_button.disabled)
	assert(not (grid._item_nodes["0,0"] as GridItem).visible)
	var notices: Array[String] = []
	EventBus.show_toast.connect(func(message: String): notices.append(message))
	GameState.spirit_stones = 0
	popup._confirm_buy()
	assert(notices.back().contains("灵石不足"))
	CloudService.golden_finger_failed.emit("insufficient_stones")
	assert(notices.back() == "灵石不足")
	assert(controller._choice_popup == popup and controller._phase == "choose")
	assert(not (grid._item_nodes["0,0"] as GridItem).visible, "Failed purchases must retain the selected furnace material")
	popup._close()
	await get_tree().create_timer(0.25).timeout
	assert(controller._phase.is_empty())
	assert((grid._item_nodes["0,0"] as GridItem).visible)

	controller._uid = 997001
	controller._phase = "sync"
	controller._request_preview()
	await get_tree().process_frame
	popup = controller._choice_popup
	popup._on_info(_info([materials[0]]))
	assert(popup.candidate_buttons.is_empty() and popup.use_button.disabled)
	assert(popup.message_label.text.contains("暂无"))
	popup._on_info(_info(materials))
	popup._select_target(5001)
	assert(popup._previewing and popup.use_button.disabled)
	assert(CloudService._request_queue.back().tag == "golden_preview")
	var quote: Dictionary = {"ok": true, "output_id": 5001, "output_name": "露芽米", "output_count": 1}
	CloudService.golden_finger_preview.emit({"version": 4, "golden_finger": _info(materials).golden_finger, "quote": quote, "output_name": "露芽米"})
	assert(not popup.use_button.disabled)
	assert(popup.message_label.text.contains("露芽米"))
	await get_tree().create_timer(0.25).timeout
	await _capture("furnace_choices")
	popup._confirm_use()
	assert(CloudService.golden_finger_retry.body.uids == [997001])
	assert(CloudService.golden_finger_retry.body.target_id == 5001)
	assert(popup.close_button.disabled and popup.use_button.disabled)
	var queued: int = CloudService._request_queue.size()
	popup._confirm_use()
	assert(CloudService._request_queue.size() == queued)
	CloudService.golden_finger_failed.emit("state_conflict")
	assert(not popup._pending and popup.use_button.disabled)
	assert(not CloudService.golden_finger_busy)
	assert((grid._item_nodes["0,0"] as GridItem).visible)
	await get_tree().create_timer(0.25).timeout
	# A fresh info/preview can be confirmed, followed by authoritative delivery.
	controller._on_drop(997001)
	popup = controller._choice_popup
	popup._on_info(_info(materials))
	popup._select_target(9001)
	quote.output_id = 9001
	quote.output_name = "石隙清泉"
	CloudService.golden_finger_preview.emit({"version": 4, "golden_finger": _info(materials).golden_finger, "quote": quote, "output_name": "石隙清泉"})
	popup._confirm_use()
	CloudService._request_queue.clear()
	CloudService.online = false
	var output: Dictionary = {"id": 9001, "uid": 997002, "col": 0, "row": 0}
	var result: Dictionary = {"artifact": "furnace", "action": "use", "storage_revision": 100, "grid": [output], "spawned_items": [output], "pending_rewards": []}
	CloudService._on_golden_action(result)
	assert(controller._flies.size() == 1)
	assert(GridManager.find_pos_by_uid(997001).x < 0)
	assert(not (grid._item_nodes["0,0"] as GridItem).visible)
	var fly: TextureRect = controller._flies[0]
	assert(fly.get_global_rect().get_center().is_equal_approx(controller.basin_button.get_global_rect().get_center()))
	var landing: Dictionary = {}
	fly.tree_exiting.connect(func(): landing.position = fly.get_global_rect().get_center())
	CloudService._on_golden_action(result)
	assert(controller._flies.size() == 1)
	await get_tree().create_timer(0.3).timeout
	await _capture("furnace_flight")
	await get_tree().create_timer(0.35).timeout
	assert(not is_instance_valid(popup))
	assert(controller._flies.is_empty())
	assert((landing.position as Vector2).distance_to((grid._item_nodes["0,0"] as GridItem).icon_rect.get_global_rect().get_center()) < 1)
	assert((grid._item_nodes["0,0"] as GridItem).visible)
	assert(not UIManager.is_input_blocked())
	CloudService._busy = false
	CloudService._query_queue.clear()
	CloudService._query_requests.clear()
	print("FURNACE_DRAG_UI_SMOKE_OK choices same_level cancel empty preview conflict confirm single_flight replay")
	get_tree().quit()
