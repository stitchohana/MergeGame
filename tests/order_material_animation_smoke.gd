extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CloudService.online = false
	GameState.main_grid_cache = []
	GameState.meridian_acupoints = []
	GameState.current_board_type = Constants.BoardType.MAIN
	GridManager.init_grid()
	StoragePouch.restore_from_server([
		{"uid": 995001, "id": 5001}, {"uid": 995002, "id": 5001},
	])
	var material: Dictionary = ConfigDatabase.get_item_data(5002).duplicate(true)
	material["_uid"] = 995003
	assert(GridManager.add_item(material, Vector2i.ZERO))
	var screen: GameScreen = preload("res://scenes/screens/GameScreen.tscn").instantiate() as GameScreen
	add_child(screen)
	screen._is_initial_game_load = false
	GameState.meridian_acupoints = [{
		"items": [{"item_id": 5001}, {"item_id": 5001}, {"item_id": 5002}],
		"item_ids": [5001, 5001, 5002], "completed": false,
	}, {"item_ids": [9001], "items": [{"item_id": 9001}], "completed": false}]
	screen._display_meridian()
	for frame: int in range(5):
		await get_tree().process_frame
	screen.requirement_list.scroll.scroll_horizontal = 0
	await get_tree().process_frame
	screen._capture_order_animation(0)
	var animation: Dictionary = screen._pending_order_animation
	var sources: Array = animation["sources"]
	assert(sources.size() == 3)
	assert(sources[0]["source"] == "pouch" and sources[1]["source"] == "pouch")
	assert(sources[0]["uid"] != sources[1]["uid"], "Each pouch instance may fly only once")
	assert(sources[0]["target_icon"] != sources[1]["target_icon"], "Repeated item IDs need distinct slots")
	var target_icon: TextureRect = sources[0]["target_icon"] as TextureRect
	var old_target: Vector2 = target_icon.get_global_rect().get_center()
	screen.requirement_list.scroll.scroll_horizontal += 100
	await get_tree().process_frame
	assert(not old_target.is_equal_approx(target_icon.get_global_rect().get_center()))
	var landed: Dictionary = {}
	var fly: TextureRect = screen._play_flying_item(5001, Vector2(400, 600), old_target, 0.25, null, target_icon)
	fly.tree_exiting.connect(func():
		landed["position"] = fly.get_global_rect().get_center()
		landed["target"] = target_icon.get_global_rect().get_center()
	)
	await get_tree().create_timer(0.08).timeout
	screen.requirement_list.scroll.scroll_horizontal += 100
	await get_tree().create_timer(0.25).timeout
	assert(landed.has("position"))
	assert((landed["position"] as Vector2).is_equal_approx(landed["target"]), "The fly must land on the live icon after scrolling")

	# A repeated playback must not create another copy of any submitted item.
	screen._play_order_material_fly(animation, 0.15)
	var overlay: Control = screen._get_order_animation_host()
	assert(_flying_icon_count(overlay) == 3)
	screen._play_order_material_fly(animation, 0.15)
	assert(_flying_icon_count(overlay) == 3)
	for source: Dictionary in sources:
		assert((source["target_icon"] as TextureRect).self_modulate.a == 0.0, "The target must not display a second copy during flight")
	await get_tree().create_timer(0.2).timeout
	assert(_flying_icon_count(overlay) == 0)

	# Exercise the complete confirmation flow, including duplicate callbacks.
	screen._display_meridian()
	for frame: int in range(3):
		await get_tree().process_frame
	screen._capture_order_animation(0)
	var result: Dictionary = {"grid": [], "pouch": [], "meridian_acupoints": [], "qi_gained": 0}
	screen._on_meridian_confirmed(result)
	screen._on_meridian_confirmed(result)
	await get_tree().create_timer(Constants.ORDER_SOURCE_HIDE_DURATION + 0.05).timeout
	assert(_flying_icon_count(overlay) == 3, "Duplicate confirmation must not spawn duplicate flying copies")
	await get_tree().create_timer(Constants.ORDER_ITEM_FLY_DURATION + 0.5).timeout
	assert(_flying_icon_count(overlay) == 0)
	assert(GridManager.count_items() == 0)
	assert(StoragePouch.items.is_empty())
	assert(screen._order_animation_input_token == -1)
	print("ORDER_MATERIAL_ANIMATION_SMOKE_OK live_scroll_target=true distinct_slots=true pouch_once=true target_no_duplicate=true repeated_confirmation=true")
	get_tree().quit(0)


func _flying_icon_count(host: Control) -> int:
	var count: int = 0
	for child: Node in host.get_children():
		if child is TextureRect and not child.is_queued_for_deletion():
			count += 1
	return count
