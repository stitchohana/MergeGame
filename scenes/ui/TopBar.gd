class_name TopBar extends BaseHUD

@onready var settings_btn: Button = $SettingsBtn
@onready var status_indicator: ColorRect = $StatusIndicator
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var stamina_label: Label = $StaminaLabel
@onready var stones_label: Label = $StonesLabel
@onready var shop_btn: Button = $ShopButton

func _ready() -> void:
	if settings_btn:
		settings_btn.pressed.connect(func(): EventBus.pause_requested.emit())
	if shop_btn:
		shop_btn.pressed.connect(_on_shop_pressed)
	_update_status_indicator()
	_update_stamina()
	_update_stones()
	CloudService.connected.connect(_update_status_indicator)
	CloudService.disconnected.connect(_update_status_indicator)
	GameState.stamina_changed.connect(_on_stamina_changed)
	GameState.spirit_stones_changed.connect(_on_stones_changed)

func _on_stamina_changed(current: int, max_stam: int) -> void:
	_update_stamina()

func _on_stones_changed(amount: int) -> void:
	_update_stones()

func _update_stones() -> void:
	if stones_label:
		stones_label.text = "灵石 %d" % GameState.spirit_stones

func _on_shop_pressed() -> void:
	var popup := preload("res://scenes/ui/ShopPopup.tscn").instantiate() as ShopPopup
	UIManager.show_popup(popup)

func _update_stamina() -> void:
	if stamina_bar:
		stamina_bar.max_value = GameState.max_stamina
		stamina_bar.value = GameState.stamina
		var ratio := float(GameState.stamina) / float(GameState.max_stamina) if GameState.max_stamina > 0 else 0.0
		if ratio > 0.5:
			stamina_bar.modulate = Color(0.2, 0.8, 0.2, 1)
		elif ratio > 0.2:
			stamina_bar.modulate = Color(0.8, 0.8, 0.2, 1)
		else:
			stamina_bar.modulate = Color(0.8, 0.2, 0.2, 1)
	if stamina_label:
		stamina_label.text = "体力 %d/%d" % [GameState.stamina, GameState.max_stamina]

func _update_status_indicator() -> void:
	if not status_indicator:
		return
	if CloudService.online:
		status_indicator.color = Color(0.2, 0.8, 0.2)  # Green = connected
	else:
		status_indicator.color = Color(0.8, 0.2, 0.2)  # Red = disconnected
