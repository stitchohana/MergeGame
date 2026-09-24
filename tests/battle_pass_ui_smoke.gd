extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.activity_defs = [{
		"id": 4,
		"name": "首期战令",
		"active": true,
		"end_time": "2026-10-23T00:00:00Z",
	}]
	GameState.battle_pass_progress = {
		"4": {"points": 10, "premium_unlocked": false, "free_claimed_levels": [], "premium_claimed_levels": []},
	}
	var panel := preload("res://scenes/ui/activity/BattlePassPanel.tscn").instantiate() as BattlePassPanel
	root.add_child(panel)
	panel.setup(4)
	await process_frame
	assert(panel.title_label.text == "首期战令")
	assert(panel.tiers_box.get_child_count() == 50)
	assert(panel.points_label.text == "10 / 500 战令积分")
	assert(panel.unlock_button.visible)
	assert(panel.status_label.text.contains("截止"))
	var first_tier := panel.tiers_box.get_child(0) as HBoxContainer
	var claim_button := first_tier.get_child(1) as Button
	assert(not claim_button.disabled)
	GameState.battle_pass_progress["4"]["free_claimed_levels"] = [1.0]
	GameState.battle_pass_changed.emit(GameState.battle_pass_progress)
	assert(panel.tiers_box.get_child_count() == 50)
	first_tier = panel.tiers_box.get_child(0) as HBoxContainer
	var claimed_button := first_tier.get_child(1) as Button
	assert(claimed_button.disabled)
	assert(claimed_button.text.contains("已领取"))
	GameState.battle_pass_progress["4"]["premium_unlocked"] = true
	GameState.battle_pass_changed.emit(GameState.battle_pass_progress)
	first_tier = panel.tiers_box.get_child(0) as HBoxContainer
	var premium_button := first_tier.get_child(2) as Button
	assert(not premium_button.disabled)
	assert(premium_button.text.contains("领取"))
	GameState.battle_pass_progress["4"]["premium_claimed_levels"] = [1]
	GameState.battle_pass_changed.emit(GameState.battle_pass_progress)
	first_tier = panel.tiers_box.get_child(0) as HBoxContainer
	premium_button = first_tier.get_child(2) as Button
	assert(premium_button.disabled)
	assert(premium_button.text.contains("已领取"))
	panel.queue_free()
	print("battle_pass_ui_smoke: ok")
	quit()
