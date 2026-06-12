extends Control

# Main: Thin entry point. Pushes the initial screen onto UIManager.

var _toast: Label = null
var _toast_panel: Panel = null
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
	# Root container — centered at top, self-sizing
	var panel := Panel.new()
	panel.name = "ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_top = 50
	panel.offset_left = 40
	panel.offset_right = -40
	panel.size.y = 0
	panel.self_modulate = Color(0, 0, 0, 0.85)
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.name = "ToastHBox"
	hbox.anchor_left = 0.5
	hbox.anchor_top = 0.5
	hbox.anchor_right = 0.5
	hbox.anchor_bottom = 0.5
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(hbox)

	_toast = Label.new()
	_toast.name = "ToastLabel"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_toast)

	_toast_panel = panel
	panel.modulate.a = 0.0

func _on_show_toast(message: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = message
	_toast_panel.modulate.a = 1.0

	# Auto-size panel to text
	_toast_panel.size.y = _toast.get_minimum_size().y + 20
	if _toast.get_minimum_size().x + 40 > _toast_panel.size.x:
		_toast_panel.size.x = min(_toast.get_minimum_size().x + 40, 700)

	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)

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
