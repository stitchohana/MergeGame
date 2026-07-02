class_name TopBar extends BaseHUD

@onready var stamina_label: Label = $StaminaLabel
@onready var stones_label: Label = $StonesLabel
@onready var regen_timer_label: Label = $RegenTimerLabel
@onready var gm_btn: Button = $GMButton

var _regen_remaining: float = 0.0

func _open_gm() -> void:
	var gm := preload("res://scenes/ui/GMPanel.tscn").instantiate()
	UIManager.show_popup(gm)
var _last_regen_server_ms: float = 0.0

func _ready() -> void:
	_update_stamina()
	_update_stones()
	GameState.stamina_changed.connect(_on_stamina_changed)
	GameState.spirit_stones_changed.connect(_on_stones_changed)
	_sync_from_server()
	if gm_btn:
		gm_btn.pressed.connect(_open_gm)

func _sync_from_server() -> void:
	if GameState.regen_remaining_ms > 0:
		_last_regen_server_ms = GameState.regen_remaining_ms
		_regen_remaining = GameState.regen_remaining_ms / 1000.0

func _reset_regen() -> void:
	if GameState.stamina >= GameState.max_stamina:
		_regen_remaining = 0.0
		_update_regen_timer()
		return
	# Use server value if it changed (e.g. from merge/spawn/pill response)
	if GameState.regen_remaining_ms > 0 and GameState.regen_remaining_ms != _last_regen_server_ms:
		_last_regen_server_ms = GameState.regen_remaining_ms
		_regen_remaining = GameState.regen_remaining_ms / 1000.0
		_update_regen_timer()
		return
	if _regen_remaining > 0:
		_update_regen_timer()
		return
	_regen_remaining = 120.0
	_update_regen_timer()

func _process(delta: float) -> void:
	if _regen_remaining > 0:
		_regen_remaining -= delta
		if _regen_remaining <= 0:
			_regen_remaining = 0
			GameState.stamina = mini(GameState.stamina + 1, GameState.max_stamina)
			if GameState.stamina < GameState.max_stamina:
				_regen_remaining = 120.0
			GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	_update_regen_timer()

func _on_stamina_changed(current: int, max_stam: int) -> void:
	_update_stamina()
	_reset_regen()

func _on_stones_changed(amount: int) -> void:
	_update_stones()

func _update_stones() -> void:
	if stones_label:
		stones_label.text = "%d" % GameState.spirit_stones

func _update_stamina() -> void:
	if stamina_label:
		stamina_label.text = "%d/%d" % [GameState.stamina, GameState.max_stamina]

func _update_regen_timer() -> void:
	if not regen_timer_label:
		return
	if GameState.stamina >= GameState.max_stamina:
		regen_timer_label.text = ""
		return
	var secs: int = int(ceil(_regen_remaining))
	var m: int = secs / 60
	var s: int = secs % 60
	regen_timer_label.text = "%02d:%02d" % [m, s]
