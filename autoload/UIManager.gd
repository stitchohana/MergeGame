extends Node

# UIManager: Central hub for UI layer management and screen stack.

enum Layer {
	BACKGROUND = 0,
	GAME = 1,
	HUD = 2,
	OVERLAY = 3,
	POPUP = 4,
	TOOLTIP = 5,
	LOADING = 6,
}

const LAYER_Z_STRIDE: int = 512

var _ui_root: Control
var _canvas_layer: CanvasLayer = null
var _layers: Dictionary = {}
var _screen_stack: Array[BaseScreen] = []
var _active_popups: Array[BasePopup] = []

signal pre_screen_changed(screen_name: String, action: String)
signal post_screen_changed(screen_name: String, action: String)
signal input_blocked_changed(blocked: bool)


func _ready() -> void:
	_ui_root = Control.new()
	_ui_root.name = "UIRoot"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 1
	_canvas_layer.add_child(_ui_root)
	get_tree().root.add_child.call_deferred(_canvas_layer)

	var layer_order := [
		Layer.BACKGROUND, Layer.GAME, Layer.HUD, Layer.OVERLAY,
		Layer.POPUP, Layer.TOOLTIP, Layer.LOADING,
	]
	for layer in layer_order:
		var c := Control.new()
		c.name = "Layer_%s" % Layer.keys()[layer]
		c.z_index = int(layer) * LAYER_Z_STRIDE
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui_root.add_child(c)
		_layers[layer] = c

	_update_input_gating()


func _exit_tree() -> void:
	if _canvas_layer and is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()


func get_layer(layer: Layer) -> Control:
	return _layers.get(layer, null)


# --- Screen stack ---

func push_screen(screen: BaseScreen) -> void:
	pre_screen_changed.emit(screen.name if screen else "", "pushed")

	if _screen_stack.size() > 0:
		var top = _screen_stack.back()
		if is_instance_valid(top):
			top.on_pause()

	_layers[Layer.GAME].add_child(screen)
	_screen_stack.append(screen)
	screen.on_enter()
	post_screen_changed.emit(screen.name if screen else "", "pushed")


func pop_screen() -> void:
	if _screen_stack.size() <= 1:
		return

	var screen: BaseScreen = _screen_stack.back()
	if not is_instance_valid(screen):
		_screen_stack.erase(screen)
		return

	pre_screen_changed.emit(screen.name, "popped")
	_on_screen_removed(screen)


func replace_top_screen(screen: BaseScreen) -> void:
	var old: BaseScreen = null
	if _screen_stack.size() > 0:
		old = _screen_stack.back()

	print("[UIMgr] replace_top_screen: screen=", screen.name, " old=", old.name if old else "null")
	_layers[Layer.GAME].add_child(screen)
	_screen_stack.append(screen)
	print("[UIMgr] screen added, scheduling call_deferred _finish_replace")
	call_deferred("_finish_replace", old, screen)


func _finish_replace(old: BaseScreen, screen: BaseScreen) -> void:
	print("[UIMgr] _finish_replace: screen=", screen.name, " old=", old.name if old else "null")
	if is_instance_valid(old):
		old.on_exit()
		print("[UIMgr] old.on_exit() done, erasing from stack")
		_screen_stack.erase(old)
		old.queue_free()
	print("[UIMgr] calling screen.on_enter(): ", screen.name)
	screen.on_enter()
	print("[UIMgr] on_enter done, emitting post_screen_changed")
	post_screen_changed.emit(screen.name if screen else "", "replaced")
	print("[UIMgr] _finish_replace complete")


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
	input_blocked_changed.emit(is_input_blocked())


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
