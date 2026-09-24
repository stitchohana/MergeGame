class_name BattlePassEntry extends Button

@onready var icon_label: Label = $Content/IconFrame/IconLabel
@onready var name_label: Label = $Content/NameLabel
@onready var progress_label: Label = $Content/ProgressLabel
@onready var status_label: Label = $Content/StatusLabel

var _activity_id: int = 0


func _ready() -> void:
	pressed.connect(_on_pressed)
	if not GameState.battle_pass_changed.is_connected(_on_battle_pass_changed):
		GameState.battle_pass_changed.connect(_on_battle_pass_changed)
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)


func setup(activity: Dictionary) -> void:
	_activity_id = int(activity.get("id", 0))
	name_label.text = str(activity.get("name", "战令"))
	tooltip_text = "打开%s" % name_label.text
	_refresh()


func _on_battle_pass_changed(_progress: Dictionary) -> void:
	_refresh()


func _on_state_loaded(_state: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	if _activity_id <= 0 or not is_node_ready():
		return
	var pass_data: Dictionary = ConfigDatabase.get_battle_pass(_activity_id)
	var tiers: Array = pass_data.get("tiers", [])
	var max_points: int = int((tiers.back() as Dictionary).get("required_points", 0)) if not tiers.is_empty() else 0
	var progress: Dictionary = GameState.battle_pass_progress.get(_activity_id, {})
	if progress.is_empty():
		progress = GameState.battle_pass_progress.get(str(_activity_id), {})
	var points: int = maxi(0, int(progress.get("points", 0)))
	var unlocked: bool = bool(progress.get("premium_unlocked", false))
	icon_label.text = "战"
	progress_label.text = "%d / %d 积分" % [points, max_points]
	status_label.text = "进阶线已解锁" if unlocked else "点击查看 · 进阶线未解锁"
	status_label.add_theme_color_override(
		"font_color",
		Color("#b8e39d") if unlocked else Color("#f2d59c")
	)


func _on_pressed() -> void:
	if _activity_id <= 0:
		return
	var panel := preload("res://scenes/ui/activity/BattlePassPanel.tscn").instantiate() as BattlePassPanel
	UIManager.show_popup(panel)
	panel.setup(_activity_id)
