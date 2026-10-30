class_name OrderDuelPanel extends BasePopup

const GOLD := Color("eed5a3")
const MUTED := Color("acc4c1")
var _status: Label
var _rules: Label
var _result: Label
var _score: Label
var _mine: ProgressBar
var _opponent: ProgressBar
var _opponent_name: Label
var _rewards: VBoxContainer
var _start: Button
var _rest: Button
var _refresh_button: Button
var _busy: bool = false
var _reward_signature: String = ""


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
	var title := _label("订单对战", 32, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _button("关闭")
	close.pressed.connect(func() -> void: UIManager.hide_popup(self))
	header.add_child(close)
	layout.add_child(_label("同台论道 · 先达者胜", 22, GOLD))
	_rules = _label("完成订单获取对战积分，获胜后自动匹配下一位道友。", 17, MUTED)
	layout.add_child(_rules)
	_status = _label("正在同步对战…", 21, GOLD)
	layout.add_child(_status)
	var arena := PanelContainer.new()
	arena.add_theme_stylebox_override("panel", _style(Color("1b393b"), Color("53716c")))
	layout.add_child(arena)
	var race := VBoxContainer.new()
	race.add_theme_constant_override("separation", 10)
	arena.add_child(race)
	race.add_child(_label("我 · 对战积分", 20, GOLD))
	_mine = _bar(Color("68bb9a"))
	race.add_child(_mine)
	_opponent_name = _label("等待道友 · 对战积分", 20, MUTED)
	race.add_child(_opponent_name)
	_opponent = _bar(Color("dba76b"))
	race.add_child(_opponent)
	_result = _label("", 18, GOLD)
	layout.add_child(_result)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	layout.add_child(actions)
	_start = _button("开始匹配")
	_start.pressed.connect(func() -> void: _action("start", int(ActivityManager.order_duel.get("round", 0))))
	actions.add_child(_start)
	_rest = _button("休息一下")
	_rest.pressed.connect(func() -> void: _action("rest", int(ActivityManager.order_duel.get("round", 0))))
	actions.add_child(_rest)
	_refresh_button = _button("刷新")
	_refresh_button.pressed.connect(_request)
	actions.add_child(_refresh_button)
	_score = _label("累计胜利积分  0", 24, GOLD)
	layout.add_child(_score)
	layout.add_child(_label("十档论道礼 · 达标即可领取，积分不消耗", 17, MUTED))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_rewards = VBoxContainer.new()
	_rewards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rewards.add_theme_constant_override("separation", 10)
	scroll.add_child(_rewards)
	CloudService.order_duel_loaded.connect(_on_loaded)
	CloudService.order_duel_failed.connect(_on_failed)
	ActivityManager.order_duel_updated.connect(_refresh)
	_refresh()


func setup(_activity_id: int) -> void:
	_request()


func _request() -> void:
	if _busy:
		return
	_busy = true
	_refresh()
	CloudService.fetch_order_duel()


func _action(action: String, value: int) -> void:
	if _busy:
		return
	_busy = true
	_refresh()
	CloudService.submit_order_duel(action, value)


func _on_loaded(_data: Dictionary) -> void:
	_busy = false
	_refresh()


func _on_failed(reason: String) -> void:
	_busy = false
	_refresh()
	var messages: Dictionary = {"state_conflict": "对战已更新，请刷新后重试。", "insufficient_points": "胜利积分尚未达标。", "activity_inactive": "活动当前不可参与。"}
	_status.text = str(messages.get(reason, "同步未完成，请刷新重试。"))


func _refresh() -> void:
	if not is_node_ready():
		return
	var data: Dictionary = ActivityManager.order_duel
	var settings: Dictionary = data.get("settings", {})
	var state: String = str(data.get("status", "resting"))
	var active: bool = bool(data.get("active", false))
	var target: int = maxi(1, int(settings.get("target_points", 100)))
	var opponent: Dictionary = data.get("opponent", {}) if data.get("opponent") is Dictionary else {}
	var my_points: int = int(data.get("my_points", 0))
	var opponent_points: int = int(opponent.get("points", 0))
	_mine.max_value = target
	_mine.value = my_points
	_mine.tooltip_text = "%d / %d 对战积分" % [my_points, target]
	_opponent.max_value = target
	_opponent.value = opponent_points
	_opponent.tooltip_text = "%d / %d 对战积分" % [opponent_points, target]
	_opponent_name.text = "%s · %d / %d" % [str(opponent.get("name", "等待道友")), opponent_points, target]
	var states: Dictionary = {"resting": "休息中 · 准备好即可参战", "matching": "正在随机匹配道友，%d 秒后机器人补位" % int(settings.get("matchmaking_seconds", 1)), "playing": "我的积分 %d / %d · 率先达标获胜" % [my_points, target], "lost": "本场惜败 · 休息一下，或再战一场", "locked": "活动尚未解锁"}
	_status.text = str(states.get(state, "正在同步对战…")) if active else "活动当前未开放"
	if _busy:
		_status.text = "正在同步对战…"
	_rules.text = "订单价值 × %s = 对战积分（有效订单至少 1 分）。先达 %d 分获胜，奖励 %d 体力 + %d 胜利积分。胜利自动续战；关闭界面不暂停对战。" % [str(settings.get("order_points_ratio", 0.1)), target, int(settings.get("win_stamina", 30)), int(settings.get("win_points", 10))]
	var result: Dictionary = data.get("last_result", {}) if data.get("last_result") is Dictionary else {}
	_result.visible = not result.is_empty()
	_result.text = "上场获胜 · 已到账 %d 体力、%d 胜利积分" % [int(result.get("stamina", 0)), int(result.get("victory_points", 0))] if bool(result.get("won", false)) else "上场惜败 · %d : %d，下一场重新出发" % [int(result.get("my_points", 0)), int(result.get("opponent_points", 0))]
	_start.visible = state in ["resting", "lost"] and active
	_start.text = "下一场对战" if state == "lost" else "开始匹配"
	_start.disabled = _busy
	_rest.visible = state == "lost"
	_rest.disabled = _busy
	_refresh_button.disabled = _busy
	var points: int = int(data.get("victory_points", 0))
	_score.text = "累计胜利积分  %d" % points
	var claimed: Array = data.get("claimed_tiers", [])
	var signature: String = JSON.stringify([points, claimed, data.get("rewards", []), _busy])
	if signature == _reward_signature:
		return
	_reward_signature = signature
	for child: Node in _rewards.get_children():
		_rewards.remove_child(child)
		child.queue_free()
	for reward: Dictionary in data.get("rewards", []):
		var tier: int = int(reward.get("tier", 0))
		var threshold: int = int(reward.get("required_points", 0))
		var collected: bool = claimed.has(tier) or claimed.has(float(tier))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(Color("254c43") if points >= threshold else Color("1a3336"), Color("8b9a63") if points >= threshold else Color("355459")))
		_rewards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text_label := _label("第 %d 档 · %d 胜利积分\n%d 体力 / %d 灵石" % [tier, threshold, int(reward.get("stamina", 0)), int(reward.get("spirit_stones", 0))], 18, GOLD if points >= threshold else MUTED)
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_label)
		var claim := _button("已领取" if collected else "领取" if points >= threshold else "未解锁")
		claim.disabled = _busy or collected or points < threshold
		claim.pressed.connect(_action.bind("claim", tier))
		row.add_child(claim)


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 24
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("10282c"), Color("355459")))
	bar.add_theme_stylebox_override("fill", _style(color, color))
	return bar


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
	button.custom_minimum_size = Vector2(100, 52)
	button.add_theme_font_size_override("font_size", 19)
	return button


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
