class_name WeeklyActivityPanel extends BasePopup

const DAY_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/weekly/weekly_day_button.png")


@onready var day_buttons: HBoxContainer = $Panel/DayButtons
@onready var task_list: VBoxContainer = $Panel/VBox/ScrollContainer/TaskList
@onready var empty_state: Label = $Panel/VBox/ScrollContainer/TaskList/EmptyState
@onready var close_btn: Button = $Panel/CloseButton
@onready var points_summary: Label = $Panel/VBox/WeeklyPoints/Summary
@onready var points_bar: ProgressBar = $Panel/VBox/WeeklyPoints/Progress
@onready var points_hint: Label = $Panel/VBox/WeeklyPoints/Hint
@onready var milestones_container: HBoxContainer = $Panel/VBox/WeeklyPoints/Milestones

var _activity_id: int = -1
var _current_day: int = 0
var _refresh_queued: bool = false


func setup(activity_id: int) -> void:
	_activity_id = activity_id
	_build_ui()


func _build_ui() -> void:
	for child in day_buttons.get_children():
		child.queue_free()
	var weekday_names: Array[String] = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
	for i in range(7):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(66, 46)
		btn.text = weekday_names[i]
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.72, 1))
		btn.add_theme_stylebox_override("normal", _make_day_style(Color.WHITE))
		btn.add_theme_stylebox_override("hover", _make_day_style(Color(1, 1, 0.86, 1)))
		btn.add_theme_stylebox_override("pressed", _make_day_style(Color(0.82, 0.86, 0.82, 1)))
		btn.add_theme_stylebox_override("disabled", _make_day_style(Color(0.56, 0.58, 0.55, 0.72)))
		btn.pressed.connect(_on_day_pressed.bind(i))
		day_buttons.add_child(btn)

	_current_day = GameState.activity_current_day
	_show_day(_current_day)
	_refresh_milestones()
	if not QuestService.weekly_progress_changed.is_connected(_queue_weekly_refresh):
		QuestService.weekly_progress_changed.connect(_queue_weekly_refresh)
	if not CloudService.quest_claim_confirmed.is_connected(_on_claim_done):
		CloudService.quest_claim_confirmed.connect(_on_claim_done)
	if not CloudService.quest_claim_rejected.is_connected(_on_claim_rejected):
		CloudService.quest_claim_rejected.connect(_on_claim_rejected)
	if not CloudService.state_loaded.is_connected(_on_state_synced):
		CloudService.state_loaded.connect(_on_state_synced)
	if not close_btn.pressed.is_connected(_on_close):
		close_btn.pressed.connect(_on_close)


func _on_claim_done(_result: Dictionary) -> void:
	_show_day(_current_day)


func _on_claim_rejected(_reason: String) -> void:
	_show_day(_current_day)


func _on_state_synced(_state: Dictionary) -> void:
	_show_day(_current_day)
	_refresh_milestones()


func _queue_weekly_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_weekly.call_deferred()


func _refresh_weekly() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	_refresh_milestones()
	_show_day(_current_day)


func _refresh_milestones() -> void:
	for child: Node in milestones_container.get_children():
		milestones_container.remove_child(child)
		child.queue_free()
	var definition: Dictionary = QuestService.get_weekly_definition(_activity_id)
	var current: Dictionary = QuestService.get_weekly_progress(_activity_id)
	var stages: Array = definition.get("milestones", [])
	var points: int = int(current.get("points", 0))
	var maximum: int = int(stages.back().get("required_points", 1)) if not stages.is_empty() else 1
	points_summary.text = "本周积分 %d / %d" % [points, maximum] if not current.is_empty() else "正在同步周常积分…"
	points_bar.max_value = maximum
	points_bar.value = points
	var reset_hour: int = int(ConfigDatabase.get_game_config("reset_hour", 5))
	points_hint.text = "领取任务奖励 +%d 积分 · 每周一 %02d:00 重置" % [int(definition.get("points_per_task", 0)), reset_hour]
	for stage: Dictionary in stages:
		var stage_id: int = int(stage.get("stage", 0))
		var required: int = int(stage.get("required_points", 0))
		var is_claimed: bool = QuestService.is_weekly_stage_claimed(_activity_id, stage_id)
		var can_claim: bool = points >= required and not is_claimed
		var card := PanelContainer.new()
		card.name = "Stage%d" % stage_id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.98, 0.95, 0.77) if can_claim else Color(0.91, 0.93, 0.85)
		style.border_color = Color(0.66, 0.50, 0.20) if can_claim else Color(0.51, 0.62, 0.47)
		style.set_border_width_all(2 if can_claim else 1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 6.0
		style.content_margin_right = 6.0
		style.content_margin_top = 8.0
		style.content_margin_bottom = 8.0
		card.add_theme_stylebox_override("panel", style)
		milestones_container.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		card.add_child(column)
		var threshold := Label.new()
		threshold.text = "%d 积分" % required
		threshold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		threshold.add_theme_font_size_override("font_size", 14)
		threshold.add_theme_color_override("font_color", Color(0.18, 0.31, 0.22))
		column.add_child(threshold)
		var rewards := HBoxContainer.new()
		rewards.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(rewards)
		var reward: Dictionary = stage.get("rewards", {})
		for token: Dictionary in reward.get("tokens", []):
			_add_stage_icon(rewards, int(token.get("token", 0)), int(token.get("amount", 0)))
		for item: Dictionary in reward.get("items", []):
			_add_stage_icon(rewards, int(item.get("id", 0)), int(item.get("count", 0)))
		var button := Button.new()
		button.name = "ClaimButton"
		button.custom_minimum_size = Vector2(0, 40)
		button.text = "已领取" if is_claimed else "领取" if can_claim else "未达成"
		button.disabled = not can_claim or QuestService.weekly_claiming or current.is_empty()
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", Color(1, 0.96, 0.78))
		button.add_theme_color_override("font_disabled_color", Color(0.34, 0.41, 0.31))
		button.add_theme_stylebox_override("normal", _make_stage_button_style(Color(0.22, 0.39, 0.27)))
		button.add_theme_stylebox_override("hover", _make_stage_button_style(Color(0.29, 0.48, 0.32)))
		button.add_theme_stylebox_override("pressed", _make_stage_button_style(Color(0.16, 0.30, 0.21)))
		button.add_theme_stylebox_override("disabled", _make_stage_button_style(Color(0.79, 0.83, 0.72)))
		button.pressed.connect(QuestService.claim_weekly_stage.bind(_activity_id, stage_id))
		column.add_child(button)


func _add_stage_icon(parent: Control, item_id: int, amount: int) -> void:
	var icon: WeeklyRewardIcon = preload("res://scenes/ui/activity/WeeklyRewardIcon.tscn").instantiate() as WeeklyRewardIcon
	parent.add_child(icon)
	icon.setup(item_id, amount)


func _show_day(day: int) -> void:
	var quest_ids: Array = ConfigDatabase.get_weekly_tasks(_activity_id)
	var today: int = clampi(GameState.activity_current_day, 0, 6)
	_current_day = clampi(day, 0, mini(today, quest_ids.size() - 1)) if not quest_ids.is_empty() else 0
	for child in task_list.get_children():
		if child != empty_state:
			child.queue_free()

	for i in range(day_buttons.get_child_count()):
		var btn := day_buttons.get_child(i) as Button
		btn.disabled = i > today
		btn.modulate = Color(1, 0.78, 0.48, 1) if i == _current_day else Color(0.66, 0.68, 0.61, 0.75) if i > today else Color.WHITE
		if i == _current_day:
			btn.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
		else:
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	if quest_ids.is_empty() or _current_day >= quest_ids.size():
		empty_state.text = "暂无周常任务配置"
		empty_state.visible = true
		return
	var day_ids: Array = quest_ids[_current_day]
	var visible_task_count: int = 0

	for qid in day_ids:
		var qid_int: int = int(qid)
		var quest := _find_quest(qid_int)
		if quest.is_empty():
			continue
		var slot := preload("res://scenes/ui/activity/WeeklyTaskSlot.tscn").instantiate() as WeeklyTaskSlot
		task_list.add_child(slot)
		slot.setup(quest, QuestService.get_progress(qid_int))
		visible_task_count += 1
	empty_state.visible = visible_task_count == 0
	if empty_state.visible:
		empty_state.text = "暂无任务可显示"


func _find_quest(qid: int) -> Dictionary:
	for q in QuestService.quest_defs:
		if q.get("id", 0) == qid:
			return q
	return {}


func _on_day_pressed(day: int) -> void:
	_show_day(day)


func _on_close() -> void:
	if QuestService.weekly_progress_changed.is_connected(_queue_weekly_refresh):
		QuestService.weekly_progress_changed.disconnect(_queue_weekly_refresh)
	if CloudService.quest_claim_confirmed.is_connected(_on_claim_done):
		CloudService.quest_claim_confirmed.disconnect(_on_claim_done)
	if CloudService.quest_claim_rejected.is_connected(_on_claim_rejected):
		CloudService.quest_claim_rejected.disconnect(_on_claim_rejected)
	if CloudService.state_loaded.is_connected(_on_state_synced):
		CloudService.state_loaded.disconnect(_on_state_synced)
	UIManager.hide_popup(self)


func _make_day_style(modulate_color: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = DAY_BUTTON_TEXTURE
	style.texture_margin_left = 20.0
	style.texture_margin_top = 18.0
	style.texture_margin_right = 20.0
	style.texture_margin_bottom = 18.0
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	style.modulate_color = modulate_color
	return style


func _make_stage_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
