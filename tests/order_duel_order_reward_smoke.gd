extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CloudService.online = false
	CultivationService.current_level = 2
	var activity: Dictionary = {"id": 8, "widget": "OrderDuel", "active": true, "enabled": true}
	GameState.activity_defs = [activity]
	ActivityManager.order_duel = {"activity_id": 8, "active": true, "status": "playing", "my_points": 0,
		"settings": {"target_points": 100, "order_points_ratio": 0.1}}
	var order: Dictionary = {"item_ids": [5004, 5004], "items": [{"item_id": 5004}, {"item_id": 5004}],
		"total_value": 999999, "rewards": {"tokens": [{"token": 2, "amount": 120}]}}
	var screen := preload("res://scenes/screens/GameScreen.gd").new() as GameScreen
	assert(screen._get_order_duel_points(order) == 4, "Use actual item values, not stale total_value")
	assert(screen._get_order_duel_points({"item_id": 5004, "count": 2}) == 4)
	ActivityManager.order_duel.settings.order_points_ratio = 0.025
	assert(screen._get_order_duel_points(order) == 1)
	ActivityManager.order_duel.settings.order_points_ratio = 0.1
	ActivityManager.order_duel.my_points = 98
	assert(screen._get_order_duel_points(order) == 2, "Cap the reward at the remaining target")
	ActivityManager.order_duel.my_points = 100
	assert(screen._get_order_duel_points(order) == 0)
	ActivityManager.order_duel.my_points = 0
	for state: String in ["matching", "resting", "lost", "locked"]:
		ActivityManager.order_duel.status = state
		assert(screen._get_order_duel_points(order) == 0)
	ActivityManager.order_duel.status = "playing"
	assert(screen._get_order_duel_points({"item_ids": [99999999]}) == 0)
	assert(screen._get_order_duel_points({"item_ids": [5004], "completed": true}) == 0)
	assert(screen._get_order_duel_points({"item_ids": [5004], "breakthrough_order": true}) == 0)
	activity.enabled = false
	assert(screen._get_order_duel_points(order) == 0)
	activity.enabled = true
	activity.end_time = "2020-01-01T00:00:00Z"
	assert(screen._get_order_duel_points(order) == 0)
	activity.erase("end_time")
	ActivityManager.order_duel.active = false
	assert(screen._get_order_duel_points(order) == 0)
	ActivityManager.order_duel.active = true
	ActivityManager.order_duel.settings.order_points_ratio = INF
	assert(screen._get_order_duel_points(order) == 0)
	ActivityManager.order_duel.settings.order_points_ratio = 0.1
	var shown: Dictionary = screen._with_active_activity_rewards(order)
	assert(int(shown.rewards.order_duel_points) == 4)
	assert(not order.rewards.has("order_duel_points"), "Preview must not change the stored reward")
	CultivationService.current_level = 1
	shown = screen._with_active_activity_rewards({"rewards": {"order_duel_points": 999}})
	assert(not shown.rewards.has("order_duel_points"))
	CultivationService.current_level = 2
	screen.free()

	# Polling updates the existing card and labels, preserving material animation targets.
	GameState.main_grid_cache = []
	GridManager.init_grid()
	GameState.meridian_acupoints = [order]
	var live := preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(live)
	live._is_initial_game_load = false
	live._display_meridian()
	var entry: RequirementEntry
	for child: Node in live.requirement_list.container.get_children():
		if child is RequirementEntry:
			entry = child as RequirementEntry
	assert(entry != null)
	var label: Label = entry.get_node("RewardRow/RewardBox/OrderDuelPoints") as Label
	assert(label.text == "对战 +4")
	var material: Node = entry.get_node("ItemsContainer").get_child(0)
	ActivityManager.order_duel.my_points = 98
	ActivityManager.order_duel_updated.emit()
	assert(label.text == "对战 +2")
	assert(entry.get_node("ItemsContainer").get_child(0) == material)
	ActivityManager.order_duel.status = "lost"
	ActivityManager.order_duel_updated.emit()
	assert(not entry.has_node("RewardRow/RewardBox/OrderDuelPoints"))
	ActivityManager.order_duel.status = "playing"
	ActivityManager.order_duel.my_points = 0
	ActivityManager.order_duel_updated.emit()
	assert(entry.has_node("RewardRow/RewardBox/OrderDuelPoints"))
	assert(entry.get_node("ItemsContainer").get_child(0) == material)
	for frame: int in range(3):
		await get_tree().process_frame
	label = entry.get_node("RewardRow/RewardBox/OrderDuelPoints") as Label
	assert(label.get_global_rect().end.x <= entry.get_global_rect().end.x)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/order_duel_order_reward.png")
	entry.setup([], 0, true, {"order_duel_points": 4})
	assert(not entry.has_node("RewardRow/RewardBox/OrderDuelPoints"))
	live.queue_free()
	await get_tree().process_frame
	print("ORDER_DUEL_ORDER_REWARD_SMOKE_OK")
	get_tree().quit()
