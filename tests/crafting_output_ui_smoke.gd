extends Node

const RESULT_ID: int = 27002
const TABLE_ID: int = 17001

func _ready() -> void:
	await get_tree().process_frame
	var recipe: Dictionary = {
		"id": 2,
		"name": "产物显示测试",
		"ingredients": [5002, 9002],
		"result": RESULT_ID,
		"craft_time": 15,
	}

	var craft_button: CraftButton = preload("res://scenes/ui/main/CraftButton.tscn").instantiate() as CraftButton
	add_child(craft_button)
	await get_tree().process_frame
	assert(craft_button.z_index > RequirementList.ORDER_ANIMATION_FOREGROUND_Z)
	craft_button.show_for_recipe(recipe)
	assert(craft_button.visible)
	assert(craft_button.get_output_item_id() == RESULT_ID)
	assert(craft_button.output_slot.visible)
	assert(craft_button.output_slot.icon_rect.texture != null)

	var detail_panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(detail_panel)
	await get_tree().process_frame
	var table_data: Dictionary = ConfigDatabase.get_item_data(TABLE_ID).duplicate(true)
	table_data["_uid"] = 990001
	table_data["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table_data["_craft_recipe"] = recipe
	table_data["_craft_stored"] = [{"id": 5002, "uid": 990002}]
	detail_panel.show_item(table_data)
	assert(detail_panel.get_output_item_id() == RESULT_ID)
	assert(detail_panel.output_label.visible)
	assert(detail_panel.output_slot.visible)
	assert(detail_panel.output_slot.size == Vector2(80, 80))
	assert(detail_panel.output_slot.icon_rect.texture != null)
	assert(detail_panel.materials_container is ScrollContainer)
	assert(detail_panel.materials_container.drag_to_scroll)
	assert(detail_panel.materials_container.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	assert(detail_panel.materials_row is HBoxContainer)
	assert(detail_panel.materials_row.get_child_count() >= 1)
	var material_slot: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	assert(material_slot.size == Vector2(80, 80))
	var previous_orders: Array = GameState.meridian_acupoints.duplicate(true)
	GameState.meridian_acupoints = []
	detail_panel._refresh_materials()
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 2)
	var fallback_ghost: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	assert(is_equal_approx(fallback_ghost.modulate.a, 0.35))
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": RESULT_ID}]}]
	detail_panel._refresh_materials()
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 2)
	var ghost_slot: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	assert(is_equal_approx(ghost_slot.modulate.a, 0.35))
	assert(ghost_slot.item_data.get("id", 0) == 9002)
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}]}]
	detail_panel._refresh_materials()
	detail_panel._refresh_materials()
	await get_tree().process_frame
	var prioritized_recipe: Dictionary = detail_panel._find_order_recipe([])
	assert(prioritized_recipe.get("result", 0) == 27081)
	assert(detail_panel.materials_row.get_child_count() == 2)
	var intermediate_ghost: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	assert(is_equal_approx(intermediate_ghost.modulate.a, 0.35))
	assert(intermediate_ghost.item_data.get("id", 0) == 9002)
	assert(detail_panel.materials_container.get_global_rect().intersects(intermediate_ghost.get_global_rect()))
	table_data["_craft_stored"] = [
		{"id": 5002, "uid": 990002},
		{"id": 9002, "uid": 990004},
		{"id": 5002, "uid": 990005},
		{"id": 9002, "uid": 990006},
	]
	detail_panel.show_item(table_data)
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 4)
	assert(detail_panel.materials_row.size.x > detail_panel.materials_container.size.x)
	assert(detail_panel.materials_container.get_h_scroll_bar().max_value > 0.0)
	var scroll_slot: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	assert(scroll_slot.size == Vector2(80, 80))
	var board_recipe: Dictionary = {
		"id": 32,
		"name": "board product material test",
		"ingredients": [27002, 9004],
		"result": 27081,
		"craft_time": 15,
	}
	GridManager.init_grid()
	var board_product: Dictionary = ConfigDatabase.get_item_data(27002).duplicate(true)
	board_product["_uid"] = 990010
	assert(GridManager.add_item(board_product, Vector2i(0, 0)))
	GameState.meridian_acupoints = [{"completed": false, "items": [{"item_id": 27081}]}]
	table_data["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	table_data["_craft_recipe"] = board_recipe
	table_data["_craft_stored"] = [{"id": 9004, "uid": 990011}]
	detail_panel.show_item(table_data)
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 1)
	var board_material_slot: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	assert(board_material_slot.item_data.get("id", 0) == 9004)
	assert(detail_panel.get_output_item_id() == 27081)
	assert(is_equal_approx(detail_panel.output_slot.modulate.a, 1.0))
	GridManager.init_grid()
	table_data["_craft_recipe"] = recipe
	table_data["_craft_stored"] = [
		{"id": 5002, "uid": 990002},
		{"id": 9002, "uid": 990004},
		{"id": 5002, "uid": 990005},
		{"id": 9002, "uid": 990006},
	]
	GameState.meridian_acupoints = previous_orders
	table_data["_craft_state"] = CraftingService.TableState.READY
	table_data["_craft_recipe"] = {}
	table_data["_craft_result_id"] = RESULT_ID
	detail_panel._refresh_materials()
	await get_tree().process_frame
	assert(detail_panel.get_output_item_id() == RESULT_ID)
	assert(detail_panel.output_slot.visible)
	assert(ItemDetailPanel.format_countdown_hms(0.0) == "0秒")
	assert(ItemDetailPanel.format_countdown_hms(0.1) == "1秒")
	assert(ItemDetailPanel.format_countdown_hms(59.01) == "1分")
	assert(ItemDetailPanel.format_countdown_hms(120.0) == "2分")
	assert(ItemDetailPanel.format_countdown_hms(3600.0) == "1时")
	assert(ItemDetailPanel.format_countdown_hms(3723.0) == "1时2分3秒")
	assert(ItemDetailPanel.calculate_speedup_cost(0.0, 1.0) == 0)
	assert(ItemDetailPanel.calculate_speedup_cost(0.1, 1.0) == 1)
	assert(ItemDetailPanel.calculate_speedup_cost(60.0, 1.0) == 1)
	assert(ItemDetailPanel.calculate_speedup_cost(60.01, 1.0) == 2)
	assert(ItemDetailPanel.calculate_speedup_cost(120.0, 1.0) == 2)
	var launcher_data: Dictionary = ConfigDatabase.get_item_data(11001).duplicate(true)
	launcher_data["_uid"] = 990003
	launcher_data["charges"] = 0
	launcher_data["_recharge_remaining"] = 3723000.0
	detail_panel.show_item(launcher_data)
	assert(detail_panel.status_label.text == "充能中… 1时2分3秒")
	assert(detail_panel.speedup_btn.text == "立即完成（63灵石）")
	detail_panel.clear()
	assert(detail_panel.get_output_item_id() == 0)
	assert(not detail_panel.output_slot.visible)

	print("CRAFTING_OUTPUT_UI_SMOKE_OK result_id=", RESULT_ID)
	get_tree().quit()
