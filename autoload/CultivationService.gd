extends Node

# CultivationService: Client-side display layer for cultivation.
# All logic (EXP, buffs, breakthrough) runs on the server.
# Client submits operations and displays results from server responses.

signal exp_changed(current_exp: int, exp_to_next: int)
signal realm_changed(realm_id: int, realm_name: String, level: int)
signal qi_changed(current_qi: int, max_qi: int)
signal level_up(realm_id: int, realm_name: String, level: int)
signal breakthrough(realm_id: int, realm_name: String)
signal breakthrough_pill_needed(pill_id: int)
signal buff_changed(buffs: Array)

var current_realm_id: int = 0
var current_level: int = 1
var current_exp: int = 0
var total_exp: int = 0
var current_qi: int = 100
var max_qi: int = 100

var _active_buffs: Array = []
var _tick_timer: Timer = null
var _paused: bool = false

func _ready() -> void:
	max_qi = ConfigDatabase.get_initial_qi()
	current_qi = max_qi
	GameState.phase_changed.connect(_on_game_phase_changed)
	_setup_timer()
	# Connect server signals
	CloudService.cultivate_tick_confirmed.connect(_on_tick_confirmed)
	CloudService.pill_consume_confirmed.connect(_on_consume_confirmed)
	CloudService.breakthrough_confirmed.connect(_on_breakthrough_confirmed)
	CloudService.cultivate_tick_rejected.connect(_on_tick_rejected)
	print("[Cultivation] Client layer ready, server-authoritative")

func _setup_timer() -> void:
	_tick_timer = Timer.new()
	_tick_timer.name = "CultivationTickTimer"
	_tick_timer.wait_time = _load_tick_interval()
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_tick_timer)
	add_child(_tick_timer)
	_tick_timer.start()
	print("[Cultivation] Tick interval: ", _tick_timer.wait_time, "s")

func _load_tick_interval() -> float:
	var file := FileAccess.open("res://config/server.json", FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(text) == OK:
			var data: Dictionary = json.data
			return float(data.get("cultivation_tick_interval", 10))
	return 10.0

func _on_tick_timer() -> void:
	if _paused:
		print("[Cultivation] Tick skipped: paused")
		return
	if not CloudService.online:
		print("[Cultivation] Tick skipped: offline")
		return
	print("[Cultivation] Sending tick v", GameState.version)
	CloudService.submit_cultivate_tick(GameState.version)

func _on_game_phase_changed(old: int, new: int) -> void:
	_paused = (new == GameState.GamePhase.PAUSED or new == GameState.GamePhase.GAME_OVER)

# --- Server response handlers ---

func _on_tick_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	var c: Dictionary = result.get("cultivation", {})
	var old_exp := current_exp
	_apply_cultivation_state(c)
	print("[Cultivation] Tick OK: v", GameState.version, " exp ", old_exp, " -> ", current_exp, " realm=", current_realm_id, " lv=", current_level)

func _on_consume_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	var c: Dictionary = result.get("cultivation", {})
	_apply_cultivation_state(c)
	print("[Cultivation] Pill consumed: exp=", current_exp, " buffs=", _active_buffs.size())

func _on_breakthrough_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	var c: Dictionary = result.get("cultivation", {})
	_apply_cultivation_state(c)
	print("[Cultivation] Breakthrough confirmed: realm=", current_realm_id)

func _on_tick_rejected(reason: String) -> void:
	print("[Cultivation] Tick rejected: ", reason)
	if reason == "invalid_token":
		CloudService.clear_token()
		CloudService.kicked.emit()
	elif reason != "version_mismatch":
		EventBus.show_toast.emit("修炼同步失败：" + reason)

# --- Public operations (submit to server) ---

func apply_buff(pill_data: Dictionary) -> void:
	var pill_id: int = pill_data.get("id", 0)
	if pill_id <= 0:
		return
	if CloudService.online:
		CloudService.submit_consume_pill(pill_id, GameState.version)
	else:
		print("[Cultivation] Cannot consume pill: offline")

func try_breakthrough(pill_id: int) -> bool:
	if CloudService.online:
		CloudService.submit_breakthrough(pill_id, GameState.version)
		return true
	return false

# --- State sync from server ---

func _apply_cultivation_state(c: Dictionary) -> void:
	var old_realm := current_realm_id
	var old_level := current_level
	var old_exp := current_exp
	var old_qi := current_qi
	var old_max_qi := max_qi
	var old_buffs := _active_buffs.duplicate()

	current_realm_id = c.get("current_realm_id", 0)
	current_level = c.get("current_level", 1)
	current_exp = c.get("current_exp", 0)
	total_exp = c.get("total_exp", 0)
	current_qi = c.get("current_qi", 100)
	max_qi = c.get("max_qi", 100)
	_active_buffs = c.get("buffs", [])

	# Emit changes
	if current_realm_id != old_realm or current_level != old_level:
		var realm_name: String = get_realm_name()
		realm_changed.emit(current_realm_id, realm_name, current_level)

	if current_exp != old_exp:
		exp_changed.emit(current_exp, get_exp_to_next_level())

	if current_qi != old_qi or max_qi != old_max_qi:
		qi_changed.emit(current_qi, max_qi)

	if not _buffs_equal(_active_buffs, old_buffs):
		buff_changed.emit(_active_buffs.duplicate())

	# Level up / breakthrough detection
	if current_realm_id > old_realm:
		breakthrough.emit(current_realm_id, get_realm_name())
	elif current_level > old_level and current_realm_id == old_realm:
		level_up.emit(current_realm_id, get_realm_name(), current_level)

	# Always emit breakthrough pill needed status (UI needs this on every update)
	if _needs_breakthrough_pill():
		var pill_id := get_required_breakthrough_pill()
		if pill_id > 0:
			print("[Cultivation] Breakthrough pill needed: id=", pill_id)
			breakthrough_pill_needed.emit(pill_id)
	else:
		# Reset label in case breakthrough was completed
		exp_changed.emit(current_exp, get_exp_to_next_level())

func _buffs_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].get("pill_id") != b[i].get("pill_id") or a[i].get("remaining") != b[i].get("remaining"):
			return false
	return true

# --- Queries (local cache, for UI display) ---

func get_realm_name() -> String:
	var realm := ConfigDatabase.get_realm_config(current_realm_id)
	return realm.get("name", "未知")

func get_exp_to_next_level() -> int:
	var realm := ConfigDatabase.get_realm_config(current_realm_id)
	if realm.is_empty():
		return 999999
	var base: int = realm.get("base_exp", 100)
	var growth: float = realm.get("growth", 1.15)
	if growth <= 1.0:
		return base
	var lv: int = mini(current_level + 1, realm.get("levels", 9))
	return int(base * pow(growth, lv - 1))

func get_exp_multiplier() -> float:
	var mult: float = 1.0
	for buff in _active_buffs:
		mult = maxf(mult, buff.get("multiplier", 1.0))
	return mult

func get_active_buffs() -> Array:
	return _active_buffs.duplicate()

func is_breakthrough_ready() -> bool:
	if is_max_cultivation():
		return false
	var realm := ConfigDatabase.get_realm_config(current_realm_id)
	if realm.is_empty():
		return false
	var max_lv: int = realm.get("levels", 1)
	return current_level >= max_lv and current_exp >= get_exp_to_next_level()

func is_max_cultivation() -> bool:
	var realms: Array = ConfigDatabase.get_cultivation_config().get("realms", [])
	return current_realm_id >= realms.size() - 1 and current_level >= _get_max_level_for_realm(current_realm_id)

func get_max_level_for_realm(realm_id: int) -> int:
	var realm := ConfigDatabase.get_realm_config(realm_id)
	return realm.get("levels", 1)

func _get_max_level_for_realm(realm_id: int) -> int:
	return get_max_level_for_realm(realm_id)

func get_required_breakthrough_pill() -> int:
	if not is_breakthrough_ready():
		return 0
	var realm := ConfigDatabase.get_realm_config(current_realm_id)
	return realm.get("breakthrough_pill", 0)

func _needs_breakthrough_pill() -> bool:
	if is_max_cultivation():
		return false
	var max_lv: int = _get_max_level_for_realm(current_realm_id)
	if current_level < max_lv:
		return false
	var realm := ConfigDatabase.get_realm_config(current_realm_id)
	var pill_id: int = realm.get("breakthrough_pill", 0)
	return pill_id > 0

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

func get_formatted_realm_level() -> String:
	var name: String = get_realm_name()
	var max_lv: int = _get_max_level_for_realm(current_realm_id)
	if max_lv <= 1:
		return name
	var level_names := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	return "%s%s" % [name, level_names[current_level] if current_level < level_names.size() else str(current_level)]

# --- Save/Load (now from server) ---

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
	_apply_cultivation_state(data)
	_paused = false
