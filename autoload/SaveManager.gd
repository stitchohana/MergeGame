extends Node

# SaveManager: Handles save/load functionality.
# To be implemented in Phase 5.

const SAVE_SLOTS := 3
const SAVE_PATH_PREFIX := "user://save_"

signal save_completed(slot: int)
signal load_completed(slot: int, data: Dictionary)
signal load_failed(slot: int)

func save_game(slot: int) -> bool:
	if slot < 0 or slot >= SAVE_SLOTS:
		return false
	# TODO: Implement save serialization
	save_completed.emit(slot)
	return true

func load_game(slot: int) -> Dictionary:
	if slot < 0 or slot >= SAVE_SLOTS:
		return {}
	# TODO: Implement load deserialization
	return {}

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_PATH_PREFIX + str(slot) + ".json")

func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(SAVE_PATH_PREFIX + str(slot) + ".json")
