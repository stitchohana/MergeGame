class_name GridView extends Control

# GridView: Visual 7x9 grid. Handles all input, item visuals, and drag-and-drop.

const LauncherControllerClass := preload("res://scenes/grid/LauncherController.gd")
const CraftingControllerClass := preload("res://scenes/grid/CraftingController.gd")
const ACTION_SYNC_SCREEN_SCENE := preload("res://scenes/screens/ActionSyncScreen.tscn")
const CELL_SIZE := Constants.CELL_SIZE
const CELL_STEP := Constants.CELL_STEP
const DRAG_THRESHOLD := 10.0  # pixels before drag starts

@export var grid_item_scene: PackedScene
@export var grid_cell_texture: Texture2D

signal item_clicked(item_data: Dictionary, grid_pos: Vector2i)
signal pill_dropped_outside(item_data: Dictionary, drop_position: Vector2)
signal item_use_requested(item_data: Dictionary, grid_pos: Vector2i)

var _item_nodes: Dictionary = {}  # "col,row" -> GridItem

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
var _pending_push_src: Vector2i = Vector2i(-1, -1)
var _pending_push_target: Vector2i = Vector2i(-1, -1)
var _pending_spawn_actions: Array[Dictionary] = []
var _active_spawn_actions: Array[Dictionary] = []
var _spawn_action_batch_in_flight: bool = false
var _action_sync_needed: bool = false
var _action_sync_waiters: Array[Callable] = []
var _action_sync_screen: Control = null
var _cancel_waiters_after_recovery: bool = false
var _action_recovery_in_flight: bool = false
var _pending_storage_deposit_src: Vector2i = Vector2i(-1, -1)
var _pending_storage_storage_pos: Vector2i = Vector2i(-1, -1)

func set_pouch_zone(zone: Control) -> void:
	_pouch_zone = zone

func set_skip_animations(skip: bool) -> void:
	_skip_anims = skip

func run_after_action_sync(callback: Callable) -> void:
	if not callback.is_valid():
		return
	if not _has_unsynced_actions():
		callback.call()
		return
	_action_sync_waiters.push_back(callback)
	_show_action_sync_screen()
	_flush_spawn_action_batch()
	call_deferred("_finalize_action_sync")
	call_deferred("_try_finish_action_sync_barrier")

func _has_unsynced_actions() -> bool:
	return (
		_spawn_action_batch_in_flight
		or not _pending_spawn_actions.is_empty()
		or _action_sync_needed
		or _action_recovery_in_flight
		or (_launcher_ctrl != null and _launcher_ctrl.is_spawn_in_flight())
	)

func _try_finish_action_sync_barrier() -> void:
	if _action_sync_waiters.is_empty() or _has_unsynced_actions():
		return
	var waiters: Array[Callable] = _action_sync_waiters.duplicate()
	_action_sync_waiters.clear()
	_hide_action_sync_screen()
	for callback: Callable in waiters:
		if callback.is_valid():
			callback.call()

func _cancel_action_sync_waiters(message: String) -> void:
	_action_sync_waiters.clear()
	_hide_action_sync_screen()
	if not message.is_empty():
		EventBus.show_toast.emit(message)

func _show_action_sync_screen() -> void:
	if _action_sync_screen and is_instance_valid(_action_sync_screen):
		return
	_action_sync_screen = ACTION_SYNC_SCREEN_SCENE.instantiate() as Control
	var layer: Control = UIManager.get_layer(UIManager.Layer.LOADING)
	if layer:
		layer.add_child(_action_sync_screen)
	set_process_input(false)

func _hide_action_sync_screen() -> void:
	if _action_sync_screen and is_instance_valid(_action_sync_screen):
		_action_sync_screen.queue_free()
	_action_sync_screen = null
	set_process_input(true)

func _exit_tree() -> void:
	_action_sync_waiters.clear()
	_hide_action_sync_screen()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("[GridView] _ready: size=", size, " position=", position, " visible=", visible)
	_create_cells_layer()
	_create_items_layer()
	_launcher_ctrl = LauncherControllerClass.new()
	add_child(_launcher_ctrl)
	_launcher_ctrl.spawn_started.connect(_on_launcher_spawn_started)
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

func _create_items_layer() -> void:
	var items_layer := Control.new()
	items_layer.name = "ItemsLayer"
	items_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(items_layer)

func _create_cells_layer() -> void:
	var cells_layer: Control = Control.new()
	cells_layer.name = "CellsLayer"
	cells_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cells_layer)
	for row: int in range(Constants.GRID_ROWS):
		for col: int in range(Constants.GRID_COLS):
			var cell: TextureRect = TextureRect.new()
			cell.name = "Cell_%d_%d" % [col, row]
			cell.position = Vector2(col * CELL_STEP, row * CELL_STEP)
			cell.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.texture = grid_cell_texture
			cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.stretch_mode = TextureRect.STRETCH_SCALE
			cells_layer.add_child(cell)

func _connect_signals() -> void:
	GridManager.item_added.connect(_on_item_added)
	GridManager.item_removed.connect(_on_item_removed)
	GridManager.item_moved.connect(_on_item_moved)
	GridManager.grid_updated.connect(_on_grid_updated)
	CloudService.action_batch_confirmed.connect(_on_action_batch_confirmed)
	CloudService.action_batch_rejected.connect(_on_action_batch_rejected)
	CloudService.action_batch_network_failed.connect(_on_action_batch_network_failed)
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
					_request_craft_retrieve(_pressed_item, _press_start_pos)
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
				drag_node.position = _to_local(get_viewport().get_mouse_position()) - Vector2(CELL_STEP * 0.5, CELL_STEP * 0.5)
		elif not _pressed_item.is_empty() and not _pressed_has_moved:
			if local_pos.distance_to(_press_screen_pos) > DRAG_THRESHOLD:
				_pressed_has_moved = true
				_start_drag(_press_start_pos)

func _to_local(global_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_pos

func _local_to_grid(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(local_pos.x / CELL_STEP), int(local_pos.y / CELL_STEP))


func _handle_crafting_drop(table_pos: Vector2i, table_item: Dictionary) -> void:
	var dragged_item: Dictionary = GridManager.get_item(_drag_source_pos) as Dictionary
	if dragged_item == null or dragged_item.is_empty():
		_snap_back()
		return
	var source_uid: int = dragged_item.get("_uid", 0)
	var table_uid: int = table_item.get("_uid", 0)
	var ingredient_id: int = dragged_item.get("id", 0)
	_snap_back()
	run_after_action_sync(func():
		var synced_source_pos: Vector2i = GridManager.find_pos_by_uid(source_uid)
		var synced_table_pos: Vector2i = GridManager.find_pos_by_uid(table_uid)
		if synced_source_pos.x < 0 or synced_table_pos.x < 0:
			EventBus.show_toast.emit("物品状态已变化，请重试")
			return
		var synced_dragged: Dictionary = GridManager.get_item(synced_source_pos) as Dictionary
		var synced_table: Dictionary = GridManager.get_item(synced_table_pos) as Dictionary
		_submit_crafting_drop(synced_table_pos, synced_table, synced_source_pos,
			ingredient_id, synced_dragged)
	)

func _submit_crafting_drop(table_pos: Vector2i, table_item: Dictionary,
		source_pos: Vector2i, ingredient_id: int, dragged_item: Dictionary) -> void:
	var ok: bool = _craft_ctrl.try_add_ingredient(
		table_pos, table_item, source_pos, ingredient_id, dragged_item
	)
	if not ok:
		return
	else:
		var table_key := "%d,%d" % [table_pos.x, table_pos.y]
		var table_node = _item_nodes.get(table_key)
		if table_node and is_instance_valid(table_node):
			table_node.set_crafting_state(CraftingService.TableState.HAS_ITEMS)

func _handle_launcher_click(pos: Vector2i) -> void:
	_pressed_item = {}
	var item: Dictionary = GridManager.get_item(pos) as Dictionary
	if item == null or item.is_empty():
		return

	var item_config: Dictionary = ConfigDatabase.get_item_data(item.get("id", 0) as int)
	var ok: bool = _launcher_ctrl.try_spawn(pos,
		item.get("_uid", -1) as int,
		item_config,
		item.get("charges", -1) as int,
		item.get("immovable") == true)
	if not ok:
		pass

func _spawn_error_text(reason: String) -> String:
	match reason:
		"launcher_not_found": return "生成失败：发射器不存在"
		"not_a_launcher": return "生成失败：不是发射器"
		"no_empty_cell": return "生成失败：棋盘已满"
		"insufficient_stamina": return "体力不足"
		"insufficient_qi": return "灵力不足"
		"no_charges": return "发射器次数用尽"
		"item_immovable": return "该物品无法使用"
		"request_queue_full": return "操作过于频繁，请稍后再试"
		"spawn_sequence_mismatch": return "发射状态已更新，请重试"
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
	call_deferred("_finalize_action_sync")
	if _pouch_zone and _pouch_zone.visible and Rect2(_pouch_zone.global_position, _pouch_zone.size).has_point(get_global_mouse_position()):
		if _drag_item_data.get("_pending_spawn", false) or _drag_item_data.get("_optimistic_action", false):
			_snap_back()
			return
		_do_pouch_deposit()
		return

	if not GridManager.is_valid_pos(target_pos) or not Rect2(Vector2.ZERO, size).has_point(_to_local(get_viewport().get_mouse_position())):
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
		if not _try_optimistic_merge(_drag_source_pos, target_pos):
			if target != null and target.get("immovable") == true:
				_snap_back()
			elif CloudService.online:
				_pending_push_src = _drag_source_pos
				_pending_push_target = target_pos
				CloudService.submit_push_place(_drag_source_pos.x, _drag_source_pos.y, target_pos.x, target_pos.y)
		else:
			_merge_failed_is_push = false

func _try_optimistic_merge(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	var from_item: Variant = GridManager.get_item(from_pos)
	var to_item: Variant = GridManager.get_item(to_pos)
	if from_item == null or to_item == null:
		return false
	if not MergeService.can_merge(from_item as Dictionary, to_item as Dictionary):
		return false
	var next_item: Dictionary = ConfigDatabase.get_next_level(
		from_item.get("type", 0) as int,
		from_item.get("level", 0) as int,
		from_item.get("group_id", 0) as int
	)
	if next_item.is_empty():
		return false
	var spawn_requests: Array[String] = _collect_spawn_requests(
		from_item as Dictionary, to_item as Dictionary
	)
	GridManager.remove_item(from_pos)
	GridManager.remove_item(to_pos)
	var predicted: Dictionary = next_item.duplicate(true)
	predicted["_uid"] = to_item.get("_uid", 0)
	predicted["_optimistic_action"] = true
	if not spawn_requests.is_empty():
		predicted["_spawn_request_ids"] = spawn_requests
	GridManager.add_item(predicted, to_pos)
	_queue_spawn_action({
		"type": "merge",
		"from": [from_pos.x, from_pos.y],
		"to": [to_pos.x, to_pos.y],
	}, {
		"kind": "merge",
		"target_pos": to_pos,
		"spawn_request_ids": spawn_requests,
	})
	return true

func _collect_spawn_requests(item_a: Dictionary, item_b: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	var items: Array[Dictionary] = [item_a, item_b]
	for item: Dictionary in items:
		var direct_id: String = item.get("_spawn_request_id", "")
		if not direct_id.is_empty() and not result.has(direct_id):
			result.push_back(direct_id)
		var inherited: Array = item.get("_spawn_request_ids", [])
		for value: Variant in inherited:
			var request_id: String = str(value)
			if not request_id.is_empty() and not result.has(request_id):
				result.push_back(request_id)
	return result

func _place_dragged_item(target_pos: Vector2i) -> void:
	var spawn_requests: Array[String] = _collect_spawn_requests(_drag_item_data)
	if not GridManager.move_item(_drag_source_pos, target_pos):
		_snap_back()
		return
	_queue_spawn_action({
		"type": "move",
		"from": [_drag_source_pos.x, _drag_source_pos.y],
		"to": [target_pos.x, target_pos.y],
	}, {
		"kind": "move",
		"spawn_request_ids": spawn_requests,
	})

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
	var table: Variant = GridManager.get_item(table_pos)
	if table == null:
		return
	var table_uid: int = table.get("_uid", 0)
	_show_craft_table_selection(table_pos)
	run_after_action_sync(func():
		var synced_pos: Vector2i = GridManager.find_pos_by_uid(table_uid)
		if synced_pos.x < 0:
			EventBus.show_toast.emit("制作台状态已变化，请重试")
			return
		var synced_table: Dictionary = GridManager.get_item(synced_pos) as Dictionary
		_craft_ctrl.submit_craft_start(synced_table, synced_pos)
	)

func _show_craft_table_selection(table_pos: Vector2i) -> void:
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

func _request_craft_retrieve(table_item: Dictionary, table_pos: Vector2i) -> void:
	var table_uid: int = table_item.get("_uid", 0)
	run_after_action_sync(func():
		var synced_pos: Vector2i = GridManager.find_pos_by_uid(table_uid)
		if synced_pos.x < 0:
			EventBus.show_toast.emit("制作台状态已变化，请重试")
			return
		var synced_table: Dictionary = GridManager.get_item(synced_pos) as Dictionary
		_craft_ctrl.try_retrieve(synced_table, synced_pos)
	)

func _request_item_use(item: Dictionary, pos: Vector2i) -> void:
	var uid: int = item.get("_uid", 0)
	if uid <= 0:
		return
	run_after_action_sync(func():
		var synced_pos: Vector2i = GridManager.find_pos_by_uid(uid)
		if synced_pos.x < 0:
			EventBus.show_toast.emit("物品状态已变化，请重试")
			return
		var synced_item: Dictionary = GridManager.get_item(synced_pos) as Dictionary
		item_use_requested.emit(synced_item, synced_pos)
	)

# --- End CraftingController signal handlers ---

# --- LauncherController signal handlers ---

func _on_launcher_spawn_started(prediction: Dictionary) -> void:
	var launcher_pos: Vector2i = prediction.get("launcher_pos", Vector2i(-1, -1))
	var node := _item_nodes.get("%d,%d" % [launcher_pos.x, launcher_pos.y]) as GridItem
	if node and is_instance_valid(node):
		var tween := create_tween()
		tween.tween_property(node, "scale", Vector2(0.82, 0.82), 0.08)
		tween.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)

	var predicted_id: int = prediction.get("predicted_id", 0)
	var target_pos: Vector2i = prediction.get("target_pos", Vector2i(-1, -1))
	if predicted_id <= 0 or target_pos.x < 0:
		return
	var predicted_item: Dictionary = _build_spawn_item(
		predicted_id, prediction.get("temp_uid", -1), 0, true
	)
	if predicted_item.is_empty():
		return
	predicted_item["_spawn_request_id"] = prediction.get("request_id", "")
	predicted_item["_spawn_origin"] = target_pos
	_is_launcher_spawning = true
	var added: bool = GridManager.add_item(predicted_item, target_pos)
	_is_launcher_spawning = false
	if added:
		_play_spawn_fly(target_pos, launcher_pos)

func _on_launcher_spawn_finished(result: Dictionary, prediction: Dictionary) -> void:
	_apply_spawn_resources(result)
	call_deferred("_flush_spawn_action_batch")
	call_deferred("_finalize_action_sync")
	call_deferred("_try_finish_action_sync_barrier")
	var target_pos := Vector2i(result.get("target_col", -1), result.get("target_row", -1))
	var predicted_pos: Vector2i = prediction.get("target_pos", Vector2i(-1, -1))
	var predicted_id: int = prediction.get("predicted_id", 0)
	var spawned_id: int = result.get("spawned_id", 0)
	var prediction_matches: bool = result.get("prediction_matches", true)
	prediction_matches = prediction_matches and predicted_id == spawned_id and predicted_pos == target_pos
	var request_id: String = prediction.get("request_id", "")

	var current_pos: Vector2i = _find_temp_spawn_pos(prediction.get("temp_uid", -1))

	if prediction_matches and current_pos.x >= 0 and GridManager.confirm_optimistic_item(
		current_pos,
		prediction.get("temp_uid", -1),
		result.get("spawned_uid", 0),
		result.get("atk_base", 0)
	):
		return
	if prediction_matches and _has_pending_spawn_dependency(request_id):
		return

	_rollback_spawn_prediction(prediction)
	if result.has("grid"):
		_sync_grid_from_server(result)
		return

	if not GridManager.is_empty(target_pos):
		var occupying: Variant = GridManager.get_item(target_pos)
		if occupying != null and occupying.get("_pending_spawn", false):
			GridManager.remove_item(target_pos)
		else:
			CloudService.fetch_state()
			return
	var authoritative_item: Dictionary = _build_spawn_item(
		spawned_id, result.get("spawned_uid", 0), result.get("atk_base", 0), false
	)
	if authoritative_item.is_empty():
		return
	_is_launcher_spawning = true
	var added: bool = GridManager.add_item(authoritative_item, target_pos)
	_is_launcher_spawning = false
	if added:
		_play_spawn_fly(target_pos, prediction.get("launcher_pos", Vector2i(-1, -1)))

func _on_launcher_spawn_failed(reason: String, prediction: Dictionary) -> void:
	call_deferred("_flush_spawn_action_batch")
	_action_sync_needed = false
	_rollback_spawn_prediction(prediction)
	_pending_spawn_actions.clear()
	_active_spawn_actions.clear()
	_spawn_action_batch_in_flight = false
	EventBus.show_toast.emit(_spawn_error_text(reason))
	_cancel_waiters_after_recovery = true
	_request_action_recovery_state()

func _find_temp_spawn_pos(temp_uid: int) -> Vector2i:
	for entry: Dictionary in GridManager.get_all_items():
		var item: Dictionary = entry.get("data", {})
		if item.get("_uid", 0) == temp_uid and item.get("_pending_spawn", false):
			return entry.get("pos", Vector2i(-1, -1))
	return Vector2i(-1, -1)

func _queue_spawn_action(operation: Dictionary, context: Dictionary) -> void:
	_pending_spawn_actions.push_back({"operation": operation, "context": context})
	call_deferred("_flush_spawn_action_batch")

func _has_pending_spawn_dependency(request_id: String) -> bool:
	if request_id.is_empty():
		return false
	for queued: Dictionary in _pending_spawn_actions:
		var context: Dictionary = queued.get("context", {})
		if (context.get("spawn_request_ids", []) as Array).has(request_id):
			return true
	for context: Dictionary in _active_spawn_actions:
		if (context.get("spawn_request_ids", []) as Array).has(request_id):
			return true
	return false

func _flush_spawn_action_batch() -> void:
	if _spawn_action_batch_in_flight or _pending_spawn_actions.is_empty():
		return
	if _launcher_ctrl != null and _launcher_ctrl.is_spawn_in_flight():
		return
	var operations: Array[Dictionary] = []
	_active_spawn_actions.clear()
	var batch_size: int = mini(32, _pending_spawn_actions.size())
	for _index in range(batch_size):
		var queued: Dictionary = _pending_spawn_actions.pop_front()
		operations.push_back(queued.get("operation", {}))
		_active_spawn_actions.push_back(queued.get("context", {}))
	_spawn_action_batch_in_flight = true
	CloudService.submit_action_batch(operations)

func _on_action_batch_confirmed(result: Dictionary) -> void:
	_active_spawn_actions.clear()
	_spawn_action_batch_in_flight = false
	_apply_spawn_resources(result)
	if result.has("crafted_item_ids"):
		var crafted_item_ids: Array = result.get("crafted_item_ids", [])
		GameState.set_crafted_item_ids(crafted_item_ids)
	if _pending_spawn_actions.is_empty() and not _launcher_ctrl.is_spawn_in_flight() and not _is_dragging:
		_action_sync_needed = false
		var server_grid: Array = result.get("grid", [])
		if not GridManager.reconcile_from_server(server_grid):
			var batch_results: Array = result.get("results", [])
			GridManager.confirm_action_batch_results(batch_results)
			push_warning("[GridView] Successful action batch snapshot did not match the optimistic board; kept local nodes")
		_try_finish_action_sync_barrier()
	else:
		_action_sync_needed = true
		_flush_spawn_action_batch()

func _on_action_batch_rejected(reason: String, result: Dictionary) -> void:
	_active_spawn_actions.clear()
	_pending_spawn_actions.clear()
	_spawn_action_batch_in_flight = false
	_action_sync_needed = false
	EventBus.show_toast.emit("操作同步失败：" + reason)
	if result.has("grid"):
		_sync_grid_from_server(result)
		_cancel_action_sync_waiters("棋盘状态已刷新，请重试")
	else:
		_cancel_waiters_after_recovery = true
		_request_action_recovery_state()

func _on_action_batch_network_failed(reason: String) -> void:
	_active_spawn_actions.clear()
	_pending_spawn_actions.clear()
	_spawn_action_batch_in_flight = false
	_action_sync_needed = false
	EventBus.show_toast.emit("操作同步失败：" + reason)
	_cancel_waiters_after_recovery = true
	_request_action_recovery_state()

func _request_action_recovery_state() -> void:
	if _action_recovery_in_flight:
		return
	_action_recovery_in_flight = true
	if not CloudService.state_loaded.is_connected(_on_action_recovery_state_loaded):
		CloudService.state_loaded.connect(_on_action_recovery_state_loaded, CONNECT_ONE_SHOT)
	if not CloudService.state_load_failed.is_connected(_on_action_recovery_state_failed):
		CloudService.state_load_failed.connect(_on_action_recovery_state_failed, CONNECT_ONE_SHOT)
	CloudService.fetch_state()

func _on_action_recovery_state_loaded(state: Dictionary) -> void:
	_action_recovery_in_flight = false
	if CloudService.state_load_failed.is_connected(_on_action_recovery_state_failed):
		CloudService.state_load_failed.disconnect(_on_action_recovery_state_failed)
	_sync_grid_from_server(state)
	if _cancel_waiters_after_recovery:
		_cancel_waiters_after_recovery = false
		_cancel_action_sync_waiters("棋盘状态已刷新，请重试")
	else:
		_try_finish_action_sync_barrier()

func _on_action_recovery_state_failed(_reason: String) -> void:
	_action_recovery_in_flight = false
	if CloudService.state_loaded.is_connected(_on_action_recovery_state_loaded):
		CloudService.state_loaded.disconnect(_on_action_recovery_state_loaded)
	_cancel_waiters_after_recovery = false
	_action_sync_needed = false
	_cancel_action_sync_waiters("棋盘同步失败，请检查网络后重试")

func _finalize_action_sync() -> void:
	if not _action_sync_needed or _spawn_action_batch_in_flight:
		return
	if not _pending_spawn_actions.is_empty() or _launcher_ctrl.is_spawn_in_flight():
		return
	_action_sync_needed = false
	_request_action_recovery_state()

func _build_spawn_item(item_id: int, uid: int, atk_base: int, pending: bool) -> Dictionary:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		return {}
	var item: Dictionary = item_data.duplicate(true)
	item["_uid"] = uid
	if pending:
		item["_pending_spawn"] = true
	if Constants.has_launcher_config(item):
		item["charges"] = item.get("max_charges", 3)
	if atk_base > 0:
		item["atk_base"] = atk_base
	return item

func _rollback_spawn_prediction(prediction: Dictionary) -> void:
	if prediction.is_empty():
		return
	var target_pos: Vector2i = _find_temp_spawn_pos(prediction.get("temp_uid", -1))
	if not GridManager.is_valid_pos(target_pos) or GridManager.is_empty(target_pos):
		return
	var item: Variant = GridManager.get_item(target_pos)
	if item != null and item.get("_uid", 0) == prediction.get("temp_uid", -1):
		GridManager.remove_item(target_pos)

func _apply_spawn_resources(result: Dictionary) -> void:
	var regen_ms: float = result.get("regen_remaining_ms", 0.0)
	if regen_ms > 0:
		GameState.regen_remaining_ms = regen_ms
	var stamina: Variant = result.get("stamina", null)
	if stamina != null:
		GameState.stamina = stamina
		GameState.max_stamina = result.get("max_stamina", GameState.max_stamina)
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	var cultivation: Variant = result.get("cultivation", null)
	if cultivation is Dictionary:
		CultivationService.deserialize(cultivation)

func _play_spawn_fly(target_pos: Vector2i, launcher_pos: Vector2i) -> void:
	var fly_node := _item_nodes.get("%d,%d" % [target_pos.x, target_pos.y]) as GridItem
	if not fly_node or not is_instance_valid(fly_node) or launcher_pos.x < 0:
		return
	fly_node.position = Vector2(launcher_pos.x * CELL_STEP, launcher_pos.y * CELL_STEP)
	fly_node.scale = Vector2(0.7, 0.7)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_node, "position", Vector2(target_pos.x * CELL_STEP, target_pos.y * CELL_STEP), 0.35).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(fly_node, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BOUNCE)

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
			if item.get("_pending_spawn", false) or item.get("_optimistic_action", false):
				return
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
				_request_item_use(item as Dictionary, pos)
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
	_skip_anims = true
	GridManager.init_grid(GameState.current_board_type)
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			if entry.has("uid"): item["_uid"] = entry.uid
			if entry.has("immovable"): item["immovable"] = entry.immovable
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	_skip_anims = false

func _deselect_all() -> void:
	if not _selected_key.is_empty():
		var node := _item_nodes.get(_selected_key) as GridItem
		if node and is_instance_valid(node):
			node.set_selected(false)
		_selected_key = ""
