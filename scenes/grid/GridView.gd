class_name GridView extends Control

# GridView: Visual 7x9 grid. Handles all input, item visuals, and drag-and-drop.

const CELL_SIZE := Constants.CELL_SIZE
const GRID_COLS := Constants.GRID_COLS
const GRID_ROWS := Constants.GRID_ROWS
const DRAG_THRESHOLD := 10.0  # pixels before drag starts

@export var grid_cell_scene: PackedScene
@export var grid_item_scene: PackedScene

signal item_clicked(item_data: Dictionary, grid_pos: Vector2i)
signal pill_dropped_outside(item_data: Dictionary)

var _item_nodes: Dictionary = {}  # "col,row" -> GridItem
var _cell_nodes: Dictionary = {}  # "col,row" -> GridCell

var _is_dragging: bool = false
var _drag_source_pos: Vector2i = Vector2i(-1, -1)
var _drag_item_data: Dictionary = {}

var _press_start_pos: Vector2i = Vector2i(-1, -1)
var _press_screen_pos: Vector2 = Vector2.ZERO
var _pressed_item: Dictionary = {}
var _pressed_has_moved: bool = false

var _drag_ghost: ColorRect = null

# Crafting
var _craft_button: CraftButton = null
var _craft_table_pos: Vector2i = Vector2i(-1, -1)
var _craft_table_item: Dictionary = {}
var _is_launcher_spawning: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_create_grid()
	_create_ghost()
	_connect_signals()
	_sync_all_items()
	_setup_crafting()
	_sync_crafting_states()

func _create_grid() -> void:
	var bg := ColorRect.new()
	bg.name = "GridBackground"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.custom_minimum_size = Vector2(GRID_COLS * CELL_SIZE, GRID_ROWS * CELL_SIZE)
	bg.size = Vector2(GRID_COLS * CELL_SIZE, GRID_ROWS * CELL_SIZE)
	bg.position = Vector2.ZERO
	add_child(bg)

	var cells_layer := Control.new()
	cells_layer.name = "GridCells"
	cells_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cells_layer)

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cell := grid_cell_scene.instantiate()
			cells_layer.add_child(cell)
			cell.setup(Vector2i(col, row), CELL_SIZE)
			_cell_nodes["%d,%d" % [col, row]] = cell

	var items_layer := Control.new()
	items_layer.name = "ItemsLayer"
	items_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(items_layer)

func _create_ghost() -> void:
	_drag_ghost = ColorRect.new()
	_drag_ghost.name = "DragGhost"
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.visible = false
	_drag_ghost.modulate = Color(1, 1, 1, 0.7)
	_drag_ghost.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	_drag_ghost.size = Vector2(CELL_SIZE, CELL_SIZE)

	# Ghost label (item name)
	var gl := Label.new()
	gl.name = "GhostLabel"
	gl.anchor_left = 0.0
	gl.anchor_top = 0.5
	gl.anchor_right = 1.0
	gl.anchor_bottom = 1.0
	gl.offset_left = 2
	gl.offset_top = 2
	gl.offset_right = -2
	gl.offset_bottom = -2
	gl.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	gl.add_theme_font_size_override("font_size", 10)
	gl.horizontal_alignment = 1
	gl.vertical_alignment = 1
	_drag_ghost.add_child(gl)

	add_child(_drag_ghost)

func _connect_signals() -> void:
	GridManager.item_added.connect(_on_item_added)
	GridManager.item_removed.connect(_on_item_removed)
	GridManager.item_moved.connect(_on_item_moved)
	GridManager.grid_updated.connect(_on_grid_updated)
	CloudService.move_confirmed.connect(_on_move_confirmed)
	CloudService.move_rejected.connect(_on_move_rejected)
	CloudService.spawn_confirmed.connect(_on_spawn_confirmed)
	CloudService.spawn_rejected.connect(_on_spawn_rejected)
	CloudService.craft_add_confirmed.connect(_on_craft_add_confirmed)
	CloudService.craft_add_rejected.connect(_on_craft_add_rejected)
	CloudService.craft_start_confirmed.connect(_on_craft_start_confirmed)
	CloudService.craft_start_rejected.connect(_on_craft_start_rejected)
	CloudService.craft_retrieve_confirmed.connect(_on_craft_retrieve_confirmed)
	CloudService.craft_retrieve_rejected.connect(_on_craft_retrieve_rejected)

# --- Input: press on any item, then drag or click dispatch ---

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local_pos := _to_local(mb.position)
		var cell_pos := _local_to_grid(local_pos)

		if mb.pressed:
			if _is_dragging or not GridManager.is_valid_pos(cell_pos):
				return
			var item = GridManager.get_item(cell_pos)
			if item == null:
				return
			# Record press on any item
			_press_start_pos = cell_pos
			_press_screen_pos = local_pos
			_pressed_item = item
			_pressed_has_moved = false
		elif _is_dragging:
			_finish_drag(cell_pos)
		elif _pressed_has_moved == false and not _pressed_item.is_empty():
			# Click without drag
			item_clicked.emit(_pressed_item, _press_start_pos)

			# Check crafting table or storage click
			if _pressed_item.get("id") == 603:
				item_clicked.emit(_pressed_item, _press_start_pos)
				_handle_storage_click(_press_start_pos)
				_pressed_item = {}
				return
			if _pressed_item.get("type") == "crafting":
				var cstate: int = _pressed_item.get("_craft_state", CraftingService.TableState.IDLE)
				if cstate == CraftingService.TableState.READY:
					_craft_table_item = _pressed_item
					_craft_table_pos = _press_start_pos
					_handle_crafting_retrieve(_pressed_item, _press_start_pos)
					_pressed_item = {}
					return
				# CRAFTING or HAS_ITEMS: show detail panel
				item_clicked.emit(_pressed_item, _press_start_pos)
				if cstate == CraftingService.TableState.HAS_ITEMS:
					var recipe: Dictionary = _pressed_item.get("_craft_recipe", {})
					if not recipe.is_empty():
						_craft_table_pos = _press_start_pos
						_craft_table_item = _pressed_item
						_craft_button.show_for_recipe(recipe)
						_craft_button.set_table_pos(position, _press_start_pos, CELL_SIZE)
				_pressed_item = {}
				return

			_hide_craft_button()
			if _pressed_item.get("type") == "launcher":
				_handle_launcher_click(_press_start_pos)
			_pressed_item = {}

	elif event is InputEventMouseMotion:
		if _is_dragging:
			var local_pos := _to_local(event.position)
			_drag_ghost.position = local_pos - Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
			_update_highlights(local_pos)
		elif not _pressed_item.is_empty() and not _pressed_has_moved:
			var local_pos := _to_local(event.position)
			if local_pos.distance_to(_press_screen_pos) > DRAG_THRESHOLD:
				_pressed_has_moved = true
				_start_drag(_press_start_pos)

func _to_local(global_pos: Vector2) -> Vector2:
	return global_pos - global_position

func _local_to_grid(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(local_pos.x / CELL_SIZE), int(local_pos.y / CELL_SIZE))

var _pending_spawn_pos: Vector2i = Vector2i(-1, -1)
var _pending_spawn_id: int = -1
var _pending_spawn_target: Vector2i = Vector2i(-1, -1)

func _handle_launcher_click(pos: Vector2i) -> void:
	if GameState.phase != GameState.GamePhase.IDLE:
		return
	if _pending_spawn_id != -1:
		return  # Previous spawn still pending
	_pressed_item = {}

	GameState.set_phase(GameState.GamePhase.SPAWNING)
	var item = GridManager.get_item(pos)
	if item == null:
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	# Check stamina locally before optimistic spawn
	if GameState.stamina < 1:
		EventBus.show_toast.emit("体力不足")
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	# Roll locally for optimistic UI
	var spawn_data: Dictionary = ConfigDatabase.roll_spawn(item.get("id", 0))
	if spawn_data.is_empty():
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	var spawn_pos := GridManager.find_nearest_empty(pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满")
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	# Optimistic: add item + play animation immediately
	var new_item: Dictionary = spawn_data.duplicate(true)
	# Init charges for spawned launchers
	if new_item.get("type", "") == "launcher":
		new_item["charges"] = new_item.get("max_charges", 3)
	_is_launcher_spawning = true
	GridManager.add_item(new_item, spawn_pos)
	_is_launcher_spawning = false

	var fly_key := "%d,%d" % [spawn_pos.x, spawn_pos.y]
	var fly_node: GridItem = _item_nodes.get(fly_key)
	if fly_node and is_instance_valid(fly_node):
		fly_node.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		fly_node.scale = Vector2(0.7, 0.7)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(fly_node, "position", Vector2(spawn_pos.x * CELL_SIZE, spawn_pos.y * CELL_SIZE), 0.35).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(fly_node, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_BOUNCE)

	# Submit to server for validation
	_pending_spawn_pos = pos
	_pending_spawn_id = spawn_data.get("id", 0)
	_pending_spawn_target = spawn_pos

	if CloudService.online:
		CloudService.submit_spawn(pos.x, pos.y, _pending_spawn_id, GameState.version)
	else:
		# Offline: keep local spawn, don't validate
		_pending_spawn_pos = Vector2i(-1, -1)
		_pending_spawn_id = -1
		_pending_spawn_target = Vector2i(-1, -1)
		GameState.set_phase(GameState.GamePhase.IDLE)

func _on_spawn_confirmed(result: Dictionary) -> void:
	# Use server position to locate the item (request queue may cause _pending values to be stale)
	var target_pos: Vector2i = Vector2i(result.get("target_col", -1), result.get("target_row", -1))
	var launcher_pos: Vector2i = _pending_spawn_pos
	_pending_spawn_pos = Vector2i(-1, -1)
	_pending_spawn_id = -1
	_pending_spawn_target = Vector2i(-1, -1)

	GameState.version = result.get("new_version", GameState.version)
	# Update stamina from server (if present)
	var stamina: Variant = result.get("stamina", null)
	if stamina != null:
		GameState.stamina = stamina
		GameState.max_stamina = result.get("max_stamina", GameState.max_stamina)
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	# Update charges display from spawn response
	var charges_val: Variant = result.get("charges", null)
	if charges_val != null:
		# Update launcher item in GridManager
		if launcher_pos.x >= 0 and launcher_pos.y >= 0:
			var launcher_item = GridManager.get_item(launcher_pos)
			if launcher_item != null:
				launcher_item["charges"] = charges_val
				# Update GridItem visual
				var launcher_key := "%d,%d" % [launcher_pos.x, launcher_pos.y]
				var launcher_node = _item_nodes.get(launcher_key)
				if launcher_node and is_instance_valid(launcher_node):
					if charges_val <= 0:
						launcher_node.charge_label.text = "空"
						launcher_node.charge_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
					else:
						var max_c: int = result.get("max_charges", 3)
						launcher_node.charge_label.text = "%d/%d" % [charges_val, max_c]
						launcher_node.charge_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		if charges_val <= 0:
			EventBus.show_toast.emit("发射器次数用尽，等待冷却")

	if GameState.phase == GameState.GamePhase.SPAWNING:
		GameState.set_phase(GameState.GamePhase.IDLE)

func _on_spawn_rejected(reason: String) -> void:
	var target_pos := _pending_spawn_target
	_pending_spawn_pos = Vector2i(-1, -1)
	_pending_spawn_id = -1
	_pending_spawn_target = Vector2i(-1, -1)

	print("[GridView] Spawn rejected: ", reason)
	# Remove the optimistically spawned item
	GridManager.remove_item(target_pos)
	EventBus.show_toast.emit(_spawn_error_text(reason))

	if GameState.phase == GameState.GamePhase.SPAWNING:
		GameState.set_phase(GameState.GamePhase.IDLE)

func _spawn_error_text(reason: String) -> String:
	match reason:
		"invalid_spawn_id": return "生成失败：物品不合法"
		"launcher_not_found": return "生成失败：发射器不存在"
		"not_a_launcher": return "生成失败：不是发射器"
		"no_empty_cell": return "生成失败：棋盘已满"
		"insufficient_stamina": return "体力不足"
		"no_charges": return "发射器次数用尽"
		"network_error": return "生成失败：网络错误"
		"version_mismatch": return "生成失败：数据过期，请重试"
		_: return "生成失败：" + reason

func _start_drag(pos: Vector2i) -> void:
	if GameState.phase != GameState.GamePhase.IDLE:
		return
	var item = GridManager.get_item(pos)
	if item == null:
		return

	_drag_source_pos = pos
	_drag_item_data = item
	_is_dragging = true
	GameState.set_phase(GameState.GamePhase.DRAGGING)

	# Dim the source item
	var src_node = _item_nodes.get("%d,%d" % [pos.x, pos.y])
	if src_node and is_instance_valid(src_node):
		src_node.set_drag_active(true)

	# Setup ghost visual (match GridItem colors by group_id)
	var group_id: int = item.get("group_id", 0)
	var item_type: String = item.get("type", "")
	if item_type == "launcher":
		match group_id:
			1: _drag_ghost.color = Color(0.6, 0.3, 0.8, 1)
			2: _drag_ghost.color = Color(1.0, 0.6, 0.2, 1)
			_: _drag_ghost.color = Color(0.5, 0.5, 0.5, 1)
	else:
		var level: int = item.get("level", 0)
		var hue := 0.0
		match group_id:
			1: hue = float(level - 1) / 8.0
			2: hue = 0.25 + float(level - 1) / 6.0 * 0.15
			_: hue = float(level - 1) / 8.0
		_drag_ghost.color = Color.from_hsv(hue, 0.6, 0.7)

	# Ghost label text (item name)
	var gl: Label = _drag_ghost.get_node_or_null("GhostLabel") as Label
	if gl:
		gl.text = item.get("name", "")

	_drag_ghost.modulate = Color(1, 1, 1, 0.7)
	_drag_ghost.visible = true
	_hide_craft_button()

func _finish_drag(target_pos: Vector2i) -> void:
	_is_dragging = false
	_pressed_item = {}
	_drag_ghost.visible = false

	# Restore source item visual
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	if _item_nodes.has(src_key):
		var src_node = _item_nodes[src_key]
		if is_instance_valid(src_node):
			src_node.set_drag_active(false)
	_clear_highlights()

	if not GridManager.is_valid_pos(target_pos):
		# Pill dropped outside grid -> consume buff or breakthrough
		var ptype: String = _drag_item_data.get("pill_type", "")
		if ptype == "cultivation" or ptype == "breakthrough":
			GridManager.remove_item(_drag_source_pos)
			pill_dropped_outside.emit(_drag_item_data)
			GameState.set_phase(GameState.GamePhase.IDLE)
			return
		_snap_back()
		GameState.set_phase(GameState.GamePhase.IDLE)
		return
	if target_pos == _drag_source_pos:
		GameState.set_phase(GameState.GamePhase.IDLE)
		return
	# No distance limit -- any valid cell is a valid drop target
	var target = GridManager.get_item(target_pos)

	# Check storage drop
	if target != null and target.get("id") == 603:
		_handle_storage_drop(target_pos, target)
		if GameState.phase in [GameState.GamePhase.DRAGGING, GameState.GamePhase.MERGING]:
			GameState.set_phase(GameState.GamePhase.IDLE)
		return
	# Check for crafting table drop
	if target != null and target.get("type") == "crafting":
		_handle_crafting_drop(target_pos, target)
		if GameState.phase in [GameState.GamePhase.DRAGGING, GameState.GamePhase.MERGING]:
			GameState.set_phase(GameState.GamePhase.IDLE)
		return
	if target == null:
		_place_dragged_item(target_pos)
		if _drag_item_data.get("type") == "crafting":
			item_clicked.emit(_drag_item_data, target_pos)
	elif not MergeService.try_merge(_drag_source_pos, target_pos):
		var push_pos = GridManager.find_nearest_empty(target_pos)
		if push_pos != Vector2i(-1, -1):
			GridManager.move_item(target_pos, push_pos)
			_place_dragged_item(target_pos)
		else:
			_snap_back()
	if GameState.phase in [GameState.GamePhase.DRAGGING, GameState.GamePhase.MERGING]:
		GameState.set_phase(GameState.GamePhase.IDLE)
func _place_dragged_item(target_pos: Vector2i) -> void:
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var node = _item_nodes.get(src_key)
	if node and is_instance_valid(node):
		node.position = Vector2(target_pos.x * CELL_SIZE, target_pos.y * CELL_SIZE)
	GridManager.move_item(_drag_source_pos, target_pos)
	# Sync move to server
	if CloudService.online:
		CloudService.submit_move(_drag_source_pos.x, _drag_source_pos.y, target_pos.x, target_pos.y, GameState.version)

func _on_move_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	print("[GridView] Move confirmed: v", GameState.version)

func _on_move_rejected(reason: String) -> void:
	print("[GridView] Move rejected: ", reason)
func _snap_back() -> void:

	var key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var item_node = _item_nodes.get(key)
	if item_node and is_instance_valid(item_node):
		var target := Vector2(_drag_source_pos.x * CELL_SIZE, _drag_source_pos.y * CELL_SIZE)
		var tween := create_tween()
		tween.tween_property(item_node, "position", target, 0.2)

func _update_highlights(local_pos: Vector2) -> void:
	_clear_highlights()
	var hover := _local_to_grid(local_pos)
	if not GridManager.is_valid_pos(hover):
		return
	if hover == _drag_source_pos:
		return

	# Highlight any valid drop target (no distance limit)
	var target = GridManager.get_item(hover)
	if target != null and target.get("id") == _drag_item_data.get("id"):
		_set_cell_highlight(hover, GridCell.HighlightType.MERGE_TARGET)
	elif target == null:
		_set_cell_highlight(hover, GridCell.HighlightType.VALID_DROP)
	else:
		_set_cell_highlight(hover, GridCell.HighlightType.INVALID)

# --- Item Visual Management ---

func _on_item_added(item_data: Dictionary, pos: Vector2i) -> void:
	_remove_item_node(pos)
	var item := grid_item_scene.instantiate()
	var layer := _get_items_layer()
	if layer:
		layer.add_child(item)
	item.setup(item_data, pos, CELL_SIZE)
	if not _is_launcher_spawning:
		item.play_spawn_animation()
	_item_nodes["%d,%d" % [pos.x, pos.y]] = item

func _on_item_removed(item_data: Dictionary, pos: Vector2i) -> void:
	var key := "%d,%d" % [pos.x, pos.y]
	var node = _item_nodes.get(key)
	if node and is_instance_valid(node):
		node.play_merge_animation()
	_item_nodes.erase(key)

func _on_item_moved(item_data: Dictionary, from_pos: Vector2i, to_pos: Vector2i) -> void:
	var key := "%d,%d" % [from_pos.x, from_pos.y]
	var node = _item_nodes.get(key)
	if node and is_instance_valid(node):
		node.grid_position = to_pos
		_item_nodes.erase(key)
		_item_nodes["%d,%d" % [to_pos.x, to_pos.y]] = node
		var target := Vector2(to_pos.x * CELL_SIZE, to_pos.y * CELL_SIZE)
		var tween := create_tween()
		tween.tween_property(node, "position", target, 0.15)
	else:
		_sync_all_items()

func _on_grid_updated() -> void:
	pass

func _sync_all_items() -> void:
	_clear_all_item_nodes()
	var layer := _get_items_layer()
	if not layer:
		return
	for entry in GridManager.get_all_items():
		var item := grid_item_scene.instantiate()
		layer.add_child(item)
		item.setup(entry.data, entry.pos, CELL_SIZE)
		_item_nodes["%d,%d" % [entry.pos.x, entry.pos.y]] = item

func _remove_item_node(pos: Vector2i) -> void:
	var key := "%d,%d" % [pos.x, pos.y]
	var node = _item_nodes.get(key)
	if node and is_instance_valid(node):
		node.queue_free()
	_item_nodes.erase(key)

func _clear_all_item_nodes() -> void:
	for key in _item_nodes:
		var node = _item_nodes[key]
		if is_instance_valid(node):
			node.queue_free()
	_item_nodes.clear()

func _clear_highlights() -> void:
	for key in _cell_nodes:
		_cell_nodes[key].set_highlight(GridCell.HighlightType.NONE)

func _set_cell_highlight(pos: Vector2i, type: GridCell.HighlightType) -> void:
	var cell = _cell_nodes.get("%d,%d" % [pos.x, pos.y])
	if cell:
		cell.set_highlight(type)

func _get_items_layer() -> Control:
	for child in get_children():
		if child.name == "ItemsLayer":
			return child as Control
	return null

# --- Crafting ---

func _setup_crafting() -> void:
	CraftingService.table_state_changed.connect(_on_table_state_changed)
	_craft_button = preload("res://scenes/ui/CraftButton.tscn").instantiate() as CraftButton
	add_child(_craft_button)
	_craft_button.hide()
	_craft_button.craft_pressed.connect(_on_craft_button_pressed)

func _handle_crafting_drop(table_pos: Vector2i, table_item: Dictionary) -> void:
	# Block drop if table is crafting or ready
	var craft_state: int = table_item.get("_craft_state", CraftingService.TableState.IDLE)
	if craft_state == CraftingService.TableState.CRAFTING or craft_state == CraftingService.TableState.READY:
		_snap_back()
		return
	var dragged_item = GridManager.get_item(_drag_source_pos)

	if dragged_item == null:
		_snap_back()
		return

	var ingredient_id: int = dragged_item.get("id", 0)

	# Remove dragged item from grid (consumed as ingredient)
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var src_node = _item_nodes.get(src_key)
	if src_node and is_instance_valid(src_node):
		src_node.queue_free()
	_item_nodes.erase(src_key)
	GridManager.remove_item(_drag_source_pos)

	# Add to crafting service -- data stored directly in table_item on the grid
	var matched := CraftingService.add_ingredient(table_item, dragged_item)
	if matched:
		_craft_table_pos = table_pos
		_craft_table_item = table_item
		var recipe := CraftingService.get_current_recipe(table_item)
		if not recipe.is_empty():
			_craft_button.show_for_recipe(recipe)
			_craft_button.set_table_pos(position, table_pos, CELL_SIZE)
	else:
		_hide_craft_button()

	# Sync to server
	if CloudService.online:
		CloudService.submit_craft_add(_drag_source_pos.x, _drag_source_pos.y, table_pos.x, table_pos.y, ingredient_id, GameState.version)

	# Update table visual
	var table_key := "%d,%d" % [table_pos.x, table_pos.y]
	var table_node = _item_nodes.get(table_key)
	if table_node and is_instance_valid(table_node):
		table_node.set_crafting_state(CraftingService.TableState.HAS_ITEMS)

var _last_craft_ingredient_id: int = -1
var _last_craft_ingredient_pos: Vector2i = Vector2i(-1, -1)

func _handle_storage_click(storage_pos: Vector2i) -> void:
	CloudService.fetch_state()
	CloudService.state_loaded.connect(func(data):
		var items: Array = []
		for entry in data.grid:
			if entry.col == storage_pos.x and entry.row == storage_pos.y and entry.has("storage"):
				items = entry.storage.items
				break
		var popup := preload("res://scenes/ui/StoragePopup.tscn").instantiate() as StoragePopup
		popup.setup(storage_pos, items)
		UIManager.show_popup(popup)
	, CONNECT_ONE_SHOT)

func _handle_storage_drop(storage_pos: Vector2i, storage_item: Dictionary) -> void:
	var dragged_item = GridManager.get_item(_drag_source_pos)
	if dragged_item == null:
		_snap_back()
		return

	var item_id: int = dragged_item.get("id", 0)
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var src_node = _item_nodes.get(src_key)
	if src_node and is_instance_valid(src_node):
		src_node.queue_free()
	_item_nodes.erase(src_key)
	GridManager.remove_item(_drag_source_pos)

	if CloudService.online:
		CloudService.submit_storage_deposit(storage_pos.x, storage_pos.y, item_id, _drag_source_pos.x, _drag_source_pos.y)

func _handle_crafting_retrieve(table_item: Dictionary, table_pos: Vector2i) -> void:
	if table_item.is_empty():
		return
	if CloudService.online:
		CloudService.submit_craft_retrieve(table_pos.x, table_pos.y, GameState.version)
	else:
		_do_local_retrieve(table_item, table_pos)

func _do_local_retrieve(table_item: Dictionary, table_pos: Vector2i) -> void:
	var result_id := CraftingService.retrieve(table_item)
	if result_id <= 0:
		return
	var result_data := ConfigDatabase.get_item_data(result_id)
	if result_data.is_empty():
		return
	var spawn_pos := GridManager.find_nearest_empty(table_pos)
	if spawn_pos == Vector2i(-1, -1):
		return
	var new_item: Dictionary = result_data.duplicate(true)
	_is_launcher_spawning = true
	GridManager.add_item(new_item, spawn_pos)
	_is_launcher_spawning = false
	var table_key := "%d,%d" % [table_pos.x, table_pos.y]
	var table_node = _item_nodes.get(table_key)
	if table_node and is_instance_valid(table_node):
		table_node.set_crafting_state(CraftingService.TableState.IDLE)
	_hide_craft_button()

func _on_craft_button_pressed() -> void:
	if _craft_table_item.is_empty():
		return
	CraftingService.start_craft(_craft_table_item)
	var table_pos: Vector2i = _get_table_grid_pos(_craft_table_item)
	if CloudService.online:
		CloudService.submit_craft_start(table_pos.x, table_pos.y, GameState.version)

func _on_craft_add_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	print("[GridView] Craft add confirmed v", GameState.version)

func _on_craft_add_rejected(reason: String) -> void:
	print("[GridView] Craft add rejected: ", reason)
	EventBus.show_toast.emit("放入材料失败：" + reason)

func _on_craft_start_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	print("[GridView] Craft start confirmed v", GameState.version)

func _on_craft_start_rejected(reason: String) -> void:
	print("[GridView] Craft start rejected: ", reason)
	EventBus.show_toast.emit("开始制作失败：" + reason)

func _on_craft_retrieve_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	var result_id: int = result.get("result_id", 0)
	if result_id <= 0: return
	var result_data := ConfigDatabase.get_item_data(result_id)
	if result_data.is_empty():
		EventBus.show_toast.emit("制作完成，但找不到物品配置 #%d" % result_id)
		return
	if not _craft_table_item.is_empty():
		CraftingService.retrieve(_craft_table_item)
		_craft_table_item = {}
	var spawn_pos := GridManager.find_nearest_empty(_craft_table_pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满，无法取出制作结果")
		return
	var new_item: Dictionary = result_data.duplicate(true)
	_is_launcher_spawning = true
	GridManager.add_item(new_item, spawn_pos)
	_is_launcher_spawning = false
	item_clicked.emit({}, Vector2i(-1, -1))
	EventBus.show_toast.emit("制作完成：%s" % result_data.get("name", "未知"))
	print("[GridView] Craft retrieve OK: v", GameState.version, " result=#", result_id)

func _on_craft_retrieve_rejected(reason: String) -> void:
	print("[GridView] Craft retrieve rejected: ", reason)
	EventBus.show_toast.emit("取件失败：" + reason)

func _get_table_grid_pos(table_item: Dictionary) -> Vector2i:
	for entry in GridManager.get_all_items():
		if entry.data == table_item:
			return entry.pos
	return Vector2i(-1, -1)

func _on_table_state_changed(table_item: Dictionary, state: int) -> void:
	# Update visual for the affected grid item
	for key in _item_nodes:
		var node = _item_nodes[key]
		if node and is_instance_valid(node) and node.item_data == table_item:
			node.set_crafting_state(state)
			break

	if state == CraftingService.TableState.CRAFTING:
		_hide_craft_button()

func _show_craft_button(table_pos: Vector2i) -> void:
	_craft_table_pos = table_pos
	var recipe := CraftingService.get_current_recipe(_craft_table_item)
	if not recipe.is_empty():
		_craft_button.show_for_recipe(recipe)
		_craft_button.set_table_pos(position, table_pos, CELL_SIZE)

func _sync_crafting_states() -> void:
	for entry in GridManager.get_all_items():
		var item: Dictionary = entry.data
		var cs: int = item.get("_craft_state", CraftingService.TableState.IDLE)
		if cs != CraftingService.TableState.IDLE:
			var key := "%d,%d" % [entry.pos.x, entry.pos.y]
			var node = _item_nodes.get(key)
			if node and is_instance_valid(node):
				node.set_crafting_state(cs)

func _hide_craft_button() -> void:
	_craft_button.hide()
	_craft_table_pos = Vector2i(-1, -1)
	_craft_table_item = {}
