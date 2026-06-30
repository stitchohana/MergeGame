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
signal craft_add_rejected(reason: String)
signal craft_start_confirmed(result: Dictionary)
signal craft_start_rejected(reason: String)
signal craft_remove_confirmed(result: Dictionary)
signal craft_remove_rejected(reason: String)
signal craft_retrieve_confirmed(result: Dictionary)
signal craft_retrieve_rejected(reason: String)
signal state_loaded(state: Dictionary)
signal state_load_failed(reason: String)

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

func _ready() -> void:
	_load_config()
	_setup_http()

func _load_config() -> void:
	var file := FileAccess.open("res://config/server.json", FileAccess.READ)
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
	_send_request("login", "/api/auth/login", HTTPClient.METHOD_POST, body)

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
	_send_authed_request("fetch_state", "/api/game/state", HTTPClient.METHOD_GET)

func _on_fetch_state_response(data: Dictionary) -> void:
	state_loaded.emit(data)

# --- Merge ---

func submit_merge(from_col: int, from_row: int, to_col: int, to_row: int, version: int) -> void:
	var body := JSON.stringify({
		"from": [from_col, from_row],
		"to": [to_col, to_row],
		"version": version,
	})
	_send_authed_request("merge", "/api/game/merge", HTTPClient.METHOD_POST, body)

func _on_merge_response(data: Dictionary) -> void:
	if data.get("ok", false):
		merge_confirmed.emit(data)
	else:
		merge_rejected.emit(data.get("error", "unknown_error"))

# --- Spawn ---

func submit_spawn(launcher_col: int, launcher_row: int, version: int) -> void:
	var body := JSON.stringify({
		"launcher_pos": [launcher_col, launcher_row],
		"version": version,
	})
	_send_authed_request("spawn", "/api/game/spawn", HTTPClient.METHOD_POST, body)

func _on_spawn_response(data: Dictionary) -> void:
	if data.get("ok", false):
		spawn_confirmed.emit(data)
	else:
		spawn_rejected.emit(data.get("error", "unknown_error"))

func _on_move_response(data: Dictionary) -> void:
	if data.get("ok", false):
		move_confirmed.emit(data)
	else:
		move_rejected.emit(data.get("error", "unknown_error"))

# --- Move ---

func submit_move(from_col: int, from_row: int, to_col: int, to_row: int, version: int) -> void:
	var body := JSON.stringify({
		"from": [from_col, from_row],
		"to": [to_col, to_row],
		"version": version,
	})
	_send_authed_request("move", "/api/game/move", HTTPClient.METHOD_POST, body)

# --- Cultivation ---

func submit_breakthrough(pill_id: int, version: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "version": version})
	_send_authed_request("breakthrough", "/api/cultivation/breakthrough", HTTPClient.METHOD_POST, body)

func submit_consume_exp_pill(pill_id: int, version: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "version": version})
	_send_authed_request("consume_exp_pill", "/api/cultivation/consume-exp", HTTPClient.METHOD_POST, body)

func submit_restore_stamina(pill_id: int, uid: int, version: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "uid": uid, "version": version})
	_send_authed_request("restore_stamina", "/api/cultivation/consume-stamina", HTTPClient.METHOD_POST, body)

func submit_board_switch(board_type: String, map_id: int = 0, stage: int = 0) -> void:
	var body_data: Dictionary = {"board_type": board_type}
	if map_id > 0:
		body_data["map_id"] = map_id
	if stage > 0:
		body_data["stage"] = stage
	var body := JSON.stringify(body_data)
	_send_authed_request("board_switch", "/api/game/board/switch", HTTPClient.METHOD_POST, body)

func submit_pouch_deposit(uid: int) -> void:
	var body := JSON.stringify({"uid": uid})
	_send_authed_request("pouch_deposit", "/api/game/pouch/deposit", HTTPClient.METHOD_POST, body)

func submit_pouch_withdraw(item_id: int, target_col: int, target_row: int) -> void:
	var body := JSON.stringify({"item_id": item_id, "target_col": target_col, "target_row": target_row})
	_send_authed_request("pouch_withdraw", "/api/game/pouch/withdraw", HTTPClient.METHOD_POST, body)

signal battle_attack_confirmed(result: Dictionary)
signal battle_attack_rejected(reason: String)

func submit_battle_attack(item_id: int, effect_id: int, col: int, row: int) -> void:
	var body := JSON.stringify({"item_id": item_id, "effect_id": effect_id, "col": col, "row": row})
	_send_authed_request("battle_attack", "/api/game/battle/attack", HTTPClient.METHOD_POST, body)

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
	_send_authed_request("meridian_refresh", "/api/game/meridian/refresh", HTTPClient.METHOD_POST, "{}")

func _on_meridian_refresh_response(data: Dictionary) -> void:
	if data.get("ok", false):
		meridian_refresh_confirmed.emit(data)

func submit_meridian_complete(index: int, item_ids: Array) -> void:
	var body := JSON.stringify({"index": index, "item_ids": item_ids})
	_send_authed_request("meridian_complete", "/api/game/meridian/complete", HTTPClient.METHOD_POST, body)

func _on_meridian_complete_response(data: Dictionary) -> void:
	if data.get("ok", false):
		meridian_complete_confirmed.emit(data)
	else:
		meridian_complete_rejected.emit(data.get("error", "unknown_error"))

func _on_breakthrough_response(data: Dictionary) -> void:
	if data.get("ok", false):
		breakthrough_confirmed.emit(data)
	else:
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

func submit_craft_add(from_col: int, from_row: int, table_col: int, table_row: int, ingredient_id: int, version: int) -> void:
	var body := JSON.stringify({
		"from_col": from_col,
		"from_row": from_row,
		"table_col": table_col,
		"table_row": table_row,
		"ingredient_id": ingredient_id,
		"version": version,
	})
	_send_authed_request("craft_add", "/api/game/craft/add", HTTPClient.METHOD_POST, body)

func _on_craft_add_response(data: Dictionary) -> void:
	if data.get("ok", false):
		craft_add_confirmed.emit(data)
	else:
		craft_add_rejected.emit(data.get("error", "unknown_error"))

func submit_craft_start(table_col: int, table_row: int, version: int) -> void:
	var body := JSON.stringify({
		"table_col": table_col,
		"table_row": table_row,
		"version": version,
	})
	_send_authed_request("craft_start", "/api/game/craft/start", HTTPClient.METHOD_POST, body)

func _on_craft_start_response(data: Dictionary) -> void:
	if data.get("ok", false):
		craft_start_confirmed.emit(data)
	else:
		craft_start_rejected.emit(data.get("error", "unknown_error"))

func submit_craft_remove(table_col: int, table_row: int, ingredient_id: int, target_col: int, target_row: int, version: int) -> void:
	var body := JSON.stringify({
		"table_col": table_col,
		"table_row": table_row,
		"ingredient_id": ingredient_id,
		"target_col": target_col,
		"target_row": target_row,
		"version": version,
	})
	_send_authed_request("craft_remove", "/api/game/craft/remove", HTTPClient.METHOD_POST, body)

func submit_craft_retrieve(table_col: int, table_row: int, version: int) -> void:
	var body := JSON.stringify({
		"table_col": table_col,
		"table_row": table_row,
		"version": version,
	})
	_send_authed_request("craft_retrieve", "/api/game/craft/retrieve", HTTPClient.METHOD_POST, body)

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
	_send_authed_request("leaderboard", "/api/game/leaderboard?limit=" + str(limit), HTTPClient.METHOD_GET)

# --- Internal ---

var _request_counter: int = 0

func _flush_queue() -> void:
	if _busy or _request_queue.is_empty():
		return
	var req: Dictionary = _request_queue.pop_front()
	if req.get("authed", false):
		_send_authed_request(req.tag, req.path, req.method, req.body)
	else:
		_send_request(req.tag, req.path, req.method, req.body)

func _reject(tag: String, reason: String) -> void:
	match tag:
		"spawn": spawn_rejected.emit(reason)
		"merge": merge_rejected.emit(reason)
		"move": move_rejected.emit(reason)
		"breakthrough": breakthrough_rejected.emit(reason)
		"consume_exp_pill": exp_pill_consume_rejected.emit(reason)
		"restore_stamina": stamina_restore_rejected.emit(reason)
		"pouch_deposit": pouch_deposit_rejected.emit(reason)
		"pouch_withdraw": pouch_withdraw_rejected.emit(reason)
		"battle_attack": battle_attack_rejected.emit(reason)
		"sell": sell_rejected.emit(reason)
		"craft_add": craft_add_rejected.emit(reason)
		"craft_start": craft_start_rejected.emit(reason)
		"craft_remove": craft_remove_rejected.emit(reason)
		"craft_retrieve": craft_retrieve_rejected.emit(reason)
		"fetch_state": state_load_failed.emit(reason)
		"leaderboard": pass

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
		_reject(tag, "network_error")
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
		_reject(tag, "network_error")
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
		match callback.get("tag", ""):
			"login":
				login_failed.emit(error_msg)
			"merge":
				merge_rejected.emit(error_msg)
			"spawn":
				spawn_rejected.emit(error_msg)
			"move":
				move_rejected.emit(error_msg)
			"breakthrough":
				breakthrough_rejected.emit(error_msg)
			"consume_exp_pill":
				exp_pill_consume_rejected.emit(error_msg)
			"board_switch":
				board_switch_rejected.emit(error_msg)
			"pouch_deposit":
				pouch_deposit_rejected.emit(error_msg)
			"pouch_withdraw":
				pouch_withdraw_rejected.emit(error_msg)
			"battle_attack":
				battle_attack_rejected.emit(error_msg)
			"restore_stamina":
				stamina_restore_rejected.emit(error_msg)
			"meridian_complete":
				meridian_complete_rejected.emit(error_msg)
			"craft_add":
				craft_add_rejected.emit(error_msg)
			"craft_start":
				craft_start_rejected.emit(error_msg)
			"craft_remove":
				craft_remove_rejected.emit(error_msg)
			"craft_retrieve":
				craft_retrieve_rejected.emit(error_msg)
			"fetch_state":
				state_load_failed.emit(error_msg)
		return

	if not online:
		online = true
		connected.emit()

	_dispatch_response(callback.get("tag", ""), data)

func _dispatch_response(tag: String, data: Dictionary) -> void:
	match tag:
		"login":
			_on_login_response(data)
		"fetch_state":
			_on_fetch_state_response(data)
		"merge":
			_on_merge_response(data)
		"spawn":
			_on_spawn_response(data)
		"move":
			_on_move_response(data)
		"breakthrough":
			_on_breakthrough_response(data)
		"consume_exp_pill":
			_on_consume_exp_pill_response(data)
		"board_switch":
			_on_board_switch_response(data)
		"pouch_deposit":
			_on_pouch_deposit_response(data)
		"pouch_withdraw":
			_on_pouch_withdraw_response(data)
		"battle_attack":
			_on_battle_attack_response(data)
		"restore_stamina":
			_on_restore_stamina_response(data)
		"meridian_complete":
			_on_meridian_complete_response(data)
		"meridian_refresh":
			_on_meridian_refresh_response(data)
		"craft_add":
			_on_craft_add_response(data)
		"craft_start":
			_on_craft_start_response(data)
		"craft_remove":
			_on_craft_remove_response(data)
		"craft_retrieve":
			_on_craft_retrieve_response(data)
		"sell":
			_on_sell_response(data)
		"shop_items":
			_on_shop_items_response(data)
		"buy":
			_on_buy_response(data)

func _handle_network_error(tag: String) -> void:
	if online:
		online = false
		disconnected.emit()

	match tag:
		"login":
			login_failed.emit("network_error")
		"merge":
			merge_rejected.emit("network_error")
		"spawn":
			spawn_rejected.emit("network_error")
		"move":
			move_rejected.emit("network_error")
		"breakthrough":
			breakthrough_rejected.emit("network_error")
		"consume_exp_pill":
			exp_pill_consume_rejected.emit("network_error")
		"board_switch":
			board_switch_rejected.emit("network_error")
		"pouch_deposit":
			pouch_deposit_rejected.emit("network_error")
		"pouch_withdraw":
			pouch_withdraw_rejected.emit("network_error")
		"battle_attack":
			battle_attack_rejected.emit("network_error")
		"restore_stamina":
			stamina_restore_rejected.emit("network_error")
		"meridian_complete":
			meridian_complete_rejected.emit("network_error")
		"sell":
			sell_rejected.emit("network_error")
		"craft_add":
			craft_add_rejected.emit("network_error")
		"craft_start":
			craft_start_rejected.emit("network_error")
		"craft_remove":
			craft_remove_rejected.emit("network_error")
		"craft_retrieve":
			craft_retrieve_rejected.emit("network_error")
		"fetch_state":
			state_load_failed.emit("network_error")

func _handle_parse_error(tag: String) -> void:
	match tag:
		"login":
			login_failed.emit("invalid_response")
		"merge":
			merge_rejected.emit("invalid_response")
		"spawn":
			spawn_rejected.emit("invalid_response")
		"move":
			move_rejected.emit("invalid_response")
		"breakthrough":
			breakthrough_rejected.emit("invalid_response")
		"consume_exp_pill":
			exp_pill_consume_rejected.emit("invalid_response")
		"board_switch":
			board_switch_rejected.emit("invalid_response")
		"pouch_deposit":
			pouch_deposit_rejected.emit("invalid_response")
		"pouch_withdraw":
			pouch_withdraw_rejected.emit("invalid_response")
		"battle_attack":
			battle_attack_rejected.emit("invalid_response")
		"restore_stamina":
			stamina_restore_rejected.emit("invalid_response")
		"meridian_complete":
			meridian_complete_rejected.emit("invalid_response")
		"sell":
			sell_rejected.emit("invalid_response")
		"craft_add":
			craft_add_rejected.emit("invalid_response")
		"craft_start":
			craft_start_rejected.emit("invalid_response")
		"craft_remove":
			craft_remove_rejected.emit("invalid_response")
		"craft_retrieve":
			craft_retrieve_rejected.emit("invalid_response")
		"fetch_state":
			state_load_failed.emit("invalid_response")

signal storage_withdraw_confirmed(result: Dictionary)

# --- Storage ---

func submit_storage_deposit(storage_col: int, storage_row: int, item_id: int, from_col: int, from_row: int) -> void:
	var body := JSON.stringify({
		"storage_col": storage_col,
		"storage_row": storage_row,
		"item_id": item_id,
		"from_col": from_col,
		"from_row": from_row,
	})
	_send_authed_request("storage_deposit", "/api/game/storage/deposit", HTTPClient.METHOD_POST, body)

func submit_storage_withdraw(storage_col: int, storage_row: int, item_id: int, target_col: int, target_row: int) -> void:
	var body := JSON.stringify({
		"storage_col": storage_col,
		"storage_row": storage_row,
		"item_id": item_id,
		"target_col": target_col,
		"target_row": target_row,
	})
	_send_authed_request("storage_withdraw", "/api/game/storage/withdraw", HTTPClient.METHOD_POST, body)

func _on_storage_withdraw_response(data: Dictionary) -> void:
	if data.get("ok", false):
		storage_withdraw_confirmed.emit(data)
		EventBus.show_toast.emit("取出成功")
	else:
		EventBus.show_toast.emit("取出失败：" + data.get("error", "unknown"))

# --- Shop ---

func fetch_shop_items() -> void:
	_send_authed_request("shop_items", "/api/game/shop/items", HTTPClient.METHOD_GET)

func _on_shop_items_response(data: Dictionary) -> void:
	if data.has("items"):
		shop_items_loaded.emit(data.items)

func submit_buy(item_id: int, target_col: int, target_row: int) -> void:
	var body := JSON.stringify({"item_id": item_id, "target_col": target_col, "target_row": target_row})
	_send_authed_request("buy", "/api/game/shop/buy", HTTPClient.METHOD_POST, body)

func _on_buy_response(data: Dictionary) -> void:
	if data.get("ok", false):
		buy_confirmed.emit(data)
	else:
		buy_rejected.emit(data.get("error", "unknown"))

func submit_sell(uid: int) -> void:
	var body := JSON.stringify({"uid": uid})
	_send_authed_request("sell", "/api/game/shop/sell", HTTPClient.METHOD_POST, body)

signal sell_confirmed(spirit_stones: int)
signal sell_rejected(reason: String)
signal shop_items_loaded(items: Array)
signal buy_confirmed(result: Dictionary)
signal buy_rejected(reason: String)

func _on_sell_response(data: Dictionary) -> void:
	if data.get("ok", false):
		GameState.spirit_stones = data.get("spirit_stones", GameState.spirit_stones)
		GameState.spirit_stones_changed.emit(GameState.spirit_stones)
		sell_confirmed.emit(GameState.spirit_stones)
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
