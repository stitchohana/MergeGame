extends BasePopup

var artifact_id: String = "basin"
var definition: Dictionary = {}
var offer: Dictionary = {}
var server_grid: Array = []
var materials: Array = []
var selected_uids: Array[int] = []
var preview: Dictionary = {}
var _pending: bool = false
var _using: bool = false
var _loading: bool = false
var _previewing: bool = false
var _preview_selection: Dictionary = {}
var _version: int = 0
var _period: String = ""
var title_label: Label
var info_label: Label
var message_label: Label
var mode: OptionButton
var target: OptionButton
var choices: VBoxContainer
var use_area: VBoxContainer
var enter_button: Button
var preview_button: Button
var use_button: Button
var buy_button: Button
var retry_button: Button
var close_button: Button
var panel_container: PanelContainer

func _ready() -> void:
	close_on_click_outside = false
	hide_animation_finished.connect(queue_free)
	for item: Dictionary in ConfigDatabase.golden_finger.get("artifacts", []):
		if str(item.get("id", "")) == artifact_id:
			definition = item
	_build()
	CloudService.golden_finger_info.connect(_on_info)
	CloudService.golden_finger_preview.connect(_on_preview)
	CloudService.golden_finger_confirmed.connect(_on_confirmed)
	CloudService.golden_finger_failed.connect(_on_failed)
	_load()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()

func _label(text: String, size: int = 24) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("345b50"))
	return label

func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 56
	button.add_theme_font_size_override("font_size", 23)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("e2e9d7")
	normal.border_color = Color("719687")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("cbdcc6")
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("b8cfb7")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("e5e2d4")
	disabled.border_color = Color("b9bba9")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("345b50"))
	button.add_theme_color_override("font_hover_color", Color("274c42"))
	button.add_theme_color_override("font_pressed_color", Color("274c42"))
	button.add_theme_color_override("font_disabled_color", Color("858878"))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.12, 0.1, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel_container = panel
	panel.anchor_left = 0.06
	panel.anchor_right = 0.94
	panel.anchor_top = 0.09
	panel.anchor_bottom = 0.55
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4f0dc")
	style.border_color = Color("719687")
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/artifact_%s.svg" % artifact_id) as Texture2D
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	title_label = _label(str(definition.get("name", "法宝")), 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title_label)
	content.add_child(_label(str(definition.get("description", ""))))
	info_label = _label("正在获取今日次数…", 22)
	content.add_child(info_label)
	enter_button = _button("前往使用", _enter_use, content)
	use_area = VBoxContainer.new()
	use_area.add_theme_constant_override("separation", 12)
	use_area.hide()
	content.add_child(use_area)
	mode = OptionButton.new()
	mode.add_item("流光 · 加速制作或发射器冷却")
	mode.add_item("溯时 · 撤销最近一次操作")
	mode.custom_minimum_size.y = 56
	_style_option(mode)
	mode.item_selected.connect(func(_index: int): _populate_choices())
	mode.visible = artifact_id == "sand"
	use_area.add_child(mode)
	target = OptionButton.new()
	target.custom_minimum_size.y = 56
	_style_option(target)
	target.item_selected.connect(func(_index: int): _clear_preview())
	use_area.add_child(target)
	var material_scroll := ScrollContainer.new()
	material_scroll.custom_minimum_size.y = 300
	material_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	use_area.add_child(material_scroll)
	choices = VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_scroll.add_child(choices)
	message_label = _label("先选择材料或目标，再预览结果。", 22)
	use_area.add_child(message_label)
	preview_button = _button("预览效果", _request_preview, use_area)
	use_button = _button("确认使用 · 消耗 1 次", _confirm_use, use_area)
	use_button.disabled = true
	buy_button = _button("获取加次价格…", _confirm_buy, content)
	buy_button.disabled = true
	retry_button = _button("重试上一笔操作", _retry, content)
	retry_button.hide()
	_button("刷新状态", _load, content)
	close_button = _button("关闭", _close, content)

func _load() -> void:
	if _pending or _loading:
		return
	_loading = true
	_clear_preview()
	_refresh_info()
	CloudService.fetch_golden_finger()

func _on_info(data: Dictionary) -> void:
	_loading = false
	_version = int(data.get("version", 0))
	server_grid = data.get("grid", [])
	materials = data.get("materials", [])
	var view: Dictionary = data.get("golden_finger", {})
	_period = str(view.get("period_key", ""))
	offer.clear()
	for item: Dictionary in view.get("artifacts", []):
		if str(item.get("id", "")) == artifact_id:
			offer = item.duplicate(true)
	_refresh_info()
	_populate_choices()

func _refresh_info() -> void:
	var unlocked: bool = bool(offer.get("unlocked", false))
	info_label.text = "解锁境界：%s\n免费剩余 %d 次 · 已购剩余 %d 次\n北京时间每日 05:00 重置，购买次数当日有效。" % [str(definition.get("unlock_label", "")), int(offer.get("free_remaining", 0)), int(offer.get("paid_remaining", 0))]
	enter_button.disabled = not unlocked or _loading or _pending
	enter_button.text = ("返回棋盘拖入物品" if artifact_id in ["basin", "furnace"] else "前往使用") if unlocked else str(definition.get("unlock_label", "")) + "解锁"
	buy_button.text = "%d 灵石增加 1 次 · 今日还可购买 %d 次" % [int(offer.get("next_cost", 0)), int(offer.get("purchases_remaining", 0))]
	var unresolved: bool = not CloudService.golden_finger_retry.is_empty()
	buy_button.disabled = not unlocked or _pending or _loading or _previewing or unresolved or int(offer.get("purchases_remaining", 0)) <= 0
	use_button.disabled = preview.is_empty() or _pending or _loading or _previewing or unresolved or int(offer.get("remaining", 0)) <= 0
	close_button.disabled = _pending
	retry_button.visible = not CloudService.golden_finger_retry.is_empty()

func _enter_use() -> void:
	if artifact_id == "furnace":
		EventBus.show_toast.emit("将一件物品拖到顶部万象炉，选择同级已解锁的其他物品进行转化")
		_close()
		return
	if artifact_id == "basin":
		EventBus.show_toast.emit("将一件低级材料拖到顶部聚宝盆，产出两个物品；空位不足时自动暂存")
		_close()
		return
	_using = true
	panel_container.anchor_bottom = 0.92
	use_area.show()
	enter_button.hide()
	_populate_choices()

func _populate_choices() -> void:
	selected_uids.clear()
	_clear_preview()
	target.clear()
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	target.visible = artifact_id == "furnace" or (artifact_id == "sand" and mode.selected == 0)
	if artifact_id == "furnace":
		for item: Dictionary in materials:
			target.add_item("%s · %d 级 · 价值 %d" % [str(item.get("name", "")), int(item.get("level", 0)), int(item.get("value", 0))])
			target.set_item_metadata(target.item_count - 1, int(item.get("id", 0)))
	if artifact_id == "sand":
		if mode.selected == 1:
			choices.add_child(_label("撤销最近一次合并、生成或出售。有效期 60 秒，后续相关操作会使回溯失效。", 22))
		else:
			for item: Dictionary in server_grid:
				var def: Dictionary = ConfigDatabase.get_item_data(int(item.get("id", 0)))
				var craft: Dictionary = item.get("craft", {})
				if int(craft.get("_craft_state", -1)) == 2 or (int(def.get("max_charges", 0)) > 0 and int(item.get("charges", 0)) < int(def.get("max_charges", 0))):
					target.add_item("%s · 第%d列第%d行" % [str(def.get("name", "")), int(item.get("col", 0)) + 1, int(item.get("row", 0)) + 1])
					target.set_item_metadata(target.item_count - 1, int(item.get("uid", 0)))
			choices.add_child(_label("选择一个等待中的设施。制作加速后仍需主动领取成品。", 22))
		return
	for item: Dictionary in server_grid:
		var id: int = int(item.get("id", 0))
		var def: Dictionary = ConfigDatabase.get_item_data(id)
		var valid: bool = false
		for candidate: Dictionary in materials:
			if int(candidate.get("id", 0)) == id:
				valid = true
		if not valid or bool(item.get("immovable", false)) or item.has("craft") or item.has("storage") or item.has("charges"):
			continue
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(54, 54)
		icon.texture = load(str(def.get("icon", ""))) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var check := CheckBox.new()
		check.text = "%s · 价值 %d · (%d,%d)" % [str(def.get("name", "")), int(def.get("value", 0)), int(item.get("col", 0)) + 1, int(item.get("row", 0)) + 1]
		check.custom_minimum_size.y = 56
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.add_theme_font_size_override("font_size", 21)
		check.add_theme_color_override("font_color", Color("345b50"))
		check.add_theme_color_override("font_hover_color", Color("274c42"))
		check.add_theme_color_override("font_pressed_color", Color("274c42"))
		var uid: int = int(item.get("uid", 0))
		check.toggled.connect(func(pressed: bool):
			if pressed:
				selected_uids.append(uid)
			else:
				selected_uids.erase(uid)
			_clear_preview()
		)
		row.add_child(check)
		choices.add_child(row)
	if choices.get_child_count() == 0:
		choices.add_child(_label("棋盘上暂无可用普通材料。", 22))

func _style_option(option: OptionButton) -> void:
	option.add_theme_font_size_override("font_size", 22)
	option.add_theme_color_override("font_color", Color("345b50"))
	option.add_theme_color_override("font_hover_color", Color("274c42"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e2e9d7")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 18
	option.add_theme_stylebox_override("normal", style)
	option.add_theme_stylebox_override("hover", style)
	option.get_popup().add_theme_font_size_override("font_size", 22)

func _selection() -> Dictionary:
	var body: Dictionary = {"artifact": artifact_id}
	if artifact_id == "sand":
		body["mode"] = "rewind" if mode.selected == 1 else "accelerate"
		if mode.selected == 0 and target.item_count > 0:
			body["uid"] = int(target.get_selected_metadata())
	else:
		body["uids"] = selected_uids.duplicate()
		if artifact_id == "furnace" and target.item_count > 0:
			body["target_id"] = int(target.get_selected_metadata())
	return body

func _clear_preview() -> void:
	preview.clear()
	if is_instance_valid(use_button):
		use_button.disabled = true

func _request_preview() -> void:
	if _pending or _previewing or _loading:
		return
	if artifact_id == "basin" and selected_uids.size() != 1:
		message_label.text = "聚宝盆需要选择恰好一件低级材料。"
		return
	_previewing = true
	preview_button.disabled = true
	_refresh_info()
	_preview_selection = _selection().duplicate(true)
	CloudService.preview_golden_finger(_preview_selection)

func _on_preview(data: Dictionary) -> void:
	if not _previewing:
		return
	_previewing = false
	preview_button.disabled = false
	if _selection() != _preview_selection:
		message_label.text = "选择已变化，请重新预览。"
		return
	preview = data.duplicate(true)
	_version = int(data.get("version", _version))
	var view: Dictionary = data.get("golden_finger", {})
	_period = str(view.get("period_key", _period))
	for item: Dictionary in view.get("artifacts", []):
		if str(item.get("id", "")) == artifact_id:
			offer = item.duplicate(true)
	if artifact_id != "sand":
		message_label.text = "将获得 %s ×%d，放入物品暂存区。" % [str(data.get("output_name", "")), int(data.get("output_count", 1))]
		if artifact_id == "furnace":
			message_label.text += "\n投入价值 %d · 目标价值 %d · 超额 %d 不返还。" % [int(data.get("input_value", 0)), int(data.get("output_value", 0)), int(data.get("excess_value", 0))]
	elif mode.selected == 0:
		message_label.text = "立即完成 %s 的等待，剩余 %d 秒。\n原灵石加速费用 %d，本次消耗法宝次数。" % [str(data.get("name", "")), int(data.get("remaining_seconds", 0)), int(data.get("original_cost", 0))]
	else:
		var operation_time: String = Time.get_time_string_from_unix_time(int(data.get("operation_at", 0)) / 1000 + int(Time.get_time_zone_from_system().bias) * 60)
		message_label.text = "撤销 %s 的%s，恢复操作前的物品、任务与资源。\n灵石 %+d · 体力 %+d · 灵力 %+d" % [operation_time, str(data.get("label", "操作")), int(data.get("stone_delta", 0)), int(data.get("stamina_delta", 0)), int(data.get("qi_delta", 0))]
	_refresh_info()

func _body() -> Dictionary:
	var body: Dictionary = _selection()
	body["version"] = _version
	body["period_key"] = _period
	body["request_id"] = "artifact-%s-%s" % [str(Time.get_ticks_usec()), str(randi())]
	return body

func _confirm_use() -> void:
	if preview.is_empty() or _pending or _loading or _previewing or not CloudService.golden_finger_retry.is_empty():
		return
	var body: Dictionary = _body()
	body["quote"] = preview.get("quote", {})
	var popup := preload("res://scenes/ui/common/ConfirmPopup.tscn").instantiate()
	UIManager.show_popup(popup)
	var warning: String = "\n消耗 1 次使用机会。"
	if artifact_id != "sand":
		warning += "材料可能包含订单所需物品，请确认。"
	popup.setup("使用" + str(definition.get("name", "法宝")), message_label.text + warning, func(): _send("use", body))
	_style_confirmation(popup)

func _confirm_buy() -> void:
	if _pending or _loading or _previewing or offer.is_empty() or not CloudService.golden_finger_retry.is_empty():
		return
	var cost: int = int(offer.get("next_cost", 0))
	if GameState.spirit_stones < cost:
		EventBus.show_toast.emit("灵石不足，需要 %d 灵石，当前拥有 %d" % [cost, GameState.spirit_stones])
		return
	var body: Dictionary = _body()
	body["expected_cost"] = int(offer.get("next_cost", 0))
	body["expected_purchase_count"] = int(offer.get("purchase_count", 0))
	var popup := preload("res://scenes/ui/common/ConfirmPopup.tscn").instantiate()
	UIManager.show_popup(popup)
	popup.setup("增加今日次数", "消耗 %d 灵石，为%s增加 1 次今日使用次数。\n次数在北京时间 05:00 重置时失效。" % [int(body.expected_cost), str(definition.get("name", "法宝"))], func(): _send("buy", body))
	_style_confirmation(popup)

func _style_confirmation(popup: ConfirmPopup) -> void:
	var panel: Panel = popup.get_node("Panel")
	panel.offset_left = -310
	panel.offset_right = 310
	popup.title_label.add_theme_font_size_override("font_size", 30)
	popup.message_label.add_theme_font_size_override("font_size", 24)
	for button: Button in [popup.confirm_btn, popup.cancel_btn]:
		button.add_theme_font_size_override("font_size", 24)
		button.custom_minimum_size = Vector2(220, 64)
	# Let multiline previews determine height while keeping the confirmation centered.
	await get_tree().process_frame
	if not is_instance_valid(popup):
		return
	var content: VBoxContainer = popup.get_node("Panel/VBox")
	var height: float = maxf(320, content.get_combined_minimum_size().y + 32)
	panel.offset_top = -height / 2
	panel.offset_bottom = height / 2

func _send(action: String, body: Dictionary) -> void:
	if _pending or CloudService.golden_finger_busy:
		return
	_pending = true
	_refresh_info()
	CloudService.submit_golden_finger(action, body)

func _retry() -> void:
	var request: Dictionary = CloudService.golden_finger_retry.duplicate(true)
	if not request.is_empty():
		_send(str(request.get("action", "")), request.get("body", {}))

func _on_confirmed(_data: Dictionary) -> void:
	_pending = false
	message_label.text = "操作成功，状态已同步。"
	EventBus.show_toast.emit("法宝操作成功")
	_load()

func _on_failed(reason: String) -> void:
	_pending = false
	_loading = false
	_previewing = false
	preview_button.disabled = false
	_clear_preview()
	var reasons: Dictionary = {"artifact_locked": "境界尚未达到解锁条件", "no_uses": "今日次数不足，可消耗灵石加次", "daily_limit": "今日购买次数已达上限", "insufficient_stones": "灵石不足", "invalid_materials": "所选材料不可用，请刷新后重选", "invalid_target": "目标物品尚未解锁或超出境界", "insufficient_value": "投入材料价值不足", "same_level_other_item": "请选择同级且不同于投料的已解锁物品", "requires_lower_level": "需要一件低于产出等级的材料", "rewind_unavailable": "没有可回溯操作，可能已超时或发生后续变化", "state_conflict": "状态或报价已变化，请刷新后重新预览", "offline": "当前未连接服务器", "not_waiting": "目标当前没有可加速的等待", "already_ready": "目标已完成等待", "same_item": "请选不同的目标物品"}
	message_label.text = str(reasons.get(reason, "请求未完成，请重试或刷新状态"))
	if reason == "insufficient_stones":
		EventBus.show_toast.emit(message_label.text)
	_refresh_info()
	info_label.text += "\n" + message_label.text
	if reason == "state_conflict":
		_load()

func _tick() -> void:
	if _pending or _loading:
		return
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000)
	if not CloudService.golden_finger_state.is_empty() and now_ms >= int(CloudService.golden_finger_state.get("next_reset_at", now_ms + 1)):
		_load()
	if artifact_id == "sand" and mode.selected == 1 and not preview.is_empty():
		if now_ms >= int(preview.get("expires_at", 0)):
			_clear_preview()
			message_label.text = "回溯机会已过期。"

func _close() -> void:
	if not _pending:
		UIManager.hide_popup(self)
