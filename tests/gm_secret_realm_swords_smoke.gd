extends Node


func _ready() -> void:
	var panel: GMPanel = preload("res://scenes/ui/other/GMPanel.tscn").instantiate() as GMPanel
	add_child(panel)
	var command_index: int = -1
	for index: int in range(panel.command_buttons.size()):
		if panel.command_buttons[index].text == "添加秘境飞剑":
			command_index = index
	assert(command_index >= 0)
	panel.command_buttons[command_index].pressed.emit()
	assert(panel.command_buttons[command_index].button_pressed)
	assert(not panel.command_buttons[0].button_pressed)
	assert(panel.level_spin.visible and panel.level_label.visible)
	assert(panel.amount_spin.editable and panel.amount_label.text == "数量（把）")
	assert(panel.amount_spin.min_value == 1 and panel.amount_spin.max_value == 1000)
	assert(panel.level_spin.min_value == 1 and panel.level_spin.max_value == 12)
	panel.amount_spin.value = 3
	panel.level_spin.value = 7
	CloudService._busy = true
	panel._on_exec()
	assert(CloudService._request_queue.size() == 1)
	var request: Dictionary = CloudService._request_queue.pop_front()
	var body: Dictionary = JSON.parse_string(request.body)
	assert(request.path == "/api/gm/exec")
	assert(body.cmd == "add_secret_realm_swords" and int(body.amount) == 3 and int(body.level) == 7)
	assert(panel.exec_btn.disabled)
	CloudService._busy = false
	CloudService._state_request_in_flight = true
	CloudService.secret_realm_revision = -1
	CloudService._on_gm_exec_response({"ok": true, "msg": "已添加 3 把 7 级飞剑到秘境暂存", "storage_revision": 42,
		"secret_realm": {"version": 5, "stash": [{"uid": 999, "id": "sword_7", "immovable": false}]}})
	assert(not panel.exec_btn.disabled and panel.result_label.text.contains("3 把 7 级飞剑"))
	assert(CloudService.secret_realm_revision == 42)
	assert(CloudService.secret_realm_state.stash[0].id == "sword_7")
	CloudService._on_gm_exec_response({"ok": true, "storage_revision": 41, "secret_realm": {"stash": []}})
	assert(CloudService.secret_realm_state.stash.size() == 1, "old GM responses cannot erase newer realm state")
	CloudService._state_request_in_flight = false
	panel._on_cmd_selected(0)
	assert(not panel.level_spin.visible and not panel.level_label.visible)
	assert(panel.amount_label.text == "数值" and panel.amount_spin.max_value == 999999)
	panel.queue_free()
	print("GM_SECRET_REALM_SWORDS_UI_SMOKE_OK fields submission sync stale_response command_switch")
	get_tree().quit()
