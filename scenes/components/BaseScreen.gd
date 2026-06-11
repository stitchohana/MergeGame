class_name BaseScreen extends Control

# Lifecycle: on_enter -> (on_pause -> on_resume)* -> on_exit
# Subclasses override only what they need.

func _init() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	pass

func on_enter() -> void:
	pass

func on_exit() -> void:
	pass

func on_pause() -> void:
	pass

func on_resume() -> void:
	pass
