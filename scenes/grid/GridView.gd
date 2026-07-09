class_name GridView extends Control

# GridView: Visual 7x9 grid. Handles all input, item visuals, and drag-and-drop.

const LauncherControllerClass := preload("res://scenes/grid/LauncherController.gd")
const CraftingControllerClass := preload("res://scenes/grid/CraftingController.gd")
const CELL_SIZE := Constants.CELL_SIZE
const GRID_COLS := Constants.GRID_COLS
const GRID_ROWS := Constants.GRID_ROWS
const DRAG_THRESHOLD := 10.0  # pixels before drag starts

@export var grid_cell_scene: PackedScene

@export var grid_item_scene: PackedScene

signal item_clicked(item_data: Dictionary, grid_pos: Vector2i)
signal pill_dropped_outside(item_data: Dictionary, drop_position: Vector2)
signal item_use_requested(item_data: Dictionary, grid_pos: Vector2i)

var _item_nodes: Dictionary = {}  # "col,row" -> GridItem
var _cell_nodes: Dictionary = {}  # "col,row" -> GridCell

var _is_dragging: bool = false
var _drag_source_pos: Vector2i = Vector2i(-1, -1)
var _drag_item_data: Dictionary = {}

var _press_start_pos: Vector2i = Vector2i(-1, -1)
var _press_screen_pos: Vector2 = Vector2.ZERO
var _pressed_item: Dictionary = {}
var _pressed_has_moved: bool = false

# Crafting — delegated to CraftingController
var _craft_ctrl: Node = null
var _is_launcher_spawning: bool = false
var _selected_key: String = ""
var _skip_anims: bool = false
var _pouch_zone: Control = null
var _launcher_ctrl: Node = null

var _merge_in_flight: bool = false
var _cached_launcher_uid: int = -1
var _pending_push_src: Vector2i = Vector2i(-1, -1)
var _pending_push_target: Vector2i = Vector2i(-1, -1)

func set_pouch_zone(zone: Control) -> void:
	_pouch_zone = zone

func set_skip_animations(skip: bool) -> void:
	_skip_anims = skip

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_create_grid()
	_launcher_ctrl = LauncherControllerClass.new()
	add_child(_launcher_ctrl)
	_launcher_ctrl.spawn_finished.connect(_on_launcher_spawn_finished)
	_launcher_ctrl.spawn_failed.connect(_on_launcher_spawn_failed)
	_launcher_ctrl.charge_visual_update.connect(_on_launcher_charge_update)
	_launcher_ctrl.depleted_launcher_removed.connect(_on_launcher_depleted_removed)
	_connect_signals()
	_sync_all_items()
	_craft_ctrl = CraftingControllerClass.new()
	add_child(_craft_ctrl)
	_craft_ctrl.setup_signals()
	_craft_ctrl.setup_button(self)
	_craft_ctrl.item_accepted_for_craft.connect(_on_craft_item_accepted)
	_craft_ctrl.craft_rejected.connect(_on_craft_rejected)
	_craft_ctrl.craft_retrieve_ready.connect(_on_craft_retrieve_ready)
	_craft_ctrl.table_visual_update.connect(_on_craft_visual_update)
	_craft_ctrl.sync_states()

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

func _connect_signals() -> void:
	GridManager.item_added.connect(_on_item_added)
	GridManager.item_removed.connect(_on_item_removed)
	GridManager.item_moved.connect(_on_item_moved)
	GridManager.grid_updated.connect(_on_grid_updated)
	CloudService.spawn_confirmed.connect(_on_spawn_confirmed)
	CloudService.spawn_rejected.connect(_on_spawn_rejected)
	CloudService.move_confirmed.connect(_on_move_confirmed)
	CloudService.move_rejected.connect(_on_move_rejected)
	MergeService.merge_failed.connect(_on_merge_failed)
	CloudService.push_place_confirmed.connect(_on_push_place_confirmed)
	CloudService.push_place_rejected.connect(_on_push_place_rejected)

# --- Input: press on any item, then drag or click dispatch ---

func _input(event: InputEvent) -> void:
	if UIManager.is_input_blocked():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local_pos := _to_local(mb.position)
		var cell_pos := _local_to_grid(local_pos)

		if mb.pressed:
			if _is_dragging or not GridManager.is_valid_pos(cell_pos) or local_pos.x < 0 or local_pos.y < 0 or local_pos.x > size.x or local_pos.y > size.y:
				return
			var item = GridManager.get_item(cell_pos)
			if item == null:
				return
			_press_start_pos = cell_pos
			_press_screen_pos = local_pos
			_pressed_item = item
			_pressed_has_moved = false
		elif _is_dragging:
			_finish_drag(cell_pos)
		elif _pressed_has_moved == false and not _pressed_item.is_empty():
			_select_item(_press_start_pos)
			item_clicked.emit(_pressed_item, _press_start_pos)

			if _pressed_item.get("id") == 603:
				_handle_storage_click(_press_start_pos)
				_pressed_item = {}
				return
			if _pressed_item.get("type") == "crafting":
				var cstate: int = _pressed_item.get("_craft_state", CraftingService.TableState.IDLE)
				if cstate == CraftingService.TableState.READY:
					_craft_ctrl.try_retrieve(_pressed_item, _press_start_pos)
					_pressed_item = {}
					return
				item_clicked.emit(_pressed_item, _press_start_pos)
				if cstate == CraftingService.TableState.HAS_ITEMS:
					var recipe: Dictionary = _pressed_item.get("_craft_recipe", {})
					if not recipe.is_empty():
						_craft_ctrl.show_button_for_table(recipe, position, _press_start_pos, CELL_SIZE)
				_pressed_item = {}
				return

			_craft_ctrl.hide_button()
			if _pressed_item.get("type") == "launcher":
				pass  # handled on double-click via _select_item
			_pressed_item = {}

	elif event is InputEventMouseMotion:
		var local_pos := _to_local(event.position)
		if _is_dragging:

			var drag_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
			var drag_node = _item_nodes.get(drag_key)
			if drag_node and is_instance_valid(drag_node):
				drag_node.position = get_global_mouse_position() - global_position - Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
			_update_highlights(local_pos)
		elif not _pressed_item.is_empty() and not _pressed_has_moved:
			if local_pos.distance_to(_press_screen_pos) > DRAG_THRESHOLD:
				_pressed_has_moved = true
				_start_drag(_press_start_pos)

func _to_local(global_pos: Vector2) -> Vector2:
	return global_pos - global_position

func _local_to_grid(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(local_pos.x / CELL_SIZE), int(local_pos.y / CELL_SIZE))


func _handle_crafting_drop(table_pos: Vector2i, table_item: Dictionary) -> void:
	var dragged_item: Dictionary = GridManager.get_item(_drag_source_pos) as Dictionary
	if dragged_item == null or dragged_item.is_empty():
		_snap_back()
		return
	var ok: bool = _craft_ctrl.try_add_ingredient(table_pos, table_item, _drag_source_pos, dragged_item.get("id", 0) as int, dragged_item)
	if not ok:
		_snap_back()
	else:
		var table_key := "%d,%d" % [table_pos.x, table_pos.y]
		var table_node = _item_nodes.get(table_key)
		if table_node and is_instance_valid(table_node):
			table_node.set_crafting_state(CraftingService.TableState.HAS_ITEMS)

func _handle_launcher_click(pos: Vector2i) -> void:
	if GameState.phase != GameState.GamePhase.IDLE or _launcher_ctrl.is_spawn_in_flight():
		return
	_pressed_item = {}
	GameState.set_phase(GameState.GamePhase.SPAWNING)
	var item: Dictionary = GridManager.get_item(pos) as Dictionary
	if item == null or item.is_empty():
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	var item_config: Dictionary = ConfigDatabase.get_item_data(item.get("id", 0) as int)
	_cached_launcher_uid = item.get("_uid", -1) as int
	var ok: bool = _launcher_ctrl.try_spawn(pos,
		_cached_launcher_uid,
		item.get("charges", -1) as int,
		item.get("immovable") == true,
		item_config.get("no_cost", false),
		item_config.get("recharge_time", 0.0) as float)
	if not ok:
		GameState.set_phase(GameState.GamePhase.IDLE)

func _on_spawn_confirmed(result: Dictionary) -> void:
	var target_pos: Vector2i = Vector2i(result.get("target_col", -1), result.get("target_row", -1))
	var spawned_id: int = result.get("spawned_id", 0)
	var spawned_name: String = result.get("spawned_name", "")

	# Create the item from server result
	var item_data: Dictionary = ConfigDatabase.get_item_data(spawned_id)
	if not item_data.is_empty():
		var new_item: Dictionary = item_data.duplicate(true)
		new_item["_uid"] = result.get("spawned_uid", 0)
		if new_item.get("type", "") == "launcher":
			new_item["charges"] = new_item.get("max_charges", 3)
		_is_launcher_spawning = true
		GridManager.add_item(new_item, target_pos)
		_is_launcher_spawning = false

	# Fly animation from launcher to target
	var launcher_uid: int = _cached_launcher_uid
	_cached_launcher_uid = -1
	var launcher_pos: Vector2i = GridManager.find_pos_by_uid(launcher_uid)
	var fly_key := "%d,%d" % [target_pos.x, target_pos.y]
	var fly_node: GridItem = _item_nodes.get(fly_key)
	if fly_node and is_instance_valid(fly_node) and launcher_pos.x >= 0:
		fly_node.position = Vector2(launcher_pos.x * CELL_SIZE, launcher_pos.y * CELL_SIZE)
		fly_node.scale = Vector2(0.7, 0.7)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(fly_node, "position", Vector2(target_pos.x * CELL_SIZE, target_pos.y * CELL_SIZE), 0.35).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(fly_node, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_BOUNCE)

	# Update stamina

	var stamina: Variant = result.get("stamina", null)

	var regen_ms: float = result.get("regen_remaining_ms", 0.0)

	if regen_ms > 0:
		GameState.regen_remaining_ms = regen_ms

	if stamina != null:

		GameState.stamina = stamina

		GameState.max_stamina = result.get("max_stamina", GameState.max_stamina)

		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	# Update cultivation (qi cost for battle board spawn)
	var cult: Variant = result.get("cultivation", null)
	if cult != null:
		CultivationService.deserialize(cult)

	# Launcher charges handled by LauncherController

	if GameState.phase == GameState.GamePhase.SPAWNING:
		GameState.set_phase(GameState.GamePhase.IDLE)

func _on_spawn_rejected(reason: String) -> void:
	print("[GridView] Spawn rejected: ", reason)
	EventBus.show_toast.emit(_spawn_error_text(reason))
	# LauncherController also handles this independently

func _spawn_error_text(reason: String) -> String:
	match reason:
		"launcher_not_found": return "生成失败：发射器不存在"
		"not_a_launcher": return "生成失败：不是发射器"
		"no_empty_cell": return "生成失败：棋盘已满"
		"insufficient_stamina": return "体力不足"
		"insufficient_qi": return "灵力不足"
		"no_charges": return "发射器次数用尽"
		"network_error": return "生成失败：网络错误"
		_: return "生成失败：" + reason

func _start_drag(pos: Vector2i) -> void:
	if GameState.phase != GameState.GamePhase.IDLE:
		return
	_deselect_all()
	var item = GridManager.get_item(pos)
	if item == null:
		return

	if item.get("immovable") == true:
		EventBus.show_toast.emit("该物品无法移动")
		return

	_drag_source_pos = pos
	_drag_item_data = item
	_is_dragging = true
	GameState.set_phase(GameState.GamePhase.DRAGGING)
	var drag_key := "%d,%d" % [pos.x, pos.y]
	var drag_node = _item_nodes.get(drag_key)
	if drag_node and is_instance_valid(drag_node):
		drag_node.z_index = 100

	_craft_ctrl.hide_button()

func _finish_drag(target_pos: Vector2i) -> void:
	_is_dragging = false
	var drag_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var drag_node = _item_nodes.get(drag_key)
	if drag_node and is_instance_valid(drag_node):
		drag_node.z_index = 0
	_pressed_item = {}
	_clear_highlights()

	if _pouch_zone and _pouch_zone.visible and Rect2(_pouch_zone.global_position, _pouch_zone.size).has_point(get_global_mouse_position()):
		_do_pouch_deposit()
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	if not GridManager.is_valid_pos(target_pos) or not Rect2(global_position, size).has_point(get_global_mouse_position()):
		_snap_back()
		GameState.set_phase(GameState.GamePhase.IDLE)
		return
	if target_pos == _drag_source_pos:
		_snap_back()
		GameState.set_phase(GameState.GamePhase.IDLE)
		return

	var target = GridManager.get_item(target_pos)

	if target != null and target.get("id") == 603:
		_handle_storage_drop(target_pos, target)
		if GameState.phase in [GameState.GamePhase.DRAGGING, GameState.GamePhase.MERGING]:
			GameState.set_phase(GameState.GamePhase.IDLE)
		return
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
		if target != null and target.get("immovable") == true:
			_snap_back()
		elif CloudService.online:
			_pending_push_src = _drag_source_pos
			_pending_push_target = target_pos
			CloudService.submit_push_place(_drag_source_pos.x, _drag_source_pos.y, target_pos.x, target_pos.y)
	if GameState.phase in [GameState.GamePhase.DRAGGING, GameState.GamePhase.MERGING]:
		GameState.set_phase(GameState.GamePhase.IDLE)

func _place_dragged_item(target_pos: Vector2i) -> void:
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var node = _item_nodes.get(src_key)
	if node and is_instance_valid(node):
		node.position = Vector2(target_pos.x * CELL_SIZE, target_pos.y * CELL_SIZE)
	GridManager.move_item(_drag_source_pos, target_pos)
	if CloudService.online:
		CloudService.submit_move(_drag_source_pos.x, _drag_source_pos.y, target_pos.x, target_pos.y)

func _do_pouch_deposit() -> void:
	if _drag_item_data.is_empty():
		return
	var item_id: int = _drag_item_data.get("id", 0)
	if item_id <= 0:
		return
	# Remove visual node immediately; data model removed on server confirmation
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var src_node = _item_nodes.get(src_key)
	if src_node and is_instance_valid(src_node):
		src_node.queue_free()
	_item_nodes.erase(src_key)
	if StoragePouch:
		StoragePouch.deposit(_drag_item_data.get("_uid", 0))

func _on_pouch_deposit_failed(_reason: String) -> void:
	var gitem = GridManager.get_item(_drag_source_pos)
	if gitem != null:
		_on_item_added(gitem, _drag_source_pos)

func _on_push_place_confirmed(result: Dictionary) -> void:
	print("[GridView] push_place confirmed: pushed=(" + str(result.get("pushed_col", -1)) + "," + str(result.get("pushed_row", -1)) + ")")
	var pushed_pos := Vector2i(result.get("pushed_col", -1), result.get("pushed_row", -1))
	if _pending_push_target.x >= 0 and pushed_pos.x >= 0:
		var src_key := "%d,%d" % [_pending_push_src.x, _pending_push_src.y]
		var dst_key := "%d,%d" % [_pending_push_target.x, _pending_push_target.y]
		if pushed_pos == _pending_push_src:
			# Direct swap using public API
			GridManager.swap_items(_pending_push_src, _pending_push_target)
			var src_node = _item_nodes.get(src_key)
			var dst_node = _item_nodes.get(dst_key)
			# Fix node dict to match new positions
			_item_nodes[src_key] = dst_node
			_item_nodes[dst_key] = src_node
			# Visual: source snaps to target
			if src_node and is_instance_valid(src_node):
				src_node.position = Vector2(_pending_push_target.x * CELL_SIZE, _pending_push_target.y * CELL_SIZE)
				src_node.grid_position = _pending_push_target
			# Visual: target tweens to source
			if dst_node and is_instance_valid(dst_node):
				dst_node.grid_position = _pending_push_src
				var tween := create_tween()
				tween.tween_property(dst_node, "position", Vector2(_pending_push_src.x * CELL_SIZE, _pending_push_src.y * CELL_SIZE), 0.15)
		else:
			GridManager.move_item(_pending_push_target, pushed_pos)
			GridManager.move_item(_pending_push_src, _pending_push_target)
	_pending_push_src = Vector2i(-1, -1)
	_pending_push_target = Vector2i(-1, -1)
func _on_push_place_rejected(reason: String) -> void:
	print("[GridView] push_place REJECTED: " + reason)
	_pending_push_src = Vector2i(-1, -1)
	_pending_push_target = Vector2i(-1, -1)

func _on_move_confirmed(result: Dictionary) -> void:
	pass

func _on_move_rejected(reason: String) -> void:
	print("[GridView] Move rejected: ", reason)

func _on_merge_failed(_reason: String) -> void:
	_merge_in_flight = false

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
	if not _is_launcher_spawning and not _skip_anims and not GridManager._skip_anims:
		item.play_spawn_animation()
	_item_nodes["%d,%d" % [pos.x, pos.y]] = item
	_try_start_launcher_cd(item_data)

func _try_start_launcher_cd(item_data: Dictionary) -> void:
	_launcher_ctrl.start_cd_from_restore(item_data)

func _on_item_removed(item_data: Dictionary, pos: Vector2i) -> void:
	var key := "%d,%d" % [pos.x, pos.y]
	var node = _item_nodes.get(key)
	if node and is_instance_valid(node):
		if _skip_anims:
			node.queue_free()
			_item_nodes.erase(key)
			return
		node.play_merge_animation()
	_item_nodes.erase(key)
	_launcher_ctrl.clear_cd(item_data.get("_uid", 0) as int)

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
		_try_start_launcher_cd(entry.data)

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

var _last_craft_ingredient_id: int = -1
var _last_craft_ingredient_pos: Vector2i = Vector2i(-1, -1)

# Pending state for craft_add (deferred until server confirms)
var _last_craft_pending_src_key: String = ""
var _last_craft_pending_src_pos: Vector2i = Vector2i(-1, -1)
var _last_craft_pending_table_item: Dictionary = {}
var _last_craft_pending_dragged_item: Dictionary = {}
var _last_craft_pending_table_pos: Vector2i = Vector2i(-1, -1)
var _last_craft_pending_ingredient_id: int = -1

# Check if stored items + new ingredient match a recipe, show craft button if so

func _handle_storage_click(storage_pos: Vector2i) -> void:
	CloudService.fetch_state()
	CloudService.state_loaded.connect(func(data):
		var items: Array = []
		for entry in data.grid:
			if entry.col == storage_pos.x and entry.row == storage_pos.y and entry.has("storage"):
				items = entry.storage.items
				break
		var popup := preload("res://scenes/ui/main/StoragePopup.tscn").instantiate() as StoragePopup
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
	var removed_sd: Dictionary = GridManager.remove_item(_drag_source_pos)
	var sd_uid: int = removed_sd.get("uid", removed_sd.get("_uid", 0)) as int

	if CloudService.online:
		CloudService.submit_storage_deposit(storage_pos.x, storage_pos.y, item_id, _drag_source_pos.x, _drag_source_pos.y)


func _on_craft_item_accepted(src_key: String, src_pos: Vector2i) -> void:
	var src_node = _item_nodes.get(src_key)
	if src_node and is_instance_valid(src_node):
		src_node.queue_free()
	_item_nodes.erase(src_key)
	var removed_item: Dictionary = GridManager.remove_item(src_pos)
	var removed_uid: int = removed_item.get("uid", removed_item.get("_uid", 0)) as int

func _on_craft_rejected(reason: String) -> void:
	if reason == "snap_back":
		_snap_back()
	else:
		_snap_back()
		EventBus.show_toast.emit(reason)

func _on_craft_retrieve_ready(result_id: int, result_uid: int, table_pos: Vector2i) -> void:
	var result_data := ConfigDatabase.get_item_data(result_id)
	if result_data.is_empty():
		EventBus.show_toast.emit("制作完成，但找不到物品配置 #%d" % result_id)
		return
	var spawn_pos := GridManager.find_nearest_empty(table_pos)
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满，无法取出制作结果")
		return
	var new_item: Dictionary = result_data.duplicate(true)
	new_item["_uid"] = result_uid
	_is_launcher_spawning = true
	GridManager.add_item(new_item, spawn_pos)
	_is_launcher_spawning = false
	item_clicked.emit({}, Vector2i(-1, -1))
	EventBus.show_toast.emit("制作完成：%s" % result_data.get("name", "未知"))

func _on_craft_visual_update(table_item: Dictionary, state: int) -> void:
	for key in _item_nodes:
		var node = _item_nodes[key]
		if node and is_instance_valid(node) and node.item_data == table_item:
			node.set_crafting_state(state)
			break

# --- End CraftingController signal handlers ---

# --- LauncherController signal handlers ---

func _on_launcher_spawn_finished() -> void:
	pass  # LauncherController handles state internally

func _on_launcher_spawn_failed(reason: String) -> void:
	EventBus.show_toast.emit(reason)

func _on_launcher_charge_update(uid: int, text: String, color: Color) -> void:
	for node_key in _item_nodes:
		var node = _item_nodes[node_key]
		if is_instance_valid(node) and node.item_data.get("_uid", 0) == uid:
			node.charge_label.text = text
			node.charge_label.add_theme_color_override("font_color", color)
			break

func _on_launcher_depleted_removed(uid: int, grid_pos: Vector2i) -> void:
	for nk in _item_nodes:
		var nd = _item_nodes[nk]
		if is_instance_valid(nd) and nd.item_data.get("_uid", 0) == uid:
			nd.queue_free()
			_item_nodes.erase(nk)
			break
	if grid_pos.x >= 0:
		GridManager.remove_item(grid_pos)
	EventBus.show_toast.emit("礼包已耗尽")

func _select_item(pos: Vector2i) -> void:
	var key := "%d,%d" % [pos.x, pos.y]
	if key == _selected_key and not _selected_key.is_empty():
		var item: Variant = GridManager.get_item(pos)
		if item != null:
			if item.get("immovable") == true:
				EventBus.show_toast.emit("该物品无法使用")
				return
			if item.get("type") == "launcher":
				print("[GridView] double-click spawn: id=" + str(item.get("id",0)))
				_handle_launcher_click(pos)
			else:
				print("[GridView] double-click use: id=" + str(item.get("id",0)) + " type=" + str(item.get("type","")))
				item_use_requested.emit(item, pos)
				_deselect_all()
		return
	_deselect_all()
	var node := _item_nodes.get(key) as GridItem
	if node and is_instance_valid(node):
		node.set_selected(true)
		_selected_key = key

func _sync_grid_from_server(result: Dictionary) -> void:
	var server_grid: Array = result.get("grid", [])
	if server_grid.is_empty():
		return
	GridManager.init_grid()
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			if entry.has("uid"): item["_uid"] = entry.uid
			if entry.has("immovable"): item["immovable"] = entry.immovable
			GridManager.add_item(item, Vector2i(entry.col, entry.row))

func _deselect_all() -> void:
	if not _selected_key.is_empty():
		var node := _item_nodes.get(_selected_key) as GridItem
		if node and is_instance_valid(node):
			node.set_selected(false)
		_selected_key = ""
