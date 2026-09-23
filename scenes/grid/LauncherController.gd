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
		charges: int, is_immovable: bool, recharge_remaining_ms: float = 0.0) -> bool:
	if is_immovable:
		spawn_failed.emit("item_immovable", {})
		return false

	# The cooldown is authoritative even when a stale/missing `charges` field
	# would otherwise make this launcher look usable.
	var is_recharging: bool = charges <= 0 and recharge_remaining_ms > 0.0
	if charges <= 0 and _launcher_cd.has(launcher_uid):
		var cooldown: Dictionary = _launcher_cd.get(launcher_uid, {}) as Dictionary
		is_recharging = is_recharging or float(cooldown.get("remaining", 0.0)) > 0.0
	if is_recharging:
		spawn_failed.emit("no_charges", {})
		return false

	var pending_for_launcher: int = _pending_count_for_launcher(launcher_uid)
	var effective_charges: int = charges - pending_for_launcher
	if charges >= 0 and effective_charges <= 0:
		spawn_failed.emit("no_charges", {})
		return false

	var is_no_cost: bool = launcher_config.get("no_cost", false)
	var stamina_multiplier: int = 1
	var stamina_cost: int = 0
	var reserved_cost: int = 0
	if not is_no_cost:
		reserved_cost = _pending_paid_spawn_cost(GameState.current_board_type)
		if GameState.current_board_type == Constants.BoardType.BATTLE:
			if CultivationService.current_qi - reserved_cost < 1:
				spawn_failed.emit("insufficient_qi", {})
				return false
		else:
			GameState.expire_stamina_multiplier_if_needed()
			var safe_multiplier: int = ConfigDatabase.get_launcher_safe_stamina_multiplier(launcher_config)
			stamina_multiplier = mini(GameState.stamina_multiplier_selected, safe_multiplier)
			if stamina_multiplier < GameState.stamina_multiplier_selected:
				EventBus.show_toast.emit(
					"该设施最高支持 ×%d，已按 ×%d 消耗" % [safe_multiplier, stamina_multiplier]
				)

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
	var base_predicted_id: int = _predict_spawn_id(
		launcher_config, effective_charges, GameState.spawn_seed, sequence, launcher_uid
	)
	var spawn_plan: Dictionary = _get_order_priority_spawn(
		base_predicted_id, stamina_multiplier
	)
	var predicted_item: Dictionary = spawn_plan.get("item", {}) as Dictionary
	var applied_multiplier: int = int(spawn_plan.get("multiplier", stamina_multiplier))
	var base_stamina_cost: int = int(ConfigDatabase.get_game_config("stamina.spawn_cost", 1))
	if not is_no_cost and GameState.current_board_type != Constants.BoardType.BATTLE:
		stamina_cost = maxi(0, base_stamina_cost * applied_multiplier)
		if GameState.stamina - reserved_cost < stamina_cost:
			spawn_failed.emit("insufficient_stamina", {})
			return false
	var predicted_id: int = int(predicted_item.get("id", 0))
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
		"stamina_multiplier": stamina_multiplier,
		"applied_stamina_multiplier": applied_multiplier,
		"stamina_cost": stamina_cost,
		"stamina_refund": maxi(
			0, base_stamina_cost * (stamina_multiplier - applied_multiplier)
		),
		"order_priority": bool(spawn_plan.get("order_priority", false)),
	}
	_next_temp_uid -= 1
	_pending_spawns.push_back(prediction)
	spawn_started.emit(prediction)
	CloudService.submit_spawn(
		grid_pos.x, grid_pos.y, request_id, sequence, predicted_id, target_pos,
		stamina_multiplier
	)
	return true


func _get_order_priority_spawn(
	base_item_id: int,
	requested_multiplier: int
) -> Dictionary:
	var boosted: Dictionary = ConfigDatabase.get_upgraded_item_for_multiplier(
		base_item_id, requested_multiplier
	)
	var base: Dictionary = ConfigDatabase.get_item_data(base_item_id)
	if base.is_empty() or boosted.is_empty() or requested_multiplier <= 1:
		return {
			"item": boosted,
			"multiplier": requested_multiplier,
			"order_priority": false,
		}
	var base_level: int = int(base.get("level", 0))
	var boosted_level: int = int(boosted.get("level", 0))
	var base_type: int = int(base.get("type", 0))
	var base_group: int = int(base.get("group_id", 0))
	var best_item: Dictionary = {}
	var best_multiplier: int = requested_multiplier
	for item_id_variant: Variant in _get_outstanding_order_item_counts().keys():
		var item_id: int = int(item_id_variant)
		var candidate: Dictionary = ConfigDatabase.get_item_data(item_id)
		if candidate.is_empty():
			continue
		var candidate_level: int = int(candidate.get("level", 0))
		if (
			int(candidate.get("type", 0)) != base_type
			or int(candidate.get("group_id", 0)) != base_group
			or candidate_level >= boosted_level
		):
			continue
		var reachable: Dictionary = ConfigDatabase.get_item_by_level(
			base_type, candidate_level, base_group
		)
		if int(reachable.get("id", 0)) != item_id:
			continue
		var candidate_multiplier: int = (
			1 if candidate_level <= base_level
			else 1 << (candidate_level - base_level)
		)
		if (
			best_item.is_empty()
			or candidate_level < int(best_item.get("level", 0))
			or (
				candidate_level == int(best_item.get("level", 0))
				and item_id < int(best_item.get("id", 0))
			)
		):
			best_item = candidate
			best_multiplier = candidate_multiplier
	if best_item.is_empty():
		return {
			"item": boosted,
			"multiplier": requested_multiplier,
			"order_priority": false,
		}
	return {
		"item": best_item,
		"multiplier": best_multiplier,
		"order_priority": true,
	}


func _get_outstanding_order_item_counts() -> Dictionary:
	var order_targets: Dictionary = {}
	for order_variant: Variant in GameState.meridian_acupoints:
		if not order_variant is Dictionary:
			continue
		var order: Dictionary = order_variant as Dictionary
		if bool(order.get("completed", false)):
			continue
		var configured: Array = order.get("item_ids", []) as Array
		if configured.is_empty():
			configured = order.get("items", []) as Array
		for entry: Variant in configured:
			var item_id: int = int((entry as Dictionary).get("item_id", 0)) if entry is Dictionary else int(entry)
			if item_id > 0:
				order_targets[item_id] = int(order_targets.get(item_id, 0)) + 1
	var available: Dictionary = {}
	for grid_entry: Dictionary in GridManager.get_all_items():
		var item: Dictionary = grid_entry.get("data", {}) as Dictionary
		var item_id: int = int(item.get("id", 0))
		if int(item.get("type", 0)) != Constants.ItemType.CRAFTING:
			if not bool(item.get("immovable", false)):
				_add_available_order_item(available, item_id)
			continue
		for stored_variant: Variant in item.get("_craft_stored", []):
			if stored_variant is Dictionary:
				_add_available_order_item(
					available, int((stored_variant as Dictionary).get("id", 0))
				)
		var craft_state: int = int(item.get("_craft_state", CraftingService.TableState.IDLE))
		if craft_state == CraftingService.TableState.CRAFTING or craft_state == CraftingService.TableState.READY:
			var result_id: int = int(item.get("_craft_result_id", 0))
			if result_id <= 0:
				var recipe: Dictionary = item.get("_craft_recipe", {}) as Dictionary
				result_id = int(recipe.get("result", 0))
			_add_available_order_item(available, result_id)
	for pouch_variant: Variant in StoragePouch.items:
		var pouch_id: int = (
			int((pouch_variant as Dictionary).get("id", 0))
			if pouch_variant is Dictionary
			else int(pouch_variant)
		)
		_add_available_order_item(available, pouch_id)

	var outstanding: Dictionary = {}
	for target_id_variant: Variant in order_targets.keys():
		var target_id: int = int(target_id_variant)
		_add_recipe_material_requirements(
			target_id,
			int(order_targets[target_id]),
			outstanding,
			available,
			{}
		)
	return outstanding


func _add_available_order_item(available: Dictionary, item_id: int) -> void:
	if item_id <= 0:
		return
	available[item_id] = int(available.get(item_id, 0)) + 1


func _consume_available_order_items(available: Dictionary, item_id: int, count: int) -> int:
	var consumed: int = mini(count, int(available.get(item_id, 0)))
	if consumed <= 0:
		return count
	var remaining_available: int = int(available.get(item_id, 0)) - consumed
	if remaining_available > 0:
		available[item_id] = remaining_available
	else:
		available.erase(item_id)
	return count - consumed


func _add_recipe_material_requirements(
	item_id: int,
	count: int,
	requirements: Dictionary,
	available: Dictionary,
	visiting: Dictionary
) -> void:
	if item_id <= 0 or count <= 0:
		return
	var missing_count: int = _consume_available_order_items(available, item_id, count)
	if missing_count <= 0:
		return
	var recipes: Array = ConfigDatabase.get_recipes_for_result(item_id)
	if recipes.is_empty() or visiting.has(item_id):
		requirements[item_id] = int(requirements.get(item_id, 0)) + missing_count
		return
	visiting[item_id] = true
	var recipe: Dictionary = recipes[0] as Dictionary
	for ingredient_variant: Variant in recipe.get("ingredients", []):
		_add_recipe_material_requirements(
			int(ingredient_variant), missing_count, requirements, available, visiting
		)
	visiting.erase(item_id)

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
			launcher_item["_recharge_remaining"] = cd_time * 1000.0
			charge_visual_update.emit(launcher_uid, TimeUtils.format_countdown(cd_time), Color(1, 0.6, 0.2, 1))
		elif charges_val <= 0:
			charge_visual_update.emit(launcher_uid, "0/%d" % max_c, Color(1, 0.3, 0.3, 1))
		else:
			_launcher_cd.erase(launcher_uid)
			launcher_item.erase("_recharge_remaining")
			charge_visual_update.emit(launcher_uid, "%d/%d" % [charges_val, max_c], Color(1, 1, 1, 0.7))

		if charges_val <= 0 and cd_time <= 0:
			var launcher_pos: Vector2i = GridManager.find_pos_by_uid(launcher_uid)
			spawn_finished.emit(result, prediction)
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

func _pending_paid_spawn_cost(board_type: int) -> int:
	var cost: int = 0
	for pending: Dictionary in _pending_spawns:
		if pending.get("board_type", -1) == board_type and not pending.get("is_no_cost", false):
			if board_type == Constants.BoardType.BATTLE:
				cost += 1
			else:
				cost += int(pending.get("stamina_cost", 1))
	return cost

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
			var charging_item: Dictionary = GridManager.find_by_uid(uid)
			if not charging_item.is_empty():
				charging_item["_recharge_remaining"] = float(cd.remaining) * 1000.0
			charge_visual_update.emit(uid, TimeUtils.format_countdown(cd.remaining), Color(1, 0.6, 0.2, 1))

	for uid in to_erase:
		_launcher_cd.erase(uid)
		var item: Dictionary = GridManager.find_by_uid(uid)
		if not item.is_empty():
			var cfg: Dictionary = ConfigDatabase.get_item_data(item.get("id", 0) as int)
			var max_c: int = cfg.get("max_charges", 3) as int
			item["charges"] = max_c
			item.erase("_recharge_remaining")
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
	item_data["_recharge_remaining"] = remaining * 1000.0
	charge_visual_update.emit(uid, TimeUtils.format_countdown(remaining), Color(1, 0.6, 0.2, 1))

func clear_cd(uid: int) -> void:
	if uid > 0 and _launcher_cd.has(uid):
		_launcher_cd.erase(uid)
	var item: Dictionary = GridManager.find_by_uid(uid)
	if not item.is_empty():
		item.erase("_recharge_remaining")

func is_spawn_in_flight() -> bool:
	return not _pending_spawns.is_empty()
