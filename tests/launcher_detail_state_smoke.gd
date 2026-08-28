extends Node

const LAUNCHER_ID: int = 11002

func _ready() -> void:
	await get_tree().process_frame
	var detail_panel: ItemDetailPanel = preload("res://scenes/ui/main/ItemDetailPanel.tscn").instantiate() as ItemDetailPanel
	add_child(detail_panel)
	await get_tree().process_frame

	var launcher_data: Dictionary = ConfigDatabase.get_item_data(LAUNCHER_ID).duplicate(true)
	assert(Constants.has_launcher_config(launcher_data))
	launcher_data["_uid"] = 992001
	launcher_data["charges"] = int(launcher_data.get("max_charges", 0)) - 1
	launcher_data["_recharge_remaining"] = 120000.0
	detail_panel.show_item(launcher_data)
	await get_tree().process_frame

	assert(int(launcher_data.get("charges", 0)) > 0)
	assert(not detail_panel.status_label.visible)
	assert(detail_panel.desc_label.visible)
	assert(not detail_panel.speedup_btn.visible)

	launcher_data["charges"] = 0
	detail_panel.show_item(launcher_data)
	await get_tree().process_frame
	assert(detail_panel.status_label.visible)
	assert(not detail_panel.desc_label.visible)
	assert(detail_panel.speedup_btn.visible)

	print("LAUNCHER_DETAIL_STATE_SMOKE_OK launcher_id=", LAUNCHER_ID,
		" charges_with_remaining=", int(launcher_data.get("max_charges", 0)) - 1,
		" charges_depleted=0 charging=true")
	get_tree().quit()
