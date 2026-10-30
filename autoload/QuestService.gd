extends Node

# QuestService: Manages quest progress. Reward distribution handled by RewardManager.

signal quest_completed(quest_id: int)
signal quest_progress_updated(quest_id: int, current_count: int, target_count: int)
signal weekly_progress_changed

var quest_defs: Array = []
var progress: Dictionary = {}  # { quest_id: { current_count, completed, claimed } }
var weekly_defs: Array = []
var weekly_progress: Dictionary = {}
var weekly_claiming: bool = false
var _weekly_revision: int = -1

func is_unlocked() -> bool:
	return CultivationService.current_level >= 2


func _ready() -> void:
	_connect_signals()

func _connect_signals() -> void:
	CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.merge_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.MERGE))
	CloudService.spawn_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.SPAWN))
	CloudService.craft_retrieve_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.CRAFT))
	CloudService.sell_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.SELL))
	CloudService.meridian_complete_confirmed.connect(_on_meridian_complete_tick)
	CloudService.battle_attack_confirmed.connect(_on_battle_attack_tick)
	CloudService.breakthrough_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.BREAKTHROUGH))
	CloudService.exp_pill_consume_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.ANY_ITEM_CONSUME))
	CloudService.stamina_restore_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.ANY_ITEM_CONSUME))
	CloudService.quest_claim_confirmed.connect(_on_quest_claim_confirmed)
	CloudService.quest_claim_rejected.connect(_on_quest_claim_rejected)
	CloudService.weekly_claim_confirmed.connect(_on_weekly_claim_confirmed)
	CloudService.weekly_claim_rejected.connect(_on_weekly_claim_rejected)


func _on_state_loaded(state: Dictionary) -> void:
	if not is_unlocked():
		quest_defs = []
		progress.clear()
		return
	if state.has("quest_defs"):
		quest_defs = state.quest_defs
	if state.has("quest_progress"):
		_apply_progress(state.quest_progress)


func _on_progress_tick(_result: Dictionary, quest_type: int) -> void:
	if not is_unlocked():
		return
	if _result.has("quest_progress"):
		_apply_progress(_result.quest_progress)


func _on_battle_attack_tick(result: Dictionary) -> void:
	_on_progress_tick(result, Constants.QuestType.BATTLE_ATTACK)
	if result.get("stage_complete", false):
		_on_progress_tick(result, Constants.QuestType.BATTLE_CLEAR)


func _on_meridian_complete_tick(result: Dictionary) -> void:
	if result.get("circulation_completed", false):
		_on_progress_tick(result, Constants.QuestType.MERIDIAN_CIRCULATION)


func _apply_progress(server_progress: Dictionary) -> void:
	if not is_unlocked():
		return
	for key in server_progress:
		var pid: int = int(key)
		var p: Dictionary = server_progress[key]
		var old: Dictionary = progress.get(pid, {})
		if p.get("completed", false) and not old.get("completed", false):
			quest_completed.emit(pid)
		progress[pid] = p
		var target: int = _find_quest_target(pid)
		quest_progress_updated.emit(pid, p.get("current_count", 0), target)


var _claiming_quest_id: int = -1

func claim_quest(quest_id: int) -> void:
	if not is_unlocked():
		return
	if _claiming_quest_id > 0:
		return
	_claiming_quest_id = quest_id
	CloudService.submit_quest_claim(quest_id)


func get_progress(quest_id: int) -> Dictionary:
	var pid: int = int(quest_id)
	var result: Dictionary = progress.get(pid, {})
	return result


func is_quest_complete(quest_id: int) -> bool:
	return progress.get(int(quest_id), {}).get("completed", false)


func _find_quest_target(quest_id: int) -> int:
	for q in quest_defs:
		if q.id == quest_id:
			return q.target_count
	return 0


func _on_quest_claim_confirmed(result: Dictionary) -> void:
	_claiming_quest_id = -1
	if result.has("quest_progress"):
		_apply_progress(result.quest_progress)

func _on_quest_claim_rejected(reason: String) -> void:
	_claiming_quest_id = -1
	EventBus.show_toast.emit("领取失败")


func reset_weekly_progress() -> void:
	weekly_defs.clear()
	weekly_progress.clear()
	weekly_claiming = false
	_weekly_revision = -1
	weekly_progress_changed.emit()


func sync_weekly_state(data: Dictionary) -> void:
	if not data.has("weekly_task_progress") and not data.has("weekly_task_defs"):
		return
	var revision: int = int(data.get("storage_revision", -1))
	if revision < _weekly_revision:
		return
	_weekly_revision = revision
	if data.has("weekly_task_defs"):
		weekly_defs = data.get("weekly_task_defs", []).duplicate(true)
	if data.has("weekly_task_progress"):
		weekly_progress = data.get("weekly_task_progress", {}).duplicate(true)
	weekly_progress_changed.emit()


func get_weekly_progress(activity_id: int) -> Dictionary:
	return weekly_progress.get(str(activity_id), weekly_progress.get(activity_id, {}))


func get_weekly_definition(activity_id: int) -> Dictionary:
	for definition: Dictionary in weekly_defs:
		if int(definition.get("activity_id", 0)) == activity_id:
			return definition
	return {}


func is_weekly_stage_claimed(activity_id: int, stage: int) -> bool:
	var current: Dictionary = get_weekly_progress(activity_id)
	# JSON numbers are floats; Array.has() compares their Variant types too.
	for claimed_stage: Variant in current.get("claimed_stages", []):
		if int(claimed_stage) == stage:
			return true
	return false


func claim_weekly_stage(activity_id: int, stage: int) -> void:
	if not is_unlocked() or weekly_claiming:
		return
	if is_weekly_stage_claimed(activity_id, stage):
		return
	var current: Dictionary = get_weekly_progress(activity_id)
	if current.is_empty():
		CloudService.fetch_state()
		return
	weekly_claiming = true
	weekly_progress_changed.emit()
	CloudService.submit_weekly_claim(activity_id, stage, str(current.get("period_key", "")))


func _on_weekly_claim_confirmed(_result: Dictionary) -> void:
	weekly_claiming = false
	weekly_progress_changed.emit()
	EventBus.show_toast.emit("周常阶段奖励已领取")


func _on_weekly_claim_rejected(reason: String) -> void:
	weekly_claiming = false
	weekly_progress_changed.emit()
	var messages: Dictionary = {"insufficient_points": "积分不足", "already_claimed": "本阶段奖励已领取",
		"state_conflict": "周常已刷新，请重新领取", "activity_locked": "活动尚未解锁", "activity_inactive": "活动未开放"}
	EventBus.show_toast.emit(str(messages.get(reason, "领取失败，请重试")))
	if reason in ["state_conflict", "already_claimed", "insufficient_points"]:
		CloudService.fetch_state()
