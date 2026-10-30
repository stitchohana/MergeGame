extends Node


func _ready() -> void:
	CloudService.online = false
	GameState.meridian_acupoints = []
	GameState.main_grid_cache = [{"id": 10002, "uid": 990001, "col": 0, "row": 0}]
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(screen)
	screen.on_enter()
	await _wait_for_layout()
	assert(screen._is_initial_game_load, "Wait for delayed orders before focusing")

	var orders: Array = [
		{"item_ids": [5002], "items": [{"item_id": 5002}], "completed": false},
		{"item_ids": [9002, 10002], "items": [{"item_id": 9002}, {"item_id": 10002}], "completed": false},
		{"item_ids": [10002], "items": [{"item_id": 10002}], "completed": false},
	]
	screen._on_state_loaded_for_orders({"meridian_acupoints": orders})
	await _wait_for_layout()
	var list: RequirementList = screen.requirement_list
	var entries: Array[RequirementEntry] = list.get_order_entries()
	assert(not screen._is_initial_game_load)
	assert(entries[0].get_display_index() == 2)
	assert(entries[1].get_display_index() == 1)
	assert(list.scroll.get_global_rect().encloses(entries[1].get_global_rect()), "Focus the next order with missing items")
	assert(list.scroll.scroll_horizontal > 0, "Scroll past activity and character entries")

	list.scroll.scroll_horizontal = 0
	screen._on_state_loaded_for_orders({"meridian_acupoints": orders})
	await _wait_for_layout()
	assert(list.scroll.scroll_horizontal == 0, "Subsequent refreshes must preserve manual scrolling")

	GameState.main_grid_cache = [
		{"id": 5002, "uid": 990001, "col": 0, "row": 0},
		{"id": 9002, "uid": 990002, "col": 1, "row": 0},
		{"id": 10002, "uid": 990003, "col": 2, "row": 0},
	]
	screen.on_enter()
	await _wait_for_layout()
	entries = list.get_order_entries()
	assert(not screen._is_initial_game_load)
	assert(entries[0].is_available())
	assert(list.scroll.get_global_rect().encloses(entries[0].get_global_rect()), "Show the first submittable order when all items are ready")
	screen.on_exit()
	print("INITIAL_ORDER_FOCUS_SMOKE_OK")
	get_tree().quit()


func _wait_for_layout() -> void:
	for frame: int in range(6):
		await get_tree().process_frame
