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
	if cmd_option:
		cmd_option.item_selected.connect(_on_cmd_selected)
	CloudService.gm_exec_confirmed.connect(_on_gm_confirmed)
	CloudService.gm_exec_rejected.connect(_on_gm_rejected)
	CloudService.state_loaded.connect(_on_state_sync)
	_populate_cmds()


func _on_cmd_selected(index: int) -> void:
	var cmd: String = cmd_option.get_item_text(index)
	if cmd in ["激活穴位节点", "下发订单道具", "刷新所有订单"]:
		amount_spin.value = 1.0

func _populate_cmds() -> void:
	if cmd_option.item_count > 0:
		cmd_option.select(0)
		return
	var cmds := ["增加经验", "增加灵石", "设置体力", "设置灵力", "升级", "突破", "添加道具", "重置发射器CD", "激活穴位节点", "下发订单道具", "刷新所有订单"]
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
		"激活穴位节点": cmd_key = "activate_home_acupoints"
		"下发订单道具": cmd_key = "grant_order_items"
		"刷新所有订单": cmd_key = "refresh_orders"
	var amount: int = 1 if cmd in ["添加道具", "下发订单道具", "刷新所有订单"] else int(amount_spin.value)
	result_label.text = "执行中..."
	CloudService.submit_gm_exec(cmd_key, amount, item_id, col, row)

func _on_gm_confirmed(_result: Dictionary) -> void:
	if exec_btn:
		exec_btn.disabled = false
	result_label.text = _result.get("msg", "ok")
	CloudService.fetch_state()

func _on_gm_rejected(reason: String) -> void:
	if exec_btn:
		exec_btn.disabled = false
	result_label.text = "失败: " + reason

func _on_state_sync(state: Dictionary) -> void:
	var cult = state.get("cultivation", {})
	if not cult.is_empty():
		CultivationService.deserialize(cult)
	var stam: int = state.get("stamina", -1)
	if stam >= 0:
		GameState.stamina = stam
		GameState.max_stamina = state.get("max_stamina", GameState.max_stamina)
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	var stones: int = state.get("spirit_stones", -1)
	if stones >= 0:
		GameState.spirit_stones = stones
		GameState.spirit_stones_changed.emit(stones)

	# Update grid caches
	GameState.main_grid_cache = state.get("main_grid", [])
	GameState.battle_grid_cache = state.get("battle_grid", [])

	# Repopulate grid for current board
	var is_battle := GameState.current_board_type == Constants.BoardType.BATTLE
	var grid_data: Array = GameState.battle_grid_cache if is_battle else GameState.main_grid_cache
	if not grid_data.is_empty():
		GridManager.init_grid()
		GridManager._skip_anims = true
		GridManager.populate_from_server(grid_data)
		GridManager._skip_anims = false
	print("[GM] synced")

func _on_close() -> void:
	UIManager.hide_popup(self)
