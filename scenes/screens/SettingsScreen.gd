class_name SettingsScreen extends BaseScreen

@onready var back_btn := $BackButton

func _ready() -> void:
	if back_btn:
		back_btn.pressed.connect(_on_back)

func _on_back() -> void:
	UIManager.pop_screen()
