class_name Overlay extends Control

signal resume_requested
signal restart_requested

func _ready() -> void:
	hide()
	GameState.game_over.connect(_on_game_over)
	$PausePanel/ResumeButton.pressed.connect(_on_resume_pressed)
	$PausePanel/QuitButton.pressed.connect(_on_quit_pressed)
	$GameOverPanel/RestartButton.pressed.connect(_on_restart_pressed)

func hide_all() -> void:
	$PausePanel.hide()
	$GameOverPanel.hide()
	hide()

func show_pause_menu() -> void:
	show()
	$PausePanel.show()
	GameState.set_phase(GameState.GamePhase.PAUSED)

func _on_game_over() -> void:
	show()
	$GameOverPanel.show()
	$GameOverPanel/FinalScoreLabel.text = "最终分数: %d" % GameState.score
	var is_new := GameState.score >= GameState.high_score
	$GameOverPanel/NewHighScoreLabel.text = "新纪录!" if is_new else ""
	$GameOverPanel/NewHighScoreLabel.visible = is_new

func _on_resume_pressed() -> void:
	hide_all()
	resume_requested.emit()

func _on_restart_pressed() -> void:
	hide_all()
	restart_requested.emit()

func _on_quit_pressed() -> void:
	get_tree().quit()
