extends Control

signal dropped(uid: int, col: int, row: int, from_stash: bool)

const ITEM_SCENE := preload("res://scenes/items/GridItem.tscn")
const CELL_TEXTURE := preload("res://assets/ui/xianxia_v3_layers_v2/layers/board_square_cell.png")
const DragController := preload("res://scenes/grid/BoardDragController.gd")
var data: Dictionary = {}
var definition: Dictionary = {}
var can_interact: Callable
var next_lookup: Callable
var combat_gate: Callable
var from_stash: bool = false
var item_visual: GridItem
var _dragging: bool = false
var _return_tween: Tween
var monster_visual: TextureRect
var submitted_icons: Array[Control] = []
var _item_definitions: Dictionary = {}
var _submitted_layer: Control


func setup(cell: Dictionary, item_def: Dictionary, gate: Callable, stash: bool = false, lookup: Callable = Callable(), submit_gate: Callable = Callable(), item_definitions: Dictionary = {}) -> void:
	data = cell
	definition = item_def
	can_interact = gate
	next_lookup = lookup
	combat_gate = submit_gate
	from_stash = stash
	_item_definitions = item_definitions
	custom_minimum_size = Vector2.ONE * Constants.CELL_SIZE
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false


func _ready() -> void:
	var background := TextureRect.new()
	background.texture = CELL_TEXTURE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var fog: bool = bool(data.get("fog", false))
	var special_fog: bool = fog and bool(data.get("special_fog", false))
	var enemy: Dictionary = data.get("enemy", {})
	var item: Dictionary = data.get("item", {})
	if fog or not enemy.is_empty():
		var overlay := TextureRect.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.texture = load("res://assets/ui/secret_realm/%s.svg" % ("fog" if fog else "boss")) as Texture2D
		overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if fog:
			background.modulate = Color("655079") if special_fog else Color("536d65")
			if special_fog:
				overlay.modulate = Color("bd98e1")
		add_child(overlay)
		if special_fog:
			var seal := Label.new()
			seal.name = "SpecialFogSeal"
			seal.text = "封"
			seal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			seal.add_theme_font_size_override("font_size", 24)
			seal.add_theme_color_override("font_color", Color("f6dbab"))
			seal.add_theme_color_override("font_outline_color", Color("34203f"))
			seal.add_theme_constant_override("outline_size", 4)
			seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(seal)
		if not fog:
			monster_visual = overlay
			show_submissions(data.get("submitted", {}))
	elif not item.is_empty():
		item_visual = create_item_visual(item, definition)
	tooltip_text = "在相邻格合成可揭雾" if fog else str(enemy.get("name", "")) if not enemy.is_empty() else str(definition.get("name", "空位")) + ("（固定：作为合成目标解锁）" if item.get("immovable", false) else "")
	if special_fog:
		tooltip_text = "特殊迷雾：击败本关全部小怪后解锁"
	if from_stash:
		tooltip_text = str(definition.get("name", "物品")) + "（点击放入棋盘空位）"
	gui_input.connect(_on_input)


func show_submissions(submitted: Dictionary) -> void:
	if is_instance_valid(_submitted_layer):
		remove_child(_submitted_layer)
		_submitted_layer.queue_free()
	submitted_icons.clear()
	if data.get("fog", false) or data.get("enemy", {}).is_empty():
		return
	_submitted_layer = Control.new()
	_submitted_layer.name = "SubmittedItems"
	_submitted_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_submitted_layer.z_index = 5
	add_child(_submitted_layer)
	for cost: Dictionary in data.enemy.get("costs", []):
		var id: String = str(cost.get("id", ""))
		var count: int = mini(int(submitted.get(id, 0)), int(cost.get("count", 0)))
		var item_def: Dictionary = _item_definitions.get(id, {})
		for n: int in range(count):
			var badge := Panel.new()
			badge.size = Vector2(20, 22)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.tooltip_text = str(item_def.get("name", id)) + "（已提交）"
			badge.set_meta("item_id", id)
			var style := StyleBoxFlat.new()
			style.bg_color = Color("dcebdc")
			style.border_color = Color("8ab6a6")
			style.set_border_width_all(1)
			style.set_corner_radius_all(4)
			badge.add_theme_stylebox_override("panel", style)
			var icon := TextureRect.new()
			icon.texture = load("res://assets/ui/secret_realm/%s.svg" % item_def.get("chain", "sword")) as Texture2D
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.position = Vector2(1, 1)
			icon.size = Vector2(18, 19)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(icon)
			var level := Label.new()
			level.text = str(int(item_def.get("level", 1)))
			level.add_theme_font_size_override("font_size", 9)
			level.add_theme_color_override("font_color", Color.BLACK)
			level.position = Vector2(2, -2)
			level.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(level)
			_submitted_layer.add_child(badge)
			submitted_icons.append(badge)
	# Four per row keeps six swords plus one qi within a single cell's width.
	var rows: int = ceili(submitted_icons.size() / 4.0)
	var top: float = -float(rows * 23) + 9.0
	# Keep the highest world row's indicators inside the clipped board viewport.
	if int(data.get("row", -1)) == int(get_meta("viewport_top_row", -2)):
		top = 0.0
	for index: int in range(submitted_icons.size()):
		var row: int = index / 4
		var count_in_row: int = mini(4, submitted_icons.size() - row * 4)
		submitted_icons[index].position = Vector2((Constants.CELL_SIZE - count_in_row * 21) * 0.5 + (index % 4) * 21, top + row * 23)


func create_item_visual(item: Dictionary, item_def: Dictionary) -> GridItem:
	var visual := ITEM_SCENE.instantiate() as GridItem
	add_child(visual)
	configure_item_visual(visual, item, item_def)
	return visual


func configure_item_visual(visual: GridItem, item: Dictionary, item_def: Dictionary) -> void:
	visual.setup({"type": Constants.ItemType.REGULAR, "icon": "res://assets/ui/secret_realm/%s.svg" % item_def.get("chain", "sword"), "immovable": item.get("immovable", false)}, Vector2i.ZERO, Constants.CELL_STEP)
	# Realm chains share art across levels, so retain a small level badge.
	visual.level_label.text = str(int(item_def.get("level", 1)))
	visual.level_label.add_theme_color_override("font_color", Color.BLACK)
	visual.level_label.show()


func set_selected(active: bool) -> void:
	if is_instance_valid(item_visual):
		item_visual.set_selected(active)


func suppress_item() -> void:
	if is_instance_valid(item_visual):
		item_visual.hide()


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		accept_event()


func get_drag_payload() -> Dictionary:
	var item: Dictionary = data.get("item", {})
	if from_stash or not can_interact.call() or data.get("fog", false) or item.is_empty() or item.get("immovable", false):
		return {}
	return {"secret_realm": true, "uid": item.get("uid", 0), "id": item.get("id", ""), "stash": from_stash, "immovable": item.get("immovable", false)}


func begin_drag(layer: Control) -> void:
	_kill_return_tween()
	item_visual.set_selected(false)
	var transform: Transform2D = item_visual.get_global_transform_with_canvas()
	item_visual.reparent(layer)
	item_visual.position = layer.get_global_transform_with_canvas().affine_inverse() * transform.origin
	item_visual.scale = transform.get_scale() / layer.get_global_transform_with_canvas().get_scale()
	item_visual.z_index = 100
	_dragging = true


func end_drag(animate: bool = false) -> void:
	_dragging = false
	if not is_instance_valid(item_visual):
		return
	var origin: Vector2 = item_visual.get_global_transform_with_canvas().origin
	item_visual.reparent(self)
	item_visual.scale = Vector2.ONE
	item_visual.z_index = 0
	item_visual.position = get_global_transform_with_canvas().affine_inverse() * origin
	_return_tween = DragController.snap_back(item_visual, Vector2.ZERO, animate)


func can_accept(payload: Dictionary) -> bool:
	if from_stash or payload.get("stash", false) or payload.get("immovable", false) or not can_interact.call() or not payload.get("secret_realm", false) or data.get("fog", false):
		return false
	var enemy: Dictionary = data.get("enemy", {})
	if not enemy.is_empty():
		return combat_gate.is_valid() and combat_gate.call(data, payload)
	if not str(data.get("monster", "")).is_empty():
		return false
	var item: Dictionary = data.get("item", {})
	if item.is_empty():
		return true
	if payload.get("immovable", false) or item.get("uid", 0) == payload.get("uid", 0):
		return false
	var source: Dictionary = merge_data()
	source["id"] = payload.get("id", "")
	if MergeService.can_merge(source, merge_data(), next_lookup):
		return true
	return not item.get("immovable", false)


func accept_drop(payload: Dictionary) -> void:
	dropped.emit(int(payload.get("uid", 0)), int(data.get("col", 0)), int(data.get("row", 0)), bool(payload.get("stash", false)))


func merge_data() -> Dictionary:
	var item: Dictionary = data.get("item", {})
	if item.is_empty():
		return {}
	return {"id": item.get("id", ""), "group_id": definition.get("chain", ""), "type": Constants.ItemType.REGULAR, "level": int(definition.get("level", 0))}


func _kill_return_tween() -> void:
	if _return_tween != null and _return_tween.is_valid():
		_return_tween.kill()
	_return_tween = null


func _exit_tree() -> void:
	_kill_return_tween()
