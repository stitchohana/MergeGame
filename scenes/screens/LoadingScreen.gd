class_name LoadingScreen extends BaseScreen

@onready var progress_bar: ProgressBar = $Panel/VBoxContainer/ProgressBar
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

var _dot_timer: float = 0.0
var _base_message: String = "加载中"

func on_enter() -> void:
	modulate = Color.TRANSPARENT
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

func set_progress(ratio: float, _message: String = "") -> void:
	if progress_bar:
		progress_bar.value = ratio
	_base_message = "加载中 %d%%" % int(ratio * 100)
