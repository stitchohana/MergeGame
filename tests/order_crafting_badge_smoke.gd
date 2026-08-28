extends Node

const RESULT_ID: int = 27001


func _ready() -> void:
	await get_tree().process_frame
	_test_item_widget_badge()
	_test_requirement_entry_badge()
	_test_crafting_result_collection()
	print("ORDER_CRAFTING_BADGE_SMOKE_OK")
	get_tree().quit()


func _test_item_widget_badge() -> void:
	var widget: ItemWidget = preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	add_child(widget)
	assert(not widget.get_node("CraftingBadge").visible)
	widget.set_crafting_badge(true)
	assert(widget.get_node("CraftingBadge").visible)
	widget.set_crafting_badge(false)
	assert(not widget.get_node("CraftingBadge").visible)
	widget.queue_free()


func _test_requirement_entry_badge() -> void:
	var entry: RequirementEntry = preload("res://scenes/ui/meridian/RequirementEntry.tscn").instantiate() as RequirementEntry
	add_child(entry)
	entry.setup([{"item_id": RESULT_ID}], 0, false)
	entry.refresh_item_crafting({RESULT_ID: true})
	var widget: ItemWidget = entry.get_node("ItemsContainer").get_child(0) as ItemWidget
	assert(widget.get_node("CraftingBadge").visible)
	entry.refresh_item_crafting({})
	assert(not widget.get_node("CraftingBadge").visible)
	entry.queue_free()


func _test_crafting_result_collection() -> void:
	GridManager.init_grid()
	var table_data: Dictionary = ConfigDatabase.get_item_data(17001).duplicate(true)
	table_data["_uid"] = 990001
	table_data["_craft_state"] = CraftingService.TableState.CRAFTING
	table_data["_craft_result_id"] = RESULT_ID
	assert(GridManager.add_item(table_data, Vector2i(0, 0)))

	var screen: GameScreen = GameScreen.new()
	assert(screen._get_crafting_result_item_ids().has(RESULT_ID))
	var table_item: Dictionary = GridManager.get_item(Vector2i(0, 0))
	table_item["_craft_state"] = CraftingService.TableState.READY
	assert(not screen._get_crafting_result_item_ids().has(RESULT_ID))
	table_item["_craft_state"] = CraftingService.TableState.CRAFTING
	table_item["_craft_result_id"] = 0
	table_item["_craft_recipe"] = {"result": 27002}
	assert(screen._get_crafting_result_item_ids().has(27002))
	screen.free()
	GridManager.init_grid()
