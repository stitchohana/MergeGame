extends Node

# MergeService: Handles merge validation and execution.
# Single merge only — no chain reactions. One drag-drop = one merge.

var _is_processing: bool = false

signal merge_performed(item_a_data, item_b_data, result_data, pos)
signal merge_failed(reason)

# Check if two items can merge
func can_merge(item_a_data: Dictionary, item_b_data: Dictionary) -> bool:
	if item_a_data.is_empty() or item_b_data.is_empty():
		return false

	# Both group_id and item_id must match to merge
	if item_a_data.get("group_id", 0) != item_b_data.get("group_id", 0):
		return false
	if item_a_data.get("id", 0) != item_b_data.get("id", 0):
		return false

	# Check that next level exists
	var type: String = item_a_data.get("type", "")
	var level: int = item_a_data.get("level", 0)
	var gid: int = item_a_data.get("group_id", 0)
	var next = ConfigDatabase.get_next_level(type, level, gid)
	if next.is_empty():
		return false  # Already max level

	return true

# Try to merge item at from_pos into item at to_pos
# Returns true if merge was performed
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
	GameState.set_phase(GameState.GamePhase.MERGING)

	# Get next level data
	var type: String = item_a.get("type", "")
	var level: int = item_a.get("level", 0)
	var gid2: int = item_a.get("group_id", 0)
	var next_level_data: Dictionary = ConfigDatabase.get_next_level(type, level, gid2)

	# Calculate target position (use to_pos as the merge result position)
	var merge_pos := to_pos

	# Remove both items
	GridManager.remove_item(from_pos)
	GridManager.remove_item(to_pos)

	# Spawn the merged item at target position
	var merged_item = next_level_data.duplicate(true)
	GridManager.add_item(merged_item, merge_pos)

	# Add score
	var score_to_add: int = next_level_data.get("merge_score", 0)
	GameState.add_score(score_to_add)

	# Check game over explicitly after the merge changes settle
	GameState.check_game_over()

	# Reset phase if still in merging state (check_game_over may have set GAME_OVER)
	if GameState.phase == GameState.GamePhase.MERGING:
		GameState.set_phase(GameState.GamePhase.IDLE)

	merge_performed.emit(item_a, item_b, next_level_data, merge_pos)
	_is_processing = false
	return true
