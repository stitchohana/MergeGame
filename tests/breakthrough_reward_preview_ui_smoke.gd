extends Node

const ACTIVATION_POPUP_SCENE: PackedScene = preload("res://scenes/ui/home/AcupointActivatePopup.tscn")
const CHARACTER_ENTRY_SCENE: PackedScene = preload("res://scenes/ui/character/CharacterEntry.tscn")


func _ready() -> void:
	var original_cultivation: Dictionary = ConfigDatabase._cultivation_config.duplicate(true)
	var original_rewards: Dictionary = ConfigDatabase._rewards_data.duplicate(true)
	var original_home_defs: Array = ConfigDatabase._home_meridian_stages.duplicate(true)
	var original_home_progress: Array = GameState.home_meridian_progress.duplicate(true)
	ConfigDatabase._cultivation_config = {
		"stages": [{
			"name": "测试境界",
			"exp": 30,
			"max_qi": 1000,
			"breakthrough_reward_id": 301,
		}, {
			"name": "下一层",
			"exp": 999,
			"max_qi": 2000,
		}],
	}
	ConfigDatabase._rewards_data = {}
	ConfigDatabase._home_meridian_stages = [{
		"name": "测试周天",
		"circulation_reward": {
			"items": [
				{"id": 20002, "count": 1},
				{"id": 21002, "count": 2},
			],
		},
	}]
	GameState.home_meridian_defs = ConfigDatabase._home_meridian_stages.duplicate(true)
	GameState.home_meridian_progress = []
	CultivationService.current_level = 1
	CultivationService.current_exp = 30

	var activation_popup: AcupointActivatePopup = ACTIVATION_POPUP_SCENE.instantiate() as AcupointActivatePopup
	UIManager.show_popup(activation_popup)
	await get_tree().process_frame
	activation_popup.setup("测试穴位", "进度：0/1", {}, "激活", Callable())
	assert(activation_popup.gift_button is TextureButton)
	activation_popup.gift_button.pressed.emit()
	await get_tree().process_frame
	var reward_popup: BreakthroughRewardPreviewPopup = _find_reward_popup()
	assert(reward_popup != null)
	assert(reward_popup.title_label.text == "周天奖励预览")
	assert(reward_popup.stage_label.text == "当前周天：测试周天")
	assert(reward_popup.rewards_container.get_child_count() == 2)
	var first_card: VBoxContainer = reward_popup.rewards_container.get_child(0) as VBoxContainer
	var first_widget: ItemWidget = first_card.get_node("ItemWidget") as ItemWidget
	assert(int(first_widget.item_data.get("id", 0)) == 20002)
	await UIManager.hide_popup(reward_popup)
	await UIManager.hide_popup(activation_popup)

	var character_entry: CharacterEntry = CHARACTER_ENTRY_SCENE.instantiate() as CharacterEntry
	add_child(character_entry)
	await get_tree().process_frame
	assert(character_entry.reward_button is TextureButton)
	character_entry.reward_button.pressed.emit()
	await get_tree().process_frame
	reward_popup = _find_reward_popup()
	assert(reward_popup != null)
	assert(reward_popup.rewards_container.get_child_count() == 2)
	await UIManager.hide_popup(reward_popup)
	character_entry.queue_free()

	ConfigDatabase._cultivation_config = original_cultivation
	ConfigDatabase._rewards_data = original_rewards
	ConfigDatabase._home_meridian_stages = original_home_defs
	GameState.home_meridian_defs = original_home_defs.duplicate(true)
	GameState.home_meridian_progress = original_home_progress
	print("BREAKTHROUGH_REWARD_PREVIEW_UI_SMOKE_OK")
	get_tree().quit()


func _find_reward_popup() -> BreakthroughRewardPreviewPopup:
	var popup_layer: Control = UIManager.get_layer(UIManager.Layer.POPUP)
	for child: Node in popup_layer.get_children():
		if child is BreakthroughRewardPreviewPopup:
			return child as BreakthroughRewardPreviewPopup
	return null
