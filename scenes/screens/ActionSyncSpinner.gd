class_name ActionSyncSpinner extends Control

const LINE_WIDTH: float = 5.0
const ROTATION_SPEED: float = 4.5
const ARC_COLOR: Color = Color(0.91, 0.74, 0.34, 1.0)
const TRACK_COLOR: Color = Color(1.0, 1.0, 1.0, 0.16)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	queue_redraw()

func _process(delta: float) -> void:
	rotation += ROTATION_SPEED * delta

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = maxf(1.0, minf(size.x, size.y) * 0.5 - LINE_WIDTH)
	draw_arc(center, radius, 0.0, TAU, 48, TRACK_COLOR, LINE_WIDTH, true)
	draw_arc(center, radius, -PI * 0.5, PI * 0.85, 32, ARC_COLOR, LINE_WIDTH, true)
