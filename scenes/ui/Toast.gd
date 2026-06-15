extends Panel

# Toast: floating text notification at screen top. Auto-hides after a few seconds.

@onready var toast_label: Label = $HBox/Label

var _tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

func show_message(msg: String, duration: float = 2.5) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	toast_label.text = msg
	modulate.a = 1.0

	_tween = create_tween()
	_tween.tween_interval(duration)
	_tween.tween_property(self, "modulate:a", 0.0, 0.5)
