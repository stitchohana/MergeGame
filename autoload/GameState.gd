extends Node

# GameState: Manages game phase transitions and player state.

enum GamePhase {
	INIT,
	IDLE,
	DRAGGING,
	MERGING,
	SPAWNING,
	PAUSED,
	GAME_OVER
}

var phase: GamePhase = GamePhase.INIT
var stamina: int = 100
var max_stamina: int = 100
var spirit_stones: int = 0
var regen_remaining_ms: float = 0.0
var current_board_type: int = Constants.BoardType.MAIN
var previous_screen_name: String = ""

# Meridian cultivation
var meridian_circulations: int = 0
var meridian_acupoints: Array = []  # [{item_id, name, count, completed}]
var meridian_threshold_idx: int = 0

# Grid caching for screen switching
var main_grid_cache: Array = []
var battle_grid_cache: Array = []

# Activity system
var activity_defs: Array = []
var activity_progress: Dictionary = {}
var activity_current_day: int = 0  # { activity_id: { completed, claimed, last_reset } }

signal meridian_updated()
signal pending_rewards_changed(count: int)

signal phase_changed(old_phase: GamePhase, new_phase: GamePhase)
signal stamina_changed(current: int, max: int)
signal spirit_stones_changed(amount: int)
signal game_over()

func _ready() -> void:
	set_phase(GamePhase.IDLE)

func reset() -> void:
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
