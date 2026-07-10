class_name GMPanel extends BasePopup

@onready var cmd_option: OptionButton = $Panel/CmdOption
@onready var amount_spin: SpinBox = $Panel/AmountSpin
@onready var exec_btn: Button = $Panel/ExecButton
@onready var result_label: Label = $Panel/ResultLabel
@onready var close_btn: Button = $Panel/CloseButton

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	if exec_btn:
		exec_btn.pressed.connect(_on_exec)
	CloudService.gm_exec_confirmed.connect(_on_gm_confirmed)
	_populate_cmds()
	CloudService.gm_exec_rejected.connect(_on_gm_rejected)

func _populate_cmds() -> void:
	if cmd_option.item_count > 0:
		cmd_option.select(0)
		return
	var cmds := ["增加经验", "增加灵石", "设置体力", "设置灵力", "升级", "突破", "添加道具", "重置发射器CD"]
	for c in cmds:
		cmd_option.add_item(c)
	cmd_option.select(0)

func _on_exec() -> void:
	if exec_btn:
		exec_btn.disabled = true
	if cmd_option.selected < 0:
		result_label.text = "请选择功能"
		if exec_btn: exec_btn.disabled = false
		return
	var cmd: String = cmd_option.get_item_text(cmd_option.selected)
	var cmd_key := ""
	var item_id := 0
	var col := -1
	var row := -1
	match cmd:
		"增加经验": cmd_key = "add_exp"
		"增加灵石": cmd_key = "add_stones"
		"设置体力": cmd_key = "set_stamina"
		"设置灵力": cmd_key = "set_qi"
		"升级": cmd_key = "levelup"
		"突破": cmd_key = "breakthrough"
		"添加道具":
			cmd_key = "add_item"
			item_id = int(amount_spin.value)
		"重置发射器CD": cmd_key = "reset_launcher_cd"
	var amount: int = 1 if cmd == "添加道具" else int(amount_spin.value)
	result_label.text = "执行中..."
	CloudService.submit_gm_exec(cmd_key, amount, item_id, col, row)

func _on_gm_confirmed(result: Dictionary) -> void:
	if exec_btn:
		exec_btn.disabled = false
	result_label.text = result.get("msg", "ok")
	if not CloudService.state_loaded.is_connected(_on_state_synced):
		CloudService.state_loaded.connect(_on_state_synced, CONNECT_ONE_SHOT)
	CloudService.fetch_state()

func _on_gm_rejected(reason: String) -> void:
	if exec_btn:
		exec_btn.disabled = false
	result_label.text = "失败: " + reason

func _on_state_synced(state: Dictionary) -> void:
	var cult = state.get("cultivation", {})
	print("[GM] synced: level=" + str(cult.get("current_level", -1)) + " exp=" + str(cult.get("current_exp", -1)) + " max_qi=" + str(cult.get("max_qi", -1)))
	SaveManager._restore_from_server(state)

func _on_close() -> void:
	UIManager.hide_popup(self)
