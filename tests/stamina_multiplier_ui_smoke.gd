extends Node


func _ready() -> void:
	await get_tree().process_frame
	GameState.stamina_multiplier_max = 1
	GameState.stamina_multiplier_selected = 1
	GameState.stamina_multiplier_expires_at = 0
	GameState.stamina_multiplier_manual = false

	var future_ms: int = int(Time.get_unix_time_from_system() * 1000.0) + 3600000
	GameState.sync_stamina_multiplier({
		"stamina_multiplier_max": 4,
		"stamina_multiplier_expires_at": future_ms,
	})
	assert(GameState.stamina_multiplier_selected == 4)

	var control: StaminaMultiplierControl = preload(
		"res://scenes/ui/main/StaminaMultiplierControl.tscn"
	).instantiate() as StaminaMultiplierControl
	add_child(control)
	await get_tree().process_frame
	assert(control.visible)
	assert(control.multiplier_menu.text == "体力 ×4")
	assert(control.multiplier_menu.get_popup().item_count == 3)

	var game_screen: Control = preload("res://scenes/screens/GameScreen.tscn").instantiate()
	var top_bar: Control = game_screen.get_node("TopBar") as Control
	var multiplier_control: Control = game_screen.get_node("StaminaMultiplierControl") as Control
	var requirement_list: Control = game_screen.get_node("RequirementList") as Control
	assert(top_bar.position.y + top_bar.size.y <= multiplier_control.position.y)
	assert(multiplier_control.position.y + multiplier_control.size.y <= requirement_list.position.y)
	game_screen.free()

	GameState.select_stamina_multiplier(2)
	await get_tree().process_frame
	assert(GameState.stamina_multiplier_selected == 2)
	assert(GameState.stamina_multiplier_manual)
	assert(control.multiplier_menu.text == "体力 ×2")

	GameState.sync_stamina_multiplier({
		"stamina_multiplier_max": 4,
		"stamina_multiplier_expires_at": future_ms + 1000,
	})
	assert(GameState.stamina_multiplier_selected == 2)

	var upgraded: Dictionary = ConfigDatabase.get_upgraded_item_for_multiplier(5001, 4)
	assert(int(upgraded.get("id", 0)) == 5003)
	var mine: Dictionary = ConfigDatabase.get_item_data(25001)
	assert(ConfigDatabase.get_launcher_safe_stamina_multiplier(mine) == 8)

	var launcher_controller: LauncherController = LauncherController.new()
	launcher_controller._pending_spawns = [
		{"board_type": Constants.BoardType.MAIN, "is_no_cost": false, "stamina_cost": 4},
		{"board_type": Constants.BoardType.MAIN, "is_no_cost": false, "stamina_cost": 2},
		{"board_type": Constants.BoardType.MAIN, "is_no_cost": true, "stamina_cost": 8},
		{"board_type": Constants.BoardType.BATTLE, "is_no_cost": false, "stamina_cost": 8},
	]
	assert(launcher_controller._pending_paid_spawn_cost(Constants.BoardType.MAIN) == 6)
	assert(launcher_controller._pending_paid_spawn_cost(Constants.BoardType.BATTLE) == 1)
	launcher_controller._pending_spawns.clear()
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.meridian_acupoints = [{
		"item_ids": [5001, 5001],
		"items": [{"item_id": 5001}, {"item_id": 5001}],
		"completed": false,
	}]
	var first_order_plan: Dictionary = launcher_controller._get_order_priority_spawn(5001, 4)
	assert(int((first_order_plan.get("item", {}) as Dictionary).get("id", 0)) == 5001)
	assert(int(first_order_plan.get("multiplier", 0)) == 1)
	var first_order_item: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	first_order_item["_uid"] = 920001
	assert(GridManager.add_item(first_order_item, Vector2i(0, 0)))
	var second_order_plan: Dictionary = launcher_controller._get_order_priority_spawn(5001, 4)
	assert(int((second_order_plan.get("item", {}) as Dictionary).get("id", 0)) == 5001)
	var second_order_item: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	second_order_item["_uid"] = 920002
	assert(GridManager.add_item(second_order_item, Vector2i(1, 0)))
	var filled_order_plan: Dictionary = launcher_controller._get_order_priority_spawn(5001, 4)
	assert(int((filled_order_plan.get("item", {}) as Dictionary).get("id", 0)) == 5003)
	assert(int(filled_order_plan.get("multiplier", 0)) == 4)
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.meridian_acupoints = [{
		"item_ids": [14101],
		"items": [{"item_id": 14101}],
		"completed": false,
		"breakthrough_order": true,
	}]
	var unrelated_breakthrough_plan: Dictionary = launcher_controller._get_order_priority_spawn(
		13101, 4
	)
	assert(int((unrelated_breakthrough_plan.get("item", {}) as Dictionary).get("id", 0)) == 13103)
	assert(not bool(unrelated_breakthrough_plan.get("order_priority", false)))
	var breakthrough_plan: Dictionary = launcher_controller._get_order_priority_spawn(14102, 4)
	assert(int((breakthrough_plan.get("item", {}) as Dictionary).get("id", 0)) == 14101)
	assert(int(breakthrough_plan.get("multiplier", 0)) == 1)
	assert(bool(breakthrough_plan.get("order_priority", false)))
	GameState.meridian_acupoints = [{
		"item_ids": [27001],
		"items": [{"item_id": 27001}],
		"completed": false,
		"breakthrough_order": true,
	}]
	var locked_material: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	locked_material["_uid"] = 920003
	locked_material["immovable"] = true
	assert(GridManager.add_item(locked_material, Vector2i(0, 0)))
	var recipe_material_plan: Dictionary = launcher_controller._get_order_priority_spawn(5002, 4)
	assert(int((recipe_material_plan.get("item", {}) as Dictionary).get("id", 0)) == 5001)
	assert(int(recipe_material_plan.get("multiplier", 0)) == 1)
	assert(bool(recipe_material_plan.get("order_priority", false)))
	GridManager.remove_item(Vector2i(0, 0))
	var owned_material: Dictionary = ConfigDatabase.get_item_data(5001).duplicate(true)
	owned_material["_uid"] = 920004
	assert(GridManager.add_item(owned_material, Vector2i(0, 0)))
	var satisfied_material_plan: Dictionary = launcher_controller._get_order_priority_spawn(5002, 4)
	assert(int((satisfied_material_plan.get("item", {}) as Dictionary).get("id", 0)) == 5004)
	assert(not bool(satisfied_material_plan.get("order_priority", false)))
	GridManager.init_grid(Constants.BoardType.MAIN)
	GameState.meridian_acupoints = [{
		"item_ids": [27081],
		"items": [{"item_id": 27081}],
		"completed": false,
	}]
	var crafting_table: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
	crafting_table["_uid"] = 920005
	crafting_table["_craft_state"] = CraftingService.TableState.HAS_ITEMS
	crafting_table["_craft_stored"] = [{"id": 27002, "_uid": 920006}]
	crafting_table["_craft_recipe"] = {}
	crafting_table["_craft_result_id"] = -1
	assert(GridManager.add_item(crafting_table, Vector2i(0, 0)))
	var stored_intermediate_outstanding: Dictionary = (
		launcher_controller._get_outstanding_order_item_counts()
	)
	assert(not stored_intermediate_outstanding.has(27002))
	assert(not stored_intermediate_outstanding.has(5002))
	assert(not stored_intermediate_outstanding.has(9002))
	assert(int(stored_intermediate_outstanding.get(9004, 0)) == 1)
	var finished_results: Array[Dictionary] = []
	launcher_controller.spawn_finished.connect(func(result: Dictionary, _prediction: Dictionary):
		finished_results.append(result)
	)
	launcher_controller._pending_spawns = [{
		"request_id": "single-finish",
		"launcher_uid": 920010,
	}]
	var launcher_item: Dictionary = ConfigDatabase.get_item_data(11001).duplicate(true)
	launcher_item["_uid"] = 920010
	launcher_item["charges"] = 5
	assert(GridManager.add_item(launcher_item, Vector2i(2, 0)))
	launcher_controller._on_spawn_confirmed({
		"request_id": "single-finish",
		"charges": 4,
		"max_charges": 5,
		"recharge_time": 60,
	})
	assert(finished_results.size() == 1)
	launcher_controller.free()

	GameState.sync_stamina_multiplier({
		"stamina_multiplier_max": 4,
		"stamina_multiplier_expires_at": 1,
	})
	await get_tree().process_frame
	assert(GameState.stamina_multiplier_max == 1)
	assert(GameState.stamina_multiplier_selected == 1)
	assert(not control.visible)

	print("STAMINA_MULTIPLIER_UI_SMOKE_OK auto=true manual=true timer=true upgrade=true order_priority=true refund=true cap=true pending=true layout=true")
	get_tree().quit()
