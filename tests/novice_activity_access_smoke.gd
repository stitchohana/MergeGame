extends Node


func _ready() -> void:
	CloudService.online = false
	call_deferred("_run")


func _run() -> void:
	CultivationService.current_level = 1
	var future_ms: int = int(Time.get_unix_time_from_system() * 1000.0) + 3600000
	GameState.sync_stamina_multiplier({"stamina_multiplier_max": 4, "stamina_multiplier_expires_at": future_ms})
	assert(GameState.stamina_multiplier_max == 1 and GameState.stamina_multiplier_selected == 1)
	assert(GameState.stamina_multiplier_expires_at == 0)
	# Even stale local data must be cleared before a launcher can use it.
	GameState.stamina_multiplier_max = 4
	GameState.stamina_multiplier_selected = 4
	GameState.stamina_multiplier_expires_at = future_ms
	GameState.select_stamina_multiplier(2)
	assert(GameState.stamina_multiplier_selected == 1)
	var activities: Array = [
		{"id": 3, "widget": "WeeklyActivity", "active": true},
		{"id": 4, "widget": "BattlePass", "active": true},
		{"id": 5, "widget": "CardCollection", "active": true},
		{"id": 6, "widget": "StairClimb", "active": false, "result_available": true},
		{"id": 7, "widget": "OrderSupply", "active": true, "config": {"target_count": 5}},
	]
	ActivityManager.reset_progress()
	ActivityManager.sync_state({"activity_defs": activities, "activity_progress": {"7": {"current_count": 5}}})
	GameState.activity_defs = activities
	assert(ActivityManager.get_active_activities().is_empty())
	QuestService._on_state_loaded({"quest_defs": [{"id": 1001, "target_count": 5}], "quest_progress": {"1001": {"current_count": 5, "completed": true}}})
	assert(QuestService.quest_defs.is_empty() and QuestService.progress.is_empty())
	var notices: Array = []
	QuestService.quest_completed.connect(func(id: int) -> void: notices.append(id))
	QuestService._apply_progress({"1001": {"current_count": 5, "completed": true}})
	assert(notices.is_empty())
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(screen)
	await get_tree().process_frame
	assert(not screen.battle_pass_entry.visible)
	assert(not screen.order_supply_entry.visible)
	var multiplier: StaminaMultiplierControl = screen.get_node("StaminaMultiplierControl") as StaminaMultiplierControl
	assert(not multiplier.visible)
	for entry: Node in screen.requirement_list.container.get_children():
		assert(not entry is WeeklyActivityEntry and not entry is HomeActivityCard)
	var home: HomeScreen = preload("res://scenes/screens/HomeScreen.tscn").instantiate() as HomeScreen
	add_child(home)
	assert(not home.activity_left.visible and not home.activity_right.visible)
	var order: Dictionary = {"total_value": 200, "rewards": {"tokens": [{"token": 2, "amount": 20}, {"token": 5, "amount": 20}], "items": [{"id": 1701, "count": 1}, {"id": 5001, "count": 1}], "stair_climb_points": 20}}
	var shown: Dictionary = screen._with_active_activity_rewards(order)
	assert(shown.rewards.tokens == [{"token": 2, "amount": 20}])
	assert(shown.rewards.items == [{"id": 5001, "count": 1}])
	assert(not shown.rewards.has("stair_climb_points"))
	assert(order.rewards.tokens.size() == 2, "display filtering must not alter stored order")
	var bar: PendingRewardBar = preload("res://scenes/ui/main/PendingRewardBar.tscn").instantiate() as PendingRewardBar
	add_child(bar)
	RewardManager.pending_rewards = [{"uid": 100, "id": 1701, "kind": "card_pack"}, {"uid": 101, "id": 5001}]
	assert(bar._available_rewards() == [{"uid": 101, "id": 5001}])
	# A fetched level change must reach listeners before their unlock checks.
	CloudService._dispatch_response("fetch_state", {"cultivation": {"current_level": 2, "current_qi": 0, "max_qi": 100}, "activity_defs": activities, "quest_defs": [{"id": 1001, "target_count": 5}], "quest_progress": {"1001": {"current_count": 0, "completed": false}}, "activity_progress": {"7": {"current_count": 0}}})
	assert(ActivityManager.is_unlocked())
	assert(GameState.stamina_multiplier_max == 1 and not multiplier.visible)
	GameState.sync_stamina_multiplier({"stamina_multiplier_max": 4, "stamina_multiplier_expires_at": future_ms})
	assert(multiplier.visible and GameState.stamina_multiplier_selected == 4)
	assert(ActivityManager.get_active_activities().size() == 5)
	assert(not QuestService.quest_defs.is_empty())
	screen._refresh_battle_pass_entry()
	screen.order_supply_entry._refresh()
	home._refresh_activity_lists()
	assert(screen.battle_pass_entry.visible and screen.order_supply_entry.visible)
	assert(home.activity_left.visible or home.activity_right.visible)
	shown = screen._with_active_activity_rewards({"total_value": 200, "rewards": {"tokens": [{"token": 2, "amount": 20}]}})
	assert((shown.rewards.tokens as Array).any(func(t: Dictionary) -> bool: return int(t.token) == 5))
	assert(shown.rewards.items == [{"id": 1702, "count": 1}])
	assert(bar._available_rewards().size() == 2)
	bar.queue_free()
	home.queue_free()
	screen.queue_free()
	print("NOVICE_ACTIVITY_ACCESS_UI_SMOKE_OK")
	get_tree().quit()
