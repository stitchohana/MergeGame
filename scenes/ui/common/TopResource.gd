class_name TopResource extends Control

@export var icon_texture: Texture2D
@export var show_regen_timer: bool = true

@onready var value_label: Label = $Label
@onready var regen_timer_label: Label = $RegenTimerLabel

var _displayed_value: int = 0
var _value_initialized: bool = false
var _value_tween: Tween = null
var _value_pulse_tween: Tween = null

func _ready() -> void:
	if icon_texture:
		$Icon.texture = icon_texture
	regen_timer_label.visible = show_regen_timer
	value_label.pivot_offset = value_label.size * 0.5

func set_value(value: int) -> void:
	if not _value_initialized:
		_displayed_value = value
		_value_initialized = true
		value_label.text = "%d" % value
		return
	if value == _displayed_value:
		return
	_animate_value_to(value)

func animate_value_from(start_value: int, target_value: int) -> void:
	_value_initialized = true
	_displayed_value = start_value
	value_label.text = "%d" % start_value
	if start_value == target_value:
		return
	_animate_value_to(target_value)

func _animate_value_to(value: int) -> void:
	var start_value: int = _displayed_value
	if _value_tween and _value_tween.is_valid():
		_value_tween.kill()
	if _value_pulse_tween and _value_pulse_tween.is_valid():
		_value_pulse_tween.kill()
	value_label.scale = Vector2.ONE
	_value_tween = create_tween()
	_value_tween.set_trans(Tween.TRANS_QUAD)
	_value_tween.set_ease(Tween.EASE_OUT)
	_value_tween.tween_method(_set_displayed_value, float(start_value), float(value), Constants.TOP_RESOURCE_VALUE_ANIM_DURATION)
	_value_pulse_tween = create_tween()
	_value_pulse_tween.set_trans(Tween.TRANS_QUAD)
	_value_pulse_tween.set_ease(Tween.EASE_OUT)
	_value_pulse_tween.tween_property(value_label, "scale", Vector2.ONE * Constants.TOP_RESOURCE_VALUE_PULSE_SCALE, Constants.TOP_RESOURCE_VALUE_ANIM_DURATION * 0.3)
	_value_pulse_tween.set_ease(Tween.EASE_IN)
	_value_pulse_tween.tween_property(value_label, "scale", Vector2.ONE, Constants.TOP_RESOURCE_VALUE_ANIM_DURATION * 0.7)

func _set_displayed_value(value: float) -> void:
	_displayed_value = int(round(value))
	value_label.text = "%d" % _displayed_value


func set_regen_timer(time_left: float) -> void:
	if not show_regen_timer:
		return
	if time_left <= 0.0:
		regen_timer_label.text = ""
		return

	var seconds: int = int(ceil(time_left))
	var minutes: int = seconds / 60
	regen_timer_label.text = "%02d:%02d" % [minutes, seconds % 60]
