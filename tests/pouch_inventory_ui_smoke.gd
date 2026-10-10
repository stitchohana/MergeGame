extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	CloudService.online = false
	GameState.main_grid_cache = []
	GameState.meridian_acupoints = []
	StoragePouch.restore_from_server([])
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	UIManager.push_screen(screen)
	for frame: int in range(5):
		await get_tree().process_frame
	GridManager.init_grid()
	var order: Dictionary = {"items": [{"item_id": 5001}, {"item_id": 5001}], "item_ids": [5001, 5001], "completed": false}
	GameState.meridian_acupoints = [order]
	screen._display_meridian()
	assert(screen._get_requirement_priority(order) == 0)
	StoragePouch.restore_from_server([{"uid": 1, "id": 5001}])
	await get_tree().process_frame
	await get_tree().process_frame
	assert(screen._get_requirement_priority(order) == 1)
	var entry: RequirementEntry = screen.requirement_list.get_order_entries()[0]
	var widgets: Array[Node] = entry.get_node("ItemsContainer").get_children()
	assert((widgets[0] as ItemWidget)._is_selected)
	assert(not (widgets[1] as ItemWidget)._is_selected, "One instance cannot select two requirement slots")
	StoragePouch.restore_from_server([{"uid": 1, "id": 5001}, {"uid": 2, "id": 5001}])
	await get_tree().process_frame
	await get_tree().process_frame
	assert(screen._check_can_complete(order))
	assert((widgets[1] as ItemWidget)._is_selected)
	assert(GridManager.count_items() == 0)
	assert(GridManager.count_empty_cells() == 63)
	var used: Dictionary = {}
	assert(screen._find_grid_item_source(5001, used).get("source") == "pouch")
	assert(screen._find_grid_item_source(5001, used).get("source") == "pouch")
	assert(screen._find_grid_item_source(5001, used).is_empty())
	GridManager.populate_from_server([{"uid": 1, "id": 5001, "col": 0, "row": 0}])
	assert(GridManager.get_inventory_items().size() == 2, "Transfer overlap must deduplicate UID")
	assert(screen._count_grid_item(5001) == 2)
	StoragePouch.restore_from_server([{"uid": 2, "id": 5001}])
	assert(screen._check_can_complete(order), "Mixed inventory must submit")
	GridManager.init_grid()
	StoragePouch.restore_from_server([{"uid": 3, "id": 5001, "immovable": true}])
	assert(screen._get_requirement_priority(order) == 0)
	StoragePouch.restore_from_server([5001, 5001])
	assert(screen._check_can_complete(order), "Legacy pouch entries count separately")

	var recipe: Dictionary = ConfigDatabase.get_recipes_for_result(27001)[0] as Dictionary
	GridManager.populate_from_server([{"uid": 10, "id": 5001, "col": 0, "row": 0}])
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27001}]}]
	StoragePouch.restore_from_server([{"uid": 11, "id": 27001}])
	screen._refresh_required_indicators()
	var material: GridItem = screen.grid_view._item_nodes["0,0"] as GridItem
	assert(not material.is_required(), "Finished pouch product must suppress missing-material markers")
	assert(screen._get_finished_order_item_counts().get(27001) == 1)
	screen.detail_panel._current_recipes = [recipe]
	assert(screen.detail_panel._find_order_recipe([]).is_empty(), "Do not recommend making an already owned product")
	StoragePouch.restore_from_server([{"uid": 12, "id": 9001}])
	assert(not screen.detail_panel._find_order_recipe([]).is_empty())
	assert(screen.detail_panel._count_board_available_item_ids().get(9001) == 1)
	assert(screen.grid_view._launcher_ctrl._get_outstanding_order_item_counts().is_empty())

	var table_id: int = 17002
	var recipe_id: int = int(ConfigDatabase.get_recipes_for_item(table_id)[0].get("id"))
	StoragePouch.restore_from_server([{"uid": 20, "id": table_id}, {"uid": 21, "id": 11003}])
	var popup: RecipePopup = preload("res://scenes/ui/main/RecipePopup.tscn").instantiate() as RecipePopup
	add_child(popup)
	assert(int(popup._find_highest_board_table(recipe_id).get("id", 0)) == table_id)
	var source_popup: RecipeSourcePopup = preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
	add_child(source_popup)
	assert(int(source_popup._find_crafting_table_for_recipe(recipe_id).get("id", 0)) == table_id)
	var path: CraftPathView = preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	add_child(path)
	assert(int(path._get_present_launchers_for_item(5001)[0].get("id", 0)) == 11003)
	GameState.main_grid_cache = [{"uid": 30, "id": 17003, "col": 0, "row": 0}]
	GridManager.init_grid(Constants.BoardType.BATTLE)
	assert(GridManager.get_inventory_item_counts(true, true, true).has(17003))
	assert(GridManager.get_inventory_item_counts().has(table_id))
	assert(not GridManager.get_inventory_item_counts().has(17003))
	GridManager.init_grid()

	var stored: Dictionary = {"uid": 40, "id": 17001, "charges": 2, "atk_base": 9,
		"craft": {"_craft_state": CraftingService.TableState.READY, "_craft_result_id": 27001},
		"storage": {"items": [{"id": 6001}], "max_slots": 3}}
	StoragePouch.restore_from_server([stored])
	StoragePouch._pending_withdraw_uid = 40
	StoragePouch._on_withdraw_confirmed({"pouch": [], "item": stored, "col": 2, "row": 3})
	var retrieved: Dictionary = GridManager.find_by_uid(40)
	assert(int(retrieved.get("charges", 0)) == 2)
	assert(int(retrieved.get("atk_base", 0)) == 9)
	assert(int(retrieved.get("_craft_result_id", 0)) == 27001)
	assert((retrieved.get("storage", {}) as Dictionary).has("items"))
	await get_tree().create_timer(0.6).timeout
	screen.on_exit()
	GridManager.init_grid(Constants.BoardType.BATTLE)
	var cached: Dictionary = GridManager.get_inventory_items(true)[0].data
	assert(int(cached.get("_uid", 0)) == 40)
	assert(int(cached.get("_craft_result_id", 0)) == 27001)
	GridManager.init_grid()
	StoragePouch.restore_from_server([{"uid": 50, "id": 5001}, {"uid": 51, "id": 6001}])
	await screen._on_meridian_confirmed({"grid": [], "pouch": [{"uid": 51, "id": 6001}],
		"meridian_acupoints": [], "pouch_capacity": 7, "pouch_next_unlock_cost": 100})
	assert(StoragePouch.items.size() == 1)
	assert(not GridManager.get_inventory_item_counts().has(5001))
	popup.queue_free()
	source_popup.queue_free()
	path.queue_free()
	await get_tree().create_timer(0.6).timeout
	UIManager.clear_all_screens()
	await get_tree().process_frame
	await get_tree().process_frame
	print("POUCH_INVENTORY_UI_SMOKE_OK")
	get_tree().quit(0)
