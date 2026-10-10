extends Node


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	ActivityManager.reset_progress()
	ActivityManager.sync_state({"storage_revision": 1, "activity_defs": [{"id": 7, "name": "订单补给", "widget": "OrderSupply", "active": true, "config": {"target_count": 5}}], "activity_progress": {"7": {"current_count": 0}}})
	var entry := preload("res://scenes/ui/activity/OrderSupplyEntry.tscn").instantiate() as OrderSupplyEntry
	add_child(entry)
	assert(entry.visible and entry.disabled and entry.text.contains("0/5"))
	CloudService._dispatch_response("spawn", {"ok": true, "storage_revision": 1, "spawned_id": 5001, "activity_progress": {"7": {"current_count": 1}}})
	assert(entry.text.contains("1/5"))
	var claims: Array = []
	entry.claim_requested.connect(func(id: int, round_count: int) -> void: claims.append([id, round_count]))
	CloudService._dispatch_response("merge", {"ok": true, "storage_revision": 2, "activity_progress": {"7": {"current_count": 4}}})
	assert(entry.disabled and entry.text.contains("4/5"))
	CloudService._dispatch_response("craft_start", {"ok": true, "storage_revision": 3, "activity_progress": {"7": {"current_count": 5}}})
	assert(not entry.disabled and entry.text.contains("领取"))
	entry.pressed.emit()
	entry.pressed.emit()
	assert(claims == [[7, 0]] and entry.disabled)
	CloudService.order_supply_claim_rejected.emit("board_full")
	assert(not entry.disabled and entry.text.contains("5/5"))
	CloudService._dispatch_response("order_supply_claim", {"ok": true, "activity_id": 7, "storage_revision": 4, "activity_progress": {"7": {"current_count": 0, "claim_count": 1}}})
	assert(entry.disabled and entry.text.contains("0/5"))
	ActivityManager.sync_state({"storage_revision": 3, "activity_progress": {"7": {"current_count": 5}}})
	assert(entry.text.contains("0/5"))
	entry.queue_free()
	var screen := preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(screen)
	await get_tree().process_frame
	ActivityManager.sync_state({"storage_revision": 5, "activity_progress": {7: {"current_count": 5, "claim_count": 1}}})
	assert(not screen.order_supply_entry.disabled)
	assert(screen.order_supply_entry.get_global_rect().end.y < screen.requirement_list.get_global_rect().position.y)
	var multiplier: Control = screen.get_node("StaminaMultiplierControl")
	assert(not multiplier.get_global_rect().intersects(screen.order_supply_entry.get_global_rect()))
	screen.order_supply_entry._claim_pending = true
	screen.grid_view._cancel_action_sync_waiters("")
	assert(not screen.order_supply_entry._claim_pending)
	screen._order_supply_input_token = UIManager.begin_input_block("supply_test")
	CloudService._dispatch_response("order_supply_claim", {"ok": true, "activity_id": 7, "storage_revision": 6, "activity_progress": {"7": {"current_count": 0, "claim_count": 2}}, "grid": [{"id": 5001, "uid": 9999, "col": 0, "row": 0}]})
	assert(screen._order_supply_input_token == -1)
	assert(screen.order_supply_entry.text.contains("0/5"))
	assert(int(GridManager.get_item(Vector2i.ZERO).get("_uid", 0)) == 9999)
	assert(GameState.main_grid_cache.size() == 1)
	var pending: Array = [{"id": 5001, "uid": 10000, "name": "露芽米"}]
	CloudService._dispatch_response("order_supply_claim", {"ok": true, "activity_id": 7, "storage_revision": 7, "activity_progress": {"7": {"current_count": 0, "claim_count": 3}}, "grid": GameState.main_grid_cache, "spawned_items": [], "pending_rewards_added": 1, "pending_rewards": pending})
	assert(RewardManager.pending_rewards == pending)
	assert(screen.order_supply_entry.text.contains("0/5"))
	var pending_bar := preload("res://scenes/ui/main/PendingRewardBar.tscn").instantiate() as PendingRewardBar
	add_child(pending_bar)
	assert(pending_bar.visible and pending_bar.item_icon.texture != null)
	pending_bar.queue_free()
	var recipe: Dictionary = {"id": 1, "result": 27001, "craft_time": 60}
	var craft: Dictionary = {"_craft_init": true, "_craft_state": CraftingService.TableState.CRAFTING,
		"_craft_recipe": recipe, "_craft_result_id": 27001, "_craft_progress": 0.0,
		"_craft_start_time": Time.get_unix_time_from_system() * 1000.0}
	var table: Dictionary = {"id": 17001, "uid": 10001, "col": 1, "row": 0, "craft": craft}
	screen.grid_view._sync_grid_from_server({"grid": [table]})
	screen.grid_view._restore_crafting_timers()
	var local_table: Dictionary = GridManager.get_item(Vector2i(1, 0))
	assert(local_table.get("_craft_timer") is Timer)
	screen._on_item_clicked(local_table, Vector2i(1, 0))
	assert(screen.detail_panel.status_label.text.begins_with("制作中"))
	assert(screen.detail_panel.speedup_btn.visible)
	var ready_table: Dictionary = table.duplicate(true)
	ready_table["craft"]["_craft_state"] = CraftingService.TableState.READY
	ready_table["craft"]["_craft_progress"] = 1.0
	CloudService._dispatch_response("order_supply_claim", {"ok": true, "activity_id": 7,
		"storage_revision": 8, "activity_progress": {"7": {"current_count": 0, "claim_count": 4}},
		"grid": [ready_table, {"id": 5001, "uid": 10002, "col": 0, "row": 0}], "crafts_completed": 1})
	local_table = GridManager.get_item(Vector2i(1, 0))
	assert(int(local_table.get("_craft_state", 0)) == CraftingService.TableState.READY)
	assert(float(local_table.get("_craft_progress", 0.0)) == 1.0)
	assert(not local_table.has("_craft_timer"))
	assert(screen.detail_panel.get_current_craft_table() == local_table)
	assert(screen.detail_panel.status_label.text == "制作完成！点击取出")
	assert(not screen.detail_panel.speedup_btn.visible)
	assert(screen.detail_panel._countdown_timer == null)
	assert(screen.detail_panel.get_output_item_id() == 27001)
	# Rewards exist in the authoritative grid immediately, but become visible
	# only as the staggered flights land. Refreshing the grid keeps them hidden.
	var spawned: Array = [
		{"id": 5001, "uid": 10003, "col": 2, "row": 0},
		{"id": 9001, "uid": 10004, "col": 3, "row": 0},
		{"id": 1001, "uid": 10005, "col": 4, "row": 0},
	]
	var reward_grid: Array = [ready_table] + spawned
	screen._on_order_supply_claim_confirmed({"grid": reward_grid, "spawned_items": spawned, "pending_rewards_added": 1})
	assert(screen._order_supply_flying_icons.size() == 3)
	assert(screen._order_supply_input_token >= 0 and UIManager.is_input_blocked())
	assert(not (screen.grid_view._item_nodes["2,0"] as GridItem).visible)
	assert(not (screen.grid_view._item_nodes["4,0"] as GridItem).visible)
	await get_tree().create_timer(0.08).timeout
	assert(screen._order_supply_flying_icons[0].visible)
	assert(not screen._order_supply_flying_icons[1].visible)
	GridManager.grid_updated.emit()
	await get_tree().process_frame
	assert(not (screen.grid_view._item_nodes["2,0"] as GridItem).visible)
	await get_tree().create_timer(Constants.ORDER_SUPPLY_FLY_DURATION - 0.08 + 0.04).timeout
	assert((screen.grid_view._item_nodes["2,0"] as GridItem).visible)
	assert(not (screen.grid_view._item_nodes["4,0"] as GridItem).visible)
	await get_tree().create_timer(Constants.ORDER_SUPPLY_FLY_STAGGER * 2.0 + 0.1).timeout
	assert((screen.grid_view._item_nodes["4,0"] as GridItem).visible)
	assert(screen._order_supply_flying_icons.is_empty())
	assert(screen._order_supply_hidden_items.is_empty())
	assert(screen._order_supply_input_token == -1)
	# Leaving the screen during a flight cleans up icons and the input lock.
	screen._on_order_supply_claim_confirmed({"grid": reward_grid, "spawned_items": spawned})
	if "--flight-screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.23).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/order_supply_flight.png")
	screen.on_exit()
	assert(screen._order_supply_flying_icons.is_empty())
	assert(screen._order_supply_input_token == -1)
	if "--screenshot" in OS.get_cmdline_user_args():
		screen.grid_view._sync_grid_from_server({"grid": reward_grid})
		ActivityManager.sync_state({"storage_revision": 9, "activity_progress": {"7": {"current_count": 5, "claim_count": 4}}})
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://order_supply_ui.png")
	screen.queue_free()
	await get_tree().process_frame
	print("ORDER_SUPPLY_UI_SMOKE_OK")
	get_tree().quit()
