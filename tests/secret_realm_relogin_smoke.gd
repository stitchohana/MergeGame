extends Node

var _kicks: int = 0
var _logins: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.codex_tmp/realm-http.json"))
	CloudService.configure(str(fixture.base_url))
	CloudService.token = str(fixture.token)
	CloudService.online = true
	CloudService.kicked.connect(_on_kicked)
	CloudService.login_success.connect(func(_id: String) -> void: _logins += 1)
	add_child(preload("res://scenes/Main.tscn").instantiate())
	await _wait_for_home(0)
	var panel := preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(panel)
	panel.setup()
	for frame: int in range(600):
		if bool(panel._view.get("initialized", false)):
			break
		await get_tree().process_frame
	assert(panel._view.get("initialized", false))
	assert(panel.find_children("*", "Button", true, false).all(func(button: Button) -> bool: return button.text != "重试操作"))
	var view: Dictionary = panel._view.duplicate(true)
	CloudService.secret_realm_revision = 500
	CloudService._send_authed_request("secret_realm", "/api/game/late-realm", HTTPClient.METHOD_GET)
	assert(not CloudService._query_requests.is_empty())
	CloudService.submit_secret_realm({"action":"move", "period":view.period, "version":int(view.version)+1, "uid":int(view.cells[0].item.uid), "col":0, "row":1, "request_id":"relogin-conflict"})
	CloudService._send_authed_request("secret_realm", "/api/game/secret_realm/action", HTTPClient.METHOD_POST, "{}")
	assert(CloudService._request_queue.size() == 1)
	# A failed authoritative reload stays on login; it must never resume offline.
	for frame: int in range(900):
		var current: BaseScreen = UIManager.get_current_screen()
		if _logins == 1 and current is LoginScreen and not current.login_btn.disabled:
			break
		await get_tree().process_frame
	var login: LoginScreen = UIManager.get_current_screen() as LoginScreen
	assert(login != null and _logins == 1 and not login.login_btn.disabled)
	assert(not CloudService.online and CloudService.token.is_empty() and CloudService.session_restore_required)
	login._on_login()
	await _wait_for_home(2)
	assert(_kicks == 1 and not CloudService.token.is_empty() and CloudService.online)
	assert(CloudService.secret_realm_retry.is_empty() and not CloudService.secret_realm_busy)
	assert(CloudService.secret_realm_revision < 500)
	assert(int(CloudService.secret_realm_state.version) == int(view.version))
	assert(UIManager._active_popups.is_empty() and UIManager._closing_popups.is_empty())
	assert(not is_instance_valid(panel))
	await get_tree().create_timer(0.8).timeout
	assert(int(CloudService.secret_realm_state.version) == int(view.version), "cancelled old HTTP query cannot overwrite the new session")
	# A business rejection remains in the session, with no automatic relogin.
	CloudService._emit_error("secret_realm", "rejected", "wrong_submission")
	await get_tree().process_frame
	assert(_kicks == 1 and CloudService.online)
	# Unknown mutation results must also re-read authoritative state through login.
	CloudService.secret_realm_retry = {"request_id":"uncertain-mutation"}
	CloudService.secret_realm_failed.emit("save_failed")
	await _wait_for_home(3)
	assert(_kicks == 2 and CloudService.secret_realm_retry.is_empty())
	# Conflict responses from the preview and other game operations share this path.
	CloudService._handle_response("secret_realm_preview", HTTPRequest.RESULT_SUCCESS, 409, '{"error":"state_conflict"}'.to_utf8_buffer())
	await _wait_for_home(4)
	CloudService._handle_response("action_batch", HTTPRequest.RESULT_SUCCESS, 409, '{"error":"state_conflict"}'.to_utf8_buffer())
	await _wait_for_home(5)
	assert(_kicks == 4)
	print("SECRET_REALM_RELOGIN_SMOKE_OK: no retry button, HTTP conflict, auto-login and authoritative restore, reload failure stays on login, queue/query cancellation, duplicate/late reply guards, uncertain mutation, business rejection, preview and batch conflict")
	get_tree().quit()


func _on_kicked() -> void:
	_kicks += 1
	assert(not CloudService.online and CloudService.token.is_empty())
	assert(CloudService.relogin_pending and CloudService._request_queue.is_empty() and CloudService._query_requests.is_empty())
	assert(CloudService.secret_realm_state.is_empty() and CloudService.secret_realm_revision == -1)
	CloudService.force_relogin() # Duplicate conflicts produce one login transition.
	CloudService._handle_response("secret_realm", HTTPRequest.RESULT_SUCCESS, 200, '{"storage_revision":999,"secret_realm":{"version":999}}'.to_utf8_buffer())
	CloudService._on_query_request_completed(HTTPRequest.RESULT_SUCCESS, 200, [], '{}'.to_utf8_buffer(), 99999)
	assert(not CloudService.online and CloudService.secret_realm_state.is_empty())


func _wait_for_home(logins: int) -> void:
	for frame: int in range(1800):
		var top: BaseScreen = UIManager.get_current_screen()
		if _logins >= logins and top != null and top.name == "HomeScreen" and not SceneTransitionManager._is_loading and not CloudService.relogin_pending:
			return
		await get_tree().process_frame
	assert(false, "auto-login did not restore the home screen")
