class_name TopBar extends BaseHUD

@onready var qi_label: Label = $QiLabel
@onready var stamina_label: Label = $StaminaLabel
@onready var stones_label: Label = $StonesLabel
@onready var regen_timer_label: Label = $RegenTimerLabel
@onready var gm_btn: Button = $GMButton

var _regen_remaining: float = 0.0


func _open_gm() -> void:
	var gm := preload("res://scenes/ui/other/GMPanel.tscn").instantiate()
	UIManager.show_popup(gm)


func _ready() -> void:
	_update_qi()
	_update_stamina()
	_update_stones()
	_reset_regen()
	CultivationService.qi_changed.connect(_on_qi_changed)
	GameState.stamina_changed.connect(_on_stamina_changed)
	GameState.spirit_stones_changed.connect(_on_stones_changed)
	if gm_btn:
		gm_btn.pressed.connect(_open_gm)


func _reset_regen() -> void:
	if GameState.stamina >= GameState.max_stamina:
		_regen_remaining = 0.0
	elif GameState.regen_remaining_ms > 0:
		_regen_remaining = GameState.regen_remaining_ms / 1000.0
	else:
		_regen_remaining = 1.0 * float(ConfigDatabase.get_game_config("stamina.regen_interval", 120))
	_update_regen_timer()


func _process(delta: float) -> void:
	if _regen_remaining > 0:
		_regen_remaining -= delta
		if _regen_remaining <= 0:
			_regen_remaining = 0
			if GameState.stamina < GameState.max_stamina:
				GameState.stamina += int(ConfigDatabase.get_game_config("stamina.regen_amount", 1))
				GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
			# Clear stale ms so _reset_regen uses full interval
			GameState.regen_remaining_ms = 0.0
			_reset_regen()
		_update_regen_timer()
	GameState.regen_remaining_ms = _regen_remaining * 1000.0


func _on_stamina_changed(current: int, max_stam: int) -> void:
	_update_stamina()
	_reset_regen()


func _on_stones_changed(amount: int) -> void:
	_update_stones()


func _on_qi_changed(_current: int, _max: int) -> void:
	_update_qi()


func _update_qi() -> void:
	if qi_label:
		qi_label.text = "%d/%d" % [CultivationService.current_qi, CultivationService.max_qi]


func _update_stones() -> void:
	if stones_label:
		stones_label.text = "%d" % GameState.spirit_stones


func _update_stamina() -> void:
	if stamina_label:
		stamina_label.text = "%d/%d" % [GameState.stamina, GameState.max_stamina]


func _update_regen_timer() -> void:
	if not regen_timer_label:
		return
	if _regen_remaining <= 0:
		regen_timer_label.text = ""
		return
	var secs: int = int(ceil(_regen_remaining))
	var m: int = secs / 60
	var s: int = secs % 60
	regen_timer_label.text = "%02d:%02d" % [m, s]
