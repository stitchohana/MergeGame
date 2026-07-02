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
	GameState.version = state.get("version", 0)
	GameState.stamina = state.get("stamina", 100)
	GameState.max_stamina = state.get("max_stamina", 100)
	GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	GameState.regen_remaining_ms = state.get("regen_remaining_ms", 0.0)
	GameState.spirit_stones = state.get("spirit_stones", 0)
	GameState.spirit_stones_changed.emit(GameState.spirit_stones)

	# Grid
	GridManager.init_grid()
	GridManager._skip_anims = true
	var grid_data: Array = state.get("grid", [])
	print("[Save] restore: ", grid_data.size(), " items from server")
	for entry in grid_data:
		var item_data := ConfigDatabase.get_item_data(entry.get("id", 0))
		if not item_data.is_empty():
			var pos := Vector2i(entry.get("col", 0), entry.get("row", 0))
			var new_item := item_data.duplicate(true)
			# Restore crafting state
			var craft_data: Variant = entry.get("craft", {})
			if craft_data is Dictionary and not craft_data.is_empty():
				print("[Save]   table #", entry.get("id", 0), " has craft: ", craft_data.get("_craft_state", -1))
				for key in craft_data:
					new_item[key] = craft_data[key]
			# Restore launcher charges
			var entry_charges: Variant = entry.get("charges", null)
			if entry_charges != null:
				new_item["charges"] = entry_charges
			var recharge_rem: Variant = entry.get("_recharge_remaining", null)
			if recharge_rem != null:
				new_item["_recharge_remaining"] = recharge_rem
			# Restore storage data
			var entry_storage: Variant = entry.get("storage", null)
			if entry_storage != null:
				new_item["storage"] = entry_storage
			var entry_uid: Variant = entry.get("uid", null)
			print("[Save] item #" + str(entry.get("id", 0)) + " server uid=" + str(entry_uid))
			if entry_uid != null:
				new_item["_uid"] = entry_uid
			else:
				print("[Save]   WARNING: item #" + str(entry.get("id", 0)) + " has no uid!")
			var entry_immovable: Variant = entry.get("immovable", null)
			if entry_immovable != null:
				new_item["immovable"] = entry_immovable
			GridManager.add_item(new_item, pos)
		else:
			print("[Save]   unknown item id: ", entry.get("id", 0))

	# Cultivation
	var cultivation_data: Dictionary = state.get("cultivation", {})
	if not cultivation_data.is_empty():
		CultivationService.deserialize(cultivation_data)

	# Meridian
	GameState.meridian_acupoints = state.get("meridian_acupoints", [])
	StoragePouch.restore_from_server(state.get("pouch", []))
	GameState.meridian_circulations = state.get("meridian_circulations", 0)
	GameState.meridian_threshold_idx = state.get("meridian_threshold_idx", 0)

	# Restore crafting timers for in-progress crafts
	GridManager._skip_anims = false
	CraftingService.restore_craft_timers()

# --- Collect current state (for server submission if needed) ---

func _collect_all_data() -> Dictionary:
	return {
		"version": GameState.version,
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
