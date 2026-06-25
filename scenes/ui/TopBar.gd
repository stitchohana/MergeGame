class_name TopBar extends BaseHUD

@onready var stamina_label: Label = $StaminaLabel
@onready var stones_label: Label = $StonesLabel

func _ready() -> void:
	_update_stamina()
	_update_stones()
	GameState.stamina_changed.connect(_on_stamina_changed)
	GameState.spirit_stones_changed.connect(_on_stones_changed)

func _on_stamina_changed(current: int, max_stam: int) -> void:
	_update_stamina()

func _on_stones_changed(amount: int) -> void:
	_update_stones()

func _update_stones() -> void:
	if stones_label:
		stones_label.text = "%d" % GameState.spirit_stones

func _update_stamina() -> void:
	if stamina_label:
		stamina_label.text = "%d/%d" % [GameState.stamina, GameState.max_stamina]
