extends Node


func _ready() -> void:
	var requirement_list: RequirementList = preload("res://scenes/ui/meridian/RequirementList.tscn").instantiate() as RequirementList
	add_child(requirement_list)
	await get_tree().process_frame

	var completed_indices: Array[int] = []
	requirement_list.complete_clicked.connect(func(index: int) -> void: completed_indices.append(index))
	var start_position: Vector2 = requirement_list.scroll.get_global_rect().get_center()

	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = start_position
	requirement_list._input(press_event)

	var drag_event := InputEventMouseMotion.new()
	drag_event.position = start_position - Vector2(RequirementList.DRAG_THRESHOLD + 1.0, 0.0)
	requirement_list._input(drag_event)
	requirement_list._emit_complete(3)
	assert(completed_indices.is_empty())

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = drag_event.position
	requirement_list._input(release_event)
	await get_tree().process_frame

	requirement_list._emit_complete(3)
	assert(completed_indices == [3])
	print("ORDER_SCROLL_CLICK_GUARD_SMOKE_OK")
	get_tree().quit()
