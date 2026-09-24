extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ActivityManager.defs = [
		{"id": 4, "name": "Disabled", "enabled": false, "active": false},
		{"id": 5, "name": "Enabled", "enabled": true, "active": true},
	]
	var active_activities: Array = ActivityManager.get_active_activities()
	assert(active_activities.size() == 1)
	assert(int(active_activities[0].get("id", 0)) == 5)
	print("activity_enabled_smoke: ok")
	quit()
