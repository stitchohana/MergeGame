extends Node


func _ready() -> void:
	GameState.home_meridian_defs = [{"acupoints": 1, "qi_cost": 1}]
	GameState.home_meridian_progress = []
	CultivationService.current_qi = 10
	GameState.pending_auto_acupoint = false
	var requirement_list: RequirementList = preload("res://scenes/ui/meridian/RequirementList.tscn").instantiate() as RequirementList
	add_child(requirement_list)
	await get_tree().process_frame
	requirement_list.set_requirements([{"items": [{"item_id": 5002}], "completed": false}])
	assert(requirement_list._can_activate_acupoint())
	var battle_pass: BattlePassEntry = requirement_list.container.get_node("BattlePassEntry") as BattlePassEntry
	battle_pass.setup({"id": 4, "name": "Battle pass"})
	var weekly: WeeklyActivityEntry = preload("res://scenes/ui/activity/WeeklyActivityEntry.tscn").instantiate() as WeeklyActivityEntry
	requirement_list.container.add_child(weekly)
	weekly.setup({"id": 3, "name": "Weekly"})
	var activity_cards: Array[HomeActivityCard] = []
	for widget: String in ["CardCollection", "StairClimb", ""]:
		var card: HomeActivityCard = preload("res://scenes/ui/activity/HomeActivityCard.tscn").instantiate() as HomeActivityCard
		requirement_list.container.add_child(card)
		card.setup({"id": 5, "name": "Activity", "widget": widget, "active": true})
		activity_cards.append(card)
	var popup_layer: Control = UIManager.get_layer(UIManager.Layer.POPUP)
	var popup_count: int = popup_layer.get_child_count()

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
	battle_pass.pressed.emit()
	weekly.btn.pressed.emit()
	for card: HomeActivityCard in activity_cards:
		card.pressed.emit()
	_emit_other_entry_clicks(requirement_list)
	assert(completed_indices.is_empty(), "Scrolling must not submit orders")
	assert(not GameState.pending_auto_acupoint, "Scrolling must not switch to cultivation")
	assert(popup_layer.get_child_count() == popup_count, "Scrolling entries must not open popups")
	await get_tree().process_frame

	# A drag remains cancelled after leaving the list, returning to its start,
	# or moving vertically with no horizontal scroll distance.
	for outside: bool in [true, false]:
		press_event.position = start_position
		requirement_list._input(press_event)
		drag_event.position = start_position + Vector2(0, 300 if outside else RequirementList.DRAG_THRESHOLD + 1)
		requirement_list._input(drag_event)
		release_event.position = start_position
		requirement_list._input(release_event)
		_emit_other_entry_clicks(requirement_list)
		assert(completed_indices.is_empty())
		assert(not GameState.pending_auto_acupoint)
		assert(popup_layer.get_child_count() == popup_count)
		await get_tree().process_frame

	requirement_list._emit_complete(3)
	assert(completed_indices == [3])
	requirement_list.cultivation_button.pressed.emit()
	assert(GameState.pending_auto_acupoint, "Tapping must still activate cultivation")
	battle_pass.pressed.emit()
	assert(popup_layer.get_child_count() == popup_count + 1, "Tapping an activity entry must still open its popup")
	await UIManager.hide_popup(popup_layer.get_child(popup_count) as BasePopup)
	popup_layer.get_child(popup_count).queue_free()
	await get_tree().process_frame
	var character: CharacterEntry = requirement_list.container.get_node("CharacterEntry") as CharacterEntry
	character.reward_button.pressed.emit()
	assert(popup_layer.get_child_count() == popup_count + 1, "Tapping the character reward must still open its popup")
	await UIManager.hide_popup(popup_layer.get_child(popup_count) as BasePopup)
	popup_layer.get_child(popup_count).queue_free()
	await get_tree().process_frame
	requirement_list.pending_reward_bar.claim_button.pressed.emit()
	assert(popup_layer.get_child_count() == popup_count + 1, "Tapping a stored card pack must still open its popup")
	var standalone: HomeActivityCard = preload("res://scenes/ui/activity/HomeActivityCard.tscn").instantiate() as HomeActivityCard
	add_child(standalone)
	assert(not RequirementList.is_scroll_click_cancelled(standalone))
	print("ORDER_SCROLL_CLICK_GUARD_SMOKE_OK")
	get_tree().quit()


func _emit_other_entry_clicks(requirement_list: RequirementList) -> void:
	var character: CharacterEntry = requirement_list.container.get_node("CharacterEntry") as CharacterEntry
	character.reward_button.pressed.emit()
	requirement_list.cultivation_button.pressed.emit()
	var order: RequirementEntry = requirement_list.get_order_entries()[0]
	(order.get_node("CompleteButton") as Button).pressed.emit()
	(order.get_node("ItemsContainer").get_child(0) as ItemWidget).pressed.emit()
	var pending: PendingRewardBar = requirement_list.pending_reward_bar
	RewardManager.pending_rewards = [{"uid": 99, "id": 5002, "name": "Item"}]
	pending._refresh(1)
	pending.claim_button.pressed.emit()
	assert(not pending._claim_pending, "Scrolling must not claim stored items")
	RewardManager.pending_rewards = [{"uid": 100, "kind": "card_pack", "collection_id": 1, "pack_id": 1, "name": "Pack"}]
	pending._refresh(1)
	pending.claim_button.pressed.emit()
