class_name TopResource extends Control

@onready var value_label: Label = $Label
@onready var regen_timer_label: Label = $RegenTimerLabel


func set_value(value: int) -> void:
	value_label.text = "%d" % value


func set_regen_timer(time_left: float) -> void:
	if time_left <= 0.0:
		regen_timer_label.text = ""
		return

	var seconds: int = int(ceil(time_left))
	var minutes: int = seconds / 60
	regen_timer_label.text = "%02d:%02d" % [minutes, seconds % 60]
