extends Control

# Main: Thin entry point. Pushes the initial screen onto UIManager.

var _toast: Node = null

func _ready() -> void:
	randomize()
	await get_tree().process_frame

	# Register screen navigation
	EventBus.screen_change_requested.connect(_on_screen_change_requested)

	# Kick back to login on disconnect
	CloudService.kicked.connect(_on_kicked)

	# Toast notifications
	EventBus.show_toast.connect(_on_show_toast)
	_setup_toast()

	# Push the login screen first
	var login := preload("res://scenes/screens/LoginScreen.tscn").instantiate()
	UIManager.push_screen(login)

func _setup_toast() -> void:
	_toast = preload("res://scenes/ui/common/Toast.tscn").instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.add_child(_toast)
	add_child(layer)

func _on_show_toast(message: String) -> void:
	if _toast and is_instance_valid(_toast):
		_toast.show_message(message)

func _on_kicked() -> void:
	print("[Main] Kicked: connection lost, returning to login")
	UIManager.clear_all_screens()
	var login := preload("res://scenes/screens/LoginScreen.tscn").instantiate()
	UIManager.push_screen(login)

func _on_screen_change_requested(screen_name: String) -> void:
	match screen_name:
		"login":
			var login := preload("res://scenes/screens/LoginScreen.tscn").instantiate()
			UIManager.push_screen(login)
		"home":
			SceneTransitionManager.load_scene_and_replace("res://scenes/screens/HomeScreen.tscn")
		"game":
			SceneTransitionManager.load_scene_and_replace("res://scenes/screens/GameScreen.tscn")
		"battle":
			SceneTransitionManager.load_scene_and_replace("res://scenes/screens/BattleScreen.tscn")
		"settings":
			var settings_scene := load("res://scenes/screens/SettingsScreen.tscn") as PackedScene
			if settings_scene:
				UIManager.push_screen(settings_scene.instantiate())
			else:
				push_error("[Main] Settings scene is unavailable")
