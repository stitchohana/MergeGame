extends Node

var _probe: GameScreen
var _grid: GridView


func _ready() -> void:
	call_deferred("_run")


func _refresh_required_indicators() -> void:
	_probe._refresh_required_indicators()


func _run() -> void:
	CloudService.online = false
	GameState.current_board_type = Constants.BoardType.MAIN
	GridManager.init_grid(Constants.BoardType.MAIN)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/craft_hint_water_trace.json")) as Dictionary
	GameState.meridian_acupoints = fixture["orders"] as Array
	for snapshot: Dictionary in fixture["tables"]:
		var table: Dictionary = ConfigDatabase.get_item_data(int(snapshot["id"])).duplicate(true)
		table["_uid"] = int(snapshot["uid"])
		table["_craft_init"] = bool(snapshot["initialized"])
		table["_craft_state"] = int(snapshot["state"])
		table["_craft_stored"] = snapshot["stored"].duplicate(true)
		table["_craft_result_id"] = int(snapshot["result_id"])
		if not _add(table, _parse_pos(str(snapshot["pos"]))):
			return
	var source: Dictionary = fixture["source"] as Dictionary
	var water: Dictionary = ConfigDatabase.get_item_data(int(source["ingredient_id"])).duplicate(true)
	water["_uid"] = int(source["ingredient_uid"])
	var source_pos: Vector2i = _parse_pos(str(source["source_pos"]))
	if not _add(water, source_pos):
		return
	water = GridManager.get_item(source_pos) as Dictionary
	# The trace gives combined available counts, not each ordinary item's
	# position. Preserve those counts in the pouch; table positions stay exact.
	StoragePouch.items = []
	var next_uid: int = 990000
	var counts: Dictionary = fixture["available_counts"] as Dictionary
	for key: String in counts:
		var id: int = int(key)
		var count: int = int(counts[key]) - (1 if id == int(water["id"]) else 0)
		for index: int in range(count):
			next_uid += 1
			StoragePouch.items.append({"id": id, "uid": next_uid})
	_probe = GameScreen.new()
	_grid = preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	_probe.grid_view = _grid
	add_child(_grid)
	await get_tree().process_frame
	for persistent: bool in [false, true]:
		_grid._show_crafting_hints(water, source_pos, persistent)
		var shown: Array = []
		for node: GridItem in _grid._craft_hint_nodes:
			shown.append(int(node.item_data.get("_uid", 0)))
		if shown != [4267]:
			_fail("Trace water must point only to the empty alchemy furnace 4267, got %s" % [shown])
			return
	var furnace: Dictionary = GridManager.find_by_uid(4267)
	var target_pos: Vector2i = GridManager.find_pos_by_uid(4267)
	if not _grid._craft_ctrl.try_add_ingredient(target_pos, furnace, source_pos, 9003, water):
		_fail("The trace destination must accept the hinted water")
		return
	_grid._clear_crafting_hints()
	var panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(panel)
	panel.show_item(furnace, target_pos)
	var material_ids: Array = []
	for child: Node in panel.materials_row.get_children():
		material_ids.append(int((child as ItemWidget).item_data.get("id", 0)))
	if panel.get_output_item_id() != 27004 or material_ids != [9003, 5004, 1002]:
		_fail("Deposited water must show recipe 4, output 27004 and the two missing materials")
		return
	# With this pill's water stored too, none of the spare forges/furnaces
	# should advertise more water for these two products.
	_grid._show_crafting_hints(water, source_pos, false)
	if not _grid._craft_hint_nodes.is_empty():
		_fail("Already stored pill and sword waters must suppress further water hints")
		return
	_probe.free()
	panel.clear()
	print("CRAFT_HINT_WATER_TRACE_SMOKE_OK exact_tables=true click=true drag=true no_duplicate_forge=true deposit_preview=true stored_water=true")
	get_tree().quit(0)


func _parse_pos(value: String) -> Vector2i:
	var parts: PackedStringArray = value.trim_prefix("(").trim_suffix(")").split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func _add(item: Dictionary, pos: Vector2i) -> bool:
	if GridManager.add_item(item, pos):
		return true
	_fail("Failed to restore trace item at %s" % pos)
	return false


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
