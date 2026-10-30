extends Node


func _ready() -> void:
	CloudService.online = false
	var panel: GMPanel = preload("res://scenes/ui/other/GMPanel.tscn").instantiate() as GMPanel
	add_child(panel)
	var command_index: int = -1
	for index: int in range(panel.command_buttons.size()):
		if panel.command_buttons[index].text == "一键领取所有暂存物品":
			command_index = index
	assert(command_index >= 0)
	panel.command_buttons[command_index].pressed.emit()
	assert(panel.command_buttons[command_index].button_pressed)
	assert(not panel.command_buttons[0].button_pressed)
	assert(not panel.amount_spin.editable)
	assert(panel.amount_spin.value == 1)
	RewardManager.reset_pending()
	RewardManager.sync_pending({"storage_revision": 1, "pending_rewards": [{"uid": 201, "id": 5001}]})
	CloudService.state_loaded.emit({"storage_revision": 2, "pending_rewards": [],
		"main_grid": [{"uid": 201, "id": 5001, "col": 0, "row": 0}], "battle_grid": []})
	assert(RewardManager.pending_rewards.is_empty())
	assert(int(GridManager.get_item(Vector2i.ZERO).get("_uid", 0)) == 201)
	panel.queue_free()
	print("GM_CLAIM_PENDING_ITEMS_SMOKE_OK command amount grid pending_sync")
	get_tree().quit()
