extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	GameState.set_crafted_item_ids([1001, 1002])
	GameState.set_item_catalog_claimed_ids([1002])
	var home: HomeScreen = preload("res://scenes/screens/HomeScreen.tscn").instantiate() as HomeScreen
	add_child(home)
	home.modulate = Color.WHITE
	assert(home.item_catalog_btn.text.contains("待领取 1"))
	home.item_catalog_btn.pressed.emit()
	await get_tree().process_frame
	var panel: ItemCatalogPanel = UIManager._active_popups.back() as ItemCatalogPanel
	assert(panel != null)
	assert(panel._tabs.get_tab_count() == 5)
	var total: int = 0
	for index: int in range(5):
		var category: Dictionary = ItemCatalogPanel.CATEGORIES[index]
		var items: Array = ConfigDatabase.get_items_for_catalog(int(category.type))
		assert(panel._grids[index].get_child_count() == items.size())
		total += items.size()
		panel._tabs.current_tab = index
		await get_tree().process_frame
	assert(panel._tiles.size() == total)
	panel._tabs.current_tab = 0
	var locked: Dictionary = panel._tiles[1003]
	assert(locked.button.disabled)
	assert(locked.mark.visible and locked.mark.text == "？")
	assert(locked.icon.texture == null)
	var reward: Dictionary = panel._tiles[1001]
	assert(not reward.button.disabled)
	assert(reward.icon.texture == ItemCatalogPanel.ENERGY_ICON)
	assert(reward.status.text == "领取 +1 体力")
	var claimed: Dictionary = panel._tiles[1002]
	assert(claimed.button.disabled)
	assert(claimed.icon.texture != null and claimed.icon.texture != ItemCatalogPanel.ENERGY_ICON)
	assert(claimed.status.text == "已领取")
	# Keep the real client request in its queue so this UI test never hits a server.
	CloudService._busy = true
	var scroll: ScrollContainer = panel._grids[0].get_parent() as ScrollContainer
	reward.button.button_down.emit()
	reward.button.set_meta("press_scroll", scroll.scroll_vertical + 20)
	reward.button.pressed.emit()
	assert(CloudService.item_catalog_claim_pending == 0)
	reward.button.button_down.emit()
	reward.button.pressed.emit()
	assert(CloudService.item_catalog_claim_pending == 1001)
	assert(CloudService._request_queue.size() == 1)
	CloudService.submit_item_catalog_claim(1001)
	assert(CloudService._request_queue.size() == 1)
	assert(JSON.parse_string(str(CloudService._request_queue[0].body)).item_id == 1001)
	CloudService._request_queue.clear()
	CloudService._busy = false
	assert(reward.button.disabled and reward.status.text == "领取中…")
	CloudService.item_catalog_claim_rejected.emit("save_failed")
	assert(CloudService.item_catalog_claim_pending == 0)
	assert(not reward.button.disabled)
	assert(panel._status.text.contains("重试"))
	CloudService._item_catalog_revision = -1
	CloudService._dispatch_response("item_catalog_claim", {"ok": true, "item_id": 1001, "reward_stamina": 1,
		"stamina": 101, "max_stamina": 100, "storage_revision": 10, "crafted_item_ids": [1001, 1002], "item_catalog_claimed_ids": [1001, 1002]})
	assert(GameState.stamina == 101)
	assert(GameState.item_catalog_claimed_ids.has(1001))
	assert(reward.button.disabled and reward.status.text == "已领取")
	assert(reward.icon.texture != ItemCatalogPanel.ENERGY_ICON)
	assert(home.item_catalog_btn.text == "图鉴")
	CloudService._sync_item_catalog({"storage_revision": 9, "item_catalog_claimed_ids": []})
	assert(GameState.item_catalog_claimed_ids.has(1001))
	# A newly discovered item becomes claimable while the popup remains open.
	GameState.register_new_item_ids([1003])
	assert(not locked.button.disabled and locked.icon.texture == ItemCatalogPanel.ENERGY_ICON)
	assert(home.item_catalog_btn.text.contains("待领取 1"))
	# Successful claims reveal the next reward, skipping locked and claimed tiles.
	var far_tile: Button = panel._grids[0].get_child(80) as Button
	var far_item_id: int = int(far_tile.get_meta("item_id"))
	GameState.set_crafted_item_ids([1001, 1002, 1003, far_item_id])
	GameState.set_item_catalog_claimed_ids([1001, 1002, 1003])
	scroll.scroll_vertical = 0
	panel._on_confirmed({"item_id": 1003})
	await get_tree().process_frame
	await get_tree().process_frame
	assert(scroll.scroll_vertical > 0)
	assert(far_tile.get_global_rect().position.y >= scroll.get_global_rect().position.y)
	assert(far_tile.get_global_rect().end.y <= scroll.get_global_rect().end.y)
	# Wrap to an earlier reward when there are none after the claimed item.
	GameState.set_item_catalog_claimed_ids([1002, 1003, far_item_id])
	panel._on_confirmed({"item_id": far_item_id})
	await get_tree().process_frame
	await get_tree().process_frame
	assert(scroll.scroll_vertical == 0)
	# An exhausted page keeps its position, even if another tab has rewards.
	var other_tile: Button = panel._grids[1].get_child(0) as Button
	var other_item_id: int = int(other_tile.get_meta("item_id"))
	GameState.set_crafted_item_ids([1001, 1002, 1003, far_item_id, other_item_id])
	GameState.set_item_catalog_claimed_ids([1001, 1002, 1003, far_item_id])
	scroll.scroll_vertical = 200
	var exhausted_position: int = scroll.scroll_vertical
	panel._on_confirmed({"item_id": 1003})
	await get_tree().process_frame
	await get_tree().process_frame
	assert(scroll.scroll_vertical == exhausted_position and panel._tabs.current_tab == 0)
	# A delayed confirmation never scrolls a newly selected tab.
	GameState.set_item_catalog_claimed_ids([1002, 1003, far_item_id])
	panel._on_confirmed({"item_id": far_item_id})
	panel._tabs.current_tab = 1
	await get_tree().process_frame
	await get_tree().process_frame
	assert(scroll.scroll_vertical == exhausted_position and panel._tabs.current_tab == 1)
	panel._tabs.current_tab = 0
	GameState.set_crafted_item_ids([1001, 1002, 1003])
	GameState.set_item_catalog_claimed_ids([1001, 1002])
	scroll.scroll_vertical = 0
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/item_catalog_ui.png")
		await UIManager.hide_popup(panel)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/item_catalog_home.png")
	else:
		await UIManager.hide_popup(panel)
	assert(not UIManager.is_input_blocked())
	print("ITEM_CATALOG_UI_SMOKE_OK")
	get_tree().quit()
