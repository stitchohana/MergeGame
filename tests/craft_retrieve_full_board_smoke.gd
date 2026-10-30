extends Node


func _ready() -> void:
	CloudService.online = false
	GridManager.init_grid()
	var table: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
	table["_uid"] = 990001
	table["_craft_init"] = true
	table["_craft_state"] = CraftingService.TableState.READY
	table["_craft_result_id"] = 27001
	table["_craft_stored"] = [{"id": 5001}, {"id": 9001}]
	table["_craft_recipe"] = {"id": 1}
	table["_craft_progress"] = 1.0
	assert(GridManager.add_item(table, Vector2i.ZERO))
	for row: int in range(GridManager.GRID_ROWS):
		for col: int in range(GridManager.GRID_COLS):
			var pos: Vector2i = Vector2i(col, row)
			if pos == Vector2i.ZERO:
				continue
			var filler: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
			filler["_uid"] = 990002 + row * GridManager.GRID_COLS + col
			assert(GridManager.add_item(filler, pos))
	var before: Dictionary = table.duplicate(true)
	var controller: CraftingController = CraftingController.new()
	add_child(controller)
	var rejections: Array[String] = []
	controller.craft_rejected.connect(func(reason: String) -> void: rejections.append(reason))
	controller.try_retrieve(table, Vector2i.ZERO)
	assert(rejections == ["棋盘已满，无法取出制作结果"])
	assert(not controller._craft_retrieve_pending)
	assert(table == before, "full board must retain result and READY state")
	# The server can also reject if its board is full while the client has room.
	GridManager.remove_item(Vector2i(6, 8))
	controller._craft_retrieve_pending = true
	controller._craft_table_item = table
	controller._craft_table_pos = Vector2i.ZERO
	controller._on_craft_retrieve_rejected("no_empty_cell")
	assert(not controller._craft_retrieve_pending)
	assert(table == before, "server rejection must preserve the completed craft")
	var products: Array[int] = []
	controller.craft_retrieve_ready.connect(func(id: int, _uid: int, _pos: Vector2i) -> void: products.append(id))
	controller._craft_table_item = table
	controller._craft_table_pos = Vector2i.ZERO
	controller._on_craft_retrieve_confirmed({"result_id": 27001, "result_uid": 999999})
	assert(products == [27001])
	assert(not table.has("_craft_state") and not table.has("_craft_result_id"))
	print("CRAFT_RETRIEVE_FULL_BOARD_UI_SMOKE_OK")
	get_tree().quit()
