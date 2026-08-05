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
	GameState.regen_remaining_ms = state.get("regen_remaining_ms", 0.0)
	GameState.stamina = state.get("stamina", 100)
	GameState.max_stamina = state.get("max_stamina", 100)
	GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	GameState.spirit_stones = state.get("spirit_stones", 0)
	GameState.spirit_stones_changed.emit(GameState.spirit_stones)
	GameState.spawn_seed = state.get("spawn_seed", 0)
	GameState.spawn_sequence = state.get("spawn_sequence", 0)
	var crafted_item_ids: Array = state.get("crafted_item_ids", [])
	GameState.set_crafted_item_ids(crafted_item_ids)

	# Grid cache for both boards (cached only — grid is NOT repopulated here)
	GameState.main_grid_cache = state.get("main_grid", [])
	GameState.battle_grid_cache = state.get("battle_grid", [])
	GameState.home_meridian_defs = state.get("home_meridian_defs", [])
	GameState.home_meridian_progress = state.get("home_meridian_progress", [])
	print("[Save] main_grid_cache=", GameState.main_grid_cache.size(), " battle_grid_cache=", GameState.battle_grid_cache.size())

	# Cultivation
	var cultivation_data: Dictionary = state.get("cultivation", {})
	if not cultivation_data.is_empty():
		CultivationService.deserialize(cultivation_data)

	# Meridian
	GameState.meridian_acupoints = state.get("meridian_acupoints", [])
	StoragePouch.restore_from_server(state.get("pouch", []))
	GameState.meridian_circulations = state.get("meridian_circulations", 0)
	GameState.meridian_threshold_idx = state.get("meridian_threshold_idx", 0)

	# Activities
	GameState.activity_defs = state.get("activity_defs", [])
	GameState.activity_progress = state.get("activity_progress", {})
	GameState.activity_current_day = state.get("activity_current_day", 0)

	# Restore crafting timers for in-progress crafts
	GridManager._skip_anims = false
	CraftingService.restore_craft_timers()

# --- Collect current state (for server submission if needed) ---

func _collect_all_data() -> Dictionary:
	return {
		"game": {
		"spirit_stones": GameState.spirit_stones,
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
					"_craft_progress", "_craft_result_id", "_craft_start_time"]:
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
