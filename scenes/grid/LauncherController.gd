class_name LauncherController extends Node

# Manages deterministic launcher prediction, server reconciliation, and cooldowns.

const SPAWN_RNG_MODULUS: int = 2147483647
const SPAWN_RNG_MULTIPLIER: int = 48271

signal spawn_started(prediction: Dictionary)
signal spawn_finished(result: Dictionary, prediction: Dictionary)
signal spawn_failed(reason: String, prediction: Dictionary)
signal charge_visual_update(uid: int, text: String, color: Color)
signal depleted_launcher_removed(uid: int, grid_pos: Vector2i)

var _pending_spawns: Array[Dictionary] = []
var _launcher_cd: Dictionary = {}
var _cd_timer: Timer = null
var _next_temp_uid: int = -1
var _request_counter: int = 0

func _ready() -> void:
	CloudService.spawn_confirmed.connect(_on_spawn_confirmed)
	CloudService.spawn_rejected.connect(_on_spawn_rejected)
	_cd_timer = Timer.new()
	_cd_timer.wait_time = 1.0
	_cd_timer.one_shot = false
	_cd_timer.timeout.connect(_on_cd_tick)
	add_child(_cd_timer)
	_cd_timer.start()

func try_spawn(grid_pos: Vector2i, launcher_uid: int, launcher_config: Dictionary,
		charges: int, is_immovable: bool) -> bool:
	if is_immovable:
		spawn_failed.emit("item_immovable", {})
		return false

	var pending_for_launcher: int = _pending_count_for_launcher(launcher_uid)
	var effective_charges: int = charges - pending_for_launcher
	if charges >= 0 and effective_charges <= 0:
		spawn_failed.emit("no_charges", {})
		return false

	var is_no_cost: bool = launcher_config.get("no_cost", false)
	if not is_no_cost:
		var reserved_cost: int = _pending_paid_spawn_count(GameState.current_board_type)
		if GameState.current_board_type == Constants.BoardType.BATTLE:
			if CultivationService.current_qi - reserved_cost < 1:
				spawn_failed.emit("insufficient_qi", {})
				return false
		elif GameState.stamina - reserved_cost < 1:
			spawn_failed.emit("insufficient_stamina", {})
			return false

	if charges <= 0 and _launcher_cd.has(launcher_uid):
		spawn_failed.emit("no_charges", {})
		return false
	if not CloudService.has_mutation_capacity():
		spawn_failed.emit("request_queue_full", {})
		return false

	var target_pos: Vector2i = GridManager.find_nearest_empty(grid_pos)
	if target_pos.x < 0:
		spawn_failed.emit("no_empty_cell", {})
		return false

	var sequence: int = GameState.spawn_sequence + _pending_spawns.size()
	var predicted_id: int = _predict_spawn_id(
		launcher_config, effective_charges, GameState.spawn_seed, sequence, launcher_uid
	)
	var request_id: String = _create_request_id(launcher_uid)
	var prediction: Dictionary = {
		"request_id": request_id,
		"launcher_uid": launcher_uid,
		"launcher_pos": grid_pos,
		"target_pos": target_pos,
		"predicted_id": predicted_id,
		"temp_uid": _next_temp_uid,
		"sequence": sequence,
		"board_type": GameState.current_board_type,
		"is_no_cost": is_no_cost,
	}
	_next_temp_uid -= 1
	_pending_spawns.push_back(prediction)
	spawn_started.emit(prediction)
	CloudService.submit_spawn(
		grid_pos.x, grid_pos.y, request_id, sequence, predicted_id, target_pos
	)
	return true

func _predict_spawn_id(launcher_config: Dictionary, effective_charges: int,
		seed: int, sequence: int, launcher_uid: int) -> int:
	var fixed_spawns: Array = launcher_config.get("fixed_spawns", [])
	if not fixed_spawns.is_empty():
		var max_charges: int = launcher_config.get("max_charges", fixed_spawns.size())
		var used_count: int = max_charges - effective_charges
		if used_count >= 0 and used_count < fixed_spawns.size():
			return int(fixed_spawns[used_count])
		return 0

	if seed <= 0:
		return 0
	var spawns: Array = launcher_config.get("spawns", [])
	var total_weight: int = 0
	for spawn: Dictionary in spawns:
		total_weight += int(spawn.get("weight", 0))
	if total_weight <= 0:
		return 0

	var roll: int = deterministic_spawn_roll(seed, sequence, launcher_uid, total_weight)
	for spawn: Dictionary in spawns:
		var weight: int = int(spawn.get("weight", 0))
		if roll < weight:
			return int(spawn.get("id", 0))
		roll -= weight
	return int((spawns[-1] as Dictionary).get("id", 0)) if not spawns.is_empty() else 0

static func deterministic_spawn_roll(seed: int, sequence: int, launcher_uid: int,
		total_weight: int) -> int:
	if total_weight <= 0:
		return 0
	var value: int = (seed % (SPAWN_RNG_MODULUS - 1)) + 1
	value = (value * SPAWN_RNG_MULTIPLIER + maxi(0, sequence)) % SPAWN_RNG_MODULUS
	value = (value * SPAWN_RNG_MULTIPLIER + maxi(0, launcher_uid)) % SPAWN_RNG_MODULUS
	return value % total_weight

func _create_request_id(launcher_uid: int) -> String:
	_request_counter += 1
	var unix_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	return "%d-%d-%d" % [unix_ms, launcher_uid, _request_counter]

func _on_spawn_confirmed(result: Dictionary) -> void:
	var prediction: Dictionary = _take_pending(String(result.get("request_id", "")))
	if prediction.is_empty():
		return
	var launcher_uid: int = prediction.get("launcher_uid", -1)

	var charges_val: Variant = result.get("charges", null)
	if charges_val != null and launcher_uid > 0:
		var launcher_item: Dictionary = GridManager.find_by_uid(launcher_uid)
		if not launcher_item.is_empty():
			launcher_item["charges"] = charges_val
		var max_c: int = result.get("max_charges", 3)
		var cd_time: float = result.get("recharge_time", 0.0)
		if charges_val <= 0 and cd_time > 0:
			_launcher_cd[launcher_uid] = {"remaining": cd_time, "recharge_time": cd_time, "max_charges": max_c}
			var cd_secs: int = int(ceil(cd_time))
			charge_visual_update.emit(launcher_uid, "%02d:%02d" % [int(cd_secs / 60), cd_secs % 60], Color(1, 0.6, 0.2, 1))
		elif charges_val <= 0:
			charge_visual_update.emit(launcher_uid, "0/%d" % max_c, Color(1, 0.3, 0.3, 1))
		else:
			charge_visual_update.emit(launcher_uid, "%d/%d" % [charges_val, max_c], Color(1, 1, 1, 0.7))

		spawn_finished.emit(result, prediction)
		if charges_val <= 0 and cd_time <= 0:
			var launcher_pos: Vector2i = GridManager.find_pos_by_uid(launcher_uid)
			depleted_launcher_removed.emit(launcher_uid, launcher_pos)
		return

	spawn_finished.emit(result, prediction)

func _on_spawn_rejected(reason: String) -> void:
	var prediction: Dictionary = {}
	if not _pending_spawns.is_empty():
		prediction = _pending_spawns.pop_front()
	spawn_failed.emit(reason, prediction)

func _take_pending(request_id: String) -> Dictionary:
	if _pending_spawns.is_empty():
		return {}
	if request_id.is_empty():
		return _pending_spawns.pop_front()
	for index in range(_pending_spawns.size()):
		if _pending_spawns[index].get("request_id", "") == request_id:
			var prediction: Dictionary = _pending_spawns[index]
			_pending_spawns.remove_at(index)
			return prediction
	return {}

func _pending_count_for_launcher(launcher_uid: int) -> int:
	var count: int = 0
	for pending: Dictionary in _pending_spawns:
		if pending.get("launcher_uid", -1) == launcher_uid:
			count += 1
	return count

func _pending_paid_spawn_count(board_type: int) -> int:
	var count: int = 0
	for pending: Dictionary in _pending_spawns:
		if pending.get("board_type", -1) == board_type and not pending.get("is_no_cost", false):
			count += 1
	return count

func _on_cd_tick() -> void:
	if _launcher_cd.is_empty():
		return
	var to_erase: Array = []
	for uid in _launcher_cd:
		if uid <= 0:
			to_erase.append(uid)
			continue
		var cd: Dictionary = _launcher_cd[uid]
		cd.remaining -= 1.0
		if cd.remaining <= 0:
			to_erase.append(uid)
		else:
			var secs: int = int(ceil(cd.remaining))
			var m: int = int(secs / 60)
			var s: int = secs % 60
			charge_visual_update.emit(uid, "%02d:%02d" % [m, s], Color(1, 0.6, 0.2, 1))

	for uid in to_erase:
		_launcher_cd.erase(uid)
		var item: Dictionary = GridManager.find_by_uid(uid)
		if not item.is_empty():
			var cfg: Dictionary = ConfigDatabase.get_item_data(item.get("id", 0) as int)
			var max_c: int = cfg.get("max_charges", 3) as int
			item["charges"] = max_c
			charge_visual_update.emit(uid, "%d/%d" % [max_c, max_c], Color(1, 1, 1, 0.7))

func start_cd_from_restore(item_data: Dictionary) -> void:
	if item_data.get("charges", -1) != 0:
		return
	var uid: int = item_data.get("_uid", 0) as int
	if _launcher_cd.has(uid):
		return
	var cfg: Dictionary = ConfigDatabase.get_item_data(item_data.get("id", 0) as int)
	if cfg.is_empty() or not Constants.has_launcher_config(cfg):
		return
	var cd_time: float = cfg.get("recharge_time", 0.0) as float
	if cd_time <= 0:
		return
	var max_c: int = cfg.get("max_charges", 3) as int
	var remaining: float = cd_time
	var server_rem: Variant = item_data.get("_recharge_remaining", null)
	if typeof(server_rem) == TYPE_FLOAT or typeof(server_rem) == TYPE_INT:
		remaining = maxf(0, float(server_rem) / 1000.0)
	_launcher_cd[uid] = {"remaining": remaining, "recharge_time": cd_time, "max_charges": max_c}
	var secs: int = int(ceil(remaining))
	charge_visual_update.emit(uid, "%02d:%02d" % [int(secs / 60), secs % 60], Color(1, 0.6, 0.2, 1))

func clear_cd(uid: int) -> void:
	if uid > 0 and _launcher_cd.has(uid):
		_launcher_cd.erase(uid)

func is_spawn_in_flight() -> bool:
	return not _pending_spawns.is_empty()
