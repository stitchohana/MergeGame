extends Node

# CultivationService: Client-side display layer for cultivation.
# All logic (EXP, breakthrough) runs on the server.
# Client submits operations and displays results from server responses.

signal exp_changed(current_exp: int, exp_to_next: int)
signal stage_changed(level: int, stage_name: String)
signal qi_changed(current_qi: int, max_qi: int)
signal breakthrough_items_needed(items: Array)

var current_level: int = 1
var current_exp: int = 0
var total_exp: int = 0
var current_qi: int = 0
var max_qi: int = 100
var _pending_exp_pill_uid: int = -1

func _ready() -> void:
	CloudService.breakthrough_confirmed.connect(_on_breakthrough_confirmed)
	CloudService.breakthrough_rejected.connect(_on_breakthrough_rejected)
	CloudService.exp_pill_consume_confirmed.connect(_on_exp_pill_consume_confirmed)

# --- Server response handlers ---

func _on_breakthrough_confirmed(result: Dictionary) -> void:
	print("[Cultivation] breakthrough confirmed")
	if result.has("grid"):
		var server_grid: Array = result.get("grid", []) as Array
		GridManager.populate_from_server(server_grid)
	if result.has("pouch"):
		var server_pouch: Array = result.get("pouch", []) as Array
		StoragePouch.restore_from_server(server_pouch)
	if result.has("meridian_acupoints"):
		GameState.meridian_acupoints = (result.get("meridian_acupoints", []) as Array).duplicate(true)
		GameState.meridian_updated.emit()
	var c: Dictionary = result.get("cultivation", {})
	_apply_cultivation_state(c)

func _on_breakthrough_rejected(_reason: String) -> void:
	pass

func _on_exp_pill_consume_confirmed(result: Dictionary) -> void:
	if result.has("meridian_acupoints"):
		GameState.meridian_acupoints = (result.get("meridian_acupoints", []) as Array).duplicate(true)
		GameState.meridian_updated.emit()
	var c: Dictionary = result.get("cultivation", {})
	_apply_cultivation_state(c)
	if _pending_exp_pill_uid > 0:
		var pos := GridManager.find_pos_by_uid(_pending_exp_pill_uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)
		_pending_exp_pill_uid = -1

# --- Public operations (submit to server) ---

func try_breakthrough(uid: int = 0) -> bool:
	print("[Cultivation] try_breakthrough uid=" + str(uid))
	if uid <= 0:
		print("[Cultivation] try_breakthrough uid=0, server will consume configured items")
	if CloudService.online:
		CloudService.submit_breakthrough(uid)
		return true
	return false

func consume_exp_pill(pill_id: int, uid: int) -> void:
	_pending_exp_pill_uid = uid
	if CloudService.online:
		CloudService.submit_consume_exp_pill(pill_id, uid)

# --- State sync from server ---

func _apply_cultivation_state(c: Dictionary) -> void:
	var old_level := current_level
	var old_exp := current_exp
	var old_qi := current_qi
	var old_max_qi := max_qi

	current_level = c.get("current_level", 1)
	current_exp = c.get("current_exp", 0)
	total_exp = c.get("total_exp", 0)
	current_qi = c.get("current_qi", 0)
	max_qi = c.get("max_qi", 100)
	print("[Cultivation] apply_state: level=" + str(current_level) + " exp=" + str(current_exp) + " qi=" + str(current_qi) + "/" + str(max_qi))

	if current_level != old_level:
		var stage_name: String = get_stage_name()
		stage_changed.emit(current_level, stage_name)

	if current_exp != old_exp:
		var e2n = get_exp_to_next_level()
		print("[Cultivation] exp_changed: " + str(current_exp) + "/" + str(e2n))
		exp_changed.emit(current_exp, e2n)

	if current_qi != old_qi or max_qi != old_max_qi:
		qi_changed.emit(current_qi, max_qi)

	if _needs_breakthrough_items():
		breakthrough_items_needed.emit(get_required_breakthrough_items())
	else:
		exp_changed.emit(current_exp, get_exp_to_next_level())

# --- Queries (local cache, for UI display) ---

func get_stage_name() -> String:
	return ConfigDatabase.get_stage_name(current_level)

func get_exp_to_next_level() -> int:
	return ConfigDatabase.get_stage_exp(current_level)

func is_breakthrough_ready() -> bool:
	if is_max_cultivation():
		return false
	return current_exp >= get_exp_to_next_level()

func is_max_cultivation() -> bool:
	return current_level >= ConfigDatabase.get_stage_count()

func get_current_atk() -> int:
	return ConfigDatabase.get_stage_atk(current_level)

func get_required_breakthrough_items() -> Array:
	if not is_breakthrough_ready():
		return []
	return ConfigDatabase.get_stage_breakthrough_items(current_level)


func _needs_breakthrough_items() -> bool:
	if is_max_cultivation():
		return false
	if not is_breakthrough_ready():
		return false
	return not ConfigDatabase.get_stage_breakthrough_items(current_level).is_empty()

func get_formatted_stage() -> String:
	return ConfigDatabase.get_stage_name(current_level)

# --- Save/Load (now from server) ---

func serialize() -> Dictionary:
	return {
		"current_level": current_level,
		"current_exp": current_exp,
		"total_exp": total_exp,
		"current_qi": current_qi,
		"max_qi": max_qi,
	}

func deserialize(data: Dictionary) -> void:
	_apply_cultivation_state(data)
