class_name AcupointNode extends Control

signal acupoint_selected(index: int)

@export_range(0, 99) var acupoint_index: int = 0

@onready var activate_button: Button = $ActivateButton
@onready var cyan_icon: Sprite2D = $CultivationStarCyan
@onready var gold_icon: Sprite2D = $CultivationStarGold

var _lit: bool = false
var _completed: int = 0
var _total: int = 1
var _pulse_time: float = 0.0


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


func hide_activation() -> void:
	activate_button.hide()
	activate_button.disabled = false


func _on_activate_pressed() -> void:
	acupoint_selected.emit(acupoint_index)


func _process(delta: float) -> void:
	_pulse_time += delta
	var icon: Sprite2D = gold_icon if _lit else cyan_icon
	if not is_instance_valid(icon) or not icon.visible:
		return
	var pulse: float = (sin(_pulse_time * 2.5) + 1.0) * 0.5
	var glow_material := icon.material as ShaderMaterial
	if glow_material:
		glow_material.set_shader_parameter("glow_intensity", lerpf(0.65, 1.1, pulse))


func _apply_visuals() -> void:
	if is_instance_valid(cyan_icon):
		cyan_icon.visible = not _lit
	if is_instance_valid(gold_icon):
		gold_icon.visible = _lit
