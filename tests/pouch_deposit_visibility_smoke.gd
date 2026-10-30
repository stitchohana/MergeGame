extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.current_board_type = Constants.BoardType.MAIN
	GameState.meridian_acupoints = []
	GridManager.init_grid(Constants.BoardType.MAIN)
	StoragePouch.restore_from_server([], {"pouch_capacity": 7})
	var data: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	data["_uid"] = 994001
	assert(GridManager.add_item(data, Vector2i.ZERO))
	var grid_view: GridView = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	add_child(grid_view)
	await get_tree().process_frame
	grid_view._drag_source_pos = Vector2i.ZERO
	grid_view._drag_item_data = data
	var dragged: GridItem = grid_view._item_nodes["0,0"] as GridItem
	dragged.position = Vector2(100, -100)
	# Queue the request to simulate server latency without making a network call.
	CloudService._busy = true
	grid_view._do_pouch_deposit()
	assert(not dragged.visible, "The dropped item must disappear before the server replies")
	assert(dragged.position == Vector2(100, -100), "Do not flash the item at its original cell")
	assert(GridManager.find_pos_by_uid(994001) == Vector2i.ZERO)
	await get_tree().process_frame
	grid_view._sync_all_items()
	dragged = grid_view._item_nodes["0,0"] as GridItem
	assert(not dragged.visible, "A board refresh must not reveal the pending item")
	CloudService._request_queue.clear()
	CloudService.pouch_deposit_rejected.emit("network_error")
	assert(dragged.visible, "Rejected deposits must restore the item")
	assert(dragged.position == Vector2.ZERO)
	assert(grid_view._pending_pouch_deposit_uid == 0)

	dragged.position = Vector2(100, -100)
	grid_view._do_pouch_deposit()
	assert(not dragged.visible)
	CloudService._request_queue.clear()
	CloudService.pouch_deposit_confirmed.emit({"pouch": [{"uid": 994001, "id": 5001}]})
	assert(not dragged.visible)
	assert(dragged.is_queued_for_deletion(), "Successful deposits must remove the hidden node without an animation")
	assert(GridManager.is_empty(Vector2i.ZERO))
	assert(not grid_view._item_nodes.has("0,0"))
	assert(grid_view._pending_pouch_deposit_uid == 0)
	assert(StoragePouch.items.size() == 1)
	CloudService._busy = false

	# If synchronization cancels the deposit before submission, restore its visual.
	assert(GridManager.add_item(data, Vector2i.ZERO))
	grid_view._action_sync_needed = true
	grid_view._do_pouch_deposit()
	dragged = grid_view._item_nodes["0,0"] as GridItem
	assert(not dragged.visible)
	assert(StoragePouch._pending_deposit_uid == -1)
	grid_view._cancel_action_sync_waiters("")
	assert(dragged.visible)
	assert(dragged.position == Vector2.ZERO)
	assert(grid_view._pending_pouch_deposit_uid == 0)
	grid_view._action_sync_needed = false
	await get_tree().process_frame
	print("POUCH_DEPOSIT_VISIBILITY_SMOKE_OK pending_hidden=true refresh_hidden=true rejected_restored=true success_no_animation=true cancelled_restored=true")
	get_tree().quit(0)
