class_name AcupointNode extends Button

signal acupoint_selected(index: int)

@export_range(0, 99) var acupoint_index: int = 0:
	set(value):
		acupoint_index = value
		if is_instance_valid(index_label):
			index_label.text = str(acupoint_index + 1)

@onready var index_label: Label = $IndexLabel
@onready var progress_label: Label = $ProgressLabel

var _lit: bool = false
var _completed: int = 0
var _total: int = 1


func _ready() -> void:
	pressed.connect(_on_pressed)
	index_label.text = str(acupoint_index + 1)
	_update_progress_text()
	_apply_visuals()


func set_lit(lit: bool) -> void:
	set_progress(1 if lit else 0, 1)


func set_progress(completed: int, total: int) -> void:
	_total = maxi(1, total)
	_completed = clampi(completed, 0, _total)
	_lit = _completed >= _total
	disabled = _lit
	_update_progress_text()
	_apply_visuals()


func _on_pressed() -> void:
	if not _lit:
		acupoint_selected.emit(acupoint_index)


func _update_progress_text() -> void:
	if not is_instance_valid(progress_label):
		return
	progress_label.text = "%d/%d" % [_completed, _total]
	tooltip_text = "穴位 %d：%d/%d" % [acupoint_index + 1, _completed, _total]


func _apply_visuals() -> void:
	if not is_instance_valid(index_label):
		return
	if _lit:
		var lit_style := _make_style(Color(0.9, 0.67, 0.2, 0.96), Color(1.0, 0.92, 0.55, 1.0), 3)
		add_theme_stylebox_override("normal", lit_style)
		add_theme_stylebox_override("hover", lit_style)
		add_theme_stylebox_override("pressed", lit_style)
		add_theme_stylebox_override("disabled", lit_style)
		index_label.add_theme_color_override("font_color", Color(0.24, 0.15, 0.04, 1.0))
		progress_label.add_theme_color_override("font_color", Color(0.24, 0.15, 0.04, 1.0))
	elif _completed > 0:
		add_theme_stylebox_override("normal", _make_style(Color(0.38, 0.3, 0.12, 0.94), Color(1.0, 0.78, 0.24, 1.0), 2))
		add_theme_stylebox_override("hover", _make_style(Color(0.5, 0.39, 0.14, 0.98), Color(1.0, 0.9, 0.5, 1.0), 3))
		add_theme_stylebox_override("pressed", _make_style(Color(0.3, 0.23, 0.09, 1.0), Color(1.0, 0.72, 0.18, 1.0), 3))
		index_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.7, 1.0))
		progress_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.7, 1.0))
	else:
		add_theme_stylebox_override("normal", _make_style(Color(0.14, 0.28, 0.22, 0.9), Color(0.77, 0.87, 0.67, 0.95), 2))
		add_theme_stylebox_override("hover", _make_style(Color(0.23, 0.48, 0.34, 0.98), Color(1.0, 0.88, 0.39, 1.0), 3))
		add_theme_stylebox_override("pressed", _make_style(Color(0.1, 0.22, 0.17, 1.0), Color(1.0, 0.78, 0.24, 1.0), 3))
		add_theme_stylebox_override("disabled", _make_style(Color(0.14, 0.28, 0.22, 0.9), Color(0.77, 0.87, 0.67, 0.95), 2))
		index_label.add_theme_color_override("font_color", Color(0.96, 0.98, 0.87, 1.0))
		progress_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.76, 1.0))


func _make_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(28)
	style.shadow_color = Color(0.04, 0.1, 0.07, 0.45)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	return style
