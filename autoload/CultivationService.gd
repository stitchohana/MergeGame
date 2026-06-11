extends Node

# CultivationService: Manages cultivation state, passive EXP gain, buffs, and breakthroughs.

signal exp_changed(current_exp: int, exp_to_next: int)
signal realm_changed(realm_id: int, realm_name: String, level: int)
signal qi_changed(current_qi: int, max_qi: int)
signal level_up(realm_id: int, realm_name: String, level: int)
signal breakthrough(realm_id: int, realm_name: String)
signal breakthrough_pill_needed(pill_id: int)
signal buff_changed(buffs: Array)  # Array of {name, remaining, duration, multiplier}

var current_realm_id: int = 0
var current_level: int = 1
var current_exp: int = 0
var total_exp: int = 0
var current_qi: int = 100
var max_qi: int = 100

var _passive_timer: Timer = null
var _paused: bool = false

# Buff system
var _active_buffs: Array = []  # [{pill_id, name, remaining, duration, multiplier}]

# --- Lifecycle ---

func _ready() -> void:
	max_qi = ConfigDatabase.get_initial_qi()
	current_qi = max_qi
	GameState.phase_changed.connect(_on_game_phase_changed)
	_setup_timer()
	_emit_state_signals()

func _exit_tree() -> void:
	if _passive_timer:
		_passive_timer.stop()

func _setup_timer() -> void:
	_passive_timer = Timer.new()
	_passive_timer.name = "CultivationPassiveTimer"
	_passive_timer.wait_time = 1.0
	_passive_timer.one_shot = false
	_passive_timer.timeout.connect(_on_passive_tick)
	add_child(_passive_timer)
	_passive_timer.start()

func _on_passive_tick() -> void:
	if _paused:
		return
	# Tick buffs
	_tick_buffs()
	# Grant EXP with current multiplier
	var base_exp: int = ConfigDatabase.get_passive_exp_per_second()
	var total_exp_this_tick: int = int(ceil(base_exp * get_exp_multiplier()))
	add_exp(total_exp_this_tick)

func _tick_buffs() -> void:
	var changed := false
	var i := 0
	while i < _active_buffs.size():
		_active_buffs[i].remaining -= 1
		if _active_buffs[i].remaining <= 0:
			_active_buffs.remove_at(i)
			changed = true
		else:
			i += 1
	if changed or _active_buffs.is_empty():
		buff_changed.emit(_active_buffs.duplicate())

func _on_game_phase_changed(old: int, new: int) -> void:
	_paused = (new == GameState.GamePhase.PAUSED or new == GameState.GamePhase.GAME_OVER)

# --- Buff API ---

func apply_buff(pill_data: Dictionary) -> void:
	var duration: int = pill_data.get("buff_duration", 0)
	var multiplier: float = pill_data.get("buff_multiplier", 1.0)
	if duration <= 0:
		return
	# Add instant EXP
	var exp_gain: int = pill_data.get("exp_gain", 0)
	if exp_gain > 0:
		add_exp(exp_gain)
	# Apply or stack buff
	var pill_id: int = pill_data.get("id", 0)
	var pill_name: String = pill_data.get("name", "丹药")
	var new_buff := {
		"pill_id": pill_id,
		"name": pill_name,
		"duration": duration,
		"remaining": duration,
		"multiplier": multiplier,
	}
	_active_buffs.append(new_buff)
	buff_changed.emit(_active_buffs.duplicate())

func get_exp_multiplier() -> float:
	var mult: float = 1.0
	for buff in _active_buffs:
		mult = maxf(mult, buff.multiplier)
	return mult

func get_active_buffs() -> Array:
	return _active_buffs.duplicate()

# --- Core API ---

func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	if is_max_cultivation():
		return
	# Block EXP gain at max level if breakthrough pill is required
	if _needs_breakthrough_pill():
		return

	current_exp += amount
	total_exp += amount

	var did_level_up := false
	var did_breakthrough := false

	while current_exp >= get_exp_to_next_level() and not is_max_cultivation():
		current_exp -= get_exp_to_next_level()
		current_level += 1

		if current_level > get_max_level_for_realm(current_realm_id):
			current_level = 1
			current_realm_id += 1
			max_qi += ConfigDatabase.get_qi_breakthrough_bonus()
			current_qi = mini(current_qi + ConfigDatabase.get_qi_recovery_per_level(), max_qi)
			did_breakthrough = true
		else:
			current_qi = mini(current_qi + ConfigDatabase.get_qi_recovery_per_level(), max_qi)
			did_level_up = true

		_recalc_exp_to_next()

	_emit_state_signals(did_level_up, did_breakthrough)

func try_breakthrough(pill_id: int) -> bool:
	if is_max_cultivation():
		return false
	if not is_breakthrough_ready():
		return false
	var required: int = get_required_breakthrough_pill()
	if required <= 0 or pill_id != required:
		return false

	current_exp = 0
	current_level = 1
	current_realm_id += 1
	max_qi += ConfigDatabase.get_qi_breakthrough_bonus()
	current_qi = mini(current_qi + ConfigDatabase.get_qi_recovery_per_level(), max_qi)
	_recalc_exp_to_next()

	var realm_name: String = get_realm_name()
	breakthrough.emit(current_realm_id, realm_name)
	_emit_state_signals()
	return true

# --- Queries ---

func get_realm_config() -> Dictionary:
	return ConfigDatabase.get_realm_config(current_realm_id)

func get_realm_name() -> String:
	return get_realm_config().get("name", "未知")

func get_formatted_realm_level() -> String:
	var name: String = get_realm_name()
	var max_lv: int = get_max_level_for_realm(current_realm_id)
	if max_lv <= 1:
		return name
	return "%s%s%s" % [name, get_realm_level_name(current_level), ""]

func get_realm_level_name(level: int) -> String:
	match level:
		1: return "一"
		2: return "二"
		3: return "三"
		4: return "四"
		5: return "五"
		6: return "六"
		7: return "七"
		8: return "八"
		9: return "九"
	return str(level)

func get_exp_to_next_level() -> int:
	var realm := get_realm_config()
	if realm.is_empty():
		return 999999
	var base: int = realm.get("base_exp", 100)
	var growth: float = realm.get("growth", 1.15)
	if growth <= 1.0:
		return base
	var level: int = mini(current_level + 1, realm.get("levels", 9))
	return int(base * pow(growth, level - 1))

var _exp_to_next_cached: int = 0

func _recalc_exp_to_next() -> void:
	_exp_to_next_cached = get_exp_to_next_level()

func is_max_cultivation() -> bool:
	return current_realm_id >= ConfigDatabase.get_cultivation_config().get("realms", []).size() - 1 and current_level >= get_max_level_for_realm(current_realm_id)

func get_max_level_for_realm(realm_id: int) -> int:
	var realm := ConfigDatabase.get_realm_config(realm_id)
	return realm.get("levels", 1)

func is_breakthrough_ready() -> bool:
	if is_max_cultivation():
		return false
	var realm := get_realm_config()
	if realm.is_empty():
		return false
	var max_lv: int = realm.get("levels", 1)
	return current_level >= max_lv and current_exp >= get_exp_to_next_level()

func get_required_breakthrough_pill() -> int:
	if not is_breakthrough_ready():
		return 0
	var realm := get_realm_config()
	return realm.get("breakthrough_pill", 0)

func _needs_breakthrough_pill() -> bool:
	if is_max_cultivation():
		return false
	var max_lv: int = get_max_level_for_realm(current_realm_id)
	if current_level < max_lv:
		return false
	var realm := get_realm_config()
	var pill_id: int = realm.get("breakthrough_pill", 0)
	return pill_id > 0

# --- Signals ---

func _emit_state_signals(level_up_occurred: bool = false, breakthrough_occurred: bool = false) -> void:
	var exp_to_next := get_exp_to_next_level()
	exp_changed.emit(current_exp, exp_to_next)
	var name: String = get_realm_name()
	realm_changed.emit(current_realm_id, name, current_level)
	qi_changed.emit(current_qi, max_qi)

	if level_up_occurred:
		level_up.emit(current_realm_id, name, current_level)
	if breakthrough_occurred:
		breakthrough.emit(current_realm_id, name)

	if _needs_breakthrough_pill():
		var realm := get_realm_config()
		var pill_id: int = realm.get("breakthrough_pill", 0)
		if pill_id > 0:
			breakthrough_pill_needed.emit(pill_id)

# --- Save / Load ---

func serialize() -> Dictionary:
	return {
		"current_realm_id": current_realm_id,
		"current_level": current_level,
		"current_exp": current_exp,
		"total_exp": total_exp,
		"current_qi": current_qi,
		"max_qi": max_qi,
		"buffs": _active_buffs.duplicate(),
	}

func deserialize(data: Dictionary) -> void:
	current_realm_id = data.get("current_realm_id", 0)
	current_level = data.get("current_level", 1)
	current_exp = data.get("current_exp", 0)
	total_exp = data.get("total_exp", 0)
	current_qi = data.get("current_qi", ConfigDatabase.get_initial_qi())
	max_qi = data.get("max_qi", ConfigDatabase.get_initial_qi())
	_active_buffs = data.get("buffs", [])
	_paused = false
	_recalc_exp_to_next()
	_emit_state_signals()
	buff_changed.emit(_active_buffs.duplicate())

func reset() -> void:
	current_realm_id = 0
	current_level = 1
	current_exp = 0
	total_exp = 0
	max_qi = ConfigDatabase.get_initial_qi()
	current_qi = max_qi
	_active_buffs = []
	_paused = false
	_recalc_exp_to_next()
	_emit_state_signals()
	buff_changed.emit([])
