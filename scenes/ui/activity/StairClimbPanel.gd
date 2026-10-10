class_name StairClimbPanel extends BasePopup

const GOLD := Color("eed5a3")
const MUTED := Color("b0c7c1")
var _title: Label
var _countdown: Label
var _summary: Label
var _rules: Label
var _status: Label
var _board: VBoxContainer
var _rewards: VBoxContainer
var _refresh_button: Button
var _busy: bool = false
var _last_fetch: int = 0
var _last_second: int = -1
var _rewards_open: bool = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_anchor(SIDE_LEFT, 0.045)
	panel.set_anchor(SIDE_RIGHT, 0.955)
	panel.set_anchor(SIDE_TOP, 0.04)
	panel.set_anchor(SIDE_BOTTOM, 0.96)
	panel.add_theme_stylebox_override("panel", _style(Color("142b2e"), Color("a68a54")))
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_title = _label("爬天梯", 32, GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := _button("关闭")
	close.pressed.connect(func() -> void: UIManager.hide_popup(self))
	header.add_child(close)
	_countdown = _label("三日登阶 · 同境争锋", 20, GOLD)
	layout.add_child(_countdown)
	_summary = _label("正在载入我的排名…", 24)
	layout.add_child(_summary)
	_rules = _label("20 人同境界比拼，完成订单累积积分。人数不足由机器人补齐。", 17, MUTED)
	layout.add_child(_rules)
	_status = _label("正在读取排行榜…", 17, MUTED)
	layout.add_child(_status)
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	_refresh_button = _button("刷新排名")
	_refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_button.pressed.connect(_request)
	actions.add_child(_refresh_button)
	var reward_button := _button("排名奖励")
	reward_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_button.pressed.connect(func() -> void:
		_rewards_open = not _rewards_open
		_refresh()
	)
	actions.add_child(reward_button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_rewards = VBoxContainer.new()
	_rewards.add_theme_constant_override("separation", 8)
	content.add_child(_rewards)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 8)
	content.add_child(_board)
	CloudService.stair_climb_loaded.connect(_on_loaded)
	CloudService.stair_climb_failed.connect(_on_failed)
	CloudService.meridian_complete_confirmed.connect(_on_order)
	_refresh()


func setup(_activity_id: int) -> void:
	_request()


func _request() -> void:
	if _busy:
		return
	_busy = true
	_last_fetch = Time.get_ticks_msec()
	_refresh_button.disabled = true
	_status.text = "正在读取排行榜…"
	CloudService.fetch_stair_climb()


func _on_loaded(_data: Dictionary) -> void:
	_busy = false
	_refresh_button.disabled = false
	_refresh()


func _on_failed(_reason: String) -> void:
	_busy = false
	_refresh_button.disabled = false
	_status.text = "排名暂未更新，请点击刷新重试。"


func _on_order(_result: Dictionary) -> void:
	_request()


func _process(_delta: float) -> void:
	var second: int = int(Time.get_ticks_msec() / 1000)
	if second != _last_second and is_node_ready():
		_last_second = second
		_update_countdown()
	if not _busy and is_visible_in_tree() and Time.get_ticks_msec() - _last_fetch >= 30000:
		_request()


func _server_now() -> int:
	return int(ActivityManager.stair_climb.get("server_now", 0)) + Time.get_ticks_msec() - ActivityManager.stair_climb_received_ticks


func _update_countdown() -> void:
	var data: Dictionary = ActivityManager.stair_climb
	if data.is_empty():
		return
	var remaining: int = maxi(0, int((int(data.get("end_time", 0)) - _server_now()) / 1000))
	_countdown.text = "剩余 %d天 %02d:%02d:%02d" % [remaining / 86400, (remaining % 86400) / 3600, (remaining % 3600) / 60, remaining % 60] if remaining > 0 else "活动已结束 · 积分停止累计"


func _refresh() -> void:
	if not is_node_ready():
		return
	_clear(_board)
	_clear(_rewards)
	var data: Dictionary = ActivityManager.stair_climb
	if data.is_empty():
		return
	_update_countdown()
	var rank: int = int(data.get("my_rank", 0))
	_summary.text = "%s · 第 %d 名 · %d 积分" % [str(data.get("realm_name", "")), rank, int(data.get("my_points", 0))] if rank > 0 else "本期尚未参赛"
	_rules.text = "订单积分 = 物品总价值 × %s，向下取整（有效订单至少 1 分）。20 人同境界分组，机器人补齐；同分先达者优先。" % str(data.get("order_points_ratio", 0.1))
	var settlement: Dictionary = data.get("settlement", {}) if data.get("settlement") is Dictionary else {}
	var reward: Dictionary = settlement.get("reward", {})
	if not settlement.is_empty():
		_status.text = "最终第 %d 名 · 已到账：%d 体力 / %d 灵石" % [int(settlement.get("rank", rank)), int(reward.get("stamina", 0)), int(reward.get("spirit_stones", 0))]
	elif str(data.get("status", "")) in ["ended", "settling"]:
		_status.text = "正在结算最终排名，奖励将自动发放。"
	elif str(data.get("status", "")) == "disabled":
		_status.text = "活动暂未开放。"
	else:
		for tier: Dictionary in data.get("rewards", []):
			if rank >= int(tier.min_rank) and rank <= int(tier.max_rank):
				_status.text = "当前预计奖励：%d 体力 / %d 灵石 · 以结束时排名为准" % [int(tier.stamina), int(tier.spirit_stones)]
	_rewards.visible = _rewards_open
	if _rewards_open:
		_rewards.add_child(_label("排名奖励 · 结束后自动到账", 22, GOLD))
		for tier: Dictionary in data.get("rewards", []):
			var range_text: String = str(tier.min_rank) if int(tier.min_rank) == int(tier.max_rank) else "%d～%d" % [int(tier.min_rank), int(tier.max_rank)]
			_rewards.add_child(_label("第 %s 名     %d 体力 / %d 灵石" % [range_text, int(tier.stamina), int(tier.spirit_stones)], 18))
	_board.add_child(_label("本组排行榜", 22, GOLD))
	var rows: Array = data.get("rows", [])
	if rows.is_empty():
		_board.add_child(_label("活动开启后自动分组，完成订单即可参与比拼。", 18, MUTED))
	for row: Dictionary in rows:
		var mine: bool = bool(row.get("is_self", false))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(Color("28514a") if mine else Color("1a3538"), Color("dbb96d") if mine else Color("355459")))
		_board.add_child(card)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		card.add_child(line)
		var place := _label(str(row.get("rank", 0)), 24, GOLD if int(row.get("rank", 0)) <= 3 else MUTED)
		place.autowrap_mode = TextServer.AUTOWRAP_OFF
		place.custom_minimum_size.x = 42
		line.add_child(place)
		var player_name: String = "我" if mine else str(row.get("name", "道友"))
		if bool(row.get("bot", false)):
			player_name += " · 机器人"
		var player := _label(player_name, 20)
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player.autowrap_mode = TextServer.AUTOWRAP_OFF
		player.clip_text = true
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(player)
		var points := _label("%d 分" % int(row.get("points", 0)), 22, GOLD if mine else Color.WHITE)
		points.autowrap_mode = TextServer.AUTOWRAP_OFF
		points.custom_minimum_size.x = 120
		points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(points)


func _clear(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _label(value: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 20)
	return button


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
