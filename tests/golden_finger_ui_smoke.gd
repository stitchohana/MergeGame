extends Node

func _ready() -> void:
	call_deferred("_run")

func _info(level: int = 6) -> Dictionary:
	var offers: Array = []
	for definition: Dictionary in ConfigDatabase.golden_finger.get("artifacts", []):
		var offer: Dictionary = definition.duplicate(true)
		offer.merge({"unlocked": level >= int(definition.unlock_level), "free_remaining": int(definition.daily_free),
			"paid_remaining": 0, "remaining": int(definition.daily_free), "purchase_count": 0,
			"purchases_remaining": int(definition.daily_buy_limit), "next_cost": 100}, true)
		offers.append(offer)
	return {"version": 2, "storage_revision": 1, "golden_finger": {"artifacts": offers, "period_key": "2026-10-23",
		"next_reset_at": int(Time.get_unix_time_from_system() * 1000) + 60000},
		"materials": [{"id": 1001, "name": "雾芽草", "level": 1, "value": 1}, {"id": 1004, "name": "玉蟾芝", "level": 4, "value": 20}, {"id": 5001, "name": "露芽米", "level": 1, "value": 1}],
		"grid": [{"id": 1001, "uid": 1, "col": 0, "row": 0}, {"id": 1004, "uid": 2, "col": 1, "row": 0}]}

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.codex_tmp/" + name + ".png")

func _run() -> void:
	await get_tree().process_frame
	CloudService.online = false
	CultivationService.current_level = 6
	var screen := preload("res://scenes/screens/GameScreen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	var bar: HBoxContainer = screen.get_node("GoldenFingerBar")
	assert(bar.entries.size() == 3)
	var pouch: Control = screen.get_node("PouchDropZone")
	assert(bar.get_global_rect().end.x < pouch.get_global_rect().position.x)
	CloudService._sync_golden_finger(_info())
	await get_tree().process_frame
	var toasts: Array[String] = []
	EventBus.show_toast.connect(func(message: String): toasts.append(message))
	for artifact: String in ["basin", "furnace", "sand"]:
		var purchase_popup := preload("res://scenes/ui/main/GoldenFingerPopup.gd").new()
		purchase_popup.artifact_id = artifact
		UIManager.show_popup(purchase_popup)
		purchase_popup._on_info(_info())
		GameState.spirit_stones = 99
		var popup_count: int = UIManager._active_popups.size()
		purchase_popup._confirm_buy()
		assert(toasts.back().contains("灵石不足") and toasts.back().contains("100") and toasts.back().contains("99"))
		assert(UIManager._active_popups.size() == popup_count, "Insufficient funds must not open purchase confirmation")
		assert(not purchase_popup._pending and CloudService.golden_finger_retry.is_empty())
		GameState.spirit_stones = 100
		purchase_popup._confirm_buy()
		assert(UIManager._active_popups.size() == popup_count + 1, "Exact balance should allow purchase confirmation")
		(UIManager._active_popups.back() as ConfirmPopup)._on_cancel()
		await get_tree().create_timer(0.22).timeout
		purchase_popup._pending = true
		purchase_popup._on_failed("insufficient_stones")
		assert(toasts.back() == "灵石不足", "A server-side balance change must also show a toast")
		assert(not purchase_popup._pending)
		purchase_popup._close()
		await get_tree().create_timer(0.22).timeout
	await _capture("golden_finger_entries")
	for level: int in [1, 2, 3, 4, 5, 6, 19]:
		for id: String in ["basin", "furnace", "sand"]:
			var popup := preload("res://scenes/ui/main/GoldenFingerPopup.gd").new()
			popup.artifact_id = id
			UIManager.show_popup(popup)
			await get_tree().process_frame
			popup._on_info(_info(level))
			var threshold: int = {"basin": 2, "furnace": 4, "sand": 6}[id]
			assert(popup.enter_button.disabled == (level < threshold))
			assert(popup.title_label.text == str(popup.definition.name))
			assert(popup.info_label.text.contains(str(popup.definition.unlock_label)))
			assert(not popup.use_area.visible)
			if level == 6 and id == "basin":
				await _capture("golden_finger_intro")
			if level >= threshold:
				popup._enter_use()
				if id in ["basin", "furnace"]:
					assert(not popup.use_area.visible)
					await get_tree().create_timer(0.22).timeout
					assert(not is_instance_valid(popup))
					continue
				assert(popup.use_area.visible)
				assert(popup.use_button.disabled)
				if id == "furnace":
					assert(popup.target.item_count == 3)
				if id == "sand":
					assert(popup.mode.item_count == 2)
					popup.mode.select(1)
					popup._populate_choices()
					assert(popup._selection().mode == "rewind")
					assert(not popup.target.visible)
				if level == 6:
					await _capture("golden_finger_" + id)
					if id == "furnace":
						popup.preview = {"quote": {"ok": true}}
						popup.message_label.text = "将获得露芽米 ×1，放入物品暂存区。\n投入价值 80 · 目标价值 1 · 超额 79 不返还。"
						popup._confirm_use()
						await get_tree().process_frame
						await get_tree().process_frame
						await _capture("golden_finger_confirm")
						var confirm: ConfirmPopup = UIManager._active_popups.back() as ConfirmPopup
						assert(confirm != null)
						assert(confirm.message_label.get_global_rect().end.y <= confirm.confirm_btn.get_global_rect().position.y)
						confirm._on_cancel()
						await get_tree().create_timer(0.22).timeout
			popup._close()
			await get_tree().create_timer(0.22).timeout
			assert(not is_instance_valid(popup))
	# Older responses must not overwrite the current quota.
	CloudService.golden_finger_revision = 10
	CloudService._sync_golden_finger(_info())
	assert(CloudService.golden_finger_revision == 10)
	CloudService._sync_golden_finger({"storage_revision": 12})
	assert(CloudService.golden_finger_revision == 12)
	# Action success restores the authoritative board/resources and clears an uncertain retry.
	var authoritative: Dictionary = _info()
	authoritative.storage_revision = 13
	authoritative.spirit_stones = 8765
	authoritative.stamina = 47
	var old_item: Dictionary = ConfigDatabase.get_item_data(1004).duplicate(true)
	old_item["_uid"] = 9999
	GridManager.add_item(old_item, Vector2i(6, 8))
	CloudService.golden_finger_retry = {"action": "use", "body": {}}
	CloudService.golden_finger_busy = true
	CloudService._sync_golden_finger(authoritative)
	CloudService._on_golden_action(authoritative)
	assert(CloudService.golden_finger_retry.is_empty())
	assert(not CloudService.golden_finger_busy)
	assert(GameState.spirit_stones == 8765)
	assert(int(GridManager.get_item(Vector2i.ZERO).id) == 1001)
	assert(GridManager.is_empty(Vector2i(6, 8)), "consumed items must disappear after an authoritative artifact response")
	assert(GridManager.get_all_items().size() == 2)
	screen.queue_free()
	await get_tree().create_timer(0.4).timeout
	print("GOLDEN_FINGER_UI_SMOKE_OK entries unlock intro materials modes offline stale modal")
	get_tree().quit()
