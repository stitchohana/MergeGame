class_name HomeScreen extends BaseScreen

@onready var game_btn: Button = $GameButton
@onready var battle_btn: Button = $BattleButton
@onready var cultivation_panel: CultivationPanel = $CultivationPanel
@onready var meridian_container: VBoxContainer = $MeridianContainer
@onready var meridian_title: Label
@onready var nodes_box: HBoxContainer

var _home_defs: Array = []
var _home_progress: Array = []
var _current_stage_idx: int = -1


func _ready() -> void:
	modulate = Color.TRANSPARENT
	game_btn.pressed.connect(_on_game_pressed)
	battle_btn.pressed.connect(_on_battle_pressed)
	cultivation_panel.cultivation_clicked.connect(_on_cultivation_clicked)
	CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.home_meridian_light_confirmed.connect(_on_light_confirmed)
	CloudService.breakthrough_confirmed.connect(_on_breakthrough_done)
	CloudService.breakthrough_rejected.connect(_on_breakthrough_rejected)
	CultivationService.exp_changed.connect(func(_c, _t): _refresh_breakthrough_btn())
	CultivationService.stage_changed.connect(func(_l, _n): _refresh_breakthrough_btn())
	_setup_meridian_ui()
	_setup_breakthrough_btn()
	if CloudService.online:
		CloudService.fetch_state()


func on_enter() -> void:
	modulate = Color.TRANSPARENT
	if CloudService.online:
		CloudService.fetch_state()


func _setup_meridian_ui() -> void:
	for child in meridian_container.get_children():
		child.queue_free()

	meridian_title = Label.new()
	meridian_title.add_theme_font_size_override("font_size", 16)
	meridian_title.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	meridian_container.add_child(meridian_title)

	nodes_box = HBoxContainer.new()
	nodes_box.add_theme_constant_override("separation", 12)
	meridian_container.add_child(nodes_box)


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("home_meridian_defs"):
		_home_defs = state.home_meridian_defs
	if state.has("home_meridian_progress"):
		_home_progress = state.home_meridian_progress
	_refresh_display()
	_refresh_breakthrough_btn()
	var fade := create_tween()
	fade.tween_property(self, "modulate", Color.WHITE, 0.15)


func _refresh_display() -> void:
	if CultivationService.is_breakthrough_ready():
		meridian_container.hide()
		return
	meridian_container.show()
	if _home_defs.is_empty():
		meridian_title.text = "经脉：无"
		return

	# Find first incomplete stage, or next after all completed
	var stage_idx: int = 0
	if _home_progress.size() > 0:
		stage_idx = _home_progress.size()
		for i in range(_home_progress.size()):
			var p: Dictionary = _home_progress[i]
			if not p.get("circulation_completed", false):
				stage_idx = i
				break
	if stage_idx >= _home_defs.size():
		stage_idx = _home_defs.size() - 1

	_current_stage_idx = stage_idx
	var def: Dictionary = _home_defs[stage_idx]

	var progress: Dictionary = {}
	for p in _home_progress:
		if p.get("stage", -1) == stage_idx:
			progress = p
			break

	var lit: Array = progress.get("lit", [])
	if lit.is_empty():
		lit = []
		for _i in range(def.get("acupoints", 0)):
			lit.append(false)

	meridian_title.text = def.get("name", "经脉")
	var qi_str: String = "灵气：%d/%d 消耗：%d" % [CultivationService.current_qi, CultivationService.max_qi, def.get("qi_cost", 0)]
	meridian_title.text += "\n" + qi_str

	# Update existing buttons, create/remove as needed
	var existing := nodes_box.get_children()
	var count := lit.size()
	while existing.size() > count:
		var extra: Node = existing.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	for i in range(count):
		var btn: Button
		if i < existing.size():
			btn = existing[i] as Button
			# Disconnect all existing connections before re-binding
			for conn in btn.pressed.get_connections():
				btn.pressed.disconnect(conn.callable)
		else:
			btn = Button.new()
			btn.custom_minimum_size = Vector2(40, 40)
			btn.add_theme_font_size_override("font_size", 18)
			nodes_box.add_child(btn)
		if lit[i]:
			btn.text = "●"
			btn.add_theme_color_override("font_color", Color(1, 0.75, 0.2, 1))
			btn.disabled = true
		else:
			btn.text = "○"
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
			btn.disabled = false
			btn.pressed.connect(_on_acupoint_pressed.bind(i))


func _on_acupoint_pressed(index: int) -> void:
	if _current_stage_idx < 0 or _home_defs.is_empty():
		return
	var def: Dictionary = _home_defs[_current_stage_idx]
	var qi_cost: int = def.get("qi_cost", 0)
	var title: String = def.get("name", "穴位") + " 第%d穴" % (index + 1)
	var cost: String = "消耗灵气：%d  当前：%d/%d" % [qi_cost, CultivationService.current_qi, CultivationService.max_qi]
	var popup := preload("res://scenes/ui/home/AcupointActivatePopup.tscn").instantiate() as AcupointActivatePopup
	UIManager.show_popup(popup)
	popup.setup(title, cost, def.get("acupoint_rewards", {}), "激活", func(): CloudService.submit_light_home_acupoint(_current_stage_idx, index))


func _on_light_confirmed(result: Dictionary) -> void:
	if result.has("home_meridian_progress"):
		_home_progress = result.home_meridian_progress
	if result.has("cultivation"):
		CultivationService.deserialize(result.cultivation)
	_refresh_display()


func _on_cultivation_clicked() -> void:
	pass


func _on_game_pressed() -> void:
	EventBus.screen_change_requested.emit("game")


func _on_battle_pressed() -> void:
	GameState.previous_screen_name = "home"
	EventBus.screen_change_requested.emit("battle")


func _setup_breakthrough_btn() -> void:
	var btn := Button.new()
	btn.name = "BreakthroughBtn"
	btn.text = ""
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_breakthrough_pressed)
	btn.visible = false
	btn.layout_mode = 0
	btn.offset_left = 200
	btn.offset_top = 1390
	btn.offset_right = 580
	btn.offset_bottom = 1430
	add_child(btn)

func _refresh_breakthrough_btn() -> void:
	var btn := get_node_or_null("BreakthroughBtn") as Button
	if not btn: return
	if CultivationService.is_breakthrough_ready():
		var pill_id: int = CultivationService.get_required_breakthrough_pill()
		if pill_id > 0:
			var pill_data := ConfigDatabase.get_item_data(pill_id)
			btn.text = "突破·" + pill_data.get("name", "丹药")
		else:
			btn.text = "突破"
		btn.visible = true
	else:
		btn.visible = false

func _on_breakthrough_pressed() -> void:
	var pill_id: int = CultivationService.get_required_breakthrough_pill()
	if pill_id > 0:
		var popup := preload("res://scenes/ui/common/ConfirmPopup.tscn").instantiate() as ConfirmPopup
		UIManager.show_popup(popup)
		var pill_data := ConfigDatabase.get_item_data(pill_id)
		popup.setup("突破确认", "确定使用" + pill_data.get("name", "丹药") + "进行突破吗？", func(): _do_breakthrough(pill_id))
	else:
		# No pill needed — just confirm
		var popup := preload("res://scenes/ui/common/ConfirmPopup.tscn").instantiate() as ConfirmPopup
		UIManager.show_popup(popup)
		popup.setup("突破确认", "确定进行突破吗？", func(): _do_breakthrough(0))

func _do_breakthrough(pill_id: int) -> void:
	CultivationService.try_breakthrough(pill_id, 0)

func _on_breakthrough_done(_result: Dictionary) -> void:
	_refresh_breakthrough_btn()
	_refresh_display()

func _on_breakthrough_rejected(reason: String) -> void:
	if reason == "pill_not_found":
		EventBus.show_toast.emit("当前没有该丹药")
