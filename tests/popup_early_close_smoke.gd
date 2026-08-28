extends Node

func _ready() -> void:
	var popup: RecipeSourcePopup = preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
	UIManager.show_popup(popup)
	UIManager.hide_popup(popup)
	await get_tree().create_timer(0.5).timeout
	print("[PopupEarlyClose] active=", UIManager._active_popups.size(), " path=", popup.get_path())
	get_tree().quit()
