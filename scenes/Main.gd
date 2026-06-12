extends Control

# Main: Thin entry point. Pushes the initial screen onto UIManager.

var _toast: Label = null
var _toast_tween: Tween = null

func _ready() -> void:
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
	UIManager.push_screen(login, UIManager.Transition.FADE)

func _setup_toast() -> void:
	_toast = Label.new()
	_toast.name = "Toast"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_toast.modulate.a = 0.0
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.0
	_toast.offset_top = 60
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_bottom = 100
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

func _on_show_toast(message: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = message
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)

func _on_kicked() -> void:
	print("[Main] Kicked: connection lost, returning to login")
	UIManager.clear_all_screens()
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
