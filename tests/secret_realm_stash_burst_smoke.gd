extends "res://tests/secret_realm_ui_smoke.gd"

var _panel: SecretRealmPanel
var _authority: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = true
	CloudService.secret_realm_busy = false
	CloudService.secret_realm_retry.clear()
	CloudService.secret_realm_state.clear()
	CloudService.secret_realm_revision = -1
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/secret_realm.json"))
	var view: Dictionary = config.settings[0].duplicate(true)
	view.merge({"available": true, "initialized": true, "version": 0, "stage": 0, "start_row": 0,
		"stash": [], "cells": [], "items": config.items})
	for row: int in range(8):
		for col: int in range(6):
			view.cells.append({"col": col, "row": row, "fog": row != 0 or col == 0})
	view.cells[1].merge({"monster": "mob_1", "enemy": config.monsters[0]})
	view.cells[5].item = {"uid": 99, "id": "sword_1", "immovable": true}
	for n: int in range(5):
		view.stash.append({"uid": 1000 + n, "id": "qi_5" if n == 1 else "sword_1", "immovable": n < 2})
	var other_ids: Array[String] = ["sword_2", "sword_3", "sword_4", "stamina_2", "qi_1"]
	for n: int in range(other_ids.size()):
		view.stash.append({"uid": 1005 + n, "id": other_ids[n], "immovable": false})
	_authority = view.duplicate(true)
	_panel = preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(_panel)
	_panel.action_requested.connect(_capture_request)
	_panel._on_view(view)
	await get_tree().create_timer(0.3).timeout
	assert(_panel._stash.get_child_count() == 4)
	var expected_uids: Array[int] = [1000, 1005, 1006, 1001]
	var expected_counts: Array[int] = [4, 1, 1, 4]
	for group: int in range(4):
		var slot: Control = _panel._stash.get_child(group)
		assert(int(slot.get_child(0).data.item.uid) == expected_uids[group])
		assert(slot.get_child(1).text.ends_with("· %d" % expected_counts[group]))
	if "--screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/realm-four-stash.png")
	for n: int in range(3):
		var head: Control = _panel._stash.get_child(3 if n == 1 else 0).get_child(0)
		assert(int(head.data.item.uid) == 1000 + n and head.get_drag_payload().is_empty())
		var point: Vector2 = head.get_global_rect().get_center()
		_mouse_button(point, true)
		_mouse_button(point, false)
		await get_tree().process_frame
		assert(_panel._stash_pending.size() == n + 1)
		assert(_requests.size() == 1, "only the first request is sent before its response")
	assert(_panel._can_click_stash() and not _panel._can_interact())
	assert(_panel._drag_layer.get_child_count() == 3, "three flights coexist")
	assert(_panel._stash_pending[0].visual.immovable_icon.visible)
	assert(_panel._stash_pending[1].visual.level_label.text == "5")
	for n: int in range(3):
		assert(_panel._stash_pending[n].col == n + 2 and _panel._stash_pending[n].row == 0)
	# Reservations fill the board even while all authoritative target cells remain empty.
	_panel._place_stash(_panel._stash.get_child(0).get_child(0))
	assert(_panel._stash_pending.size() == 3 and _panel._status.text.contains("没有已揭雾空位"))
	assert(_panel._stash.get_child(0).get_child(0).data.item.uid == 1003)
	# A response between press and release must not swallow the next stash click.
	var head_point: Vector2 = _panel._stash.get_child(0).get_child(0).get_global_rect().get_center()
	_mouse_button(head_point, true)
	_ack(_requests[0])
	assert(not _find_cell(_panel, 2, 0).item_visual.visible, "fast response does not display a duplicate landing item")
	_panel._on_view(_authority)
	await get_tree().process_frame
	_mouse_button(head_point, false)
	assert(_panel._status.text.contains("没有已揭雾空位"), "click survives a response rebuilding its stash cell")
	assert(_requests.size() == 2 and _requests[1].version == 1 and _requests[1].uid == 1001)
	assert(_requests[0].request_id != _requests[1].request_id)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/realm-single-stash-flights.png")
	await get_tree().create_timer(0.4).timeout
	assert(_panel._stash_pending.size() == 2 and not _panel._can_interact(), "landed unconfirmed items retain reservations")
	assert(_find_cell(_panel, 2, 0).item_visual.visible)
	_ack(_requests[1])
	await get_tree().process_frame
	assert(_requests.size() == 3 and _requests[2].version == 2 and _requests[2].uid == 1002)
	_ack(_requests[2])
	await get_tree().process_frame
	assert(_panel._stash_pending.is_empty() and _panel._can_interact())
	assert(_panel._drag_layer.get_child_count() == 0)
	assert(_panel._view.stash.size() == 7)
	for n: int in range(3):
		var cell: Control = _find_cell(_panel, n + 2, 0)
		assert(int(cell.data.item.uid) == 1000 + n and cell.data.item.immovable == (n < 2))
	# An unconfirmed mutation clears flights and returns to auto-login.
	_panel._on_view(view)
	await get_tree().process_frame
	_panel._place_stash(_panel._stash.get_child(0).get_child(0))
	_panel._place_stash(_panel._stash.get_child(0).get_child(0))
	assert(_panel._stash_pending.size() == 2)
	CloudService.secret_realm_failed.emit("timeout")
	await get_tree().process_frame
	assert(_panel._stash_pending.is_empty() and _panel._drag_layer.get_child_count() == 0)
	assert(CloudService.relogin_pending and CloudService.secret_realm_retry.is_empty() and not _panel._can_click_stash())
	assert(_panel._stash.get_child(0).get_child(0).data.item.uid == 1000)
	# Closing cancels queued requests and flights, while CloudService retains the sent request.
	CloudService.relogin_pending = false
	CloudService.secret_realm_retry.clear()
	_panel._place_stash(_panel._stash.get_child(0).get_child(0))
	_panel._place_stash(_panel._stash.get_child(0).get_child(0))
	var sent_count: int = _requests.size()
	_panel.hide_animated()
	await get_tree().process_frame
	assert(_panel._stash_pending.is_empty() and _panel._drag_layer.get_child_count() == 0)
	assert(_requests.size() == sent_count and not CloudService.secret_realm_retry.is_empty())
	CloudService.secret_realm_busy = false
	CloudService.secret_realm_retry.clear()
	print("SECRET_REALM_STASH_BURST_SMOKE_OK: four groups, mixed other items, simultaneous flights, reserved UIDs/cells, serial versions, fast/slow replies, full board, failure, close")
	get_tree().quit()


func _capture_request(body: Dictionary) -> void:
	_requests.append(body.duplicate(true))
	# Replace the transport with a deliberately slow response; exercise the real panel queue.
	CloudService.secret_realm_busy = true
	CloudService.secret_realm_retry = body.duplicate(true)


func _ack(body: Dictionary) -> void:
	var item: Dictionary = {}
	for candidate: Dictionary in _authority.stash:
		if int(candidate.uid) == int(body.uid):
			item = candidate
	assert(not item.is_empty())
	_authority.stash.erase(item)
	for cell: Dictionary in _authority.cells:
		if cell.col == body.col and cell.row == body.row:
			cell.item = item
	_authority.version += 1
	var response: Dictionary = {"ok": true, "replayed": false, "secret_realm": _authority, "storage_revision": _authority.version}
	CloudService._sync_secret_realm(response)
	CloudService._on_secret_realm_response(response)
