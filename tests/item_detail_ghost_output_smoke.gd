extends Node

const RESULT_ID: int = 27002
const TABLE_ID: int = 17001


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var recipes: Array = ConfigDatabase.get_recipes_for_result(RESULT_ID)
	assert(not recipes.is_empty())
	var recipe: Dictionary = recipes[0] as Dictionary
	var ingredients: Array = recipe.get("ingredients", [])
	assert(ingredients.size() >= 2)

	var detail_panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(detail_panel)
	await get_tree().process_frame

	var table_data: Dictionary = ConfigDatabase.get_item_data(TABLE_ID).duplicate(true)
	table_data["_uid"] = 991001
	table_data["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table_data["_craft_stored"] = [{"id": int(ingredients[0]), "uid": 991002}]
	detail_panel.show_item(table_data)
	await get_tree().process_frame
	assert(detail_panel.output_slot.visible)
	assert(is_equal_approx(detail_panel.output_slot.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))

	table_data["_craft_stored"] = [
		{"id": int(ingredients[0]), "uid": 991002},
		{"id": int(ingredients[1]), "uid": 991003},
	]
	detail_panel.show_item(table_data)
	await get_tree().process_frame
	assert(is_equal_approx(detail_panel.output_slot.modulate.a, 1.0))

	print("ITEM_DETAIL_GHOST_OUTPUT_SMOKE_OK result_id=", RESULT_ID,
		" ghost_alpha=", ItemDetailPanel.PREVIEW_GHOST_ALPHA, " complete_alpha=1")
	get_tree().quit(0)
