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
	if not _check(_panel._view.get("initialized", false), "fetch real grouped-stash layout"):
		return
	await get_tree().create_timer(0.3).timeout
	var supplied: Array = _panel._view.stash.duplicate(true)
	var click_order: Array[int] = [2, 3, 0, 1, 4, 5]
	for n: int in range(6):
		await _click_pointer(_find_stash(str(supplied[click_order[n]].id)))
		await get_tree().process_frame
		_check(not _panel._can_interact() and _panel._can_click_stash(), "only stash clicks remain available while requests and flights overlap")
	_check(_panel._stash.get_child_count() == 4, "four group slots remain displayed")
	_check(_panel._stash.get_child(0).get_child(0).data.is_empty() and _panel._stash.get_child(2).get_child(0).data.is_empty(), "exhausted groups keep empty slots")
	_check(_find_stash("sword_2").data.item.uid == supplied[6].uid and _find_stash("qi_1").data.item.uid == supplied[7].uid, "each group advances independently")
	_check(_panel._drag_layer.get_child_count() >= 2, "real delayed HTTP permits simultaneous flight visuals")
	var pending_count: int = _panel._stash_pending.size()
	await _click_pointer(_panel._stash.get_child(0).get_child(0))
	_check(_panel._stash_pending.size() <= pending_count and _requests.size() <= 6, "empty group does not reserve a flight or add a request")
	await _click_pointer(_find_stash("sword_2"))
	_check(_panel._status.text.contains("没有已揭雾空位"), "six reserved targets fill the board")
	for n: int in range(400):
		await get_tree().create_timer(0.02).timeout
		if _panel._view.version == 6 and _panel._can_interact():
			break
	_check(_panel._view.version == 6 and _panel._can_interact(), "six authoritative commits finish")
	_check(_requests.size() == 6 and _panel._view.stash.size() == 2, "one mutation per click, no duplicated items")
	var targets: Dictionary = {}
	for n: int in range(6):
		var body: Dictionary = _requests[n]
		_check(body.version == n and body.uid == supplied[click_order[n]].uid, "serial requests use latest version and the clicked group's UID")
		var key: Vector2i = Vector2i(int(body.col), int(body.row))
		_check(not targets.has(key), "every flight reserves a distinct empty cell")
		targets[key] = true
		var item: Dictionary = _find_cell(_panel, int(body.col), int(body.row)).data.item
		_check(item == supplied[click_order[n]], "committed item retains UID, level and fixed status")
	_check(_panel._drag_layer.get_child_count() == 0, "all flight nodes are released")
	await UIManager.hide_popup(_panel)
	print("SECRET_REALM_STASH_BURST_ONLINE_SMOKE_OK: four groups, six interleaved clicks, six serial authenticated commits, empty slots, unique cells, UID/locks, full board")
	get_tree().quit()
