extends Node

var _probe: GameScreen
var _grid: GridView
var _panel: ItemDetailPanel


func _ready() -> void:
	call_deferred("_run")


func _refresh_required_indicators() -> void:
	_probe._refresh_required_indicators()


func _run() -> void:
	CloudService.online = false
	GameState.current_board_type = Constants.BoardType.MAIN
	StoragePouch.items = []
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.meridian_acupoints = [{"item_ids": [28002, 27002], "completed": false, "items": [
		{"item_id": 28002}, {"item_id": 27002},
	]}]
	var loaded_forge: Dictionary = _add(18002, 985001, Vector2i(0, 0))
	loaded_forge["_craft_init"] = true
	loaded_forge["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	loaded_forge["_craft_stored"] = [{"id": 9002, "uid": 985005}]
	_add(18002, 985002, Vector2i(1, 0))
	var furnace: Dictionary = _add(17002, 985003, Vector2i(2, 0))
	var water: Dictionary = _add(9002, 985004, Vector2i(3, 0))
	_probe = GameScreen.new()
	_grid = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	_probe.grid_view = _grid
	add_child(_grid)
	_panel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(_panel)
	await get_tree().process_frame
	_grid._show_crafting_hints(water, Vector2i(3, 0), true)
	var loaded_node: GridItem = _grid._item_nodes["0,0"] as GridItem
	var empty_node: GridItem = _grid._item_nodes["1,0"] as GridItem
	var furnace_node: GridItem = _grid._item_nodes["2,0"] as GridItem
	if loaded_node.craft_hint_bubble.visible or empty_node.craft_hint_bubble.visible or not furnace_node.craft_hint_bubble.visible:
		_fail("Stored sword water must not advertise another forge; only the missing alchemy water may shake")
		return
	# Follow the actual hinted destination through the controller's add path.
	var controller: CraftingController = _grid._craft_ctrl
	if not controller.try_add_ingredient(Vector2i(2, 0), furnace, Vector2i(3, 0), 9002, water):
		_fail("The hinted furnace must accept the water")
		return
	GridManager.remove_item(Vector2i(3, 0))
	_panel.show_item(furnace)
	if _panel.get_output_item_id() != 27002 or _panel.materials_row.get_child_count() != 2:
		_fail("Following the hint must display the alchemy recipe and its missing herb")
		return
	# The same sword recipe still belongs to the original forge.
	var ore: Dictionary = _add(2003, 985006, Vector2i(4, 0))
	_grid._show_crafting_hints(ore, Vector2i(4, 0), true)
	if not loaded_node.craft_hint_bubble.visible or empty_node.craft_hint_bubble.visible:
		_fail("Sword ore must point back to the forge that already holds its water")
		return
	_grid._clear_crafting_hints()
	_probe.free()
	_panel.clear()
	print("CRAFT_HINT_RECIPE_CONSISTENCY_SMOKE_OK stored_water=true shared_water=true hinted_deposit=true preview=true remaining_material=true")
	get_tree().quit(0)


func _add(id: int, uid: int, pos: Vector2i) -> Dictionary:
	var item: Dictionary = ConfigDatabase.get_item_data(id).duplicate(true)
	item["_uid"] = uid
	assert(GridManager.add_item(item, pos))
	return GridManager.get_item(pos) as Dictionary


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
