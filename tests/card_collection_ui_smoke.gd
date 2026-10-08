extends Node


func _ready() -> void:
	GameState.activity_defs = [{"id": 5, "active": true, "widget": "CardCollection"}]
	GameState.card_collection_progress = {"1": {"packs": {"1": 2, "5": 1}, "cards": {"101": 2, "102": 1, "103": 1, "104": 1, "105": 1}, "claimed_sets": [], "opened_count": 0}}
	await get_tree().process_frame
	var panel := preload("res://scenes/ui/activity/CardCollectionPanel.tscn").instantiate() as CardCollectionPanel
	UIManager.show_popup(panel)
	panel.setup(5)
	await get_tree().process_frame
	assert(panel._summary.text.contains("5 / 15"))
	assert(panel._card_grids.size() == 3)
	assert(panel._card_grids[0].get_child_count() == 5)
	var claim_buttons: Array[Node] = panel.find_children("*", "Button", true, false).filter(func(button: Node) -> bool: return button.text.begins_with("集齐领取"))
	assert(claim_buttons.size() == 3)
	assert(not claim_buttons[0].disabled)
	assert(claim_buttons[1].disabled)
	GameState.card_collection_progress["1"]["claimed_sets"] = [1]
	GameState.card_collection_changed.emit()
	assert(panel.find_children("*", "Button", true, false).any(func(button: Node) -> bool: return button.text.begins_with("已领取") and button.disabled))
	panel._on_confirmed({"collection_id": 1, "pack_id": 5, "cards": [{"card_id": 105, "star": 5, "count": 2, "is_new": false}, {"card_id": 106, "star": 1, "count": 1, "is_new": true}]})
	assert(panel._result != null)
	assert(panel._card_grids.size() == 4)
	CloudService._sync_card_collection({"card_collection_progress": {"1": {"revision": 9, "packs": {"5": 2}, "cards": {}, "claimed_sets": [], "opened_count": 3}}}, "fetch_state")
	CloudService._sync_card_collection({"card_collection_progress": {"1": {"revision": 8, "packs": {"5": 3}, "cards": {}, "claimed_sets": [], "opened_count": 2}}}, "fetch_state")
	assert(int(GameState.get_card_collection_progress(1).get("opened_count", 0)) == 3)
	# Restore the visual fixture for the optional screenshot.
	GameState.card_collection_progress = {"1": {"packs": {"1": 2, "5": 1}, "cards": {"101": 2, "102": 1, "103": 1, "104": 1, "105": 1}, "claimed_sets": [1], "opened_count": 1}}
	GameState.card_collection_changed.emit()
	await get_tree().create_timer(0.5).timeout
	if "--screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/card_collection_ui.png")
	await UIManager.hide_popup(panel)
	print("CARD_COLLECTION_UI_SMOKE_OK")
	get_tree().quit()
