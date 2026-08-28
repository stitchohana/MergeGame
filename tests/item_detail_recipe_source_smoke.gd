extends Node

const RESULT_ID: int = 27002


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

	print("ITEM_DETAIL_RECIPE_SOURCE_SMOKE_OK result_id=", RESULT_ID, " popup=RecipeSourcePopup")
	get_tree().quit(0)
