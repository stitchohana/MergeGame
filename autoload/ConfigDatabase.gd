extends Node

# ConfigDatabase: Loads and provides access to all JSON configuration tables.

var _game_config: Dictionary = {}
var _items_data: Dictionary = {}        # item_id -> item_data Dictionary
var _items_by_type_level: Dictionary = {}  # type -> { level -> Array[item_data] }
var _initial_setup: Dictionary = {}
var _cultivation_config: Dictionary = {}
var _expedition_maps: Dictionary = {}
var _monsters_data: Dictionary = {}
var _meridian_thresholds: Array = []
var _tokens_data: Dictionary = {}
var _weekly_tasks: Dictionary = {}
var _recipes_by_table: Dictionary = {}  # table_id -> Array[recipe]

func _ready() -> void:
	load_all()

func load_all() -> void:
	_game_config = _load_json("res://config/json_output/game_config.json")
	_initial_setup = _load_json("res://config/json_output/initial_setup.json")
	_load_items("res://config/json_output/items.json")
	_load_recipes("res://config/json_output/recipes.json")
	_cultivation_config = _load_json("res://config/json_output/cultivation.json")
	_load_expedition("res://config/json_output/expedition.json")
	_load_meridians("res://config/json_output/meridians.json")
	_load_tokens("res://config/json_output/tokens.json")
	_load_weekly_tasks("res://config/json_output/weekly_tasks.json")

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[ConfigDatabase] Failed to open: ", path)
		return {}
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[ConfigDatabase] JSON parse error in ", path, ": ", json.get_error_message())
		return {}
	return sanitize_json_ints(json.data)

# Recursively convert JSON floats to ints for integer keys
static func sanitize_json_ints(data: Variant) -> Variant:
	if data is Dictionary:
		var result: Dictionary = {}
		for key in data as Dictionary:
			var val: Variant = (data as Dictionary)[key]
			if typeof(val) == TYPE_FLOAT and val == floor(val):
				result[key] = int(val)
			elif val is Dictionary or val is Array:
				result[key] = sanitize_json_ints(val)
			else:
				result[key] = val
		return result
	elif data is Array:
		var result: Array = []
		for val in data as Array:
			if typeof(val) == TYPE_FLOAT and val == floor(val):
				result.append(int(val))
			elif val is Dictionary or val is Array:
				result.append(sanitize_json_ints(val))
			else:
				result.append(val)
		return result
	return data

func _load_items(path: String) -> void:
	var data := _load_json(path)
	if data.is_empty():
		return

	for reg_item in data.get("regular", []):
		reg_item.type = 0
		_add_item_by_type_level(reg_item)

	for laun_item in data.get("launcher", []):
		laun_item.type = 1
		_add_item_by_type_level(laun_item)

	for craft_item in data.get("crafting", []):
		craft_item.type = 2
		_add_item_by_type_level(craft_item)

	# Recipes now loaded from separate file

# Get item data by numeric ID
func _load_recipes(path: String) -> void:
	var data := _load_json(path)
	if data.is_empty():
		return
	var recipes: Array = data.get("recipes", [])
	_items_data["_recipes"] = recipes
	_recipes_by_table.clear()
	for recipe in recipes:
		var rid: int = recipe.get("id", 0)
		for item_id in _items_data:
			if not item_id is int:
				continue
			var item: Dictionary = _items_data[item_id]
			var item_recipes: Array = item.get("recipes", [])
			if item_recipes.has(rid):
				if not _recipes_by_table.has(item_id):
					_recipes_by_table[item_id] = []
				_recipes_by_table[item_id].append(recipe)
	print("[ConfigDatabase] Loaded ", recipes.size(), " recipes")

func get_item_data(item_id: int) -> Dictionary:
	return _items_data.get(item_id, {})

# Get item data by type, level, and optional group_id
func get_item_by_level(type: int, level: int, group_id: int = 0) -> Dictionary:
	var by_level: Dictionary = _items_by_type_level.get(type, {})
	var items: Array = by_level.get(level, [])
	if items.is_empty():
		return {}
	if group_id == 0:
		return items[0] as Dictionary
	for item in items:
		if item.get("group_id", 0) == group_id:
			return item
	return {}

# Get the next level item filtered by group_id
func _add_item_by_type_level(item_data: Dictionary) -> void:
	var item_type: int = item_data.get("type", 0)
	var level: int = int(item_data.get("level", 0))
	_items_data[int(item_data.id)] = item_data
	if not _items_by_type_level.has(item_type):
		_items_by_type_level[item_type] = {}
	if not _items_by_type_level[item_type].has(level):
		_items_by_type_level[item_type][level] = []
	_items_by_type_level[item_type][level].append(item_data)

func get_next_level(type: int, level: int, group_id: int = 0) -> Dictionary:
	return get_item_by_level(type, level + 1, group_id)

# Roll a spawn outcome for a launcher based on weighted probabilities
func roll_spawn(launcher_id: int) -> Dictionary:
	var data := get_item_data(launcher_id)
	if data.is_empty():
		return {}
	var spawns: Array = data.get("spawns", [])
	if spawns.is_empty():
		return {}
	var total_weight := 0
	for s in spawns:
		total_weight += s.weight
	if total_weight <= 0:
		return {}
	var roll := randi() % total_weight
	var accum := 0
	for s in spawns:
		accum += s.weight
		if roll < accum:
			return get_item_data(s.id)
	return get_item_data(spawns[-1].id)

# Get initial setup data for a specific board type
func get_initial_setup(board_type: int = Constants.BoardType.MAIN) -> Array:
	var key := _board_type_key(board_type)
	return _initial_setup.get(key, {}).get("items", [])

func _board_type_key(board_type: int) -> String:
	match board_type:
		Constants.BoardType.BATTLE: return "battle"
		_: return "main"

# Get all launchers that can spawn a specific item_id
func get_launchers_for_item(item_id: int) -> Array:
	var result: Array = []
	for id in _items_data:
		if id is int:
			var item: Dictionary = _items_data[id]
			if item.get("type", 0) != Constants.ItemType.LAUNCHER:
				continue
			var spawns: Array = item.get("spawns", [])
			for s in spawns:
				if s.get("id", 0) == item_id:
					result.append(item)
					break
	return result

# Get all items in a specific group_id (across all types)
func get_items_by_group(group_id: int) -> Array:
	var result: Array = []
	for item_id in _items_data:
		if item_id is int:
			var item: Dictionary = _items_data[item_id]
			if item.get("group_id", 0) == group_id:
				result.append(item)
	return result

# Get all item IDs grouped by type
func get_all_items_of_type(type: int) -> Array:
	var by_level: Dictionary = _items_by_type_level.get(type, {})
	var result: Array = []
	for level in by_level:
		var items: Array = by_level[level]
		for item in items:
			result.append(item)
	return result

# Get recipes list
func get_recipes() -> Array:
	return _items_data.get("_recipes", [])

# Get recipes allowed for a specific crafting table item
func get_recipes_for_item(item_id: int) -> Array:
	return _recipes_by_table.get(item_id, [])

func _load_expedition(path: String) -> void:
	var data := _load_json(path)
	if data.is_empty():
		print("[ConfigDatabase] Expedition data is empty or failed to load: ", path)
		return
	var maps: Array = data.get("maps", [])
	print("[ConfigDatabase] Loaded ", maps.size(), " expedition maps")
	for m in maps:
		_expedition_maps[int(m.id)] = m
	var monsters: Array = data.get("monsters", [])
	print("[ConfigDatabase] Loaded ", monsters.size(), " monsters")
	for mo in monsters:
		_monsters_data[int(mo.id)] = mo

func get_expedition_map(map_id: int) -> Dictionary:
	return _expedition_maps.get(map_id, {})

func get_monster(monster_id: int) -> Dictionary:
	return _monsters_data.get(monster_id, {})

func _load_meridians(path: String) -> void:
	var data := _load_json(path)
	if data.is_empty():
		return
	_meridian_thresholds = data.get("thresholds", [])


func _load_tokens(path: String) -> void:
	var data := _load_json(path)
	for t in data.get("tokens", []):
		_tokens_data[int(t.id)] = t

func get_token_data(token_id: int) -> Dictionary:
	return _tokens_data.get(token_id, {})

func get_meridian_thresholds() -> Array:
	return _meridian_thresholds

func get_meridian_threshold(idx: int) -> Dictionary:
	if idx < 0 or idx >= _meridian_thresholds.size():
		return {}
	return _meridian_thresholds[idx]

# Reload all configs at runtime
func reload() -> void:
	load_all()

# Get game config value by key path (e.g., "game.grid_cols")
func get_game_config(key: String, default = null) -> Variant:
	var keys := key.split(".")
	var current: Variant = _game_config
	for k in keys:
		if current is Dictionary and (current as Dictionary).has(k):
			current = (current as Dictionary)[k]
		else:
			return default
	return current

# --- Cultivation config ---

func get_cultivation_config() -> Dictionary:
	return _cultivation_config

func get_stages() -> Array:
	return _cultivation_config.get("stages", [])

func get_stage_count() -> int:
	return get_stages().size()

func get_passive_exp_per_second() -> int:
	return _cultivation_config.get("passive_exp_per_second", 3)

func _get_stage(level: int) -> Dictionary:
	var stages: Array = get_stages()
	var idx := level - 1
	if idx < 0 or idx >= stages.size():
		return {}
	return stages[idx]

func get_stage_exp(level: int) -> int:
	var s: Dictionary = _get_stage(level)
	if s.is_empty():
		return 999999
	return int(s.get("exp", 0))

func get_stage_name(level: int) -> String:
	var s: Dictionary = _get_stage(level)
	if s.is_empty():
		return "未知"
	return s.get("name", "未知")

func get_stage_max_qi(level: int) -> int:
	var s: Dictionary = _get_stage(level)
	if s.is_empty():
		return 100
	return int(s.get("max_qi", 100))

func get_stage_atk(level: int) -> int:
	var s: Dictionary = _get_stage(level)
	if s.is_empty():
		return 0
	return int(s.get("atk", 0))

func get_stage_breakthrough_pill(level: int) -> int:
	var s: Dictionary = _get_stage(level)
	if s.is_empty():
		return 0
	return int(s.get("breakthrough_pill", 0))


func _load_weekly_tasks(path: String) -> void:
	var data := _load_json(path)
	for wt in data.get("weekly_tasks", []):
		_weekly_tasks[int(wt.activity_id)] = wt.daily_quests

func get_weekly_tasks(activity_id: int) -> Array:
	return _weekly_tasks.get(activity_id, [])
