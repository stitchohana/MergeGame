extends Node

# SaveManager: Persists game state via the server.
# No local auto-save — server is the authoritative data source.
# Local cache is only for recovery during reconnect.

signal save_completed(slot: int)
signal load_completed(slot: int, data: Dictionary)
signal load_failed(slot: int)

const SAVE_SLOTS := 3
const SAVE_PATH_PREFIX := "user://save_"

func _ready() -> void:
	pass  # No local autosave — server persists

# --- Server-side restore (called by LoginScreen after fetch_state) ---

func _restore_from_server(state: Dictionary) -> void:
	# Game state
	GameState.score = state.get("score", 0)
	GameState.high_score = state.get("high_score", 0)
	GameState.version = state.get("version", 0)
	GameState.score_changed.emit(GameState.score)
	GameState.high_score_changed.emit(GameState.high_score)

	# Grid
	GridManager.init_grid()
	var grid_data: Array = state.get("grid", [])
	for entry in grid_data:
		var item_data := ConfigDatabase.get_item_data(entry.get("id", 0))
		if not item_data.is_empty():
			var pos := Vector2i(entry.get("col", 0), entry.get("row", 0))
			var new_item := item_data.duplicate(true)
			# Restore crafting state
			var craft_data: Dictionary = entry.get("craft", {})
			if not craft_data.is_empty():
				for key in craft_data:
					new_item[key] = craft_data[key]
			GridManager.add_item(new_item, pos)

	# Cultivation
	var cultivation_data: Dictionary = state.get("cultivation", {})
	if not cultivation_data.is_empty():
		CultivationService.deserialize(cultivation_data)

# --- Collect current state (for server submission if needed) ---

func _collect_all_data() -> Dictionary:
	return {
		"version": GameState.version,
		"game": {
			"score": GameState.score,
			"high_score": GameState.high_score,
		},
		"grid": _collect_grid_data(),
		"cultivation": CultivationService.serialize(),
	}

func _collect_grid_data() -> Array:
	var items: Array = []
	for entry in GridManager.get_all_items():
		var data: Dictionary = entry.data.duplicate(true)
		var pos: Vector2i = entry.pos
		var save_entry := {
			"id": data.get("id", 0),
			"col": pos.x,
			"row": pos.y,
		}
		if data.has("_craft_init"):
			var craft_data: Dictionary = {}
			for key in ["_craft_init", "_craft_state", "_craft_stored", "_craft_recipe",
					"_craft_progress", "_craft_result_id"]:
				if data.has(key):
					craft_data[key] = data[key]
			if not craft_data.is_empty():
				save_entry["craft"] = craft_data
		items.append(save_entry)
	return items

# --- Local save slots (for offline caching, not primary storage) ---

func save_game(slot: int) -> bool:
	if slot < 0 or slot >= SAVE_SLOTS:
		return false
	var data := _collect_all_data()
	var json_text := JSON.new().stringify(data, "\t")
	var path := SAVE_PATH_PREFIX + str(slot) + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_text)
		file.close()
		save_completed.emit(slot)
		return true
	return false

func load_game(slot: int) -> Dictionary:
	if slot < 0 or slot >= SAVE_SLOTS:
		return {}
	var path := SAVE_PATH_PREFIX + str(slot) + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(text) == OK:
			var data: Dictionary = json.data
			load_completed.emit(slot, data)
			return data
	load_failed.emit(slot)
	return {}

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_PATH_PREFIX + str(slot) + ".json")

func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(SAVE_PATH_PREFIX + str(slot) + ".json")

# --- Legacy autosave removed — server is authoritative ---

func load_autosave() -> void:
	pass  # No-op: use server state via LoginScreen instead
