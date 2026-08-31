extends Node

const FIRST_ITEM_ID: int = 5002
const SECOND_ITEM_ID: int = 9002
const THIRD_ITEM_ID: int = 10002


func _ready() -> void:
	await get_tree().process_frame
	_test_item_order_is_unchanged()
	await _test_completion_empty_state()
	_test_requirement_priority_from_grid()
	_test_server_snapshot_emits_one_grid_update()
	await _test_available_order_is_first()
	print("REQUIREMENT_PRIORITY_SMOKE_OK")
	get_tree().quit()


func _test_item_order_is_unchanged() -> void:
	var entry: RequirementEntry = preload("res://scenes/ui/meridian/RequirementEntry.tscn").instantiate() as RequirementEntry
	add_child(entry)
	entry.setup([
		{"item_id": FIRST_ITEM_ID},
		{"item_id": SECOND_ITEM_ID},
	], 0, false)
	entry.refresh_item_selection({SECOND_ITEM_ID: true})
	assert(_get_entry_item_ids(entry) == [FIRST_ITEM_ID, SECOND_ITEM_ID])
	entry.queue_free()


func _test_completion_empty_state() -> void:
	var entry: RequirementEntry = preload("res://scenes/ui/meridian/RequirementEntry.tscn").instantiate() as RequirementEntry
	add_child(entry)
	entry.setup([{"item_id": FIRST_ITEM_ID}], 0, false)
	await get_tree().process_frame
	var items_container: HBoxContainer = entry.get_node("ItemsContainer") as HBoxContainer
	var background: TextureRect = entry.get_node("Background") as TextureRect
	assert(items_container.get_child_count() == 1)
	assert(items_container.get_child(0).visible)
	assert(background.visible)

	entry.show_completed_empty_state()
	await get_tree().process_frame
	assert(not items_container.get_child(0).visible)
	assert(background.visible)
	entry.queue_free()


func _test_requirement_priority_from_grid() -> void:
	GridManager.init_grid()
	var screen: GameScreen = GameScreen.new()
	var two_item_order: Dictionary = {
		"items": [{"item_id": FIRST_ITEM_ID}, {"item_id": SECOND_ITEM_ID}],
	}
	assert(screen._get_requirement_priority(two_item_order) == 0)
	assert(GridManager.add_item({"id": FIRST_ITEM_ID, "_uid": 910001}, Vector2i(0, 0)))
	assert(screen._get_requirement_priority(two_item_order) == 1)
	assert(GridManager.add_item({"id": SECOND_ITEM_ID, "_uid": 910002}, Vector2i(1, 0)))
	assert(screen._get_requirement_priority(two_item_order) == 2)

	var duplicate_item_order: Dictionary = {
		"items": [{"item_id": THIRD_ITEM_ID}, {"item_id": THIRD_ITEM_ID}],
	}
	assert(GridManager.add_item({"id": THIRD_ITEM_ID, "_uid": 910003}, Vector2i(2, 0)))
	assert(screen._get_requirement_priority(duplicate_item_order) == 1)
	assert(GridManager.add_item({"id": THIRD_ITEM_ID, "_uid": 910004}, Vector2i(3, 0)))
	assert(screen._get_requirement_priority(duplicate_item_order) == 2)
	screen.free()
	GridManager.init_grid()


func _test_server_snapshot_emits_one_grid_update() -> void:
	GridManager.init_grid()
	var update_count: Array[int] = [0]
	var on_grid_updated: Callable = func() -> void:
		update_count[0] += 1
	GridManager.grid_updated.connect(on_grid_updated)
	GridManager.populate_from_server([
		{"id": FIRST_ITEM_ID, "uid": 920001, "col": 0, "row": 0},
		{"id": SECOND_ITEM_ID, "uid": 920002, "col": 1, "row": 0},
		{"id": THIRD_ITEM_ID, "uid": 920003, "col": 2, "row": 0},
	])
	assert(update_count[0] == 1)
	GridManager.grid_updated.disconnect(on_grid_updated)
	GridManager.init_grid()


func _test_available_order_is_first() -> void:
	var requirement_list: RequirementList = preload("res://scenes/ui/meridian/RequirementList.tscn").instantiate() as RequirementList
	add_child(requirement_list)
	await get_tree().process_frame
	var requirements: Array = [
		{"items": [{"item_id": FIRST_ITEM_ID}], "completed": false},
		{"items": [{"item_id": SECOND_ITEM_ID}], "completed": false},
		{"items": [{"item_id": THIRD_ITEM_ID}], "completed": false},
	]
	requirement_list.set_requirements(requirements)
	await get_tree().process_frame
	await get_tree().process_frame
	var initial_load_probe: GameScreen = GameScreen.new()
	assert(not initial_load_probe._allow_available_order_focus())
	requirement_list.set_entry_priority(2, 2, initial_load_probe._allow_available_order_focus())
	await get_tree().process_frame
	await get_tree().process_frame
	var character_entry: CharacterEntry = requirement_list.container.get_node("CharacterEntry") as CharacterEntry
	assert(requirement_list.scroll.scroll_horizontal == 0)
	assert(requirement_list.scroll.get_global_rect().intersects(character_entry.get_global_rect()))
	await get_tree().create_timer(0.35).timeout
	initial_load_probe._is_initial_game_load = false
	assert(initial_load_probe._allow_available_order_focus())
	initial_load_probe.free()

	requirement_list.set_requirements(requirements, {0: 0, 1: 1, 2: 2})
	var entries: Array[RequirementEntry] = requirement_list.get_order_entries()
	assert(entries.size() == 3)
	assert(_get_order_indices(entries) == [2, 1, 0])
	await get_tree().process_frame
	await get_tree().process_frame
	assert(requirement_list.scroll.get_global_rect().intersects(entries[0].get_global_rect()))
	var max_scroll: int = int(requirement_list.scroll.get_h_scroll_bar().max_value)
	assert(max_scroll > 0)
	requirement_list.scroll.scroll_horizontal = max_scroll
	requirement_list.reset_scroll_to_start()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(requirement_list.scroll.scroll_horizontal == 0)
	requirement_list.scroll.scroll_horizontal = max_scroll
	requirement_list.set_entry_priority(0, 2)
	entries = requirement_list.get_order_entries()
	assert(_get_order_indices(entries) == [0, 2, 1])
	await get_tree().process_frame
	await get_tree().process_frame
	var promoted_entry: RequirementEntry = entries[0]
	assert(is_equal_approx(promoted_entry.modulate.a, 1.0))
	await get_tree().process_frame
	assert(promoted_entry.z_index == RequirementList.ORDER_ANIMATION_FOREGROUND_Z)
	assert(is_equal_approx(promoted_entry.modulate.a, 1.0))
	await get_tree().create_timer(0.35).timeout
	var viewport_rect: Rect2 = requirement_list.scroll.get_global_rect()
	var promoted_rect: Rect2 = entries[0].get_global_rect()
	assert(viewport_rect.encloses(promoted_rect))
	assert(requirement_list.scroll.scroll_horizontal < max_scroll)
	assert(promoted_entry.z_index == 0)
	requirement_list.scroll.scroll_horizontal = max_scroll
	requirement_list.set_requirements(requirements)
	await get_tree().process_frame
	await get_tree().process_frame
	var rebuilt_max_scroll: int = int(requirement_list.scroll.get_h_scroll_bar().max_value)
	assert(requirement_list.scroll.scroll_horizontal == rebuilt_max_scroll)
	requirement_list.set_entry_priority(0, 0)
	entries = requirement_list.get_order_entries()
	assert(_get_order_indices(entries) == [2, 1, 0])
	requirement_list.set_requirements(requirements)
	await get_tree().process_frame
	var previous_positions: Dictionary = {}
	for previous_entry in requirement_list.get_order_entries():
		previous_positions[previous_entry.get_display_index()] = previous_entry.position
	requirement_list.set_requirements([requirements[1], requirements[2]])
	entries = requirement_list.get_order_entries()
	var reflow_entry: RequirementEntry = entries[0]
	var expected_reflow_target: Vector2 = previous_positions[0]
	requirement_list.animate_reflow_from(previous_positions, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(reflow_entry.z_index == RequirementList.ORDER_ANIMATION_FOREGROUND_Z)
	assert(is_equal_approx(reflow_entry.modulate.a, 1.0))
	await get_tree().create_timer(0.35).timeout
	assert(reflow_entry.z_index == 0)
	assert(is_equal_approx(reflow_entry.modulate.a, 1.0))
	assert(reflow_entry.position.is_equal_approx(expected_reflow_target))
	requirement_list.queue_free()


func _get_entry_item_ids(entry: RequirementEntry) -> Array[int]:
	var item_ids: Array[int] = []
	var items_container: HBoxContainer = entry.get_node("ItemsContainer") as HBoxContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			item_ids.append(int((child as ItemWidget).item_data.get("id", 0)))
	return item_ids


func _get_order_indices(entries: Array[RequirementEntry]) -> Array[int]:
	var indices: Array[int] = []
	for entry in entries:
		indices.append(entry.get_display_index())
	return indices
