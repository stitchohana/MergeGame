class_name LauncherController extends Node

# Manages launcher spawn, cooldown timers, and charge display.
# Created as a child of GridView so it can access the scene tree for timers.

signal spawn_started(launcher_uid: int)
signal spawn_finished()
signal spawn_failed(reason: String)
signal charge_visual_update(uid: int, text: String, color: Color)
signal depleted_launcher_removed(uid: int, grid_pos: Vector2i)

var _pending_spawn_uid: int = -1
var _spawn_in_flight: bool = false
var _launcher_cd: Dictionary = {}  # uid -> {remaining, recharge_time, max_charges}
var _cd_timer: Timer = null

func _ready() -> void:
	CloudService.spawn_confirmed.connect(_on_spawn_confirmed)
	CloudService.spawn_rejected.connect(_on_spawn_rejected)
	_cd_timer = Timer.new()
	_cd_timer.wait_time = 1.0
	_cd_timer.one_shot = false
	_cd_timer.timeout.connect(_on_cd_tick)
	add_child(_cd_timer)
	_cd_timer.start()

func try_spawn(grid_pos: Vector2i, launcher_uid: int, charges: int, is_immovable: bool, is_no_cost: bool, recharge_time: float) -> bool:
	if _spawn_in_flight:
		return false
	_spawn_in_flight = true
	_pending_spawn_uid = launcher_uid

	if is_immovable:
		_spawn_in_flight = false
		spawn_failed.emit("该物品无法使用")
		return false

	if not is_no_cost:
		if GameState.current_board_type == Constants.BoardType.BATTLE:
			if CultivationService.current_qi < 1:
				_spawn_in_flight = false
				spawn_failed.emit("灵力不足")
				return false
		elif GameState.stamina < 1:
			_spawn_in_flight = false
			spawn_failed.emit("体力不足")
			return false

	if charges <= 0 and _launcher_cd.has(launcher_uid):
		_spawn_in_flight = false
		spawn_failed.emit("发射器冷却中")
		return false

	spawn_started.emit(launcher_uid)
	CloudService.submit_spawn(grid_pos.x, grid_pos.y)
	return true

func _on_spawn_confirmed(result: Dictionary) -> void:
	var launcher_uid: int = _pending_spawn_uid
	_pending_spawn_uid = -1

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
			charge_visual_update.emit(launcher_uid, "空", Color(1, 0.3, 0.3, 1))
		else:
			charge_visual_update.emit(launcher_uid, "%d/%d" % [charges_val, max_c], Color(1, 1, 1, 0.7))

		if charges_val <= 0:
			var recharge_t: float = result.get("recharge_time", 0.0)
			if recharge_t <= 0:
				var launcher_pos: Vector2i = GridManager.find_pos_by_uid(launcher_uid)
				_spawn_in_flight = false
				depleted_launcher_removed.emit(launcher_uid, launcher_pos)
				return

	_spawn_in_flight = false
	spawn_finished.emit()

func _on_spawn_rejected(reason: String) -> void:
	_pending_spawn_uid = -1
	_spawn_in_flight = false
	spawn_failed.emit(reason)

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
			charge_visual_update.emit(uid, "%d/%d" % [max_c, max_c], Color(1, 1, 1, 0.7))

func start_cd_from_restore(item_data: Dictionary) -> void:
	if item_data.get("charges", -1) != 0:
		return
	var uid: int = item_data.get("_uid", 0) as int
	if _launcher_cd.has(uid):
		return
	var cfg: Dictionary = ConfigDatabase.get_item_data(item_data.get("id", 0) as int)
	if cfg.is_empty() or cfg.get("type", "") != "launcher":
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
	return _spawn_in_flight
