class_name GridItem extends Control

# GridItem: A single item on the game board.
# Shows item icon, name, level, and optional status overlays.

var item_data: Dictionary = {}
var grid_position: Vector2i
var is_launcher: bool = false

var _orig_modulate: Color
var _orig_scale: Vector2

@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var icon_rect: TextureRect = $IconRect
@onready var charge_label: Label = $ChargeLabel
@onready var immovable_icon: TextureRect = $ImmovableIcon
@onready var select_icon: TextureRect = $SelectIcon
@onready var require_icon: TextureRect = $RequireIcon

var _is_selected: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orig_modulate = modulate
	_orig_scale = scale

	select_icon.visible = false

func set_selected(active: bool) -> void:
	_is_selected = active
	if select_icon:
		select_icon.visible = active

func setup(data: Dictionary, pos: Vector2i, cell_step: int) -> void:
	item_data = data
	grid_position = pos
	is_launcher = data.get("type", 0) == Constants.ItemType.LAUNCHER

	custom_minimum_size = Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)
	size = Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)
	position = Vector2(pos.x * cell_step, pos.y * cell_step)

	_update_visuals()

func _update_visuals() -> void:
	# Apply crafting state visual if present (restored from server).
	if not is_launcher:
		var cs: int = item_data.get("_craft_state", -1)
		if cs >= 0 and cs <= 3:
			set_crafting_state(cs)

	# Optional icon overlay
	var icon_path: String = item_data.get("icon", "")
	if icon_path and icon_rect:
		var tex := load(icon_path) as Texture2D
		if tex:
			icon_rect.texture = tex
			icon_rect.show()

	# The board shows item art only; text details live in the item detail panel.
	if name_label:
		name_label.hide()
	if level_label:
		level_label.hide()
	if charge_label:
		charge_label.hide()

	if immovable_icon:
		immovable_icon.visible = item_data.get("immovable") == true

# Called by GridView during drag
func set_drag_active(active: bool) -> void:
	if active:
		modulate = Color(1, 1, 1, 0.4)
		scale = Vector2(0.9, 0.9)
	else:
		modulate = Color.WHITE
		scale = Vector2(1, 1)

func set_crafting_state(state: int) -> void:
	# state: 0=IDLE, 1=HAS_ITEMS, 2=CRAFTING, 3=READY
	match state:
		1:  # HAS_ITEMS — slight glow
			modulate = Color(1.0, 1.0, 0.8, 1)
		2:  # CRAFTING — dim with progress pulse
			modulate = Color(0.6, 0.6, 0.7, 1)
		3:  # READY — bright glow
			modulate = Color(1.0, 1.0, 0.6, 1)
		_:  # IDLE or unknown — reset
			modulate = Color.WHITE

func set_visual_position(pos: Vector2) -> void:
	position = pos

func set_required(required: bool) -> void:
	if require_icon:
		require_icon.visible = required

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
