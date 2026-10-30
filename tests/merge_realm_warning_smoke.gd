extends Node

const GRID_SCENE: PackedScene = preload("res://scenes/grid/GridView.tscn")
const Preferences := preload("res://scripts/utils/MergeWarningPreferences.gd")


func _ready() -> void:
	await get_tree().process_frame
	var original_level: int = CultivationService.current_level
	var original_path: String = Preferences.storage_path
	Preferences.storage_path = "res://.codex_tmp/merge_warning_smoke.cfg"
	DirAccess.remove_absolute(Preferences.storage_path)
	var before_midnight: int = int(Time.get_unix_time_from_datetime_string("2026-10-16T15:59:59"))
	Preferences.suppress_today(before_midnight)
	assert(Preferences.is_suppressed_today(before_midnight))
	assert(not Preferences.is_suppressed_today(before_midnight + 1))
	# A new ConfigFile read must preserve the preference, as after restarting.
	var saved_preferences: ConfigFile = ConfigFile.new()
	assert(saved_preferences.load(Preferences.storage_path) == OK)
	assert(saved_preferences.get_value("merge", "skip_warning_date") == "2026-10-16")
	DirAccess.remove_absolute(Preferences.storage_path)

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
	assert(popup.skip_today_checkbox.visible)
	assert(popup.skip_today_checkbox.text == "今日不再提示")
	assert(not popup.skip_today_checkbox.button_pressed)
	assert(int((GridManager.get_item(Vector2i(0, 0)) as Dictionary).get("id", 0)) == 5004)
	assert(int((GridManager.get_item(Vector2i(1, 0)) as Dictionary).get("id", 0)) == 5004)

	popup.skip_today_checkbox.button_pressed = true
	popup.cancel_btn.pressed.emit()
	await popup.hide_animation_finished
	assert(not Preferences.is_suppressed_today(), "cancelling must not save suppression")
	assert(int((GridManager.get_item(Vector2i(0, 0)) as Dictionary).get("id", 0)) == 5004)
	assert(int((GridManager.get_item(Vector2i(1, 0)) as Dictionary).get("id", 0)) == 5004)

	assert(grid_view.call("_try_optimistic_merge", Vector2i(0, 0), Vector2i(1, 0)))
	popup = _find_confirm_popup()
	assert(popup != null)
	assert(not popup.skip_today_checkbox.button_pressed)
	popup.confirm_btn.pressed.emit()
	assert(GridManager.get_item(Vector2i(0, 0)) == null)
	var merged_item: Dictionary = GridManager.get_item(Vector2i(1, 0)) as Dictionary
	assert(int(merged_item.get("level", 0)) == 5)
	assert(not Preferences.is_suppressed_today(), "unchecked confirmation keeps warnings")
	await popup.hide_animation_finished

	_add_pair(Vector2i(2, 0), Vector2i(3, 0), 920001)
	assert(grid_view.call("_try_optimistic_merge", Vector2i(2, 0), Vector2i(3, 0)))
	popup = _find_confirm_popup()
	assert(popup != null)
	popup.skip_today_checkbox.button_pressed = true
	popup.confirm_btn.pressed.emit()
	assert(Preferences.is_suppressed_today())
	await popup.hide_animation_finished
	_add_pair(Vector2i(4, 0), Vector2i(5, 0), 930001)
	assert(grid_view.call("_try_optimistic_merge", Vector2i(4, 0), Vector2i(5, 0)))
	assert(_find_confirm_popup() == null)
	assert(int((GridManager.get_item(Vector2i(5, 0)) as Dictionary).get("level", 0)) == 5)

	# Expired preferences restore the warning for a new day.
	Preferences.suppress_today(Time.get_unix_time_from_system() - 86400.0)
	_add_pair(Vector2i(0, 1), Vector2i(1, 1), 940001)
	assert(grid_view.call("_try_optimistic_merge", Vector2i(0, 1), Vector2i(1, 1)))
	popup = _find_confirm_popup()
	assert(popup != null)
	popup.cancel_btn.pressed.emit()
	await popup.hide_animation_finished
	var ordinary: ConfirmPopup = preload("res://scenes/ui/common/ConfirmPopup.tscn").instantiate() as ConfirmPopup
	add_child(ordinary)
	assert(not ordinary.skip_today_checkbox.visible)

	CultivationService.current_level = original_level
	DirAccess.remove_absolute(Preferences.storage_path)
	Preferences.storage_path = original_path
	print("MERGE_REALM_WARNING_SMOKE_OK caps cancel confirm checkbox persistence skip midnight ordinary")
	get_tree().quit()


func _add_pair(from_pos: Vector2i, to_pos: Vector2i, uid: int) -> void:
	var first: Dictionary = ConfigDatabase.get_item_data(5004).duplicate(true)
	var second: Dictionary = first.duplicate(true)
	first["_uid"] = uid
	second["_uid"] = uid + 1
	assert(GridManager.add_item(first, from_pos))
	assert(GridManager.add_item(second, to_pos))


func _find_confirm_popup() -> ConfirmPopup:
	for child: Node in UIManager._active_popups:
		if child is ConfirmPopup:
			return child as ConfirmPopup
	return null
