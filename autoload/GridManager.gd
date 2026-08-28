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
# Reverse lookup: uid -> Vector2i for O(1) position queries
var _uid_to_pos: Dictionary = {}  # int uid -> Vector2i


signal item_added(item_data: Dictionary, pos: Vector2i)
signal item_removed(item_data: Dictionary, pos: Vector2i)
signal item_moved(item_data: Dictionary, from_pos: Vector2i, to_pos: Vector2i)
signal items_swapped(item_a: Dictionary, item_b: Dictionary, pos_a: Vector2i, pos_b: Vector2i)
signal grid_updated()

var _skip_anims: bool = false
var _grid_update_batch_depth: int = 0
var _grid_update_pending: bool = false


func _notify_grid_updated() -> void:
	if _grid_update_batch_depth > 0:
		_grid_update_pending = true
		return
	grid_updated.emit()


func _begin_grid_update_batch() -> void:
	_grid_update_batch_depth += 1


func _end_grid_update_batch() -> void:
	_grid_update_batch_depth = maxi(_grid_update_batch_depth - 1, 0)
	if _grid_update_batch_depth == 0 and _grid_update_pending:
		_grid_update_pending = false
		grid_updated.emit()

func _ready() -> void:
	init_grid(current_board_type)

func init_grid(board_type: int = Constants.BoardType.MAIN) -> void:
	var previous_item_count: int = count_items() if _grid.size() == GRID_ROWS else 0
	print("[GridManager] init_grid: board=", board_type,
		" previous_items=", previous_item_count,
		" caller=", get_stack())
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
	_uid_to_pos.clear()
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
	var has_valid_uid: bool = item_data.has("_uid") and item_data["_uid"] > 0
	if not has_valid_uid:
		var is_optimistic: bool = (
			item_data.get("_pending_spawn", false)
			or item_data.get("_optimistic_action", false)
		)
		if not is_optimistic:
			print("[ERROR] GridManager.add_item: no server uid for id=#" + str(item_data.get("id", 0)) + " has no server uid!")
	_grid[pos.y][pos.x] = item_data

	# Track position for this item_id
	var item_id: int = item_data.get("id", 0)
	if not _item_positions.has(item_id):
		_item_positions[item_id] = []
	_item_positions[item_id].append(pos)

	# Track uid -> position
	var uid: int = item_data.get("_uid", 0)
	if uid > 0:
		_uid_to_pos[uid] = pos

	item_added.emit(item_data, pos)
	_notify_grid_updated()
	return true

func confirm_optimistic_item(pos: Vector2i, temp_uid: int, server_uid: int,
		atk_base: int = 0) -> bool:
	if not is_valid_pos(pos) or is_empty(pos) or server_uid <= 0:
		return false
	var item: Dictionary = _grid[pos.y][pos.x]
	if item.get("_uid", 0) != temp_uid or not item.get("_pending_spawn", false):
		return false
	item["_uid"] = server_uid
	item.erase("_pending_spawn")
	item.erase("_spawn_request_id")
	item.erase("_spawn_origin")
	if atk_base > 0:
		item["atk_base"] = atk_base
	_uid_to_pos[server_uid] = pos
	_notify_grid_updated()
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

	# Remove uid tracking
	var uid: int = item_data.get("_uid", 0)
	if uid > 0:
		_uid_to_pos.erase(uid)

	item_removed.emit(item_data, pos)
	_notify_grid_updated()
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

	# Update uid tracking
	var uid: int = item_data.get("_uid", 0)
	if uid > 0:
		_uid_to_pos[uid] = to_pos

	item_moved.emit(item_data, from_pos, to_pos)
	_notify_grid_updated()
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
	# Update uid tracking
	var uid_a: int = item_a.get("_uid", 0)
	var uid_b: int = item_b.get("_uid", 0)
	if uid_a > 0:
		_uid_to_pos[uid_a] = pos_b
	if uid_b > 0:
		_uid_to_pos[uid_b] = pos_a
	items_swapped.emit(item_a, item_b, pos_a, pos_b)
	_notify_grid_updated()

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


func find_nearest_empty_after_removing(removed_pos: Vector2i, from_pos: Vector2i) -> Vector2i:
	var visited: Dictionary = {}
	var queue: Array = [from_pos]
	visited[hash_pos(from_pos)] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == removed_pos or is_empty(current):
			return current
		for neighbor: Vector2i in get_neighbors(current):
			var key: int = hash_pos(neighbor)
			if not visited.has(key):
				visited[key] = true
				queue.append(neighbor)

	return Vector2i(-1, -1)

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

# Find an item by its unique instance ID — O(1) via uid index
func find_by_uid(uid: int) -> Dictionary:
	if uid <= 0 or not _uid_to_pos.has(uid):
		return {}
	var pos: Vector2i = _uid_to_pos[uid]
	if not is_valid_pos(pos):
		_uid_to_pos.erase(uid)
		return {}
	var item = _grid[pos.y][pos.x]
	if item == null or item.get("_uid", 0) != uid:
		_uid_to_pos.erase(uid)
		return {}
	return item

# Find the grid position of an item by its unique instance ID — O(1) via uid index
func find_pos_by_uid(uid: int) -> Vector2i:
	if uid <= 0:
		return Vector2i(-1, -1)
	if _uid_to_pos.has(uid):
		var pos: Vector2i = _uid_to_pos[uid]
		if is_valid_pos(pos):
			var item = _grid[pos.y][pos.x]
			if item != null and item.get("_uid", 0) == uid:
				return pos
		_uid_to_pos.erase(uid)
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
			var item_type: int = item.get("type", 0)
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
# Recursively convert JSON floats to ints for integer keys
static func _sanitize_json_ints(data: Variant) -> Variant:
	if data is Dictionary:
		var result: Dictionary = {}
		for key in data as Dictionary:
			var val: Variant = (data as Dictionary)[key]
			if typeof(val) == TYPE_FLOAT and val == floor(val):
				result[key] = int(val)
			elif val is Dictionary or val is Array:
				result[key] = _sanitize_json_ints(val)
			else:
				result[key] = val
		return result
	elif data is Array:
		var result: Array = []
		for val in data as Array:
			if typeof(val) == TYPE_FLOAT and val == floor(val):
				result.append(int(val))
			elif val is Dictionary or val is Array:
				result.append(_sanitize_json_ints(val))
			else:
				result.append(val)
		return result
	return data

# Populate grid from server entries — shared by all screen restore paths
func populate_from_server(server_grid: Array) -> void:
	print("[GridManager] populate_from_server: entries=", server_grid.size())
	_begin_grid_update_batch()
	# One authoritative snapshot should produce one UI refresh, even when empty.
	_grid_update_pending = true
	for raw_entry in server_grid:
		var entry: Dictionary = _sanitize_json_ints(raw_entry) as Dictionary
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if item_data.is_empty():
			continue
		var item := item_data.duplicate(true)
		item["_uid"] = entry.uid
		if entry.has("charges"):
			item["charges"] = entry.charges
		if entry.has("last_charge_time"):
			item["last_charge_time"] = entry.last_charge_time
		if entry.has("immovable"):
			item["immovable"] = entry.immovable
		var craft_data: Variant = entry.get("craft", null)
		if craft_data is Dictionary and not (craft_data as Dictionary).is_empty():
			for key in craft_data as Dictionary:
				item[key] = craft_data[key]
		var recharge_rem: Variant = entry.get("_recharge_remaining", null)
		if recharge_rem != null:
			item["_recharge_remaining"] = recharge_rem
		var entry_storage: Variant = entry.get("storage", null)
		if entry_storage != null:
			item["storage"] = entry_storage
		if entry.has("atk_base"):
			item["atk_base"] = entry.atk_base
		add_item(item, Vector2i(entry.col, entry.row))
	_end_grid_update_batch()


# Apply an authoritative snapshot without clearing the board when the optimistic
# layout already matches. Returns false when a full rebuild is required.
func reconcile_from_server(server_grid: Array) -> bool:
	var entries: Array[Dictionary] = []
	var seen_positions: Dictionary = {}
	for raw_entry in server_grid:
		var entry: Dictionary = _sanitize_json_ints(raw_entry) as Dictionary
		var pos := Vector2i(int(entry.get("col", -1)), int(entry.get("row", -1)))
		var pos_key: int = hash_pos(pos)
		if not is_valid_pos(pos) or seen_positions.has(pos_key) or is_empty(pos):
			return false
		var local_item: Dictionary = _grid[pos.y][pos.x]
		if int(local_item.get("id", 0)) != int(entry.get("id", 0)):
			return false
		if int(entry.get("uid", 0)) <= 0:
			return false
		if ConfigDatabase.get_item_data(int(entry.get("id", 0))).is_empty():
			return false
		seen_positions[pos_key] = true
		entries.append(entry)

	if entries.size() != get_all_items().size():
		return false

	_uid_to_pos.clear()
	for entry in entries:
		var pos := Vector2i(int(entry.get("col", -1)), int(entry.get("row", -1)))
		var local_item: Dictionary = _grid[pos.y][pos.x]
		var authoritative: Dictionary = ConfigDatabase.get_item_data(int(entry.get("id", 0))).duplicate(true)
		authoritative["_uid"] = int(entry.get("uid", 0))
		if entry.has("charges"):
			authoritative["charges"] = entry.charges
		if entry.has("last_charge_time"):
			authoritative["last_charge_time"] = entry.last_charge_time
		if entry.has("immovable"):
			authoritative["immovable"] = entry.immovable
		var craft_data: Variant = entry.get("craft", null)
		if craft_data is Dictionary and not (craft_data as Dictionary).is_empty():
			for key in craft_data as Dictionary:
				authoritative[key] = craft_data[key]
		var recharge_remaining: Variant = entry.get("_recharge_remaining", null)
		if recharge_remaining != null:
			authoritative["_recharge_remaining"] = recharge_remaining
		var storage_data: Variant = entry.get("storage", null)
		if storage_data != null:
			authoritative["storage"] = storage_data
		if entry.has("atk_base"):
			authoritative["atk_base"] = entry.atk_base

		local_item.clear()
		local_item.merge(authoritative, true)
		_uid_to_pos[int(authoritative["_uid"])] = pos

	_notify_grid_updated()
	return true


# Confirm surviving optimistic merge results without rebuilding the grid. This
# is used when a successful batch snapshot cannot be reconciled structurally.
func confirm_action_batch_results(server_results: Array) -> void:
	var changed: bool = false
	for raw_result in server_results:
		var result: Dictionary = _sanitize_json_ints(raw_result) as Dictionary
		if str(result.get("type", "")) != "merge":
			continue
		var target_data: Array = result.get("to", [])
		if target_data.size() != 2:
			continue
		var target := Vector2i(int(target_data[0]), int(target_data[1]))
		if not is_valid_pos(target) or is_empty(target):
			continue
		var item: Dictionary = _grid[target.y][target.x]
		if int(item.get("id", 0)) != int(result.get("result_id", 0)):
			continue
		var server_uid: int = int(result.get("result_uid", 0))
		if server_uid <= 0:
			continue
		var old_uid: int = int(item.get("_uid", 0))
		if old_uid > 0:
			_uid_to_pos.erase(old_uid)
		item["_uid"] = server_uid
		item.erase("_optimistic_action")
		item.erase("_spawn_request_ids")
		item.erase("_pending_spawn")
		item.erase("_spawn_request_id")
		item.erase("_spawn_origin")
		if result.has("atk_base"):
			item["atk_base"] = result.atk_base
		_uid_to_pos[server_uid] = target
		changed = true

	if changed:
		_notify_grid_updated()
