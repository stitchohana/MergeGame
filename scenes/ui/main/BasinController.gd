extends Node

var artifact_id: String = "basin"
var artifact_name: String = "聚宝盆"
var _choice_popup: BasePopup
var grid_view: GridView
var basin_button: Control
var pending_bar: PendingRewardBar
var _uid: int = 0
var _phase: String = ""
var _input_token: int = -1
var _tween: Tween
var _flies: Array[TextureRect] = []
var _hidden: Dictionary = {}
var _last_delivery: String = ""

func setup(grid: GridView, button: Control, pending: PendingRewardBar) -> void:
	grid_view = grid
	basin_button = button
	pending_bar = pending
	if artifact_id == "furnace":
		artifact_name = "万象炉"
		grid_view.set_furnace_zone(button)
		grid_view.furnace_drop_requested.connect(_on_drop)
	else:
		grid_view.set_basin_zone(button)
		grid_view.basin_drop_requested.connect(_on_drop)
	grid_view.action_sync_cancelled.connect(_on_sync_cancelled)
	CloudService.golden_finger_preview.connect(_on_preview)
	CloudService.golden_finger_confirmed.connect(_on_confirmed)
	CloudService.golden_finger_failed.connect(_on_failed)

func _on_drop(uid: int) -> void:
	if not _phase.is_empty() or _input_token >= 0:
		return
	if not CloudService.online:
		EventBus.show_toast.emit("请联网后使用" + artifact_name)
		return
	var unlock_level: int = 2
	for definition: Dictionary in ConfigDatabase.golden_finger.get("artifacts", []):
		if str(definition.get("id", "")) == artifact_id:
			unlock_level = int(definition.get("unlock_level", 2))
	if CultivationService.current_level < unlock_level:
		EventBus.show_toast.emit("万象炉在练气三层解锁" if artifact_id == "furnace" else "聚宝盆在练气一层解锁")
		return
	if CloudService.golden_finger_busy or not CloudService.golden_finger_retry.is_empty():
		EventBus.show_toast.emit("有待确认的法宝操作，请点击法宝重试上一笔操作")
		return
	if uid <= 0:
		return
	_uid = uid
	_phase = "sync"
	grid_view.run_after_action_sync(_request_preview)

func _request_preview() -> void:
	if _phase != "sync":
		return
	var pos: Vector2i = GridManager.find_pos_by_uid(_uid)
	if pos.x < 0 or GameState.current_board_type != Constants.BoardType.MAIN:
		_on_failed("invalid_materials")
		return
	if artifact_id == "furnace":
		_phase = "choose"
		grid_view.set_item_hidden(_uid, true)
		var popup := preload("res://scenes/ui/main/FurnaceChoicePopup.gd").new()
		popup.artifact_id = "furnace"
		popup.input_uid = _uid
		_choice_popup = popup
		popup.tree_exited.connect(_on_choice_closed)
		UIManager.show_popup(popup)
		return
	_input_token = UIManager.begin_input_block("basin_use")
	_phase = "preview"
	grid_view.set_item_hidden(_uid, true)
	CloudService.preview_golden_finger({"artifact": "basin", "uids": [_uid]})

func _on_preview(data: Dictionary) -> void:
	if _phase != "preview":
		return
	_phase = "use"
	CloudService.submit_golden_finger("use", {"artifact": "basin", "uids": [_uid],
		"version": int(data.get("version", 0)), "period_key": str(data.get("golden_finger", {}).get("period_key", "")),
		"quote": data.get("quote", {}), "request_id": "basin-%s-%s" % [str(Time.get_ticks_usec()), str(randi())]})

func _on_confirmed(data: Dictionary) -> void:
	if str(data.get("artifact", "")) != artifact_id or str(data.get("action", "")) != "use":
		return
	_phase = ""
	grid_view.set_item_hidden(_uid, false)
	_uid = 0
	var outputs: Array = data.get("spawned_items", []).duplicate(true)
	for item: Dictionary in data.get("pending_items", []):
		var entry: Dictionary = item.duplicate(true)
		entry["pending"] = true
		outputs.append(entry)
	var signature: String = str(outputs.map(func(item: Dictionary) -> int: return int(item.get("uid", 0))))
	if signature == _last_delivery:
		return
	if outputs.is_empty():
		_release_input()
		return
	_last_delivery = signature
	_finish_animation()
	_input_token = UIManager.begin_input_block("basin_fly")
	_tween = create_tween().set_parallel(true)
	var host: Control = UIManager.get_layer(UIManager.Layer.OVERLAY)
	var origin: Vector2 = basin_button.get_global_rect().get_center()
	for index: int in range(outputs.size()):
		var entry: Dictionary = outputs[index]
		var def: Dictionary = ConfigDatabase.get_item_data(int(entry.get("id", 0)))
		var texture: Texture2D = load(str(def.get("icon", ""))) as Texture2D
		if texture == null:
			continue
		var target: Vector2
		var fly_size := Vector2(72, 72)
		if bool(entry.get("pending", false)):
			target = pending_bar.get_global_rect().get_center()
		else:
			var pos := Vector2i(int(entry.get("col", -1)), int(entry.get("row", -1)))
			var node: GridItem = grid_view._item_nodes.get("%d,%d" % [pos.x, pos.y]) as GridItem
			if not is_instance_valid(node) or int(node.item_data.get("_uid", 0)) != int(entry.get("uid", 0)):
				continue
			target = node.icon_rect.get_global_rect().get_center()
			fly_size = node.icon_rect.get_global_rect().size
			_hidden[int(entry.uid)] = true
			grid_view.set_item_hidden(int(entry.uid), true)
		var fly := TextureRect.new()
		fly.texture = texture
		fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fly.size = fly_size
		fly.z_index = 1000
		host.add_child(fly)
		fly.global_position = origin - fly_size / 2.0
		_flies.append(fly)
		var delay: float = index * 0.12
		if bool(entry.get("pending", false)):
			_tween.tween_method(_move_to_pending.bind(fly, origin), 0.0, 1.0, 0.5).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		else:
			_tween.tween_property(fly, "global_position", target - fly_size / 2.0, 0.5).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_callback(_land.bind(int(entry.uid), fly)).set_delay(delay + 0.5)
	_tween.finished.connect(_finish_animation)
	var count: int = int(data.get("pending_rewards_added", 0))
	EventBus.show_toast.emit("万象炉转化完成，物品已放入棋盘" if artifact_id == "furnace" else ("聚宝盆产出 2 件物品，%d 件已放入暂存区" % count if count > 0 else "聚宝盆产出 2 件物品，已放入棋盘"))

func _on_choice_closed() -> void:
	_choice_popup = null
	if _phase == "choose":
		grid_view.set_item_hidden(_uid, false)
		_uid = 0
		_phase = ""

func _move_to_pending(progress: float, fly: TextureRect, origin: Vector2) -> void:
	if is_instance_valid(fly):
		fly.global_position = origin.lerp(pending_bar.get_global_rect().get_center(), progress) - fly.size / 2.0

func _land(uid: int, fly: TextureRect) -> void:
	if is_instance_valid(grid_view):
		grid_view.set_item_hidden(uid, false)
	_hidden.erase(uid)
	_flies.erase(fly)
	if is_instance_valid(fly):
		fly.queue_free()

func _on_sync_cancelled() -> void:
	if _phase == "sync":
		_on_failed("state_conflict")

func _on_failed(reason: String) -> void:
	if _phase.is_empty():
		return
	# Buying an extra use does not cancel the furnace material selection.
	if _phase == "choose" and reason == "insufficient_stones":
		return
	grid_view.set_item_hidden(_uid, false)
	if _phase == "choose" and is_instance_valid(_choice_popup):
		UIManager.hide_popup(_choice_popup)
	_choice_popup = null
	_phase = ""
	_uid = 0
	_release_input()
	if artifact_id == "furnace":
		var furnace_reasons: Dictionary = {"no_uses": "今日次数不足，请点击万象炉消耗灵石加次", "artifact_locked": "万象炉在练气三层解锁", "invalid_materials": "该物品不能投入万象炉", "invalid_target": "目标尚未解锁或超出境界", "same_level_other_item": "请选择同级且不同于投料的已解锁物品", "state_conflict": "物品状态已变化，请重新拖入", "offline": "请联网后使用万象炉"}
		EventBus.show_toast.emit(str(furnace_reasons.get(reason, "万象炉请求未完成，请点击图标重试或刷新状态")))
		return
	var reasons: Dictionary = {"no_uses": "今日次数不足，请点击聚宝盆消耗灵石加次", "artifact_locked": "聚宝盆在练气一层解锁", "requires_lower_level": "请拖入低于当前境界最高级的材料", "invalid_materials": "该物品不能投入聚宝盆", "state_conflict": "物品状态已变化，请重新拖入", "offline": "请联网后使用聚宝盆"}
	EventBus.show_toast.emit(str(reasons.get(reason, "聚宝盆请求未完成，请点击图标重试或刷新状态")))

func _release_input() -> void:
	if _input_token >= 0:
		UIManager.end_input_block(_input_token)
		_input_token = -1

func _finish_animation() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	for uid: int in _hidden.keys():
		_land(uid, null)
	for fly: TextureRect in _flies:
		if is_instance_valid(fly):
			fly.queue_free()
	_flies.clear()
	_release_input()

func _exit_tree() -> void:
	if is_instance_valid(_choice_popup):
		_choice_popup.set("_pending", false)
		UIManager.hide_popup(_choice_popup)
	if is_instance_valid(grid_view):
		grid_view.set_item_hidden(_uid, false)
	_finish_animation()
