extends "res://tests/secret_realm_ui_smoke.gd"


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	CloudService.secret_realm_state.clear()
	CloudService.secret_realm_retry.clear()
	CloudService.secret_realm_busy = false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/secret_realm.json"))
	var view: Dictionary = config.settings[0].duplicate(true)
	view.merge({"available": true, "initialized": true, "version": 0, "stage": 0, "start_row": 0,
		"items": config.items, "cells": [], "stash": [], "inventory": {}})
	for y: int in range(8):
		for x: int in range(6):
			view.cells.append({"col": x, "row": 7-y, "fog": false,
				"item": {"uid": 1+y*6+x, "id": "sword_1", "immovable": true}})
	var panel := preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(panel)
	panel.action_requested.connect(func(body: Dictionary) -> void: _requests.append(body))
	var source_data: Dictionary = view.cells[0]
	source_data.item.immovable = false
	var target_data: Dictionary = view.cells[3*6+2]
	target_data.item = {"uid": 900, "id": "qi_1", "immovable": false}
	var empty_data: Dictionary = view.cells[3*6+3]
	empty_data.erase("item")
	panel._on_view(view)
	await get_tree().create_timer(0.3).timeout
	var source: Control = _find_cell(panel, 0, 7)
	var target: Control = _find_cell(panel, 2, 4)
	var destination: Control = _find_cell(panel, 3, 4)
	assert(target.can_accept(source.get_drag_payload()))
	assert(panel._push_destination(source, target) == destination)
	var gap: Vector2 = source.get_global_transform_with_canvas() * Vector2(Constants.CELL_SIZE+1, 20)
	assert(panel._cell_at(gap) == source, "gap hit testing follows the main board cell step")
	# Same BFS used by the actual main board yields right, left, down, up ties.
	GridManager.init_grid()
	var full: Array = []
	for y: int in range(Constants.GRID_ROWS):
		for x: int in range(Constants.GRID_COLS):
			if Vector2i(x,y) in [Vector2i(3,3), Vector2i(1,3), Vector2i(2,4), Vector2i(2,2)]:
				continue
			full.append({"id":1001,"uid":2000+y*Constants.GRID_COLS+x,"col":x,"row":y})
	GridManager.populate_from_server(full)
	assert(GridManager.find_nearest_empty(Vector2i(2,3)) == Vector2i(3,3))
	assert(GridManager.find_nearest_empty_after_removing(Vector2i(2,3), Vector2i(2,3)) == Vector2i(2,3))
	# A real pointer drop routes to move immediately; it is never a merge preview.
	var start: Vector2 = source.get_global_rect().get_center()
	var finish: Vector2 = target.get_global_rect().get_center()
	_mouse_button(start, true)
	await get_tree().process_frame
	_mouse_move(start+Vector2(20,0), Vector2(20,0))
	await get_tree().process_frame
	_mouse_move(finish, finish-start-Vector2(20,0))
	await get_tree().process_frame
	_mouse_button(finish, false)
	await get_tree().process_frame
	assert(_requests.size() == 1 and _requests[0].action == "move" and panel._pending_merge.is_empty())
	assert(panel._view == view and _find_cell(panel, 0, 7).item_visual.visible, "offline rejection restores both items")
	source = _find_cell(panel, 0, 7)
	target = _find_cell(panel, 2, 4)
	destination = _find_cell(panel, 3, 4)
	var dragged: GridItem = source.item_visual
	var displaced: GridItem = target.item_visual
	panel._present_drop(int(source_data.item.uid), 2, 4)
	assert(panel._view == view and panel._is_drop_animating())
	assert(target.item_visual == dragged and destination.item_visual == displaced)
	assert(dragged.position == Vector2.ZERO and displaced.position != Vector2.ZERO)
	var confirmed: Dictionary = view.duplicate(true)
	confirmed.version = 1
	confirmed.cells[0].erase("item")
	confirmed.cells[3*6+2].item = source_data.item.duplicate(true)
	confirmed.cells[3*6+3].item = target_data.item.duplicate(true)
	panel._on_view(confirmed)
	assert(panel._view.version == 0, "fast response waits for the shared 0.15 second slide")
	await get_tree().create_timer(0.2).timeout
	assert(panel._view.version == 1 and panel._can_interact())
	assert(_find_cell(panel, 2, 4).data.item.uid == source_data.item.uid)
	assert(_find_cell(panel, 3, 4).data.item.uid == 900)
	# Full board fallback swaps movable items, including identical max-level pairs.
	var full_view: Dictionary = view.duplicate(true)
	full_view.version = 2
	full_view.cells[0].item.id = "sword_12"
	full_view.cells[3*6+2].item.id = "sword_12"
	full_view.cells[3*6+3].item = {"uid":901,"id":"qi_1","immovable":true}
	panel._on_view(full_view)
	source = _find_cell(panel, 0, 7)
	target = _find_cell(panel, 2, 4)
	assert(target.can_accept(source.get_drag_payload()) and panel._push_destination(source, target) == source)
	dragged = source.item_visual
	displaced = target.item_visual
	panel._present_drop(int(source_data.item.uid), 2, 4)
	assert(target.item_visual == dragged and source.item_visual == displaced)
	assert(dragged.position != Vector2.ZERO and displaced.position != Vector2.ZERO)
	await get_tree().create_timer(0.2).timeout
	assert(dragged.position.is_equal_approx(Vector2.ZERO) and displaced.position.is_equal_approx(Vector2.ZERO))
	panel._on_failed("timeout")
	assert(_find_cell(panel, 0, 7).data.item.uid == source_data.item.uid)
	assert(_find_cell(panel, 2, 4).data.item.uid == 900)
	await UIManager.hide_popup(panel)
	print("SECRET_REALM_PUSH_UI_SMOKE_OK: shared BFS and slide; pointer push; gap hits; full/max swap; response deferral; rollback")
	get_tree().quit()
