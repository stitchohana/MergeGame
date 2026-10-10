extends Node

# ActivityManager: Manages activity state and progress.

signal activity_updated(activity_id: int)

var defs: Array = []
var progress: Dictionary = {}
var _progress_revision: int = -1
var stair_climb: Dictionary = {}
var stair_climb_received_ticks: int = 0
var _shown_card_set_rewards: Dictionary = {}
signal stair_climb_updated()


func _ready() -> void:
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.card_collection_confirmed.connect(_on_card_collection_confirmed)


func _on_state_loaded(state: Dictionary) -> void:
	sync_state(state)


func reset_progress() -> void:
	_progress_revision = -1
	defs.clear()
	progress.clear()
	_shown_card_set_rewards.clear()


func _on_card_collection_confirmed(data: Dictionary) -> void:
	var completed_sets: Array = data.get("completed_sets", [])
	var rewards: Dictionary = data.get("rewards", {})
	if not data.has("cards") or completed_sets.is_empty() or rewards.is_empty():
		return
	var names: PackedStringArray = []
	var has_new_reward: bool = false
	for completed: Dictionary in completed_sets:
		var collection_id: int = int(completed.get("collection_id", 0))
		var set_id: int = int(completed.get("set_id", 0))
		var key: String = "%d:%d" % [collection_id, set_id]
		has_new_reward = has_new_reward or not _shown_card_set_rewards.has(key)
		_shown_card_set_rewards[key] = true
		var set_name: String = "卡组 %d" % set_id
		for card_set: Dictionary in ConfigDatabase.card_collection.get("card_sets", []):
			if int(card_set.collection_id) == collection_id and int(card_set.set_id) == set_id:
				set_name = str(card_set.name)
				break
		names.append(set_name)
	if has_new_reward:
		# Show above the opening result after all response listeners finish refreshing.
		_show_card_set_reward_popup.call_deferred("、".join(names), rewards.duplicate(true))


func _show_card_set_reward_popup(set_names: String, rewards: Dictionary) -> void:
	var popup: RewardReceivedPopup = preload("res://scenes/ui/home/RewardReceivedPopup.tscn").instantiate() as RewardReceivedPopup
	UIManager.show_popup(popup)
	popup.setup("卡组集齐奖励", "恭喜集齐「%s」！\n奖励已自动到账" % set_names, rewards)


func sync_state(state: Dictionary) -> void:
	var revision: int = int(state.get("storage_revision", -1))
	if revision < _progress_revision:
		return
	if state.has("activity_defs"):
		defs = state.activity_defs
	if state.has("activity_progress"):
		_progress_revision = revision
		progress = state.activity_progress.duplicate(true)
		GameState.activity_progress = progress
	for activity: Dictionary in defs:
		activity_updated.emit(int(activity.get("id", 0)))


func get_progress(activity_id: int) -> Dictionary:
	return progress.get(str(activity_id), progress.get(activity_id, {}))


func is_completed(activity_id: int) -> bool:
	return bool(get_progress(activity_id).get("completed", false))


func is_claimed(activity_id: int) -> bool:
	return bool(get_progress(activity_id).get("claimed", false))


func get_active_activities() -> Array:
	var result: Array = []
	for act in defs:
		if act.get("active", false) or (act.get("widget", "") == "StairClimb" and act.get("result_available", false)):
			result.append(act)
	return result
