extends "res://tests/secret_realm_online_smoke.gd"

var _effect_phases: Dictionary = {}
var _animated_drops: Dictionary = {}


func _process(_delta: float) -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_panel._reward_effects):
		return
	_effect_phases[_panel._reward_effects.phase] = true
	for visual: GridItem in _panel._reward_effects.drop_visuals:
		_animated_drops[int(visual.get_meta("drop_uid"))] = true


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
	await _open_combat_panel()
	_check_boss_seal(true)
	# Wrong grades and locked Bosses snap back without a consuming request.
	await _drag_pointer(_find_cell(_panel, 4, 0), _find_cell(_panel, 1, 4))
	await get_tree().create_timer(0.3).timeout
	_check(_requests.is_empty(), "wrong sword level submits nothing")
	await _drag_pointer(_find_cell(_panel, 4, 0), _find_cell(_panel, 3, 6))
	await get_tree().create_timer(0.3).timeout
	_check(_requests.is_empty(), "Boss rejects drops while mobs remain")
	await _drag_and_commit(_find_cell(_panel, 0, 0), _find_cell(_panel, 1, 4))
	_check(_find_cell(_panel, 1, 4).data.get("submitted", {}).get("sword_4", 0) == 1, "first sword persisted")
	_check(_find_cell(_panel, 1, 4).submitted_icons.size() == 1 and _find_cell(_panel, 1, 4).submitted_icons[0].get_meta("item_id") == "sword_4", "submitted sword is shown as an individual icon")
	_check(_find_cell(_panel, 1, 4).data.get("monster", "") == "mob_1", "partial submission keeps the mob alive")
	_check(_panel._detail.text.contains("4级飞剑 1/1"), "detail immediately shows submitted quantity")
	await _drag_pointer(_find_cell(_panel, 2, 0), _find_cell(_panel, 1, 4))
	await get_tree().create_timer(0.3).timeout
	_check(_requests.size() == 1, "filled requirement rejects extra sword")
	# Close and fetch the saved partial quantities in a fresh panel.
	await UIManager.hide_popup(_panel)
	await _open_combat_panel()
	_check(_find_cell(_panel, 1, 4).data.get("submitted", {}).get("sword_4", 0) == 1, "reopening retains partial delivery")
	_check(_find_cell(_panel, 1, 4).submitted_icons.size() == 1, "reopening restores submitted icons")
	await _drag_and_commit(_find_cell(_panel, 2, 0), _find_cell(_panel, 4, 4))
	await _drag_and_commit(_find_cell(_panel, 1, 0), _find_cell(_panel, 1, 4))
	_check(_panel._view.remaining_mobs == 1, "last required item defeats exactly one mob")
	_check_boss_seal(true)
	await _drag_and_commit(_find_cell(_panel, 3, 0), _find_cell(_panel, 4, 4))
	_check(_panel._view.remaining_mobs == 0, "both mobs defeated")
	_check_boss_seal(false)
	await UIManager.hide_popup(_panel)
	await _open_combat_panel()
	_check_boss_seal(false)
	await _drag_and_commit(_find_cell(_panel, 4, 0), _find_cell(_panel, 3, 6))
	_check(_panel._view.stage == 0 and _find_cell(_panel, 3, 6).data.submitted.sword_7 == 1, "partial Boss submission does not advance")
	var before_advance: Dictionary = _panel._view.duplicate(true)
	var final_uid: int = int(_find_cell(_panel, 5, 0).data.item.uid)
	await _drag_and_commit(_find_cell(_panel, 5, 0), _find_cell(_panel, 3, 6))
	_check(_panel._view.stage == 1 and _panel._view.start_row == 4, "final qi defeats Boss and advances")
	_check_recovery(before_advance, final_uid)
	for col: int in range(6):
		_check(not _find_cell(_panel, col, 4).data.fog, "new bottom row is revealed")
	_check(_requests.size() == 6 and not main_grid._is_dragging, "one submission per drag; main board stays idle")
	_check(_effect_phases.has("attack") and _effect_phases.has("defeat") and _effect_phases.has("drops"), "real HTTP confirmations play all three combat phases")
	_check(_animated_drops.size() == 12, "all twelve rewards from two mobs and the Boss animate once")
	var saved_stash: Array = _panel._view.stash.duplicate(true)
	var saved_cells: Array = _panel._view.cells.duplicate(true)
	await UIManager.hide_popup(_panel)
	await _open_combat_panel()
	_check(_panel._view.stash == saved_stash and _panel._view.cells == saved_cells, "reopening preserves recovered stash and board without a second recovery")
	for spec: Array in [["sword_2", 0, 4, "sword_3"], ["qi_2", 5, 7, "qi_3"]]:
		var recovered: Control = _find_stash(str(spec[0]))
		_check(is_instance_valid(recovered) and not recovered.data.item.immovable, "recovered fixed items are unlocked in stash")
		var placed: Control = await _click_and_commit(recovered)
		_check(not placed.data.item.immovable and not placed.get_drag_payload().is_empty(), "recovered items remain draggable after clicking into the board")
		await _merge(placed, int(spec[1]), int(spec[2]), str(spec[3]))
	await UIManager.hide_popup(_panel)
	print("SECRET_REALM_COMBAT_ONLINE_SMOKE_OK: deliveries; reload; rejection; rewards; advance; recovery unlock; recovered sword/qi click and drag merge")
	get_tree().quit()


func _check_recovery(before: Dictionary, consumed_uid: int) -> void:
	var after: Dictionary = _panel._view
	var board: Dictionary = {}
	var stash: Dictionary = {}
	for cell: Dictionary in after.cells:
		if cell.has("item"):
			var uid: int = int(cell.item.uid)
			_check(not board.has(uid), "board UIDs remain unique")
			board[uid] = cell.item
	for item: Dictionary in after.stash:
		var uid: int = int(item.uid)
		_check(not stash.has(uid) and not board.has(uid), "each recovered UID exists exactly once")
		stash[uid] = item
	for item: Dictionary in before.stash:
		_check(stash.get(int(item.uid), {}) == item, "existing stash survives advancement")
	for cell: Dictionary in before.cells:
		if not cell.has("item"):
			continue
		var uid: int = int(cell.item.uid)
		if uid == consumed_uid:
			_check(not stash.has(uid) and not board.has(uid), "submitted qi is consumed rather than recovered")
		elif int(cell.row) < int(after.start_row):
			var recovered: Dictionary = cell.item.duplicate(true)
			recovered.immovable = false
			_check(stash.get(uid, {}) == recovered and not board.has(uid), "outgoing items retain UID and grade but become movable")
		else:
			_check(board.get(uid, {}) == cell.item and not stash.has(uid), "overlap items remain on the board")
	for drop: Dictionary in after.get("_effects", {}).get("drops", []):
		_check(board.get(int(drop.item.uid), stash.get(int(drop.item.uid), {})) == drop.item, "Boss rewards survive even when their landing cells leave the viewport")


func _check_boss_seal(locked: bool) -> void:
	for col: int in range(2, 5):
		for row: int in range(5, 8):
			var cell: Control = _find_cell(_panel, col, row)
			_check(bool(cell.data.fog) == locked, "all nine Boss cells reveal only after the final mob")
			_check(cell.has_node("SpecialFogSeal") == locked, "seal visuals follow authoritative fog")
			if locked:
				_check(cell.data.get("special_fog", false) and not cell.data.has("monster") and not cell.data.has("item"), "special fog hides occupants")


func _open_combat_panel() -> void:
	_panel = preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(_panel)
	_panel.action_requested.connect(func(body: Dictionary) -> void: _requests.append(body))
	_panel.setup()
	for n: int in range(300):
		await get_tree().create_timer(0.02).timeout
		if _panel._view.get("initialized", false) and not CloudService.secret_realm_busy:
			break
	_check(_panel._view.get("initialized", false), "fetch authenticated combat state")
	await get_tree().create_timer(0.3).timeout
