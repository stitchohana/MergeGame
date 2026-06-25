class_name Overlay extends BasePopup

func _ready() -> void:
	GameState.game_over.connect(_on_game_over)
	$PausePanel/ResumeButton.pressed.connect(_on_resume_pressed)
	$PausePanel/QuitButton.pressed.connect(_on_quit_pressed)
	$GameOverPanel/RestartButton.pressed.connect(_on_restart_pressed)
	$PausePanel.hide()
	$GameOverPanel.hide()

func show_pause_menu() -> void:
	$PausePanel.show()
	$GameOverPanel.hide()
	show_animated()
	GameState.set_phase(GameState.GamePhase.PAUSED)

func _on_game_over() -> void:
	$PausePanel.hide()
	$GameOverPanel.show()
	show_animated()

func _on_resume_pressed() -> void:
	hide_animated()
	EventBus.resume_requested.emit()

func _on_restart_pressed() -> void:
	hide_animated()
	EventBus.restart_requested.emit()

func _on_quit_pressed() -> void:
	get_tree().quit()
