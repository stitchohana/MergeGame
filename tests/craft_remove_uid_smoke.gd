extends Node


class TestGridView:
	extends GridView

	func _ready() -> void:
		_launcher_ctrl = LauncherControllerClass.new()
		add_child(_launcher_ctrl)
		set_process(false)
		set_process_input(false)

	func _flush_spawn_action_batch() -> void:
		# Exercise the real queue and reconciliation without sending requests.
		pass


const TABLE_POS := Vector2i(0, 0)
const TARGET_POS := Vector2i(1, 0)
const TABLE_UID: int = 990001
const RETURNED_UID: int = 990100


func _ready() -> void:
	CloudService.online = false
	await get_tree().process_frame
	var view: TestGridView = TestGridView.new()
	add_child(view)

	# Server material entries only contain an ID; legacy local entries may
	# still carry their original UID. Neither is the returned item's new UID.
	for stored_material: Dictionary in [{"id": 5001}, {"id": 5001, "uid": 990002}]:
		_seed_table(stored_material)
		view.queue_craft_remove(TABLE_POS, 5001, TARGET_POS)
		var predicted: Dictionary = GridManager.get_item(TARGET_POS) as Dictionary
		assert(bool(predicted.get("_optimistic_action", false)), "Returned material must remain pending until server confirmation")
		assert(int(predicted.get("_uid", -1)) == 0, "Do not reuse a stored UID; the server creates a new one")
		assert(CraftingService.get_stored_items(GridManager.get_item(TABLE_POS) as Dictionary).is_empty())
		assert(view._pending_spawn_actions.size() == 1)
		var operation: Dictionary = view._pending_spawn_actions[0].get("operation", {})
		assert(operation.get("type", "") == "craft_remove")
		assert(operation.get("ingredient_id", 0) == 5001)
		assert(operation.get("from", []) == [0, 0])
		assert(operation.get("to", []) == [1, 0])

		# The real batch-confirmation path must replace pending identity and
		# flags with the positive server UID while retaining the material.
		view._pending_spawn_actions.clear()
		view._spawn_action_batch_in_flight = true
		view._on_action_batch_confirmed({"grid": [
			{"id": 17001, "uid": TABLE_UID, "col": 0, "row": 0,
				"craft": {"_craft_stored": [], "_craft_state": CraftingService.TableState.IDLE}},
			{"id": 5001, "uid": RETURNED_UID, "col": 1, "row": 0},
		]})
		var confirmed: Dictionary = GridManager.get_item(TARGET_POS) as Dictionary
		assert(int(confirmed.get("_uid", 0)) == RETURNED_UID)
		assert(not confirmed.has("_optimistic_action"))
		assert(GridManager.find_pos_by_uid(RETURNED_UID) == TARGET_POS)
		assert(not view._has_unsynced_actions())

	# A rejected batch restores the material to its original table without
	# leaving a provisional board copy or a pending action behind.
	_seed_table({"id": 5001})
	view.queue_craft_remove(TABLE_POS, 5001, TARGET_POS)
	view._on_action_batch_rejected("target_occupied", {"grid": [
		{"id": 17001, "uid": TABLE_UID, "col": 0, "row": 0,
			"craft": {"_craft_stored": [{"id": 5001}], "_craft_state": CraftingService.TableState.HAS_ITEMS}},
	]})
	assert(GridManager.is_empty(TARGET_POS))
	assert(CraftingService.get_stored_items(GridManager.get_item(TABLE_POS) as Dictionary).size() == 1)
	assert(not view._has_unsynced_actions())

	# Invalid targets must not consume the stored material locally.
	var occupied: Dictionary = ConfigDatabase.get_item_data(9001).duplicate(true)
	occupied["_uid"] = 990003
	assert(GridManager.add_item(occupied, TARGET_POS))
	view.queue_craft_remove(TABLE_POS, 5001, TARGET_POS)
	view.queue_craft_remove(TABLE_POS, 5001, Vector2i(-1, 0))
	assert(CraftingService.get_stored_items(GridManager.get_item(TABLE_POS) as Dictionary).size() == 1)
	assert(view._pending_spawn_actions.is_empty())
	assert(int((GridManager.get_item(TARGET_POS) as Dictionary).get("id", 0)) == 9001)

	print("CRAFT_REMOVE_UID_SMOKE_OK missing_uid=true legacy_uid=true confirm=true rollback=true target_guard=true")
	get_tree().quit()


func _seed_table(stored_material: Dictionary) -> void:
	GridManager.init_grid()
	var table: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
	table["_uid"] = TABLE_UID
	table["_craft_init"] = true
	table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table["_craft_stored"] = [stored_material.duplicate(true)]
	assert(GridManager.add_item(table, TABLE_POS))
