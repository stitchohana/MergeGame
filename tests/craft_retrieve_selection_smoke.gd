extends Node


class TestGridView:
	extends GridView
	var retrieve_requests: Array[Vector2i] = []
	var item_use_requests: int = 0

	func _request_craft_retrieve(_table_item: Dictionary, table_pos: Vector2i) -> void:
		retrieve_requests.append(table_pos)

	func _request_item_use(_item: Dictionary, _pos: Vector2i) -> void:
		item_use_requests += 1


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	GridManager.init_grid()
	var first_pos := Vector2i(1, 2)
	var second_pos := Vector2i(3, 2)
	for pos: Vector2i in [first_pos, second_pos]:
		var table: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
		table["_uid"] = 998000 + pos.x
		table["_craft_init"] = true
		table["_craft_state"] = CraftingService.TableState.READY
		table["_craft_stored"] = []
		table["_craft_result_id"] = 27001
		assert(GridManager.add_item(table, pos))
	var view: TestGridView = TestGridView.new()
	view.grid_item_scene = preload("res://scenes/items/GridItem.tscn")
	view.size = Vector2(Constants.CELL_STEP * 7, Constants.CELL_STEP * 9)
	add_child(view)
	view.set_process_input(false)
	await get_tree().process_frame
	_click(view, first_pos)
	assert(view._selected_key == "1,2")
	assert(view.retrieve_requests.is_empty(), "first click only selects the completed table")
	var detail: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(detail)
	detail.show_item(GridManager.get_item(first_pos) as Dictionary, first_pos)
	assert(detail.status_label.text == "制作完成！再次点击制作台取出")
	_click(view, first_pos)
	assert(view.retrieve_requests == [first_pos], "second click retrieves")
	assert(view.item_use_requests == 0, "tables must not trigger generic item use")
	_click(view, second_pos)
	assert(view._selected_key == "3,2")
	assert(view.retrieve_requests.size() == 1, "switching tables only selects")
	_click(view, first_pos)
	assert(view.retrieve_requests.size() == 1, "returning to a previous table selects again")
	_click(view, first_pos)
	assert(view.retrieve_requests == [first_pos, first_pos])
	view._deselect_all()
	_click(view, first_pos)
	assert(view.retrieve_requests.size() == 2, "deselected table requires selection again")
	var table: Dictionary = GridManager.get_item(first_pos) as Dictionary
	for state: int in [CraftingService.TableState.IDLE, CraftingService.TableState.HAS_ITEMS, CraftingService.TableState.CRAFTING]:
		table["_craft_state"] = state
		_click(view, first_pos)
		assert(view.retrieve_requests.size() == 2, "unfinished tables do not retrieve")
	assert(view.item_use_requests == 0)
	print("CRAFT_RETRIEVE_SELECTION_SMOKE_OK first_select second_retrieve switch reselect unfinished no_generic_use")
	get_tree().quit()


func _click(view: GridView, pos: Vector2i) -> void:
	var point: Vector2 = view.get_global_transform_with_canvas() * (Vector2(pos) * Constants.CELL_STEP + Vector2.ONE * Constants.CELL_STEP * 0.5)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		view._input(event)
