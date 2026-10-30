class_name GMPanel extends BasePopup

const COMMAND_LABELS: Array[String] = [
	"增加经验", "增加灵石", "增加战令积分", "设置体力", "设置灵力", "升级", "突破", "添加道具",
	"重置发射器CD", "激活穴位节点", "下发订单道具", "刷新所有订单", "清理所有棋盘普通物品",
	"一键领取所有暂存物品", "一键合成棋盘所有物品", "添加秘境飞剑",
]

@onready var command_grid: GridContainer = $Panel/CommandGrid
@onready var amount_spin: SpinBox = $Panel/AmountSpin
@onready var level_spin: SpinBox = $Panel/LevelSpin
@onready var level_label: Label = $Panel/LevelLabel
@onready var amount_label: Label = $Panel/AmountLabel
@onready var exec_btn: Button = $Panel/ExecButton
@onready var result_label: Label = $Panel/ResultLabel
@onready var close_btn: Button = $Panel/CloseButton

var command_buttons: Array[CheckBox] = []
var _selected_command: int = -1

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)
	if exec_btn:
		exec_btn.pressed.connect(_on_exec)
	CloudService.gm_exec_confirmed.connect(_on_gm_confirmed)
	CloudService.gm_exec_rejected.connect(_on_gm_rejected)
	CloudService.state_loaded.connect(_on_state_sync)
	_populate_cmds()


func _on_cmd_selected(index: int) -> void:
	if index < 0 or index >= COMMAND_LABELS.size():
		return
	_selected_command = index
	for button_index: int in range(command_buttons.size()):
		command_buttons[button_index].set_pressed_no_signal(button_index == index)
	var cmd: String = COMMAND_LABELS[index]
	var realm_swords: bool = cmd == "添加秘境飞剑"
	level_spin.visible = realm_swords
	level_label.visible = realm_swords
	amount_label.text = "数量（把）" if realm_swords else "数值"
	amount_spin.min_value = 1.0 if realm_swords else 0.0
	amount_spin.max_value = 1000.0 if realm_swords else 999999.0
	if realm_swords:
		amount_spin.value = 1.0
	amount_spin.editable = cmd not in ["清理所有棋盘普通物品", "一键领取所有暂存物品", "一键合成棋盘所有物品"]
	if cmd in ["激活穴位节点", "下发订单道具", "刷新所有订单", "清理所有棋盘普通物品", "一键领取所有暂存物品", "一键合成棋盘所有物品"]:
		amount_spin.value = 1.0

func _populate_cmds() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for index: int in range(COMMAND_LABELS.size()):
		var option: CheckBox = CheckBox.new()
		option.text = COMMAND_LABELS[index]
		option.button_group = group
		option.custom_minimum_size = Vector2(302, 48)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_font_size_override("font_size", 22)
		option.pressed.connect(_on_cmd_selected.bind(index))
		command_grid.add_child(option)
		command_buttons.append(option)
	_on_cmd_selected(0)

func _on_exec() -> void:
	if exec_btn:
		exec_btn.disabled = true
	if _selected_command < 0:
		result_label.text = "请选择功能"
		if exec_btn: exec_btn.disabled = false
		return
	var cmd: String = COMMAND_LABELS[_selected_command]
	var cmd_key := ""
	var item_id := 0
	var col := -1
	var row := -1
	match cmd:
		"增加经验": cmd_key = "add_exp"
		"增加灵石": cmd_key = "add_stones"
		"增加战令积分": cmd_key = "add_battle_pass_points"
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
		"清理所有棋盘普通物品": cmd_key = "clear_board_items"
		"一键领取所有暂存物品": cmd_key = "claim_all_pending_items"
		"一键合成棋盘所有物品": cmd_key = "merge_all_board_items"
		"添加秘境飞剑": cmd_key = "add_secret_realm_swords"
	var amount: int = 1 if cmd in ["添加道具", "下发订单道具", "刷新所有订单", "清理所有棋盘普通物品", "一键领取所有暂存物品", "一键合成棋盘所有物品"] else int(amount_spin.value)
	result_label.text = "执行中..."
	CloudService.submit_gm_exec(cmd_key, amount, item_id, col, row, int(level_spin.value) if cmd == "添加秘境飞剑" else 0)

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
	RewardManager.sync_pending(state)

	# Repopulate grid for current board
	var is_battle := GameState.current_board_type == Constants.BoardType.BATTLE
	var grid_data: Array = GameState.battle_grid_cache if is_battle else GameState.main_grid_cache
	if state.has("battle_grid" if is_battle else "main_grid"):
		GridManager.init_grid(GameState.current_board_type)
		GridManager._skip_anims = true
		GridManager.populate_from_server(grid_data)
		GridManager._skip_anims = false
	print("[PlayerAction] gm_sync")

func _on_close() -> void:
	UIManager.hide_popup(self)
