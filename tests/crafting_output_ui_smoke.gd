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
	table_data["_craft_recipe"] = {}
	table_data["_craft_stored"] = [{"id": 27002, "uid": 990007}]
	detail_panel.show_item(table_data)
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 2)
	var stored_recipe_product: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	var nested_recipe_ghost: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	assert(stored_recipe_product.item_data.get("id", 0) == 27002)
	assert(is_equal_approx(stored_recipe_product.modulate.a, 1.0))
	assert(nested_recipe_ghost.item_data.get("id", 0) == 9004)
	assert(is_equal_approx(nested_recipe_ghost.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	assert(detail_panel.get_output_item_id() == 27081)
	assert(is_equal_approx(detail_panel.output_slot.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	GameState.meridian_acupoints = [{"completed": false, "item_ids": [27143]}]
	table_data["_craft_recipe"] = {}
	table_data["_craft_stored"] = []
	table_data.erase("_craft_init")
	detail_panel.show_item(table_data)
	var level_two_material: Dictionary = ConfigDatabase.get_item_data(6002).duplicate(true)
	level_two_material["_uid"] = 990008
	assert(not CraftingService.add_ingredient(table_data, level_two_material))
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 3)
	var cross_table_stored: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	var cross_table_ghost_a: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	var cross_table_ghost_b: ItemWidget = detail_panel.materials_row.get_child(2) as ItemWidget
	assert(cross_table_stored.item_data.get("id", 0) == 6002)
	assert(cross_table_ghost_a.item_data.get("id", 0) == 9004)
	assert(cross_table_ghost_b.item_data.get("id", 0) == 3004)
	assert(is_equal_approx(cross_table_ghost_a.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	assert(is_equal_approx(cross_table_ghost_b.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	assert(detail_panel.get_output_item_id() == 27054)
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
	assert(detail_panel.materials_row.get_child_count() == 2)
	var board_material_slot: ItemWidget = detail_panel.materials_row.get_child(0) as ItemWidget
	var board_material_ghost: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	assert(board_material_slot.item_data.get("id", 0) == 9004)
	assert(board_material_ghost.item_data.get("id", 0) == 27002)
	assert(is_equal_approx(board_material_ghost.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	assert(detail_panel.get_output_item_id() == 27081)
	assert(is_equal_approx(detail_panel.output_slot.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	# A board product cannot satisfy both its direct order and a parent recipe.
	GameState.meridian_acupoints = [
		{"completed": false, "item_ids": [27081]},
		{"completed": false, "item_ids": [27002]},
	]
	table_data["_craft_recipe"] = {}
	table_data["_craft_stored"] = [{"id": 9002, "uid": 990012}]
	detail_panel.show_item(table_data)
	await get_tree().process_frame
	assert(detail_panel._get_order_recipe_demand_counts(
		detail_panel._get_active_order_item_counts(), detail_panel._count_board_available_item_ids()
	).get(27002, 0) == 2)
	assert(detail_panel.materials_row.get_child_count() == 2)
	var shared_product_ghost: ItemWidget = detail_panel.materials_row.get_child(1) as ItemWidget
	assert(shared_product_ghost.item_data.get("id", 0) == 5002)
	assert(is_equal_approx(shared_product_ghost.modulate.a, ItemDetailPanel.PREVIEW_GHOST_ALPHA))
	assert(detail_panel.get_output_item_id() == 27002)
	var second_board_product: Dictionary = ConfigDatabase.get_item_data(27002).duplicate(true)
	second_board_product["_uid"] = 990013
	assert(GridManager.add_item(second_board_product, Vector2i(1, 0)))
	detail_panel._refresh_materials()
	await get_tree().process_frame
	assert(detail_panel.materials_row.get_child_count() == 1)
	GridManager.remove_item(Vector2i(1, 0))
	var finished_parent: Dictionary = ConfigDatabase.get_item_data(27081).duplicate(true)
	finished_parent["_uid"] = 990014
	assert(GridManager.add_item(finished_parent, Vector2i(1, 0)))
	detail_panel._refresh_materials()
	await get_tree().process_frame
	assert(detail_panel._get_order_recipe_demand_counts(
		detail_panel._get_active_order_item_counts(), detail_panel._count_board_available_item_ids()
	).get(27002, 0) == 1)
	assert(detail_panel.materials_row.get_child_count() == 1)
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
	assert(ItemDetailPanel.format_countdown_hms(3723.0) == "1时2分")
	assert(TimeUtils.format_countdown(90061.0) == "1日1时")
	assert(TimeUtils.format_countdown(3661.0) == "1时1分")
	assert(ItemDetailPanel.calculate_speedup_cost(0.0, 1.0) == 0)
	assert(ItemDetailPanel.calculate_speedup_cost(0.1, 1.0) == 1)
	assert(ItemDetailPanel.calculate_speedup_cost(60.0, 1.0) == 1)
	assert(ItemDetailPanel.calculate_speedup_cost(60.01, 1.0) == 2)
	assert(ItemDetailPanel.calculate_speedup_cost(120.0, 1.0) == 2)
	# A server reconciliation can replace the table dictionary and remove the
	# scene-local Timer. The service must rebuild it from the craft timestamp so
	# the detail panel still receives a non-zero countdown.
	var syncing_table: Dictionary = ConfigDatabase.get_item_data(TABLE_ID).duplicate(true)
	syncing_table["_uid"] = 990020
	syncing_table["_craft_state"] = CraftingService.TableState.CRAFTING
	syncing_table["_craft_recipe"] = recipe
	syncing_table["_craft_result_id"] = RESULT_ID
	syncing_table["_craft_start_time"] = int(Time.get_unix_time_from_system() * 1000.0) - 4000
	assert(GridManager.add_item(syncing_table, Vector2i(3, 0)))
	var server_grid: Array = [{
		"uid": 990020,
		"id": TABLE_ID,
		"col": 3,
		"row": 0,
		"craft": {
			"_craft_init": true,
			"_craft_state": CraftingService.TableState.CRAFTING,
			"_craft_recipe": recipe,
			"_craft_result_id": RESULT_ID,
			"_craft_start_time": syncing_table["_craft_start_time"],
			"_craft_stored": [],
		},
	}]
	assert(GridManager.reconcile_from_server(server_grid))
	var reconciled_table: Dictionary = GridManager.find_by_uid(990020)
	assert(CraftingService.get_remaining_craft_seconds(reconciled_table) > 0.0)
	GridManager.remove_item(Vector2i(3, 0))
	var launcher_data: Dictionary = ConfigDatabase.get_item_data(11001).duplicate(true)
	launcher_data["_uid"] = 990003
	launcher_data["charges"] = 0
	launcher_data["_recharge_remaining"] = 3723000.0
	detail_panel.show_item(launcher_data)
	assert(detail_panel.status_label.text == "充能中… 1时2分")
	assert(detail_panel.speedup_btn.text == "立即完成（63灵石）")
	detail_panel.clear()
	assert(detail_panel.get_output_item_id() == 0)
	assert(not detail_panel.output_slot.visible)

	print("CRAFTING_OUTPUT_UI_SMOKE_OK result_id=", RESULT_ID)
	get_tree().quit()
