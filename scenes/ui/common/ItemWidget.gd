class_name ItemWidget extends ColorRect

# ItemWidget: Reusable item display for grid and UI. Shows icon, name, level,
# selection indicator, charge status, and crafting state.

signal selected(item_data: Dictionary)

var item_data: Dictionary = {}
var grid_position: Vector2i
var is_launcher: bool = false

var _is_selected: bool = false
var _orig_modulate: Color
var _orig_scale: Vector2

@onready var icon_rect: TextureRect = $IconRect
@onready var name_label: Label = $NameLabel
@onready var charge_label: Label = $ChargeLabel
@onready var level_label: Label = $LevelLabel
@onready var select_icon: TextureRect = $SelectIcon

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orig_modulate = modulate
	_orig_scale = scale

func setup(data: Dictionary, pos: Vector2i = Vector2i(-1, -1), cell_size: int = 80) -> void:
	item_data = data
	is_launcher = data.get("type", 0) == Constants.ItemType.LAUNCHER

	if pos.x >= 0:
		grid_position = pos
		custom_minimum_size = Vector2(cell_size, cell_size)
		size = Vector2(cell_size, cell_size)
		position = Vector2(pos.x * cell_size, pos.y * cell_size)

	_update_visuals()

# Lazy accessors — fall back to get_node_or_null when @onready hasn't fired
func _ic() -> TextureRect:
	return icon_rect if icon_rect else get_node_or_null("IconRect") as TextureRect

func _nm() -> Label:
	return name_label if name_label else get_node_or_null("NameLabel") as Label

func _ch() -> Label:
	return charge_label if charge_label else get_node_or_null("ChargeLabel") as Label

func _lv() -> Label:
	return level_label if level_label else get_node_or_null("LevelLabel") as Label

func _si() -> TextureRect:
	return select_icon if select_icon else get_node_or_null("SelectIcon") as TextureRect

func _update_visuals() -> void:
	var item_type: int = item_data.get("type", 0)
	var group_id: int = item_data.get("group_id", 0)

	# Background color
	if is_launcher:
		match group_id:
			1: color = Color(0.6, 0.3, 0.8, 1)
			2: color = Color(1.0, 0.6, 0.2, 1)
			_: color = Color(0.5, 0.5, 0.5, 1)
	else:
		var level: int = item_data.get("level", 0)
		var hue := 0.0
		match group_id:
			1: hue = float(level - 1) / 8.0
			2: hue = 0.25 + float(level - 1) / 6.0 * 0.15
			_: hue = float(level - 1) / 8.0
		color = Color.from_hsv(hue, 0.6, 0.7)
		var cs: int = item_data.get("_craft_state", -1)
		if cs >= 0 and cs <= 3:
			set_crafting_state(cs)

	# Icon
	var icon_path: String = item_data.get("icon", "")
	var ic := _ic()
	if icon_path and ic:
		var tex := load(icon_path) as Texture2D
		if tex:
			ic.texture = tex
			ic.show()

	# Name
	var item_name: String = item_data.get("name", "")
	var item_id: int = item_data.get("id", 0)
	var nm := _nm()
	if nm:
		nm.text = item_name if item_id <= 0 else item_name
		nm.visible = true

	# Level
	var lv: int = item_data.get("level", 0)
	var ll := _lv()
	if ll:
		ll.text = str(lv)
		ll.visible = true

	# Charge
	var ch := _ch()
	if ch:
		if is_launcher:
			var item_charges: int = item_data.get("charges", -1)
			var config := ConfigDatabase.get_item_data(item_data.get("id", 0))
			var max_c: int = config.get("max_charges", 0) if not config.is_empty() else 0
			if item_charges >= 0 and max_c > 0:
				ch.visible = true
				if item_charges <= 0:
					ch.text = "空"
					ch.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
				else:
					ch.text = "%d/%d" % [item_charges, max_c]
					ch.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
			else:
				ch.visible = false
		else:
			ch.visible = false

func set_selected(active: bool) -> void:
	_is_selected = active
	var si := _si()
	if si:
		si.visible = active

func set_drag_active(active: bool) -> void:
	if active:
		modulate = Color(1, 1, 1, 0.4)
		scale = Vector2(0.9, 0.9)
	else:
		modulate = Color.WHITE
		scale = Vector2(1, 1)

func set_crafting_state(state: int) -> void:
	match state:
		1: modulate = Color(1.0, 1.0, 0.8, 1)
		2: modulate = Color(0.6, 0.6, 0.7, 1)
		3: modulate = Color(1.0, 1.0, 0.6, 1)
		_: modulate = Color.WHITE

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
