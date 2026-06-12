extends Control

# Main: Thin entry point. Pushes the initial screen onto UIManager.

func _ready() -> void:
	await get_tree().process_frame

	# Register screen navigation
	EventBus.screen_change_requested.connect(_on_screen_change_requested)

	# Push the login screen first
	var login := preload("res://scenes/screens/LoginScreen.tscn").instantiate()
	UIManager.push_screen(login, UIManager.Transition.FADE)

func _on_screen_change_requested(screen_name: String) -> void:
	match screen_name:
		"login":
			var login := preload("res://scenes/screens/LoginScreen.tscn").instantiate()
			UIManager.push_screen(login, UIManager.Transition.FADE)
		"game":
			var game := preload("res://scenes/screens/GameScreen.tscn").instantiate()
			UIManager.replace_top_screen(game, UIManager.Transition.FADE)
		"settings":
			var settings := preload("res://scenes/screens/SettingsScreen.tscn").instantiate()
			UIManager.push_screen(settings, UIManager.Transition.SLIDE_LEFT)
