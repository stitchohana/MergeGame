extends Node

var _panel: ItemDetailPanel
var _first: Dictionary
var _second: Dictionary


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CloudService.online = false
	GameState.current_board_type = Constants.BoardType.MAIN
	StoragePouch.items = []
	GridManager.init_grid(Constants.BoardType.MAIN)
	_first = _add(18002, 990101, Vector2i(0, 0))
	_second = _add(18002, 990102, Vector2i(1, 0))
	_add(9002, 990103, Vector2i(2, 0))
	for table: Dictionary in [_first, _second]:
		table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
		table["_craft_stored"] = [{"id": 2003}]
		table["_craft_recipe"] = {}
	_panel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(_panel)
	await get_tree().process_frame
	_set_orders([28002, 28003])
	if not _expect(_first, 28002, "first_forge") or not _expect(_second, 28003, "second_forge_alternative"):
		return
	# Selection order must not affect which furnace owns a recommendation.
	if not _expect(_second, 28003, "repeat_second") or not _expect(_first, 28002, "repeat_first"):
		return
	_set_orders([28002])
	if not _expect(_second, 0, "no_duplicate_fallback"):
		return
	# A more complete table has priority over the earlier board position.
	_set_orders([28003])
	_second["_craft_stored"] = [{"id": 2003}, {"id": 2004}]
	if not _expect(_first, 0, "more_complete_table_claims_recipe") or not _expect(_second, 28003, "more_complete_preview"):
		return
	# Returning materials releases the reservation on the next refresh.
	_second["_craft_stored"] = []
	_second["_craft_state"] = CraftingService.TableState.IDLE
	CraftingService.table_state_changed.emit(_second, CraftingService.TableState.IDLE)
	if not _expect(_first, 28003, "released_recipe"):
		return
	_panel.clear()
	# Check the board hint path with two forges, not only the detail panel.
	_set_orders([28002])
	_second["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	_second["_craft_stored"] = [{"id": 2003}]
	var grid: GridView = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	add_child(grid)
	await get_tree().process_frame
	var source: GridItem = grid._item_nodes["2,0"] as GridItem
	source.set_required(true)
	grid._show_crafting_hints(source.item_data, Vector2i(2, 0), true)
	var first_node: GridItem = grid._item_nodes["0,0"] as GridItem
	var second_node: GridItem = grid._item_nodes["1,0"] as GridItem
	if not first_node.craft_hint_bubble.visible or second_node.craft_hint_bubble.visible:
		push_error("Identical loaded forges must show only one board hint")
		get_tree().quit(1)
		return
	_second["_craft_stored"] = [{"id": 2003}, {"id": 4001}]
	grid._show_crafting_hints(source.item_data, Vector2i(2, 0), true)
	if first_node.craft_hint_bubble.visible or not second_node.craft_hint_bubble.visible:
		push_error("The more complete forge must receive the board hint")
		get_tree().quit(1)
		return
	grid._clear_crafting_hints()
	print("FORGE_RECIPE_PREVIEW_DEDUP_SMOKE_OK alternatives=true stable=true no_duplicate=true priority=true release=true board=true")
	get_tree().quit(0)


func _set_orders(ids: Array) -> void:
	var targets: Array = []
	for id: int in ids:
		targets.append({"item_id": id})
	GameState.meridian_acupoints = [{"completed": false, "items": targets}]


func _add(id: int, uid: int, pos: Vector2i) -> Dictionary:
	var item: Dictionary = ConfigDatabase.get_item_data(id).duplicate(true)
	item["_uid"] = uid
	assert(GridManager.add_item(item, pos))
	return GridManager.get_item(pos) as Dictionary


func _expect(table: Dictionary, result_id: int, scenario: String) -> bool:
	_panel.show_item(table)
	if _panel.get_output_item_id() != result_id:
		push_error("%s: expected %d, got %d" % [scenario, result_id, _panel.get_output_item_id()])
		get_tree().quit(1)
		return false
	if result_id > 0 and not is_equal_approx(_panel.output_slot.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA):
		push_error("%s: incomplete recipe must remain translucent" % scenario)
		get_tree().quit(1)
		return false
	return true
