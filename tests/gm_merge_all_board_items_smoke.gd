extends Node


func _ready() -> void:
	CloudService.online = false
	var panel: GMPanel = preload("res://scenes/ui/other/GMPanel.tscn").instantiate() as GMPanel
	add_child(panel)
	var command_index: int = -1
	for index: int in range(panel.command_buttons.size()):
		if panel.command_buttons[index].text == "一键合成棋盘所有物品":
			command_index = index
	assert(command_index >= 0)
	panel.command_buttons[command_index].pressed.emit()
	assert(panel.command_buttons[command_index].button_pressed)
	assert(not panel.command_buttons[0].button_pressed)
	assert(not panel.amount_spin.editable)
	assert(panel.amount_spin.value == 1)
	panel._on_cmd_selected(0)
	assert(panel.amount_spin.editable)
	for board_type: int in [Constants.BoardType.MAIN, Constants.BoardType.BATTLE]:
		GameState.current_board_type = board_type
		panel._on_state_sync({"main_grid": [{"uid": 800, "id": 5003, "col": 1, "row": 0}],
			"battle_grid": [{"uid": 801, "id": 11003, "col": 2, "row": 0}]})
		assert(GridManager.get_all_items().size() == 1)
		var pos: Vector2i = Vector2i(2, 0) if board_type == Constants.BoardType.BATTLE else Vector2i(1, 0)
		var uid: int = 801 if board_type == Constants.BoardType.BATTLE else 800
		assert(int(GridManager.get_item(pos).get("_uid", 0)) == uid)
	panel._on_gm_rejected("test")
	assert(not panel.exec_btn.disabled)
	panel.queue_free()
	print("GM_MERGE_ALL_BOARD_ITEMS_UI_SMOKE_OK command amount main battle sync")
	get_tree().quit()
