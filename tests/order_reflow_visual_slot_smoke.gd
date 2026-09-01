extends Node


func _ready() -> void:
	var requirement_list: RequirementList = preload("res://scenes/ui/meridian/RequirementList.tscn").instantiate() as RequirementList
	add_child(requirement_list)
	await get_tree().process_frame

	var requirements: Array = [
		{"items": [{"item_id": 5001}], "completed": false},
		{"items": [{"item_id": 5002}], "completed": false},
		{"items": [{"item_id": 5003}], "completed": false},
		{"items": [{"item_id": 5004}], "completed": false},
	]
	# The second visual card is display index 0 because index 1 is available.
	requirement_list.set_requirements(requirements, {0: 0, 1: 2, 2: 0, 3: 0})
	await get_tree().process_frame
	await get_tree().process_frame

	var old_entries: Array[RequirementEntry] = requirement_list.get_order_entries()
	assert(old_entries.size() == 4)
	var previous_positions: Dictionary = {}
	var removed_visual_index: int = -1
	for visual_index in range(old_entries.size()):
		var old_entry: RequirementEntry = old_entries[visual_index]
		previous_positions[visual_index] = old_entry.position
		if old_entry.get_display_index() == 0:
			removed_visual_index = visual_index
	assert(removed_visual_index == 1)

	requirement_list.set_requirements([requirements[1], requirements[2], requirements[3]], {0: 0, 1: 0, 2: 0})
	var new_entries: Array[RequirementEntry] = requirement_list.get_order_entries()
	requirement_list.animate_reflow_from(previous_positions, removed_visual_index)
	await get_tree().process_frame

	# The order before the removed visual slot stays in place; later cards use
	# the next old visual slot and move forward by exactly one card.
	for new_visual_index in range(new_entries.size()):
		var old_visual_index: int = new_visual_index
		if new_visual_index >= removed_visual_index:
			old_visual_index += 1
		var expected_position: Vector2 = previous_positions[old_visual_index]
		assert(new_entries[new_visual_index].position.is_equal_approx(expected_position))

	print("ORDER_REFLOW_VISUAL_SLOT_SMOKE_OK")
	get_tree().quit()
