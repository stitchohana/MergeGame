class_name ActivityInfoPopup extends BasePopup

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var cycle_label: Label = $Panel/VBox/CycleLabel
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)


func setup(activity: Dictionary) -> void:
	title_label.text = str(activity.get("name", "活动详情"))
	cycle_label.text = "活动周期：%s" % _get_cycle_name(int(activity.get("cycle", -1)))
	var progress: Dictionary = ActivityManager.get_progress(int(activity.get("id", 0)))
	if progress.get("claimed", false):
		status_label.text = "活动奖励已领取"
	elif progress.get("completed", false):
		status_label.text = "活动已完成"
	else:
		status_label.text = "活动进行中"


func _get_cycle_name(cycle: int) -> String:
	match cycle:
		0:
			return "限时活动"
		1:
			return "每日刷新"
		2:
			return "每周刷新"
		3:
			return "每月刷新"
		_:
			return "长期活动"


func _on_close_pressed() -> void:
	UIManager.hide_popup(self)
