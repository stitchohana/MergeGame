class_name PendingRewardBar extends Control

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var items_box: HBoxContainer = $Panel/VBox/ItemsBox

var _item_widget_scene := preload("res://scenes/ui/common/ItemWidget.tscn")
var grid_view: Control = null


func _ready() -> void:
	RewardManager.pending_rewards_changed.connect(_refresh)
	CloudService.pending_reward_claimed.connect(_on_claimed)
	_refresh(0)

func setup(grid: Control) -> void:
	grid_view = grid


func _refresh(_count: int) -> void:
	for child in items_box.get_children():
		child.queue_free()

	var rewards = RewardManager.pending_rewards
	if rewards.is_empty():
		hide()
		return
	show()
	title_label.text = "暂存区 (%d)" % rewards.size()

	var r: Dictionary = rewards[0]
	var item_id: int = r.get("id", 0)
	var item_data := ConfigDatabase.get_item_data(item_id)

	var widget := _item_widget_scene.instantiate() as ItemWidget
	widget.setup(item_data, Vector2i(-1, -1), 36)
	widget.custom_minimum_size = Vector2(50, 50)
	widget.size = Vector2(50, 50)
	for node_name: String in ["IconBg", "SelectIcon", "IconRect"]:
		var texture_rect := widget.get_node_or_null(node_name) as TextureRect
		if texture_rect:
			texture_rect.offset_left = 7.0
			texture_rect.offset_top = 7.0
			texture_rect.offset_right = -7.0
			texture_rect.offset_bottom = -7.0
	widget.set_clickable(true)
	widget.pressed.connect(_on_claim.bind(r))
	var click_button := widget.get_node_or_null("ClickButton") as Button
	if click_button:
		click_button.tooltip_text = "%s (点击放入棋盘)" % r.get("name", "")
	items_box.add_child(widget)


var _fly_targets: Dictionary = {}  # uid -> (col, row) for fly animation

var _claim_pending: bool = false

func _on_claim(reward: Dictionary) -> void:
	if _claim_pending:
		return
	var uid: int = reward.get("uid", -1)
	if uid < 0:
		return

	# Start fly animation (target will be filled in by _on_claimed)
	if items_box.get_child_count() == 0:
		return
	var from_pos: Vector2 = items_box.get_child(0).global_position
	var item_data := ConfigDatabase.get_item_data(reward.get("id", 0))

	var fly := _item_widget_scene.instantiate() as ItemWidget
	if item_data.is_empty():
		fly.setup({"name": reward.get("name", "?")})
	else:
		fly.setup(item_data)
	fly.custom_minimum_size = Vector2(48, 48)
	fly.size = Vector2(48, 48)
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.global_position = from_pos
	fly.z_index = 100
	fly.top_level = true
	get_parent().add_child(fly)
	_fly_targets[uid] = {"fly": fly, "from": from_pos}

	# Send request, server returns position
	_claim_pending = true
	CloudService.submit_claim_pending_reward(uid)


func _on_claimed(result: Dictionary) -> void:
	_claim_pending = false
	# Update pending rewards immediately (hide the claimed item)
	if result.has("pending_rewards"):
		RewardManager.pending_rewards = result.pending_rewards
		_refresh(RewardManager.pending_rewards.size())

	# Play fly animation, then sync grid
	var col: int = result.get("col", -1)
	var row: int = result.get("row", -1)
	var grid_origin: Vector2 = grid_view.global_position if grid_view and is_instance_valid(grid_view) else Vector2.ZERO
	var cell_size: int = Constants.CELL_STEP
	var cell_center: Vector2 = grid_origin + Vector2(col * cell_size + cell_size / 2, row * cell_size + cell_size / 2)

	var on_done := func():
		if result.has("grid"):
			_sync_grid(result.grid)

	var animating := false
	for uid in _fly_targets:
		var data: Dictionary = _fly_targets[uid]
		var fly: Control = data["fly"]
		_fly_targets.erase(uid)
		if fly and is_instance_valid(fly):
			animating = true
			var to_pos: Vector2 = cell_center - fly.size / 2
			var tween := get_tree().create_tween()
			tween.tween_property(fly, "global_position", to_pos, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			tween.tween_callback(func(): fly.queue_free(); on_done.call())
		break
	if not animating:
		on_done.call()


func _sync_grid(grid: Array) -> void:
	GridManager.init_grid()
	GridManager._skip_anims = true
	for entry in grid:
		var data := ConfigDatabase.get_item_data(entry.id)
		if not data.is_empty():
			var item := data.duplicate(true)
			item["_uid"] = entry.uid
			if entry.has("immovable"):
				item["immovable"] = entry.immovable
			if entry.has("charges"):
				item["charges"] = entry.charges
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	GridManager._skip_anims = false
