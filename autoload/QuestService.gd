extends Node

# QuestService: Manages quest progress. Reward distribution handled by RewardManager.

signal quest_completed(quest_id: int)
signal quest_progress_updated(quest_id: int, current_count: int, target_count: int)

var quest_defs: Array = []
var progress: Dictionary = {}  # { quest_id: { current_count, completed, claimed } }


func _ready() -> void:
	_connect_signals()

func _connect_signals() -> void:
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)
	if not CloudService.merge_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.MERGE)):
		CloudService.merge_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.MERGE))
	if not CloudService.spawn_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.SPAWN)):
		CloudService.spawn_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.SPAWN))
	if not CloudService.craft_retrieve_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.CRAFT)):
		CloudService.craft_retrieve_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.CRAFT))
	if not CloudService.sell_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.SELL)):
		CloudService.sell_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.SELL))
	if not CloudService.meridian_complete_confirmed.is_connected(_on_meridian_complete_tick):
		CloudService.meridian_complete_confirmed.connect(_on_meridian_complete_tick)
	if not CloudService.battle_attack_confirmed.is_connected(_on_battle_attack_tick):
		CloudService.battle_attack_confirmed.connect(_on_battle_attack_tick)
	if not CloudService.breakthrough_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.BREAKTHROUGH)):
		CloudService.breakthrough_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.BREAKTHROUGH))
	# Both exp pill and stamina pill consumption count as "any item consume" quest progress
	if not CloudService.exp_pill_consume_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.ANY_ITEM_CONSUME)):
		CloudService.exp_pill_consume_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.ANY_ITEM_CONSUME))
	if not CloudService.stamina_restore_confirmed.is_connected(_on_progress_tick.bind(Constants.QuestType.ANY_ITEM_CONSUME)):
		CloudService.stamina_restore_confirmed.connect(_on_progress_tick.bind(Constants.QuestType.ANY_ITEM_CONSUME))
	if not CloudService.quest_claim_confirmed.is_connected(_on_quest_claim_confirmed):
		CloudService.quest_claim_confirmed.connect(_on_quest_claim_confirmed)
	if not CloudService.quest_claim_rejected.is_connected(_on_quest_claim_rejected):
		CloudService.quest_claim_rejected.connect(_on_quest_claim_rejected)


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("quest_defs"):
		quest_defs = state.quest_defs
	if state.has("quest_progress"):
		_apply_progress(state.quest_progress)


func _on_progress_tick(_result: Dictionary, quest_type: int) -> void:
	if _result.has("quest_progress"):
		_apply_progress(_result.quest_progress)
	else:
		# Optimistic local increment (fallback)
		for q in quest_defs:
			if q.type != quest_type:
				continue
			var pid: int = int(q.id)
			if not progress.has(pid):
				continue
			var p: Dictionary = progress[pid]
			if p.get("completed", false) or p.get("claimed", false):
				continue
			p["current_count"] = mini(p.get("current_count", 0) + 1, q.target_count)
			quest_progress_updated.emit(pid, p.current_count, q.target_count)
			if p.current_count >= q.target_count and not p.get("completed", false):
				p["completed"] = true
				quest_completed.emit(pid)


func _on_battle_attack_tick(result: Dictionary) -> void:
	_on_progress_tick(result, Constants.QuestType.BATTLE_ATTACK)
	if result.get("stage_complete", false):
		_on_progress_tick(result, Constants.QuestType.BATTLE_CLEAR)


func _on_meridian_complete_tick(result: Dictionary) -> void:
	if result.get("circulation_completed", false):
		_on_progress_tick(result, Constants.QuestType.MERIDIAN_CIRCULATION)


func _apply_progress(server_progress: Dictionary) -> void:
	for key in server_progress:
		var pid: int = int(key)
		var p: Dictionary = server_progress[key]
		var old: Dictionary = progress.get(pid, {})
		if p.get("completed", false) and not old.get("completed", false):
			quest_completed.emit(pid)
		if p.get("claimed", false) and not old.get("claimed", false):
			var rewards = _find_quest_rewards(pid)
			if not rewards.is_empty():
				RewardManager.apply_rewards(rewards)
		progress[pid] = p
		var target: int = _find_quest_target(pid)
		quest_progress_updated.emit(pid, p.get("current_count", 0), target)


func claim_quest(quest_id: int) -> void:
	CloudService.submit_quest_claim(quest_id)


func get_progress(quest_id: int) -> Dictionary:
	var pid: int = int(quest_id)
	var result: Dictionary = progress.get(pid, {})
	return result


func is_quest_complete(quest_id: int) -> bool:
	return progress.get(int(quest_id), {}).get("completed", false)


func _find_quest_rewards(quest_id: int) -> Dictionary:
	for q in quest_defs:
		if q.id == quest_id:
			if q.rewards is Dictionary:
				return q.rewards
			return {}
	return {}


func _find_quest_target(quest_id: int) -> int:
	for q in quest_defs:
		if q.id == quest_id:
			return q.target_count
	return 0






func _on_quest_claim_confirmed(result: Dictionary) -> void:
	if result.has("quest_progress"):
		_apply_progress(result.quest_progress)

func _on_quest_claim_rejected(reason: String) -> void:
	EventBus.show_toast.emit("领取失败")
