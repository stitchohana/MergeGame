class_name GridItem extends ColorRect

# GridItem: A single item on the game board.
# Shows colored background, item name, level, and optional icon.

var item_data: Dictionary = {}
var grid_position: Vector2i
var is_launcher: bool = false

var _orig_modulate: Color
var _orig_scale: Vector2

@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var icon_rect: TextureRect = $IconRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orig_modulate = modulate
	_orig_scale = scale

func setup(data: Dictionary, pos: Vector2i, cell_size: int) -> void:
	item_data = data
	grid_position = pos
	is_launcher = data.get("type", "") == "launcher"

	custom_minimum_size = Vector2(cell_size, cell_size)
	size = Vector2(cell_size, cell_size)
	position = Vector2(pos.x * cell_size, pos.y * cell_size)

	_update_visuals()

func _update_visuals() -> void:
	# Background color by type and group
	var group_id: int = item_data.get("group_id", 0)
	if is_launcher:
		match group_id:
			1:
				color = Color(0.6, 0.3, 0.8, 1)  # purple for stone set
			2:
				color = Color(1.0, 0.6, 0.2, 1)  # orange for plant set
			_:
				color = Color(0.5, 0.5, 0.5, 1)
	else:
		var level = item_data.get("level", 0)
		var hue := 0.0
		match group_id:
			1:
				# Stone set: rainbow range (hue 0.0-0.875)
				hue = float(level - 1) / 8.0
			2:
				# Plant set: green range (hue 0.25-0.4)
				hue = 0.25 + float(level - 1) / 6.0 * 0.15
			_:
				hue = float(level - 1) / 8.0
		color = Color.from_hsv(hue, 0.6, 0.7)

	# Optional icon overlay
	var icon_path: String = item_data.get("icon", "")
	if icon_path and icon_rect:
		var tex := load(icon_path) as Texture2D
		if tex:
			icon_rect.texture = tex
			icon_rect.show()

	# Item name
	var item_name: String = item_data.get("name", "")
	if name_label:
		name_label.text = item_name
		name_label.visible = true

	# Level label
	var level = item_data.get("level", 0)
	if level_label:
		level_label.text = str(level)
		level_label.visible = true

# Called by GridView during drag
func set_drag_active(active: bool) -> void:
	if active:
		modulate = Color(1, 1, 1, 0.4)
		scale = Vector2(0.9, 0.9)
	else:
		modulate = Color.WHITE
		scale = Vector2(1, 1)

func set_visual_position(pos: Vector2) -> void:
	position = pos

func play_merge_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)

func play_spawn_animation() -> void:
	scale = Vector2(0, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.25)
