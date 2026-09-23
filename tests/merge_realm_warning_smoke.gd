extends Node

const GRID_SCENE: PackedScene = preload("res://scenes/grid/GridView.tscn")


func _ready() -> void:
	await get_tree().process_frame
	var original_level: int = CultivationService.current_level

	for test_case: Array in [
		[1, 4, 5],
		[2, 4, 5],
		[11, 8, 9],
		[14, 12, 13],
		[17, 16, 17],
	]:
		CultivationService.current_level = int(test_case[0])
		assert(CultivationService.get_current_realm_item_level_cap() == int(test_case[1]))
		assert(not CultivationService.is_item_level_above_current_realm(int(test_case[1])))
		assert(CultivationService.is_item_level_above_current_realm(int(test_case[2])))

	CultivationService.current_level = 20
	assert(CultivationService.get_current_realm_item_level_cap() == 0)
	assert(not CultivationService.is_item_level_above_current_realm(99))

	CultivationService.current_level = 2
	GridManager.init_grid(Constants.BoardType.MAIN)
	var first: Dictionary = ConfigDatabase.get_item_data(5004).duplicate(true)
	var second: Dictionary = ConfigDatabase.get_item_data(5004).duplicate(true)
	first["_uid"] = 910001
	second["_uid"] = 910002
	assert(GridManager.add_item(first, Vector2i(0, 0)))
	assert(GridManager.add_item(second, Vector2i(1, 0)))

	var grid_view: GridView = GRID_SCENE.instantiate() as GridView
	add_child(grid_view)
	await get_tree().process_frame
	assert(grid_view.call("_try_optimistic_merge", Vector2i(0, 0), Vector2i(1, 0)))

	var popup: ConfirmPopup = _find_confirm_popup()
	assert(popup != null)
	assert(popup.title_label.text == "越境合成提示")
	assert(popup.message_label.text.contains("5级"))
	assert(popup.message_label.text.contains("练气期"))
	assert(popup.message_label.text.contains("4级"))
	assert(int((GridManager.get_item(Vector2i(0, 0)) as Dictionary).get("id", 0)) == 5004)
	assert(int((GridManager.get_item(Vector2i(1, 0)) as Dictionary).get("id", 0)) == 5004)

	popup.cancel_btn.pressed.emit()
	await popup.hide_animation_finished
	assert(int((GridManager.get_item(Vector2i(0, 0)) as Dictionary).get("id", 0)) == 5004)
	assert(int((GridManager.get_item(Vector2i(1, 0)) as Dictionary).get("id", 0)) == 5004)

	assert(grid_view.call("_try_optimistic_merge", Vector2i(0, 0), Vector2i(1, 0)))
	popup = _find_confirm_popup()
	assert(popup != null)
	popup.confirm_btn.pressed.emit()
	assert(GridManager.get_item(Vector2i(0, 0)) == null)
	var merged_item: Dictionary = GridManager.get_item(Vector2i(1, 0)) as Dictionary
	assert(int(merged_item.get("level", 0)) == 5)

	CultivationService.current_level = original_level
	print("MERGE_REALM_WARNING_SMOKE_OK caps=true cancel=true confirm=true")
	get_tree().quit()


func _find_confirm_popup() -> ConfirmPopup:
	var popup_layer: Control = UIManager.get_layer(UIManager.Layer.POPUP)
	for child: Node in popup_layer.get_children():
		if child is ConfirmPopup:
			return child as ConfirmPopup
	return null
