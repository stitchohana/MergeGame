class_name TopBar extends BaseHUD

@onready var score_label: Label = $ScoreLabel
@onready var high_score_label: Label = $HighScoreLabel
@onready var settings_btn: Button = $SettingsBtn
@onready var status_indicator: ColorRect = $StatusIndicator

func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.high_score_changed.connect(_on_high_score_changed)
	_on_score_changed(GameState.score)
	_on_high_score_changed(GameState.high_score)
	if settings_btn:
		settings_btn.pressed.connect(func(): EventBus.pause_requested.emit())
	_update_status_indicator()
	CloudService.connected.connect(_update_status_indicator)
	CloudService.disconnected.connect(_update_status_indicator)

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "分数: %d" % new_score

func _on_high_score_changed(new_high: int) -> void:
	if high_score_label:
		high_score_label.text = "最高: %d" % new_high

func _update_status_indicator() -> void:
	if not status_indicator:
		return
	if CloudService.online:
		status_indicator.color = Color(0.2, 0.8, 0.2)  # Green = connected
	else:
		status_indicator.color = Color(0.8, 0.2, 0.2)  # Red = disconnected
