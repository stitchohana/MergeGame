extends Node


func _ready() -> void:
	await get_tree().process_frame
	CultivationService.current_level = 2
	GameState.activity_current_day = 2
	QuestService.quest_defs = []
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/quests.json"))
	for quest: Dictionary in definitions.get("quests", []):
		var configured: Dictionary = quest.duplicate(true)
		configured["rewards"] = ConfigDatabase.get_reward_data(int(quest.get("rewards", 0)))
		configured["weekly_points"] = 10
		QuestService.quest_defs.append(configured)
		QuestService.progress[int(quest.id)] = {"current_count": 0, "completed": false, "claimed": false}
	var weekly: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/weekly_tasks.json"))
	QuestService._weekly_revision = -1
	# Exercise the same JSON numeric types as actual HTTP responses.
	var initial_response: Dictionary = JSON.parse_string(JSON.stringify({"weekly_task_defs": weekly.weekly_tasks, "weekly_task_progress": {
		"3": {"points": 100, "period_key": "2026-10-26", "claimed_stages": [1], "scored_quest_ids": []}}, "storage_revision": 10}))
	QuestService.sync_weekly_state(initial_response)
	var panel: WeeklyActivityPanel = preload("res://scenes/ui/activity/WeeklyActivityPanel.tscn").instantiate() as WeeklyActivityPanel
	UIManager.show_popup(panel)
	panel.setup(3)
	await get_tree().process_frame
	assert(panel.points_summary.text == "本周积分 100 / 350")
	assert(panel.points_bar.value == 100)
	assert(panel.milestones_container.get_child_count() == 4)
	var first: Button = _button(panel, 0)
	assert(first.text == "已领取" and first.disabled)
	assert(QuestService.is_weekly_stage_claimed(3, 1))
	QuestService.claim_weekly_stage(3, 1)
	assert(not QuestService.weekly_claiming, "claimed stages must not send another request")
	assert(_button(panel, 1).text == "领取" and not _button(panel, 1).disabled)
	assert(_button(panel, 2).text == "未达成" and _button(panel, 2).disabled)
	var task: WeeklyTaskSlot = panel.task_list.get_child(1) as WeeklyTaskSlot
	assert(task.rewards_container.get_node("TaskPoints").text == "+10 积分")
	assert(task.rewards_container.get_node("TaskPoints").tooltip_text == "领取任务奖励时获得积分")
	# Claim waiting and failure return to a usable state without issuing a network request.
	QuestService.weekly_claiming = true
	QuestService.weekly_progress_changed.emit()
	await get_tree().process_frame
	assert(_button(panel, 1).disabled)
	QuestService._on_weekly_claim_rejected("network_error")
	await get_tree().process_frame
	assert(not _button(panel, 1).disabled)
	# Ignore stale state responses so an old refresh cannot resurrect claimed rewards.
	QuestService.sync_weekly_state({"storage_revision": 9, "weekly_task_progress": {"3": {"points": 0}}})
	assert(int(QuestService.get_weekly_progress(3).get("points", 0)) == 100)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/weekly_task_points_ui.png")
	# Parse a real HTTP success body; its claimed IDs must disable buttons immediately.
	QuestService.weekly_claiming = true
	var claim_response: Dictionary = {"ok": true, "storage_revision": 11, "stamina": GameState.stamina,
		"weekly_task_progress": {"3": {"points": 100, "period_key": "2026-10-26", "claimed_stages": [1, 2]}},
		"pending_rewards": [{"uid": 900001, "id": 1702, "name": "2星卡包", "kind": "card_pack"}]}
	CloudService._handle_response("weekly_claim", HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(claim_response).to_utf8_buffer())
	await get_tree().process_frame
	assert(not QuestService.weekly_claiming)
	assert(_button(panel, 0).disabled and _button(panel, 0).text == "已领取")
	assert(_button(panel, 1).disabled and _button(panel, 1).text == "已领取")
	assert(RewardManager.pending_rewards.size() == 1 and int(RewardManager.pending_rewards[0].id) == 1702)
	QuestService.claim_weekly_stage(3, 2)
	assert(not QuestService.weekly_claiming)
	# A late response cannot restore the old unclaimed button.
	QuestService.sync_weekly_state(initial_response)
	panel._refresh_milestones()
	assert(_button(panel, 1).disabled and _button(panel, 1).text == "已领取")
	var reset_response: Dictionary = JSON.parse_string(JSON.stringify({"storage_revision": 12, "weekly_task_progress": {"3": {
		"points": 0, "period_key": "2026-11-02", "claimed_stages": []}}}))
	QuestService.sync_weekly_state(reset_response)
	await get_tree().process_frame
	assert(panel.points_bar.value == 0 and _button(panel, 0).text == "未达成")
	assert(not QuestService.is_weekly_stage_claimed(3, 1) and not QuestService.is_weekly_stage_claimed(3, 2))
	# Receiving a task claim updates both the task row and weekly score immediately.
	var task_response: Dictionary = {"ok": true, "storage_revision": 13,
		"quest_id": 1011, "quest_progress": {"1011": {"current_count": 5, "completed": true, "claimed": true}},
		"weekly_task_progress": {"3": {"points": 10, "period_key": "2026-11-02", "claimed_stages": [], "scored_quest_ids": [1011]}}}
	CloudService._handle_response("quest_claim", HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(task_response).to_utf8_buffer())
	await get_tree().process_frame
	assert(panel.points_summary.text == "本周积分 10 / 350" and panel.points_bar.value == 10)
	assert(QuestService.get_progress(1011).claimed)
	var claimed_task: WeeklyTaskSlot = panel.task_list.get_child(1) as WeeklyTaskSlot
	assert(claimed_task.done_label.visible and not claimed_task.claim_btn.visible)
	# Old state arriving after collection cannot erase the awarded points.
	QuestService.sync_weekly_state(reset_response)
	assert(int(QuestService.get_weekly_progress(3).points) == 10)
	# Close and reopen without leaking listeners or duplicating day buttons.
	panel._on_close()
	await get_tree().create_timer(0.3).timeout
	print("WEEKLY_TASK_POINTS_UI_SMOKE_OK task_claim_points json_claims duplicate_guard rewards points retry stale reset close")
	get_tree().quit()


func _button(panel: WeeklyActivityPanel, index: int) -> Button:
	return panel.milestones_container.get_child(index).get_child(0).get_node("ClaimButton") as Button
