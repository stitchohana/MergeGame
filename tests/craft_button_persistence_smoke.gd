extends Node


class TestGridView:
	extends GridView

	func _flush_spawn_action_batch() -> void:
		# Retain queued operations while simulating server replies in the test.
		pass


const TABLE_POS := Vector2i(2, 3)
const OTHER_POS := Vector2i(4, 3)
const SOURCE_POS := Vector2i(0, 3)
const TABLE_UID: int = 995001
const OTHER_UID: int = 995002
const SOURCE_UID: int = 995003


func _ready() -> void:
	CloudService.online = false
	await get_tree().process_frame
	var recipes: Array = ConfigDatabase.get_recipes_for_item(17001)
	var recipe: Dictionary = {}
	for candidate: Dictionary in recipes:
		if int(candidate.get("id", 0)) == 1:
			recipe = candidate
	assert(not recipe.is_empty())
	GridManager.init_grid()
	var table: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
	table["_uid"] = TABLE_UID
	table["_craft_init"] = true
	table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table["_craft_stored"] = [{"id": 5001}]
	assert(GridManager.add_item(table, TABLE_POS))
	var other: Dictionary = ConfigDatabase.get_item_data(17002).duplicate(true)
	other["_uid"] = OTHER_UID
	other["_craft_init"] = true
	other["_craft_state"] = CraftingService.TableState.CRAFTING
	other["_craft_stored"] = []
	other["_craft_recipe"] = recipe
	other["_craft_start_time"] = int(Time.get_unix_time_from_system() * 1000)
	assert(GridManager.add_item(other, OTHER_POS))
	var ingredient: Dictionary = ConfigDatabase.get_item_data(9001).duplicate(true)
	ingredient["_uid"] = SOURCE_UID
	assert(GridManager.add_item(ingredient, SOURCE_POS))

	var view: TestGridView = TestGridView.new()
	view.grid_item_scene = preload("res://scenes/items/GridItem.tscn")
	view.size = Vector2(Constants.CELL_STEP * 7, Constants.CELL_STEP * 9)
	add_child(view)
	await get_tree().process_frame
	var controller: CraftingController = view._craft_ctrl as CraftingController
	assert(not controller.is_button_visible())
	view._start_drag(SOURCE_POS)
	view._handle_crafting_drop(TABLE_POS, GridManager.get_item(TABLE_POS) as Dictionary)
	view._is_dragging = false
	assert(controller.is_button_visible(), "Completing a recipe must immediately show the button")
	assert(controller._craft_table_pos == TABLE_POS)
	assert((controller._craft_button as CraftButton).get_output_item_id() == 27001)

	# Confirmation restores all tables, including the other active craft. Its
	# timer/state notification must not hide the newly craftable table's button.
	view._pending_spawn_actions.clear()
	view._spawn_action_batch_in_flight = true
	view._on_action_batch_confirmed({"grid": [
		{"id": 17001, "uid": TABLE_UID, "col": TABLE_POS.x, "row": TABLE_POS.y,
			"craft": {"_craft_init": true, "_craft_state": CraftingService.TableState.HAS_ITEMS,
				"_craft_stored": [{"id": 5001}, {"id": 9001}], "_craft_recipe": recipe}},
		{"id": 17002, "uid": OTHER_UID, "col": OTHER_POS.x, "row": OTHER_POS.y,
			"craft": {"_craft_init": true, "_craft_state": CraftingService.TableState.CRAFTING,
				"_craft_stored": [], "_craft_recipe": recipe,
				"_craft_start_time": int(Time.get_unix_time_from_system() * 1000)}},
	]})
	await get_tree().process_frame
	assert(controller.is_button_visible(), "Another crafting table's restore must not hide the button")
	assert(controller._craft_table_pos == TABLE_POS)
	var ready_table: Dictionary = GridManager.get_item(TABLE_POS) as Dictionary
	var other_table: Dictionary = GridManager.get_item(OTHER_POS) as Dictionary
	CraftingService.complete_craft_now(other_table)
	assert(controller.is_button_visible())
	CraftingService.retrieve(other_table)
	assert(controller.is_button_visible())
	CraftingService.add_ingredient(other_table, {"id": 5001})
	assert(controller.is_button_visible(), "Incomplete materials on another table must not hide the button")

	# Keep the button bound to the live table after position updates and ensure
	# its click requests crafting from that table, even after another update.
	var moved_pos := Vector2i(3, 3)
	assert(GridManager.move_item(TABLE_POS, moved_pos))
	assert(controller._craft_table_pos == moved_pos)
	var clicked_positions: Array[Vector2i] = []
	controller.craft_start_requested.connect(func(pos: Vector2i): clicked_positions.append(pos))
	(controller._craft_button as CraftButton).craft_btn.pressed.emit()
	assert(clicked_positions == [moved_pos])
	CraftingService.start_craft(ready_table)
	assert(not controller.is_button_visible(), "Starting this table must hide its button")

	# Removing a required material or replacing a snapshot with an incomplete
	# recipe must hide the button belonging to that table.
	ready_table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	ready_table["_craft_stored"] = [{"id": 5001}, {"id": 9001}]
	ready_table["_craft_recipe"] = recipe
	controller._on_table_state_changed(ready_table, CraftingService.TableState.HAS_ITEMS)
	assert(controller.is_button_visible())
	CraftingService.remove_ingredient(ready_table, 9001)
	assert(not controller.is_button_visible())
	CraftingService.add_ingredient(ready_table, {"id": 9001})
	assert(controller.is_button_visible())
	ready_table["_craft_recipe"] = {}
	GridManager.grid_updated.emit()
	assert(not controller.is_button_visible(), "An authoritative incomplete recipe must hide a stale button")
	CraftingService.reset_all()
	print("CRAFT_BUTTON_PERSISTENCE_SMOKE_OK drop=true sync=true unrelated_tables=true move=true click=true own_state=true")
	get_tree().quit()
