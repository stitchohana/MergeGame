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
signal cultivate_tick_confirmed(result: Dictionary)
signal cultivate_tick_rejected(reason: String)
signal pill_consume_confirmed(result: Dictionary)
signal pill_consume_rejected(reason: String)
signal breakthrough_confirmed(result: Dictionary)
signal breakthrough_rejected(reason: String)
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
var cultivation_url: String = ""

var _http: HTTPRequest = null
var _timeout: float = 10.0
var _max_retries: int = 2
var _busy: bool = false
var _callbacks: Dictionary = {}
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
			cultivation_url = data.get("cultivation_url", base_url)
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

func submit_spawn(launcher_col: int, launcher_row: int, rolled_id: int, version: int) -> void:
	var body := JSON.stringify({
		"launcher_pos": [launcher_col, launcher_row],
		"rolled_id": rolled_id,
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

func submit_cultivate_tick(version: int) -> void:
	var body := JSON.stringify({"version": version})
	_send_cultivation("cultivate_tick", "/api/cultivation/tick", HTTPClient.METHOD_POST, body)

func submit_consume_pill(pill_id: int, version: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "version": version})
	_send_cultivation("consume_pill", "/api/cultivation/consume", HTTPClient.METHOD_POST, body)

func submit_breakthrough(pill_id: int, version: int) -> void:
	var body := JSON.stringify({"pill_id": pill_id, "version": version})
	_send_cultivation("breakthrough", "/api/cultivation/breakthrough", HTTPClient.METHOD_POST, body)

func _on_cultivate_tick_response(data: Dictionary) -> void:
	if data.get("ok", false):
		cultivate_tick_confirmed.emit(data)
	else:
		cultivate_tick_rejected.emit(data.get("error", "unknown_error"))

func _on_consume_pill_response(data: Dictionary) -> void:
	if data.get("ok", false):
		pill_consume_confirmed.emit(data)
	else:
		pill_consume_rejected.emit(data.get("error", "unknown_error"))

func _on_breakthrough_response(data: Dictionary) -> void:
	if data.get("ok", false):
		breakthrough_confirmed.emit(data)
	else:
		breakthrough_rejected.emit(data.get("error", "unknown_error"))

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

func _is_priority(tag: String) -> bool:
	return tag != "cultivate_tick"

func _reject(tag: String, reason: String) -> void:
	match tag:
		"spawn": spawn_rejected.emit(reason)
		"merge": merge_rejected.emit(reason)
		"move": move_rejected.emit(reason)
		"cultivate_tick": cultivate_tick_rejected.emit(reason)
		"consume_pill": pill_consume_rejected.emit(reason)
		"breakthrough": breakthrough_rejected.emit(reason)

func _send_request(tag: String, path: String, method: int, body: String = "") -> int:
	var req_id := _request_counter
	_request_counter += 1
	_callbacks[req_id] = {"tag": tag, "retries": 0}

	if _busy:
		if _is_priority(tag):
			# Priority request cancels any in-flight request
			_http.cancel_request()
			_callbacks.clear()
			_busy = false
		else:
			# Low-priority: silent skip (ticks retry on next timer)
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
		if _is_priority(tag):
			# Priority request cancels any in-flight request
			_http.cancel_request()
			_callbacks.clear()
			_busy = false
		else:
			# Low-priority: silent skip (ticks retry on next timer)
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

func _send_cultivation(tag: String, path: String, method: int, body: String = "") -> int:
	var req_id := _request_counter
	_request_counter += 1
	_callbacks[req_id] = {"tag": tag, "retries": 0}

	if _busy:
		if _is_priority(tag):
			_http.cancel_request()
			_callbacks.clear()
			_busy = false
		else:
			_callbacks.erase(req_id)
			return -1

	var full_url := cultivation_url + path
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
			"cultivate_tick":
				cultivate_tick_rejected.emit(error_msg)
			"consume_pill":
				pill_consume_rejected.emit(error_msg)
			"breakthrough":
				breakthrough_rejected.emit(error_msg)
			"craft_add":
				craft_add_rejected.emit(error_msg)
			"craft_start":
				craft_start_rejected.emit(error_msg)
			"craft_remove":
				craft_remove_rejected.emit(error_msg)
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
		"cultivate_tick":
			_on_cultivate_tick_response(data)
		"consume_pill":
			_on_consume_pill_response(data)
		"breakthrough":
			_on_breakthrough_response(data)
		"craft_add":
			_on_craft_add_response(data)
		"craft_start":
			_on_craft_start_response(data)
		"craft_remove":
			_on_craft_remove_response(data)
		"craft_retrieve":
			_on_craft_retrieve_response(data)

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
		"cultivate_tick":
			cultivate_tick_rejected.emit("network_error")
		"consume_pill":
			pill_consume_rejected.emit("network_error")
		"breakthrough":
			breakthrough_rejected.emit("network_error")
		"craft_add":
			craft_add_rejected.emit("network_error")
		"craft_start":
			craft_start_rejected.emit("network_error")
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
		"cultivate_tick":
			cultivate_tick_rejected.emit("invalid_response")
		"consume_pill":
			pill_consume_rejected.emit("invalid_response")
		"breakthrough":
			breakthrough_rejected.emit("invalid_response")
		"craft_add":
			craft_add_rejected.emit("invalid_response")
		"craft_start":
			craft_start_rejected.emit("invalid_response")
		"craft_retrieve":
			craft_retrieve_rejected.emit("invalid_response")
		"fetch_state":
			state_load_failed.emit("invalid_response")

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
