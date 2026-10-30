extends "res://tests/secret_realm_ui_smoke.gd"

var _panel: SecretRealmPanel
var _expected_version: int = 0


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
	# Keep the actual main board alive to catch global input conflicts.
	var main_grid := preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	UIManager.get_layer(UIManager.Layer.GAME).add_child(main_grid)
	_panel = preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(_panel)
	_panel.action_requested.connect(func(body: Dictionary) -> void: _requests.append(body))
	_panel.setup()
	for n: int in range(300):
		await get_tree().create_timer(0.02).timeout
		if _panel._view.get("initialized", false):
			break
	if not _check(_panel._view.get("initialized", false), "fetch actual authenticated router view"):
		return
	await get_tree().create_timer(0.3).timeout
	# Stash dragging and a full-board click must never submit a request.
	var stash: Control = _find_stash("sword_2")
	var start: Vector2 = stash.get_global_rect().get_center()
	var finish: Vector2 = _find_cell(_panel,0,1).get_global_rect().get_center()
	_mouse_button(start,true)
	_mouse_move(start+Vector2(20,0),Vector2(20,0))
	_mouse_move(finish,finish-start-Vector2(20,0))
	_check(_panel._drag_source==null and stash.get_drag_payload().is_empty(), "stash never starts a drag")
	_mouse_button(finish,false)
	_check(_requests.is_empty(), "stash drag submits nothing")
	await _click_pointer(stash)
	_check(_requests.is_empty() and _panel._status.text.contains("没有已揭雾空位"), "full-board click keeps stash intact")
	# A full-board board merge still previews lost rewards before consuming.
	var before_cancel: Dictionary = _panel._view.duplicate(true)
	await _drag_pointer(_find_cell(_panel,3,1),_find_cell(_panel,3,0))
	for n: int in range(300):
		await get_tree().create_timer(0.02).timeout
		if is_instance_valid(_panel._loss_popup):
			break
	if not _check(is_instance_valid(_panel._loss_popup), "overflow requires confirmation"):
		return
	_check(_panel._loss_popup.message_label.text.contains("1级飞剑") and not _panel._loss_popup.message_label.text.contains("1级剑气"), "warning names only the reward that cannot fit")
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.codex_tmp/realm-space-warning.png")
	_check(not _panel._can_interact() and _requests.is_empty(), "warning blocks gameplay and consuming requests")
	_panel._loss_popup.cancel_btn.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	_check(_panel._view==before_cancel and _requests.is_empty(), "cancel preserves both instances and all rewards")
	await _merge(_find_cell(_panel,3,1),3,0,"sword_5")
	await _merge(_find_cell(_panel,0,0),0,1,"sword_2") # Fixed target unlocks.
	_check(_find_cell(_panel,0,0).data.get("item",{}).is_empty(), "level 2 produces no qi")
	await _merge(_find_cell(_panel,1,0),2,0,"sword_2") # Movable target.
	for spec: Array in [["sword",0,1],["qi",5,1],["stamina",5,2],["stone",3,2]]:
		var chain: String = spec[0]
		var col: int = spec[1]
		var row: int = spec[2]
		if chain != "sword":
			await _merge(_find_cell(_panel,col-1,row),col,row,chain+"_2")
		var placed: Control = await _click_and_commit(_find_stash(chain+"_2"))
		await _merge(placed,col,row,chain+"_3")
	# Explicitly fixed stash fixtures preserve their lock and UID on placement.
	var locked: Control = _find_stash("sword_1")
	var fixed_uid: int = int(locked.data.item.uid)
	var fixed: Control = await _click_and_commit(locked)
	_check(fixed.data.item.immovable and int(fixed.data.item.uid)==fixed_uid, "empty placement preserves lock and UID")
	_check(fixed.get_drag_payload().is_empty(), "fixed board source cannot drag")
	_check(not main_grid._is_dragging, "main board never handles realm drags")
	await UIManager.hide_popup(_panel)
	print("SECRET_REALM_ONLINE_SMOKE_OK: 15 commits; single stash click/flight/no-drag/full-board; board merge loss preview/cancel/confirm")
	get_tree().quit()


func _merge(source: Control, col: int, row: int, result_id: String) -> void:
	await _drag_and_commit(source,_find_cell(_panel,col,row))
	var item: Dictionary = _find_cell(_panel,col,row).data.get("item",{})
	_check(item.get("id","")==result_id and not item.get("immovable",true), "committed unlocked result: "+result_id)


func _drag_and_commit(source: Control, target: Control) -> void:
	await _drag_pointer(source,target)
	await _await_commit()


func _click_and_commit(source: Control) -> Control:
	var uid: int = int(source.data.item.uid)
	await _click_pointer(source)
	_check(not _panel._stash_pending.is_empty() and not _panel._can_interact(), "click starts an independent stash flight")
	var body: Dictionary = _requests[-1].duplicate(true)
	_check(body.action=="place" and int(body.uid)==uid, "click submits exactly the selected instance")
	await _await_commit()
	var cell: Control = _find_cell(_panel,int(body.col),int(body.row))
	_check(int(cell.data.item.uid)==uid, "authoritative placement retains selected UID")
	return cell


func _click_pointer(source: Control) -> void:
	var point: Vector2 = source.get_global_rect().get_center()
	_mouse_button(point,true)
	await get_tree().process_frame
	_mouse_button(point,false)


func _await_commit() -> void:
	_expected_version += 1
	for n: int in range(300):
		await get_tree().create_timer(0.02).timeout
		if is_instance_valid(_panel._loss_popup):
			_check(_requests.size()==_expected_version-1, "no commit before confirmation")
			_panel._loss_popup.confirm_btn.pressed.emit()
		if int(_panel._view.version)==_expected_version and _panel._can_interact():
			break
	_check(int(_panel._view.version)==_expected_version and _panel._can_interact(), "HTTP commit %d: %s" % [_expected_version,_panel._status.text])
	_check(_requests.size()==_expected_version, "one request per successful placement or merge")
	# The confirmation's close animation must finish before the next real press.
	await get_tree().create_timer(0.25).timeout


func _drag_pointer(source: Control, target: Control) -> void:
	if not _check(is_instance_valid(source) and is_instance_valid(target), "source and target exist"):
		return
	var start: Vector2 = source.get_global_rect().get_center()
	var finish: Vector2 = target.get_global_rect().get_center()
	_mouse_button(start,true)
	await get_tree().process_frame
	_mouse_move(start+Vector2(20,0),Vector2(20,0))
	await get_tree().process_frame
	_mouse_move(finish,finish-start-Vector2(20,0))
	await get_tree().process_frame
	_check(is_instance_valid(_panel._drag_source), "shared controller starts the drag")
	_mouse_button(finish,false)


func _find_stash(id: String) -> Control:
	for cell: Control in _panel._all_cells():
		if cell.from_stash and cell.data.get("item",{}).get("id","")==id:
			return cell
	return null


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("SECRET_REALM_ONLINE_SMOKE_FAILED: "+message)
		get_tree().quit(1)
	return condition
