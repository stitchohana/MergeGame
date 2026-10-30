extends Node


func _ready() -> void:
	await get_tree().process_frame
	GameState.current_board_type = Constants.BoardType.MAIN
	StoragePouch.items = []
	GameState.meridian_acupoints = [{
		"completed": false, "item_ids": [27001], "items": [{"item_id": 27001}],
	}]
	GridManager.init_grid(Constants.BoardType.MAIN)
	var water: Dictionary = ConfigDatabase.get_item_data(9001).duplicate(true)
	water["_uid"] = 940001
	var furnace: Dictionary = ConfigDatabase.get_item_data(17002).duplicate(true)
	furnace["_uid"] = 940002
	furnace["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	furnace["_craft_stored"] = [{"id": 5001, "uid": 940003}]
	var forge: Dictionary = ConfigDatabase.get_item_data(18002).duplicate(true)
	forge["_uid"] = 940004
	forge["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	forge["_craft_stored"] = [{"id": 9001, "uid": 940005}]
	assert(GridManager.add_item(water, Vector2i(1, 2)))
	assert(GridManager.add_item(furnace, Vector2i(3, 3)))
	assert(GridManager.add_item(forge, Vector2i(4, 3)))
	furnace = GridManager.get_item(Vector2i(3, 3)) as Dictionary
	var grid: GridView = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	add_child(grid)
	await get_tree().process_frame
	var screen: GameScreen = GameScreen.new()
	screen.grid_view = grid
	screen._refresh_required_indicators()
	var water_node: GridItem = grid._item_nodes["1,2"] as GridItem
	var furnace_node: GridItem = grid._item_nodes["3,3"] as GridItem
	var forge_node: GridItem = grid._item_nodes["4,3"] as GridItem
	assert(water_node.is_required(), "Water in a forge must not hide the alchemy material require badge")
	# 27081 has a water recipe and a non-water recipe. With no selected water
	# path, only the non-water branch is advertised as a requirement.
	GameState.meridian_acupoints = [{"item_ids": [27081], "completed": false, "items": [{"item_id": 27081}]}]
	var alt_water: Dictionary = ConfigDatabase.get_item_data(9004).duplicate(true)
	alt_water["_uid"] = 940008
	assert(GridManager.add_item(alt_water, Vector2i(2, 2)))
	screen._refresh_required_indicators()
	assert(not (grid._item_nodes["2,2"] as GridItem).is_required())
	GameState.meridian_acupoints = [{
		"completed": false, "item_ids": [27001], "items": [{"item_id": 27001}],
	}]
	screen._refresh_required_indicators()
	grid._show_crafting_hints(water, Vector2i(1, 2), false)
	assert(furnace_node.craft_hint_bubble.visible)
	assert(not forge_node.craft_hint_bubble.visible)
	assert(furnace_node.craft_hint_icon.texture == water_node.icon_rect.texture)
	grid._clear_crafting_hints()
	var launcher: LauncherController = LauncherController.new()
	assert(not launcher._get_outstanding_order_item_counts().has(9001))
	GridManager.remove_item(Vector2i(1, 2))
	assert(int(launcher._get_outstanding_order_item_counts().get(9001, 0)) == 1)
	assert(GridManager.add_item(water, Vector2i(1, 2)))
	water_node = grid._item_nodes["1,2"] as GridItem
	# A compatible furnace does reserve the material already put inside it.
	furnace["_craft_stored"] = [{"id": 9001, "uid": 940006}]
	screen._refresh_required_indicators()
	assert(not water_node.is_required())
	# Stored materials for another recipe in the same furnace cannot satisfy it.
	furnace["_craft_stored"] = [{"id": 9001}, {"id": 3001}]
	screen._refresh_required_indicators()
	assert(water_node.is_required())
	# Completed products still suppress their material badges.
	var product: Dictionary = ConfigDatabase.get_item_data(27001).duplicate(true)
	product["_uid"] = 940007
	assert(GridManager.add_item(product, Vector2i(5, 3)))
	screen._refresh_required_indicators()
	assert(not water_node.is_required())
	_test_in_progress_materials(screen, grid, furnace)
	_test_shared_water(screen, grid, furnace, GridManager.get_item(Vector2i(4, 3)) as Dictionary)
	screen.free()
	launcher.free()
	print("CRAFT_MATERIAL_RESERVATION_SMOKE_OK require=true furnace_hint=true unrelated_table=true compatible_reservation=true in_progress=true alternate_recipes=true duplicate_orders=true shared_water=true")
	get_tree().quit()


func _test_in_progress_materials(screen: GameScreen, grid: GridView, furnace: Dictionary) -> void:
	# 27081 has alternate recipes using 9004 and 3002. Starting either recipe
	# must suppress both branches, including snapshots that only have result_id.
	GameState.meridian_acupoints = [{"item_ids": [27081], "completed": false, "items": [{"item_id": 27081}]}]
	var positions: Dictionary = {5002: Vector2i(0, 4), 9004: Vector2i(1, 4), 3002: Vector2i(2, 4)}
	for item_id: int in positions:
		var material: Dictionary = ConfigDatabase.get_item_data(item_id).duplicate(true)
		material["_uid"] = 950000 + item_id
		assert(GridManager.add_item(material, positions[item_id]))
	furnace["_craft_stored"] = []
	furnace["_craft_state"] = CraftingService.TableState.CRAFTING
	furnace["_craft_result_id"] = 27081
	furnace["_craft_recipe"] = {}
	screen._refresh_required_indicators()
	_assert_material_badges(grid, positions, false)
	# The configured recipe fallback also works when the result field is absent.
	furnace["_craft_result_id"] = -1
	furnace["_craft_recipe"] = ConfigDatabase.get_recipes_for_result(27081)[0]
	screen._refresh_required_indicators()
	_assert_material_badges(grid, positions, false)
	# One craft cannot also cover a second requested copy or another product.
	GameState.meridian_acupoints[0]["items"].append({"item_id": 27081})
	GameState.meridian_acupoints[0]["item_ids"].append(27081)
	screen._refresh_required_indicators()
	_assert_material_badges(grid, positions, {5002: true, 9004: false, 3002: true})
	GameState.meridian_acupoints[0]["items"] = [{"item_id": 27081}, {"item_id": 27002}]
	GameState.meridian_acupoints[0]["item_ids"] = [27081, 27002]
	screen._refresh_required_indicators()
	assert((grid._item_nodes["0,4"] as GridItem).is_required())
	assert(not (grid._item_nodes["1,4"] as GridItem).is_required())
	assert(not (grid._item_nodes["2,4"] as GridItem).is_required())
	# Ready-but-uncollected output likewise satisfies only one copy.
	furnace["_craft_state"] = CraftingService.TableState.READY
	GameState.meridian_acupoints[0]["items"] = [{"item_id": 27081}, {"item_id": 27081}]
	GameState.meridian_acupoints[0]["item_ids"] = [27081, 27081]
	screen._refresh_required_indicators()
	_assert_material_badges(grid, positions, {5002: true, 9004: false, 3002: true})
	GameState.meridian_acupoints[0]["items"] = [{"item_id": 27081}]
	GameState.meridian_acupoints[0]["item_ids"] = [27081]
	screen._refresh_required_indicators()
	_assert_material_badges(grid, positions, false)
	# An idle table's current preview governs demand, regardless of stale result metadata.
	furnace["_craft_state"] = CraftingService.TableState.IDLE
	screen._refresh_required_indicators()
	_assert_material_badges(grid, positions, {5002: true, 9004: true, 3002: false})


func _assert_material_badges(grid: GridView, positions: Dictionary, expected: Variant) -> void:
	for item_id: int in positions:
		var pos: Vector2i = positions[item_id]
		var node: GridItem = grid._item_nodes["%d,%d" % [pos.x, pos.y]] as GridItem
		var should_require: bool = (
			bool(expected.get(item_id, false)) if expected is Dictionary else bool(expected)
		)
		assert(node.is_required() == should_require, "Unexpected require badge for material %d" % item_id)


func _test_shared_water(screen: GameScreen, grid: GridView, furnace: Dictionary, forge: Dictionary) -> void:
	var water: Dictionary = ConfigDatabase.get_item_data(9003).duplicate(true)
	water["_uid"] = 960001
	assert(GridManager.add_item(water, Vector2i(5, 6)))
	var water_node: GridItem = grid._item_nodes["5,6"] as GridItem
	var furnace_node: GridItem = grid._item_nodes["3,3"] as GridItem
	var forge_node: GridItem = grid._item_nodes["4,3"] as GridItem
	# The alchemy recipe is selected by 5004, the sword recipe by 2004.
	for reverse: bool in [false, true]:
		var targets: Array = [{"item_id": 27004}, {"item_id": 28003}]
		if reverse:
			targets.reverse()
		GameState.meridian_acupoints = [{"item_ids": targets.map(func(target: Dictionary) -> int: return int(target.item_id)), "completed": false, "items": targets}]
		furnace["_craft_state"] = CraftingService.TableState.HAS_ITEMS
		forge["_craft_state"] = CraftingService.TableState.HAS_ITEMS
		furnace["_craft_stored"] = [{"id": 5004}, {"id": 9003}]
		forge["_craft_stored"] = [{"id": 2004}]
		screen._refresh_required_indicators()
		assert(water_node.is_required(), "Furnace water cannot satisfy the sword, regardless of order sequence")
		grid._show_crafting_hints(water, Vector2i(5, 6), false)
		assert(forge_node.craft_hint_bubble.visible)
		assert(not furnace_node.craft_hint_bubble.visible)
		grid._clear_crafting_hints()
		forge["_craft_stored"] = [{"id": 2004}, {"id": 9003}]
		furnace["_craft_stored"] = [{"id": 5004}]
		screen._refresh_required_indicators()
		assert(water_node.is_required(), "Forge water cannot satisfy the pill")
		grid._show_crafting_hints(water, Vector2i(5, 6), false)
		assert(furnace_node.craft_hint_bubble.visible)
		assert(not forge_node.craft_hint_bubble.visible)
		grid._clear_crafting_hints()
		furnace["_craft_stored"].append({"id": 9003})
		screen._refresh_required_indicators()
		assert(not water_node.is_required(), "Both loaded waters satisfy both targets")
	# A spare furnace for a product already crafting must not steal sword water.
	forge["_craft_stored"] = [{"id": 2004}]
	var working_furnace: Dictionary = ConfigDatabase.get_item_data(17002).duplicate(true)
	working_furnace["_uid"] = 960002
	working_furnace["_craft_state"] = CraftingService.TableState.CRAFTING
	working_furnace["_craft_result_id"] = 27004
	assert(GridManager.add_item(working_furnace, Vector2i(6, 6)))
	screen._refresh_required_indicators()
	assert(water_node.is_required())
	GridManager.remove_item(Vector2i(6, 6))
	# Two copies of one pill also need two loaded tables, not two reservations
	# from a single table; the second table is claimed only by the second copy.
	forge["id"] = 17002
	forge["_craft_stored"] = [{"id": 5004}]
	GameState.meridian_acupoints = [{"item_ids": [27004, 27004], "completed": false, "items": [{"item_id": 27004}, {"item_id": 27004}]}]
	screen._refresh_required_indicators()
	assert(water_node.is_required())
	forge["_craft_stored"].append({"id": 9003})
	screen._refresh_required_indicators()
	assert(not water_node.is_required())
