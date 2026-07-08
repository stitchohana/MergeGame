extends Node

# ActivityManager: Manages activity state and progress.

signal activity_updated(activity_id: int)

var defs: Array = []
var progress: Dictionary = {}


func _ready() -> void:
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("activity_defs"):
		defs = state.activity_defs
	if state.has("activity_progress"):
		progress = state.activity_progress


func get_progress(activity_id: int) -> Dictionary:
	return progress.get(activity_id, {})


func is_completed(activity_id: int) -> bool:
	return progress.get(activity_id, {}).get("completed", false)


func is_claimed(activity_id: int) -> bool:
	return progress.get(activity_id, {}).get("claimed", false)


func get_active_activities() -> Array:
	var result: Array = []
	for act in defs:
		if act.get("active", false):
			result.append(act)
	return result
