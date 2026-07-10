class_name LoadingScreen extends Control

@onready var progress_bar: ProgressBar = $Panel/VBoxContainer/ProgressBar
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

var _dot_timer: float = 0.0
var _base_message: String = "加载中"


func _ready() -> void:
	progress_bar.value = 0.0
	_base_message = "加载中"
	status_label.text = _base_message


func _process(delta: float) -> void:
	_dot_timer += delta
	var dots := "."
	var count := int(_dot_timer * 3.0) % 4
	for i in count:
		dots += "."
	status_label.text = _base_message + dots


func get_progress() -> float:
	if progress_bar:
		return progress_bar.value
	return 0.0


func set_progress(ratio: float) -> void:
	if progress_bar:
		progress_bar.value = ratio


func set_message(message: String) -> void:
	_base_message = message
