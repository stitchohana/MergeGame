class_name CardCollectionPanel extends BasePopup

const STAR_COLORS: Array[Color] = [Color("b5c7bf"), Color("74c6a4"), Color("7eafe4"), Color("ba95dd"), Color("efd081")]
var collection_id: int = 1
var _activity_id: int = 5
var _body: VBoxContainer
var _status: Label
var _summary: Label
var _retry: Button
var _result: VBoxContainer
var _reveal_tween: Tween
var _result_data: Dictionary = {}
var _card_grids: Array[GridContainer] = []


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
	var title: Label = _label("万象仙册", 28, Color("eed5a3"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = _button("关闭")
	close.pressed.connect(func() -> void: UIManager.hide_popup(self))
	header.add_child(close)
	_summary = _label("收集山海万象 · 集齐卡组领取厚礼", 17)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_summary)
	_status = _label("完成任务、提交订单、运转周天，获得卡包", 14, Color("a9bdb5"))
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


func setup(activity_id: int) -> void:
	_activity_id = activity_id
	for collection: Dictionary in ConfigDatabase.card_collection.get("collections", []):
		if int(collection.activity_id) == activity_id:
			collection_id = int(collection.collection_id)
	_refresh()


func _on_state(_data: Dictionary) -> void:
	_refresh()


func _is_active() -> bool:
	for activity: Dictionary in GameState.activity_defs:
		if int(activity.get("id", 0)) == _activity_id:
			return bool(activity.get("active", false))
	return false


func _refresh() -> void:
	if not is_node_ready():
		return
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_card_grids.clear()
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var config: Dictionary = ConfigDatabase.card_collection
	var progress: Dictionary = GameState.get_card_collection_progress(collection_id)
	var owned: Dictionary = progress.get("cards", {})
	var packs: Dictionary = progress.get("packs", {})
	var busy: bool = CloudService.card_collection_busy or not CloudService.card_collection_request.is_empty()
	var active: bool = _is_active()
	_retry.visible = not CloudService.card_collection_request.is_empty()
	_retry.disabled = CloudService.card_collection_busy
	_status.text = "正在结算，请稍候…" if CloudService.card_collection_busy else ("上次操作未确认，请重试以恢复结果" if busy else ("完成任务、提交订单、运转周天，获得卡包" if active else "活动当前不可参与，已收集卡片会保留"))
	_body.add_child(_label("我的卡包", 21, Color("eed5a3")))
	for pack: Dictionary in config.get("packs", []):
		if int(pack.collection_id) != collection_id:
			continue
		var row := HBoxContainer.new()
		_body.add_child(row)
		var pack_icon_path: String = str(pack.get("icon", ""))
		if not pack_icon_path.is_empty() and ResourceLoader.exists(pack_icon_path):
			var pack_icon := TextureRect.new()
			pack_icon.custom_minimum_size = Vector2(40, 40)
			pack_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pack_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pack_icon.texture = load(pack_icon_path) as Texture2D
			row.add_child(pack_icon)
		var star: int = int(pack.star)
		var info: Label = _label("%s  %s\n%d 张卡 · 必得 1 张 %d 星卡" % ["★".repeat(star), str(pack.name), int(pack.card_count), star], 16, STAR_COLORS[star - 1])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var count: int = _count(packs, int(pack.pack_id))
		var open: Button = _button("开启 ×%d" % count)
		open.disabled = count <= 0 or busy or not active
		open.pressed.connect(_submit.bind("open", int(pack.pack_id)))
		row.add_child(open)
		var details: Button = _button("详情")
		details.pressed.connect(_show_pack_details.bind(pack))
		row.add_child(details)
	if not _result_data.is_empty():
		_build_result(_result_data)
	else:
		var last_open: Dictionary = progress.get("last_open", {})
		if not last_open.is_empty():
			var last_button: Button = _button("查看上次开包结果")
			last_button.pressed.connect(func() -> void:
				_result_data = last_open
				_refresh()
			)
			_body.add_child(last_button)
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
		var claim: Button = _button(("已领取 · " if claimed else "集齐领取 · ") + _reward_text(card_set.get("rewards", {})))
		claim.disabled = busy or not active or claimed or set_count < set_cards.size()
		claim.pressed.connect(_submit.bind("claim", int(card_set.set_id)))
		section.add_child(claim)
	_summary.text = "已收集 %d / %d 张 · 集齐卡组领取体力与灵石" % [collected, total]
	_resize_grids()


func _submit(action: String, target: int) -> void:
	CloudService.submit_card_collection(action, collection_id, target)
	_refresh()


func _on_confirmed(data: Dictionary) -> void:
	if int(data.get("collection_id", 0)) != collection_id:
		return
	if data.has("cards"):
		_result_data = data
	else:
		EventBus.show_toast.emit("卡组奖励到账：" + _reward_text(data.get("rewards", {})))
	_refresh()
	if data.has("cards"):
		_reveal_tween = create_tween()
		for child: Node in _result.get_children():
			if child is GridContainer:
				for tile: Control in child.get_children():
					tile.modulate.a = 0.0
					_reveal_tween.tween_property(tile, "modulate:a", 1.0, 0.16)


func _on_rejected(reason: String) -> void:
	_refresh()
	var messages: Dictionary = {"insufficient_packs": "卡包不足", "activity_inactive": "活动当前不可参与", "state_conflict": "进度已更新，正在同步", "already_claimed": "奖励已领取", "set_incomplete": "卡组尚未集齐", "pending_operation": "请先重试上次操作", "save_failed": "保存未完成，请重试"}
	_status.text = str(messages.get(reason, "操作未确认，请检查网络后重试"))


func _build_result(data: Dictionary) -> void:
	_result = VBoxContainer.new()
	_body.add_child(_result)
	_result.add_child(_label("开包所得", 21, Color("eed5a3")))
	var grid := GridContainer.new()
	_result.add_child(grid)
	_card_grids.append(grid)
	for drawn: Dictionary in data.get("cards", []):
		for card: Dictionary in ConfigDatabase.card_collection.get("cards", []):
			if int(card.card_id) == int(drawn.card_id):
				grid.add_child(_card_tile(card, int(drawn.count), "新获得" if bool(drawn.is_new) else "重复卡 +1"))
	var skip: Button = _button("全部展示 / 跳过动画")
	skip.pressed.connect(func() -> void:
		if _reveal_tween and _reveal_tween.is_valid():
			_reveal_tween.kill()
		for tile: Control in grid.get_children():
			tile.modulate.a = 1.0
	)
	_result.add_child(skip)


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
	var sources: PackedStringArray = []
	var source_names: Dictionary = {"quest": "任务目标数", "order": "订单价值", "circulation": "周天序号"}
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
