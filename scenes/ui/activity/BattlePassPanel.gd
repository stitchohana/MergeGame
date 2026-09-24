class_name BattlePassPanel extends BasePopup

@onready var title_label: Label = $Panel/Content/Header/Title
@onready var points_icon: TextureRect = $Panel/Content/ProgressRow/PointsIcon
@onready var points_label: Label = $Panel/Content/ProgressRow/Progress
@onready var unlock_button: Button = $Panel/Content/UnlockButton
@onready var tiers_scroll: ScrollContainer = $Panel/Content/Scroll
@onready var tiers_box: VBoxContainer = $Panel/Content/Scroll/Tiers
@onready var status_label: Label = $Panel/Content/Status

var _activity_id: int = 0
var _pending: bool = false
var _activity_active: bool = false
var _error_message: String = ""
var _activity_end_text: String = ""


func _ready() -> void:
	$Panel/Content/Header/CloseButton.pressed.connect(_on_close)
	unlock_button.pressed.connect(_on_unlock)
	if not CloudService.battle_pass_action_confirmed.is_connected(_on_action_confirmed):
		CloudService.battle_pass_action_confirmed.connect(_on_action_confirmed)
	if not CloudService.battle_pass_action_rejected.is_connected(_on_action_rejected):
		CloudService.battle_pass_action_rejected.connect(_on_action_rejected)
	if not GameState.battle_pass_changed.is_connected(_on_progress_changed):
		GameState.battle_pass_changed.connect(_on_progress_changed)
	if not CloudService.state_loaded.is_connected(_on_state_loaded):
		CloudService.state_loaded.connect(_on_state_loaded)


func setup(activity_id: int) -> void:
	_activity_id = activity_id
	_refresh()


func _refresh() -> void:
	if not is_node_ready() or _activity_id <= 0:
		return
	var pass_data: Dictionary = ConfigDatabase.get_battle_pass(_activity_id)
	var points_token: Dictionary = ConfigDatabase.get_token_data(int(pass_data.get("points_token_id", 0)))
	var points_icon_path: String = str(points_token.get("icon", ""))
	points_icon.texture = load(points_icon_path) as Texture2D if not points_icon_path.is_empty() and ResourceLoader.exists(points_icon_path) else null
	var activity_name: String = "战令"
	_activity_active = false
	_activity_end_text = ""
	for activity: Variant in GameState.activity_defs:
		if activity is Dictionary and int(activity.get("id", 0)) == _activity_id:
			activity_name = str(activity.get("name", activity_name))
			_activity_active = bool(activity.get("active", false))
			var end_time: String = str(activity.get("end_time", ""))
			if not end_time.is_empty():
				_activity_end_text = " · 截止 %s" % end_time.replace("T", " ").replace("Z", " UTC")
			break
	title_label.text = activity_name
	var progress: Dictionary = _get_progress()
	var points: int = int(progress.get("points", 0))
	var tiers: Array = pass_data.get("tiers", [])
	var max_points: int = int(tiers.back().get("required_points", 0)) if not tiers.is_empty() else 0
	points_label.text = "%d / %d 战令积分" % [points, max_points]
	var unlocked: bool = bool(progress.get("premium_unlocked", false))
	unlock_button.visible = not unlocked and _activity_active
	unlock_button.disabled = _pending or unlocked or not _activity_active
	unlock_button.text = "解锁进阶线 · %d 灵石" % int(ConfigDatabase.get_game_config("battle_pass.premium_unlock_cost", 0))
	status_label.text = _error_message if not _error_message.is_empty() else (("活动当前不可参与" if not _activity_active else ("进阶线已解锁" if unlocked else "免费线始终开放 · 解锁进阶线可领取第二轨奖励")) + _activity_end_text)
	var scroll_position: int = tiers_scroll.scroll_vertical
	for child: Node in tiers_box.get_children():
		tiers_box.remove_child(child)
		child.queue_free()
	for tier_value: Variant in tiers:
		if tier_value is Dictionary:
			_add_tier(tier_value, progress)
	tiers_scroll.set_deferred("scroll_vertical", scroll_position)


func _get_progress() -> Dictionary:
	if GameState.battle_pass_progress.has(_activity_id):
		return GameState.battle_pass_progress[_activity_id]
	return GameState.battle_pass_progress.get(str(_activity_id), {})


func _add_tier(tier: Dictionary, progress: Dictionary) -> void:
	var level: int = int(tier.get("level", 0))
	var required_points: int = int(tier.get("required_points", 0))
	var points: int = int(progress.get("points", 0))
	var claimed_free: Variant = progress.get("free_claimed_levels", [])
	var claimed_premium: Variant = progress.get("premium_claimed_levels", [])
	var premium_unlocked: bool = bool(progress.get("premium_unlocked", false))
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 88)
	row.add_theme_constant_override("separation", 10)
	var level_label := Label.new()
	level_label.custom_minimum_size = Vector2(68, 0)
	level_label.text = "Lv.%02d · %d 分" % [level, required_points]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_color_override("font_color", Color("#eed9a5"))
	level_label.add_theme_font_size_override("font_size", 15)
	row.add_child(level_label)
	row.add_child(_make_reward_button(tier.get("free_rewards", {}), "免费", level, "free", points >= required_points and _activity_active, _has_claimed_level(claimed_free, level)))
	row.add_child(_make_reward_button(tier.get("premium_rewards", {}), "进阶", level, "premium", points >= required_points and premium_unlocked and _activity_active, _has_claimed_level(claimed_premium, level)))
	tiers_box.add_child(row)


func _has_claimed_level(claimed_levels: Variant, level: int) -> bool:
	if not claimed_levels is Array:
		return false
	for claimed_value: Variant in claimed_levels:
		if int(claimed_value) == level:
			return true
	return false


func _make_reward_button(reward_value: Variant, track_name: String, level: int, track: String, can_claim: bool, claimed: bool) -> Button:
	var rewards: Dictionary = reward_value if reward_value is Dictionary else {}
	var tokens: Array = rewards.get("tokens", [])
	var amount: int = int(tokens[0].get("amount", 0)) if not tokens.is_empty() and tokens[0] is Dictionary else 0
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 76)
	button.add_theme_font_size_override("font_size", 14)
	if not tokens.is_empty() and tokens[0] is Dictionary:
		var token_data: Dictionary = ConfigDatabase.get_token_data(int(tokens[0].get("token", 0)))
		var icon_path: String = str(token_data.get("icon", ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			button.icon = load(icon_path) as Texture2D
			button.expand_icon = true
			button.add_theme_constant_override("h_separation", 8)
	if claimed:
		button.text = "%s · 已领取" % track_name
		button.disabled = true
	elif not can_claim:
		button.text = "%s · %s" % [track_name, "未解锁" if track == "premium" else "未达成"]
		button.disabled = true
	else:
		button.text = "%s · 领取 %d 体力" % [track_name, amount]
		button.disabled = _pending
		button.pressed.connect(_on_claim.bind(level, track, button))
	return button


func _on_unlock() -> void:
	if _pending:
		return
	_pending = true
	unlock_button.text = "解锁中..."
	_show_pending("进阶线解锁中...")
	CloudService.submit_battle_pass_unlock(_activity_id)


func _on_claim(level: int, track: String, button: Button) -> void:
	if _pending:
		return
	_pending = true
	button.text = "%s · 领取中..." % ("进阶" if track == "premium" else "免费")
	_show_pending("奖励领取中...")
	CloudService.submit_battle_pass_claim(_activity_id, level, track)


func _show_pending(message: String) -> void:
	status_label.text = message
	unlock_button.disabled = true
	for row: Node in tiers_box.get_children():
		for child: Node in row.get_children():
			if child is Button:
				child.disabled = true


func _on_action_confirmed(result: Dictionary) -> void:
	_pending = false
	_error_message = ""
	_refresh()
	EventBus.show_toast.emit("战令奖励已领取" if result.has("rewards") else "进阶线已解锁")


func _on_action_rejected(reason: String) -> void:
	_pending = false
	_error_message = "操作失败：%s" % _friendly_error(reason)
	_refresh()
	EventBus.show_toast.emit(_error_message)
	if reason == "already_claimed":
		CloudService.fetch_state()


func _on_progress_changed(_progress: Dictionary) -> void:
	_error_message = ""
	_refresh()


func _on_state_loaded(_state: Dictionary) -> void:
	_error_message = ""
	_refresh()


func _friendly_error(reason: String) -> String:
	match reason:
		"insufficient_spirit_stones":
			return "灵石不足"
		"insufficient_points":
			return "战令积分不足"
		"premium_not_unlocked":
			return "请先解锁进阶线"
		"already_claimed":
			return "奖励已领取"
		"activity_inactive":
			return "活动尚未开启或已结束"
		_:
			return reason


func _on_close() -> void:
	UIManager.hide_popup(self)
