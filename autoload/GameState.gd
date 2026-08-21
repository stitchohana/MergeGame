extends Node

# GameState: Manages player state.

var stamina: int = 100
var max_stamina: int = 100
var spirit_stones: int = 0
var regen_remaining_ms: float = 0.0
var current_board_type: int = Constants.BoardType.MAIN
var battle_player_hp: int = 100
var battle_player_max_hp: int = 100
var previous_screen_name: String = ""
var spawn_seed: int = 0
var spawn_sequence: int = 0
var crafted_item_ids: Dictionary = {}

# Meridian cultivation
var meridian_circulations: int = 0
var meridian_acupoints: Array = []  # [{item_id, name, count, completed}]
var meridian_threshold_idx: int = 0

# Grid caching for screen switching
var main_grid_cache: Array = []
var battle_grid_cache: Array = []
var home_meridian_defs: Array = []
var home_meridian_progress: Array = []

# Activity system
var activity_defs: Array = []
var activity_progress: Dictionary = {}
var activity_current_day: int = 0

# Auto-acupoint activation from RequirementList
var pending_auto_acupoint: bool = false
var skip_next_home_loading: bool = false

signal meridian_updated()
signal pending_rewards_changed(count: int)

signal stamina_changed(current: int, max: int)
signal spirit_stones_changed(amount: int)


func set_crafted_item_ids(ids: Array) -> void:
	crafted_item_ids.clear()
	for value: Variant in ids:
		var item_id: int = int(value)
		if item_id > 0:
			crafted_item_ids[item_id] = true


func has_crafted_item(item_id: int) -> bool:
	return item_id > 0 and crafted_item_ids.has(item_id)
