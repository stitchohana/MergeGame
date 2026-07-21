class_name HomeScreen extends BaseScreen

@onready var game_btn: Button = $GameButton
@onready var battle_btn: Button = $BattleButton
@onready var realm_label: Label = $RealmLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var exp_label: Label = $ExpLabel
@onready var meridian_container: VBoxContainer = $MeridianContainer
@onready var acupoint_layer: Control = $AcupointLayer
@onready var meridian_title: Label

var acupoint_nodes: Array[AcupointNode] = []

var _home_defs: Array = []
var _home_progress: Array = []
var _current_stage_idx: int = -1
var _load_token: int = -1


func _ready() -> void:
	modulate = Color.TRANSPARENT
	game_btn.pressed.connect(_on_game_pressed)
	battle_btn.pressed.connect(_on_battle_pressed)
	CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.home_meridian_light_confirmed.connect(_on_light_confirmed)
	CloudService.breakthrough_confirmed.connect(_on_breakthrough_done)
	CloudService.breakthrough_rejected.connect(_on_breakthrough_rejected)
	CultivationService.exp_changed.connect(_on_cultivation_exp_changed)
	CultivationService.stage_changed.connect(_on_cultivation_stage_changed)
	_setup_meridian_ui()
	_setup_breakthrough_btn()
	_refresh_cultivation_info()


func _refresh_cultivation_info() -> void:
	realm_label.text = CultivationService.get_stage_name()
	_update_exp_display(CultivationService.current_exp, CultivationService.get_exp_to_next_level())


func _update_exp_display(current_exp: int, exp_to_next: int) -> void:
	if exp_to_next > 0:
		exp_bar.value = (float(current_exp) / float(exp_to_next)) * 100.0
		exp_label.text = "%d/%d" % [current_exp, exp_to_next]
	else:
		exp_bar.value = 0.0
		exp_label.text = "%d" % current_exp


func _on_cultivation_exp_changed(current_exp: int, exp_to_next: int) -> void:
	_update_exp_display(current_exp, exp_to_next)
	_refresh_breakthrough_btn()
	_refresh_display()


func _on_cultivation_stage_changed(_level: int, stage_name: String) -> void:
	realm_label.text = stage_name
	_update_exp_display(CultivationService.current_exp, CultivationService.get_exp_to_next_level())
	_refresh_breakthrough_btn()
	_refresh_display()


func on_enter() -> void:
	modulate = Color.TRANSPARENT
	if GameState.skip_next_home_loading:
		GameState.skip_next_home_loading = false
	else:
		_load_token = LoadingManager.begin("加载数据...")
	if CloudService.online:
		CloudService.fetch_state()


func _setup_meridian_ui() -> void:
	for child in meridian_container.get_children():
		child.queue_free()

	meridian_title = Label.new()
	meridian_title.add_theme_font_size_override("font_size", 16)
	meridian_title.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	meridian_container.add_child(meridian_title)

	for child in acupoint_layer.get_children():
		var acupoint_node := child as AcupointNode
		if not acupoint_node:
			continue
		acupoint_nodes.append(acupoint_node)
		acupoint_node.acupoint_selected.connect(_on_acupoint_pressed)


func _on_state_loaded(state: Dictionary) -> void:
	if _load_token > 0:
		LoadingManager.end(_load_token)
		_load_token = -1
	if state.has("home_meridian_defs"):
		_home_defs = state.home_meridian_defs
	if state.has("home_meridian_progress"):
		_home_progress = state.home_meridian_progress
	_refresh_cultivation_info()
	_refresh_display()
	_refresh_breakthrough_btn()
	_try_auto_acupoint()
	var fade := create_tween()
	fade.tween_property(self, "modulate", Color.WHITE, 0.15)


func _refresh_display() -> void:
	if CultivationService.is_breakthrough_ready():
		meridian_container.hide()
		acupoint_layer.hide()
		return
	meridian_container.show()
	acupoint_layer.show()
	_set_acupoint_nodes([], 0)
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

	_set_acupoint_nodes(lit, int(def.get("acupoints", 0)))


func _set_acupoint_nodes(lit: Array, count: int) -> void:
	var visible_slot_count: int = _get_visible_slot_count(count)
	for node in acupoint_nodes:
		var slot_index: int = node.acupoint_index
		var is_active: bool = slot_index < visible_slot_count
		node.visible = is_active
		if is_active:
			var config_range: Vector2i = _get_config_range(slot_index, count)
			var completed: int = _count_lit_in_range(lit, config_range)
			node.set_progress(completed, config_range.y - config_range.x)


func _get_visible_slot_count(config_count: int) -> int:
	return mini(maxi(config_count, 0), acupoint_nodes.size())


func _get_config_range(slot_index: int, config_count: int) -> Vector2i:
	var slot_count: int = _get_visible_slot_count(config_count)
	if slot_count <= 0 or slot_index < 0 or slot_index >= slot_count:
		return Vector2i(-1, -1)
	var range_start: int = floori(float(slot_index * config_count) / float(slot_count))
	var range_end: int = floori(float((slot_index + 1) * config_count) / float(slot_count))
	return Vector2i(range_start, range_end)


func _count_lit_in_range(lit: Array, config_range: Vector2i) -> int:
	var completed: int = 0
	for config_index in range(config_range.x, config_range.y):
		if config_index < lit.size() and bool(lit[config_index]):
			completed += 1
	return completed


func _try_auto_acupoint() -> void:
	if not GameState.pending_auto_acupoint:
		return
	GameState.pending_auto_acupoint = false
	if _current_stage_idx < 0 or _home_defs.is_empty():
		return
	var def: Dictionary = _home_defs[_current_stage_idx]
	var qi_cost: int = def.get("qi_cost", 0)
	if CultivationService.current_qi < qi_cost:
		return
	var progress: Dictionary = {}
	for p in _home_progress:
		if p.get("stage", -1) == _current_stage_idx:
			progress = p
			break
	var lit: Array = progress.get("lit", [])
	var total: int = def.get("acupoints", 0)
	for slot_index in range(_get_visible_slot_count(total)):
		var config_range: Vector2i = _get_config_range(slot_index, total)
		for config_index in range(config_range.x, config_range.y):
			var is_lit: bool = lit[config_index] if config_index < lit.size() else false
			if not is_lit:
				_on_acupoint_pressed(slot_index)
				return


func _on_acupoint_pressed(slot_index: int) -> void:
	if _current_stage_idx < 0 or _home_defs.is_empty():
		return
	var def: Dictionary = _home_defs[_current_stage_idx]
	var config_count: int = int(def.get("acupoints", 0))
	var config_range: Vector2i = _get_config_range(slot_index, config_count)
	if config_range.x < 0:
		return
	var progress: Dictionary = {}
	for stage_progress in _home_progress:
		if stage_progress.get("stage", -1) == _current_stage_idx:
			progress = stage_progress
			break
	var lit: Array = progress.get("lit", [])
	var target_index: int = -1
	for config_index in range(config_range.x, config_range.y):
		if config_index >= lit.size() or not bool(lit[config_index]):
			target_index = config_index
			break
	if target_index < 0:
		return
	var qi_cost: int = def.get("qi_cost", 0)
	var completed: int = _count_lit_in_range(lit, config_range)
	var group_total: int = config_range.y - config_range.x
	var title: String = def.get("name", "穴位") + " 第%d穴" % (target_index + 1)
	var cost: String = "消耗灵气：%d  当前：%d/%d" % [qi_cost, CultivationService.current_qi, CultivationService.max_qi]
	if group_total > 1:
		cost += "\n点位进度：%d/%d" % [completed, group_total]
	var popup := preload("res://scenes/ui/home/AcupointActivatePopup.tscn").instantiate() as AcupointActivatePopup
	UIManager.show_popup(popup)
	popup.setup(title, cost, def.get("acupoint_rewards", {}), "激活", func(): CloudService.submit_light_home_acupoint(_current_stage_idx, target_index))


func _on_light_confirmed(result: Dictionary) -> void:
	if result.has("home_meridian_progress"):
		_home_progress = result.home_meridian_progress
	if result.has("cultivation"):
		CultivationService.deserialize(result.cultivation)
	_refresh_display()


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
		_do_breakthrough(0)

func _do_breakthrough(pill_id: int) -> void:
	CultivationService.try_breakthrough(pill_id, 0)

func _on_breakthrough_done(_result: Dictionary) -> void:
	_refresh_breakthrough_btn()
	_refresh_display()

func _on_breakthrough_rejected(reason: String) -> void:
	if reason == "pill_not_found":
		EventBus.show_toast.emit("当前没有该丹药")
