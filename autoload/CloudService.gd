extends Node

# CloudService: HTTP communication with the game server.
# Autoload singleton — registered after EventBus in project.godot.

signal connected()
signal disconnected()
signal kicked()
signal login_success(user_id: String)
signal login_failed(reason: String)
signal merge_confirmed(result: Dictionary)
signal merge_rejected(reason: String)
signal spawn_confirmed(result: Dictionary)
signal spawn_rejected(reason: String)
signal craft_add_confirmed(result: Dictionary)
signal move_confirmed(result: Dictionary)
signal move_rejected(reason: String)
signal push_place_confirmed(result: Dictionary)
signal push_place_rejected(reason: String)
signal breakthrough_confirmed(result: Dictionary)
signal breakthrough_rejected(reason: String)
signal exp_pill_consume_confirmed(result: Dictionary)
signal exp_pill_consume_rejected(reason: String)
signal stamina_restore_confirmed(result: Dictionary)
signal stamina_restore_rejected(reason: String)
signal board_switch_confirmed(result: Dictionary)
signal board_switch_rejected(reason: String)
signal pouch_deposit_confirmed(result: Dictionary)
signal pouch_deposit_rejected(reason: String)
signal pouch_withdraw_confirmed(result: Dictionary)
signal pouch_withdraw_rejected(reason: String)
signal meridian_refresh_confirmed(result: Dictionary)
signal meridian_complete_confirmed(result: Dictionary)
signal meridian_complete_rejected(reason: String)
signal quest_claim_confirmed(result: Dictionary)
signal quest_claim_rejected(reason: String)
signal pending_reward_claimed(result: Dictionary)
signal pending_reward_claimed_rejected(reason: String)
signal home_meridian_light_confirmed(result: Dictionary)
signal home_meridian_light_rejected(reason: String)
signal craft_add_rejected(reason: String)
signal craft_start_confirmed(result: Dictionary)
signal craft_start_rejected(reason: String)
signal craft_remove_confirmed(result: Dictionary)
signal craft_remove_rejected(reason: String)
signal craft_retrieve_confirmed(result: Dictionary)
signal craft_retrieve_rejected(reason: String)
signal state_loaded(state: Dictionary)
signal state_load_failed(reason: String)
signal battle_attack_confirmed(result: Dictionary)
signal battle_attack_rejected(reason: String)
signal battle_heal_confirmed(result: Dictionary)
signal battle_heal_rejected(reason: String)
signal storage_withdraw_confirmed(result: Dictionary)
signal sell_confirmed(result: Dictionary)
signal sell_rejected(reason: String)
signal shop_items_loaded(items: Array)
signal buy_confirmed(result: Dictionary)
signal buy_rejected(reason: String)
signal gm_exec_confirmed(result: Dictionary)
signal gm_exec_rejected(reason: String)

var online: bool = false
var token: String = ""
var base_url: String = ""

var _http: HTTPRequest = null
var _timeout: float = 10.0
var _max_retries: int = 2
var _busy: bool = false
var _callbacks: Dictionary = {}
var _request_queue: Array[Dictionary] = []
const QUEUE_MAX := 10
var _current_tag: String = ""

# --- Endpoint registry: maps tag -> { response_cb, rejected_signal, network_signal, parse_signal } ---
var _endpoints: Dictionary = {}

func _ready() -> void:
	_load_config()
	_setup_http()
	_register_all_endpoints()

func _register_endpoint(tag: String, response_cb: Callable,
		rejected_signal: Signal = Signal(), network_signal: Signal = Signal(), parse_signal: Signal = Signal()) -> void:
	_endpoints[tag] = {
		"response_cb": response_cb,
		"rejected": rejected_signal,
		"network": network_signal,
		"parse": parse_signal,
	}

func _register_all_endpoints() -> void:
	_register_endpoint("login", _on_login_response, login_failed, login_failed, login_failed)
	_register_endpoint("fetch_state", _on_fetch_state_response, state_load_failed, state_load_failed, state_load_failed)
	_register_endpoint("merge", _on_merge_response, merge_rejected, merge_rejected, merge_rejected)
	_register_endpoint("spawn", _on_spawn_response, spawn_rejected, spawn_rejected, spawn_rejected)
	_register_endpoint("push_place", _on_push_place_response, push_place_rejected, push_place_rejected, push_place_rejected)
	_register_endpoint("move", _on_move_response, move_rejected, move_rejected, move_rejected)
	_register_endpoint("breakthrough", _on_breakthrough_response, breakthrough_rejected, breakthrough_rejected, breakthrough_rejected)
	_register_endpoint("consume_exp_pill", _on_consume_exp_pill_response, exp_pill_consume_rejected, exp_pill_consume_rejected, exp_pill_consume_rejected)
	_register_endpoint("restore_stamina", _on_restore_stamina_response, stamina_restore_rejected, stamina_restore_rejected, stamina_restore_rejected)
	_register_endpoint("board_switch", _on_board_switch_response, board_switch_rejected, board_switch_rejected, board_switch_rejected)
	_register_endpoint("pouch_deposit", _on_pouch_deposit_response, pouch_deposit_rejected, pouch_deposit_rejected, pouch_deposit_rejected)
	_register_endpoint("pouch_withdraw", _on_pouch_withdraw_response, pouch_withdraw_rejected, pouch_withdraw_rejected, pouch_withdraw_rejected)
	_register_endpoint("meridian_refresh", _on_meridian_refresh_response, meridian_refresh_confirmed, meridian_refresh_confirmed, meridian_refresh_confirmed)
	_register_endpoint("meridian_complete", _on_meridian_complete_response, meridian_complete_rejected, meridian_complete_rejected, meridian_complete_rejected)
	_register_endpoint("quest_claim", _on_quest_claim_response, quest_claim_rejected, quest_claim_rejected, quest_claim_rejected)
	_register_endpoint("claim_pending_reward", _on_claim_pending_reward_response, pending_reward_claimed_rejected, pending_reward_claimed_rejected, pending_reward_claimed_rejected)
	_register_endpoint("home_meridian_light", _on_home_meridian_light_response, home_meridian_light_rejected, home_meridian_light_rejected, home_meridian_light_rejected)
	_register_endpoint("craft_add", _on_craft_add_response, craft_add_rejected, craft_add_rejected, craft_add_rejected)
	_register_endpoint("craft_start", _on_craft_start_response, craft_start_rejected, craft_start_rejected, craft_start_rejected)
	_register_endpoint("craft_remove", _on_craft_remove_response, craft_remove_rejected, craft_remove_rejected, craft_remove_rejected)
	_register_endpoint("craft_retrieve", _on_craft_retrieve_response, craft_retrieve_rejected, craft_retrieve_rejected, craft_retrieve_rejected)
	_register_endpoint("battle_attack", _on_battle_attack_response, battle_attack_rejected, battle_attack_rejected, battle_attack_rejected)
	_register_endpoint("battle_heal", _on_battle_heal_response, battle_heal_rejected, battle_heal_rejected, battle_heal_rejected)
	_register_endpoint("storage_withdraw", _on_storage_withdraw_response)
	_register_endpoint("storage_deposit", Callable())
	_register_endpoint("sell", _on_sell_response, sell_rejected, sell_rejected, sell_rejected)
	_register_endpoint("shop_items", _on_shop_items_response)
	_register_endpoint("buy", _on_buy_response, buy_rejected, buy_rejected, buy_rejected)
	_register_endpoint("gm_exec", _on_gm_exec_response, gm_exec_rejected, gm_exec_rejected, gm_exec_rejected)
	_register_endpoint("leaderboard", Callable())

func _load_config() -> void:
	var file := FileAccess.open("res://config/json_output/server.json", FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(text) == OK:
			var data: Dictionary = json.data
			base_url = data.get("base_url", "http://localhost:3000")
			_timeout = data.get("timeout", 10.0)
			_max_retries = data.get("max_retries", 2)
			print("[CloudService] Configured: ", base_url)
		else:
			push_error("[CloudService] Failed to parse server.json")
	else:
		push_error("[CloudService] server.json not found, using default localhost:3000")
		base_url = "http://localhost:3000"

func _setup_http() -> void:
	_http = HTTPRequest.new()
	_http.name = "CloudHTTP"
	_http.timeout = _timeout
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)

func configure(url: String) -> void:
	base_url = url

# --- Auth ---

func login(device_id: String) -> void:
	var body := JSON.stringify({"device_id": device_id})
	_send_request("login", "/api/auth/login", HTTPClient.Method.METHOD_POST, body)

func _on_login_response(data: Dictionary) -> void:
	token = data.get("token", "")
	var user: Dictionary = data.get("user", {})
	var user_id: String = user.get("user_id", "")
	if not token.is_empty() and not user_id.is_empty():
		_save_token()
		online = true
		connected.emit()
		login_success.emit(user_id)
		print("[CloudService] Login success: ", user_id)
	else:
		login_failed.emit("invalid_response")

# --- Game State ---

func fetch_state() -> void:
	_send_authed_request("fetch_state", "/api/game/state", HTTPClient.Method.METHOD_GET)

func _on_fetch_state_response(data: Dictionary) -> void:
	state_loaded.emit(data)

# --- Merge ---

func submit_merge(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	var body := JSON.stringify({
		"from": [from_col, from_row],
		"to": [to_col, to_row]
	})
	_send_authed_request("merge", "/api/game/merge", HTTPClient.Method.METHOD_POST, body)

func _on_merge_response(data: Dictionary) -> void:
	if data.get("ok", false):
		merge_confirmed.emit(data)
	else:
		merge_rejected.emit(data.get("error", "unknown_error"))

# --- Spawn ---

func submit_spawn(launcher_col: int, launcher_row: int) -> void:
	var body := JSON.stringify({
		"launcher_pos": [launcher_col, launcher_row]
	})
	_send_authed_request("spawn", "/api/game/spawn", HTTPClient.Method.METHOD_POST, body)

func _on_spawn_response(data: Dictionary) -> void:
	if data.get("ok", false):
		spawn_confirmed.emit(data)
	else:
		spawn_rejected.emit(data.get("error", "unknown_error"))

func _on_push_place_response(data: Dictionary) -> void:
	if data.get("ok", false):
		push_place_confirmed.emit(data)
	else:
		push_place_rejected.emit(data.get("error", "unknown_error"))

func _on_move_response(data: Dictionary) -> void:
	if data.get("ok", false):
		move_confirmed.emit(data)
	else:
		move_rejected.emit(data.get("error", "unknown_error"))

# --- Move ---

func submit_push_place(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	var body := JSON.stringify({"from": [from_col, from_row], "to": [to_col, to_row]})
	_send_authed_request("push_place", "/api/game/push_place", HTTPClient.Method.METHOD_POST, body)

func submit_move(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	var body := JSON.stringify({
		"from": [from_col, from_row],
		"to": [to_col, to_row]
	})
	_send_authed_request("move", "/api/game/move", HTTPClient.Method.METHOD_POST, body)

# --- Cultivation ---

func submit_breakthrough(pill_id: int, uid: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "uid": uid})
	_send_authed_request("breakthrough", "/api/cultivation/breakthrough", HTTPClient.Method.METHOD_POST, body)

func submit_consume_exp_pill(pill_id: int, uid: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "uid": uid})
	_send_authed_request("consume_exp_pill", "/api/cultivation/consume-exp", HTTPClient.Method.METHOD_POST, body)

func submit_restore_stamina(pill_id: int, uid: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "uid": uid})
	_send_authed_request("restore_stamina", "/api/cultivation/consume-stamina", HTTPClient.Method.METHOD_POST, body)

func submit_board_switch(board_type: String, map_id: int = 0, stage: int = 0) -> void:
	var body_data: Dictionary = {"board_type": board_type}
	if map_id > 0:
		body_data["map_id"] = map_id
	if stage > 0:
		body_data["stage"] = stage
	var body := JSON.stringify(body_data)
	_send_authed_request("board_switch", "/api/game/board/switch", HTTPClient.Method.METHOD_POST, body)

func submit_pouch_deposit(uid: int) -> void:
	var body := JSON.stringify({"uid": uid})
	_send_authed_request("pouch_deposit", "/api/game/pouch/deposit", HTTPClient.Method.METHOD_POST, body)

func submit_pouch_withdraw(uid: int) -> void:
	var body := JSON.stringify({"uid": uid})
	_send_authed_request("pouch_withdraw", "/api/game/pouch/withdraw", HTTPClient.Method.METHOD_POST, body)

func submit_battle_heal(item_id: int, effect_id: int, uid: int) -> void:
	var body := JSON.stringify({"item_id": item_id, "effect_id": effect_id, "uid": uid})
	_send_authed_request("battle_heal", "/api/game/battle/heal", HTTPClient.Method.METHOD_POST, body)

func submit_battle_attack(item_id: int, effect_id: int, col: int, row: int) -> void:
	var body := JSON.stringify({"item_id": item_id, "effect_id": effect_id, "col": col, "row": row})
	_send_authed_request("battle_attack", "/api/game/battle/attack", HTTPClient.Method.METHOD_POST, body)

func _on_battle_heal_response(data: Dictionary) -> void:
	if data.get("ok", false):
		battle_heal_confirmed.emit(data)
	else:
		battle_heal_rejected.emit(data.get("error", "unknown_error"))

func _on_battle_attack_response(data: Dictionary) -> void:
	if data.get("ok", false):
		battle_attack_confirmed.emit(data)
	else:
		battle_attack_rejected.emit(data.get("error", "unknown_error"))

func _on_board_switch_response(data: Dictionary) -> void:
	if data.get("ok", false):
		board_switch_confirmed.emit(data)
	else:
		board_switch_rejected.emit(data.get("error", "unknown_error"))

func _on_pouch_deposit_response(data: Dictionary) -> void:
	if data.get("ok", false):
		pouch_deposit_confirmed.emit(data)
	else:
		pouch_deposit_rejected.emit(data.get("error", "unknown_error"))

func _on_pouch_withdraw_response(data: Dictionary) -> void:
	if data.get("ok", false):
		pouch_withdraw_confirmed.emit(data)
	else:
		pouch_withdraw_rejected.emit(data.get("error", "unknown_error"))

func submit_meridian_refresh() -> void:
	_send_authed_request("meridian_refresh", "/api/game/meridian/refresh", HTTPClient.Method.METHOD_POST, "{}")

func _on_meridian_refresh_response(data: Dictionary) -> void:
	if data.get("ok", false):
		meridian_refresh_confirmed.emit(data)

func submit_meridian_complete(index: int, item_ids: Array) -> void:
	var body := JSON.stringify({"index": index, "item_ids": item_ids})
	_send_authed_request("meridian_complete", "/api/game/meridian/complete", HTTPClient.Method.METHOD_POST, body)

func submit_quest_claim(quest_id: int) -> void:
	var body := JSON.stringify({"quest_id": quest_id})
	_send_authed_request("quest_claim", "/api/game/quest_claim", HTTPClient.Method.METHOD_POST, body)

func submit_claim_pending_reward(uid: int) -> void:
	var body := JSON.stringify({"uid": uid})
	_send_authed_request("claim_pending_reward", "/api/game/claim_pending_reward", HTTPClient.Method.METHOD_POST, body)

func submit_light_home_acupoint(stage: int, index: int) -> void:
	var body := JSON.stringify({"stage": stage, "index": index})
	_send_authed_request("home_meridian_light", "/api/game/home_meridian/light", HTTPClient.METHOD_POST, body)

func _on_meridian_complete_response(data: Dictionary) -> void:
	if data.get("ok", false):
		meridian_complete_confirmed.emit(data)
	else:
		meridian_complete_rejected.emit(data.get("error", "unknown_error"))

func _on_quest_claim_response(data: Dictionary) -> void:
	if data.get("ok", false):
		quest_claim_confirmed.emit(data)
	else:
		quest_claim_rejected.emit(data.get("error", "unknown_error"))

func _on_home_meridian_light_response(data: Dictionary) -> void:
	if data.get("ok", false):
		home_meridian_light_confirmed.emit(data)
	else:
		home_meridian_light_rejected.emit(data.get("error", "unknown_error"))

func _on_claim_pending_reward_response(data: Dictionary) -> void:
	if data.get("ok", false):
		pending_reward_claimed.emit(data)
	else:
		pending_reward_claimed_rejected.emit(data.get("error", "unknown_error"))

func _on_breakthrough_response(data: Dictionary) -> void:
	print("[CloudService] breakthrough response: " + str(data))
	if data.get("ok", false):
		breakthrough_confirmed.emit(data)
	else:
		print("[CloudService] breakthrough REJECTED: " + str(data.get("error", "unknown")))
		breakthrough_rejected.emit(data.get("error", "unknown_error"))

func _on_consume_exp_pill_response(data: Dictionary) -> void:
	if data.get("ok", false):
		exp_pill_consume_confirmed.emit(data)
	else:
		exp_pill_consume_rejected.emit(data.get("error", "unknown_error"))

func _on_restore_stamina_response(data: Dictionary) -> void:
	if data.get("ok", false):
		stamina_restore_confirmed.emit(data)
	else:
		stamina_restore_rejected.emit(data.get("error", "unknown_error"))

# --- Craft ---

func submit_craft_add(from_col: int, from_row: int, table_col: int, table_row: int, ingredient_id: int) -> void:
	var body := JSON.stringify({
		"from_col": from_col,
		"from_row": from_row,
		"table_col": table_col,
		"table_row": table_row,
		"ingredient_id": ingredient_id
	})
	_send_authed_request("craft_add", "/api/game/craft/add", HTTPClient.Method.METHOD_POST, body)

func _on_craft_add_response(data: Dictionary) -> void:
	if data.get("ok", false):
		craft_add_confirmed.emit(data)
	else:
		craft_add_rejected.emit(data.get("error", "unknown_error"))

func submit_craft_start(table_col: int, table_row: int) -> void:
	var body := JSON.stringify({
		"table_col": table_col,
		"table_row": table_row
	})
	_send_authed_request("craft_start", "/api/game/craft/start", HTTPClient.Method.METHOD_POST, body)

func _on_craft_start_response(data: Dictionary) -> void:
	if data.get("ok", false):
		craft_start_confirmed.emit(data)
	else:
		craft_start_rejected.emit(data.get("error", "unknown_error"))

func submit_craft_remove(table_col: int, table_row: int, uid: int, target_col: int, target_row: int) -> void:
	var body := JSON.stringify({
		"table_col": table_col,
		"table_row": table_row,
		"uid": uid,
		"target_col": target_col,
		"target_row": target_row
	})
	_send_authed_request("craft_remove", "/api/game/craft/remove", HTTPClient.Method.METHOD_POST, body)

func submit_craft_retrieve(table_col: int, table_row: int) -> void:
	var body := JSON.stringify({
		"table_col": table_col,
		"table_row": table_row
	})
	_send_authed_request("craft_retrieve", "/api/game/craft/retrieve", HTTPClient.Method.METHOD_POST, body)

func _on_craft_remove_response(data: Dictionary) -> void:
	if data.get("ok", false):
		craft_remove_confirmed.emit(data)
	else:
		craft_remove_rejected.emit(data.get("error", "unknown_error"))

func _on_craft_retrieve_response(data: Dictionary) -> void:
	if data.get("ok", false):
		craft_retrieve_confirmed.emit(data)
	else:
		craft_retrieve_rejected.emit(data.get("error", "unknown_error"))

# --- Leaderboard ---

func get_leaderboard(limit: int = 50) -> void:
	_send_authed_request("leaderboard", "/api/game/leaderboard?limit=" + str(limit), HTTPClient.Method.METHOD_GET)

# --- Request queue ---

var _request_counter: int = 0

func _flush_queue() -> void:
	if _busy or _request_queue.is_empty():
		return
	var req: Dictionary = _request_queue.pop_front()
	if req.get("authed", false):
		_send_authed_request(req.tag, req.path, req.method, req.body)
	else:
		_send_request(req.tag, req.path, req.method, req.body)

func _emit_error(tag: String, error_type: String, reason: String) -> void:
	var ep: Dictionary = _endpoints.get(tag, {})
	var sig: Signal = ep.get(error_type, Signal())
	if sig.is_null():
		return
	sig.emit(reason)

func _send_request(tag: String, path: String, method: int, body: String = "") -> int:
	var req_id := _request_counter
	_request_counter += 1
	_callbacks[req_id] = {"tag": tag, "retries": 0}

	if _busy:
		if _request_queue.size() < QUEUE_MAX:
			_request_queue.push_back({"tag": tag, "path": path, "method": method, "body": body, "authed": false})
		_callbacks.erase(req_id)
		return -1

	var full_url := base_url + path
	var headers: PackedStringArray = ["Content-Type: application/json", "Accept: application/json"]

	_busy = true
	_current_tag = tag

	var err := _http.request(full_url, headers, method, body)
	if err != OK:
		_busy = false
		_current_tag = ""
		if err == ERR_CANT_OPEN or err == ERR_CANT_CONNECT:
			if online:
				online = false
				disconnected.emit()
				kicked.emit()
		_callbacks.erase(req_id)
		_emit_error(tag, "network", "network_error")
		return -1

	return req_id

func _send_authed_request(tag: String, path: String, method: int, body: String = "") -> int:
	var req_id := _request_counter
	_request_counter += 1
	_callbacks[req_id] = {"tag": tag, "retries": 0}

	if _busy:
		if _request_queue.size() < QUEUE_MAX:
			_request_queue.push_back({"tag": tag, "path": path, "method": method, "body": body, "authed": true})
		_callbacks.erase(req_id)
		return -1

	var full_url := base_url + path
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer " + token,
	]

	_busy = true
	_current_tag = tag

	var err := _http.request(full_url, headers, method, body)
	if err != OK:
		_busy = false
		_current_tag = ""
		if err == ERR_CANT_OPEN or err == ERR_CANT_CONNECT:
			if online:
				online = false
				disconnected.emit()
				kicked.emit()
		_callbacks.erase(req_id)
		_emit_error(tag, "network", "network_error")
		return -1

	return req_id

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	_current_tag = ""
	_flush_queue()

	var req_id := -1
	var callback: Dictionary = {}
	for id in _callbacks:
		req_id = id
		callback = _callbacks[id]
		break
	_callbacks.erase(req_id)

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_network_error(callback.get("tag", ""))
		return

	var body_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(body_text) != OK:
		_handle_parse_error(callback.get("tag", ""))
		return

	var data: Dictionary = json.data

	if response_code >= 400:
		var error_msg: String = data.get("error", "request_failed")
		var tag: String = callback.get("tag", "")
		if tag == "login":
			login_failed.emit(error_msg)
		else:
			_emit_error(tag, "rejected", error_msg)
		return

	if not online:
		online = true
		connected.emit()

	_dispatch_response(callback.get("tag", ""), data)

func _dispatch_response(tag: String, data: Dictionary) -> void:
	var ep: Dictionary = _endpoints.get(tag, {})
	var cb: Callable = ep.get("response_cb", Callable())
	if cb.is_valid():
		cb.call(data)

func _handle_network_error(tag: String) -> void:
	if online:
		online = false
		disconnected.emit()
	_emit_error(tag, "network", "network_error")

func _handle_parse_error(tag: String) -> void:
	_emit_error(tag, "parse", "invalid_response")

# --- Storage ---

func submit_storage_deposit(storage_col: int, storage_row: int, item_id: int, from_col: int, from_row: int) -> void:
	var body := JSON.stringify({
		"storage_col": storage_col,
		"storage_row": storage_row,
		"item_id": item_id,
		"from_col": from_col,
		"from_row": from_row,
	})
	_send_authed_request("storage_deposit", "/api/game/storage/deposit", HTTPClient.Method.METHOD_POST, body)

func submit_storage_withdraw(storage_col: int, storage_row: int, uid: int, target_col: int, target_row: int) -> void:
	var body := JSON.stringify({
		"storage_col": storage_col,
		"storage_row": storage_row,
		"uid": uid,
		"target_col": target_col,
		"target_row": target_row,
	})
	_send_authed_request("storage_withdraw", "/api/game/storage/withdraw", HTTPClient.Method.METHOD_POST, body)

func _on_storage_withdraw_response(data: Dictionary) -> void:
	if data.get("ok", false):
		storage_withdraw_confirmed.emit(data)
		EventBus.show_toast.emit("取出成功")
	else:
		EventBus.show_toast.emit("取出失败：" + data.get("error", "unknown"))

# --- Shop ---

func fetch_shop_items() -> void:
	_send_authed_request("shop_items", "/api/game/shop/items", HTTPClient.Method.METHOD_GET)

func _on_shop_items_response(data: Dictionary) -> void:
	if data.has("items"):
		shop_items_loaded.emit(data.items)

func submit_buy(item_id: int, target_col: int, target_row: int) -> void:
	var body := JSON.stringify({"item_id": item_id, "target_col": target_col, "target_row": target_row})
	_send_authed_request("buy", "/api/game/shop/buy", HTTPClient.Method.METHOD_POST, body)

func submit_gm_exec(cmd: String, amount: int, item_id: int = 0, col: int = -1, row: int = -1) -> void:
	var body := JSON.stringify({"cmd": cmd, "amount": amount, "item_id": item_id, "col": col, "row": row})
	_send_authed_request("gm_exec", "/api/gm/exec", HTTPClient.Method.METHOD_POST, body)

func _on_gm_exec_response(data: Dictionary) -> void:
	if data.get("ok", false):
		gm_exec_confirmed.emit(data)
	else:
		gm_exec_rejected.emit(data.get("error", "unknown_error"))

func _on_buy_response(data: Dictionary) -> void:
	if data.get("ok", false):
		buy_confirmed.emit(data)
	else:
		buy_rejected.emit(data.get("error", "unknown"))

func submit_sell(uid: int) -> void:
	var body := JSON.stringify({"uid": uid})
	_send_authed_request("sell", "/api/game/shop/sell", HTTPClient.Method.METHOD_POST, body)

func _on_sell_response(data: Dictionary) -> void:
	if data.get("ok", false):
		GameState.spirit_stones = data.get("spirit_stones", GameState.spirit_stones)
		GameState.spirit_stones_changed.emit(GameState.spirit_stones)
		sell_confirmed.emit(data)
		EventBus.show_toast.emit("出售成功")
	else:
		sell_rejected.emit(data.get("error", "unknown"))
		EventBus.show_toast.emit("出售失败：" + data.get("error", "unknown"))

# --- Token persistence ---

func _save_token() -> void:
	var file := FileAccess.open("user://auth_token", FileAccess.WRITE)
	if file:
		file.store_string(token)
		file.close()

func load_saved_token() -> bool:
	var file := FileAccess.open("user://auth_token", FileAccess.READ)
	if file:
		token = file.get_as_text().strip_edges()
		file.close()
		return not token.is_empty()
	return false

func clear_token() -> void:
	token = ""
	var path := "user://auth_token"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
