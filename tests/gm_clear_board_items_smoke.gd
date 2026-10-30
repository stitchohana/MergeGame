extends Node


func _ready() -> void:
	CloudService.online = false
	var panel: GMPanel = preload("res://scenes/ui/other/GMPanel.tscn").instantiate() as GMPanel
	add_child(panel)
	var command_index: int = -1
	for index: int in range(panel.command_buttons.size()):
		if panel.command_buttons[index].text == "清理所有棋盘普通物品":
			command_index = index
	assert(command_index >= 0)
	panel.command_buttons[command_index].pressed.emit()
	assert(panel.command_buttons[command_index].button_pressed)
	assert(not panel.command_buttons[0].button_pressed)
	assert(not panel.amount_spin.editable)
	assert(panel.amount_spin.value == 1)
	panel._on_cmd_selected(0)
	assert(panel.amount_spin.editable)
	# An authoritative empty board must remove stale client items on either board.
	for board_type: int in [Constants.BoardType.MAIN, Constants.BoardType.BATTLE]:
		GameState.current_board_type = board_type
		GridManager.init_grid(board_type)
		var item: Dictionary = ConfigDatabase.get_item_data(5002).duplicate(true)
		item["_uid"] = 700001
		assert(GridManager.add_item(item, Vector2i.ZERO))
		panel._on_state_sync({"main_grid": [], "battle_grid": []})
		assert(GridManager.get_all_items().is_empty())
		assert(GridManager.current_board_type == board_type)
		assert(GameState.main_grid_cache.is_empty() and GameState.battle_grid_cache.is_empty())
	# Main-board facilities survive synchronization while its battle cache clears.
	GameState.current_board_type = Constants.BoardType.MAIN
	panel._on_state_sync({"main_grid": [{"id": 11001, "uid": 700002, "col": 0, "row": 0}], "battle_grid": []})
	assert(GridManager.get_all_items().size() == 1)
	assert(int(GridManager.get_item(Vector2i.ZERO).get("_uid", 0)) == 700002)
	panel.queue_free()
	print("GM_CLEAR_BOARD_ITEMS_SMOKE_OK command amount empty_main empty_battle cache facilities")
	get_tree().quit()
