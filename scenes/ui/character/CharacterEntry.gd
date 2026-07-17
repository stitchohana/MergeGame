class_name CharacterEntry extends Control

@onready var icon: TextureRect = $Icon
@onready var btn: Button = $Button

var _home_defs: Array = []
var _home_progress: Array = []


func _ready() -> void:
	CloudService.state_loaded.connect(_on_state_loaded)
	CultivationService.qi_changed.connect(_refresh_btn)
	btn.pressed.connect(_on_btn_pressed)
	btn.visible = false
	if CloudService.online:
		CloudService.fetch_state()


func _on_state_loaded(state: Dictionary) -> void:
	if state.has("home_meridian_defs"):
		_home_defs = state.home_meridian_defs
	if state.has("home_meridian_progress"):
		_home_progress = state.home_meridian_progress
	_refresh_btn(CultivationService.current_qi, CultivationService.max_qi)


func _refresh_btn(_current_qi: int = -1, _max_qi: int = -1) -> void:
	btn.visible = _can_activate_acupoint()


func _can_activate_acupoint() -> bool:
	if _home_defs.is_empty():
		return false
	var qi: int = CultivationService.current_qi

	var stage_idx: int = 0
	if _home_progress.size() > 0:
		stage_idx = _home_progress.size()
		for i in range(_home_progress.size()):
			var p: Dictionary = _home_progress[i]
			if not p.get("circulation_completed", false):
				stage_idx = i
				break
	if stage_idx >= _home_defs.size():
		stage_idx = _home_defs.size() - 1

	var def: Dictionary = _home_defs[stage_idx]
	var qi_cost: int = def.get("qi_cost", 0)
	if qi_cost <= 0 or qi < qi_cost:
		return false

	var progress: Dictionary = {}
	for p in _home_progress:
		if p.get("stage", -1) == stage_idx:
			progress = p
			break
	var lit: Array = progress.get("lit", [])
	var total: int = def.get("acupoints", 0)
	for i in range(total):
		var is_lit: bool = lit[i] if i < lit.size() else false
		if not is_lit:
			return true
	return false


func _on_btn_pressed() -> void:
	GameState.pending_auto_acupoint = true
	EventBus.screen_change_requested.emit("home")
