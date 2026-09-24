class_name WeeklyActivityPanel extends BasePopup

const DAY_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/weekly/weekly_day_button.png")


@onready var day_buttons: HBoxContainer = $Panel/VBox/DayButtons
@onready var task_list: VBoxContainer = $Panel/VBox/ScrollContainer/TaskList
@onready var empty_state: Label = $Panel/VBox/ScrollContainer/TaskList/EmptyState
@onready var close_btn: Button = $Panel/VBox/CloseButton

var _activity_id: int = -1
var _current_day: int = 0


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
	style.modulate_color = modulate_color
	return style
