class_name AcupointNode extends Control

signal acupoint_selected(index: int)

const ACUPOINT_INACTIVE: Texture2D = preload("res://assets/home/ui/acupoint_inactive.tres")
const ACUPOINT_ACTIVE: Texture2D = preload("res://assets/home/ui/acupoint_active.tres")
const ACUPOINT_CURRENT: Texture2D = preload("res://assets/home/ui/acupoint_current.tres")

@export_range(0, 99) var acupoint_index: int = 0

@onready var point_texture: TextureRect = $PointTexture
@onready var activate_button: Button = $ActivateButton

var _lit: bool = false
var _completed: int = 0
var _total: int = 1


func _ready() -> void:
	activate_button.pressed.connect(_on_activate_pressed)
	activate_button.hide()
	_apply_visuals()


func set_lit(lit: bool) -> void:
	set_progress(1 if lit else 0, 1)


func set_progress(completed: int, total: int) -> void:
	_total = maxi(1, total)
	_completed = clampi(completed, 0, _total)
	_lit = _completed >= _total
	_apply_visuals()


func show_activation(completed: int, total: int, qi_cost: int, pending: bool) -> void:
	activate_button.text = "激活中...\n%d/%d · 灵气 %d" % [completed, total, qi_cost] if pending else "激活\n%d/%d · 灵气 %d" % [completed, total, qi_cost]
	activate_button.disabled = pending
	activate_button.show()
	point_texture.texture = ACUPOINT_CURRENT


func hide_activation() -> void:
	activate_button.hide()
	activate_button.disabled = false


func _on_activate_pressed() -> void:
	acupoint_selected.emit(acupoint_index)


func _apply_visuals() -> void:
	if not is_instance_valid(point_texture):
		return
	if _lit:
		point_texture.texture = ACUPOINT_ACTIVE
	else:
		point_texture.texture = ACUPOINT_INACTIVE
