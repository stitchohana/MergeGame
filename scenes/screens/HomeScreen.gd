class_name HomeScreen extends BaseScreen

@onready var game_btn: Button = $VBoxContainer/GameButton
@onready var battle_btn: Button = $VBoxContainer/BattleButton

func _ready() -> void:
	game_btn.pressed.connect(_on_game_pressed)
	battle_btn.pressed.connect(_on_battle_pressed)

func _on_game_pressed() -> void:
	GridManager.init_grid()
	EventBus.screen_change_requested.emit("game")

func _on_battle_pressed() -> void:
	GridManager.init_grid()
	EventBus.screen_change_requested.emit("battle")
