extends Node


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	var bar: TopBar = preload("res://scenes/ui/common/TopBar.tscn").instantiate() as TopBar
	add_child(bar)
	await get_tree().process_frame
	GameState.spirit_stones = 1000
	bar.stamina_resource.get_node("AddButton").pressed.emit()
	var popup: ResourcePurchasePopup = UIManager._active_popups.back() as ResourcePurchasePopup
	assert(popup.resource == "stamina")
	assert(popup.title_label.text == "购买体力")
	assert(popup.confirm_btn.text == "重试")
	var quote: Dictionary = {"resource_purchase": {"period_key": "2026-10-14", "reset_hour": 5,
		"cost_increment": 100, "stamina": {"cost": 100, "amount": 100, "purchase_count": 0},
		"qi": {"cost": 200, "amount": 100, "purchase_count": 1}}}
	CloudService.resource_purchase_info_loaded.emit(quote)
	assert(popup.message_label.text.contains("100 体力"))
	assert(popup.confirm_btn.text == "100 灵石购买")
	popup.confirm_btn.pressed.emit()
	assert(not popup._pending)
	assert(not popup.confirm_btn.disabled)
	assert(GameState.spirit_stones == 1000)
	# A lost response may already have deducted stones on the server. Retry its
	# receipt even if a later state refresh shows insufficient remaining stones.
	var original_request_id: String = popup._request_id
	assert(not original_request_id.is_empty())
	GameState.spirit_stones = 0
	popup.confirm_btn.pressed.emit()
	assert(popup._request_id == original_request_id)
	assert(popup.confirm_btn.text == "重试购买")
	assert(not popup._pending)
	popup._on_cancel()
	await get_tree().create_timer(0.25).timeout
	assert(not is_instance_valid(popup))
	await get_tree().process_frame
	bar.qi_resource.get_node("AddButton").pressed.emit()
	popup = UIManager._active_popups.back() as ResourcePurchasePopup
	CloudService.resource_purchase_info_loaded.emit(quote)
	assert(popup.title_label.text == "购买灵力")
	assert(popup.message_label.text.contains("100 灵力"))
	assert(popup.confirm_btn.text == "200 灵石购买")
	popup._pending = true
	popup.confirm_btn.disabled = true
	popup.cancel_btn.disabled = true
	CloudService._on_resource_purchase_response({"ok": true, "resource": "qi", "amount": 100,
		"spirit_stones": 800, "stamina": 200, "max_stamina": 100,
		"cultivation": {"current_level": 1, "current_exp": 0, "total_exp": 0,
			"current_qi": 100, "max_qi": 1000}})
	assert(GameState.spirit_stones == 800)
	assert(GameState.stamina == 200)
	assert(CultivationService.current_qi == 100)
	await get_tree().create_timer(0.25).timeout
	assert(not is_instance_valid(popup))
	await get_tree().process_frame
	bar.stones_resource.get_node("AddButton").pressed.emit()
	assert(UIManager._active_popups.back() is ShopPopup)
	UIManager.hide_top_popup()
	await get_tree().create_timer(0.25).timeout
	print("TOPBAR_RESOURCE_PURCHASE_SMOKE_OK stamina qi shop quote offline sync")
	get_tree().quit()
