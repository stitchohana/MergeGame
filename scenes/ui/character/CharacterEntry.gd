class_name CharacterEntry extends Control

@onready var icon: TextureRect = $Icon
@onready var btn: Button = $Button
@onready var progress_bar: TextureProgressBar = $ProgressOuter
@onready var progress_label: Label = $ProgressOuter/ProgressLabel

var _home_defs: Array = []
var _home_progress: Array = []


func _ready() -> void:
	CloudService.state_loaded.connect(_on_state_loaded)
	CloudService.home_meridian_light_confirmed.connect(_on_home_meridian_light_confirmed)
	CultivationService.qi_changed.connect(_refresh_btn)
	btn.pressed.connect(_on_btn_pressed)
	btn.visible = false
	_home_defs = GameState.home_meridian_defs.duplicate(true)
	_home_progress = GameState.home_meridian_progress.duplicate(true)
	_refresh_progress()
	_refresh_btn(CultivationService.current_qi, CultivationService.max_qi)


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("home_meridian_defs"):
		_home_defs = state.home_meridian_defs
		GameState.home_meridian_defs = _home_defs.duplicate(true)
	if state.has("home_meridian_progress"):
		_home_progress = state.home_meridian_progress
		GameState.home_meridian_progress = _home_progress.duplicate(true)
	_refresh_progress()
	_refresh_btn(CultivationService.current_qi, CultivationService.max_qi)


func _on_home_meridian_light_confirmed(result: Dictionary) -> void:
	if not result.has("home_meridian_progress"):
		return
	var progress: Array = result.get("home_meridian_progress", [])
	_home_progress = progress
	GameState.home_meridian_progress = progress.duplicate(true)
	_refresh_progress()
	_refresh_btn(CultivationService.current_qi, CultivationService.max_qi)


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
					return stage_idx
				break
		if not has_progress:
			return stage_idx
	return _home_defs.size() - 1


func _get_stage_lit(stage_idx: int) -> Array:
	for progress: Dictionary in _home_progress:
		if int(progress.get("stage", -1)) == stage_idx:
			return progress.get("lit", [])
	return []


func _refresh_btn(_current_qi: int = -1, _max_qi: int = -1) -> void:
	btn.visible = _can_activate_acupoint()


func _can_activate_acupoint() -> bool:
	if _home_defs.is_empty():
		return false
	var qi: int = CultivationService.current_qi

	var stage_idx: int = _get_active_stage_index()

	var def: Dictionary = _home_defs[stage_idx]
	var qi_cost: int = def.get("qi_cost", 0)
	if qi_cost <= 0 or qi < qi_cost:
		return false

	var lit: Array = _get_stage_lit(stage_idx)
	var total: int = def.get("acupoints", 0)
	for i in range(total):
		var is_lit: bool = lit[i] if i < lit.size() else false
		if not is_lit:
			return true
	return false


func _on_btn_pressed() -> void:
	GameState.pending_auto_acupoint = true
	EventBus.screen_change_requested.emit("home")
