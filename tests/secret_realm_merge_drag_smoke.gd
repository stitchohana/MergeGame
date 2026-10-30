extends "res://tests/secret_realm_ui_smoke.gd"


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = true
	CloudService.secret_realm_state.clear()
	CloudService.secret_realm_retry.clear()
	CloudService.secret_realm_busy = false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/secret_realm.json"))
	var view: Dictionary = config.settings[0].duplicate(true)
	view.merge({"available": true, "initialized": true, "version": 0, "stage": 0, "start_row": 0,
		"items": config.items, "cells": [], "stash": [], "inventory": {}})
	for row: int in range(8):
		for col: int in range(6):
			var cell: Dictionary = {"col": col, "row": row, "fog": false}
			if row == 0:
				cell.item = {"uid": col + 1, "id": "sword_1", "immovable": false}
			view.cells.append(cell)
	var panel := preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(panel)
	panel._on_view(view)
	# Suppress transport while retaining the panel's real animation and transaction path.
	panel.action_requested.connect(func(body: Dictionary) -> void:
		_requests.append(body.duplicate(true))
		CloudService.secret_realm_busy = true
		CloudService.secret_realm_retry = body.duplicate(true)
	)
	await get_tree().create_timer(0.3).timeout
	panel._present_drop(1, 1, 0)
	panel._effect_request_id = "first-merge"
	CloudService.secret_realm_busy = true
	CloudService.secret_realm_retry = {"request_id": "first-merge"}
	assert(panel._is_drop_animating() and panel._can_drag_board())
	assert(_find_cell(panel, 0, 0).get_drag_payload().is_empty(), "consumed source cannot be dragged twice")
	assert(_find_cell(panel, 1, 0).get_drag_payload().is_empty(), "merging target is reserved")
	var first: Dictionary = view.duplicate(true)
	first.version = 1
	first.cells[0].erase("item")
	first.cells[1].item = {"uid": 100, "id": "sword_2", "immovable": false}
	first.cells[6].item = {"uid": 101, "id": "sword_1", "immovable": true}
	first._effects = {"kind": "merge", "request_id": "first-merge", "col": 1, "row": 0,
		"drops": [{"item": first.cells[6].item, "col": 0, "row": 1}]}
	# Begin the next drag while the first merge is still scaling.
	var start: Vector2 = _find_cell(panel, 2, 0).get_global_rect().get_center()
	var finish: Vector2 = _find_cell(panel, 3, 0).get_global_rect().get_center()
	_mouse_button(start, true)
	_mouse_move(start + Vector2(24, 0), Vector2(24, 0))
	assert(is_instance_valid(panel._drag_source) and panel._drag_source.data.item.uid == 3)
	CloudService.secret_realm_busy = false
	CloudService.secret_realm_retry.clear()
	panel._on_view(first)
	await get_tree().create_timer(Constants.SPAWN_ANIM_DURATION + 0.03).timeout
	assert(is_instance_valid(panel._reward_effects) and panel._can_drag_board(), "merge reward flight also permits dragging")
	assert(not _find_cell(panel, 0, 1).can_accept(panel._drag_payload), "reward landing cells stay reserved")
	_mouse_move(finish, finish - start - Vector2(24, 0))
	_mouse_button(finish, false)
	assert(panel._queued_drops.size() == 1 and _requests.is_empty(), "release is queued without submitting a stale version")
	assert(_find_cell(panel, 2, 0).get_drag_payload().is_empty(), "queued source cannot be queued twice")
	# Drag a third item across the response-driven board rebuild without losing the pointer.
	start = _find_cell(panel, 4, 0).get_global_rect().get_center()
	_mouse_button(start, true)
	_mouse_move(start + Vector2(28, 0), Vector2(28, 0))
	assert(panel._drag_source.data.item.uid == 5)
	var position: Vector2 = panel._drag_source.item_visual.position
	await get_tree().create_timer(0.45).timeout
	assert(panel._view.version == 1 and not is_instance_valid(panel._reward_effects))
	assert(panel._drag_source.data.item.uid == 5 and panel._drag_source.item_visual.position.is_equal_approx(position))
	assert(panel._queued_drops.size() == 1, "no new request rebuilds the board underneath an active drag")
	_mouse_button(start, false)
	await get_tree().process_frame
	assert(panel._queued_drops.is_empty() and panel._pending_merge.uid == 3)
	assert(panel._pending_merge.version == 1, "queued merge rechecks rewards with the latest authoritative version")
	var preview: Dictionary = panel._pending_merge.duplicate(true)
	preview.lost_drops = []
	CloudService._on_secret_realm_preview(preview)
	assert(_requests.size() == 1 and _requests[0].version == 1 and _requests[0].uid == 3)
	assert(panel._is_drop_animating() and panel._can_drag_board())
	# Failure cancels remaining intent and follows the existing retry path.
	panel._drop(5, 5, 0, false)
	assert(panel._queued_drops.size() == 1)
	panel._on_failed("timeout")
	assert(panel._queued_drops.is_empty() and not panel._can_drag_board())
	CloudService.secret_realm_busy = false
	CloudService.secret_realm_retry.clear()
	panel._on_view(first)
	# A queued move must not turn into an unintended merge when a new drop fills its target.
	panel._present_drop(3, 3, 0)
	panel._drop(5, 2, 1, false)
	assert(panel._queued_drops.size() == 1)
	var filled: Dictionary = first.duplicate(true)
	filled.version = 2
	filled.erase("_effects")
	filled.cells[2].erase("item")
	filled.cells[3].item = {"uid": 200, "id": "sword_2", "immovable": false}
	filled.cells[8].item = {"uid": 201, "id": "sword_1", "immovable": true}
	panel._on_view(filled)
	await get_tree().create_timer(Constants.SPAWN_ANIM_DURATION + 0.05).timeout
	assert(panel._queued_drops.is_empty() and _requests.size() == 1, "changed target cancels stale intent without consuming anything")
	assert(_find_cell(panel, 4, 0).data.item.uid == 5)
	# Combat and map scrolling continue to block all board dragging.
	var combat: Dictionary = first.duplicate(true)
	combat.version = 3
	combat.cells[12].merge({"monster": "mob_1", "enemy": config.monsters[0]})
	panel._on_view(combat)
	panel._present_drop(5, 0, 2)
	assert(not panel._can_drag_board())
	panel._on_failed("wrong_submission")
	var advanced: Dictionary = first.duplicate(true)
	advanced.version = 4
	advanced.start_row = 4
	advanced.cells = []
	for row: int in range(4, 12):
		for col: int in range(6):
			advanced.cells.append({"col": col, "row": row, "fog": row > 8})
	panel._on_view(advanced)
	assert(panel._is_scrolling() and not panel._can_drag_board())
	await get_tree().create_timer(0.65).timeout
	panel._on_view(view)
	panel._present_drop(1, 1, 0)
	panel._drop(3, 3, 0, false)
	assert(panel._queued_drops.size() == 1)
	await UIManager.hide_popup(panel)
	assert(panel._queued_drops.is_empty() and panel._drag_source == null and not panel._is_drop_animating())
	print("SECRET_REALM_MERGE_DRAG_SMOKE_OK: merge/loot drag, reserved cells, queued version, pointer through rebuild, failure, combat/scroll lock")
	get_tree().quit()
