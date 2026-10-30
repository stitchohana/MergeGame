extends Node


func _ready() -> void:
	CultivationService.current_level = 2
	GameState.activity_defs = [{"id": 5, "active": true, "widget": "CardCollection"}]
	GameState.card_collection_progress = {"1": {"packs": {"1": 2, "5": 1}, "cards": {"101": 2, "102": 1, "103": 1, "104": 1, "105": 1}, "claimed_sets": [], "opened_count": 0}}
	await get_tree().process_frame
	var game_screen: Control = preload("res://scenes/screens/GameScreen.gd").new()
	for tier: Array in [[199, 1701], [200, 1702], [599, 1702], [600, 1703]]:
		var original: Dictionary = {"total_value": tier[0], "rewards": {"tokens": [{"token": 2, "amount": tier[0]}]}}
		var displayed: Dictionary = game_screen._with_active_activity_rewards(original)
		assert(displayed.rewards.items == [{"id": tier[1], "count": 1}])
		assert(not original.rewards.has("items"))
		var order_entry: RequirementEntry = preload("res://scenes/ui/meridian/RequirementEntry.tscn").instantiate()
		add_child(order_entry)
		order_entry.setup([{"item_id": 5001}], 0, false, displayed.rewards)
		var reward_box: HBoxContainer = order_entry.get_node("RewardRow/RewardBox")
		assert(reward_box.get_child_count() == 2)
		var slot: RewardSlot = reward_box.get_child(1) as RewardSlot
		assert(slot.icon_rect.texture != null)
		assert(slot.count_label.text == "1")
		order_entry.queue_free()
	GameState.activity_defs[0]["active"] = false
	assert(game_screen._with_active_activity_rewards({"total_value": 600}).rewards.get("items", []).is_empty())
	GameState.activity_defs[0]["active"] = true
	game_screen.free()
	var panel := preload("res://scenes/ui/activity/CardCollectionPanel.tscn").instantiate() as CardCollectionPanel
	UIManager.show_popup(panel)
	panel.setup(5)
	await get_tree().process_frame
	assert(panel._summary.text.contains("5 / 108"))
	assert(panel._countdown.text == "长期开放")
	var deadline: int = int(Time.get_unix_time_from_system()) + 90061
	GameState.activity_defs[0]["end_time"] = Time.get_datetime_string_from_unix_time(deadline) + "Z"
	panel._update_countdown(deadline - 90061)
	assert(panel._countdown.text == "活动剩余：1天 01:01:01")
	panel._update_countdown(deadline - 1)
	assert(panel._countdown.text == "活动剩余：0天 00:00:01")
	panel._update_countdown(deadline)
	assert(panel._countdown.text == "活动已结束")
	assert(panel._activity_timestamp("2026-10-20T08:00:00+08:00") == panel._activity_timestamp("2026-10-20T00:00:00Z"))
	assert(panel._activity_timestamp("2026-10-19T16:00:00-08:00") == panel._activity_timestamp("2026-10-20T00:00:00Z"))
	GameState.activity_defs[0]["start_time"] = Time.get_datetime_string_from_unix_time(deadline - 3600) + "Z"
	panel._update_countdown(deadline - 3661)
	assert(panel._countdown.text == "距活动开始：0天 00:01:01")
	GameState.activity_defs[0].erase("start_time")
	GameState.activity_defs[0].erase("end_time")
	panel._update_countdown()
	assert(panel._card_grids.size() == 12)
	for grid: GridContainer in panel._card_grids:
		assert(grid.get_child_count() == 9)
	var claim_buttons: Array[Node] = panel.find_children("*", "Button", true, false).filter(func(button: Node) -> bool: return button.text.begins_with("集齐领取"))
	assert(claim_buttons.is_empty())
	assert(panel.find_children("*", "Label", true, false).filter(func(label: Node) -> bool: return label.text.begins_with("集齐奖励")).size() == 12)
	GameState.card_collection_progress["1"]["claimed_sets"] = [1]
	GameState.card_collection_changed.emit()
	assert(panel.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text.begins_with("已发放")))
	assert(not panel.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text == "我的卡包"))
	assert(panel._points_label.text == "集卡积分：0 · 累计获得：0")
	assert(panel._exchange_button.disabled)
	GameState.card_collection_progress["1"]["duplicate_points"] = 200
	GameState.card_collection_progress["1"]["total_duplicate_points"] = 250
	GameState.card_collection_changed.emit()
	assert(not panel._exchange_button.disabled)
	assert(panel._points_label.text == "集卡积分：200 · 累计获得：250")
	await UIManager.hide_popup(panel)
	var reward: Dictionary = {"uid": 120, "kind": "card_pack", "id": 5, "pack_id": 5, "collection_id": 1, "name": "五星卡包"}
	var normal: Dictionary = {"uid": 121, "id": 5001, "name": "露芽米"}
	RewardManager.sync_pending({"storage_revision": 7, "pending_rewards": [reward, normal]})
	var bar := preload("res://scenes/ui/main/PendingRewardBar.tscn").instantiate() as PendingRewardBar
	add_child(bar)
	assert(bar.claim_button.text.contains("卡包"))
	bar._on_claim_button_pressed()
	await get_tree().process_frame
	var opening: CardPackOpeningPopup = get_tree().root.find_children("*", "CardPackOpeningPopup", true, false)[0] as CardPackOpeningPopup
	assert(opening.selected_reward.uid == 120)
	assert(opening._countdown.text == "长期开放")
	assert(not opening._open_selected.disabled)
	assert(not opening._open_all.disabled)
	assert(opening._exchange_button.text == "兑换5星卡包 · 200积分")
	assert(not opening._exchange_button.disabled)
	GameState.activity_defs[0]["end_time"] = "2026-01-01T00:00:00Z"
	opening._last_countdown_second = -1
	opening._last_time_active = true
	opening._process(1.0)
	assert(opening._countdown.text == "活动已结束")
	assert(opening._exchange_button.disabled)
	assert(opening._open_selected.disabled)
	assert(opening._open_all.disabled)
	GameState.activity_defs[0].erase("end_time")
	opening._refresh()
	CloudService.card_collection_busy = true
	opening._refresh()
	assert(opening._exchange_button.disabled)
	CloudService.card_collection_busy = false
	opening._refresh()
	assert(not bar._claim_pending)
	# Configured effect item rewards render their icon and skip board-item discovery.
	var pack_item: Dictionary = ConfigDatabase.get_item_data(1705)
	assert(int(pack_item.get("effect_type", 0)) == Constants.EffectType.CARD_PACK)
	assert(int(pack_item.get("effect_value", 0)) == 5)
	reward["id"] = 1705
	reward["icon"] = pack_item["icon"]
	RewardManager.pending_rewards[0] = reward.duplicate(true)
	bar._refresh(2)
	assert(bar.item_icon.texture != null)
	CloudService._register_confirmed_item_discoveries("quest_claim", {"rewards": {"items": [{"id": 1705, "count": 1}]}})
	assert(not GameState.has_crafted_item(1705))
	RewardManager.sync_pending({"storage_revision": 8, "pending_rewards": [normal]})
	assert(opening._open_selected.disabled)
	assert(opening._open_all.disabled)
	assert(bar.claim_button.text.is_empty())
	RewardManager._on_state_loaded({"storage_revision": 7, "pending_rewards": [reward, normal]})
	assert(RewardManager.pending_rewards.size() == 1)
	# Redeeming with no pending packs updates balance and enables all-open for the new pack.
	var exchange_response: Dictionary = {"ok": true, "collection_id": 1, "exchanged": true, "points_spent": 200, "storage_revision": 9, "pending_rewards": [normal, reward], "card_collection_progress": {"1": {"revision": 9, "cards": {"101": 2}, "claimed_sets": [1], "opened_count": 0, "duplicate_points": 0, "total_duplicate_points": 250, "exchange_count": 1}}}
	CloudService._dispatch_response("card_collection", exchange_response)
	assert(opening._exchange_button.disabled)
	assert(not opening._open_all.disabled)
	assert(opening._points_label.text == "集卡积分：0 · 累计获得：250")
	assert(RewardManager.pending_rewards.size() == 2)
	CloudService._sync_card_collection({"card_collection_progress": {"1": {"revision": 8, "duplicate_points": 200}}}, "fetch_state")
	assert(int(GameState.get_card_collection_progress(1).get("duplicate_points", -1)) == 0)
	var completion: Dictionary = {"ok": true, "collection_id": 1, "pack_id": 5, "duplicate_points_gained": 7, "completed_sets": [{"collection_id": 1, "set_id": 1}], "rewards": {"tokens": [{"token": 3, "amount": 300}, {"token": 1, "amount": 1000}]}, "cards": [{"card_id": 105, "star": 2, "count": 2, "gained": 1, "is_new": false}, {"card_id": 106, "star": 1, "count": 3, "gained": 3, "is_new": true}]}
	CloudService._on_card_collection_response(completion)
	await get_tree().process_frame
	var received: RewardReceivedPopup = UIManager._active_popups.back() as RewardReceivedPopup
	assert(received != null)
	assert(received.title_label.text == "卡组集齐奖励")
	assert(received.message_label.text.contains("山海灵踪"))
	assert(received.message_label.text.contains("奖励已自动到账"))
	assert(received.rewards_container.get_child_count() == 2)
	assert(received.rewards_container.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text == "体力 ×300"))
	assert(received.rewards_container.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text == "灵石 ×1000"))
	var popup_count: int = UIManager._active_popups.size()
	CloudService.card_collection_confirmed.emit(completion)
	await get_tree().process_frame
	assert(UIManager._active_popups.size() == popup_count)
	await UIManager.hide_popup(received)
	assert(UIManager._active_popups.back() == opening)
	assert(opening._result != null)
	assert(opening._card_grids.size() == 1)
	assert(opening._result.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text == "奖励已到账：300 体力 + 1000 灵石"))
	assert(opening._result.find_children("*", "Label", true, false).any(func(label: Node) -> bool: return label.text == "重复卡获得集卡积分：+7"))
	CloudService._sync_card_collection({"card_collection_progress": {"1": {"revision": 10, "packs": {"5": 2}, "cards": {}, "claimed_sets": [], "opened_count": 3}}}, "fetch_state")
	CloudService._sync_card_collection({"card_collection_progress": {"1": {"revision": 8, "packs": {"5": 3}, "cards": {}, "claimed_sets": [], "opened_count": 2}}}, "fetch_state")
	assert(int(GameState.get_card_collection_progress(1).get("opened_count", 0)) == 3)
	# Restore pending entry for the optional screenshot.
	RewardManager.sync_pending({"storage_revision": 10, "pending_rewards": [reward, normal]})
	GameState.card_collection_progress = {"1": {"packs": {"1": 2, "5": 1}, "cards": {"101": 2, "102": 1, "103": 1, "104": 1, "105": 1}, "claimed_sets": [1], "opened_count": 1, "duplicate_points": 207, "total_duplicate_points": 407, "exchange_count": 1}}
	GameState.card_collection_changed.emit()
	await get_tree().create_timer(0.5).timeout
	if "--screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/card_collection_ui.png")
	await UIManager.hide_popup(opening)
	await get_tree().process_frame
	# Completion is still announced if the opening window closed before the response.
	CloudService.card_collection_confirmed.emit({"cards": [], "completed_sets": [{"collection_id": 1, "set_id": 2}, {"collection_id": 1, "set_id": 3}], "rewards": {"tokens": [{"token": 3, "amount": 900}, {"token": 1, "amount": 3500}]}})
	await get_tree().process_frame
	var combined: RewardReceivedPopup = UIManager._active_popups.back() as RewardReceivedPopup
	assert(combined.message_label.text.contains("洞天仙物、九霄奇珍"))
	assert(combined.rewards_container.get_child_count() == 2)
	await UIManager.hide_popup(combined)
	CloudService.card_collection_confirmed.emit({"cards": [], "collection_id": 1})
	await get_tree().process_frame
	assert(UIManager._active_popups.is_empty())
	print("CARD_COLLECTION_UI_SMOKE_OK")
	get_tree().quit()
