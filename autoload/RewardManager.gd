extends Node

# RewardManager: Receives reward notifications from explicit reward flows.
# Items are synced exclusively via pending_rewards from server responses.
# Tokens (spirit_stones, stamina, qi, cultivation) are synced from response fields.

signal pending_rewards_changed(count: int)

var _pending_revision: int = -1
var pending_rewards: Array = []  # [{id, name, uid}]


func _ready() -> void:
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)
	if not CloudService.meridian_complete_confirmed.is_connected(_on_reward_response):
		CloudService.meridian_complete_confirmed.connect(_on_reward_response)
	if not CloudService.quest_claim_confirmed.is_connected(_on_reward_response):
		CloudService.quest_claim_confirmed.connect(_on_reward_response)
	if not CloudService.home_meridian_light_confirmed.is_connected(_on_reward_response):
		CloudService.home_meridian_light_confirmed.connect(_on_reward_response)
	if not CloudService.home_meridian_run_confirmed.is_connected(_on_reward_response):
		CloudService.home_meridian_run_confirmed.connect(_on_reward_response)
	if not CloudService.breakthrough_confirmed.is_connected(_on_breakthrough_reward_response):
		CloudService.breakthrough_confirmed.connect(_on_breakthrough_reward_response)
	if not CloudService.battle_attack_confirmed.is_connected(_on_reward_response):
		CloudService.battle_attack_confirmed.connect(_on_reward_response)
	if not CloudService.pending_reward_claimed.is_connected(_on_reward_response):
		CloudService.pending_reward_claimed.connect(_on_reward_response)


func reset_pending() -> void:
	_pending_revision = -1
	pending_rewards.clear()
	pending_rewards_changed.emit(0)


func sync_pending(data: Dictionary, notify: bool = false) -> void:
	if not data.has("pending_rewards"):
		return
	var revision: int = int(data.get("storage_revision", -1))
	if revision < _pending_revision:
		return
	var old_uids: Array = pending_rewards.map(func(reward: Dictionary) -> int: return int(reward.get("uid", 0)))
	var gained_pack: bool = false
	for reward: Dictionary in data.get("pending_rewards", []):
		if str(reward.get("kind", "")) == "card_pack" and int(reward.get("uid", 0)) not in old_uids:
			gained_pack = true
	_pending_revision = revision
	pending_rewards = data.get("pending_rewards", []).duplicate(true)
	pending_rewards_changed.emit(pending_rewards.size())
	if notify and gained_pack:
		EventBus.show_toast.emit("获得卡包，已放入物品暂存区")


func _on_state_loaded(state: Dictionary) -> void:
	sync_pending(state)


func _on_reward_response(result: Dictionary) -> void:
	GameState.sync_stamina_multiplier(result)
	if result.has("cultivation"):
		CultivationService.deserialize(result.cultivation)
	if result.has("spirit_stones"):
		GameState.spirit_stones = result.spirit_stones
		GameState.spirit_stones_changed.emit(GameState.spirit_stones)
	if result.has("stamina"):
		GameState.stamina = result.stamina
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	sync_pending(result)


func _on_breakthrough_reward_response(result: Dictionary) -> void:
	_on_reward_response(result)
	var rewards_variant: Variant = result.get("rewards", {})
	var rewards: Dictionary = {}
	if rewards_variant is Dictionary:
		rewards = rewards_variant as Dictionary
	var popup := preload("res://scenes/ui/home/RewardReceivedPopup.tscn").instantiate() as RewardReceivedPopup
	if popup == null:
		return
	UIManager.show_popup(popup)
	popup.setup("收到奖励", "突破成功，境界提升并获得突破奖励", rewards)


func claim_pending_reward(uid: int) -> void:
	CloudService.submit_claim_pending_reward(uid)


func has_pending_rewards() -> bool:
	return not pending_rewards.is_empty()
