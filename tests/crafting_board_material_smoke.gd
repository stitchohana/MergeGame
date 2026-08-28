extends Node

const BOARD_PRODUCT_ID: int = 27002
const DIRECT_ORDER_ID: int = 27081
const TABLE_ID: int = 17001

func _ready() -> void:
	await get_tree().process_frame
	var detail_panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(detail_panel)
	await get_tree().process_frame

	GridManager.init_grid()
	var board_product: Dictionary = ConfigDatabase.get_item_data(BOARD_PRODUCT_ID).duplicate(true)
	board_product["_uid"] = 991001
	assert(GridManager.add_item(board_product, Vector2i(0, 0)))

	var table_data: Dictionary = ConfigDatabase.get_item_data(TABLE_ID).duplicate(true)
	table_data["_uid"] = 991002
	table_data["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table_data["_craft_recipe"] = {
		"id": 32,
		"ingredients": [BOARD_PRODUCT_ID, 9004],
		"result": DIRECT_ORDER_ID,
		"craft_time": 15,
	}
	table_data["_craft_stored"] = [{"id": 9004, "uid": 991003}]
	GameState.meridian_acupoints = [{
		"completed": false,
		"items": [{"item_id": DIRECT_ORDER_ID}],
	}]
	detail_panel.show_item(table_data)
	await get_tree().process_frame

	assert(detail_panel.materials_row.get_child_count() == 1)
	var stored_slot: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	assert(stored_slot.item_data.get("id", 0) == 9004)
	assert(detail_panel.get_output_item_id() == DIRECT_ORDER_ID)
	assert(is_equal_approx(detail_panel.output_slot.modulate.a, 1.0))

	var prioritized_recipe: Dictionary = detail_panel._find_order_recipe([])
	assert(prioritized_recipe.get("result", 0) == DIRECT_ORDER_ID)

	print("CRAFTING_BOARD_MATERIAL_SMOKE_OK board_product_id=", BOARD_PRODUCT_ID,
		" selected_result_id=", int(prioritized_recipe.get("result", 0)))
	get_tree().quit()
