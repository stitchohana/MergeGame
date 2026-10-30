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
	_panel = preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(_panel)
	_panel.action_requested.connect(func(body: Dictionary) -> void: _requests.append(body.duplicate(true)))
	_panel.setup()
	for n: int in range(300):
		await get_tree().create_timer(0.02).timeout
		if _panel._view.get("initialized", false):
			break
	if not _check(_panel._view.get("initialized", false), "load real merge layout"):
		return
	await get_tree().create_timer(0.3).timeout
	await _drag_pointer(_find_cell(_panel, 0, 0), _find_cell(_panel, 1, 0))
	for n: int in range(200):
		await get_tree().create_timer(0.005).timeout
		if _panel._is_drop_animating():
			break
	_check(_panel._is_drop_animating() and _panel._can_drag_board(), "first merge animates while the board accepts another drag")
	await _drag_pointer(_find_cell(_panel, 2, 0), _find_cell(_panel, 3, 0))
	_check(_panel._queued_drops.size() == 1, "second real drop is accepted during the first animation")
	var held_uid: int = int(_find_cell(_panel, 4, 0).data.item.uid)
	var start: Vector2 = _find_cell(_panel, 4, 0).get_global_rect().get_center()
	_mouse_button(start, true)
	_mouse_move(start + Vector2(30, 0), Vector2(30, 0))
	var position: Vector2 = _panel._drag_source.item_visual.position
	for n: int in range(200):
		await get_tree().create_timer(0.01).timeout
		if _panel._view.version == 1:
			break
	_check(is_instance_valid(_panel._drag_source) and int(_panel._drag_source.data.item.uid) == held_uid, "held item survives real response/loot completion")
	_check(_panel._drag_source.item_visual.position.is_equal_approx(position), "held item stays under the same pointer")
	_check(_requests.size() == 1, "queue waits while a pointer drag is active")
	_mouse_button(start, false)
	for n: int in range(400):
		await get_tree().create_timer(0.01).timeout
		if _panel._view.version == 2 and _panel._can_interact():
			break
	_check(_panel._view.version == 2 and _panel._can_interact(), "both merges commit once")
	_check(_requests.size() == 2 and _requests[0].version == 0 and _requests[1].version == 1, "queued merge uses the latest version")
	for col: int in [1, 3]:
		_check(_find_cell(_panel, col, 0).data.item.id == "sword_5", "each merge produces one level 5 sword")
	_check(_panel._queued_drops.is_empty() and _panel._drag_layer.get_child_count() == 0, "no queued input or visual nodes remain")
	await UIManager.hide_popup(_panel)
	print("SECRET_REALM_MERGE_DRAG_ONLINE_SMOKE_OK: real pointer merge during animation, two authenticated commits, continuous held drag, versions, drops")
	get_tree().quit()
