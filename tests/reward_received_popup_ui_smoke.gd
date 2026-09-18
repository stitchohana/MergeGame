extends Node

const REWARD_POPUP_SCENE: PackedScene = preload("res://scenes/ui/home/RewardReceivedPopup.tscn")


func _ready() -> void:
	var popup: RewardReceivedPopup = REWARD_POPUP_SCENE.instantiate() as RewardReceivedPopup
	assert(popup != null)
	UIManager.show_popup(popup)
	await get_tree().process_frame
	popup.setup(
		"收到奖励",
		"测试周天完成",
		{
			"tokens": [{"token": 4, "amount": 2}],
			"items": [{"id": 20002, "count": 1}, {"id": 21002, "count": 2}],
		}
	)
	assert(popup.title_label.text == "收到奖励")
	assert(popup.rewards_container.get_child_count() == 3)
	await UIManager.hide_popup(popup)
	print("REWARD_RECEIVED_POPUP_UI_SMOKE_OK")
	get_tree().quit()
