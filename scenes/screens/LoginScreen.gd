class_name LoginScreen extends BaseScreen

@onready var device_input: LineEdit = $DeviceInput
@onready var login_btn: Button = $LoginButton
@onready var status_label: Label = $StatusLabel
@onready var back_btn: Button = $BackButton

func _ready() -> void:
	# Generate or load device ID
	var device_id := _get_device_id()
	device_input.text = device_id

	if login_btn:
		login_btn.pressed.connect(_on_login)
	if back_btn:
		back_btn.pressed.connect(_on_back)

	CloudService.login_success.connect(_on_login_success)
	CloudService.login_failed.connect(_on_login_failed)

func on_enter() -> void:
	# If already logged in, skip to game
	if not CloudService.token.is_empty():
		_status("已有登录凭证，拉取存档...")
		CloudService.fetch_state()
		CloudService.state_loaded.connect(_on_state_loaded_for_skip, CONNECT_ONE_SHOT)
		CloudService.state_load_failed.connect(_on_state_load_failed_skip, CONNECT_ONE_SHOT)
	else:
		_status("请输入设备ID或使用自动生成的ID登录")

func _get_device_id() -> String:
	var path := "user://device_id"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var id := file.get_as_text().strip_edges()
			file.close()
			if not id.is_empty():
				return id
	# Generate new device ID
	var id := "device_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(id)
		file.close()
	return id

func _status(msg: String) -> void:
	if status_label:
		status_label.text = msg
		print("[LoginScreen] ", msg)

func _on_login() -> void:
	var device_id := device_input.text.strip_edges()
	if device_id.is_empty():
		_status("设备ID不能为空")
		return

	login_btn.disabled = true
	_status("正在连接服务器...")
	CloudService.login(device_id)

func _on_login_success(user_id: String) -> void:
	_status("登录成功，拉取游戏存档...")
	CloudService.fetch_state()
	# Connect state load result
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)
	if not CloudService.state_load_failed.is_connected(_on_state_load_failed):
		CloudService.state_load_failed.connect(_on_state_load_failed)

func _on_state_loaded(state: Dictionary) -> void:
	print("[LoginScreen] Game state loaded, version: ", state.get("version", 0))
	_disconnect_state_signals()

	var old_realm := CultivationService.current_realm_id
	var old_level := CultivationService.current_level
	var old_total := CultivationService.total_exp
	var offline_exp : float = state.get("offline_exp_gained", 0)

	SaveManager._restore_from_server(state)
	var offline_msg := _format_offline_gains(old_realm, old_level, old_total, offline_exp)

	SceneTransitionManager.load_scene_and_replace(
		"res://scenes/screens/HomeScreen.tscn",
		UIManager.Transition.FADE,
		func(): EventBus.show_toast.emit(offline_msg)
	)

func _on_state_loaded_for_skip(state: Dictionary) -> void:
	print("[LoginScreen] Auto-login, game state version: ", state.get("version", 0))
	_disconnect_state_signals()

	var old_realm := CultivationService.current_realm_id
	var old_level := CultivationService.current_level
	var old_total := CultivationService.total_exp
	var offline_exp : float = state.get("offline_exp_gained", 0)
	var old_tick: float = CultivationService.last_tick_time

	SaveManager._restore_from_server(state)
	var offline_msg := _format_offline_gains(old_realm, old_level, old_total, offline_exp)

	SceneTransitionManager.load_scene_and_replace(
		"res://scenes/screens/HomeScreen.tscn",
		UIManager.Transition.FADE,
		func(): EventBus.show_toast.emit(offline_msg)
	)

func _format_offline_gains(old_realm: int, old_level: int, old_total: int, offline_exp: int = 0) -> String:
	var exp_gained := offline_exp
	var realm_up := CultivationService.current_realm_id > old_realm
	var level_up := CultivationService.current_level > old_level and CultivationService.current_realm_id == old_realm

	var parts: PackedStringArray = []

	# Always show current realm/level
	var fmt_lv: String = CultivationService.get_formatted_realm_level()
	parts.append("当前：%s" % fmt_lv)

	if realm_up:
		parts.append("突破至%s" % CultivationService.get_realm_name())
	if level_up:
		parts.append("升至%s Lv%d" % [CultivationService.get_realm_name(), CultivationService.current_level])
	if exp_gained > 0:
		parts.append("获得%d经验" % exp_gained)

	var msg: String = "、".join(parts)
	print("[LoginScreen] ", msg)
	return msg

func _on_state_load_failed(reason: String) -> void:
	print("[LoginScreen] State load failed: ", reason)
	_disconnect_state_signals()

	if CloudService.token.is_empty():
		# New login failed
		login_btn.disabled = false
		_status("加载失败: " + reason)
	else:
		# Already had token but state load failed — still allow entering title
		_status("存档加载失败，进入离线模式")
		SceneTransitionManager.load_scene_and_replace("res://scenes/screens/HomeScreen.tscn")

func _on_state_load_failed_skip(reason: String) -> void:
	_on_state_load_failed(reason)

func _on_login_failed(reason: String) -> void:
	login_btn.disabled = false
	_status("登录失败: " + reason)

func _on_back() -> void:
	UIManager.pop_screen()

func _disconnect_state_signals() -> void:
	if CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.disconnect(_on_state_loaded)
	if CloudService.state_load_failed.is_connected(_on_state_load_failed):
		CloudService.state_load_failed.disconnect(_on_state_load_failed)
