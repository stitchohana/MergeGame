class_name HomeScreen extends BaseScreen

@onready var game_btn: Button = $GameButton
@onready var battle_btn: Button = $BattleButton
@onready var realm_label: Label = $RealmLabel
@onready var exp_bar: TextureProgressBar = $ExpBar
@onready var exp_label: Label = $ExpLabel
@onready var acupoint_layer: Control = $AcupointLayer

const ITEM_WIDGET_SCENE: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
const BREAKTHROUGH_ITEM_SIZE: int = 72

var acupoint_nodes: Array[AcupointNode] = []

var _home_defs: Array = []
var _home_progress: Array = []
var _current_stage_idx: int = -1
var _load_token: int = -1
var _activation_pending: bool = false
var _breakthrough_items_scroll: ScrollContainer = null
var _breakthrough_items_row: HBoxContainer = null


func _ready() -> void:
	modulate = Color.TRANSPARENT
	game_btn.pressed.connect(_on_game_pressed)
	battle_btn.pressed.connect(_on_battle_pressed)
	CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.home_meridian_light_confirmed.connect(_on_light_confirmed)
	CloudService.home_meridian_light_rejected.connect(_on_light_rejected)
	CloudService.breakthrough_confirmed.connect(_on_breakthrough_done)
	CloudService.breakthrough_rejected.connect(_on_breakthrough_rejected)
	CultivationService.exp_changed.connect(_on_cultivation_exp_changed)
	CultivationService.stage_changed.connect(_on_cultivation_stage_changed)
	_setup_acupoint_ui()
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
	if not GameState.home_meridian_defs.is_empty():
		_home_defs = GameState.home_meridian_defs.duplicate(true)
		_home_progress = GameState.home_meridian_progress.duplicate(true)
		_refresh_display()
		_refresh_breakthrough_btn()
		modulate = Color.WHITE
	if GameState.skip_next_home_loading:
		GameState.skip_next_home_loading = false
	elif GameState.home_meridian_defs.is_empty():
		_load_token = LoadingManager.begin("加载数据...")
	if CloudService.online:
		CloudService.fetch_state()
	_try_show_pending_breakthrough_prompt()


func _setup_acupoint_ui() -> void:
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
		GameState.home_meridian_defs = _home_defs.duplicate(true)
	if state.has("home_meridian_progress"):
		_home_progress = state.home_meridian_progress
		GameState.home_meridian_progress = _home_progress.duplicate(true)
	_refresh_cultivation_info()
	_refresh_display()
	_refresh_breakthrough_btn()
	_try_show_pending_breakthrough_prompt()
	_try_auto_acupoint()
	var fade := create_tween()
	fade.tween_property(self, "modulate", Color.WHITE, 0.15)


func _refresh_display() -> void:
	if CultivationService.is_breakthrough_ready():
		acupoint_layer.hide()
		return
	acupoint_layer.show()
	_set_acupoint_nodes([], 0, 0)
	if _home_defs.is_empty():
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
	stage_idx = mini(stage_idx, _max_unlocked_home_stage_index())

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

	_set_acupoint_nodes(lit, int(def.get("acupoints", 0)), int(def.get("qi_cost", 0)))


func _max_unlocked_home_stage_index() -> int:
	return ConfigDatabase.get_max_unlocked_home_meridian_stage_index(CultivationService.current_level)


func _set_acupoint_nodes(lit: Array, count: int, qi_cost: int) -> void:
	var visible_slot_count: int = _get_visible_slot_count(count)
	var next_acupoint_index: int = _get_next_acupoint_index(lit, count)
	var next_slot_index: int = _get_slot_for_config_index(next_acupoint_index, count)
	for node in acupoint_nodes:
		var slot_index: int = node.acupoint_index
		var is_active: bool = slot_index < visible_slot_count
		node.visible = is_active
		node.hide_activation()
		if is_active:
			var config_range: Vector2i = _get_config_range(slot_index, count)
			var completed: int = _count_lit_in_range(lit, config_range)
			node.set_progress(completed, config_range.y - config_range.x)
			if slot_index == next_slot_index:
				node.show_activation(next_acupoint_index, count, qi_cost, _activation_pending)


func _get_visible_slot_count(config_count: int) -> int:
	return mini(maxi(config_count, 0), acupoint_nodes.size())


func _get_config_range(slot_index: int, config_count: int) -> Vector2i:
	var slot_count: int = _get_visible_slot_count(config_count)
	if slot_count <= 0 or slot_index < 0 or slot_index >= slot_count:
		return Vector2i(-1, -1)
	var range_start: int = floori(float(slot_index * config_count) / float(slot_count))
	var range_end: int = floori(float((slot_index + 1) * config_count) / float(slot_count))
	return Vector2i(range_start, range_end)


func _get_next_acupoint_index(lit: Array, config_count: int) -> int:
	for config_index in range(config_count):
		if config_index >= lit.size() or not bool(lit[config_index]):
			return config_index
	return -1


func _get_slot_for_config_index(config_index: int, config_count: int) -> int:
	if config_index < 0:
		return -1
	for slot_index in range(_get_visible_slot_count(config_count)):
		var config_range: Vector2i = _get_config_range(slot_index, config_count)
		if config_index >= config_range.x and config_index < config_range.y:
			return slot_index
	return -1


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
	var target_index: int = _get_next_acupoint_index(lit, total)
	var slot_index: int = _get_slot_for_config_index(target_index, total)
	if slot_index >= 0:
		_on_acupoint_pressed(slot_index)


func _on_acupoint_pressed(slot_index: int) -> void:
	if _activation_pending or _current_stage_idx < 0 or _home_defs.is_empty():
		return
	var def: Dictionary = _home_defs[_current_stage_idx]
	var config_count: int = int(def.get("acupoints", 0))
	var progress: Dictionary = {}
	for stage_progress in _home_progress:
		if stage_progress.get("stage", -1) == _current_stage_idx:
			progress = stage_progress
			break
	var lit: Array = progress.get("lit", [])
	var target_index: int = _get_next_acupoint_index(lit, config_count)
	if target_index < 0 or _get_slot_for_config_index(target_index, config_count) != slot_index:
		return
	var qi_cost: int = int(def.get("qi_cost", 0))
	var title: String = "%s · 第%d穴" % [String(def.get("name", "穴位")), target_index + 1]
	var cost: String = "进度：%d/%d\n消耗灵气：%d　当前：%d/%d" % [target_index, config_count, qi_cost, CultivationService.current_qi, CultivationService.max_qi]
	var rewards: Dictionary = _get_acupoint_rewards(def, target_index)
	var stage_index: int = _current_stage_idx
	var popup := preload("res://scenes/ui/home/AcupointActivatePopup.tscn").instantiate() as AcupointActivatePopup
	UIManager.show_popup(popup)
	popup.setup(title, cost, rewards, "激活", func(): _submit_acupoint(stage_index, target_index))


func _get_acupoint_rewards(def: Dictionary, target_index: int) -> Dictionary:
	if target_index < 0 or target_index >= int(def.get("acupoints", 0)):
		return {}
	return {
		"tokens": [
			{"token": 4, "amount": int(def.get("acupoint_exp", 0))},
			{"token": 3, "amount": 15},
		],
		"items": [],
	}


func _submit_acupoint(stage_index: int, target_index: int) -> void:
	if _activation_pending:
		return
	_activation_pending = true
	_refresh_display()
	CloudService.submit_light_home_acupoint(stage_index, target_index)


func _on_light_confirmed(result: Dictionary) -> void:
	_activation_pending = false
	if result.has("home_meridian_progress"):
		_home_progress = result.home_meridian_progress
		GameState.home_meridian_progress = _home_progress.duplicate(true)
	if result.has("cultivation"):
		CultivationService.deserialize(result.cultivation)
	if result.has("meridian_acupoints"):
		GameState.meridian_acupoints = result.meridian_acupoints.duplicate(true)
		GameState.meridian_updated.emit()
	_refresh_display()


func _on_light_rejected(_reason: String) -> void:
	_activation_pending = false
	_refresh_display()


func _on_game_pressed() -> void:
	EventBus.screen_change_requested.emit("game")


func _on_battle_pressed() -> void:
	GameState.previous_screen_name = "home"
	EventBus.screen_change_requested.emit("battle")


func _setup_breakthrough_btn() -> void:
	_breakthrough_items_scroll = ScrollContainer.new()
	_breakthrough_items_scroll.name = "BreakthroughItemsScroll"
	_breakthrough_items_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_breakthrough_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_breakthrough_items_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_breakthrough_items_scroll.offset_left = 200
	_breakthrough_items_scroll.offset_top = 1304
	_breakthrough_items_scroll.offset_right = 580
	_breakthrough_items_scroll.offset_bottom = 1382
	_breakthrough_items_scroll.z_index = 4
	add_child(_breakthrough_items_scroll)

	_breakthrough_items_row = HBoxContainer.new()
	_breakthrough_items_row.name = "BreakthroughItemsRow"
	_breakthrough_items_row.custom_minimum_size = Vector2(0, BREAKTHROUGH_ITEM_SIZE)
	_breakthrough_items_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breakthrough_items_row.add_theme_constant_override("separation", 8)
	_breakthrough_items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_breakthrough_items_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_breakthrough_items_scroll.add_child(_breakthrough_items_row)

	var btn := Button.new()
	btn.name = "BreakthroughBtn"
	btn.text = "突破"
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_breakthrough_pressed)
	btn.visible = false
	btn.flat = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = true
	btn.layout_mode = 0
	btn.offset_left = 200
	btn.offset_top = 1390
	btn.offset_right = 580
	btn.offset_bottom = 1430
	add_child(btn)

func _refresh_breakthrough_btn() -> void:
	var btn := get_node_or_null("BreakthroughBtn") as Button
	if btn == null or _breakthrough_items_scroll == null or _breakthrough_items_row == null:
		return
	var ready: bool = CultivationService.is_breakthrough_ready()
	btn.visible = ready
	_breakthrough_items_scroll.visible = ready
	if not ready:
		_clear_breakthrough_items()
		return
	_refresh_breakthrough_items()

func _clear_breakthrough_items() -> void:
	if _breakthrough_items_row == null:
		return
	for child: Node in _breakthrough_items_row.get_children():
		child.free()

func _refresh_breakthrough_items() -> void:
	_clear_breakthrough_items()
	var requirements: Array = CultivationService.get_required_breakthrough_items()
	for requirement_variant: Variant in requirements:
		if not requirement_variant is Dictionary:
			continue
		var requirement: Dictionary = requirement_variant as Dictionary
		var item_id: int = int(requirement.get("item_id", 0))
		var count: int = int(requirement.get("count", 0))
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		if item_id <= 0 or count <= 0 or item_data.is_empty():
			continue

		var item_slot := Control.new()
		item_slot.name = "BreakthroughItem%d" % item_id
		item_slot.custom_minimum_size = Vector2(BREAKTHROUGH_ITEM_SIZE, BREAKTHROUGH_ITEM_SIZE)
		item_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var item_widget: ItemWidget = ITEM_WIDGET_SCENE.instantiate() as ItemWidget
		item_widget.name = "ItemWidget"
		item_widget.custom_minimum_size = Vector2(BREAKTHROUGH_ITEM_SIZE, BREAKTHROUGH_ITEM_SIZE)
		item_widget.size = Vector2(BREAKTHROUGH_ITEM_SIZE, BREAKTHROUGH_ITEM_SIZE)
		item_widget.setup(item_data)
		item_widget.set_clickable(true)
		item_widget.pressed.connect(_on_breakthrough_item_pressed.bind(item_id))
		item_slot.add_child(item_widget)

		var count_label := Label.new()
		count_label.name = "CountLabel"
		count_label.text = "×%d" % count
		count_label.position = Vector2(42, 48)
		count_label.size = Vector2(30, 22)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
		count_label.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.05, 1.0))
		count_label.add_theme_constant_override("outline_size", 3)
		item_slot.add_child(count_label)

		_breakthrough_items_row.add_child(item_slot)
	_breakthrough_items_scroll.scroll_horizontal = 0

func _on_breakthrough_item_pressed(item_id: int) -> void:
	if item_id <= 0:
		return
	var source_popup := preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
	UIManager.show_popup(source_popup)
	source_popup.setup_for_item(item_id)

func _on_breakthrough_pressed() -> void:
	var requirements: Array = CultivationService.get_required_breakthrough_items()
	if not requirements.is_empty():
		var popup := preload("res://scenes/ui/home/BreakthroughConfirmPopup.tscn").instantiate() as BreakthroughConfirmPopup
		UIManager.show_popup(popup)
		popup.setup_with_rewards(
			"突破确认",
			_format_breakthrough_confirmation(requirements),
			ConfigDatabase.get_stage_breakthrough_reward(CultivationService.current_level),
			_do_breakthrough
		)
	else:
		_do_breakthrough()

func _try_show_pending_breakthrough_prompt() -> void:
	if not GameState.pending_breakthrough_prompt:
		return
	if not CultivationService.is_breakthrough_ready():
		return
	GameState.pending_breakthrough_prompt = false
	call_deferred("_on_breakthrough_pressed")

func _format_breakthrough_confirmation(requirements: Array) -> String:
	var labels: Array[String] = []
	for requirement_variant: Variant in requirements:
		if not requirement_variant is Dictionary:
			continue
		var requirement: Dictionary = requirement_variant as Dictionary
		var item_data: Dictionary = ConfigDatabase.get_item_data(int(requirement.get("item_id", 0)))
		var item_name: String = String(item_data.get("name", "物品"))
		var count: int = int(requirement.get("count", 0))
		labels.append("%s ×%d" % [item_name, count])
	return "确认消耗：%s\n进行突破吗？" % ", ".join(labels)

func _do_breakthrough() -> void:
	CultivationService.try_breakthrough()

func _on_breakthrough_done(_result: Dictionary) -> void:
	_refresh_breakthrough_btn()
	_refresh_display()

func _on_breakthrough_rejected(reason: String) -> void:
	if reason == "breakthrough_items_insufficient":
		EventBus.show_toast.emit("突破材料不足")
