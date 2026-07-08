class_name WeeklyActivityEntry extends Control

@onready var btn: Button = $Button

var _activity_id: int = -1


func setup(activity: Dictionary) -> void:
	_activity_id = activity.get("id", 0)
	btn.text = activity.get("name", "周常")
	btn.pressed.connect(_on_pressed)


func _on_pressed() -> void:
	var panel := preload("res://scenes/ui/activity/WeeklyActivityPanel.tscn").instantiate() as WeeklyActivityPanel
	UIManager.show_popup(panel)
	panel.setup(_activity_id)
