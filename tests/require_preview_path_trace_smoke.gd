extends Node

const RecipeHints := preload("res://scripts/utils/CraftingRecipeHints.gd")
var _screen: GameScreen
var _grid: GridView
var _panel: ItemDetailPanel


func _ready() -> void:
	call_deferred("_run")


func _refresh_required_indicators() -> void:
	_screen._refresh_required_indicators()


func _run() -> void:
	CloudService.online = false
	GameState.current_board_type = Constants.BoardType.MAIN
	GridManager.init_grid()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/require_preview_path_trace.json")) as Dictionary
	GameState.meridian_acupoints = fixture["orders"] as Array
	StoragePouch.items = fixture["pouch"] as Array
	for summary: Dictionary in fixture["tables"]:
		var table: Dictionary = _add(summary)
		table["_craft_init"] = true
		table["_craft_state"] = int(summary["state"])
		table["_craft_stored"] = summary["stored"].duplicate(true)
	for summary: Dictionary in fixture["board"]:
		_add(summary)
	_screen = GameScreen.new()
	_grid = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	_screen.grid_view = _grid
	add_child(_grid)
	_panel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(_panel)
	await get_tree().process_frame
	var owner: Dictionary = GridManager.find_by_uid(4635)
	var water: Dictionary = GridManager.find_by_uid(5134)
	assert(not owner.is_empty() and int(water.get("id", 0)) == 9004)
	# Actual trace: rice was already deposited, while another table held a
	# different recipe's water. The owner's missing water must still be required.
	_expect_water_path(owner, water)
	# Before depositing rice the preview already chooses the water route.
	var rice: Dictionary = owner["_craft_stored"][0]
	owner["_craft_stored"] = []
	owner["_craft_state"] = CraftingService.TableState.IDLE
	var rice_data: Dictionary = ConfigDatabase.get_item_data(5002).duplicate(true)
	rice_data["_uid"] = rice["uid"]
	assert(GridManager.add_item(rice_data, Vector2i(2, 8)))
	_expect_water_path(owner, water)
	# Deposit through the real service; require must remain on the same path.
	assert(not CraftingService.add_ingredient(owner, rice_data))
	GridManager.remove_item(Vector2i(2, 8))
	_expect_water_path(owner, water)
	# Once this owner stores its water the duplicate board waters stop being
	# required, even though other tables still own different water recipes.
	assert(CraftingService.add_ingredient(owner, water))
	_screen._refresh_required_indicators()
	assert(not _water_node(water).is_required())
	# Active/ready output covers the order and suppresses alternative materials.
	for state: int in [CraftingService.TableState.CRAFTING, CraftingService.TableState.READY]:
		owner["_craft_state"] = state
		owner["_craft_result_id"] = 27081
		_screen._refresh_required_indicators()
		assert(not _water_node(water).is_required())
		var required: Dictionary = {}
		# Recursion must use the same assigned path for an intermediate product.
		_screen._collect_recipe_dependency_ids(27081, required, {}, {}, {9004: 7},
			{27081: ConfigDatabase.get_recipes_for_result(27081)[0]})
		assert(required.has(9004) and not required.has(3002))
	_screen.free()
	_panel.clear()
	print("REQUIRE_PREVIEW_PATH_TRACE_SMOKE_OK trace_replay loaded empty deposit reserved_elsewhere dedup crafting ready nested")
	get_tree().quit()


func _expect_water_path(owner: Dictionary, water: Dictionary) -> void:
	_screen._refresh_required_indicators()
	_panel.show_item(owner)
	var assignments: Array[Dictionary] = RecipeHints.build_assignments()
	assert(int(RecipeHints.get_table_recipe(owner, assignments).get("id", 0)) == 32)
	# Empty tables expose the assigned recipe through destination hints; the
	# detail panel only shows a candidate output once a material is deposited.
	var expected_output: int = 0 if CraftingService.get_stored_items(owner).is_empty() else 27081
	assert(_panel.get_output_item_id() == expected_output)
	assert(_water_node(water).is_required(), "preview recipe 32 requires board water before and after rice deposit")
	_grid._show_crafting_hints(water, GridManager.find_pos_by_uid(int(water["_uid"])), true)
	assert(_grid._craft_hint_nodes.size() == 1)
	assert(int(_grid._craft_hint_nodes[0].item_data.get("_uid", 0)) == 4635)
	_grid._clear_crafting_hints()


func _water_node(water: Dictionary) -> GridItem:
	var pos: Vector2i = GridManager.find_pos_by_uid(int(water["_uid"]))
	return _grid._item_nodes["%d,%d" % [pos.x, pos.y]] as GridItem


func _add(summary: Dictionary) -> Dictionary:
	var data: Dictionary = ConfigDatabase.get_item_data(int(summary["id"])).duplicate(true)
	data["_uid"] = int(summary["uid"])
	data["immovable"] = bool(summary.get("immovable", false))
	var coordinates: PackedStringArray = str(summary["pos"]).trim_prefix("(").trim_suffix(")").split(",")
	var pos := Vector2i(int(coordinates[0]), int(coordinates[1]))
	assert(GridManager.add_item(data, pos))
	return GridManager.get_item(pos) as Dictionary
