extends Node

var _probe: GameScreen
var _grid: GridView
var _next_uid: int = 970000


func _ready() -> void:
	call_deferred("_run")


# Exercise GridView's synchronous refresh through its actual parent callback.
func _refresh_required_indicators() -> void:
	_probe._refresh_required_indicators()


func _run() -> void:
	GameState.current_board_type = Constants.BoardType.MAIN
	StoragePouch.items = []
	GridManager.init_grid(Constants.BoardType.MAIN)
	# Reproduce the three orders from the reported trace, including JSON floats.
	GameState.meridian_acupoints = []
	for ids: Array in [[27004.0, 27053.0, 28002.0], [28003.0, 6004.0, 27001.0], [27082.0, 2004.0]]:
		var targets: Array = []
		for id: float in ids:
			targets.append({"item_id": id})
		GameState.meridian_acupoints.append({"completed": false, "item_ids": ids, "items": targets})
	_add(27004, Vector2i(0, 0))
	_add(27053, Vector2i(1, 0))
	_add(27001, Vector2i(2, 0))
	var water: Dictionary = _add(9003, Vector2i(5, 5))
	_add(18002, Vector2i(0, 8))
	for x: int in range(1, 5):
		_add(17002 if x < 4 else 17001, Vector2i(x, 8))
	var other_forge: Dictionary = _add(18002, Vector2i(5, 8))
	other_forge["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	other_forge["_craft_stored"] = [{"id": 9002}]
	var sword_forge: Dictionary = _add(18002, Vector2i(6, 8))
	sword_forge["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	sword_forge["_craft_stored"] = [{"id": 2004}]
	_probe = GameScreen.new()
	_grid = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	_probe.grid_view = _grid
	add_child(_grid)
	await get_tree().process_frame
	if not _verify_hints(water, false, "owned_products"):
		return
	# One owned pill must not hide demand for a second copy in another order.
	GameState.meridian_acupoints.append({"item_ids": [27004], "completed": false, "items": [{"item_id": 27004}]})
	if not _verify_hints(water, true, "second_copy_missing"):
		return
	GameState.meridian_acupoints.pop_back()
	GridManager.remove_item(Vector2i(0, 0))
	var working: Dictionary = GridManager.get_item(Vector2i(1, 8)) as Dictionary
	working["_craft_result_id"] = 27004
	for state: int in [CraftingService.TableState.CRAFTING, CraftingService.TableState.READY]:
		working["_craft_state"] = state
		if not _verify_hints(water, false, "covered_by_table_%d" % state):
			return
	# Restored snapshots can provide only the active recipe's result.
	working["_craft_result_id"] = -1
	working["_craft_recipe"] = ConfigDatabase.get_recipes_for_result(27004)[0]
	if not _verify_hints(water, false, "recipe_result_fallback"):
		return
	# Stale result metadata on an idle table does not cover the missing pill.
	working["_craft_state"] = CraftingService.TableState.IDLE
	if not _verify_hints(water, true, "idle_stale_result"):
		return
	# Identical empty furnaces must offer a recipe on only one destination.
	GameState.meridian_acupoints = [{"item_ids": [27004], "completed": false, "items": [{"item_id": 27004}]}]
	for x: int in range(1, 5):
		var furnace: Dictionary = GridManager.get_item(Vector2i(x, 8)) as Dictionary
		furnace["_craft_state"] = CraftingService.TableState.IDLE
		furnace["_craft_stored"] = []
	if not _expect_destinations(water, ["1,8"], "duplicate_empty_tables"):
		return
	var loaded: Dictionary = GridManager.get_item(Vector2i(3, 8)) as Dictionary
	loaded["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	loaded["_craft_stored"] = [{"id": 5004}]
	if not _expect_destinations(water, ["3,8"], "loaded_table_preferred"):
		return
	var same_recipe: Dictionary = GridManager.get_item(Vector2i(2, 8)) as Dictionary
	same_recipe["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	same_recipe["_craft_stored"] = [{"id": 5004}]
	if not _expect_destinations(water, ["2,8"], "duplicate_loaded_tables"):
		return
	# Different recipes may still show together at the same priority, even
	# though both hints display the selected water ingredient.
	GameState.meridian_acupoints[0]["items"].append({"item_id": 28003})
	GameState.meridian_acupoints[0]["item_ids"].append(28003)
	if not _expect_destinations(water, ["2,8", "6,8"], "different_recipes"):
		return
	_grid._clear_crafting_hints()
	_probe.free()
	print("CRAFT_HINT_COVERED_PRODUCTS_SMOKE_OK owned=true duplicate=true crafting=true ready=true fallback=true idle=true")
	get_tree().quit(0)


func _expect_destinations(water: Dictionary, expected: Array, scenario: String) -> bool:
	_grid._show_crafting_hints(water, Vector2i(5, 5), true)
	var actual: Array = []
	for x: int in range(7):
		var key: String = "%d,8" % x
		var table_node: GridItem = _grid._item_nodes[key] as GridItem
		if table_node.craft_hint_bubble.visible:
			actual.append(key)
	if actual != expected:
		push_error("%s: expected destinations %s, got %s" % [scenario, expected, actual])
		get_tree().quit(1)
		return false
	print("CRAFT_HINT_DEDUP_CASE_OK ", scenario)
	return true


func _add(item_id: int, pos: Vector2i) -> Dictionary:
	_next_uid += 1
	var item: Dictionary = ConfigDatabase.get_item_data(item_id).duplicate(true)
	item["_uid"] = _next_uid
	if not GridManager.add_item(item, pos):
		push_error("Failed to set up hint regression item %d at %s" % [item_id, pos])
		get_tree().quit(1)
	return GridManager.get_item(pos) as Dictionary


func _verify_hints(water: Dictionary, expect_alchemy: bool, scenario: String) -> bool:
	# Do not pre-set the require flag: the production click/drag path refreshes it.
	_grid._show_crafting_hints(water, Vector2i(5, 5), true)
	var water_node: GridItem = _grid._item_nodes["5,5"] as GridItem
	var empty_forge: GridItem = _grid._item_nodes["0,8"] as GridItem
	var loaded_forge: GridItem = _grid._item_nodes["6,8"] as GridItem
	var unrelated_forge: GridItem = _grid._item_nodes["5,8"] as GridItem
	if not water_node.is_required() or empty_forge.craft_hint_bubble.visible or not loaded_forge.craft_hint_bubble.visible or unrelated_forge.craft_hint_bubble.visible:
		push_error("%s: loaded compatible forge should be preferred over an empty forge" % scenario)
		get_tree().quit(1)
		return false
	for x: int in range(1, 5):
		var furnace: GridItem = _grid._item_nodes["%d,8" % x] as GridItem
		if furnace.craft_hint_bubble.visible:
			push_error("%s: empty furnace should not compete with a loaded compatible forge" % scenario)
			get_tree().quit(1)
			return false
	# Demand for the second pill remains valid even though a loaded forge has
	# priority over its empty furnace for this interaction.
	var controller: Node = _grid.get("_craft_ctrl") as Node
	var furnace_data: Dictionary = GridManager.get_item(Vector2i(4, 8)) as Dictionary
	var acceptance: Dictionary = controller.call("get_ingredient_hint_debug", furnace_data, 9003) as Dictionary
	if bool(acceptance.get("accepted", false)) != expect_alchemy:
		push_error("%s: alchemy recipe demand changed unexpectedly" % scenario)
		get_tree().quit(1)
		return false
	print("CRAFT_HINT_COVERED_PRODUCTS_CASE_OK ", scenario)
	return true
