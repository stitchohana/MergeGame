extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var previous_orders: Array = GameState.meridian_acupoints.duplicate(true)
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27002}]}]
	var item_scene: PackedScene = load("res://scenes/items/GridItem.tscn") as PackedScene
	assert(item_scene != null)
	var item: GridItem = item_scene.instantiate() as GridItem
	add_child(item)
	await get_tree().process_frame

	var icon: Texture2D = load("res://assets/items/icons_simple/5001.png") as Texture2D
	assert(icon != null)
	item.set_required(true)
	assert(item.is_required())
	item.show_crafting_hint(icon)
	assert(item.craft_hint_bubble.visible)
	assert(item.craft_hint_icon.texture == icon)
	item.hide_crafting_hint()
	assert(not item.craft_hint_bubble.visible)

	var config_database: Node = get_node("/root/ConfigDatabase")
	var controller_script: GDScript = load("res://scenes/grid/CraftingController.gd") as GDScript
	var controller: Node = controller_script.new()
	add_child(controller)
	var table_item: Dictionary = (config_database.call("get_item_data", 17001) as Dictionary).duplicate(true)
	assert(not table_item.is_empty())
	table_item["_craft_state"] = 0
	table_item["_craft_stored"] = []
	assert(controller.call("can_accept_ingredient", table_item, 5001))
	assert(not controller.call("can_accept_ingredient", table_item, 999999))
	table_item["_craft_state"] = 3
	assert(not controller.call("can_accept_ingredient", table_item, 5002))
	var busy_hint_result: Dictionary = controller.call("get_ingredient_hint_debug", table_item, 5002) as Dictionary
	assert(bool(busy_hint_result.get("accepted", false)))
	assert(str(busy_hint_result.get("reason", "")) == "required_recipe_supported_table_busy")
	var forge_table: Dictionary = (config_database.call("get_item_data", 18002) as Dictionary).duplicate(true)
	forge_table["_craft_state"] = 0
	forge_table["_craft_stored"] = []
	var unrelated_hint_result: Dictionary = controller.call("get_ingredient_hint_debug", forge_table, 9002) as Dictionary
	assert(not bool(unrelated_hint_result.get("accepted", false)))
	assert(str(unrelated_hint_result.get("reason", "")) == "ingredient_not_in_required_recipes")
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}]}]
	var recursive_recipe_ids: Dictionary = controller.call("_get_required_recipe_ids") as Dictionary
	assert(recursive_recipe_ids.has(32))
	assert(recursive_recipe_ids.has(81))
	assert(recursive_recipe_ids.has(2))
	var requirement_probe: GameScreen = GameScreen.new()
	var recursive_required_ids: Dictionary = {}
	requirement_probe.call("_collect_recipe_material_ids", 27081, recursive_required_ids, {})
	assert(not recursive_required_ids.has(27081))
	assert(recursive_required_ids.has(27002))
	assert(recursive_required_ids.has(5002))
	assert(recursive_required_ids.has(9002))
	requirement_probe.free()
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27002}]}]

	item.queue_free()
	await get_tree().process_frame

	var grid_manager: Node = get_node("/root/GridManager")
	grid_manager.call("init_grid", 0)
	var ingredient_item: Dictionary = (config_database.call("get_item_data", 9002) as Dictionary).duplicate(true)
	ingredient_item["_uid"] = 900001
	var second_ingredient_item: Dictionary = (config_database.call("get_item_data", 5002) as Dictionary).duplicate(true)
	second_ingredient_item["_uid"] = 900005
	var intermediate_item: Dictionary = (config_database.call("get_item_data", 27002) as Dictionary).duplicate(true)
	intermediate_item["_uid"] = 900006
	var order_product_item: Dictionary = (config_database.call("get_item_data", 27081) as Dictionary).duplicate(true)
	order_product_item["_uid"] = 900007
	var board_table: Dictionary = table_item.duplicate(true)
	board_table["_uid"] = 900002
	var board_forge_table: Dictionary = forge_table.duplicate(true)
	board_forge_table["_uid"] = 900003
	assert(grid_manager.call("add_item", ingredient_item, Vector2i(1, 2)))
	assert(grid_manager.call("add_item", second_ingredient_item, Vector2i(2, 2)))
	assert(grid_manager.call("add_item", intermediate_item, Vector2i(5, 2)))
	assert(grid_manager.call("add_item", board_table, Vector2i(3, 3)))
	assert(grid_manager.call("add_item", board_forge_table, Vector2i(4, 3)))
	var stored_board_table: Dictionary = grid_manager.call("get_item", Vector2i(3, 3)) as Dictionary
	stored_board_table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	stored_board_table["_craft_stored"] = [{"id": 27002, "uid": 900004}]
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}]}]
	var reserved_recipe_ids: Dictionary = controller.call("_get_required_recipe_ids") as Dictionary
	assert(reserved_recipe_ids.has(32))
	assert(reserved_recipe_ids.has(81))
	assert(reserved_recipe_ids.has(2))
	stored_board_table["_craft_state"] = CraftingService.TableState.READY
	stored_board_table["_craft_stored"] = []
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27002}]}]

	var grid_scene: PackedScene = load("res://scenes/grid/GridView.tscn") as PackedScene
	var grid_view: GridView = grid_scene.instantiate() as GridView
	add_child(grid_view)
	await get_tree().process_frame
	var item_nodes: Dictionary = grid_view.get("_item_nodes") as Dictionary
	var source_node: GridItem = item_nodes.get("1,2") as GridItem
	var second_source_node: GridItem = item_nodes.get("2,2") as GridItem
	var intermediate_node: GridItem = item_nodes.get("5,2") as GridItem
	var table_node: GridItem = item_nodes.get("3,3") as GridItem
	var forge_table_node: GridItem = item_nodes.get("4,3") as GridItem
	assert(source_node != null and second_source_node != null and intermediate_node != null and table_node != null and forge_table_node != null)
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}]}]
	var recursive_screen_probe: GameScreen = GameScreen.new()
	recursive_screen_probe.grid_view = grid_view
	recursive_screen_probe.call("_refresh_required_indicators")
	assert(intermediate_node.is_required())
	assert(source_node.is_required())
	assert(second_source_node.is_required())
	assert(grid_manager.call("add_item", order_product_item, Vector2i(6, 2)))
	await get_tree().process_frame
	var order_product_node: GridItem = (grid_view.get("_item_nodes") as Dictionary).get("6,2") as GridItem
	assert(order_product_node != null)
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}, {"item_id": 27081}]}]
	recursive_screen_probe.call("_refresh_required_indicators")
	assert(intermediate_node.is_required())
	assert(source_node.is_required())
	assert(second_source_node.is_required())
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}]}]
	recursive_screen_probe.call("_refresh_required_indicators")
	assert(order_product_node.is_required())
	assert(not intermediate_node.is_required())
	assert(not source_node.is_required())
	assert(not second_source_node.is_required())
	grid_manager.call("remove_item", Vector2i(6, 2))
	await get_tree().process_frame
	stored_board_table["_craft_state"] = CraftingService.TableState.READY
	stored_board_table["_craft_result_id"] = 27081
	stored_board_table["_craft_recipe"] = {"result": 27081, "ingredients": [27002, 9004]}
	recursive_screen_probe.call("_refresh_required_indicators")
	assert(not intermediate_node.is_required())
	assert(not source_node.is_required())
	assert(not second_source_node.is_required())
	stored_board_table.erase("_craft_result_id")
	stored_board_table.erase("_craft_recipe")
	stored_board_table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	stored_board_table["_craft_stored"] = [{"id": 27002, "uid": 900004}]
	recursive_screen_probe.call("_refresh_required_indicators")
	assert(not intermediate_node.is_required())
	assert(not source_node.is_required())
	assert(not second_source_node.is_required())
	# A product already on the board must satisfy its matching order even when
	# other active orders still need recipe products.
	stored_board_table["_craft_state"] = CraftingService.TableState.IDLE
	stored_board_table["_craft_stored"] = []
	GameState.meridian_acupoints = [
		{"completed": false, "items": [{"item_id": 27002}]},
		{"completed": false, "items": [{"item_id": 27054}]},
	]
	recursive_screen_probe.call("_refresh_required_indicators")
	assert(intermediate_node.is_required())
	assert(not source_node.is_required())
	assert(not second_source_node.is_required())
	recursive_screen_probe.free()
	stored_board_table["_craft_state"] = CraftingService.TableState.READY
	stored_board_table["_craft_stored"] = []
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27002}]}]
	source_node.set_required(true)
	var click_position := Vector2(Constants.CELL_STEP + Constants.CELL_SIZE * 0.5, Constants.CELL_STEP * 2 + Constants.CELL_SIZE * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click_position
	grid_view._input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click_position
	grid_view._input(release)
	assert(table_node.craft_hint_bubble.visible)
	assert(not forge_table_node.craft_hint_bubble.visible)
	GameState.meridian_acupoints = previous_orders

	print("CRAFT_HINT_SMOKE_OK visible=true click_trigger=true unrelated_table_hidden=true table=17001 ingredient=9002")
	get_tree().quit(0)
