extends Node

# GridManager: Core grid data structure for the merge board.
# All item placement, movement, and lookup operations go through this singleton.

# Grid dimensions (mirrors Constants.gd — keep in sync)
const GRID_COLS := Constants.GRID_COLS
const GRID_ROWS := Constants.GRID_ROWS

var current_board_type: int = Constants.BoardType.MAIN

# _grid[row][col] = { "id": int, "level": int, "type": str } or null
var _grid: Array[Array] = []

# Reverse lookup: item_id -> Array[Vector2i] (multiple same-id items can exist)
var _item_positions: Dictionary = {}  # int item_id -> Array[Vector2i]

# Unique instance ID counter — assigned to every item placed on the grid
var _next_uid: int = 1

signal item_added(item_data: Dictionary, pos: Vector2i)
signal item_removed(item_data: Dictionary, pos: Vector2i)
signal item_moved(item_data: Dictionary, from_pos: Vector2i, to_pos: Vector2i)
signal grid_updated()

func _ready() -> void:
	init_grid(current_board_type)

func init_grid(board_type: int = Constants.BoardType.MAIN) -> void:
	current_board_type = board_type
	# Emit removal signals for all existing items before clearing
	if not _grid.is_empty():
		for row in range(GRID_ROWS):
			for col in range(GRID_COLS):
				if _grid[row][col] != null:
					var item: Dictionary = _grid[row][col]
					var pos := Vector2i(col, row)
					item_removed.emit(item, pos)
	_grid.clear()
	_item_positions.clear()
	for row in range(GRID_ROWS):
		var row_data: Array = []
		row_data.resize(GRID_COLS)
		for col in range(GRID_COLS):
			row_data[col] = null
		_grid.append(row_data)

# --- Validation ---

func is_valid_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_COLS and pos.y >= 0 and pos.y < GRID_ROWS

func is_empty(pos: Vector2i) -> bool:
	if not is_valid_pos(pos):
		return false
	return _grid[pos.y][pos.x] == null

func get_item(pos: Vector2i) -> Variant:
	if not is_valid_pos(pos):
		return null
	return _grid[pos.y][pos.x]

# --- Mutations ---

func add_item(item_data: Dictionary, pos: Vector2i) -> bool:
	item_data = item_data.duplicate(true)
	if not is_valid_pos(pos) or not is_empty(pos):
		return false
	item_data["_uid"] = _next_uid
	_next_uid += 1
	_grid[pos.y][pos.x] = item_data

	# Track position for this item_id
	var item_id: int = item_data.get("id", 0)
	if not _item_positions.has(item_id):
		_item_positions[item_id] = []
	_item_positions[item_id].append(pos)

	item_added.emit(item_data, pos)
	grid_updated.emit()
	return true

func remove_item(pos: Vector2i) -> Dictionary:
	if not is_valid_pos(pos) or is_empty(pos):
		return {}

	var item_data: Dictionary = _grid[pos.y][pos.x]
	_grid[pos.y][pos.x] = null

	# Remove position tracking
	var item_id: int = item_data.get("id", 0)
	if _item_positions.has(item_id):
		var idx = _item_positions[item_id].find(pos)
		if idx >= 0:
			_item_positions[item_id].remove_at(idx)
		if _item_positions[item_id].is_empty():
			_item_positions.erase(item_id)

	item_removed.emit(item_data, pos)
	grid_updated.emit()
	return item_data

func move_item(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	if not is_valid_pos(from_pos) or not is_valid_pos(to_pos):
		return false
	if is_empty(from_pos):
		return false
	if not is_empty(to_pos):
		return false

	var item_data: Dictionary = _grid[from_pos.y][from_pos.x]
	_grid[from_pos.y][from_pos.x] = null
	_grid[to_pos.y][to_pos.x] = item_data

	# Update position tracking
	var item_id: int = item_data.get("id", 0)
	if _item_positions.has(item_id):
		var idx = _item_positions[item_id].find(from_pos)
		if idx >= 0:
			_item_positions[item_id][idx] = to_pos

	item_moved.emit(item_data, from_pos, to_pos)
	grid_updated.emit()
	return true

func swap_items(pos_a: Vector2i, pos_b: Vector2i) -> void:
	if not is_valid_pos(pos_a) or not is_valid_pos(pos_b):
		return
	if is_empty(pos_a) or is_empty(pos_b):
		return
	var item_a: Dictionary = _grid[pos_a.y][pos_a.x]
	var item_b: Dictionary = _grid[pos_b.y][pos_b.x]
	_grid[pos_a.y][pos_a.x] = item_b
	_grid[pos_b.y][pos_b.x] = item_a
	# Update position tracking
	var id_a: int = item_a.get("id", 0)
	if _item_positions.has(id_a):
		var idx = _item_positions[id_a].find(pos_a)
		if idx >= 0:
			_item_positions[id_a][idx] = pos_b
	var id_b: int = item_b.get("id", 0)
	if _item_positions.has(id_b):
		var idx = _item_positions[id_b].find(pos_b)
		if idx >= 0:
			_item_positions[id_b][idx] = pos_a
	item_moved.emit(item_a, pos_a, pos_b)
	item_moved.emit(item_b, pos_b, pos_a)
	grid_updated.emit()

# --- Queries ---

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var candidates := [
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x, pos.y + 1),
		Vector2i(pos.x, pos.y - 1),
	]
	for c in candidates:
		if is_valid_pos(c):
			result.append(c)
	return result

func get_occupied_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for n in get_neighbors(pos):
		if not is_empty(n):
			result.append(n)
	return result

func find_nearest_empty(from_pos: Vector2i) -> Vector2i:
	# BFS from the given position to find the nearest empty cell
	var visited := {}
	var queue: Array = [from_pos]
	visited[hash_pos(from_pos)] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if is_empty(current):
			return current
		for n in get_neighbors(current):
			var h := hash_pos(n)
			if not visited.has(h):
				visited[h] = true
				queue.append(n)

	return Vector2i(-1, -1)  # No empty cell found

func find_empty_by_row() -> Vector2i:
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if _grid[row][col] == null:
				return Vector2i(col, row)
	return Vector2i(-1, -1)

func count_items() -> int:
	var count := 0
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if _grid[row][col] != null:
				count += 1
	return count

func count_empty_cells() -> int:
	return (GRID_COLS * GRID_ROWS) - count_items()

func is_grid_full() -> bool:
	return count_empty_cells() == 0

# Get all positions that have a specific item_id
func get_positions_by_item_id(item_id: int) -> Array[Vector2i]:
	return _item_positions.get(item_id, []).duplicate()

# Find an item by its unique instance ID
func find_by_uid(uid: int) -> Dictionary:
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var item = _grid[row][col]
			if item != null and item.get("_uid", 0) == uid:
				return item
	return {}

# Find the grid position of an item by its unique instance ID
func find_pos_by_uid(uid: int) -> Vector2i:
	if uid <= 0:
		return Vector2i(-1, -1)
	for entry in get_all_items():
		if entry.data.get("_uid", 0) == uid:
			return entry.pos
	return Vector2i(-1, -1)

# Get all items on the grid
func get_all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if _grid[row][col] != null:
				result.append({
					"data": _grid[row][col],
					"pos": Vector2i(col, row)
				})
	return result

# Get all items of a specific type
func get_all_items_of_type(type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var item = _grid[row][col]
			if item != null and item.get("type") == type:
				result.append({
					"data": item,
					"pos": Vector2i(col, row)
				})
	return result

# Check if any merge is possible on the board
func has_possible_merge() -> bool:
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var item = _grid[row][col]
			if item == null:
				continue
			var item_level: int = item.get("level", 0)
			var item_type: String = item.get("type", "")
			var item_group_id = item.get("group_id", 0)
			var next_level_data := ConfigDatabase.get_next_level(item_type, item_level, item_group_id)
			if next_level_data.is_empty():
				continue  # Max level, can't merge further
			# Check neighbors for same type+level
			for n in get_neighbors(Vector2i(col, row)):
				var neighbor = _grid[n.y][n.x]
				if neighbor != null and neighbor.get("id") == item.get("id"):
					return true
	return false

# Hash a position for use as a Dictionary key
static func hash_pos(pos: Vector2i) -> int:
	return pos.y * GRID_COLS + pos.x
