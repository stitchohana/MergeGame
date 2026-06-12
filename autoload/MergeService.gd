extends Node

# MergeService: Handles merge validation and execution.
# Server-authoritative: plays optimistic animation locally, submits to server,
# confirms on success or rolls back on rejection.

var _is_processing: bool = false

# Pending merge state for rollback
var _pending_from_data: Dictionary = {}
var _pending_to_data: Dictionary = {}
var _pending_from_pos: Vector2i = Vector2i(-1, -1)
var _pending_to_pos: Vector2i = Vector2i(-1, -1)

signal merge_performed(item_a_data, item_b_data, result_data, pos)
signal merge_failed(reason)
signal merge_rollback(from_data, to_data, from_pos, to_pos, reason)

func _ready() -> void:
	# Listen for server responses
	CloudService.merge_confirmed.connect(_on_merge_confirmed)
	CloudService.merge_rejected.connect(_on_merge_rejected)

# Local pre-check (no server call)
func can_merge(item_a_data: Dictionary, item_b_data: Dictionary) -> bool:
	if item_a_data.is_empty() or item_b_data.is_empty():
		return false
	if item_a_data.get("group_id", 0) != item_b_data.get("group_id", 0):
		return false
	if item_a_data.get("id", 0) != item_b_data.get("id", 0):
		return false
	var type: String = item_a_data.get("type", "")
	var level: int = item_a_data.get("level", 0)
	var gid: int = item_a_data.get("group_id", 0)
	var next = ConfigDatabase.get_next_level(type, level, gid)
	if next.is_empty():
		return false
	return true

# Try merge: local pre-check → optimistic animation → submit to server
func try_merge(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	if _is_processing:
		merge_failed.emit("Already processing")
		return false

	var item_a = GridManager.get_item(from_pos)
	var item_b = GridManager.get_item(to_pos)

	if item_a == null or item_b == null:
		merge_failed.emit("Invalid item")
		return false

	if not can_merge(item_a, item_b):
		merge_failed.emit("Cannot merge: not same type/level")
		return false

	_is_processing = true

	# Save pending state for rollback
	_pending_from_data = item_a.duplicate(true)
	_pending_to_data = item_b.duplicate(true)
	_pending_from_pos = from_pos
	_pending_to_pos = to_pos

	# Optimistic: execute merge locally for immediate visual feedback
	var type: String = item_a.get("type", "")
	var level: int = item_a.get("level", 0)
	var gid2: int = item_a.get("group_id", 0)
	var next_level_data: Dictionary = ConfigDatabase.get_next_level(type, level, gid2)

	var merge_pos := to_pos

	GridManager.remove_item(from_pos)
	GridManager.remove_item(to_pos)

	var merged_item = next_level_data.duplicate(true)
	GridManager.add_item(merged_item, merge_pos)

	# Add score optimistically
	var score_to_add: int = next_level_data.get("merge_score", 0)
	GameState.add_score(score_to_add)

	GameState.check_game_over()

	merge_performed.emit(item_a, item_b, next_level_data, merge_pos)

	# Submit to server for authoritative validation
	if CloudService.online:
		CloudService.submit_merge(from_pos.x, from_pos.y, to_pos.x, to_pos.y, GameState.version)

	_is_processing = false
	return true

func _on_merge_confirmed(result: Dictionary) -> void:
	print("[MergeService] Merge confirmed by server")
	GameState.version = result.get("new_version", GameState.version)
	_pending_from_data = {}
	_pending_to_data = {}

func _on_merge_rejected(reason: String) -> void:
	print("[MergeService] Merge rejected: ", reason)
	if _pending_from_data.is_empty():
		return

	GameState.set_phase(GameState.GamePhase.MERGING)

	# Rollback: remove the merged item, restore originals
	var merge_pos := _pending_to_pos
	var merged = GridManager.get_item(merge_pos)
	if merged != null:
		GridManager.remove_item(merge_pos)

	GridManager.add_item(_pending_from_data.duplicate(true), _pending_from_pos)
	GridManager.add_item(_pending_to_data.duplicate(true), _pending_to_pos)

	merge_rollback.emit(
		_pending_from_data, _pending_to_data,
		_pending_from_pos, _pending_to_pos, reason
	)

	_pending_from_data = {}
	_pending_to_data = {}

	if GameState.phase == GameState.GamePhase.MERGING:
		GameState.set_phase(GameState.GamePhase.IDLE)
