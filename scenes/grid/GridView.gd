class_name GridView extends Control

# GridView: Visual 7x9 grid. Handles all input, item visuals, and drag-and-drop.

const LauncherControllerClass := preload("res://scenes/grid/LauncherController.gd")
const CraftingControllerClass := preload("res://scenes/grid/CraftingController.gd")
const CELL_SIZE := Constants.CELL_SIZE
const CELL_STEP := Constants.CELL_STEP
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
var _merge_failed_is_push: bool = false
var _cached_launcher_uid: int = -1
var _pending_push_src: Vector2i = Vector2i(-1, -1)
var _pending_push_target: Vector2i = Vector2i(-1, -1)
var _pending_move_src: Vector2i = Vector2i(-1, -1)
var _pending_move_target: Vector2i = Vector2i(-1, -1)
var _pending_storage_deposit_src: Vector2i = Vector2i(-1, -1)
var _pending_storage_storage_pos: Vector2i = Vector2i(-1, -1)

func set_pouch_zone(zone: Control) -> void:
	_pouch_zone = zone

func set_skip_animations(skip: bool) -> void:
	_skip_anims = skip

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("[GridView] _ready: size=", size, " position=", position, " visible=", visible)
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
	_craft_ctrl.craft_start_requested.connect(_on_craft_start_requested)
	_craft_ctrl.sync_states()

func _create_grid() -> void:
	print("[GridView] _create_grid: CELL_SIZE=", CELL_SIZE, " CELL_STEP=", CELL_STEP, " grid=", GRID_COLS, "x", GRID_ROWS)
	var cells_layer := Control.new()
	cells_layer.name = "GridCells"
	cells_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cells_layer)
	print("[GridView] cells_layer created, adding cells...")

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cell := grid_cell_scene.instantiate()
			cells_layer.add_child(cell)
			cell.setup(Vector2i(col, row), CELL_STEP)
			_cell_nodes["%d,%d" % [col, row]] = cell
	print("[GridView] cells done: ", _cell_nodes.size(), " cells")

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
	CloudService.storage_deposit_confirmed.connect(_on_storage_deposit_confirmed)
	CloudService.storage_deposit_rejected.connect(_on_storage_deposit_rejected)
	StoragePouch.deposit_failed.connect(_on_pouch_deposit_rejected)

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
			if _is_dragging:
				return
			if _craft_ctrl.is_point_over_button(local_pos):
				return
			if not GridManager.is_valid_pos(cell_pos) or local_pos.x < 0 or local_pos.y < 0 or local_pos.x > size.x or local_pos.y > size.y:
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

			if _pressed_item.get("type", 0) == Constants.ItemType.CRAFTING:
				var cstate: int = _pressed_item.get("_craft_state", CraftingService.TableState.IDLE)
				if cstate == CraftingService.TableState.READY:
					_craft_ctrl.try_retrieve(_pressed_item, _press_start_pos)
					_pressed_item = {}
					return
				item_clicked.emit(_pressed_item, _press_start_pos)
				if cstate == CraftingService.TableState.HAS_ITEMS:
					var recipe: Dictionary = _pressed_item.get("_craft_recipe", {})
					if not recipe.is_empty():
						_craft_ctrl.show_button_for_table(recipe, _press_start_pos, CELL_STEP)
				_pressed_item = {}
				return

			_craft_ctrl.hide_button()
			if Constants.has_launcher_config(_pressed_item):
				pass  # handled on double-click via _select_item
			_pressed_item = {}

	elif event is InputEventMouseMotion:
		var local_pos := _to_local(event.position)
		if _is_dragging:

			var drag_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
			var drag_node = _item_nodes.get(drag_key)
			if drag_node and is_instance_valid(drag_node):
				drag_node.position = get_global_mouse_position() - global_position - Vector2(CELL_STEP * 0.5, CELL_STEP * 0.5)
			_update_highlights(local_pos)
		elif not _pressed_item.is_empty() and not _pressed_has_moved:
			if local_pos.distance_to(_press_screen_pos) > DRAG_THRESHOLD:
				_pressed_has_moved = true
				_start_drag(_press_start_pos)

func _to_local(global_pos: Vector2) -> Vector2:
	return global_pos - global_position

func _local_to_grid(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(local_pos.x / CELL_STEP), int(local_pos.y / CELL_STEP))


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
	if _launcher_ctrl.is_spawn_in_flight():
		return
	_pressed_item = {}
	var item: Dictionary = GridManager.get_item(pos) as Dictionary
	if item == null or item.is_empty():
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
		pass

func _on_spawn_confirmed(result: Dictionary) -> void:
	var target_pos: Vector2i = Vector2i(result.get("target_col", -1), result.get("target_row", -1))
	var spawned_id: int = result.get("spawned_id", 0)
	var spawned_name: String = result.get("spawned_name", "")

	# Create the item from server result
	var item_data: Dictionary = ConfigDatabase.get_item_data(spawned_id)
	if not item_data.is_empty():
		var new_item: Dictionary = item_data.duplicate(true)
		new_item["_uid"] = result.get("spawned_uid", 0)
		if Constants.has_launcher_config(new_item):
			new_item["charges"] = new_item.get("max_charges", 3)
		var atk_base: int = result.get("atk_base", 0) as int
		if atk_base > 0:
			new_item["atk_base"] = atk_base
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
		fly_node.position = Vector2(launcher_pos.x * CELL_STEP, launcher_pos.y * CELL_STEP)
		fly_node.scale = Vector2(0.7, 0.7)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(fly_node, "position", Vector2(target_pos.x * CELL_STEP, target_pos.y * CELL_STEP), 0.35).set_trans(Tween.TRANS_CUBIC)
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

	# spawn phase handled by LauncherController

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
	if _is_dragging:
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
		return

	if not GridManager.is_valid_pos(target_pos) or not Rect2(global_position, size).has_point(get_global_mouse_position()):
		_snap_back()
		return
	if target_pos == _drag_source_pos:
		_snap_back()
		return

	var target = GridManager.get_item(target_pos)

	if target != null:
		var _target_cfg := ConfigDatabase.get_item_data(target.get("id", 0))
		if _target_cfg.get("storage_slots", 0) > 0:
			_handle_storage_drop(target_pos, target)
			return
	if target != null and target.get("type", 0) == Constants.ItemType.CRAFTING:
		_handle_crafting_drop(target_pos, target)
		return
	if target == null:
		_place_dragged_item(target_pos)
		if _drag_item_data.get("type", 0) == Constants.ItemType.CRAFTING:
			item_clicked.emit(_drag_item_data, target_pos)
	else:
		_merge_failed_is_push = true
		if not MergeService.try_merge(_drag_source_pos, target_pos):
			if target != null and target.get("immovable") == true:
				_snap_back()
			elif CloudService.online:
				_pending_push_src = _drag_source_pos
				_pending_push_target = target_pos
				CloudService.submit_push_place(_drag_source_pos.x, _drag_source_pos.y, target_pos.x, target_pos.y)
		else:
			_merge_failed_is_push = false


func _place_dragged_item(target_pos: Vector2i) -> void:
	if _pending_move_src.x >= 0:
		_snap_back()
		return
	var src_key := "%d,%d" % [_drag_source_pos.x, _drag_source_pos.y]
	var node = _item_nodes.get(src_key)
	if node and is_instance_valid(node):
		node.position = Vector2(target_pos.x * CELL_STEP, target_pos.y * CELL_STEP)
	_pending_move_src = _drag_source_pos
	_pending_move_target = target_pos
	if CloudService.online:
		CloudService.submit_move(_drag_source_pos.x, _drag_source_pos.y, target_pos.x, target_pos.y)

func _do_pouch_deposit() -> void:
	if _drag_item_data.is_empty():
		return
	var item_id: int = _drag_item_data.get("id", 0)
	if item_id <= 0:
		return
	if StoragePouch:
		StoragePouch.deposit(_drag_item_data.get("_uid", 0))

func _on_pouch_deposit_rejected(reason: String) -> void:
	EventBus.show_toast.emit("存入背包失败：" + reason)

func _on_push_place_confirmed(result: Dictionary) -> void:
	print("[GridView] push_place_confirmed: src=", _pending_push_src, " tgt=", _pending_push_target, " pushed=", Vector2i(result.get("pushed_col", -1), result.get("pushed_row", -1)))
	print("[GridView] push_place confirmed: pushed=(" + str(result.get("pushed_col", -1)) + "," + str(result.get("pushed_row", -1)) + ")")
	var pushed_pos := Vector2i(result.get("pushed_col", -1), result.get("pushed_row", -1))
	if _pending_push_target.x >= 0 and pushed_pos.x >= 0:
		var src_key := "%d,%d" % [_pending_push_src.x, _pending_push_src.y]
		var dst_key := "%d,%d" % [_pending_push_target.x, _pending_push_target.y]
		if pushed_pos == _pending_push_src:
			# swap_items triggers item_moved which handles visual update
			GridManager.swap_items(_pending_push_src, _pending_push_target)
		else:
			GridManager.move_item(_pending_push_target, pushed_pos)
			_skip_anims = true
			GridManager.move_item(_pending_push_src, _pending_push_target)
			_skip_anims = false
	_pending_push_src = Vector2i(-1, -1)
	_pending_push_target = Vector2i(-1, -1)
func _on_push_place_rejected(reason: String) -> void:
	print("[GridView] push_place REJECTED: " + reason)
	if _pending_push_src.x >= 0:
		_snap_back_to(_pending_push_src)
	_pending_push_src = Vector2i(-1, -1)
	_pending_push_target = Vector2i(-1, -1)

func _on_move_confirmed(_result: Dictionary) -> void:
	if _pending_move_src.x >= 0 and _pending_move_target.x >= 0:
		GridManager.move_item(_pending_move_src, _pending_move_target)
	_pending_move_src = Vector2i(-1, -1)
	_pending_move_target = Vector2i(-1, -1)

func _on_move_rejected(reason: String) -> void:
	print("[GridView] Move rejected: ", reason)
	EventBus.show_toast.emit("移动失败：" + reason)
	if _pending_move_src.x >= 0:
		_snap_back_to(_pending_move_src)
	_pending_move_src = Vector2i(-1, -1)
	_pending_move_target = Vector2i(-1, -1)

func _on_merge_failed(_reason: String) -> void:
	_merge_in_flight = false
	if _merge_failed_is_push:
		_merge_failed_is_push = false
		return
	if _drag_source_pos.x >= 0:
		_snap_back_to(_drag_source_pos)

func _snap_back() -> void:
	_snap_back_to(_drag_source_pos)

func _snap_back_to(pos: Vector2i) -> void:
	var key := "%d,%d" % [pos.x, pos.y]
	var item_node = _item_nodes.get(key)
	if item_node and is_instance_valid(item_node):
		var target := Vector2(pos.x * CELL_STEP, pos.y * CELL_STEP)
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
	item.setup(item_data, pos, CELL_STEP)
	if GameState.current_board_type != Constants.BoardType.MAIN:
		item.set_required(false)
	if not _is_launcher_spawning and not _skip_anims and not GridManager._skip_anims:
		item.play_spawn_animation()
	_item_nodes["%d,%d" % [pos.x, pos.y]] = item
	_try_start_launcher_cd(item_data)
	CraftingService.restore_craft_timer_for_item(item_data)

func _try_start_launcher_cd(item_data: Dictionary) -> void:
	if not Constants.has_launcher_config(item_data):
		return
	_launcher_ctrl.start_cd_from_restore(item_data)

func _on_item_removed(item_data: Dictionary, pos: Vector2i) -> void:
	var key := "%d,%d" % [pos.x, pos.y]
	if key == _selected_key:
		_selected_key = ""
	var node = _item_nodes.get(key)
	if node and is_instance_valid(node):
		if _skip_anims:
			node.queue_free()
			_item_nodes.erase(key)
			return
		node.play_merge_animation()
	_item_nodes.erase(key)
	# CD managed by LauncherController start_cd_from_restore

func _on_item_moved(item_data: Dictionary, from_pos: Vector2i, to_pos: Vector2i) -> void:
	var key := "%d,%d" % [from_pos.x, from_pos.y]
	var node = _item_nodes.get(key)
	if node and is_instance_valid(node):
		node.grid_position = to_pos
		_item_nodes.erase(key)
		_item_nodes["%d,%d" % [to_pos.x, to_pos.y]] = node
		var target := Vector2(to_pos.x * CELL_STEP, to_pos.y * CELL_STEP)
		if _skip_anims:
			node.position = target
		else:
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
		item.setup(entry.data, entry.pos, CELL_STEP)
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

# Check if stored items + new ingredient match a recipe, show craft button if so

# Storage popup opens directly from local grid data
var _storage_popup_open: bool = false

func _has_storage_slots(item: Variant) -> bool:
	if item == null:
		return false
	var cfg: Dictionary = ConfigDatabase.get_item_data(item.get("id", 0))
	return cfg.get("storage_slots", 0) > 0

func _handle_storage_click(storage_pos: Vector2i) -> void:
	if _storage_popup_open:
		return
	var item = GridManager.get_item(storage_pos)
	if item == null:
		return
	var storage_data: Variant = item.get("storage", null)
	var items: Array = storage_data.get("items", []) if storage_data is Dictionary else []
	var popup := preload("res://scenes/ui/main/StoragePopup.tscn").instantiate() as StoragePopup
	popup.setup(storage_pos, items)
	_storage_popup_open = true
	popup.tree_exiting.connect(func(): _storage_popup_open = false)
	UIManager.show_popup(popup)

func _handle_storage_drop(storage_pos: Vector2i, storage_item: Dictionary) -> void:
	var dragged_item = GridManager.get_item(_drag_source_pos)
	if dragged_item == null:
		_snap_back()
		return
	if _pending_storage_deposit_src.x >= 0:
		_snap_back()
		EventBus.show_toast.emit("操作太频繁，请稍后再试")
		return

	var item_uid: int = dragged_item.get("_uid", 0)
	_pending_storage_deposit_src = _drag_source_pos
	_pending_storage_storage_pos = storage_pos

	if CloudService.online:
		CloudService.submit_storage_deposit(storage_pos.x, storage_pos.y, item_uid, _drag_source_pos.x, _drag_source_pos.y)


func _on_storage_deposit_confirmed(result: Dictionary) -> void:
	if _pending_storage_deposit_src.x >= 0:
		var src_key := "%d,%d" % [_pending_storage_deposit_src.x, _pending_storage_deposit_src.y]
		var src_node = _item_nodes.get(src_key)
		if src_node and is_instance_valid(src_node):
			src_node.queue_free()
		_item_nodes.erase(src_key)
		GridManager.remove_item(_pending_storage_deposit_src)
	# Update storage item data from server grid
	var server_grid: Array = result.get("grid", [])
	var storage_pos := _pending_storage_storage_pos
	for entry in server_grid:
		if entry.col == storage_pos.x and entry.row == storage_pos.y:
			var item: Variant = GridManager.get_item(storage_pos)
			if item != null:
				item["storage"] = entry.get("storage", {})
			break
	_pending_storage_deposit_src = Vector2i(-1, -1)
	_pending_storage_storage_pos = Vector2i(-1, -1)

func _on_storage_deposit_rejected(reason: String) -> void:
	print("[GridView] Storage deposit rejected: ", reason)
	EventBus.show_toast.emit("存入仓库失败：" + reason)
	if _pending_storage_deposit_src.x >= 0:
		_snap_back_to(_pending_storage_deposit_src)
	_pending_storage_deposit_src = Vector2i(-1, -1)
	_pending_storage_storage_pos = Vector2i(-1, -1)


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

func _on_craft_start_requested(table_pos: Vector2i) -> void:
	var key := "%d,%d" % [table_pos.x, table_pos.y]
	if _selected_key != key:
		_deselect_all()
	var node := _item_nodes.get(key) as GridItem
	if node and is_instance_valid(node):
		node.set_selected(true)
		_selected_key = key
	var table_item: Variant = GridManager.get_item(table_pos)
	if table_item != null:
		item_clicked.emit(table_item as Dictionary, table_pos)

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
			if Constants.has_launcher_config(item):
				print("[GridView] double-click spawn: id=" + str(item.get("id",0)))
				_handle_launcher_click(pos)
			elif _has_storage_slots(item):
				_handle_storage_click(pos)
			else:
				print("[GridView] double-click use: id=" + str(item.get("id",0)) + " type=" + str(item.get("type","")))
				item_use_requested.emit(item, pos)
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
