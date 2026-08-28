extends Node

const TABLE_ID: int = 17001

func _ready() -> void:
	var table_data: Dictionary = ConfigDatabase.get_item_data(TABLE_ID).duplicate(true)
	assert(not table_data.is_empty())
	var clean_table: Dictionary = table_data.duplicate(true)
	clean_table["_craft_stored"] = []
	var stored_table: Dictionary = table_data.duplicate(true)
	stored_table["_craft_stored"] = [{"id": 5002, "uid": 990004}]
	assert(MergeService.can_merge(clean_table, clean_table))
	assert(not MergeService.can_merge(stored_table, clean_table))
	assert(MergeService.is_merge_blocked_by_craft_materials(stored_table, clean_table))
	assert(MergeService._merge_error_text("craft_table_has_materials") == "无法合成")
	print("MERGE_CRAFTING_TABLE_SMOKE_OK blocked_with_material=true")
	get_tree().quit()
