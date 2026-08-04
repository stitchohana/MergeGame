class_name AcupointNode extends Control

signal acupoint_selected(index: int)

@export_range(0, 99) var acupoint_index: int = 0

@onready var activate_button: Button = $ActivateButton
@onready var glow_control: ColorRect = $CultivationGlow
@onready var cyan_icon: Sprite2D = $CultivationStarCyan
@onready var gold_icon: Sprite2D = $CultivationStarGold

const CYAN_GLOW_COLOR: Color = Color(0.28, 0.9, 1.0, 1.0)
const GOLD_GLOW_COLOR: Color = Color(1.0, 0.76, 0.28, 1.0)

var _lit: bool = false
var _completed: int = 0
var _total: int = 1
var _pulse_time: float = 0.0
var _glow_material: ShaderMaterial


func _ready() -> void:
	_glow_material = glow_control.material as ShaderMaterial
	glow_control.show()
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


func hide_activation() -> void:
	activate_button.hide()
	activate_button.disabled = false


func _on_activate_pressed() -> void:
	acupoint_selected.emit(acupoint_index)


func _process(delta: float) -> void:
	_pulse_time += delta
	if not is_instance_valid(_glow_material):
		return
	var pulse: float = (sin(_pulse_time * 2.5) + 1.0) * 0.5
	_glow_material.set_shader_parameter("glow_opacity", lerpf(0.6, 1.0, pulse))


func _apply_visuals() -> void:
	if is_instance_valid(cyan_icon):
		cyan_icon.visible = not _lit
	if is_instance_valid(gold_icon):
		gold_icon.visible = _lit
	if is_instance_valid(_glow_material):
		_glow_material.set_shader_parameter("glow_color", GOLD_GLOW_COLOR if _lit else CYAN_GLOW_COLOR)
