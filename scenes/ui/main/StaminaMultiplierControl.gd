class_name StaminaMultiplierControl extends Control

@onready var multiplier_menu: MenuButton = $MultiplierMenu
@onready var timer_label: Label = $TimerLabel

var _displayed_max: int = 0
var _refresh_accumulator: float = 0.0


func _ready() -> void:
	multiplier_menu.get_popup().id_pressed.connect(_on_multiplier_selected)
	GameState.stamina_multiplier_changed.connect(_on_multiplier_changed)
	_refresh()


func _process(delta: float) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator < 0.25:
		return
	_refresh_accumulator = 0.0
	_refresh()


func _on_multiplier_changed(_max_multiplier: int, _selected: int, _expires_at: int) -> void:
	_refresh()


func _on_multiplier_selected(multiplier: int) -> void:
	GameState.select_stamina_multiplier(multiplier)


func _refresh() -> void:
	GameState.expire_stamina_multiplier_if_needed()
	var max_multiplier: int = GameState.stamina_multiplier_max
	visible = max_multiplier > 1
	if not visible:
		_displayed_max = 0
		return
	if _displayed_max != max_multiplier:
		_rebuild_menu(max_multiplier)
	multiplier_menu.text = "体力 ×%d" % GameState.stamina_multiplier_selected
	timer_label.text = TimeUtils.format_countdown(
		GameState.get_stamina_multiplier_remaining_seconds()
	)
	_update_checks()


func _rebuild_menu(max_multiplier: int) -> void:
	var popup: PopupMenu = multiplier_menu.get_popup()
	popup.clear()
	var multiplier: int = 1
	while multiplier <= max_multiplier:
		popup.add_check_item("×%d" % multiplier, multiplier)
		multiplier *= 2
	_displayed_max = max_multiplier


func _update_checks() -> void:
	var popup: PopupMenu = multiplier_menu.get_popup()
	for index: int in range(popup.item_count):
		popup.set_item_checked(
			index, popup.get_item_id(index) == GameState.stamina_multiplier_selected
		)
