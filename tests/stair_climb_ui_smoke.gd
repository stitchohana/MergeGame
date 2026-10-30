extends Node


func _ready() -> void:
	await get_tree().process_frame
	# Activity UI fixtures must pass the existing cultivation-level unlock gate.
	CultivationService.current_level = 2
	ActivityManager.stair_climb_received_ticks = Time.get_ticks_msec()
	var tiers: Array = []
	for rank: int in range(1, 11):
		tiers.append({"min_rank": rank, "max_rank": rank, "stamina": 300 - (rank - 1) * 25, "spirit_stones": 3000 - (rank - 1) * 250})
	tiers.append({"min_rank": 11, "max_rank": 20, "stamina": 50, "spirit_stones": 500})
	var rows: Array = []
	for rank: int in range(1, 21):
		rows.append({"rank": rank, "name": "云岫" if rank != 3 else "道友03", "bot": rank != 3, "is_self": rank == 3, "points": 2100 - rank * 50})
	ActivityManager.stair_climb = {"realm_name": "练气三层", "server_now": 1000000, "end_time": 1000000 + 86400000, "my_rank": 3, "my_points": 1950, "order_points_ratio": 0.1, "rewards": tiers, "rows": rows, "status": "active"}
	var panel := preload("res://scenes/ui/activity/StairClimbPanel.tscn").instantiate() as StairClimbPanel
	UIManager.show_popup(panel)
	await get_tree().process_frame
	assert(panel._board.get_child_count() == 21)
	assert(panel._summary.text.contains("第 3 名"))
	assert(panel._rules.text.contains("0.1"))
	assert(panel._status.text.contains("250 体力 / 2500 灵石"))
	assert(panel._countdown.text.begins_with("剩余"))
	panel._rewards_open = true
	panel._refresh()
	assert(panel._rewards.get_child_count() == 12)
	assert(panel._rewards.visible)
	panel._on_failed("network_error")
	assert(not panel._refresh_button.disabled)
	assert(panel._status.text.contains("重试"))
	panel._on_loaded({})
	ActivityManager.stair_climb["end_time"] = 0
	ActivityManager.stair_climb["status"] = "ended"
	ActivityManager.stair_climb["settlement"] = {"rank": 3, "reward": {"stamina": 250, "spirit_stones": 2500}}
	panel._refresh()
	assert(panel._status.text.contains("已到账"))
	assert(panel._countdown.text.contains("活动已结束"))
	ActivityManager.defs = [
		{"id": 4, "name": "Disabled", "enabled": false, "active": false},
		{"id": 6, "widget": "StairClimb", "active": false, "result_available": true},
	]
	assert(ActivityManager.get_active_activities().size() == 1)
	var entry := preload("res://scenes/ui/activity/HomeActivityCard.tscn").instantiate() as HomeActivityCard
	add_child(entry)
	entry.setup({"id": 6, "name": "爬天梯", "widget": "StairClimb", "active": true})
	assert(entry.activity_mark.text == "梯")
	assert(entry.status_label.text.contains("比拼中"))
	entry.setup({"id": 6, "name": "爬天梯", "widget": "StairClimb", "active": false, "result_available": true})
	assert(entry.status_label.text.contains("结算"))
	entry.queue_free()
	CloudService._stair_climb_revision = -1
	CloudService._sync_stair_climb({"storage_revision": 10, "stair_climb_progress": {"6:0": {"points": 25}}})
	CloudService._sync_stair_climb({"storage_revision": 9, "stair_climb_progress": {"6:0": {"points": 10}}})
	assert(int(GameState.stair_climb_progress["6:0"]["points"]) == 25)
	if "--screenshot" in OS.get_cmdline_user_args():
		panel._rewards_open = false
		panel._refresh()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/stair_climb_ui.png")
		panel._rewards_open = true
		panel._refresh()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/stair_climb_rewards.png")
	await UIManager.hide_popup(panel)
	print("STAIR_CLIMB_UI_SMOKE_OK")
	get_tree().quit()
