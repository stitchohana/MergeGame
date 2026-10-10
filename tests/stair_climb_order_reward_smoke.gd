extends Node


func _ready() -> void:
	var screen := preload("res://scenes/screens/GameScreen.gd").new() as GameScreen
	var activity: Dictionary = {"widget": "StairClimb", "active": true, "enabled": true,
		"start_time": "2020-01-01T00:00:00Z", "end_time": "2099-01-01T00:00:00Z",
		"config": {"order_points_ratio": 0.1}}
	GameState.activity_defs = [activity]
	var order: Dictionary = {"item_ids": [1006, 1006], "total_value": 999999,
		"rewards": {"tokens": [{"token": 4, "amount": 232}]}}
	var value: float = float(ConfigDatabase.get_item_data(1006).get("value", 0)) * 2
	var expected: int = maxi(1, floori(value * 0.1 + 0.000000001))
	var display: Dictionary = screen._with_active_activity_rewards(order)
	assert(int(display.rewards.stair_climb_points) == expected)
	assert(not order.rewards.has("stair_climb_points"))
	assert(screen._get_order_stair_climb_points({"item_id": 1006, "count": 2}) == expected)
	activity.config.order_points_ratio = 0.25
	assert(screen._get_order_stair_climb_points(order) == floori(value * 0.25))
	activity.config.order_points_ratio = 0.1
	assert(screen._get_order_stair_climb_points({"item_ids": [99999999]}) == 0)
	assert(screen._get_order_stair_climb_points({"item_ids": [1006], "breakthrough_order": true}) == 0)
	assert(screen._get_order_stair_climb_points({"item_ids": [1006], "completed": true}) == 0)
	activity.active = false
	assert(screen._get_order_stair_climb_points(order) == 0)
	activity.active = true
	activity.end_time = "2020-01-02T00:00:00Z"
	assert(screen._get_order_stair_climb_points(order) == 0)
	var entry := preload("res://scenes/ui/meridian/RequirementEntry.tscn").instantiate() as RequirementEntry
	add_child(entry)
	entry.setup([{"item_id": 1006}], 0, false, display.rewards)
	var label := entry.get_node("RewardRow/RewardBox/StairClimbPoints") as Label
	assert(label.text == "天梯 +%d" % expected)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(label.size.x > 0)
	assert(label.get_global_rect().end.x <= entry.get_global_rect().end.x)
	entry.setup([{"item_id": 1006}], 0, false, {})
	assert(not entry.has_node("RewardRow/RewardBox/StairClimbPoints"))
	entry.queue_free()
	screen.free()
	await get_tree().process_frame
	print("STAIR_CLIMB_ORDER_REWARD_SMOKE_OK")
	get_tree().quit()
