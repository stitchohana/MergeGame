class_name TitleScreen extends BaseScreen

@onready var start_btn := $StartButton
@onready var settings_btn := $SettingsButton

func _ready() -> void:
	if start_btn:
		start_btn.pressed.connect(_on_start)
	if settings_btn:
		settings_btn.pressed.connect(_on_settings)

func _on_start() -> void:
	EventBus.screen_change_requested.emit("game")

func _on_settings() -> void:
	EventBus.screen_change_requested.emit("settings")
