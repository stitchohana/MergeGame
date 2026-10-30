extends Node

var _panel: ItemDetailPanel
var _table: Dictionary


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.current_board_type = Constants.BoardType.MAIN
	StoragePouch.items = []
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.meridian_acupoints = [{"item_ids": [27002, 27081], "completed": false, "items": [
		{"item_id": 27002}, {"item_id": 27081},
	]}]
	_table = ConfigDatabase.get_item_data(17001).duplicate(true)
	_table["_uid"] = 980001
	_table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	_table["_craft_stored"] = [{"id": 5002, "uid": 980002}]
	_table["_craft_recipe"] = {}
	if not GridManager.add_item(_table, Vector2i(0, 0)):
		get_tree().quit(1)
		return
	_table = GridManager.get_item(Vector2i(0, 0)) as Dictionary
	var water: Dictionary = ConfigDatabase.get_item_data(9002).duplicate(true)
	water["_uid"] = 980003
	if not GridManager.add_item(water, Vector2i(1, 0)):
		get_tree().quit(1)
		return
	_panel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(_panel)
	await get_tree().process_frame
	_panel.show_item(_table)
	# Without a started craft, the recipe with materials already on board wins.
	if not _expect_preview(27002, "initial_available_materials"):
		return
	var working: Dictionary = ConfigDatabase.get_item_data(17002).duplicate(true)
	working["_uid"] = 980004
	working["_craft_state"] = CraftingService.TableState.CRAFTING
	working["_craft_result_id"] = 27002
	working["_craft_recipe"] = ConfigDatabase.get_recipes_for_result(27002)[0]
	working["_craft_stored"] = []
	if not GridManager.add_item(working, Vector2i(2, 0)):
		get_tree().quit(1)
		return
	working = GridManager.get_item(Vector2i(2, 0)) as Dictionary
	# The selected table stays open while another furnace starts crafting.
	CraftingService.table_state_changed.emit(working, CraftingService.TableState.CRAFTING)
	if not _expect_preview(27081, "other_table_started"):
		return
	working["_craft_state"] = CraftingService.TableState.READY
	CraftingService.table_state_changed.emit(working, CraftingService.TableState.READY)
	if not _expect_preview(27081, "ready_output"):
		return
	working["_craft_result_id"] = -1
	_panel.show_item(_table)
	if not _expect_preview(27081, "restored_recipe_result"):
		return
	# A second requested copy must still be offered even with one copy started.
	GameState.meridian_acupoints[0]["items"].append({"item_id": 27002})
	GameState.meridian_acupoints[0]["item_ids"].append(27002)
	_panel.show_item(_table)
	if not _expect_preview(27002, "duplicate_order_shortage"):
		return
	GameState.meridian_acupoints[0]["items"].pop_back()
	GameState.meridian_acupoints[0]["item_ids"].pop_back()
	working["_craft_state"] = CraftingService.TableState.IDLE
	CraftingService.table_state_changed.emit(working, CraftingService.TableState.IDLE)
	if not _expect_preview(27002, "idle_result_not_counted"):
		return
	_panel.clear()
	print("ITEM_DETAIL_RECIPE_PRIORITY_SMOKE_OK started=true ready=true fallback=true duplicate=true live_refresh=true")
	get_tree().quit(0)


func _expect_preview(result_id: int, scenario: String) -> bool:
	if _panel.get_output_item_id() != result_id:
		push_error("%s: expected preview %d, got %d" % [scenario, result_id, _panel.get_output_item_id()])
		get_tree().quit(1)
		return false
	if not is_equal_approx(_panel.output_slot.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA):
		push_error("%s: candidate output must remain translucent" % scenario)
		get_tree().quit(1)
		return false
	var expected_materials: Array = []
	for recipe: Dictionary in ConfigDatabase.get_recipes_for_result(result_id):
		if recipe.get("ingredients", []).has(5002):
			expected_materials.append(recipe.get("ingredients", []))
	var displayed: Array = []
	for child: Node in _panel.materials_row.get_children():
		var slot: ItemWidget = child as ItemWidget
		displayed.append(int(slot.item_data.get("id", 0)))
		var expected_alpha: float = 1.0 if displayed.size() == 1 else ItemDetailPanel.PREVIEW_GHOST_ALPHA
		if not is_equal_approx(slot.modulate.a, expected_alpha):
			get_tree().quit(1)
			return false
	if not expected_materials.has(displayed):
		push_error("%s: displayed materials do not match preview %d" % [scenario, result_id])
		get_tree().quit(1)
		return false
	return true
