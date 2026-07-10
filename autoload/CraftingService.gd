extends Node

# CraftingService: Manages crafting table state, recipes, and timers.
# All state is stored directly in the crafting table's item data Dictionary
# on the grid, so it moves with the item automatically.

enum TableState { IDLE, HAS_ITEMS, CRAFTING, READY }

signal table_state_changed(table_item: Dictionary, state: int)

var _recipes: Array = []

func _ready() -> void:
	load_recipes()

func load_recipes() -> void:
	_recipes = ConfigDatabase.get_recipes()

func get_recipes() -> Array:
	return _recipes

# --- Helpers ---

func _init_craft_data(table_item: Dictionary) -> void:
	if table_item.has("_craft_init"):
		return
	table_item["_craft_init"] = true
	table_item["_craft_state"] = TableState.IDLE
	table_item["_craft_stored"] = []
	table_item["_craft_recipe"] = {}
	table_item["_craft_progress"] = 0.0
	table_item["_craft_result_id"] = -1

func _get_state(table_item: Dictionary) -> int:
	return table_item.get("_craft_state", TableState.IDLE)

func _set_state(table_item: Dictionary, state: int) -> void:
	table_item["_craft_state"] = state

# --- Public API ---

func add_ingredient(table_item: Dictionary, ingredient_data: Dictionary) -> bool:
	_init_craft_data(table_item)
	var stored: Array = table_item["_craft_stored"]
	stored.append({"uid": ingredient_data.get("_uid", ingredient_data.get("uid", 0)) as int, "id": ingredient_data.get("id", 0) as int})
	_set_state(table_item, TableState.HAS_ITEMS)

	var table_id: int = table_item.get("id", 0)
	var allowed_recipes: Array = ConfigDatabase.get_recipes_for_item(table_id)
	var recipe := _match_recipe(stored, allowed_recipes)
	if not recipe.is_empty():
		table_item["_craft_recipe"] = recipe
		table_state_changed.emit(table_item, TableState.HAS_ITEMS)
		return true
	else:
		table_item.erase("_craft_recipe")

	table_state_changed.emit(table_item, TableState.HAS_ITEMS)
	return false

func start_craft(table_item: Dictionary) -> bool:
	if _get_state(table_item) == TableState.CRAFTING:
		return false
	var recipe: Dictionary = table_item.get("_craft_recipe", {})
	if recipe.is_empty():
		return false

	_set_state(table_item, TableState.CRAFTING)
	table_item["_craft_progress"] = 0.0
	table_item["_craft_stored"] = []
	table_item["_craft_result_id"] = recipe.get("result", 0)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = recipe.get("craft_time", 3.0)
	timer.timeout.connect(_on_craft_timeout.bind(table_item))
	add_child(timer)
	timer.start()
	table_item["_craft_timer"] = timer

	table_state_changed.emit(table_item, TableState.CRAFTING)
	return true

func restore_craft_timers() -> void:
	# Called after server state restore — recreates local timers for CRAFTING tables
	print("[Crafting] restore_craft_timers: grid has ", GridManager.count_items(), " items")
	for entry in GridManager.get_all_items():
		var cs: int = entry.data.get("_craft_state", -1)
		if cs != -1:
			print("[Crafting]   item #", entry.data.get("id", 0), " at (", entry.pos.x, ",", entry.pos.y, ") craft_state=", cs)
	for entry in GridManager.get_all_items():
		var item: Dictionary = entry.data
		if item.get("_craft_state", TableState.IDLE) != TableState.CRAFTING:
			continue
		var recipe: Dictionary = item.get("_craft_recipe", {})
		if recipe.is_empty():
			continue
		var total_time: float = recipe.get("craft_time", 3.0)
		var start_time: float = item.get("_craft_start_time", 0)
		var elapsed: float = (Time.get_unix_time_from_system() * 1000 - start_time) / 1000.0
		var remaining: float = maxf(0, total_time - elapsed)

		if remaining <= 0:
			_set_state(item, TableState.READY)
			item["_craft_progress"] = 1.0
			table_state_changed.emit(item, TableState.READY)
			continue

		# Clean up old timer if exists, then create new one
		var old_timer: Timer = item.get("_craft_timer")
		if old_timer and is_instance_valid(old_timer):
			old_timer.queue_free()
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = remaining
		timer.timeout.connect(_on_craft_timeout.bind(item))
		add_child(timer)
		timer.start()
		item["_craft_timer"] = timer
		table_state_changed.emit(item, TableState.CRAFTING)

func restore_craft_timer_for_item(item: Dictionary) -> void:
	if item.get("_craft_state", TableState.IDLE) != TableState.CRAFTING:
		return
	var recipe: Dictionary = item.get("_craft_recipe", {})
	if recipe.is_empty():
		return
	var total_time: float = recipe.get("craft_time", 3.0)
	var start_time: float = item.get("_craft_start_time", 0)
	var elapsed: float = (Time.get_unix_time_from_system() * 1000 - start_time) / 1000.0
	var remaining: float = maxf(0, total_time - elapsed)
	if remaining <= 0:
		_set_state(item, TableState.READY)
		item["_craft_progress"] = 1.0
		table_state_changed.emit(item, TableState.READY)
		return
	var old_timer: Timer = item.get("_craft_timer")
	if old_timer and is_instance_valid(old_timer):
		old_timer.queue_free()
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = remaining
	timer.timeout.connect(_on_craft_timeout.bind(item))
	add_child(timer)
	timer.start()
	item["_craft_timer"] = timer
	table_state_changed.emit(item, TableState.CRAFTING)

func get_remaining_craft_seconds(table_item: Dictionary) -> float:
	var timer: Timer = table_item.get("_craft_timer")
	if not is_instance_valid(timer) or not timer.is_inside_tree():
		return 0.0
	return timer.time_left

func _on_craft_timeout(table_item: Dictionary) -> void:
	_set_state(table_item, TableState.READY)
	table_item["_craft_progress"] = 1.0
	var timer: Timer = table_item.get("_craft_timer")
	if timer:
		timer.queue_free()
		table_item.erase("_craft_timer")
	table_state_changed.emit(table_item, TableState.READY)

func retrieve(table_item: Dictionary) -> int:
	if _get_state(table_item) != TableState.READY:
		return -1
	var result_id: int = table_item.get("_craft_result_id", -1)
	_clear_craft_data(table_item)
	table_state_changed.emit(table_item, TableState.IDLE)
	return result_id

func get_stored_items(table_item: Dictionary) -> Array:
	return table_item.get("_craft_stored", [])

func get_current_recipe(table_item: Dictionary) -> Dictionary:
	return table_item.get("_craft_recipe", {})

func _clear_craft_data(table_item: Dictionary) -> void:
	var timer: Timer = table_item.get("_craft_timer")
	if timer:
		timer.queue_free()
	for key in ["_craft_init", "_craft_state", "_craft_stored", "_craft_recipe",
			"_craft_progress", "_craft_result_id", "_craft_timer"]:
		table_item.erase(key)

func reset_all() -> void:
	for child in get_children():
		if child is Timer:
			child.queue_free()

# Remove one ingredient by ID. Returns the removed item data, or empty dict if not found.
func remove_ingredient(table_item: Dictionary, item_id: int) -> Dictionary:
	var stored: Array = table_item.get("_craft_stored", [])
	for i in range(stored.size()):
		if stored[i].get("id", 0) == item_id:
			var removed: Dictionary = stored[i]
			stored.remove_at(i)
			_recheck_recipe(table_item)
			if stored.is_empty():
				_set_state(table_item, TableState.IDLE)
			table_state_changed.emit(table_item, TableState.HAS_ITEMS if not stored.is_empty() else TableState.IDLE)
			return removed
	return {}

func _recheck_recipe(table_item: Dictionary) -> void:
	var stored: Array = table_item.get("_craft_stored", [])
	if stored.is_empty():
		table_item.erase("_craft_recipe")
		return
	var table_id: int = table_item.get("id", 0)
	var allowed_recipes: Array = ConfigDatabase.get_recipes_for_item(table_id)
	var recipe := _match_recipe(stored, allowed_recipes)
	if not recipe.is_empty():
		table_item["_craft_recipe"] = recipe
	else:
		table_item.erase("_craft_recipe")

# --- Recipe matching ---

func _match_recipe(stored: Array, recipes: Array) -> Dictionary:
	var stored_counts: Dictionary = {}
	for s in stored:
		var sid: int = s.get("id", 0) as int
		stored_counts[sid] = stored_counts.get(sid, 0) + 1

	for recipe in recipes:
		var ingredients: Array = recipe.get("ingredients", [])
		if stored.size() != ingredients.size():
			continue
		var recipe_counts: Dictionary = {}
		for ing_id in ingredients:
			var iid: int = ing_id as int
			recipe_counts[iid] = recipe_counts.get(iid, 0) + 1
		var matched := true
		for iid in recipe_counts:
			if stored_counts.get(iid, 0) != recipe_counts[iid]:
				matched = false
				break
		if matched:
			return recipe
	return {}
