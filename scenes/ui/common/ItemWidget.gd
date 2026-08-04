class_name ItemWidget extends Control

# Reusable item icon with selection and click handling.

signal selected(item_data: Dictionary)
signal pressed

var item_data: Dictionary = {}
var grid_position: Vector2i
var is_launcher: bool = false
var _is_selected: bool = false

@onready var icon_rect: TextureRect = $IconRect
@onready var select_icon: TextureRect = $SelectIcon
@onready var click_button: Button = $ClickButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	click_button.pressed.connect(_on_click_button_pressed)


func setup(data: Dictionary, pos: Vector2i = Vector2i(-1, -1), cell_size: int = 80) -> void:
	item_data = data
	is_launcher = data.get("type", 0) == Constants.ItemType.LAUNCHER
	if pos.x >= 0:
		grid_position = pos
		custom_minimum_size = Vector2(cell_size, cell_size)
		size = Vector2(cell_size, cell_size)
		position = Vector2(pos.x * cell_size, pos.y * cell_size)
	_update_visuals()


func _icon() -> TextureRect:
	return icon_rect if icon_rect else get_node_or_null("IconRect") as TextureRect


func _selection() -> TextureRect:
	return select_icon if select_icon else get_node_or_null("SelectIcon") as TextureRect


func _update_visuals() -> void:
	var icon_path: String = item_data.get("icon", "")
	var icon: TextureRect = _icon()
	if not icon_path.is_empty() and icon:
		var texture: Texture2D = load(icon_path) as Texture2D
		if texture:
			icon.texture = texture
			icon.show()


func set_selected(active: bool) -> void:
	_is_selected = active
	var selection: TextureRect = _selection()
	if selection:
		selection.visible = active


func set_clickable(active: bool) -> void:
	var button: Button = click_button if click_button else get_node_or_null("ClickButton") as Button
	if button:
		button.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


func _on_click_button_pressed() -> void:
	pressed.emit()


func set_drag_active(active: bool) -> void:
	scale = Vector2(0.9, 0.9) if active else Vector2.ONE


func set_visual_position(pos: Vector2) -> void:
	position = pos


func play_merge_animation() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15)
	tween.tween_callback(queue_free)


func play_spawn_animation() -> void:
	scale = Vector2.ZERO
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25)
