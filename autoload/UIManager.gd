extends Node

# UIManager: Central hub for UI layer management, screen stack,
# transition animations, and input gating.

enum Layer {
	BACKGROUND = 0,
	GAME = 1,
	HUD = 2,
	OVERLAY = 3,
	POPUP = 4,
	TOOLTIP = 5,
	LOADING = 6,
}

enum Transition {
	NONE,
	FADE,
	SLIDE_LEFT,
	SLIDE_RIGHT,
	SCALE,
}

var transition_duration: float = 0.3

var _ui_root: Control
var _layers: Dictionary = {}
var _screen_stack: Array[BaseScreen] = []
var _active_popups: Array[BasePopup] = []
var _transition_tween: Tween = null

signal pre_screen_changed(screen_name: String, action: String)
signal post_screen_changed(screen_name: String, action: String)
signal input_blocked_changed(blocked: bool)

func _ready() -> void:
	# Root UI container inside a CanvasLayer so it renders above game content
	_ui_root = Control.new()
	_ui_root.name = "UIRoot"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cl := CanvasLayer.new()
	cl.layer = 1
	cl.add_child(_ui_root)
	get_tree().root.add_child.call_deferred(cl)

	# Create layer containers in Z-order (last child = topmost)
	var layer_order := [
		Layer.BACKGROUND, Layer.GAME, Layer.HUD, Layer.OVERLAY,
		Layer.POPUP, Layer.TOOLTIP, Layer.LOADING,
	]
	for layer in layer_order:
		var c := Control.new()
		c.name = "Layer_%s" % Layer.keys()[layer]
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui_root.add_child(c)
		_layers[layer] = c

	_update_input_gating()

func _exit_tree() -> void:
	if _ui_root and is_instance_valid(_ui_root):
		_ui_root.get_parent().queue_free()

# --- Layer access ---

func get_layer(layer: Layer) -> Control:
	return _layers.get(layer, null)

# --- Screen stack ---

func push_screen(screen: BaseScreen, transition: Transition = Transition.NONE) -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()

	pre_screen_changed.emit(screen.name if screen else "", "pushed")

	if _screen_stack.size() > 0:
		var top = _screen_stack.back()
		if is_instance_valid(top):
			top.on_pause()

	_layers[Layer.GAME].add_child(screen)
	_screen_stack.append(screen)

	if transition != Transition.NONE:
		_play_transition_in(screen, transition)
	else:
		screen.on_enter()
		post_screen_changed.emit(screen.name if screen else "", "pushed")

func pop_screen(transition: Transition = Transition.NONE) -> void:
	if _screen_stack.size() <= 1:
		return

	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()

	var screen: BaseScreen = _screen_stack.back()
	if not is_instance_valid(screen):
		_screen_stack.erase(screen)
		return

	pre_screen_changed.emit(screen.name, "popped")

	if transition != Transition.NONE:
		_play_transition_out(screen, transition, func():
			_on_screen_removed(screen)
		)
	else:
		_on_screen_removed(screen)

func replace_top_screen(screen: BaseScreen, transition: Transition = Transition.NONE) -> void:
	if _screen_stack.size() > 0:
		var old = _screen_stack.back()
		if is_instance_valid(old):
			old.on_exit()
			_screen_stack.erase(old)
			old.queue_free()
	_layers[Layer.GAME].add_child(screen)
	_screen_stack.append(screen)
	screen.on_enter()
	post_screen_changed.emit(screen.name if screen else "", "replaced")

func get_current_screen() -> BaseScreen:
	return _screen_stack.back() if _screen_stack.size() > 0 else null

func clear_all_screens() -> void:
	var screens_to_clear := _screen_stack.duplicate()
	for screen: BaseScreen in screens_to_clear:
		screen.on_exit()
		_screen_stack.erase(screen)
		screen.queue_free()

	var popups_to_clear := _active_popups.duplicate()
	for popup: BasePopup in popups_to_clear:
		hide_popup(popup)

func _on_screen_removed(screen: BaseScreen) -> void:
	screen.on_exit()
	_screen_stack.erase(screen)
	screen.queue_free()
	if _screen_stack.size() > 0:
		var resumed = _screen_stack.back()
		if is_instance_valid(resumed):
			resumed.on_resume()
	post_screen_changed.emit(
		_screen_stack.back().name if _screen_stack.size() > 0 else "",
		"resumed"
	)

# --- Popups ---

func show_popup(popup: BasePopup, layer: Layer = Layer.POPUP) -> void:
	_layers[layer].add_child(popup)
	popup.show_animated()
	_active_popups.append(popup)
	_update_input_gating()
	input_blocked_changed.emit(true)

func hide_popup(popup: BasePopup) -> void:
	popup.hide_animated()
	_active_popups.erase(popup)
	_update_input_gating()
	input_blocked_changed.emit(false)

func hide_top_popup() -> void:
	if _active_popups.size() > 0:
		hide_popup(_active_popups.back())

func is_input_blocked() -> bool:
	return _active_popups.size() > 0

func _update_input_gating() -> void:
	var blocked := is_input_blocked()
	var game_layer = _layers.get(Layer.GAME)
	if game_layer:
		game_layer.mouse_filter = Control.MOUSE_FILTER_STOP if blocked else Control.MOUSE_FILTER_IGNORE
	var hud_layer = _layers.get(Layer.HUD)
	if hud_layer:
		hud_layer.mouse_filter = Control.MOUSE_FILTER_STOP if blocked else Control.MOUSE_FILTER_IGNORE

# --- Transitions ---

func _play_transition_in(screen: BaseScreen, transition: Transition) -> void:
	_transition_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	match transition:
		Transition.FADE:
			screen.modulate = Color.TRANSPARENT
			_transition_tween.tween_property(screen, "modulate", Color.WHITE, transition_duration)
		Transition.SLIDE_LEFT:
			screen.position = Vector2(screen.size.x, 0)
			_transition_tween.tween_property(screen, "position", Vector2.ZERO, transition_duration)
		Transition.SLIDE_RIGHT:
			screen.position = Vector2(-screen.size.x, 0)
			_transition_tween.tween_property(screen, "position", Vector2.ZERO, transition_duration)
		Transition.SCALE:
			screen.scale = Vector2.ZERO
			_transition_tween.tween_property(screen, "scale", Vector2.ONE, transition_duration)
		_:
			screen.on_enter()
			post_screen_changed.emit(screen.name if screen else "", "pushed")
			return

	_transition_tween.tween_callback(func():
		screen.on_enter()
		post_screen_changed.emit(screen.name if screen else "", "pushed")
	)

func _play_transition_out(screen: BaseScreen, transition: Transition, on_complete: Callable) -> void:
	_transition_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	match transition:
		Transition.FADE:
			_transition_tween.tween_property(screen, "modulate", Color.TRANSPARENT, transition_duration)
		Transition.SLIDE_LEFT:
			_transition_tween.tween_property(screen, "position", Vector2(-screen.size.x, 0), transition_duration)
		Transition.SLIDE_RIGHT:
			_transition_tween.tween_property(screen, "position", Vector2(screen.size.x, 0), transition_duration)
		Transition.SCALE:
			_transition_tween.tween_property(screen, "scale", Vector2.ZERO, transition_duration)
		_:
			on_complete.call()
			return

	_transition_tween.tween_callback(on_complete)
