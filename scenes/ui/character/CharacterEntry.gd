class_name CharacterEntry extends Control

@onready var icon: TextureRect = $Icon
@onready var progress_bar: TextureProgressBar = $ProgressOuter
@onready var progress_label: Label = $ProgressOuter/ProgressLabel
@onready var reward_button: TextureButton = $RewardBadge

var _home_defs: Array = []
var _home_progress: Array = []


func _ready() -> void:
	if reward_button and not reward_button.pressed.is_connected(_on_reward_button_pressed):
		reward_button.pressed.connect(_on_reward_button_pressed)
	CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.home_meridian_light_confirmed.connect(_on_home_meridian_light_confirmed)
	CultivationService.stage_changed.connect(_on_cultivation_stage_changed)
	_home_defs = GameState.home_meridian_defs.duplicate(true)
	_home_progress = GameState.home_meridian_progress.duplicate(true)
	_refresh_progress()
	_refresh_reward_button()


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("home_meridian_defs"):
		_home_defs = state.home_meridian_defs
		GameState.home_meridian_defs = _home_defs.duplicate(true)
	if state.has("home_meridian_progress"):
		_home_progress = state.home_meridian_progress
		GameState.home_meridian_progress = _home_progress.duplicate(true)
	_refresh_progress()
	_refresh_reward_button()


func _on_home_meridian_light_confirmed(result: Dictionary) -> void:
	if not result.has("home_meridian_progress"):
		return
	var progress: Array = result.get("home_meridian_progress", [])
	_home_progress = progress
	GameState.home_meridian_progress = progress.duplicate(true)
	_refresh_progress()
	_refresh_reward_button()


func _on_cultivation_stage_changed(_level: int, _stage_name: String) -> void:
	_refresh_progress()
	_refresh_reward_button()


func _on_reward_button_pressed() -> void:
	var popup := preload("res://scenes/ui/home/BreakthroughRewardPreviewPopup.tscn").instantiate() as BreakthroughRewardPreviewPopup
	UIManager.show_popup(popup)
	popup.setup_for_current_stage()


func _refresh_reward_button() -> void:
	if reward_button == null:
		return
	reward_button.tooltip_text = "查看周天奖励"


func _refresh_progress() -> void:
	if not progress_bar or not progress_label:
		return
	var stage_idx: int = _get_active_stage_index()
	if stage_idx < 0:
		progress_bar.max_value = 1.0
		progress_bar.value = 0.0
		progress_label.text = "0/0"
		return

	var def: Dictionary = _home_defs[stage_idx]
	var total: int = int(def.get("acupoints", 0))
	var lit: Array = _get_stage_lit(stage_idx)
	var activated: int = 0
	for index: int in range(total):
		if index < lit.size() and bool(lit[index]):
			activated += 1
	progress_bar.max_value = float(maxi(total, 1))
	progress_bar.value = float(activated)
	progress_label.text = "%d/%d" % [activated, total]


func _get_active_stage_index() -> int:
	for stage_idx: int in range(_home_defs.size()):
		var has_progress: bool = false
		for progress: Dictionary in _home_progress:
			if int(progress.get("stage", -1)) == stage_idx:
				has_progress = true
				if not bool(progress.get("circulation_completed", false)):
					return _clamp_unlocked_stage_index(stage_idx)
				break
		if not has_progress:
			return _clamp_unlocked_stage_index(stage_idx)
	return _clamp_unlocked_stage_index(_home_defs.size() - 1)


func _clamp_unlocked_stage_index(stage_idx: int) -> int:
	if _home_defs.is_empty():
		return -1
	return clampi(stage_idx, 0, mini(_home_defs.size() - 1, _max_unlocked_home_stage_index()))


func _max_unlocked_home_stage_index() -> int:
	return ConfigDatabase.get_max_unlocked_home_meridian_stage_index(CultivationService.current_level)


func _get_stage_lit(stage_idx: int) -> Array:
	for progress: Dictionary in _home_progress:
		if int(progress.get("stage", -1)) == stage_idx:
			return progress.get("lit", [])
	return []
