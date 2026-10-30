extends Node

func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	GridManager.init_grid()
	var popup: ShopPopup = preload("res://scenes/ui/shop/ShopPopup.tscn").instantiate() as ShopPopup
	add_child(popup)
	popup.show()
	popup.modulate = Color.WHITE
	assert(not popup._pending)
	assert(popup.refresh_btn.text == "重新加载")
	var quote: Dictionary = {"revision": 1, "remaining_seconds": 14400, "refresh_cost": 100,
		"items": [
			{"id": 1001, "price": 10, "remaining": 5, "purchase_limit": 5, "order_required": true},
			{"id": 1002, "price": 30, "remaining": 0, "purchase_limit": 5},
		]}
	CloudService._on_shop_items_response(quote)
	assert(popup.refresh_btn.text == "刷新全部 · 100 灵石")
	assert(popup.countdown_label.text.contains("4时"))
	assert(popup._buy_buttons.size() == 2)
	assert(not popup._buy_buttons[0].disabled)
	assert(popup._buy_buttons[1].disabled)
	assert(popup._buy_buttons[1].text == "已售罄")
	var entry: Node = popup.item_container.get_child(0)
	assert((entry.get_child(1) as Label).text == "订单需要")
	assert((entry.get_child(2) as Label).text == "剩余 5/5 次")
	GameState.spirit_stones = 99
	popup._on_refresh_pressed()
	assert(not popup._pending)
	GameState.spirit_stones = 1000
	popup._on_refresh_pressed()
	assert(not popup._pending)
	assert(not CloudService.shop_busy)
	assert(GameState.spirit_stones == 1000)
	popup._on_buy_pressed(1001, 10)
	assert(not popup._pending)
	assert(not CloudService.shop_busy)
	CloudService.shop_busy = true
	popup._update_controls()
	assert(popup.refresh_btn.disabled)
	assert(popup._buy_buttons[0].disabled)
	CloudService._on_shop_error("network_error")
	popup._update_controls()
	assert(not popup.refresh_btn.disabled)
	var buy_shop: Dictionary = quote.duplicate(true)
	buy_shop.items[0].remaining = 4
	CloudService._on_buy_response({"ok": true, "item_id": 1001, "uid": 12345,
		"target_col": 3, "target_row": 3, "spirit_stones": 990, "shop": buy_shop})
	assert(GameState.spirit_stones == 990)
	assert(GridManager.find_by_uid(12345).get("id", 0) == 1001)
	assert(((popup.item_container.get_child(0)).get_child(2) as Label).text == "剩余 4/5 次")
	# Closing the popup must not lose a purchase result.
	popup.queue_free()
	await get_tree().process_frame
	CloudService._on_buy_response({"ok": true, "item_id": 1001, "uid": 12346,
		"target_col": 4, "target_row": 3, "spirit_stones": 980, "shop": buy_shop})
	assert(GridManager.find_by_uid(12346).get("id", 0) == 1001)
	assert(GameState.spirit_stones == 980)
	popup = preload("res://scenes/ui/shop/ShopPopup.tscn").instantiate() as ShopPopup
	add_child(popup)
	CloudService._on_shop_items_response(quote)
	popup._received_ticks -= 14400000
	assert(popup._seconds_left() == 0)
	var refreshed: Dictionary = quote.duplicate(true)
	refreshed.revision = 2
	CloudService._on_shop_refresh_response({"ok": true, "spirit_stones": 880,
		"revision": 2, "remaining_seconds": 14400, "refresh_cost": 100, "items": refreshed.items})
	assert(popup._revision == 2)
	assert(popup._seconds_left() == 14400)
	assert(GameState.spirit_stones == 880)
	CloudService.shop_updated.emit(quote)
	assert(popup._revision == 2)
	popup.show_items([])
	assert(popup.item_container.get_child_count() == 1)
	assert((popup.item_container.get_child(0) as Label).text == "暂无商品")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			var entries: Array = []
			for item_id: int in [1006, 5003, 9003, 5001, 9001, 1001, 1002, 2001, 2002,
				5002, 7001, 1005, 2005, 5005, 15101, 15201, 7002, 9002, 1003, 2003, 5004, 9004, 7003, 7004]:
				entries.append({"id": item_id, "price": 100, "remaining": 0 if item_id == 2002 else 5,
					"purchase_limit": 5, "order_required": item_id in [1006, 5003, 9003]})
			popup.show_items(entries)
			popup.show()
			popup.modulate = Color.WHITE
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			assert(popup.item_container.size.x <= 512)
			assert(popup.get_node("Panel/ScrollContainer").get_v_scroll_bar().max_value > 986)
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--screenshot="))
	print("SHOP_REFRESH_UI_SMOKE_OK quota sold_out countdown refresh offline busy sync close")
	get_tree().quit()
