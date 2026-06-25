extends Node

# GameState: Manages score, high score, and game phase transitions.

enum GamePhase {
	INIT,
	IDLE,
	DRAGGING,
	MERGING,
	SPAWNING,
	PAUSED,
	GAME_OVER
}

var score: int = 0
var high_score: int = 0
var version: int = 0
var phase: GamePhase = GamePhase.INIT
var stamina: int = 100
var max_stamina: int = 100
var spirit_stones: int = 0
var current_board_type: int = Constants.BoardType.MAIN

# Meridian cultivation
var meridian_circulations: int = 0
var meridian_acupoints: Array = []  # [{item_id, name, count, completed}]
var meridian_threshold_idx: int = 0

signal meridian_updated()

signal score_changed(new_score: int)
signal high_score_changed(new_high: int)
signal phase_changed(old_phase: GamePhase, new_phase: GamePhase)
signal stamina_changed(current: int, max: int)
signal spirit_stones_changed(amount: int)
signal game_over()

func _ready() -> void:
	_load_high_score()
	set_phase(GamePhase.IDLE)

func add_score(points: int) -> void:
	if points <= 0:
		return
	score += points
	score_changed.emit(score)
	if score > high_score:
		high_score = score
		high_score_changed.emit(high_score)
		_save_high_score()

func reset() -> void:
	score = 0
	score_changed.emit(score)
	set_phase(GamePhase.IDLE)

func set_phase(new_phase: GamePhase) -> void:
	var old := phase
	phase = new_phase
	phase_changed.emit(old, new_phase)

func check_game_over() -> void:
	if phase == GamePhase.GAME_OVER:
		return
	if GridManager.is_grid_full() and not GridManager.has_possible_merge():
		set_phase(GamePhase.GAME_OVER)
		game_over.emit()

func _load_high_score() -> void:
	var file := FileAccess.open("user://highscore.dat", FileAccess.READ)
	if file:
		high_score = file.get_32()
		file.close()

func _save_high_score() -> void:
	var file := FileAccess.open("user://highscore.dat", FileAccess.WRITE)
	if file:
		file.store_32(high_score)
		file.close()
