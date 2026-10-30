extends RefCounted

# Shared main-board gesture and visual movement. Board owners supply hit testing,
# permissions and settlement; this controller has no dependency on board storage.
enum Motion { NONE, START, FOLLOW }
enum Release { NONE, CLICK, DROP }

const DRAG_THRESHOLD: float = 10.0
const MOVE_DURATION: float = 0.15
var _pressed: bool = false
var _moved: bool = false
var _origin: Vector2 = Vector2.ZERO


func press(position: Vector2) -> void:
	_pressed = true
	_moved = false
	_origin = position


func motion(position: Vector2, dragging: bool) -> Motion:
	if dragging:
		return Motion.FOLLOW
	if _pressed and not _moved and position.distance_to(_origin) > DRAG_THRESHOLD:
		_moved = true
		return Motion.START
	return Motion.NONE


func release(dragging: bool) -> Release:
	var result: Release = Release.DROP if dragging else Release.CLICK if _pressed and not _moved else Release.NONE
	cancel()
	return result


func cancel() -> void:
	_pressed = false
	_moved = false


static func follow(item: Control, pointer_position: Vector2, cell_step: float) -> void:
	item.position = pointer_position - Vector2.ONE * cell_step * 0.5


static func snap_back(item: Control, target: Vector2, animate: bool = true) -> Tween:
	if not animate:
		item.position = target
		return null
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "position", target, Constants.SNAP_BACK_DURATION)
	return tween


static func slide(item: Control, target: Vector2, parallel_tween: Tween = null) -> Tween:
	var tween: Tween = parallel_tween if parallel_tween != null else item.create_tween()
	tween.tween_property(item, "position", target, MOVE_DURATION)
	return tween
