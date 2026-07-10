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
	var temp := ColorRect.new()
	temp.name = "SelectColor"
	temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	temp.anchors_preset = Control.PRESET_FULL_RECT
	temp.anchor_right = 1.0
	temp.anchor_bottom = 1.0
	temp.color = Color(1, 0.85, 0.2, 0.7)
	select_icon.add_child(temp)

	var lock_bg := ColorRect.new()
	lock_bg.name = "LockBg"
	lock_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_bg.anchors_preset = Control.PRESET_FULL_RECT
	lock_bg.anchor_right = 1.0
	lock_bg.anchor_bottom = 1.0
	lock_bg.color = Color(1, 0.2, 0.2, 0.85)
	immovable_icon.add_child(lock_bg)

func set_selected(active: bool) -> void:
	_is_selected = active
	if select_icon:
		select_icon.visible = active

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
	var item_type: String = item_data.get("type", "")
	var group_id: int = item_data.get("group_id", 0)

	# Character rendering
	if item_type == "character":
		color = Color(0.15, 0.5, 0.75, 1)
		if name_label:
			name_label.text = item_data.get("name", "")
			name_label.visible = true
		var hp: int = item_data.get("hp", 0)
		var max_hp: int = item_data.get("max_hp", 0)
		if level_label:
			level_label.text = "HP %d/%d" % [hp, max_hp]
			level_label.visible = true
		return

	# Monster rendering
	if item_type == "monster":
		color = Color(0.8, 0.15, 0.15, 1)
		if name_label:
			name_label.text = item_data.get("name", "")
			name_label.visible = true
		var hp: int = item_data.get("hp", 0)
		var max_hp: int = item_data.get("max_hp", 0)
		if level_label:
			level_label.text = "HP %d/%d" % [hp, max_hp]
			level_label.visible = true
		return

	if is_launcher:
		color = GridUtils.launcher_color(group_id)
	else:
		var level: int = item_data.get("level", 0)
		color = GridUtils.item_color(group_id, level)
		# Apply crafting state visual if present (restored from server)
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

	# Item name
	var item_name: String = item_data.get("name", "")
	var item_id: int = item_data.get("id", 0)
	if name_label:
		name_label.text = item_name + (" [#%d]" % item_id if item_id > 0 else "")
		name_label.visible = true

	# Level label
	var level: int = item_data.get("level", 0)
	if level_label:
		level_label.text = str(level)
		level_label.visible = true

	# Charge indicator for launchers (uses node from scene)
	if charge_label:
		if is_launcher:
			var item_charges: int = item_data.get("charges", -1) as int
			var config := ConfigDatabase.get_item_data(item_data.get("id", 0))
			var max_c: int = config.get("max_charges", 0) if not config.is_empty() else 0
			if item_charges >= 0 and max_c > 0:
				charge_label.visible = true
				if item_charges <= 0:
					charge_label.text = "空"
					charge_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
				else:
					charge_label.text = "%d/%d" % [item_charges, max_c]
					charge_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
			else:
				charge_label.visible = false

		else:
			charge_label.visible = false

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
