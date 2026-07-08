extends Node

# RewardManager: Receives reward notifications from explicit reward flows.
# Operations only carry quest_progress; rewards come from claim/meridian/state.

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
	if not CloudService.battle_attack_confirmed.is_connected(_on_reward_response):
		CloudService.battle_attack_confirmed.connect(_on_reward_response)
	if not CloudService.pending_reward_claimed.is_connected(_on_reward_response):
		CloudService.pending_reward_claimed.connect(_on_reward_response)


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("pending_rewards"):
		pending_rewards = state.pending_rewards
		pending_rewards_changed.emit(pending_rewards.size())


func _on_reward_response(result: Dictionary) -> void:
	if result.has("rewards_applied") and result.rewards_applied != null:
		_apply(result.rewards_applied)
	if result.has("pending_rewards"):
		pending_rewards = result.pending_rewards
		pending_rewards_changed.emit(pending_rewards.size())


func apply_rewards(config: Dictionary) -> void:
	_apply(config)


func _apply(config: Dictionary) -> void:
	if config.has("tokens"):
		for t in config.tokens:
			var token_type: int = int(t.get("token", 0))
			var amount: int = int(t.get("amount", 0))
			match token_type:
				Constants.TokenType.SPIRIT_STONES:
					GameState.spirit_stones += amount
					GameState.spirit_stones_changed.emit(GameState.spirit_stones)
				Constants.TokenType.QI:
					var new_qi: int = mini(CultivationService.current_qi + amount, CultivationService.max_qi)
					CultivationService.current_qi = new_qi
					CultivationService.qi_changed.emit(new_qi, CultivationService.max_qi)
				Constants.TokenType.STAMINA:
					GameState.stamina += amount
					GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
				Constants.TokenType.EXP:
					CultivationService.current_exp += amount
					CultivationService.exp_changed.emit(CultivationService.current_exp, CultivationService.get_exp_to_next_level())

	if config.has("items"):
		for ri in config.items:
			var item_id: int = ri.get("id", 0)
			var count: int = ri.get("count", 0)
			var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
			var item_name: String = item_data.get("name", "#" + str(item_id))
			for _i in range(count):
				pending_rewards.append({"id": item_id, "name": item_name, "uid": -1})
		pending_rewards_changed.emit(pending_rewards.size())


func claim_pending_reward(uid: int) -> void:
	CloudService.submit_claim_pending_reward(uid)


func has_pending_rewards() -> bool:
	return not pending_rewards.is_empty()
