extends Node


func _ready() -> void:
	var panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(panel)
	await get_tree().process_frame
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.meridian_acupoints = [{"item_ids": [27001], "items": [{"item_id": 27001}], "completed": false}]
	var table: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
	table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table["_craft_stored"] = [{"id": 5001, "uid": 950001}]
	panel.show_item(table)
	# Force overflow with a real stored ingredient and a recipe preview icon.
	panel.materials_container.size.x = 100
	await get_tree().process_frame
	await get_tree().process_frame
	assert(panel.materials_row.get_child_count() == 2)
	assert(panel.materials_container.get_h_scroll_bar().max_value > panel.materials_container.size.x)
	var stored: ItemWidget = panel.materials_row.get_child(0) as ItemWidget
	var ghost: ItemWidget = panel.materials_row.get_child(1) as ItemWidget
	var removed: Array[int] = []
	var sources: Array[int] = []
	panel.material_clicked.connect(func(uid: int, _item_id: int): removed.append(uid))
	panel.material_source_requested.connect(func(item_id: int): sources.append(item_id))
	var start: Vector2 = panel.materials_container.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	panel._input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = start - Vector2(40, 0)
	panel._input(motion)
	assert(panel.materials_container.scroll_horizontal == 40)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	panel._input(release)
	stored.pressed.emit()
	ghost.pressed.emit()
	assert(removed.is_empty(), "Dragging must not remove a stored material")
	assert(sources.is_empty(), "Dragging must not open a material source")
	await get_tree().process_frame
	# A stationary click continues to dispatch each icon's normal action.
	press.position = start
	panel._input(press)
	release.position = start
	panel._input(release)
	stored.pressed.emit()
	ghost.pressed.emit()
	assert(removed == [950001])
	assert(sources == [9001])
	await get_tree().process_frame
	# Touch dragging scrolls too; the emulated mouse must not reset the gesture.
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = start
	panel._input(touch)
	panel._input(press)
	var touch_drag := InputEventScreenDrag.new()
	touch_drag.index = 0
	touch_drag.position = start + Vector2(25, 0)
	panel._input(touch_drag)
	assert(panel.materials_container.scroll_horizontal == 15)
	touch.pressed = false
	touch.position = touch_drag.position
	panel._input(touch)
	stored.pressed.emit()
	ghost.pressed.emit()
	assert(removed.size() == 1 and sources.size() == 1)
	await get_tree().process_frame
	# Moving away and returning to the press location still cancels a click.
	panel._input(press)
	motion.position = start + Vector2(0, 200)
	panel._input(motion)
	release.position = start
	panel._input(release)
	stored.pressed.emit()
	assert(removed.size() == 1)
	print("ITEM_DETAIL_MATERIAL_SCROLL_SMOKE_OK mouse=true touch=true click=true drag_guard=true")
	get_tree().quit()
