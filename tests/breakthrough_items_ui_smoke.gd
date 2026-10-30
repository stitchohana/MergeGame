extends Node

const HOME_SCENE: PackedScene = preload("res://scenes/screens/HomeScreen.tscn")


func _ready() -> void:
	var home: HomeScreen = HOME_SCENE.instantiate() as HomeScreen
	add_child(home)
	await get_tree().process_frame
	await get_tree().process_frame

	# Server refreshes must show the manual breakthrough button even when
	# Qi layer three has no configured breakthrough materials.
	CloudService.online = false
	CultivationService.current_level = 4
	CultivationService.current_exp = ConfigDatabase.get_stage_exp(4) - 1
	var defs: Array = ConfigDatabase.get_home_meridian_stages().duplicate(true)
	var completed_progress: Array = []
	for index in range(defs.size()):
		var def: Dictionary = defs[index]
		if int(def.get("cultivation_level", 0)) != 4:
			continue
		var lit: Array = []
		lit.resize(int(def.get("acupoints", 0)))
		lit.fill(true)
		completed_progress.append({"stage": index, "lit": lit, "circulation_completed": true})
	var authoritative_cultivation: Dictionary = {
		"current_level": 4, "current_exp": ConfigDatabase.get_stage_exp(4),
		"total_exp": 244, "current_qi": 100, "max_qi": 6000,
	}
	home._home_defs = defs.duplicate(true)
	home._home_progress = completed_progress.duplicate(true)
	home._refresh_breakthrough_btn()
	var breakthrough_btn: Button = home.get_node("BreakthroughBtn") as Button
	assert(not breakthrough_btn.visible)
	# Keep a stale pending circulation locally: the refreshed progress must be
	# applied before cultivation signals decide whether breakthrough is ready.
	home._home_progress[-1]["circulation_completed"] = false
	home._on_state_loaded({
		"home_meridian_defs": defs,
		"home_meridian_progress": completed_progress.duplicate(true),
		"cultivation": authoritative_cultivation,
	})
	assert(CultivationService.current_level == 4)
	assert(CultivationService.current_exp == ConfigDatabase.get_stage_exp(4))
	assert(breakthrough_btn.visible)
	assert(CultivationService.get_required_breakthrough_items().is_empty())
	# The last circulation and its animation still gate manual breakthrough.
	home._home_progress[-1]["circulation_completed"] = false
	home._refresh_breakthrough_btn()
	assert(not breakthrough_btn.visible)
	home._home_progress[-1]["circulation_completed"] = true
	home._circulation_animating = true
	home._refresh_breakthrough_btn()
	assert(not breakthrough_btn.visible)
	home._circulation_animating = false
	home._refresh_breakthrough_btn()
	assert(breakthrough_btn.visible)
	home._home_progress = []

	var original_cultivation_config: Dictionary = ConfigDatabase._cultivation_config.duplicate(true)
	ConfigDatabase._cultivation_config = {
		"stages": [{
			"name": "测试突破",
			"exp": 30,
			"max_qi": 1000,
			"breakthrough_items": [
				{"item_id": 14101, "count": 1},
				{"item_id": 28049, "count": 2},
				{"item_id": 28050, "count": 1},
				{"item_id": 28051, "count": 1},
				{"item_id": 28052, "count": 1},
				{"item_id": 28053, "count": 1},
			],
			"breakthrough_reward_id": 301,
		}, {
			"name": "下一层",
			"exp": 999,
			"max_qi": 2000,
		}],
	}
	CultivationService.current_level = 1
	CultivationService.current_exp = ConfigDatabase.get_stage_exp(1)
	home._refresh_breakthrough_btn()
	await get_tree().process_frame

	GameState.pending_breakthrough_prompt = true
	home._try_show_pending_breakthrough_prompt()
	await get_tree().process_frame
	assert(not GameState.pending_breakthrough_prompt)
	var popup_layer: Control = UIManager.get_layer(UIManager.Layer.POPUP)
	var confirm_popup: ConfirmPopup = null
	for child: Node in popup_layer.get_children():
		if child is ConfirmPopup:
			confirm_popup = child as ConfirmPopup
			break
	assert(confirm_popup != null)
	assert(confirm_popup.title_label.text == "突破确认")
	assert(confirm_popup is BreakthroughConfirmPopup)
	var breakthrough_popup: BreakthroughConfirmPopup = confirm_popup as BreakthroughConfirmPopup
	assert(breakthrough_popup.skip_today_checkbox == null)
	var panel: Control = breakthrough_popup.get_node("Panel") as Control
	var panel_offsets: Vector2 = Vector2(panel.offset_top, panel.offset_bottom)
	breakthrough_popup.show_skip_today_option()
	assert(Vector2(panel.offset_top, panel.offset_bottom) == panel_offsets)
	assert(breakthrough_popup.rewards_container.get_child_count() == 1)
	var first_reward_card: VBoxContainer = breakthrough_popup.rewards_container.get_child(0) as VBoxContainer
	var first_reward_widget: ItemWidget = first_reward_card.get_node("ItemWidget") as ItemWidget
	assert(int(first_reward_widget.item_data.get("id", 0)) == 25001)
	await UIManager.hide_popup(confirm_popup)

	var scroll: ScrollContainer = home.get_node("BreakthroughItemsScroll") as ScrollContainer
	var row: HBoxContainer = home.get_node("BreakthroughItemsScroll/BreakthroughItemsRow") as HBoxContainer
	assert(scroll.visible)
	assert(row.get_child_count() == 6)
	assert(scroll.get_h_scroll_bar().max_value > 0)

	var slot: Control = row.get_child(0) as Control
	var item_widget: ItemWidget = slot.get_node("ItemWidget") as ItemWidget
	var count_label: Label = slot.get_node("CountLabel") as Label
	assert(int(item_widget.item_data.get("id", 0)) == 14101)
	assert(count_label.text == "×1")
	var second_count_label: Label = (row.get_child(1) as Control).get_node("CountLabel") as Label
	assert(second_count_label.text == "×2")

	# With a short list, the row should center its items in the viewport.
	ConfigDatabase._cultivation_config["stages"][0]["breakthrough_items"] = [{"item_id": 28049, "count": 1}]
	home._refresh_breakthrough_btn()
	await get_tree().process_frame
	assert(row.get_child_count() == 1)
	var centered_slot: Control = row.get_child(0) as Control
	var expected_left: float = (scroll.size.x - centered_slot.size.x) / 2.0
	assert(abs(centered_slot.position.x - expected_left) <= 1.0)

	var recipe_item_widget: ItemWidget = centered_slot.get_node("ItemWidget") as ItemWidget
	recipe_item_widget.pressed.emit()
	await get_tree().process_frame
	var source_popup: RecipeSourcePopup = null
	for child: Node in popup_layer.get_children():
		if child is RecipeSourcePopup:
			source_popup = child as RecipeSourcePopup
			break
	assert(source_popup != null)
	assert(source_popup.title_label.text == String(ConfigDatabase.get_item_data(28049).get("name", "")))
	assert(source_popup.product_icon.visible)
	assert(int(source_popup.product_icon.item_data.get("id", 0)) == 17001)
	var ingredient_widget: ItemWidget = source_popup.get_node("Panel/SourceContainer/SourceBg/HBoxContainer/IngredientItem1") as ItemWidget
	ingredient_widget.pressed.emit()
	await get_tree().process_frame
	var source_path: CraftPathView = null
	for child: Node in popup_layer.get_children():
		if child is CraftPathView:
			source_path = child as CraftPathView
			break
	assert(source_path != null)
	assert(source_path.source_item.visible)
	assert(int(source_path.source_item.item_data.get("id", 0)) > 0)
	assert((source_path.source_item.get_node("IconRect") as TextureRect).visible)
	await UIManager.hide_popup(source_path)
	await UIManager.hide_popup(source_popup)

	# Recipe products can intentionally have a null group_id. CraftPathView must
	# treat that as an ungrouped item instead of calling int(null).
	var null_group_path: CraftPathView = preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	add_child(null_group_path)
	null_group_path.show_for_item(ConfigDatabase.get_item_data(28049))
	assert(null_group_path._items.size() == 1)
	assert(null_group_path.rows_container.get_child_count() > 0)
	null_group_path.queue_free()

	ConfigDatabase._cultivation_config = original_cultivation_config
	home.free()
	print("BREAKTHROUGH_ITEMS_UI_SMOKE_OK")
	get_tree().quit()
