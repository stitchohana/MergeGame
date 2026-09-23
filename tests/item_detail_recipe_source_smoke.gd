extends Node

const RESULT_ID: int = 27002
const MERGE_FAMILY_SOURCE_ID: int = 3004


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var detail_panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(detail_panel)
	await get_tree().process_frame

	var recipe_product_data: Dictionary = ConfigDatabase.get_item_data(RESULT_ID).duplicate(true)
	assert(not recipe_product_data.is_empty())
	assert(not ConfigDatabase.get_recipes_for_result(RESULT_ID).is_empty())
	detail_panel.show_item(recipe_product_data)
	detail_panel._on_view_pressed()
	await get_tree().process_frame

	assert(not UIManager._active_popups.is_empty())
	var popup: BasePopup = UIManager._active_popups.back() as BasePopup
	assert(popup is RecipeSourcePopup)
	UIManager.hide_popup(popup)
	await get_tree().create_timer(0.5).timeout
	assert(not UIManager._active_popups.has(popup))

	var source_path: CraftPathView = preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	add_child(source_path)
	await get_tree().process_frame
	source_path.show_for_item(ConfigDatabase.get_item_data(MERGE_FAMILY_SOURCE_ID))
	assert(source_path.relation_label.text == "来源")
	assert(source_path.source_item.visible)
	assert(int(source_path.source_item.item_data.get("id", 0)) > 0)
	var source_ids: Array[int] = []
	for source: Dictionary in source_path._get_present_launchers_for_item(MERGE_FAMILY_SOURCE_ID):
		source_ids.append(int(source.get("id", 0)))
	assert(source_ids.has(13012))

	# An owned level-2 launcher must show its actual icon even when it has no
	# merge/crafting discovery record yet.
	GridManager.init_grid()
	GameState.set_crafted_item_ids([])
	var owned_launcher: Dictionary = ConfigDatabase.get_item_data(13002).duplicate(true)
	owned_launcher["_uid"] = 990031
	assert(GridManager.add_item(owned_launcher, Vector2i(0, 0)))
	assert(GridManager.get_positions_by_item_id(13002) == [Vector2i(0, 0)])
	source_path.show_for_item(ConfigDatabase.get_item_data(MERGE_FAMILY_SOURCE_ID))
	assert(int(source_path.source_item.item_data.get("id", 0)) == 13002)
	var source_icon: TextureRect = source_path.source_item.get_node("IconRect") as TextureRect
	var source_lock: TextureRect = source_path.source_item.get_node("IconLock") as TextureRect
	assert(source_icon.visible)
	assert(not source_lock.visible)
	GridManager.remove_item(Vector2i(0, 0))
	assert(GridManager.get_positions_by_item_id(13002).is_empty())
	source_path.queue_free()

	print("ITEM_DETAIL_RECIPE_SOURCE_SMOKE_OK result_id=", RESULT_ID, " popup=RecipeSourcePopup")
	get_tree().quit(0)
