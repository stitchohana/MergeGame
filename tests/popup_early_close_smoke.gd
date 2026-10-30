extends Node

func _ready() -> void:
	var popup: RecipeSourcePopup = preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
	UIManager.show_popup(popup)
	UIManager.hide_popup(popup)
	await get_tree().create_timer(0.5).timeout
	assert(not is_instance_valid(popup), "Closed popup must be freed")
	assert(UIManager._active_popups.is_empty())
	print("POPUP_EARLY_CLOSE_SMOKE_OK freed=true")
	get_tree().quit()
