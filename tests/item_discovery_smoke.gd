extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var notices: Array[String] = []
	EventBus.show_toast.connect(func(message: String) -> void: notices.append(message))

	GameState.set_crafted_item_ids([13002])
	assert(notices.is_empty())
	CloudService._dispatch_response("unknown_test_tag", {
		"ok": false, "spawned_id": 3004, "pending_rewards": [{"id": 3004}],
	})
	assert(notices.is_empty())
	CloudService._register_confirmed_item_discoveries("spawn", {
		"spawned_items": [{"id": 3004}],
	})
	await get_tree().process_frame
	assert(GameState.has_crafted_item(3004))
	assert(notices.size() == 1 and notices[0].contains("白石髓"))
	CloudService._register_confirmed_item_discoveries("spawn", {
		"spawned_items": [{"id": 3004}], "replayed": true,
	})
	await get_tree().process_frame
	assert(notices.size() == 1)

	CloudService._register_confirmed_item_discoveries("action_batch", {
		"results": [{"type": "merge", "result_id": 3003}, {"type": "merge", "result_id": 3003}],
	})
	await get_tree().process_frame
	assert(GameState.has_crafted_item(3003))
	assert(notices.size() == 2 and notices[1].contains("木心液"))

	CloudService._register_confirmed_item_discoveries("home_meridian_run", {
		"pending_rewards": [{"id": 3002}, {"id": 3001}, {"id": 3002}],
	})
	await get_tree().process_frame
	assert(GameState.has_crafted_item(3001) and GameState.has_crafted_item(3002))
	assert(notices.size() == 3)
	assert(notices[2].contains("青荷浆") and notices[2].contains("晨岚露"))

	CloudService._register_confirmed_item_discoveries("craft_retrieve", {"result_id": 27002})
	await get_tree().process_frame
	assert(GameState.has_crafted_item(27002))
	assert(notices.size() == 4)
	CloudService._register_confirmed_item_discoveries("merge", {"result_id": 3004})
	CloudService._register_confirmed_item_discoveries("home_meridian_run", {
		"pending_rewards": [{"id": 3002}, {"id": 3001}],
	})
	assert(notices.size() == 4)
	GameState.set_crafted_item_ids([13002, 3004, 3003, 3002, 3001, 27002])
	await get_tree().process_frame
	assert(notices.size() == 4)
	print("ITEM_DISCOVERY_SMOKE_OK")
	get_tree().quit(0)
