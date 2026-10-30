extends Node

var _requests: Array[Dictionary] = []


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	CloudService.secret_realm_state.clear()
	CloudService.secret_realm_retry.clear()
	CloudService.secret_realm_busy = false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/secret_realm.json"))
	var view: Dictionary = config.settings[0].duplicate(true)
	view.merge({"available": true, "initialized": true, "version": 0, "stage": 0, "stage_name": "第1境", "start_row": 0, "completed": false, "stash": [], "cells": [], "items": config.items, "inventory": {"sword_5": 1, "qi_6": 1}})
	view["remaining_mobs"] = 2
	var uid: int = 0
	for data: Dictionary in config.layout:
		uid += 1
		if int(data.row) >= 8:
			continue
		var cell: Dictionary = {"col": data.col, "row": data.row, "fog": data.fog}
		if absi(int(data.col) - 3) <= 1 and absi(int(data.row) - 6) <= 1:
			cell["special_fog"] = true
		if not data.fog:
			cell["item"] = {"uid": uid, "id": data.id, "immovable": data.immovable}
		view.cells.append(cell)
	for n: int in range(8):
		view.stash.append({"uid": 1000 + n, "id": "sword_1", "immovable": n == 0})
	var panel := preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(panel)
	panel.setup(9, false)
	panel.action_requested.connect(func(body: Dictionary) -> void: _requests.append(body))
	panel._on_view(view)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	assert(panel._board_layer.get_child_count() == 48)
	assert(panel.find_children("*", "Button", true, false).all(func(button: Button) -> bool: return button.text not in ["刷新", "重试操作"]))
	assert(panel._stash.get_child_count() == 4)
	assert(panel._stash.get_child(0).get_child(0).data.item.uid == 1000)
	assert(panel._board_layer.get_children().filter(func(cell: Control) -> bool: return cell.has_node("SpecialFogSeal")).size() == 9)
	var seal_cell: Control = _find_cell(panel, 2, 5)
	assert(seal_cell.data.fog and seal_cell.item_visual == null and seal_cell.monster_visual == null)
	assert(seal_cell.tooltip_text.contains("击败本关全部小怪"))
	panel._select(seal_cell.data, false)
	assert(panel._detail.text.contains("特殊迷雾") and panel._detail.text.contains("2 只"))
	assert(not _find_cell(panel, 0, 3).has_node("SpecialFogSeal"))
	var source: Control = _find_cell(panel, 0, 0)
	var target: Control = _find_cell(panel, 0, 1)
	# Compare logical and displayed cell geometry against the main-board scene.
	var main_grid := preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	assert(source.size == Vector2.ONE * Constants.CELL_SIZE)
	assert(source.get_child(0).texture == main_grid.grid_cell_texture)
	assert(source.item_visual is GridItem and target.item_visual.immovable_icon.visible)
	assert(source.get_global_rect().size.is_equal_approx(Vector2.ONE * Constants.CELL_SIZE * Constants.BOARD_DISPLAY_SCALE))
	var neighbor: Control = _find_cell(panel, 1, 0)
	assert(is_equal_approx(neighbor.global_position.x - source.global_position.x, Constants.CELL_STEP * Constants.BOARD_DISPLAY_SCALE))
	var stash_cell: Control = panel._stash.get_child(0).get_child(0)
	assert(stash_cell.get_global_rect().size.is_equal_approx(source.get_global_rect().size))
	assert(stash_cell.get_drag_payload().is_empty())
	main_grid.free()
	var fog: Control = _find_cell(panel, 0, 3)
	var fixed: Control = _find_cell(panel, 4, 0)
	assert(fixed.get_drag_payload().is_empty())
	assert(fog.get_drag_payload().is_empty())
	var payload: Dictionary = {"secret_realm": true, "uid": source.data.item.uid, "id": "sword_1", "stash": false}
	assert(not fog.can_accept(payload))
	assert(target.can_accept(payload))
	# The shared MergeService uses realm config lookup, not hardcoded caps.
	var next_def: Dictionary = panel._defs["sword_2"]
	panel._defs.erase("sword_2")
	assert(not target.can_accept(payload))
	panel._defs["sword_2"] = next_def
	var supply_payload: Dictionary = payload.duplicate(true)
	supply_payload.merge({"uid": 1001, "stash": true, "immovable": false}, true)
	assert(not target.can_accept(supply_payload), "stash items cannot be dragged into a merge")
	supply_payload.immovable = true
	assert(not target.can_accept(supply_payload))
	var enemy_target: Control = panel._make_cell({"col": 0, "row": 0, "enemy": config.monsters[0]})
	assert(not enemy_target.can_accept(payload))
	enemy_target.free()
	# Empty optional monster fields must not prohibit an ordinary target.
	target.data.monster = ""
	assert(target.can_accept(payload))
	target.data.erase("monster")
	# Drive real pointer events through the shared main-board drag controller.
	var start: Vector2 = source.get_global_rect().get_center()
	var finish: Vector2 = target.get_global_rect().get_center()
	_mouse_button(start, true)
	await get_tree().process_frame
	_mouse_move(start + Vector2(20, 0), Vector2(20, 0))
	await get_tree().process_frame
	_mouse_move(finish, finish - start - Vector2(20, 0))
	await get_tree().process_frame
	assert(is_instance_valid(panel._drag_source))
	assert(source._dragging and source.item_visual.get_parent() == panel._drag_layer, "same GridItem follows the pointer without a native preview duplicate")
	_mouse_button(finish, false)
	await get_tree().process_frame
	assert(_requests.is_empty(), "offline preview never submits a consuming action")
	assert(panel._board_layer.get_child_count() == 48, "offline requests do not optimistically consume items")
	# Main-board GridItem effects are reused without changing authoritative realm data.
	var saved: Dictionary = panel._view.duplicate(true)
	panel._present_drop(int(payload.uid), 0, 1)
	source = _find_cell(panel, 0, 0)
	target = _find_cell(panel, 0, 1)
	assert(not source.item_visual.visible and target.item_visual.level_label.text == "2")
	assert(target.item_visual.scale.length() < 0.001)
	assert(panel._view == saved)
	await get_tree().create_timer(Constants.SPAWN_ANIM_DURATION + 0.05).timeout
	assert(target.item_visual.scale.is_equal_approx(Vector2.ONE))
	panel._on_failed("timeout")
	source = _find_cell(panel, 0, 0)
	assert(source.item_visual.visible and source.item_visual.level_label.text == "1")
	# A fast authoritative response waits for the shared spawn effect to finish.
	var confirmed: Dictionary = view.duplicate(true)
	confirmed.version = 1
	for cell: Dictionary in confirmed.cells:
		if cell.col == 0 and cell.row == 0:
			cell.erase("item")
		if cell.col == 0 and cell.row == 1:
			cell.item = {"uid": 9999, "id": "sword_2", "immovable": false}
	panel._present_drop(int(payload.uid), 0, 1)
	panel._on_view(confirmed)
	assert(panel._view.version == 0 and not panel._can_interact())
	await get_tree().create_timer(Constants.SPAWN_ANIM_DURATION + 0.08).timeout
	assert(panel._view.version == 1 and panel._can_interact())
	assert(_find_cell(panel, 0, 1).item_visual.level_label.text == "2")
	panel._on_view(view)
	source = _find_cell(panel, 0, 0)
	# Invalid release returns the icon to its cell in the main board's 0.2 seconds.
	start = source.get_global_rect().get_center()
	finish = _find_cell(panel, 0, 3).get_global_rect().get_center()
	_mouse_button(start, true)
	await get_tree().process_frame
	_mouse_move(start + Vector2(20, 0), Vector2(20, 0))
	await get_tree().process_frame
	_mouse_move(finish, finish - start - Vector2(20, 0))
	await get_tree().process_frame
	_mouse_button(finish, false)
	await get_tree().process_frame
	assert(source.item_visual.visible and source._return_tween != null)
	await get_tree().create_timer(Constants.SNAP_BACK_DURATION + 0.05).timeout
	assert(source.item_visual.position.is_equal_approx(Vector2.ZERO))
	assert(_requests.is_empty())
	# Rebuilding continues an unchanged item drag by UID and preserves its position.
	start = source.get_global_rect().get_center()
	_mouse_button(start, true)
	await get_tree().process_frame
	_mouse_move(start + Vector2(20, 0), Vector2(20, 0))
	await get_tree().process_frame
	assert(source.item_visual.get_parent() == panel._drag_layer)
	panel._render_board()
	assert(is_instance_valid(panel._drag_source) and panel._drag_source.data.item.uid == source.data.item.uid)
	_mouse_button(start, false)
	panel._cancel_drag()
	assert(_requests.is_empty())
	var before: Vector2 = panel._board_layer.position
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	panel._board.gui_input.emit(wheel)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 100)
	panel._board.gui_input.emit(pan)
	assert(panel._board_layer.position == before)
	# Stash uses release-click only. Dragging out and back never places an item.
	stash_cell = panel._stash.get_child(0).get_child(0)
	start = stash_cell.get_global_rect().get_center()
	_mouse_button(start, true)
	_mouse_move(start + Vector2(30, 0), Vector2(30, 0))
	assert(panel._drag_source == null)
	_mouse_move(start, Vector2(-30, 0))
	_mouse_button(start, false)
	assert(_requests.is_empty())
	_mouse_button(start, true)
	_mouse_button(start, false)
	assert(_requests.is_empty() and panel._status.text.contains("没有已揭雾空位"))
	# Auto-placement skips hidden and monster cells. Offline failure restores visuals.
	var room: Dictionary = view.duplicate(true)
	room.version = 2
	for cell: Dictionary in room.cells:
		if cell.row == 0 and cell.col < 3:
			cell.erase("item")
			if cell.col == 0:
				cell.fog = true
			elif cell.col == 1:
				cell.monster = "mob_1"
				cell.enemy = config.monsters[0]
	panel._on_view(room)
	await get_tree().process_frame
	stash_cell = panel._stash.get_child(0).get_child(0)
	start = stash_cell.get_global_rect().get_center()
	_mouse_button(start, true)
	_mouse_button(start, false)
	assert(_requests.size() == 1 and _requests[0].action == "place" and _requests[0].uid == 1000)
	assert(_requests[0].col == 2 and _requests[0].row == 0)
	assert(panel._view == room and panel._stash_pending.is_empty())
	assert(panel._stash.get_child(0).get_child(0).item_visual.visible)
	_requests.clear()
	# Independent stash flights and rapid clicks have their own regression scene.
	panel._on_view(view)
	await _test_reward_clicks(panel, view)
	panel._on_view(view)
	panel._select({"col": 3, "row": 6, "enemy": config.monsters[1]}, false)
	assert(panel._detail.text.contains("本关剩余小怪 2 只"))
	var combat_payload: Dictionary = {"secret_realm": true, "uid": 9900, "id": "sword_7", "stash": false, "immovable": false}
	assert(not panel._can_submit_to_monster({"enemy": config.monsters[1]}, combat_payload))
	var gated_view: Dictionary = view.duplicate(true)
	gated_view.version = 4
	gated_view.remaining_mobs = 1
	panel._on_view(gated_view)
	panel._select({"col": 3, "row": 6, "enemy": config.monsters[1]}, false)
	assert(panel._detail.text.contains("本关剩余小怪 1 只"))
	combat_payload.id = "sword_4"
	assert(panel._can_submit_to_monster({"enemy": config.monsters[0]}, combat_payload), "mobs accept required items while Boss is locked")
	panel._on_failed("mobs_remaining")
	assert(panel._status.text.contains("请先击败本关全部小怪"))
	gated_view.version = 5
	gated_view.remaining_mobs = 0
	for data: Dictionary in gated_view.cells:
		if data.col == 0 and data.row == 0:
			data.item = {"uid": 9900, "id": "sword_7", "immovable": false}
		if data.col == 3 and data.row == 6:
			data.erase("item")
			data.merge({"fog": false, "monster": "boss_1", "enemy": config.monsters[1]}, true)
	panel._on_view(gated_view)
	panel._select(_find_cell(panel, 3, 6).data, false)
	assert(panel._detail.text.contains("6级剑气"))
	assert(panel._detail.text.contains("本关小怪已全部击败"))
	var monster_cell: Control = _find_cell(panel, 3, 6)
	combat_payload.id = "sword_7"
	assert(monster_cell.can_accept(combat_payload))
	combat_payload.id = "sword_6"
	assert(not monster_cell.can_accept(combat_payload))
	combat_payload.id = "sword_7"
	combat_payload.immovable = true
	assert(not monster_cell.can_accept(combat_payload))
	combat_payload.immovable = false
	combat_payload.stash = true
	assert(not monster_cell.can_accept(combat_payload))
	combat_payload.stash = false
	# Use the shared pointer drag all the way onto the monster, without a button.
	source = _find_cell(panel, 0, 0)
	start = source.get_global_rect().get_center()
	finish = monster_cell.get_global_rect().get_center()
	_mouse_button(start, true)
	await get_tree().process_frame
	_mouse_move(start + Vector2(20, 0), Vector2(20, 0))
	await get_tree().process_frame
	_mouse_move(finish, finish - start - Vector2(20, 0))
	await get_tree().process_frame
	_mouse_button(finish, false)
	await get_tree().process_frame
	assert(_requests[-1].action == "fight" and int(_requests[-1].uid) == 9900)
	assert(panel._view == gated_view and _find_cell(panel, 0, 0).item_visual.visible, "offline submission restores the source")
	# Fast authoritative partial progress waits for the reused item effect.
	panel._select(_find_cell(panel, 3, 6).data, false)
	panel._present_drop(9900, 3, 6)
	assert(panel._is_drop_animating() and not panel._can_interact())
	var partial_view: Dictionary = gated_view.duplicate(true)
	partial_view.version = 6
	for data: Dictionary in partial_view.cells:
		if data.col == 0 and data.row == 0:
			data.erase("item")
		if data.col == 3 and data.row == 6:
			data.submitted = {"sword_7": 1}
	panel._on_view(partial_view)
	await get_tree().create_timer(Constants.SPAWN_ANIM_DURATION + 0.08).timeout
	assert(int(panel._view.version) == 6 and panel._detail.text.contains("7级飞剑 1/1"))
	monster_cell = _find_cell(panel, 3, 6)
	assert(not monster_cell.can_accept(combat_payload), "filled sword requirement rejects extra items")
	combat_payload.id = "qi_6"
	assert(monster_cell.can_accept(combat_payload))
	# A slow response can arrive after the effect while the cloud request is busy.
	CloudService.secret_realm_busy = true
	partial_view.version = 7
	panel._on_view(partial_view)
	assert(panel._detail.text.contains("7级飞剑 1/1") and not panel._can_interact())
	CloudService.secret_realm_busy = false
	panel._on_view(partial_view)
	assert(panel._detail.text.contains("7级飞剑 1/1") and panel._can_interact())
	# Successful acknowledgements clear the current request without a retry button.
	CloudService.secret_realm_retry = _requests[-1].duplicate(true)
	CloudService._on_secret_realm_response({"ok": true, "replayed": true, "storage_revision": 10})
	assert(CloudService.secret_realm_retry.is_empty())
	CloudService._sync_secret_realm({"storage_revision": 10, "secret_realm": view})
	CloudService._sync_secret_realm({"storage_revision": 9, "secret_realm": {"version": -1}})
	assert(CloudService.secret_realm_state.version == 0)
	# Late and mismatching previews cannot commit; failed previews are retryable
	# by dragging again and never become unresolved mutation retries.
	var pending: Dictionary = panel._action_body("move", {"uid": int(payload.uid), "col": 0, "row": 1})
	panel._pending_merge = pending.duplicate(true)
	panel._on_merge_preview({"request_id": "other", "version": 0, "period": view.period, "lost_drops": []})
	assert(not panel._pending_merge.is_empty())
	panel._on_failed("timeout")
	assert(panel._pending_merge.is_empty() and CloudService.secret_realm_retry.is_empty())
	panel._pending_merge = pending.duplicate(true)
	panel._on_merge_preview({"request_id": pending.request_id, "version": 0, "period": view.period, "lost_drops": [{"id":"qi_4","count":1},{"id":"sword_3","count":1},{"id":"sword_4","count":1}]})
	assert(is_instance_valid(panel._loss_popup) and not panel._can_interact())
	assert(panel._loss_popup.message_label.text.contains("4级剑气") and panel._loss_popup.message_label.text.contains("4级飞剑"))
	for level in range(3, 5):
		assert(panel._loss_popup.message_label.text.contains("%d级飞剑" % level))
	var changes: Dictionary = view.duplicate(true)
	changes.version = 9
	panel._on_view(changes)
	assert(panel._pending_merge.is_empty() and not is_instance_valid(panel._loss_popup))
	panel._on_merge_preview({"request_id": pending.request_id, "version": 0, "period": view.period, "lost_drops": []})
	assert(panel._pending_merge.is_empty())
	await get_tree().create_timer(0.3).timeout
	panel._on_view(view)
	# A Boss response animates logical rows downward and blocks all actions.
	var advance_base: Dictionary = view.duplicate(true)
	advance_base.version = 20
	for data: Dictionary in advance_base.cells:
		if data.col == 0 and data.row == 4:
			data.fog = false
			data.item = {"uid": 9100, "id": "qi_2", "immovable": false}
		if data.col == 5 and data.row == 7:
			data.fog = false
			data.item = {"uid": 9101, "id": "qi_3", "immovable": true}
	panel._on_view(advance_base)
	var retained_position: Vector2 = _find_cell(panel, 0, 4).global_position
	var next: Dictionary = advance_base.duplicate(true)
	next.version = 21
	next.start_row = 4
	next.stage = 1
	next.stage_name = "第2境"
	next.cells = []
	for data: Dictionary in advance_base.cells:
		if data.row >= 4:
			next.cells.append(data.duplicate(true))
		elif not data.fog and data.has("item"):
			next.stash.append(data.item.duplicate(true))
	for row: int in range(8, 12):
		for col: int in range(6):
			next.cells.append({"col": col, "row": row, "fog": true})
	panel._on_view(next)
	assert(panel._is_scrolling() and not panel._can_interact())
	assert(_find_cell(panel, 0, 4).global_position.is_equal_approx(retained_position), "overlapping cells start at the same screen position")
	for old: Control in panel._outgoing.get_children():
		assert(old.visible == (int(old.data.row) < 4), "outgoing layer contains only disappearing rows")
	assert(not next.stash.any(func(i: Dictionary) -> bool: return int(i.uid) in [9100, 9101]))
	var start_y: float = panel._board_layer.position.y
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/realm-outgoing-only-scroll.png")
	await get_tree().create_timer(0.75).timeout
	assert(not panel._is_scrolling() and panel._can_interact())
	assert(panel._board_layer.position.y > start_y)
	assert(panel._board_layer.get_child_count() == 48)
	assert(panel._outgoing == null)
	assert(_find_cell(panel, 0, 4).data.item.uid == 9100 and not _find_cell(panel, 0, 4).data.item.immovable)
	assert(_find_cell(panel, 5, 7).data.item.uid == 9101 and _find_cell(panel, 5, 7).data.item.immovable)
	assert(panel._board.get_global_rect().encloses(panel._board_layer.get_global_rect()))
	# The sixth Boss displays all six max-level swords and max qi without truncating quantities.
	var final_boss: Dictionary = {}
	for monster: Dictionary in config.monsters:
		if monster.id == "boss_6":
			final_boss = monster
	assert(not final_boss.is_empty())
	var final_view: Dictionary = view.duplicate(true)
	final_view.merge({"version": 30, "stage": 5, "stage_name": "第6境", "start_row": 20,
		"cells": [], "remaining_mobs": 0, "inventory": {"sword_12": 5, "qi_6": 1}}, true)
	for data: Dictionary in config.layout:
		if int(data.row) < 20 or int(data.row) >= 28:
			continue
		var final_cell: Dictionary = {"col": data.col, "row": data.row, "fog": true}
		if data.monster == "boss_6":
			final_cell.merge({"fog": false, "monster": "boss_6", "enemy": final_boss}, true)
		final_view.cells.append(final_cell)
	panel._on_view(final_view)
	assert(panel._board_layer.get_child_count() == 48)
	panel._select(_find_cell(panel, 3, 26).data, false)
	assert(panel._detail.text.contains("12级飞剑 0/6（持有5）") and panel._detail.text.contains("6级剑气 0/6（持有1）"))
	final_view.version = 31
	final_view.inventory.sword_12 = 6
	for data: Dictionary in final_view.cells:
		if data.get("monster", "") == "boss_6":
			data.submitted = {"sword_12": 6}
	panel._on_view(final_view)
	panel._select(_find_cell(panel, 3, 26).data, false)
	assert(panel._detail.text.contains("12级飞剑 6/6"))
	panel._on_view(next)
	var entry := preload("res://scenes/ui/activity/HomeActivityCard.tscn").instantiate() as HomeActivityCard
	add_child(entry)
	entry.setup({"id": 9, "name": "剑墟秘境", "widget": "SecretRealm", "active": true})
	assert(entry.activity_mark.text == "秘")
	entry.queue_free()
	if "--screenshot" in OS.get_cmdline_user_args():
		panel._on_view(view)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/secret_realm_ui.png")
	# Closing during advance cancels presentation only; cloud receipt still completes.
	panel._on_view(view)
	panel._on_view(next)
	assert(panel._is_scrolling())
	await UIManager.hide_popup(panel)
	CloudService._on_secret_realm_response({"ok": true, "replayed": true, "storage_revision": 11})
	print("SECRET_REALM_UI_SMOKE_OK")
	get_tree().quit()


func _find_cell(panel: SecretRealmPanel, col: int, row: int) -> Control:
	for cell: Control in panel._board_layer.get_children():
		if cell.data.get("col", -1) == col and cell.data.get("row", -1) == row:
			return cell
	return null


func _test_reward_clicks(panel: SecretRealmPanel, base: Dictionary) -> void:
	assert(panel.find_children("*", "Button", true, false).all(func(button: Button) -> bool: return button.text not in ["使用奖励", "收回暂存"]))
	var rewards: Dictionary = base.duplicate(true)
	rewards.version = 100
	var ids: Array[String] = ["stamina_2", "stone_3", "stamina_1", "stone_1", "stone_2", "sword_1"]
	for data: Dictionary in rewards.cells:
		if int(data.row) == 0:
			data.fog = false
			data.item = {"uid": 9000 + int(data.col), "id": ids[int(data.col)], "immovable": int(data.col) == 4}
	panel._on_view(rewards)
	await get_tree().process_frame
	_requests.clear()
	for col: int in [0, 1]:
		var cell: Control = _find_cell(panel, col, 0)
		var point: Vector2 = cell.get_global_rect().get_center()
		_mouse_button(point, true)
		_mouse_button(point, false)
		assert(_requests.size() == col, "first click selects without consuming either resource")
		assert(panel._detail.text.contains("再次点击使用"))
		_mouse_button(point, true)
		assert(_requests.size() == col, "press alone never consumes")
		_mouse_button(point, false)
		assert(_requests.size() == col + 1 and _requests[-1].action == "use" and int(_requests[-1].uid) == 9000 + col)
	assert(panel._view == rewards, "resources wait for authoritative settlement")
	_requests.clear()
	# Level-one, fixed and non-resource items never submit use.
	for col: int in [2, 3, 4, 5]:
		var point: Vector2 = _find_cell(panel, col, 0).get_global_rect().get_center()
		for n: int in range(2):
			_mouse_button(point, true)
			_mouse_button(point, false)
	assert(_requests.is_empty())
	var source: Control = _find_cell(panel, 0, 0)
	var point: Vector2 = source.get_global_rect().get_center()
	_mouse_button(point, true)
	_mouse_button(point, false)
	# A second press that becomes a drag must not use the selected reward.
	_mouse_button(point, true)
	_mouse_move(point + Vector2(24, 0), Vector2(24, 0))
	await get_tree().process_frame
	assert(is_instance_valid(panel._drag_source))
	_mouse_button(Vector2.ZERO, false)
	assert(_requests.is_empty())
	# Releasing outside the cell and blocked input also cannot consume it.
	_mouse_button(point, true)
	_mouse_button(Vector2.ZERO, false)
	CloudService.secret_realm_busy = true
	_mouse_button(point, true)
	_mouse_button(point, false)
	CloudService.secret_realm_busy = false
	assert(_requests.is_empty())


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _mouse_move(position: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)
