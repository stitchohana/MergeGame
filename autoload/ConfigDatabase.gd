extends Node

# ConfigDatabase: Loads and provides access to all JSON configuration tables.

var _game_config: Dictionary = {}
var _items_data: Dictionary = {}        # item_id -> item_data Dictionary
var _items_by_type_level: Dictionary = {}  # type -> { level -> Array[item_data] }
var _initial_setup: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> void:
	_game_config = _load_json("res://config/game_config.json")
	_initial_setup = _load_json("res://config/initial_setup.json")
	_load_items("res://config/items.json")
	print("[ConfigDatabase] Loaded all configs: ", _items_data.size(), " items defined")

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
	return json.data

func _load_items(path: String) -> void:
	var data := _load_json(path)
	if data.is_empty():
		return

	# Load regular items
	var regular: Array = data.get("regular", [])
	for reg_item in regular:
		var id: int = reg_item.id
		reg_item.type = "regular"
		_items_data[id] = reg_item

		var level: int = reg_item.level
		if not _items_by_type_level.has("regular"):
			_items_by_type_level["regular"] = {}
		if not _items_by_type_level["regular"].has(level):
			_items_by_type_level["regular"][level] = []
		_items_by_type_level["regular"][level].append(reg_item)

	# Load launcher items
	var launchers: Array = data.get("launcher", [])
	for laun_item in launchers:
		var id: int = laun_item.id
		laun_item.type = "launcher"
		_items_data[id] = laun_item

		var level: int = laun_item.level
		if not _items_by_type_level.has("launcher"):
			_items_by_type_level["launcher"] = {}
		if not _items_by_type_level["launcher"].has(level):
			_items_by_type_level["launcher"][level] = []
		_items_by_type_level["launcher"][level].append(laun_item)

	# Load crafting items
	var craftings: Array = data.get("crafting", [])
	for craft_item in craftings:
		var id: int = craft_item.id
		craft_item.type = "crafting"
		_items_data[id] = craft_item

		var level: int = craft_item.level
		if not _items_by_type_level.has("crafting"):
			_items_by_type_level["crafting"] = {}
		if not _items_by_type_level["crafting"].has(level):
			_items_by_type_level["crafting"][level] = []
		_items_by_type_level["crafting"][level].append(craft_item)

	# Store recipes for CraftingService
	_items_data["_recipes"] = data.get("recipes", [])

# Get item data by numeric ID
func get_item_data(item_id: int) -> Dictionary:
	return _items_data.get(item_id, {})

# Get item data by type, level, and optional group_id
func get_item_by_level(type: String, level: int, group_id: int = 0) -> Dictionary:
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
func get_next_level(type: String, level: int, group_id: int = 0) -> Dictionary:
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

# Get initial setup data
func get_initial_setup() -> Array:
	return _initial_setup.get("items", [])

# Get all item IDs grouped by type
func get_all_items_of_type(type: String) -> Array:
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
	var item_data := get_item_data(item_id)
	if item_data.is_empty():
		return []
	var recipe_ids: Array = item_data.get("recipes", [])
	if recipe_ids.is_empty():
		return []
	var all_recipes: Array = get_recipes()
	var result: Array = []
	for rid in recipe_ids:
		for r in all_recipes:
			if r.get("id", 0) == rid:
				result.append(r)
				break
	return result

# Reload all configs at runtime
func reload() -> void:
	load_all()

# Get game config value by key path (e.g., "game.grid_cols")
func get_game_config(key: String) -> Variant:
	var keys := key.split(".")
	var current = _game_config
	for k in keys:
		if current is Dictionary and current.has(k):
			current = current[k]
		else:
			return null
	return current
