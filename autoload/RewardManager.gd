extends Node

# RewardManager: Receives reward notifications from explicit reward flows.
# Items are synced exclusively via pending_rewards from server responses.
# Tokens (spirit_stones, stamina, qi, cultivation) are synced from response fields.

signal pending_rewards_changed(count: int)

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
	if not CloudService.breakthrough_confirmed.is_connected(_on_reward_response):
		CloudService.breakthrough_confirmed.connect(_on_reward_response)
	if not CloudService.battle_attack_confirmed.is_connected(_on_reward_response):
		CloudService.battle_attack_confirmed.connect(_on_reward_response)
	if not CloudService.pending_reward_claimed.is_connected(_on_reward_response):
		CloudService.pending_reward_claimed.connect(_on_reward_response)


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("pending_rewards"):
		pending_rewards = state.pending_rewards
		pending_rewards_changed.emit(pending_rewards.size())


func _on_reward_response(result: Dictionary) -> void:
	if result.has("cultivation"):
		CultivationService.deserialize(result.cultivation)
	if result.has("spirit_stones"):
		GameState.spirit_stones = result.spirit_stones
		GameState.spirit_stones_changed.emit(GameState.spirit_stones)
	if result.has("stamina"):
		GameState.stamina = result.stamina
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	if result.has("pending_rewards"):
		pending_rewards = result.pending_rewards
		pending_rewards_changed.emit(pending_rewards.size())


func claim_pending_reward(uid: int) -> void:
	CloudService.submit_claim_pending_reward(uid)


func has_pending_rewards() -> bool:
	return not pending_rewards.is_empty()
