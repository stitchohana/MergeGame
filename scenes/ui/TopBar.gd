class_name TopBar extends Control

@onready var score_label: Label = $ScoreLabel
@onready var high_score_label: Label = $HighScoreLabel
@onready var settings_btn: Button = $SettingsBtn

signal settings_pressed

func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.high_score_changed.connect(_on_high_score_changed)
	_on_score_changed(GameState.score)
	_on_high_score_changed(GameState.high_score)
	if settings_btn:
		settings_btn.pressed.connect(func(): settings_pressed.emit())

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "分数: %d" % new_score

func _on_high_score_changed(new_high: int) -> void:
	if high_score_label:
		high_score_label.text = "最高: %d" % new_high
