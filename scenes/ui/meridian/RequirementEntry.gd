class_name RequirementEntry extends Control

signal complete_pressed()
signal item_pressed(item_id: int)

var _data: Dictionary = {}
var _items_setup: Array = []
var _index_setup: int = -1
var _completed_setup: bool = false
var _rewards_setup: Dictionary = {}
var _ready_done: bool = false
var _available: bool = false
var _order_priority: int = 0
var _order_match_count: int = 0
var _item_widget_scene: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")
var _reward_slot_scene: PackedScene = preload("res://scenes/ui/meridian/RewardSlot.tscn")


func _ready() -> void:
	_ready_done = true
	if not _items_setup.is_empty():
		_do_setup(_items_setup, _index_setup, _completed_setup, _rewards_setup)


func setup(items: Array, index: int, completed: bool, rewards: Dictionary = {}) -> void:
	_items_setup = items
	_index_setup = index
	_completed_setup = completed
	_rewards_setup = rewards
	if _ready_done:
		_do_setup(items, index, completed, rewards)


func _do_setup(items: Array, index: int, completed: bool, rewards: Dictionary) -> void:
	_data = {"items": items, "index": index, "completed": completed}

	var items_container: HBoxContainer = $ItemsContainer
	var reward_box: HBoxContainer = $RewardRow/RewardBox
	var complete_btn: Button = $CompleteButton
	items_container.show()
	$RewardRow.show()
	complete_btn.show()
	modulate = Color.WHITE
	scale = Vector2.ONE

	for child in items_container.get_children():
		items_container.remove_child(child)
		child.queue_free()
	for child in reward_box.get_children():
		reward_box.remove_child(child)
		child.queue_free()

	for item_variant in items:
		var item: Dictionary = item_variant
		var item_id: int = int(item.get("item_id", 0))
		var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
		var widget: ItemWidget = _item_widget_scene.instantiate() as ItemWidget
		widget.custom_minimum_size = Vector2(68, 84)
		widget.size = Vector2(68, 84)
		widget.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_item_widget(widget)
		if not item_data.is_empty():
			widget.setup(item_data)
		else:
			widget.setup({"name": item.get("name", "?")})
		widget.set_clickable(true)
		widget.pressed.connect(_on_item_pressed.bind(item_id))
		var click_button: Button = widget.get_node_or_null("ClickButton") as Button
		if click_button:
			click_button.tooltip_text = "查看获取方式"
		items_container.add_child(widget)

	if not rewards.is_empty():
		if rewards.has("tokens"):
			for token_variant in rewards.tokens:
				var token: Dictionary = token_variant
				var token_type: int = int(token.get("token", 0))
				var amount: int = int(token.get("amount", 0))
				var slot: RewardSlot = _reward_slot_scene.instantiate() as RewardSlot
				reward_box.add_child(slot)
				slot.setup(token_type, amount)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if rewards.has("items"):
			for reward_variant in rewards.items:
				var reward: Dictionary = reward_variant
				var item_id: int = int(reward.get("id", 0))
				var count: int = int(reward.get("count", 0))
				var slot: RewardSlot = _reward_slot_scene.instantiate() as RewardSlot
				reward_box.add_child(slot)
				slot.setup(item_id, count)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stair_points: int = int(rewards.get("stair_climb_points", 0))
	if stair_points > 0 and not completed:
		var stair_label := Label.new()
		stair_label.name = "StairClimbPoints"
		stair_label.text = "天梯 +%d" % stair_points
		stair_label.tooltip_text = "完成本单获得 %d 天梯积分" % stair_points
		stair_label.add_theme_font_size_override("font_size", 14)
		stair_label.add_theme_color_override("font_color", Color("806022"))
		stair_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		reward_box.add_child(stair_label)
	set_order_duel_points(int(rewards.get("order_duel_points", 0)))
	set_secret_realm_swords(rewards.get("secret_realm_swords", []))

	if completed:
		complete_btn.text = ""
		complete_btn.disabled = true
		complete_btn.visible = true
	else:
		complete_btn.text = ""
		complete_btn.disabled = false
		if complete_btn.pressed.is_connected(_on_btn_pressed):
			complete_btn.pressed.disconnect(_on_btn_pressed)
		complete_btn.pressed.connect(_on_btn_pressed)
		complete_btn.visible = false


func set_order_duel_points(points: int) -> void:
	var reward_box: HBoxContainer = $RewardRow/RewardBox
	var label: Label = reward_box.get_node_or_null("OrderDuelPoints") as Label
	if points <= 0 or bool(_data.get("completed", false)):
		if label:
			reward_box.remove_child(label)
			label.queue_free()
		return
	if not label:
		label = Label.new()
		label.name = "OrderDuelPoints"
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color("806022"))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		reward_box.add_child(label)
	label.text = "对战 +%d" % points
	label.tooltip_text = "完成本单获得 %d 对战积分（以本场剩余目标积分为限）" % points


func set_secret_realm_swords(drops: Array) -> void:
	var reward_box: HBoxContainer = $RewardRow/RewardBox
	var slot: RewardSlot = reward_box.get_node_or_null("SecretRealmSwords") as RewardSlot
	var total: int = 0
	var details: PackedStringArray = []
	for drop: Dictionary in drops:
		var count: int = int(drop.get("count", 0))
		if count <= 0:
			continue
		total += count
		for item: Dictionary in ConfigDatabase.secret_realm.get("items", []):
			if item.get("id", "") == drop.get("id", ""):
				details.append("%s ×%d" % [item.get("name", "飞剑"), count])
				break
	if total <= 0 or bool(_data.get("completed", false)):
		if slot:
			reward_box.remove_child(slot)
			slot.queue_free()
		return
	if not slot:
		slot = _reward_slot_scene.instantiate() as RewardSlot
		slot.name = "SecretRealmSwords"
		reward_box.add_child(slot)
	slot.icon_rect.texture = preload("res://assets/ui/secret_realm/sword.svg")
	slot.count_label.text = "×%d" % total
	slot.tooltip_text = "完成本单获得秘境飞剑，进入秘境暂存：\n%s" % "\n".join(details)


func set_available(available: bool) -> bool:
	var changed: bool = _available != available
	_available = available
	if not bool(_data.get("completed", false)):
		var btn: Button = $CompleteButton
		btn.visible = available
	return changed


func is_available() -> bool:
	return _available


func set_order_priority(priority: int) -> bool:
	return set_order_rank(priority, _order_match_count)


func set_order_rank(priority: int, match_count: int) -> bool:
	var normalized_priority: int = clampi(priority, 0, 2)
	var normalized_match_count: int = maxi(match_count, 0)
	var changed: bool = (
		_order_priority != normalized_priority
		or _order_match_count != normalized_match_count
	)
	_order_priority = normalized_priority
	_order_match_count = normalized_match_count
	set_available(_order_priority == 2)
	return changed


func get_order_priority() -> int:
	return _order_priority


func get_order_match_count() -> int:
	return _order_match_count


func get_display_index() -> int:
	return int(_data.get("index", -1))


func refresh_item_selection(present_item_ids: Dictionary) -> void:
	var remaining: Dictionary = present_item_ids.duplicate()
	var items_container: HBoxContainer = $ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			var widget: ItemWidget = child as ItemWidget
			var item_id: int = int(widget.item_data.get("id", 0))
			var count: int = int(remaining.get(item_id, 0))
			widget.set_selected(item_id > 0 and count > 0)
			if count > 0:
				remaining[item_id] = count - 1


func refresh_item_crafting(crafting_item_ids: Dictionary) -> void:
	var items_container: HBoxContainer = $ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			var widget: ItemWidget = child as ItemWidget
			var item_id: int = int(widget.item_data.get("id", 0))
			widget.set_crafting_badge(item_id > 0 and crafting_item_ids.has(item_id))

func get_item_widget_center(item_id: int) -> Vector2:
	for child in $ItemsContainer.get_children():
		if child is ItemWidget and int((child as ItemWidget).item_data.get("id", 0)) == item_id:
			return (child as Control).get_global_rect().get_center()
	return get_global_rect().get_center()

func show_completed_empty_state() -> void:
	# Clear the completed order immediately; the list reflow starts right after this call.
	for child in $ItemsContainer.get_children():
		child.hide()
	$RewardRow.hide()
	$CompleteButton.hide()
	modulate = Color.WHITE
	scale = Vector2.ONE


func _on_btn_pressed() -> void:
	if RequirementList.is_scroll_click_cancelled(self):
		return
	complete_pressed.emit()


func _on_item_pressed(item_id: int) -> void:
	if RequirementList.is_scroll_click_cancelled(self):
		return
	if item_id > 0:
		item_pressed.emit(item_id)


func mark_completed() -> void:
	var btn: Button = $CompleteButton
	btn.text = ""
	btn.disabled = true
	btn.visible = true
	var items_container: HBoxContainer = $ItemsContainer
	for child in items_container.get_children():
		if child is ItemWidget:
			child.modulate = Color(0.5, 0.8, 0.5, 1)


func _style_item_widget(widget: ItemWidget) -> void:
	var icon_rect: TextureRect = widget.get_node_or_null("IconRect") as TextureRect
	if icon_rect:
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		icon_rect.offset_left = -28.0
		icon_rect.offset_top = -28.0
		icon_rect.offset_right = 28.0
		icon_rect.offset_bottom = 28.0
