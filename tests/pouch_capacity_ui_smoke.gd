extends Node

func _ready() -> void:
	CloudService.online = false
	StoragePouch.restore_from_server([], {"pouch_capacity": 7, "pouch_next_unlock_cost": 100})
	GameState.spirit_stones = 500
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	UIManager.push_screen.call_deferred(screen)
	for frame: int in range(6):
		await get_tree().process_frame
	var popup: PouchPopup = preload("res://scenes/ui/main/PouchPopup.tscn").instantiate() as PouchPopup
	UIManager.show_popup(popup)
	await get_tree().process_frame
	assert(StoragePouch.capacity == 7)
	assert(popup.item_container.get_child_count() == 7)
	assert(popup.title_label.text.contains("0/7"))
	assert(popup.unlock_button.text.contains("100"))
	assert(popup.unlock_button.disabled, "Offline purchases must be disabled")
	CloudService.online = true
	GameState.spirit_stones_changed.emit(500)
	assert(not popup.unlock_button.disabled)
	StoragePouch.unlock_pending = true
	StoragePouch.pouch_updated.emit(StoragePouch.items)
	assert(popup.unlock_button.disabled)
	StoragePouch.unlock_slot()
	assert(StoragePouch.unlock_pending, "A pending unlock must not be submitted again")
	CloudService.pouch_unlock_confirmed.emit({"pouch_capacity": 8, "pouch_next_unlock_cost": 150, "spirit_stones": 400})
	assert(not StoragePouch.unlock_pending)
	assert(StoragePouch.capacity == 8)
	assert(GameState.spirit_stones == 400)
	assert(popup.item_container.get_child_count() == 8)
	assert(popup.unlock_button.text.contains("150"))
	assert(screen.pouch_zone.count_label.text == "0/8")
	GameState.spirit_stones = 149
	GameState.spirit_stones_changed.emit(149)
	assert(popup.unlock_button.disabled)
	CloudService.online = false
	StoragePouch._on_unlock_rejected("network_error")
	assert(not StoragePouch.unlock_pending)
	var pouch_items: Array = []
	for i: int in range(7):
		pouch_items.append({"uid": i + 1, "id": 5001 + i})
	StoragePouch.restore_from_server(pouch_items, {"pouch_capacity": 7, "pouch_next_unlock_cost": 100})
	var failures: Array[String] = []
	StoragePouch.deposit_failed.connect(func(reason: String): failures.append(reason))
	StoragePouch.deposit(999)
	assert(failures == ["pouch_full"])
	assert(StoragePouch._pending_deposit_uid == -1)
	assert(popup.item_container.get_child_count() == 7)
	assert(popup.title_label.text.contains("7/7"))
	var data: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	data["_uid"] = 999
	GridManager.add_item(data, Vector2i(0, 0))
	screen.grid_view._drag_source_pos = Vector2i(0, 0)
	screen.grid_view._drag_item_data = data
	var dragged: GridItem = screen.grid_view._item_nodes["0,0"] as GridItem
	dragged.position = Vector2(100, -100)
	screen.grid_view._do_pouch_deposit()
	await get_tree().create_timer(0.25).timeout
	assert(GridManager.find_pos_by_uid(999) == Vector2i(0, 0))
	assert(dragged.position.is_equal_approx(Vector2.ZERO), "Rejected full pouch drop must snap back")
	CloudService.state_loaded.emit({"pouch": [], "pouch_capacity": 9, "pouch_next_unlock_cost": 200, "spirit_stones": 250})
	assert(StoragePouch.capacity == 9 and StoragePouch.next_unlock_cost == 200)
	assert(GameState.spirit_stones == 250, "Recovery must restore the authoritative balance")
	StoragePouch.restore_from_server([], {"pouch_capacity": 7, "pouch_next_unlock_cost": 100})
	GameState.spirit_stones = 500
	CloudService.online = true
	GameState.spirit_stones_changed.emit(500)
	await get_tree().create_timer(Constants.TOP_RESOURCE_VALUE_ANIM_DURATION + 0.1).timeout
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/pouch_capacity_ui.png")
		StoragePouch.restore_from_server([], {"pouch_capacity": 49, "pouch_next_unlock_cost": 2200})
		await get_tree().process_frame
		assert(popup.item_container.get_child_count() == 49)
		assert(popup.get_node("Panel/Scroll").get_v_scroll_bar().max_value > 416.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/pouch_capacity_expanded_ui.png")
	CloudService.online = false
	UIManager.hide_popup(popup)
	await get_tree().create_timer(0.25).timeout
	print("POUCH_CAPACITY_UI_SMOKE_OK initial=7 unlock=8 cost=150 balance=400 full_guard=true")
	get_tree().quit()
