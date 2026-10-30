class_name CraftingRecipeHints extends RefCounted

# A single board-wide assignment drives destination hints and detail previews.
# Only one table recommends each output; loaded tables reserve it before empty
# ones, so a material already deposited cannot start the same recipe elsewhere.
static func build_assignments(extra_table: Dictionary = {}, extra_items: Array = [],
		selected_material_id: int = 0) -> Array[Dictionary]:
	var active_order_counts: Dictionary = _get_active_order_item_counts()
	var active_order_ids: Dictionary = _get_active_order_item_ids()
	var order_target_ids: Dictionary = _get_order_recipe_target_ids()
	var board_counts: Dictionary = _count_board_available_item_ids()
	var demand_counts: Dictionary = _get_order_recipe_demand_counts(active_order_counts, board_counts)
	var tables: Array[Dictionary] = []
	var extra_found: bool = false
	for entry: Dictionary in GridManager.get_all_items():
		var table: Dictionary = entry.get("data", {}) as Dictionary
		if int(table.get("type", 0)) != Constants.ItemType.CRAFTING or bool(table.get("immovable", false)):
			continue
		var state: int = int(table.get("_craft_state", CraftingService.TableState.IDLE))
		if state == CraftingService.TableState.CRAFTING or state == CraftingService.TableState.READY:
			continue
		extra_found = extra_found or _same_table(table, extra_table)
		tables.append({"table": table, "stored": CraftingService.get_stored_items(table), "index": tables.size()})
	if not extra_found and not extra_table.is_empty():
		tables.append({"table": extra_table, "stored": extra_items, "index": tables.size()})
	tables.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_count: int = (a["stored"] as Array).size()
		var b_count: int = (b["stored"] as Array).size()
		return a_count > b_count if a_count != b_count else int(a["index"]) < int(b["index"])
	)
	var claimed_results: Dictionary = {}
	for candidate: Dictionary in tables:
		var table: Dictionary = candidate["table"] as Dictionary
		var recipes: Array = ConfigDatabase.get_recipes_for_item(int(table.get("id", 0)))
		var stored: Array = candidate["stored"] as Array
		# Loaded tables keep their existing recipe reservations. Empty tables
		# choose an unclaimed recipe for the material currently being offered,
		# rather than reserving an unrelated recipe before that material is known.
		var required_material: int = selected_material_id if stored.is_empty() else 0
		var recipe: Dictionary = _choose_order_recipe(stored, recipes,
			board_counts, demand_counts, order_target_ids, active_order_ids, claimed_results,
			required_material)
		candidate["recipe"] = recipe
		if not recipe.is_empty():
			claimed_results[int(recipe.get("result", 0))] = true
	return tables


static func get_table_recipe(table: Dictionary, assignments: Array[Dictionary]) -> Dictionary:
	for assignment: Dictionary in assignments:
		if _same_table(table, assignment["table"] as Dictionary):
			return assignment.get("recipe", {}) as Dictionary
	return {}


static func choose_recipe(items: Array, recipes: Array) -> Dictionary:
	var orders: Dictionary = _get_active_order_item_counts()
	var board_counts: Dictionary = _count_board_available_item_ids()
	return _choose_order_recipe(items, recipes, board_counts,
		_get_order_recipe_demand_counts(orders, board_counts), _get_order_recipe_target_ids(),
		_get_active_order_item_ids(), {})


static func _same_table(a: Dictionary, b: Dictionary) -> bool:
	if is_same(a, b):
		return true
	var uid: int = int(a.get("_uid", 0))
	return uid > 0 and uid == int(b.get("_uid", 0))


static func _count_stored_item_ids(items: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item_variant in items:
		var item: Dictionary = item_variant as Dictionary
		var item_id: int = int(item.get("id", 0))
		counts[item_id] = int(counts.get(item_id, 0)) + 1
	return counts


static func _count_board_available_item_ids() -> Dictionary:
	var counts: Dictionary = GridManager.get_inventory_item_counts(false, false)
	# Started and ready outputs already cover one requested copy. Exclude
	# their satisfied recipes before ranking the remaining ghost previews.
	for entry: Dictionary in GridManager.get_inventory_items():
		var item: Dictionary = entry.get("data", {}) as Dictionary
		if int(item.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		var state: int = int(item.get("_craft_state", CraftingService.TableState.IDLE))
		if state != CraftingService.TableState.CRAFTING and state != CraftingService.TableState.READY:
			continue
		var result_id: int = int(item.get("_craft_result_id", 0))
		if result_id <= 0:
			var recipe: Dictionary = item.get("_craft_recipe", {}) as Dictionary
			result_id = int(recipe.get("result", 0))
		if result_id > 0:
			counts[result_id] = int(counts.get(result_id, 0)) + 1
	return counts


static func _count_recipe_ingredients(ingredients: Array) -> Dictionary:
	var counts: Dictionary = {}
	for ingredient_variant in ingredients:
		var ingredient_id: int = int(ingredient_variant)
		counts[ingredient_id] = int(counts.get(ingredient_id, 0)) + 1
	return counts


static func _get_active_order_item_ids() -> Dictionary:
	var order_item_ids: Dictionary = {}
	for item_id_variant: Variant in _get_active_order_item_counts().keys():
		order_item_ids[item_id_variant] = true
	return order_item_ids


static func _get_active_order_item_counts() -> Dictionary:
	var order_item_counts: Dictionary = {}
	for order_index: int in range(GameState.meridian_acupoints.size()):
		var order_variant: Variant = GameState.meridian_acupoints[order_index]
		var order: Dictionary = order_variant as Dictionary
		if bool(order.get("completed", false)):
			continue
		var configured: Array = order.get("item_ids", []) as Array
		for item_variant: Variant in configured:
			var item_id: int = int(item_variant)
			if item_id > 0:
				order_item_counts[item_id] = int(order_item_counts.get(item_id, 0)) + 1
	return order_item_counts


static func _get_order_recipe_demand_counts(order_counts: Dictionary, board_counts: Dictionary) -> Dictionary:
	var demand_counts: Dictionary = {}
	var expanded_counts: Dictionary = {}
	for item_id_variant: Variant in order_counts.keys():
		_expand_order_recipe_demand(int(item_id_variant), int(order_counts[item_id_variant]),
			demand_counts, expanded_counts, board_counts, {})
	return demand_counts


static func _expand_order_recipe_demand(item_id: int, count: int, demand_counts: Dictionary,
		expanded_counts: Dictionary, board_counts: Dictionary, path: Dictionary) -> void:
	if item_id <= 0 or count <= 0 or path.has(item_id):
		return
	demand_counts[item_id] = int(demand_counts.get(item_id, 0)) + count
	var shortage: int = maxi(0, int(demand_counts[item_id]) - int(board_counts.get(item_id, 0)))
	var to_expand: int = shortage - int(expanded_counts.get(item_id, 0))
	if to_expand <= 0:
		return
	expanded_counts[item_id] = shortage
	var ingredient_demands: Dictionary = {}
	for recipe_variant: Variant in ConfigDatabase.get_recipes_for_result(item_id):
		if not recipe_variant is Dictionary:
			continue
		var recipe_counts: Dictionary = _count_recipe_ingredients((recipe_variant as Dictionary).get("ingredients", []))
		for ingredient_id_variant: Variant in recipe_counts.keys():
			var ingredient_id: int = int(ingredient_id_variant)
			ingredient_demands[ingredient_id] = maxi(
				int(ingredient_demands.get(ingredient_id, 0)), int(recipe_counts[ingredient_id]))
	var next_path: Dictionary = path.duplicate()
	next_path[item_id] = true
	for ingredient_id_variant: Variant in ingredient_demands.keys():
		_expand_order_recipe_demand(int(ingredient_id_variant),
			to_expand * int(ingredient_demands[ingredient_id_variant]), demand_counts,
			expanded_counts, board_counts, next_path)


static func _get_order_recipe_target_ids() -> Dictionary:
	var target_ids: Dictionary = _get_active_order_item_ids()
	var visited_item_ids: Dictionary = {}
	for item_id_variant: Variant in target_ids.keys():
		_collect_order_recipe_target_ids(
			int(item_id_variant), target_ids, visited_item_ids
		)
	return target_ids


static func _collect_order_recipe_target_ids(
	item_id: int,
	target_ids: Dictionary,
	visited_item_ids: Dictionary
) -> void:
	if item_id <= 0 or visited_item_ids.has(item_id):
		return
	visited_item_ids[item_id] = true
	var result_recipes: Array = ConfigDatabase.get_recipes_for_result(item_id)
	for recipe_variant: Variant in result_recipes:
		if not recipe_variant is Dictionary:
			continue
		var recipe: Dictionary = recipe_variant as Dictionary
		for ingredient_variant: Variant in recipe.get("ingredients", []):
			var ingredient_id: int = int(ingredient_variant)
			var ingredient_recipes: Array = ConfigDatabase.get_recipes_for_result(ingredient_id)
			if ingredient_recipes.is_empty():
				continue
			target_ids[ingredient_id] = true
			_collect_order_recipe_target_ids(
				ingredient_id, target_ids, visited_item_ids
			)


static func _choose_order_recipe(items: Array, recipes: Array, board_counts: Dictionary,
		demand_counts: Dictionary, order_target_ids: Dictionary, active_order_item_ids: Dictionary,
		claimed_results: Dictionary, required_material: int = 0) -> Dictionary:
	var has_order_filter: bool = not order_target_ids.is_empty()
	var stored_counts: Dictionary = _count_stored_item_ids(items)
	var best_recipe: Dictionary = {}
	var best_order_priority: int = 2147483647
	var fewest_missing: int = 2147483647
	for recipe_variant in recipes:
		var recipe: Dictionary = recipe_variant as Dictionary
		var result_id: int = int(recipe.get("result", 0))
		if has_order_filter and not order_target_ids.has(result_id):
			continue
		if required_material > 0 and not (recipe.get("ingredients", []) as Array).has(required_material):
			continue
		if claimed_results.has(result_id):
			continue
		if int(board_counts.get(result_id, 0)) >= maxi(1, int(demand_counts.get(result_id, 0))):
			continue
		var recipe_ingredients: Array = recipe.get("ingredients", [])
		var required_counts: Dictionary = _count_recipe_ingredients(recipe_ingredients)
		var compatible: bool = true
		for item_id_variant in stored_counts.keys():
			var item_id: int = int(item_id_variant)
			if int(stored_counts[item_id]) > int(required_counts.get(item_id, 0)):
				compatible = false
				break
		if not compatible:
			continue
		var available_counts: Dictionary = stored_counts.duplicate()
		for board_item_id_variant in board_counts.keys():
			var board_item_id: int = int(board_item_id_variant)
			available_counts[board_item_id] = int(available_counts.get(board_item_id, 0)) + int(board_counts[board_item_id])
		var missing: int = 0
		for ingredient_variant in recipe_ingredients:
			var ingredient_id: int = int(ingredient_variant)
			var available: int = int(available_counts.get(ingredient_id, 0))
			if available > 0:
				available_counts[ingredient_id] = available - 1
			else:
				missing += 1
		var order_priority: int = 0
		if has_order_filter and not active_order_item_ids.has(result_id):
			order_priority = 1
		if order_priority < best_order_priority or (order_priority == best_order_priority and missing < fewest_missing):
			best_order_priority = order_priority
			fewest_missing = missing
			best_recipe = recipe
	return best_recipe
