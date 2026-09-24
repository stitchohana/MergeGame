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
var stamina_multiplier_max: int = 1
var stamina_multiplier_selected: int = 1
var stamina_multiplier_expires_at: int = 0
var stamina_multiplier_manual: bool = false

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
var battle_pass_progress: Dictionary = {}

# Auto-acupoint activation from RequirementList
var pending_auto_acupoint: bool = false
var pending_breakthrough_prompt: bool = false
var skip_next_home_loading: bool = false

signal meridian_updated()
signal pending_rewards_changed(count: int)

signal stamina_changed(current: int, max: int)
signal stamina_multiplier_changed(max_multiplier: int, selected_multiplier: int, expires_at: int)
signal spirit_stones_changed(amount: int)
signal battle_pass_changed(progress: Dictionary)


func sync_stamina_multiplier(data: Dictionary) -> void:
	if not data.has("stamina_multiplier_max"):
		return
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var was_active: bool = stamina_multiplier_max > 1 and stamina_multiplier_expires_at > now_ms
	var next_max: int = maxi(1, int(data.get("stamina_multiplier_max", 1)))
	var next_expires_at: int = int(data.get("stamina_multiplier_expires_at", 0))
	var is_active: bool = next_max > 1 and next_expires_at > now_ms
	stamina_multiplier_max = next_max if is_active else 1
	stamina_multiplier_expires_at = next_expires_at if is_active else 0
	if not is_active:
		stamina_multiplier_selected = 1
		stamina_multiplier_manual = false
	elif not was_active:
		stamina_multiplier_selected = stamina_multiplier_max
		stamina_multiplier_manual = false
	elif stamina_multiplier_selected > stamina_multiplier_max:
		stamina_multiplier_selected = stamina_multiplier_max
	elif not stamina_multiplier_manual and stamina_multiplier_selected < stamina_multiplier_max:
		stamina_multiplier_selected = stamina_multiplier_max
	stamina_multiplier_changed.emit(
		stamina_multiplier_max, stamina_multiplier_selected, stamina_multiplier_expires_at
	)


func select_stamina_multiplier(multiplier: int) -> void:
	if expire_stamina_multiplier_if_needed():
		return
	if multiplier < 1 or multiplier > stamina_multiplier_max or not _is_power_of_two(multiplier):
		return
	stamina_multiplier_selected = multiplier
	stamina_multiplier_manual = true
	stamina_multiplier_changed.emit(
		stamina_multiplier_max, stamina_multiplier_selected, stamina_multiplier_expires_at
	)


func expire_stamina_multiplier_if_needed() -> bool:
	if stamina_multiplier_max <= 1:
		return false
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	if stamina_multiplier_expires_at > now_ms:
		return false
	stamina_multiplier_max = 1
	stamina_multiplier_selected = 1
	stamina_multiplier_expires_at = 0
	stamina_multiplier_manual = false
	stamina_multiplier_changed.emit(1, 1, 0)
	return true


func get_stamina_multiplier_remaining_seconds() -> float:
	if expire_stamina_multiplier_if_needed():
		return 0.0
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	return maxf(0.0, float(stamina_multiplier_expires_at - now_ms) / 1000.0)


func _is_power_of_two(value: int) -> bool:
	return value >= 1 and (value & (value - 1)) == 0


func set_crafted_item_ids(ids: Array) -> void:
	crafted_item_ids.clear()
	for value: Variant in ids:
		var item_id: int = ConfigDatabase._coerce_int(value)
		if item_id > 0 and not ConfigDatabase.get_item_data(item_id).is_empty():
			crafted_item_ids[item_id] = true


func register_new_item_ids(ids: Array) -> void:
	var new_names: PackedStringArray = []
	for value: Variant in ids:
		var item_id: int = ConfigDatabase._coerce_int(value)
		if item_id <= 0 or crafted_item_ids.has(item_id):
			continue
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		if item_data.is_empty():
			continue
		crafted_item_ids[item_id] = true
		new_names.append(String(item_data.get("name", "#%d" % item_id)))
	if not new_names.is_empty():
		# Let the ordinary action result toast display first; otherwise it can
		# immediately replace the first-time discovery notification.
		EventBus.call_deferred("emit_signal", "show_toast", "解锁新物品：%s" % "、".join(new_names))


func has_crafted_item(item_id: int) -> bool:
	return item_id > 0 and crafted_item_ids.has(item_id)
