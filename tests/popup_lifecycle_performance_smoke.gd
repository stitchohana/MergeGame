extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CloudService.online = false
	var popup_layer: Control = UIManager.get_layer(UIManager.Layer.POPUP)
	var initial_nodes: int = popup_layer.get_child_count()
	var initial_shop_connections: int = CloudService.shop_updated.get_connections().size()
	for index: int in range(12):
		var popup: ShopPopup = preload("res://scenes/ui/shop/ShopPopup.tscn").instantiate() as ShopPopup
		popup.animation_duration = 0.001
		UIManager.show_popup(popup)
		await get_tree().process_frame
		await UIManager.hide_popup(popup)
		assert(popup.is_queued_for_deletion(), "Closed popups must be released")
		await get_tree().process_frame
	assert(popup_layer.get_child_count() == initial_nodes, "Hidden popup nodes must not accumulate")
	assert(CloudService.shop_updated.get_connections().size() == initial_shop_connections,
		"Closed popup signal connections must be released with the node")
	print("POPUP_LIFECYCLE_PERFORMANCE_SMOKE_OK released=true stable_nodes=true stable_connections=true")
	get_tree().quit(0)
