class_name BasePopup extends Control

@export var animation_duration: float = 0.2
@export var close_on_click_outside: bool = true

func _init() -> void:
	hide()
	modulate = Color.TRANSPARENT
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_animated() -> void:
	show()
	modulate = Color.TRANSPARENT
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color.WHITE, animation_duration)
	
func hide_animated() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate", Color.TRANSPARENT, animation_duration)
	tween.tween_callback(hide)
	
