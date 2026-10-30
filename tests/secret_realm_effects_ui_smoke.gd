extends "res://tests/secret_realm_ui_smoke.gd"

var _capture: bool = false


func _ready() -> void:
	await get_tree().process_frame
	_capture = "--capture-effects" in OS.get_cmdline_user_args()
	CloudService.online = false
	CloudService.secret_realm_state.clear()
	CloudService.secret_realm_retry.clear()
	CloudService.secret_realm_busy = false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/json_output/secret_realm.json"))
	var view: Dictionary = config.settings[0].duplicate(true)
	view.merge({"available": true, "initialized": true, "version": 0, "stage": 0, "start_row": 0,
		"items": config.items, "cells": [], "stash": [], "inventory": {}})
	for row: int in range(8):
		for col: int in range(6):
			view.cells.append({"col": col, "row": row, "fog": false})
	var enemy: Dictionary = {"id": "boss_6", "name": "剑墟守卫", "boss": true, "costs": [{"id": "sword_12", "count": 6}, {"id": "qi_6", "count": 1}]}
	view.cells[6 * 6 + 3].merge({"enemy": enemy, "monster": "boss_6", "submitted": {"sword_12": 6}})
	view.cells[0].item = {"uid": 1, "id": "qi_6", "immovable": false}
	view.cells[4 * 6].merge({"enemy": enemy, "monster": "hidden", "fog": true, "submitted": {"sword_12": 6}}, true)
	var panel := preload("res://scenes/ui/activity/SecretRealmPanel.tscn").instantiate() as SecretRealmPanel
	UIManager.show_popup(panel)
	panel._on_view(view)
	await get_tree().create_timer(0.3).timeout
	var monster: Control = _find_cell(panel, 3, 6)
	assert(monster.submitted_icons.size() == 6)
	for badge: Control in monster.submitted_icons:
		assert(badge.get_meta("item_id") == "sword_12")
		assert(badge.position.x >= 0 and badge.position.x + badge.size.x <= Constants.CELL_SIZE)
	assert(_find_cell(panel, 0, 4).submitted_icons.is_empty(), "fog never reveals submitted content")
	await _snapshot("submitted")
	monster.show_submissions({"sword_12": 2, "qi_6": 1})
	assert(monster.submitted_icons.size() == 3 and monster.submitted_icons[2].get_meta("item_id") == "qi_6")
	# Restoring a saved view builds individual icons again, without a new request.
	panel._render_board()
	monster = _find_cell(panel, 3, 6)
	assert(monster.submitted_icons.size() == 6)
	var confirmed: Dictionary = view.duplicate(true)
	confirmed.version = 1
	confirmed.cells[0].erase("item")
	confirmed.cells[6 * 6 + 3].erase("enemy")
	confirmed.cells[6 * 6 + 3].erase("monster")
	confirmed.cells[6 * 6 + 3].erase("submitted")
	var drops: Array = []
	for index: int in range(3):
		var item: Dictionary = {"uid": 100 + index, "id": "stamina_1" if index < 2 else "stone_1", "immovable": false}
		confirmed.cells[6 * 6 + 2 + index].item = item
		drops.append({"item": item, "col": 2 + index, "row": 6})
	var overflow: Dictionary = {"uid": 103, "id": "stone_1", "immovable": false}
	confirmed.stash.append(overflow)
	drops.append({"item": overflow, "stash": true})
	confirmed._effects = {"request_id": "kill", "kind": "fight", "col": 3, "row": 6, "defeated": true,
		"submitted": {"sword_12": 6, "qi_6": 1}, "drops": drops}
	panel._effect_request_id = "kill"
	panel._on_view(confirmed)
	assert(panel._reward_effects.phase == "attack" and panel._view.version == 0)
	assert(monster.submitted_icons.size() == 7 and not panel._can_interact())
	assert(panel.find_children("*", "Button", true, false).all(func(button: Button) -> bool: return button.text != "重试操作"))
	await get_tree().create_timer(0.15).timeout
	await _snapshot("attack")
	await get_tree().create_timer(0.38).timeout
	assert(panel._reward_effects.phase == "defeat")
	await get_tree().create_timer(0.3).timeout
	assert(panel._reward_effects.phase == "drops" and panel._reward_effects.drop_visuals.size() == 4)
	await get_tree().create_timer(0.08).timeout
	await _snapshot("drops")
	panel._on_view(confirmed)
	await get_tree().create_timer(0.75).timeout
	assert(not is_instance_valid(panel._reward_effects) and panel._view.version == 1 and panel._can_interact())
	assert(_find_cell(panel, 3, 6).data.get("monster", "").is_empty())
	assert(panel._view.stash.size() == 1)
	panel._on_view(confirmed)
	assert(not is_instance_valid(panel._reward_effects), "same response never repeats attack or drops")
	# A merge animates only its actual granted manifest, including fixed swords.
	var merged: Dictionary = confirmed.duplicate(true)
	merged.version = 2
	merged.erase("_effects")
	merged.cells[2 * 6 + 2].item = {"uid": 200, "id": "sword_7", "immovable": false}
	var merge_drops: Array = []
	for index: int in range(3):
		var item: Dictionary = {"uid": 201 + index, "id": ["qi_2", "sword_1", "sword_2"][index], "immovable": index > 0}
		merged.cells[1 * 6 + index].item = item
		merge_drops.append({"item": item, "col": index, "row": 1})
	merged.cells[2 * 6 + 3].item = {"uid": 50, "id": "sword_2", "immovable": true}
	merged._effects = {"request_id": "merge", "kind": "merge", "col": 2, "row": 2, "drops": merge_drops}
	panel._effect_request_id = "merge"
	panel._on_view(merged)
	assert(panel._reward_effects.phase == "drops" and panel._reward_effects.drop_visuals.size() == 3)
	assert(panel._reward_effects.drop_visuals[2].get_meta("drop_uid") == 203)
	await get_tree().create_timer(0.8).timeout
	assert(panel._view.version == 2 and panel._can_interact())
	# Failure rolls back the initial delivery without an attack or reward effect.
	panel._effect_request_id = "rejected"
	panel._present_drop(200, 0, 4)
	panel._on_failed("wrong_submission")
	assert(not is_instance_valid(panel._reward_effects) and panel._effect_request_id.is_empty())
	assert(_find_cell(panel, 2, 2).item_visual.visible)
	# Boss advancement starts after attack and rewards, including outgoing drops.
	var boss_view: Dictionary = merged.duplicate(true)
	boss_view.version = 3
	boss_view.erase("_effects")
	boss_view.cells[6 * 6 + 3].erase("item")
	boss_view.cells[6 * 6 + 3].merge({"enemy": enemy, "monster": "boss_6", "submitted": {"sword_12": 6}})
	panel._on_view(boss_view)
	var advanced: Dictionary = boss_view.duplicate(true)
	advanced.version = 4
	advanced.stage = 1
	advanced.start_row = 4
	advanced.cells = []
	for row: int in range(4, 12):
		for col: int in range(6):
			advanced.cells.append({"col": col, "row": row, "fog": row > 8})
	advanced._effects = {"request_id": "advance", "kind": "fight", "col": 3, "row": 6, "defeated": true,
		"submitted": {"sword_12": 6, "qi_6": 1}, "drops": []}
	panel._effect_request_id = "advance"
	panel._on_view(advanced)
	assert(panel._view.start_row == 0 and not panel._is_scrolling())
	await get_tree().create_timer(0.8).timeout
	assert(panel._view.start_row == 4 and panel._is_scrolling())
	await get_tree().create_timer(0.7).timeout
	assert(panel._can_interact())
	for col: int in range(6):
		var frontier: Control = _find_cell(panel, col, 8)
		assert(not frontier.data.fog, "the incoming area's bottom row stays revealed after scrolling")
		assert(frontier.position.y == 3 * Constants.CELL_STEP)
		assert(_find_cell(panel, col, 9).data.fog, "higher incoming rows keep their fog")
	# Closing midway cancels all effect tweens and discards deferred presentation.
	panel._on_view(boss_view)
	panel._effect_request_id = "advance"
	panel._on_view(advanced)
	assert(is_instance_valid(panel._reward_effects))
	await UIManager.hide_popup(panel)
	await get_tree().create_timer(0.85).timeout
	print("SECRET_REALM_EFFECTS_UI_SMOKE_OK: individual icons, fog, restore, attack/defeat/drop order, fixed/overflow drops, dedupe, rollback, Boss scroll, close cleanup")
	get_tree().quit()


func _snapshot(label: String) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.codex_tmp/realm-effects-%s.png" % label)
