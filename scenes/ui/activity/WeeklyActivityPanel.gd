class_name WeeklyActivityPanel extends BasePopup


@onready var day_buttons: HBoxContainer = $Panel/VBox/DayButtons
@onready var task_list: VBoxContainer = $Panel/VBox/ScrollContainer/TaskList
@onready var close_btn: Button = $Panel/VBox/CloseButton

var _activity_id: int = -1
var _current_day: int = 0


func setup(activity_id: int) -> void:
	_activity_id = activity_id
	_build_ui()


func _build_ui() -> void:
	for child in day_buttons.get_children():
		child.queue_free()
	for i in range(7):
		var btn := Button.new()
		btn.text = "第%d天" % (i + 1)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_day_pressed.bind(i))
		day_buttons.add_child(btn)

	_current_day = GameState.activity_current_day
	_show_day(_current_day)
	CloudService.quest_claim_confirmed.connect(_on_claim_done)
	close_btn.pressed.connect(_on_close)


func _on_claim_done(_result: Dictionary) -> void:
	_show_day(_current_day)


func _show_day(day: int) -> void:
	_current_day = day
	for child in task_list.get_children():
		child.queue_free()

	var today: int = GameState.activity_current_day
	for i in range(day_buttons.get_child_count()):
		var btn := day_buttons.get_child(i) as Button
		btn.disabled = i > today
		if i == day:
			btn.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
		else:
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# Get quest IDs for this day from config
	var quest_ids: Array = ConfigDatabase.get_weekly_tasks(_activity_id)
	if day < 0 or day >= quest_ids.size():
		return
	var day_ids: Array = quest_ids[day]

	for qid in day_ids:
		var qid_int: int = int(qid)
		var quest := _find_quest(qid_int)
		if quest.is_empty():
			continue
		var slot := preload("res://scenes/ui/activity/WeeklyTaskSlot.tscn").instantiate() as WeeklyTaskSlot
		task_list.add_child(slot)
		slot.setup(quest, QuestService.get_progress(qid_int))


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
	UIManager.hide_popup(self)
