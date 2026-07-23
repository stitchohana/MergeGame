class_name BasePopup extends Control

signal hide_animation_finished

@export var animation_duration: float = 0.2
@export var close_on_click_outside: bool = true

var _animation_tween: Tween = null

func _init() -> void:
	hide()
	modulate = Color.TRANSPARENT
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false

func show_animated() -> void:
	_set_modal_input_blocking()
	_kill_animation_tween()
	show()
	modulate = Color.TRANSPARENT
	_animation_tween = create_tween()
	_animation_tween.set_ease(Tween.EASE_OUT)
	_animation_tween.tween_property(self, "modulate", Color.WHITE, animation_duration)
	
func hide_animated() -> void:
	_set_modal_input_blocking()
	_kill_animation_tween()
	_animation_tween = create_tween()
	_animation_tween.set_ease(Tween.EASE_IN)
	_animation_tween.tween_property(self, "modulate", Color.TRANSPARENT, animation_duration)
	_animation_tween.tween_callback(_finish_hide)

func _set_modal_input_blocking() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false

func _kill_animation_tween() -> void:
	if _animation_tween and _animation_tween.is_valid():
		_animation_tween.kill()
	_animation_tween = null

func _finish_hide() -> void:
	hide()
	_animation_tween = null
	hide_animation_finished.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		accept_event()
	
