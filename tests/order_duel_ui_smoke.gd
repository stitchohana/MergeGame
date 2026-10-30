extends Node


func _ready() -> void:
	await get_tree().process_frame
	CultivationService.current_level = 2
	var tiers: Array = []
	for tier: int in range(1, 11):
		tiers.append({"tier": tier, "required_points": tier * 10, "stamina": tier * 10, "spirit_stones": tier * 100})
	ActivityManager.order_duel = {"active": true, "status": "playing", "round": 1, "victory_points": 30, "my_points": 65,
		"opponent": {"name": "云岫 · 机器人", "bot": true, "points": 40}, "rewards": tiers, "claimed_tiers": [1],
		"settings": {"target_points": 100, "order_points_ratio": 0.1, "win_stamina": 30, "win_points": 10, "matchmaking_seconds": 1}}
	var panel := preload("res://scenes/ui/activity/OrderDuelPanel.tscn").instantiate() as OrderDuelPanel
	UIManager.show_popup(panel)
	await get_tree().process_frame
	assert(panel._rewards.get_child_count() == 10)
	assert(panel._mine.value == 65)
	assert(panel._opponent.value == 40)
	assert(panel._rules.text.contains("30 体力"))
	assert(not panel._start.visible and not panel._rest.visible)
	var first_claim: Button = panel._rewards.get_child(0).get_child(0).get_child(1) as Button
	var second_claim: Button = panel._rewards.get_child(1).get_child(0).get_child(1) as Button
	var last_claim: Button = panel._rewards.get_child(9).get_child(0).get_child(1) as Button
	assert(first_claim.disabled and first_claim.text == "已领取")
	assert(not second_claim.disabled and second_claim.text == "领取")
	assert(last_claim.disabled and last_claim.text == "未解锁")
	ActivityManager.order_duel["status"] = "lost"
	ActivityManager.order_duel["last_result"] = {"won": false, "my_points": 65, "opponent_points": 100}
	panel._refresh()
	assert(panel._start.visible and panel._rest.visible)
	assert(panel._start.text == "下一场对战")
	assert(panel._result.text.contains("惜败"))
	panel._busy = true
	panel._refresh()
	assert(panel._start.disabled and panel._rest.disabled and panel._refresh_button.disabled)
	panel._on_failed("state_conflict")
	assert(not panel._busy and panel._status.text.contains("重试"))
	ActivityManager.order_duel["status"] = "matching"
	ActivityManager.order_duel["last_result"] = {"won": true, "stamina": 30, "victory_points": 10}
	panel._refresh()
	assert(panel._result.text.contains("已到账 30 体力"))
	assert(panel._status.text.contains("1 秒后机器人补位"))
	assert(not panel._start.visible and not panel._rest.visible)
	CloudService._order_duel_revision = -1
	CloudService._sync_order_duel({"storage_revision": 10, "order_duel": ActivityManager.order_duel.duplicate(true)})
	CloudService._sync_order_duel({"storage_revision": 9, "order_duel": {"victory_points": 0}})
	assert(int(ActivityManager.order_duel.get("victory_points", 0)) == 30)
	var shared: Dictionary = ActivityManager.order_duel.duplicate(true)
	shared["registry_revision"] = 20
	CloudService._sync_order_duel({"storage_revision": 10, "order_duel": shared})
	var older: Dictionary = shared.duplicate(true)
	older["registry_revision"] = 19
	older["victory_points"] = 0
	CloudService._sync_order_duel({"storage_revision": 10, "order_duel": older})
	assert(int(ActivityManager.order_duel.get("victory_points", 0)) == 30)
	var entry := preload("res://scenes/ui/activity/HomeActivityCard.tscn").instantiate() as HomeActivityCard
	add_child(entry)
	entry.setup({"id": 8, "name": "订单对战", "widget": "OrderDuel", "active": true})
	assert(entry.activity_mark.text == "战")
	assert(entry.status_label.text.contains("匹配"))
	ActivityManager.order_duel["active"] = false
	panel._refresh()
	assert(not panel._start.visible and panel._status.text.contains("未开放"))
	if "--screenshot" in OS.get_cmdline_user_args():
		ActivityManager.order_duel["active"] = true
		ActivityManager.order_duel["status"] = "playing"
		panel._refresh()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/order_duel_ui.png")
	entry.queue_free()
	await UIManager.hide_popup(panel)
	_check_matching_poll()
	ActivityManager.reset_progress()
	assert(ActivityManager.order_duel.is_empty())
	await get_tree().process_frame
	print("ORDER_DUEL_UI_SMOKE_OK")
	get_tree().quit()


func _check_matching_poll() -> void:
	# Occupy query slots so requests can be observed without making network calls.
	var old_online: bool = CloudService.online
	var old_requests: Dictionary = CloudService._query_requests.duplicate()
	var old_queue: Array[Dictionary] = CloudService._query_queue.duplicate()
	CloudService._query_requests.clear()
	CloudService._query_queue.clear()
	for index: int in range(CloudService.QUERY_CONCURRENCY):
		CloudService._query_requests[index] = {}
	CloudService.online = true
	ActivityManager._duel_poll_status = ""
	ActivityManager.order_duel["status"] = "matching"
	ActivityManager._process(0.99)
	assert(CloudService._query_queue.is_empty())
	ActivityManager._process(0.02)
	assert(CloudService._query_queue.size() == 1)
	assert(CloudService._query_queue[0].path == "/api/game/order_duel")
	ActivityManager._process(1.0)
	assert(CloudService._query_queue.size() == 1, "slow matching queries must not accumulate")
	CloudService._query_queue.clear()
	ActivityManager.order_duel["status"] = "playing"
	ActivityManager._process(1.0)
	assert(CloudService._query_queue.is_empty())
	ActivityManager._process(9.0)
	assert(CloudService._query_queue.size() == 1)
	ActivityManager.order_duel["status"] = "resting"
	ActivityManager._process(10.0)
	assert(CloudService._query_queue.size() == 1)
	CloudService.online = old_online
	CloudService._query_requests = old_requests
	CloudService._query_queue = old_queue
