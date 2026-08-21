class_name TopBar extends BaseHUD

@onready var stamina_resource: TopResource = $StaminaResource
@onready var qi_resource: TopResource = $QiResource
@onready var stones_resource: TopResource = $StonesResource
@onready var gm_btn: Button = $GMButton

var _regen_remaining: float = 0.0
var _qi_updates_suppressed: bool = false


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
	if _qi_updates_suppressed:
		return
	_update_qi()

func set_qi_updates_suppressed(suppressed: bool) -> void:
	var was_suppressed: bool = _qi_updates_suppressed
	_qi_updates_suppressed = suppressed
	if was_suppressed and not suppressed:
		_update_qi()


func _update_qi() -> void:
	qi_resource.set_value(CultivationService.current_qi)


func _update_stones() -> void:
	stones_resource.set_value(GameState.spirit_stones)


func _update_stamina() -> void:
	stamina_resource.set_value(GameState.stamina)


func _update_regen_timer() -> void:
	stamina_resource.set_regen_timer(_regen_remaining)
