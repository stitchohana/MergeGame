extends Node

# SaveManager: Auto-saves game state every second to JSON.
# Each autoload with persistent state provides serialize()/deserialize().

const AUTOSAVE_PATH := "user://autosave.json"
const SAVE_SLOTS := 3
const SAVE_PATH_PREFIX := "user://save_"

signal save_completed(slot: int)
signal load_completed(slot: int, data: Dictionary)
signal load_failed(slot: int)

var _save_timer: Timer = null
var _last_saved_data: Dictionary = {}

func _ready() -> void:
	_setup_autosave()

func _setup_autosave() -> void:
	_save_timer = Timer.new()
	_save_timer.name = "SaveTimer"
	_save_timer.wait_time = 1.0
	_save_timer.one_shot = false
	_save_timer.timeout.connect(_autosave)
	add_child(_save_timer)
	_save_timer.start()

func _autosave() -> void:
	var data := _collect_all_data()
	if data.hash() == _last_saved_data.hash():
		return
	var json_text := JSON.new().stringify(data, "\t")
	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_text)
		file.close()
		_last_saved_data = data

func load_autosave() -> void:
	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[SaveManager] Failed to parse autosave")
		return
	var data: Dictionary = json.data
	_restore_all_data(data)

func _collect_all_data() -> Dictionary:
	return {
		"version": 1,
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
		# Save crafting state (exclude non-serializable values)
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

func _restore_all_data(data: Dictionary) -> void:
	# Game state
	var game_data: Dictionary = data.get("game", {})
	if not game_data.is_empty():
		GameState.score = game_data.get("score", 0)
		GameState.high_score = game_data.get("high_score", 0)
		GameState.score_changed.emit(GameState.score)
		GameState.high_score_changed.emit(GameState.high_score)

	# Grid
	var grid_data: Array = data.get("grid", [])
	if not grid_data.is_empty():
		GridManager.init_grid()
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
	var cultivation_data: Dictionary = data.get("cultivation", {})
	if not cultivation_data.is_empty():
		CultivationService.deserialize(cultivation_data)

# --- Manual save slots (stub, for future use) ---

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
			_restore_all_data(data)
			load_completed.emit(slot, data)
			return data
	load_failed.emit(slot)
	return {}

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_PATH_PREFIX + str(slot) + ".json")

func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(SAVE_PATH_PREFIX + str(slot) + ".json")
