extends "res://tests/secret_realm_online_smoke.gd"


func _ready() -> void:
	await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.codex_tmp/realm-http.json"))
	CloudService.base_url = fixture.base_url
	CloudService.token = fixture.token
	CloudService.online = true
	CloudService.secret_realm_state.clear()
	CloudService.secret_realm_revision = -1
	CloudService.secret_realm_retry.clear()
	CloudService.secret_realm_busy = false
	var main_grid := preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	UIManager.get_layer(UIManager.Layer.GAME).add_child(main_grid)
	_panel = preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(_panel)
	_panel.action_requested.connect(func(body: Dictionary) -> void: _requests.append(body))
	_panel.setup()
	for n: int in range(300):
		await get_tree().create_timer(0.02).timeout
		if _panel._view.get("initialized", false) and not CloudService.secret_realm_busy:
			break
	_check(_panel._view.get("initialized", false), "fetch push fixture")
	await get_tree().create_timer(0.3).timeout
	var left_uid: int = _find_cell(_panel,4,0).data.item.uid
	var right_uid: int = _find_cell(_panel,5,0).data.item.uid
	await _drag_and_commit(_find_cell(_panel,4,0), _find_cell(_panel,5,0))
	_check(_requests[-1].action == "move" and _find_cell(_panel,5,0).data.item.uid == left_uid and _find_cell(_panel,4,0).data.item.uid == right_uid, "max-level full-board swap retains both UIDs")
	var source_uid: int = _find_cell(_panel,0,7).data.item.uid
	var target_uid: int = _find_cell(_panel,2,4).data.item.uid
	await _drag_and_commit(_find_cell(_panel,0,7), _find_cell(_panel,2,4))
	_check(_find_cell(_panel,0,7).data.item.uid == target_uid and _find_cell(_panel,2,4).data.item.uid == source_uid, "full-board different-item swap")
	# Same-level fixed merge takes priority over displacement and frees a workspace.
	await _merge(_find_cell(_panel,2,4),3,4,"sword_2")
	var merged_uid: int = _find_cell(_panel,3,4).data.item.uid
	await _drag_and_commit(_find_cell(_panel,0,7), _find_cell(_panel,3,4))
	_check(_find_cell(_panel,3,4).data.item.uid == target_uid, "dragged item occupies its target")
	_check(_find_cell(_panel,2,4).data.item.uid == merged_uid, "target displaced into nearest existing empty cell")
	_check(_find_cell(_panel,0,7).data.get("item",{}).is_empty(), "existing vacancy used before source vacancy")
	_check(_panel._pending_merge.is_empty() and not is_instance_valid(_panel._loss_popup), "push never opens merge confirmation")
	# Different fixed targets still reject the same drag.
	await _drag_pointer(_find_cell(_panel,3,4), _find_cell(_panel,4,4))
	await get_tree().create_timer(0.3).timeout
	_check(_requests.size() == 4 and not main_grid._is_dragging, "fixed target rejection leaves requests and main board alone")
	await UIManager.hide_popup(_panel)
	print("SECRET_REALM_PUSH_ONLINE_SMOKE_OK: max/full swap; fixed merge priority; nearest push; UIDs; no confirmation; fixed rejection")
	get_tree().quit()
