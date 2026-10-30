class_name SecretRealmPanel extends BasePopup

signal action_requested(body: Dictionary)

const Cell = preload("res://scenes/ui/activity/SecretRealmCell.gd")
const DragController := preload("res://scenes/grid/BoardDragController.gd")
const RealmEffects := preload("res://scenes/ui/activity/SecretRealmEffects.gd")
const CONFIRM_SCENE := preload("res://scenes/ui/common/ConfirmPopup.tscn")
const STASH_FLY_DURATION: float = 0.35
var _view: Dictionary = {}
var _defs: Dictionary = {}
var _selection: Dictionary = {}
var _closing: bool = false
var _scroll_tween: Tween
var _board_layer: Control
var _outgoing: Control
var _board: Control
var _title: Label
var _status: Label
var _detail: Label
var _stash_title: Label
var _stash: HBoxContainer
var _cell_size: float = 80.0
var _presenting_drop: bool = false
var _drop_animation: Tween
var _deferred_view: Dictionary = {}
var _drag_gesture := DragController.new()
var _pressed_cell: Control
var _pressed_selected_uid: int = 0
var _drag_source: Control
var _drag_payload: Dictionary = {}
var _drag_layer: Control
var _pending_merge: Dictionary = {}
var _loss_popup: ConfirmPopup
var _stash_pending: Array[Dictionary] = []
var _stash_sending_uid: int = 0
var _reward_effects: Control
var _effect_request_id: String = ""
var _effect_view: Dictionary = {}
var _merge_drag_open: bool = false
var _merge_locked_cells: Array[Vector2i] = []
var _queued_drops: Array[Dictionary] = []


func _ready() -> void:
	close_on_click_outside = false
	_build_ui()
	CloudService.secret_realm_updated.connect(_on_view)
	CloudService.secret_realm_failed.connect(_on_failed)
	CloudService.secret_realm_preview_loaded.connect(_on_merge_preview)
	resized.connect(_layout_board)
	if not CloudService.secret_realm_state.is_empty():
		_on_view(CloudService.secret_realm_state)


func setup(_activity_id: int = 9, request_state: bool = true) -> void:
	if request_state:
		CloudService.fetch_secret_realm()


func _label(text: String, font_size: int, color: Color = Color("d3ded2")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(100, 48)
	button.add_theme_font_size_override("font_size", 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("274b48")
	style.border_color = Color("617d66")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	button.add_theme_stylebox_override("normal", style)
	button.pressed.connect(callback)
	return button


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.65)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ContentPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c181e")
	style.border_color = Color("36524f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _label("剑墟秘境", 34, Color("e4cb8c"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_button("返回", _close))
	column.add_child(_label("合剑探雾，向剑墟深处进发", 20, Color("86aaa0")))
	_status = _label("正在读取秘境…", 20)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_board = Control.new()
	_board.name = "BoardViewport"
	_board.clip_contents = true
	_board.custom_minimum_size = Vector2(6 * Constants.CELL_STEP - Constants.CELL_GAP, 8 * Constants.CELL_STEP - Constants.CELL_GAP) * Constants.BOARD_DISPLAY_SCALE
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.mouse_force_pass_scroll_events = false
	_board.gui_input.connect(_block_map_input)
	_board.resized.connect(_layout_board)
	column.add_child(_board)
	_detail = _label("拖动相同物品合成，揭开产物上下左右的迷雾。", 18)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.y = 68
	column.add_child(_detail)
	var stash_header := HBoxContainer.new()
	column.add_child(stash_header)
	_stash_title = _label("秘境暂存 · 0", 22, Color("e4cb8c"))
	_stash_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stash_header.add_child(_stash_title)
	_stash = HBoxContainer.new()
	_stash.custom_minimum_size.y = Constants.CELL_SIZE * Constants.BOARD_DISPLAY_SCALE
	_stash.alignment = BoxContainer.ALIGNMENT_CENTER
	_stash.add_theme_constant_override("separation", 12)
	column.add_child(_stash)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var note: Label = _label("主棋盘订单获补给；点击暂存物品飞入棋盘空位。", 17, Color("86aaa0"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(note)
	_drag_layer = Control.new()
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_layer.scale = Vector2.ONE * Constants.BOARD_DISPLAY_SCALE
	add_child(_drag_layer)


# Uses the main board's gesture controller and the real GridItem, including the
# same logical threshold, mouse offset and snap-back. Only cell lookup differs.
func _input(event: InputEvent) -> void:
	if not UIManager._active_popups.is_empty() and UIManager._active_popups.back() != self:
		return
	var board_ready: bool = _can_drag_board()
	if not board_ready and not _can_click_stash():
		_cancel_drag()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed_selected_uid = 0
			_pressed_cell = _cell_at(event.position)
			if is_instance_valid(_pressed_cell) and not board_ready and not _pressed_cell.from_stash:
				_pressed_cell = null
			if is_instance_valid(_pressed_cell):
				if not _pressed_cell.from_stash and not _selection.get("stash", false):
					_pressed_selected_uid = int(_selection.get("item", {}).get("uid", 0))
				_select(_pressed_cell.data, _pressed_cell.from_stash)
				if _pressed_cell.from_stash or not _pressed_cell.get_drag_payload().is_empty():
					_drag_gesture.press(_drag_local(event.position))
			return
		var released: int = _drag_gesture.release(is_instance_valid(_drag_source))
		if released == DragController.Release.DROP:
			var target: Control = _cell_at(event.position)
			var accepted: bool = is_instance_valid(target) and target.can_accept(_drag_payload)
			var payload: Dictionary = _drag_payload
			_drag_source.end_drag(not accepted)
			_drag_source = null
			_drag_payload = {}
			_pressed_cell = null
			if accepted:
				target.accept_drop(payload)
		elif released == DragController.Release.CLICK and is_instance_valid(_pressed_cell) and _cell_at(event.position) == _pressed_cell:
			if _pressed_cell.from_stash:
				_place_stash(_pressed_cell)
			elif _pressed_selected_uid != 0 and _pressed_selected_uid == int(_pressed_cell.data.get("item", {}).get("uid", 0)):
				_use_selected()
		_pressed_cell = null
		_pressed_selected_uid = 0
		_drain_queued_drops.call_deferred()
	elif event is InputEventMouseMotion:
		var motion: int = _drag_gesture.motion(_drag_local(event.position), is_instance_valid(_drag_source))
		if motion == DragController.Motion.START and is_instance_valid(_pressed_cell):
			_drag_payload = _pressed_cell.get_drag_payload()
			if not _drag_payload.is_empty():
				_drag_source = _pressed_cell
				_drag_source.begin_drag(_drag_layer)
		elif motion == DragController.Motion.FOLLOW:
			DragController.follow(_drag_source.item_visual, _drag_local(event.position), Constants.CELL_STEP)


func _drag_local(pointer: Vector2) -> Vector2:
	return _drag_layer.get_global_transform_with_canvas().affine_inverse() * pointer


func _cell_at(pointer: Vector2) -> Control:
	for cell: Control in _all_cells():
		if cell.from_stash and not cell.data.get("item", {}).is_empty() and cell.is_visible_in_tree() and cell.get_global_rect().has_point(pointer):
			return cell
	if not _board.get_global_rect().has_point(pointer):
		return null
	var local: Vector2 = _board_layer.get_global_transform_with_canvas().affine_inverse() * pointer
	if not Rect2(Vector2.ZERO, _board_layer.size).has_point(local):
		return null
	# Main board assigns the small inter-cell gap to the preceding cell step.
	var col: int = floori(local.x / Constants.CELL_STEP)
	var row: int = int(_view.get("start_row", 0)) + 7 - floori(local.y / Constants.CELL_STEP)
	for cell: Control in _board_layer.get_children():
		if int(cell.data.col) == col and int(cell.data.row) == row:
			return cell
	return null


func _next_definition(item: Dictionary) -> Dictionary:
	for candidate: Dictionary in _defs.values():
		if candidate.get("chain", "") == item.get("group_id", "") and int(candidate.get("level", 0)) == int(item.get("level", 0)) + 1:
			return candidate
	return {}


func _block_map_input(event: InputEvent) -> void:
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventPanGesture:
		_board.accept_event()


func _can_interact() -> bool:
	if CloudService.relogin_pending:
		return false
	return _stash_pending.is_empty() and not _closing and not is_instance_valid(_reward_effects) and _pending_merge.is_empty() and not is_instance_valid(_loss_popup) and not _is_scrolling() and not _is_drop_animating() and not CloudService.secret_realm_busy and CloudService.secret_realm_retry.is_empty() and bool(_view.get("available", false)) and bool(_view.get("initialized", false))


func _can_drag_board() -> bool:
	if CloudService.relogin_pending:
		return false
	return _can_interact() or (_merge_drag_open and not _closing and _stash_pending.is_empty() and not is_instance_valid(_loss_popup) and not _is_scrolling() and bool(_view.get("available", false)) and bool(_view.get("initialized", false)))


func _can_drag_cell(data: Dictionary) -> bool:
	if not _can_drag_board():
		return false
	var pos: Vector2i = Vector2i(int(data.get("col", -1)), int(data.get("row", -1)))
	if pos in _merge_locked_cells:
		return false
	var uid: int = int(data.get("item", {}).get("uid", 0))
	for queued: Dictionary in _queued_drops:
		if uid == int(queued.uid) or pos == Vector2i(int(queued.col), int(queued.row)) or pos == queued.source:
			return false
	return true


func _lock_merge(uid: int, col: int, row: int) -> void:
	_merge_drag_open = true
	_merge_locked_cells = [Vector2i(col, row)]
	for cell: Control in _board_layer.get_children():
		if int(cell.data.get("item", {}).get("uid", 0)) == uid:
			_merge_locked_cells.append(Vector2i(int(cell.data.col), int(cell.data.row)))
			break


func _drain_queued_drops() -> void:
	if not _can_interact() or _merge_drag_open or _queued_drops.is_empty() or is_instance_valid(_drag_source):
		return
	var queued: Dictionary = _queued_drops.pop_front()
	var source: Control
	for cell: Control in _board_layer.get_children():
		if int(cell.data.get("item", {}).get("uid", 0)) == int(queued.uid):
			source = cell
			break
	var target: Control = _find_board_cell(int(queued.col), int(queued.row))
	if is_instance_valid(source) and is_instance_valid(target) and int(target.data.get("item", {}).get("uid", 0)) == int(queued.target_uid) and target.can_accept(source.get_drag_payload()):
		_execute_drop(int(queued.uid), int(queued.col), int(queued.row))
	_drain_queued_drops.call_deferred()


func _can_click_stash() -> bool:
	if CloudService.relogin_pending:
		return false
	var own_request: bool = _stash_sending_uid != 0
	return _queued_drops.is_empty() and not _merge_drag_open and not _closing and not is_instance_valid(_reward_effects) and _pending_merge.is_empty() and not is_instance_valid(_loss_popup) and not _is_scrolling() and not _is_drop_animating() and (own_request or (not CloudService.secret_realm_busy and CloudService.secret_realm_retry.is_empty())) and bool(_view.get("available", false)) and bool(_view.get("initialized", false))


func _is_drop_animating() -> bool:
	return _drop_animation != null and _drop_animation.is_valid() and _drop_animation.is_running()


func _is_scrolling() -> bool:
	return _scroll_tween != null and _scroll_tween.is_valid() and _scroll_tween.is_running()


func _on_view(data: Dictionary) -> void:
	if _closing:
		return
	if not _view.is_empty() and (data.get("period", "") != _view.get("period", "") or data.get("start_row", 0) != _view.get("start_row", 0)):
		_queued_drops.clear()
		_merge_drag_open = false
		_merge_locked_cells.clear()
		_cancel_drag()
	if not _stash_pending.is_empty() and (data.get("period", "") != _view.get("period", "") or data.get("start_row", 0) != _view.get("start_row", 0)):
		_clear_stash_flights()
	if is_instance_valid(_reward_effects):
		_effect_view = data.duplicate(true)
		return
	if _is_drop_animating():
		_deferred_view = data.duplicate(true)
		return
	if _play_confirmed_effects(data):
		return
	if int(data.get("version", -1)) > int(_view.get("version", -1)):
		_merge_drag_open = false
		_merge_locked_cells.clear()
	var changed: bool = _view.is_empty() or data.get("version", -1) != _view.get("version", -1) or data.get("period", "") != _view.get("period", "") or data.get("initialized", false) != _view.get("initialized", false)
	var old_start: int = int(_view.get("start_row", 0))
	var old_period: String = str(_view.get("period", ""))
	var previous_selection: Dictionary = _selection.duplicate(true)
	_view = data.duplicate(true)
	_defs.clear()
	for item: Dictionary in _view.get("items", []):
		_defs[str(item.get("id", ""))] = item
	_title.text = "剑墟秘境 · " + str(_view.get("stage_name", "待开启"))
	_status.text = "秘境已通关！剩余奖励可继续合成、使用。" if bool(_view.get("completed", false)) else "第 %d 境 · 合成探索，收集飞剑与满级剑气挑战首领" % (int(_view.get("stage", 0)) + 1)
	if not bool(_view.get("available", false)):
		_status.text = "秘境暂未开放，练气一层后可参与。"
	if changed:
		_clear_merge_preview()
		_selection.clear()
		_detail.text = "拖动相同物品合成，揭开产物上下左右的迷雾。"
		var distance: int = int(_view.get("start_row", 0)) - old_start
		_render_board(distance if old_period == str(_view.get("period", "")) else 0)
		_render_stash()
	if changed and old_period == str(_view.get("period", "")) and previous_selection.has("enemy"):
		for cell: Control in _board_layer.get_children():
			if cell.data.get("col", -1) == previous_selection.get("col", -2) and cell.data.get("row", -1) == previous_selection.get("row", -2) and cell.data.has("enemy"):
				_select(cell.data, false, true)
				break
	_sync_stash_flights()
	_send_next_stash.call_deferred()
	_drain_queued_drops.call_deferred()


func _make_cell(data: Dictionary, stash: bool = false) -> Control:
	var cell := Cell.new()
	var item: Dictionary = data.get("item", {})
	var definition: Dictionary = _defs.get(str(item.get("id", "")), {})
	cell.set_meta("viewport_top_row", int(_view.get("start_row", 0)) + 7)
	cell.setup(data, definition, _can_click_stash if stash else _can_drag_cell.bind(data), stash, _next_definition, _can_submit_to_monster, _defs)
	cell.dropped.connect(_drop)
	return cell


func _find_board_cell(col: int, row: int) -> Control:
	for cell: Control in _board_layer.get_children():
		if int(cell.data.get("col", -1)) == col and int(cell.data.get("row", -1)) == row:
			return cell
	return null


func _play_confirmed_effects(data: Dictionary) -> bool:
	if _effect_request_id.is_empty() or int(data.get("version", -1)) <= int(_view.get("version", -1)):
		return false
	var effects: Dictionary = data.get("_effects", {})
	var matches: bool = effects.get("request_id", "") == _effect_request_id and data.get("period", "") == _view.get("period", "")
	_effect_request_id = ""
	if not matches:
		return false
	var col: int = int(effects.get("col", -1))
	var row: int = int(effects.get("row", -1))
	var monster: Control = _find_board_cell(col, row) if effects.get("defeated", false) else null
	if is_instance_valid(monster) and not monster.data.get("enemy", {}).is_empty():
		monster.show_submissions(effects.get("submitted", {}))
	else:
		monster = null
	var drops: Array = effects.get("drops", []).duplicate(true)
	if not is_instance_valid(monster) and drops.is_empty():
		return false
	if effects.get("kind", "") == "merge":
		_merge_drag_open = true
		_merge_locked_cells.append(Vector2i(col, row))
		for drop: Dictionary in drops:
			if not drop.get("stash", false):
				_merge_locked_cells.append(Vector2i(int(drop.col), int(drop.row)))
	_reward_effects = RealmEffects.new()
	_reward_effects.name = "ConfirmedRealmEffects"
	_drag_layer.add_child(_reward_effects)
	_reward_effects.position = _drag_local(_board_layer.global_position)
	var stash_target: Vector2 = _reward_effects.get_global_transform_with_canvas().affine_inverse() * _stash_title.get_global_rect().get_center() - Vector2.ONE * Constants.CELL_SIZE * 0.5
	for drop: Dictionary in drops:
		if drop.get("stash", false):
			drop.destination = stash_target
		else:
			drop.destination = Vector2(int(drop.col), 7 - (int(drop.row) - int(_view.get("start_row", 0)))) * Constants.CELL_STEP
			drop.cell = _find_board_cell(int(drop.col), int(drop.row))
	var origin: Vector2 = Vector2(col, 7 - (row - int(_view.get("start_row", 0)))) * Constants.CELL_STEP + Vector2.ONE * Constants.CELL_SIZE * 0.5
	_effect_view = data.duplicate(true)
	_reward_effects.finished.connect(_on_reward_effects_finished)
	_reward_effects.play(monster, drops, _defs, origin)
	return true


func _on_reward_effects_finished() -> void:
	var latest: Dictionary = _effect_view
	_clear_reward_effects()
	if not latest.is_empty():
		_on_view(latest)


func _clear_reward_effects() -> void:
	if is_instance_valid(_reward_effects):
		_reward_effects.cancel()
		_reward_effects.queue_free()
	_reward_effects = null
	_effect_view = {}


func _render_board(distance: int = 0) -> void:
	var drag_uid: int = int(_drag_payload.get("uid", 0)) if distance == 0 and is_instance_valid(_drag_source) else 0
	var drag_position: Vector2 = _drag_source.item_visual.position if drag_uid != 0 else Vector2.ZERO
	var pressed_uid: int = int(_pressed_cell.data.get("item", {}).get("uid", 0)) if distance == 0 and is_instance_valid(_pressed_cell) and not _pressed_cell.from_stash else 0
	if drag_uid != 0:
		_drag_source.end_drag()
		_drag_source = null
	elif pressed_uid == 0 and (not is_instance_valid(_pressed_cell) or not _pressed_cell.from_stash):
		_cancel_drag()
	_finish_drop_animation()
	_presenting_drop = false
	_finish_scroll()
	var previous: Control = _board_layer
	_board_layer = Control.new()
	_board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_board_layer)
	for data: Dictionary in _view.get("cells", []):
		_board_layer.add_child(_make_cell(data))
	_layout_board()
	if drag_uid != 0 or pressed_uid != 0:
		var restored: bool = false
		for cell: Control in _board_layer.get_children():
			if int(cell.data.get("item", {}).get("uid", 0)) == (drag_uid if drag_uid != 0 else pressed_uid) and not cell.get_drag_payload().is_empty():
				_pressed_cell = cell
				if drag_uid != 0:
					_drag_source = cell
					cell.begin_drag(_drag_layer)
					cell.item_visual.position = drag_position
				restored = true
				break
		if not restored:
			_cancel_drag()
	if is_instance_valid(previous):
		if distance > 0 and distance < 8:
			_outgoing = previous
			# Overlapping rows are already represented by the new board. Only
			# cells actually leaving the viewport belong to the outgoing layer.
			var start_row: int = int(_view.get("start_row", 0))
			for cell: Control in previous.get_children():
				var row: int = int(cell.data.get("row", -1))
				cell.visible = row < start_row or row >= start_row + 8
			_board_layer.position.y -= distance * _cell_size
			_scroll_tween = create_tween().set_parallel(true)
			_scroll_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			_scroll_tween.tween_property(_board_layer, "position:y", _board_layer.position.y + distance * _cell_size, 0.6)
			_scroll_tween.tween_property(previous, "position:y", previous.position.y + distance * _cell_size, 0.6)
			_scroll_tween.finished.connect(_on_scroll_finished)
		else:
			previous.queue_free()


func _layout_board() -> void:
	if not is_instance_valid(_board_layer):
		return
	if _is_scrolling():
		_finish_scroll()
	_cell_size = Constants.CELL_STEP * Constants.BOARD_DISPLAY_SCALE
	_board_layer.scale = Vector2.ONE * Constants.BOARD_DISPLAY_SCALE
	_board_layer.size = Vector2(6 * Constants.CELL_STEP - Constants.CELL_GAP, 8 * Constants.CELL_STEP - Constants.CELL_GAP)
	_board_layer.position = (_board.size - _board_layer.size * Constants.BOARD_DISPLAY_SCALE) * 0.5
	for cell: Control in _board_layer.get_children():
		var x: int = int(cell.data.get("col", 0))
		var y: int = 7 - (int(cell.data.get("row", 0)) - int(_view.get("start_row", 0)))
		cell.position = Vector2(x, y) * Constants.CELL_STEP
		cell.size = Vector2.ONE * Constants.CELL_SIZE


func _finish_scroll() -> void:
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = null
	if is_instance_valid(_outgoing):
		_outgoing.queue_free()
	_outgoing = null


func _on_scroll_finished() -> void:
	_finish_scroll()


func _render_stash() -> void:
	var pressed_uid: int = int(_pressed_cell.data.get("item", {}).get("uid", 0)) if is_instance_valid(_pressed_cell) and _pressed_cell.from_stash else 0
	for child: Node in _stash.get_children():
		_stash.remove_child(child)
		child.queue_free()
	var groups: Array = [[], [], [], []]
	var count: int = 0
	for item: Dictionary in _view.get("stash", []):
		if not _stash_has_uid(int(item.uid)):
			groups[_stash_group(item)].append(item)
			count += 1
	_stash_title.text = "秘境暂存 · %d　点击投放，可连续点击" % count
	var restored: bool = false
	var titles: Array[String] = ["1级飞剑", "2级飞剑", "3级飞剑", "其他物品"]
	for group: int in range(4):
		var items: Array = groups[group]
		var slot := Control.new()
		var cell_size: float = Constants.CELL_SIZE * Constants.BOARD_DISPLAY_SCALE
		slot.custom_minimum_size = Vector2(120, cell_size + 30)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stash.add_child(slot)
		var cell: Control = _make_cell({"item": items[0]} if not items.is_empty() else {}, true)
		cell.scale = Vector2.ONE * Constants.BOARD_DISPLAY_SCALE
		cell.position.x = (slot.custom_minimum_size.x - cell_size) * 0.5
		slot.add_child(cell)
		if items.is_empty():
			cell.modulate.a = 0.4
			cell.tooltip_text = titles[group] + "：暂无物品"
		elif group == 3:
			cell.tooltip_text += "\n4级及以上飞剑、剑气、体力和灵石"
		var label: Label = _label("%s · %d" % [titles[group], items.size()], 17, Color("86aaa0"))
		label.position.y = cell_size + 5
		label.size.x = slot.custom_minimum_size.x
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(label)
		if pressed_uid != 0 and not items.is_empty() and int(items[0].uid) == pressed_uid:
			_pressed_cell = cell
			restored = true
	if pressed_uid != 0 and not restored:
		_cancel_drag()


func _stash_group(item: Dictionary) -> int:
	var definition: Dictionary = _defs.get(str(item.get("id", "")), {})
	var level: int = int(definition.get("level", 0))
	return level - 1 if definition.get("chain", "") == "sword" and level >= 1 and level <= 3 else 3


func _select(data: Dictionary, stash: bool, restore: bool = false) -> void:
	if not restore and not _can_interact():
		return
	_selection = data.duplicate(true)
	_selection["stash"] = stash
	for cell: Control in _all_cells():
		cell.set_selected(cell.data == data)
	var item: Dictionary = data.get("item", {})
	var def: Dictionary = _defs.get(str(item.get("id", "")), {})
	var enemy: Dictionary = data.get("enemy", {})
	if data.get("fog", false):
		if data.get("special_fog", false):
			_detail.text = "特殊迷雾：击败本关全部小怪后，Boss 周围九格一起解锁。\n本关剩余小怪 %d 只（含迷雾中的小怪）。" % int(_view.get("remaining_mobs", 0))
		else:
			_detail.text = "迷雾：在它上下左右的格子完成合成，可显露预置内容。"
	elif not enemy.is_empty():
		var requirements: PackedStringArray = []
		var inventory: Dictionary = _view.get("inventory", {})
		var submitted: Dictionary = data.get("submitted", {})
		for cost: Dictionary in enemy.get("costs", []):
			var id: String = str(cost.get("id", ""))
			var cost_def: Dictionary = _defs.get(id, {})
			requirements.append("%s %d/%d（持有%d）" % [cost_def.get("name", id), submitted.get(id, 0), cost.get("count", 0), inventory.get(id, 0)])
		_detail.text = str(enemy.get("name", "")) + "　已提交：" + "，".join(requirements) + "\n将所需飞剑、剑气逐件拖到怪物格，凑齐后自动击败。"
		if enemy.get("boss", false):
			var remaining: int = int(_view.get("remaining_mobs", 0))
			_detail.text += "\n本关剩余小怪 %d 只（含迷雾中小怪），全部击败后可挑战 Boss。" % remaining if remaining > 0 else "\n本关小怪已全部击败，可挑战 Boss。"
	elif not item.is_empty():
		_detail.text = str(def.get("name", ""))
		if stash:
			_detail.text += " · 点击后飞入棋盘空位。" + ("放入后保持固定，合成后解锁。" if item.get("immovable", false) else "")
		elif item.get("immovable", false):
			_detail.text += " · 固定物品，拖入相同等级物品合成后解锁。"
		elif str(def.get("chain", "")) in ["stamina", "stone"]:
			if int(def.get("level", 0)) < 2:
				_detail.text += " · 合成到 2 级后可使用。"
			else:
				_detail.text += " · 再次点击使用，获得 %d %s。" % [def.get("value", 0), "体力" if def.get("chain", "") == "stamina" else "灵石"]
		else:
			_detail.text += " · 拖至同级物品合成。"
	else:
		_detail.text = "已揭雾空位：可放入暂存物品。"


func _drop(uid: int, col: int, row: int, stash: bool) -> void:
	if stash or not _can_drag_board():
		return
	if not _can_interact() or _merge_drag_open or not _queued_drops.is_empty():
		var target: Control = _find_board_cell(col, row)
		for source: Control in _board_layer.get_children():
			if int(source.data.get("item", {}).get("uid", 0)) == uid and is_instance_valid(target) and target.can_accept(source.get_drag_payload()):
				_queued_drops.append({"uid": uid, "col": col, "row": row, "target_uid": int(target.data.get("item", {}).get("uid", 0)), "source": Vector2i(int(source.data.col), int(source.data.row))})
				_drain_queued_drops.call_deferred()
				return
		return
	_execute_drop(uid, col, row)


func _execute_drop(uid: int, col: int, row: int) -> void:
	var action: String = "move"
	var extra: Dictionary = {"uid": uid, "col": col, "row": row}
	for cell: Control in _all_cells():
		if not cell.from_stash and int(cell.data.get("col", -1)) == col and int(cell.data.get("row", -1)) == row and cell.data.has("enemy"):
			var payload: Dictionary = {}
			for source: Control in _board_layer.get_children():
				if int(source.data.get("item", {}).get("uid", 0)) == uid:
					payload = source.get_drag_payload()
			if _can_submit_to_monster(cell.data, payload):
				_select(cell.data, false)
				_submit("fight", extra)
			return
		if not cell.from_stash and int(cell.data.get("col", -1)) == col and int(cell.data.get("row", -1)) == row and not cell.data.get("item", {}).is_empty():
			for source: Control in _board_layer.get_children():
				if int(source.data.get("item", {}).get("uid", 0)) == uid and not MergeService.can_merge(source.merge_data(), cell.merge_data(), _next_definition):
					_submit("move", extra)
					return
			_lock_merge(uid, col, row)
			_pending_merge = _action_body(action, extra)
			_status.text = "正在检查合成奖励空间…"
			CloudService.preview_secret_realm_merge(_pending_merge)
			return
	_submit(action, extra)


func _can_submit_to_monster(data: Dictionary, payload: Dictionary) -> bool:
	if not _can_interact() or payload.is_empty() or payload.get("stash", false) or payload.get("immovable", false) or data.get("fog", false):
		return false
	var enemy: Dictionary = data.get("enemy", {})
	if enemy.get("boss", false) and int(_view.get("remaining_mobs", 0)) > 0:
		return false
	var submitted: Dictionary = data.get("submitted", {})
	for cost: Dictionary in enemy.get("costs", []):
		var id: String = str(cost.get("id", ""))
		if id == payload.get("id", "") and int(submitted.get(id, 0)) < int(cost.get("count", 0)):
			return true
	return false


func _place_stash(source: Control) -> void:
	if not _can_click_stash() or not is_instance_valid(source) or not source.from_stash:
		return
	var item: Dictionary = source.data.get("item", {})
	if item.is_empty() or _stash_has_uid(int(item.uid)):
		return
	for cell: Control in _board_layer.get_children():
		if not _stash_slot_reserved(int(cell.data.col), int(cell.data.row)) and not cell.data.get("fog", false) and cell.data.get("item", {}).is_empty() and cell.data.get("enemy", {}).is_empty() and str(cell.data.get("monster", "")).is_empty():
			var visual: GridItem = source.create_item_visual(item, source.definition)
			visual.reparent(_drag_layer)
			visual.position = _drag_local(source.item_visual.global_position)
			visual.z_index = 100
			var flight: Dictionary = {"item": item.duplicate(true), "col": cell.data.col, "row": cell.data.row, "visual": visual, "landed": false, "confirmed": false}
			_stash_pending.append(flight)
			var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			flight.tween = tween
			tween.tween_property(visual, "position", _drag_local(cell.global_position), STASH_FLY_DURATION)
			tween.finished.connect(_on_stash_landed.bind(int(item.uid)))
			_render_stash()
			_send_next_stash()
			return
	_status.text = "棋盘没有已揭雾空位，请先合成或使用物品腾出空位。"


func _stash_has_uid(uid: int) -> bool:
	return _stash_pending.any(func(flight: Dictionary) -> bool: return int(flight.item.uid) == uid)


func _stash_slot_reserved(col: int, row: int) -> bool:
	return _stash_pending.any(func(flight: Dictionary) -> bool: return int(flight.col) == col and int(flight.row) == row)


func _send_next_stash() -> void:
	if _closing or _stash_sending_uid != 0 or CloudService.secret_realm_busy or not CloudService.secret_realm_retry.is_empty():
		return
	for flight: Dictionary in _stash_pending:
		if flight.confirmed:
			continue
		_stash_sending_uid = int(flight.item.uid)
		var body: Dictionary = _action_body("place", {"uid": _stash_sending_uid, "col": flight.col, "row": flight.row})
		action_requested.emit(body)
		CloudService.submit_secret_realm(body)
		return


func _on_stash_landed(uid: int) -> void:
	for flight: Dictionary in _stash_pending:
		if int(flight.item.uid) == uid:
			flight.landed = true
			break
	_sync_stash_flights()


func _sync_stash_flights() -> void:
	for index: int in range(_stash_pending.size() - 1, -1, -1):
		var flight: Dictionary = _stash_pending[index]
		var target: Control = _find_board_cell(int(flight.col), int(flight.row))
		var arrived: bool = is_instance_valid(target) and int(target.data.get("item", {}).get("uid", 0)) == int(flight.item.uid)
		if arrived:
			flight.confirmed = true
			if _stash_sending_uid == int(flight.item.uid):
				_stash_sending_uid = 0
			if is_instance_valid(target.item_visual):
				target.item_visual.visible = bool(flight.landed)
		if flight.confirmed and flight.landed:
			flight.visual.queue_free()
			_stash_pending.remove_at(index)


func _clear_stash_flights() -> void:
	for flight: Dictionary in _stash_pending:
		var tween: Tween = flight.tween
		if tween != null and tween.is_valid():
			tween.kill()
		if is_instance_valid(flight.visual):
			flight.visual.queue_free()
	_stash_pending.clear()
	_stash_sending_uid = 0


func _on_merge_preview(preview: Dictionary) -> void:
	if _closing or _pending_merge.is_empty() or preview.get("request_id", "") != _pending_merge.get("request_id", ""):
		return
	if int(preview.get("version", -1)) != int(_view.get("version", 0)) or preview.get("period", "") != _view.get("period", ""):
		_clear_merge_preview()
		_on_failed("state_conflict")
		return
	var lost: Array = preview.get("lost_drops", [])
	if lost.is_empty():
		_commit_merge(false)
		return
	var names: PackedStringArray = []
	for drop: Dictionary in lost:
		var definition: Dictionary = _defs.get(str(drop.get("id", "")), {})
		names.append("%s ×%d" % [definition.get("name", drop.get("id", "")), int(drop.get("count", 0))])
	_loss_popup = CONFIRM_SCENE.instantiate() as ConfirmPopup
	UIManager.show_popup(_loss_popup)
	_loss_popup.setup("合成奖励空间不足", "合成后空位不足，继续将丢失：\n%s\n是否继续合成？" % "、".join(names), _commit_merge.bind(true))
	_status.text = "合成奖励空间不足，请选择是否继续。"
	var popup_panel: Panel = _loss_popup.get_node("Panel") as Panel
	popup_panel.offset_left = -300
	popup_panel.offset_right = 300
	popup_panel.offset_top = -160
	popup_panel.offset_bottom = 160
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10252b")
	style.border_color = Color("86aaa0")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	popup_panel.add_theme_stylebox_override("panel", style)
	_loss_popup.title_label.add_theme_font_size_override("font_size", 26)
	_loss_popup.message_label.add_theme_font_size_override("font_size", 20)
	for button: Button in [_loss_popup.confirm_btn, _loss_popup.cancel_btn]:
		button.add_theme_font_size_override("font_size", 22)
		button.custom_minimum_size = Vector2(150, 52)
	_loss_popup.confirm_btn.text = "继续合成"
	_loss_popup.cancel_btn.text = "取消"
	_loss_popup.hide_animation_finished.connect(_on_loss_popup_closed)


func _commit_merge(accept_loss: bool) -> void:
	var body: Dictionary = _pending_merge
	_pending_merge = {}
	_loss_popup = null
	if _closing or body.is_empty():
		return
	if int(body.get("version", -1)) != int(_view.get("version", 0)) or body.get("period", "") != _view.get("period", ""):
		_on_failed("state_conflict")
		return
	if accept_loss:
		body["accept_reward_loss"] = true
	_send_action(body)


func _on_loss_popup_closed() -> void:
	if not _pending_merge.is_empty():
		_status.text = "已取消合成，物品与奖励均未消耗。"
	_pending_merge = {}
	_loss_popup = null
	if not _is_drop_animating() and not is_instance_valid(_reward_effects) and not CloudService.secret_realm_busy:
		_merge_drag_open = false
		_merge_locked_cells.clear()
	_drain_queued_drops.call_deferred()


func _clear_merge_preview() -> void:
	_pending_merge = {}
	if is_instance_valid(_loss_popup):
		UIManager.hide_popup(_loss_popup)
	_loss_popup = null


func _all_cells() -> Array[Control]:
	var cells: Array[Control] = []
	if is_instance_valid(_board_layer):
		for cell: Control in _board_layer.get_children():
			cells.append(cell)
	for slot: Node in _stash.get_children():
		if slot.get_child_count() > 0 and slot.get_child(0).get_script() == Cell:
			cells.append(slot.get_child(0))
	return cells


func _present_drop(uid: int, col: int, row: int) -> void:
	var source: Control
	var target: Control
	for cell: Control in _all_cells():
		var item: Dictionary = cell.data.get("item", {})
		if int(item.get("uid", 0)) == uid:
			source = cell
		if not cell.from_stash and int(cell.data.get("col", -1)) == col and int(cell.data.get("row", -1)) == row:
			target = cell
	if not is_instance_valid(source) or not is_instance_valid(target):
		return
	var source_item: Dictionary = source.data.get("item", {})
	var target_item: Dictionary = target.data.get("item", {})
	if not target_item.is_empty() and not MergeService.can_merge(source.merge_data(), target.merge_data(), _next_definition):
		_present_push(source, target)
		return
	source.suppress_item()
	_presenting_drop = true
	if target.data.has("enemy"):
		var submitted_visual: GridItem = target.create_item_visual(source_item, source.definition)
		submitted_visual.play_merge_animation()
		_drop_animation = create_tween()
		_drop_animation.tween_interval(Constants.SPAWN_ANIM_DURATION)
		_drop_animation.finished.connect(_on_drop_animation_finished)
		return
	if target_item.is_empty():
		target.item_visual = target.create_item_visual(source_item, source.definition)
		return
	# Reuse the actual main-board animation methods, including timings/easing.
	_lock_merge(uid, col, row)
	target.item_visual.play_merge_animation()
	var arriving: GridItem = target.create_item_visual(source_item, source.definition)
	arriving.play_merge_animation()
	var next_definition: Dictionary = MergeService.get_next_item(source.merge_data(), _next_definition)
	if not next_definition.is_empty():
		target.item_visual = target.create_item_visual({"immovable": false}, next_definition)
		target.item_visual.play_spawn_animation()
	_drop_animation = create_tween()
	_drop_animation.tween_interval(Constants.SPAWN_ANIM_DURATION)
	_drop_animation.finished.connect(_on_drop_animation_finished)


func _push_destination(source: Control, target: Control) -> Control:
	var positions: Dictionary = {}
	var start_row: int = int(_view.get("start_row", 0))
	for cell: Control in _board_layer.get_children():
		positions[Vector2i(int(cell.data.col), 7 - (int(cell.data.row) - start_row))] = cell
	var start: Vector2i = Vector2i(int(target.data.col), 7 - (int(target.data.row) - start_row))
	var found: Vector2i = GridUtils.find_nearest_empty(start, 6, 8, func(pos: Vector2i) -> bool:
		var cell: Control = positions.get(pos)
		return is_instance_valid(cell) and not cell.data.get("fog", false) and cell.data.get("item", {}).is_empty() and str(cell.data.get("monster", "")).is_empty() and cell.data.get("enemy", {}).is_empty()
	)
	return positions.get(found, source)


func _present_push(source: Control, target: Control) -> void:
	var destination: Control = _push_destination(source, target)
	var dragged: GridItem = source.item_visual
	var displaced: GridItem = target.item_visual
	_presenting_drop = true
	source.item_visual = null
	displaced.reparent(destination)
	destination.item_visual = displaced
	dragged.reparent(target)
	target.item_visual = dragged
	_drop_animation = create_tween().set_parallel(true)
	DragController.slide(displaced, Vector2.ZERO, _drop_animation)
	if destination == source:
		DragController.slide(dragged, Vector2.ZERO, _drop_animation)
	else:
		dragged.position = Vector2.ZERO
	_drop_animation.finished.connect(_on_drop_animation_finished)


func _on_drop_animation_finished() -> void:
	var latest: Dictionary = _deferred_view
	_finish_drop_animation()
	if not latest.is_empty():
		_on_view(latest)
	_drain_queued_drops.call_deferred()


func _finish_drop_animation() -> void:
	if _drop_animation != null and _drop_animation.is_valid():
		_drop_animation.kill()
	_drop_animation = null
	_deferred_view = {}


func _use_selected() -> void:
	var item: Dictionary = _selection.get("item", {})
	var def: Dictionary = _defs.get(str(item.get("id", "")), {})
	if _selection.get("stash", false) or _selection.get("fog", false) or item.is_empty() or item.get("immovable", false):
		return
	if str(def.get("chain", "")) not in ["stamina", "stone"] or int(def.get("level", 0)) < 2:
		return
	_submit("use", {"uid": item.get("uid", 0)})


func _submit(action: String, extra: Dictionary) -> void:
	if not _can_interact():
		return
	_send_action(_action_body(action, extra))


func _action_body(action: String, extra: Dictionary) -> Dictionary:
	var body: Dictionary = extra.duplicate(true)
	body.merge({"action": action, "period": _view.get("period", ""), "version": _view.get("version", 0), "request_id": "realm-%s-%s" % [Time.get_ticks_usec(), randi()]})
	return body


func _send_action(body: Dictionary) -> void:
	if not _can_interact():
		return
	_effect_request_id = str(body.get("request_id", ""))
	if body.get("action", "") in ["move", "place", "fight"]:
		_present_drop(int(body.get("uid", 0)), int(body.get("col", -1)), int(body.get("row", -1)))
	action_requested.emit(body)
	CloudService.submit_secret_realm(body)


func _on_failed(reason: String) -> void:
	if reason == "state_conflict":
		CloudService.force_relogin()
	_queued_drops.clear()
	_merge_drag_open = false
	_merge_locked_cells.clear()
	_cancel_drag()
	_effect_request_id = ""
	_clear_reward_effects()
	_clear_merge_preview()
	var had_stash_flights: bool = not _stash_pending.is_empty()
	_clear_stash_flights()
	if _presenting_drop or had_stash_flights:
		_render_board()
		_render_stash()
	var messages: Dictionary = {"offline": "连接服务器后可继续探索", "state_conflict": "服务器状态不一致，正在重新登录…", "insufficient_items": "所需飞剑或剑气不足", "max_level": "该物品已达到最高等级", "item_locked": "固定物品须先合成解锁", "cell_occupied": "请投放至已揭雾空位", "merge_reward_first": "奖励合成到 2 级后可使用", "activity_locked": "秘境暂未开放"}
	messages["merge_reward_overflow"] = "合成奖励空间不足，请重新拖动并确认是否继续"
	messages["mobs_remaining"] = "请先击败本关全部小怪（含迷雾中的小怪），再挑战 Boss"
	messages["wrong_submission"] = "请拖入怪物所需等级的飞剑或剑气"
	messages["requirement_filled"] = "该物品已提交足够数量，请提交其余需求"
	messages["invalid_source"] = "请拖入棋盘上已解锁的飞剑或剑气"
	_status.text = "操作结果未确认，正在重新登录…" if CloudService.relogin_pending else str(messages.get(reason, "操作失败，请稍后再试"))


func _close() -> void:
	if not _closing:
		_closing = true
		_finish_scroll()
		UIManager.hide_popup(self)


func hide_animated() -> void:
	_closing = true
	_queued_drops.clear()
	_clear_merge_preview()
	_clear_reward_effects()
	_cancel_drag()
	_clear_stash_flights()
	_finish_drop_animation()
	_finish_scroll()
	super.hide_animated()


func _exit_tree() -> void:
	_clear_reward_effects()
	_clear_stash_flights()
	_finish_drop_animation()
	_finish_scroll()


func _cancel_drag() -> void:
	_drag_gesture.cancel()
	_pressed_selected_uid = 0
	if is_instance_valid(_drag_source):
		_drag_source.end_drag()
	_drag_source = null
	_pressed_cell = null
	_drag_payload = {}
