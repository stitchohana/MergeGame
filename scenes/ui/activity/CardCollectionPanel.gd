class_name CardCollectionPanel extends BasePopup

const STAR_COLORS: Array[Color] = [Color("b5c7bf"), Color("74c6a4"), Color("7eafe4"), Color("ba95dd"), Color("efd081")]
var collection_id: int = 1
var _activity_id: int = 5
var _title: Label
var _body: VBoxContainer
var _status: Label
var _summary: Label
var _retry: Button
var _result: VBoxContainer
var _reveal_tween: Tween
var _result_data: Dictionary = {}
var _card_grids: Array[GridContainer] = []
var _points_label: Label
var _exchange_button: Button
var _countdown: Label
var _last_countdown_second: int = -1
var _last_time_active: bool = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.035, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_anchor(SIDE_LEFT, 0.04)
	panel.set_anchor(SIDE_TOP, 0.035)
	panel.set_anchor(SIDE_RIGHT, 0.96)
	panel.set_anchor(SIDE_BOTTOM, 0.965)
	panel.add_theme_stylebox_override("panel", _style(Color("14292d"), Color("9d8454"), 18))
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_title = _label("万象仙册", 28, Color("eed5a3"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close: Button = _button("关闭")
	close.pressed.connect(func() -> void: UIManager.hide_popup(self))
	header.add_child(close)
	_countdown = _label("", 17, Color("eed5a3"))
	_countdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_countdown)
	_summary = _label("收集山海万象 · 集齐卡组获得厚礼", 17)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_summary)
	_status = _label("完成任务、提交订单、运转周天获得卡包，在物品暂存区点击开启", 14, Color("a9bdb5"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	_retry = _button("重试上次操作")
	_retry.pressed.connect(func() -> void:
		CloudService.retry_card_collection()
		_refresh()
	)
	layout.add_child(_retry)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_body)
	GameState.card_collection_changed.connect(_refresh)
	CloudService.state_loaded.connect(_on_state)
	CloudService.card_collection_confirmed.connect(_on_confirmed)
	CloudService.card_collection_rejected.connect(_on_rejected)
	resized.connect(_resize_grids)
	_refresh()
	_update_countdown()
	_last_time_active = _is_active()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var second: int = int(Time.get_unix_time_from_system())
	if second == _last_countdown_second:
		return
	_last_countdown_second = second
	_update_countdown()
	var active: bool = _is_active()
	if active != _last_time_active:
		_last_time_active = active
		_refresh()


func _activity_definition() -> Dictionary:
	for activity: Dictionary in GameState.activity_defs:
		if int(activity.get("id", 0)) == _activity_id:
			return activity
	return {}


func _activity_timestamp(value: String) -> int:
	if value.is_empty():
		return 0
	# Godot parses the wall time but does not apply an ISO 8601 timezone offset.
	var zone_index: int = maxi(value.find("+", 10), value.find("-", 10))
	var offset: int = 0
	if zone_index >= 0:
		var zone: String = value.substr(zone_index + 1).replace(":", "")
		offset = (int(zone.left(2)) * 3600 + int(zone.substr(2, 2)) * 60) * (1 if value[zone_index] == "+" else -1)
		value = value.left(zone_index)
	return int(Time.get_unix_time_from_datetime_string(value.trim_suffix("Z"))) - offset


func _update_countdown(now: int = -1) -> void:
	if not is_instance_valid(_countdown):
		return
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var activity: Dictionary = _activity_definition()
	var end_time: int = _activity_timestamp(str(activity.get("end_time", "")))
	var start_time: int = _activity_timestamp(str(activity.get("start_time", "")))
	if end_time > 0 and now >= end_time:
		_countdown.text = "活动已结束"
	elif start_time > now:
		_countdown.text = "距活动开始：" + _duration_text(start_time - now)
	elif not bool(activity.get("active", false)):
		_countdown.text = "活动暂未开放"
	elif end_time > 0:
		_countdown.text = "活动剩余：" + _duration_text(end_time - now)
	else:
		_countdown.text = "长期开放"


func _duration_text(seconds: int) -> String:
	return "%d天 %02d:%02d:%02d" % [seconds / 86400, (seconds % 86400) / 3600, (seconds % 3600) / 60, seconds % 60]


func setup(activity_id: int) -> void:
	_activity_id = activity_id
	for collection: Dictionary in ConfigDatabase.card_collection.get("collections", []):
		if int(collection.activity_id) == activity_id:
			collection_id = int(collection.collection_id)
	_refresh()


func _on_state(_data: Dictionary) -> void:
	_refresh()


func _is_active() -> bool:
	var activity: Dictionary = _activity_definition()
	var now: int = int(Time.get_unix_time_from_system())
	var start_time: int = _activity_timestamp(str(activity.get("start_time", "")))
	var end_time: int = _activity_timestamp(str(activity.get("end_time", "")))
	return bool(activity.get("active", false)) and (start_time <= now) and (end_time <= 0 or now < end_time)


func _refresh() -> void:
	if not is_node_ready():
		return
	_update_countdown()
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_card_grids.clear()
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var config: Dictionary = ConfigDatabase.card_collection
	var progress: Dictionary = GameState.get_card_collection_progress(collection_id)
	var owned: Dictionary = progress.get("cards", {})
	var busy: bool = CloudService.card_collection_busy or not CloudService.card_collection_request.is_empty()
	var active: bool = _is_active()
	_retry.visible = not CloudService.card_collection_request.is_empty()
	_retry.disabled = CloudService.card_collection_busy
	_status.text = "正在结算，请稍候…" if CloudService.card_collection_busy else ("上次操作未确认，请重试以恢复结果" if busy else ("完成任务、提交订单、运转周天获得卡包，在物品暂存区点击开启" if active else "活动当前不可参与，已收集卡片会保留"))
	_build_exchange_controls(busy)
	_body.add_child(_label("珍藏图鉴", 21, Color("eed5a3")))
	var total: int = 0
	var collected: int = 0
	for card_set: Dictionary in config.get("card_sets", []):
		if int(card_set.collection_id) != collection_id:
			continue
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 8)
		_body.add_child(section)
		var set_cards: Array[Dictionary] = []
		var set_count: int = 0
		for card: Dictionary in config.get("cards", []):
			if int(card.set_id) == int(card_set.set_id):
				set_cards.append(card)
				if _count(owned, int(card.card_id)) > 0:
					set_count += 1
		collected += set_count
		total += set_cards.size()
		section.add_child(_label("%s    %d / %d" % [str(card_set.name), set_count, set_cards.size()], 19))
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		section.add_child(grid)
		_card_grids.append(grid)
		for card: Dictionary in set_cards:
			grid.add_child(_card_tile(card, _count(owned, int(card.card_id))))
		var claimed: bool = card_set.set_id in progress.get("claimed_sets", [])
		var reward_label: Label = _label(("已发放 · " if claimed else "集齐奖励 · ") + _reward_text(card_set.get("rewards", {})), 17, Color("eed5a3"))
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		section.add_child(reward_label)
	_summary.text = "已收集 %d / %d 张 · 集齐卡组获得体力与灵石" % [collected, total]
	_resize_grids()


func _on_confirmed(data: Dictionary) -> void:
	if int(data.get("collection_id", 0)) != collection_id:
		return
	if not data.has("cards") and not bool(data.get("exchanged", false)):
		EventBus.show_toast.emit("卡组奖励到账：" + _reward_text(data.get("rewards", {})))
	_refresh()


func _on_rejected(reason: String) -> void:
	_refresh()
	var messages: Dictionary = {"pack_not_found": "当前卡包已不在暂存区，正在同步", "insufficient_packs": "暂存区没有可开启的卡包", "insufficient_points": "集卡积分不足", "exchange_unavailable": "当前收藏暂不支持兑换", "activity_inactive": "活动当前不可参与", "state_conflict": "进度已更新，正在同步", "already_claimed": "奖励已领取", "set_incomplete": "卡组尚未集齐", "pending_operation": "请先重试上次操作", "save_failed": "保存未完成，请重试"}
	_status.text = str(messages.get(reason, "操作未确认，请检查网络后重试"))


func _build_result(data: Dictionary) -> void:
	_result = VBoxContainer.new()
	_body.add_child(_result)
	var points_gained: int = int(data.get("duplicate_points_gained", 0))
	if points_gained > 0:
		_result.add_child(_label("重复卡获得集卡积分：+%d" % points_gained, 17, Color("eed5a3")))
	var completed_sets: Array = data.get("completed_sets", [])
	if not completed_sets.is_empty():
		var names: PackedStringArray = []
		for completed: Dictionary in completed_sets:
			for card_set: Dictionary in ConfigDatabase.card_collection.get("card_sets", []):
				if int(card_set.set_id) == int(completed.get("set_id", 0)):
					names.append(str(card_set.name))
		var set_label: Label = _label("卡组集齐：" + "、".join(names), 19, Color("eed5a3"))
		set_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result.add_child(set_label)
		var reward_label: Label = _label("奖励已到账：" + _reward_text(data.get("rewards", {})), 17, Color("eed5a3"))
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result.add_child(reward_label)
	_result.add_child(_label("开包所得", 21, Color("eed5a3")))
	var grid := GridContainer.new()
	_result.add_child(grid)
	_card_grids.append(grid)
	for drawn: Dictionary in data.get("cards", []):
		for card: Dictionary in ConfigDatabase.card_collection.get("cards", []):
			if int(card.card_id) == int(drawn.card_id):
				grid.add_child(_card_tile(card, int(drawn.count), ("新获得" if bool(drawn.is_new) else "重复卡") + " +%d" % int(drawn.get("gained", 1))))
	var skip: Button = _button("全部展示 / 跳过动画")
	skip.pressed.connect(func() -> void:
		if _reveal_tween and _reveal_tween.is_valid():
			_reveal_tween.kill()
		for tile: Control in grid.get_children():
			tile.modulate.a = 1.0
	)
	_result.add_child(skip)


func _build_exchange_controls(busy: bool) -> void:
	var collection: Dictionary = {}
	for entry: Dictionary in ConfigDatabase.card_collection.get("collections", []):
		if int(entry.collection_id) == collection_id:
			collection = entry
	var progress: Dictionary = GameState.get_card_collection_progress(collection_id)
	var points: int = int(progress.get("duplicate_points", 0))
	var total: int = int(progress.get("total_duplicate_points", 0))
	_points_label = _label("集卡积分：%d · 累计获得：%d" % [points, total], 20, Color("eed5a3"))
	_points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_points_label)
	var rates: Array = collection.get("duplicate_points_by_star", [1, 2, 3, 4, 5])
	var descriptions: PackedStringArray = []
	for index: int in range(rates.size()):
		descriptions.append("%d星 +%d" % [index + 1, int(rates[index])])
	var rule: Label = _label("重复卡返积分：" + " / ".join(descriptions), 14, Color("a9bdb5"))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(rule)
	var cost: int = int(collection.get("exchange_cost", 200))
	var pack_id: int = int(collection.get("exchange_pack_id", 0))
	_exchange_button = _button("兑换5星卡包 · %d积分" % cost)
	_exchange_button.disabled = busy or not _is_active() or pack_id <= 0 or points < cost
	_exchange_button.tooltip_text = "兑换一个5星卡包，放入物品暂存区"
	_exchange_button.pressed.connect(func() -> void:
		CloudService.submit_card_collection("exchange", collection_id, 0)
		_refresh()
	)
	_body.add_child(_exchange_button)


func _card_tile(card: Dictionary, count: int, badge: String = "") -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(120, 145)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var color: Color = STAR_COLORS[int(card.star) - 1] if count > 0 else Color("526b69")
	tile.add_theme_stylebox_override("panel", _style(Color("203a3d") if count > 0 else Color("172a2d"), color, 10))
	var box := VBoxContainer.new()
	tile.add_child(box)
	box.add_child(_label("★".repeat(int(card.star)), 15, color))
	var icon_path: String = str(card.get("icon", ""))
	if count > 0 and not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path) as Texture2D
		icon.custom_minimum_size = Vector2(0, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
	else:
		var mark: Label = _label(str(card.name).left(1) if count > 0 else "？", 32, color)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(mark)
	var title: Label = _label(str(card.name), 15, color)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	box.add_child(_label(badge if not badge.is_empty() else ("已收集 ×%d" % count if count > 0 else "尚未收集"), 13, color))
	return tile


func _show_pack_details(pack: Dictionary) -> void:
	var weights: Array = pack.get("normal_weights", [])
	var weight_sum: float = 0.0
	for weight: Variant in weights:
		weight_sum += float(weight)
	var rates: PackedStringArray = []
	for i: int in range(weights.size()):
		rates.append("%d星 %.1f%%" % [i + 1, float(weights[i]) * 100.0 / maxf(1.0, weight_sum)])
	var sources: PackedStringArray = ["配置了此卡包的任务奖励"]
	if int(pack.get("star", 0)) == 4:
		sources.append("完成周天奖励")
	var source_names: Dictionary = {"order": "订单价值", "circulation": "周天序号"}
	for source: Dictionary in ConfigDatabase.card_collection.get("source_rewards", []):
		if int(source.pack_id) == int(pack.pack_id) and bool(source.get("enabled", true)):
			sources.append("%s达到%d（按最高档发放）" % [str(source_names.get(str(source.source_type), "进度")), int(source.min_value)])
	_status.text = "%s：%d张，必含1张%d星卡。其余卡位：%s。来源：%s。同星卡等概率，允许重复。" % [str(pack.name), int(pack.card_count), int(pack.star), " / ".join(rates), "；".join(sources)]


func _resize_grids() -> void:
	for grid: GridContainer in _card_grids:
		if is_instance_valid(grid):
			grid.columns = clampi(int((size.x * 0.92 - 40.0) / 135.0), 2, 5)


func _count(data: Dictionary, id: int) -> int:
	return int(data.get(str(id), data.get(id, 0)))


func _reward_text(rewards: Dictionary) -> String:
	var parts: PackedStringArray = []
	for token: Dictionary in rewards.get("tokens", []):
		parts.append("%d %s" % [int(token.amount), "体力" if int(token.token) == 3 else "灵石"])
	return " + ".join(parts)


func _label(value: String, font_size: int = 16, color: Color = Color("d9e5da")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 15)
	return button


func _style(background: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
