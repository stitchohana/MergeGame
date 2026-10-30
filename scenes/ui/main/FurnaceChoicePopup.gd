extends "res://scenes/ui/main/GoldenFingerPopup.gd"

var input_uid: int = 0
var selected_target: int = 0
var candidate_buttons: Dictionary = {}
var _input_label: Label

func _build() -> void:
	super._build()
	panel_container.anchor_bottom = 0.88
	enter_button.hide()
	use_area.show()
	mode.hide()
	target.hide()
	preview_button.hide()
	_input_label = _label("正在读取投入物品…", 24)
	use_area.add_child(_input_label)
	use_area.move_child(_input_label, 0)
	use_button.text = "确定转化 · 消耗 1 次"
	close_button.text = "取消"
	message_label.text = "请选择一种同级物品。"

func _populate_choices() -> void:
	_clear_preview()
	selected_target = 0
	candidate_buttons.clear()
	for child: Node in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	var source: Dictionary = {}
	for entry: Dictionary in server_grid:
		if int(entry.get("uid", 0)) == input_uid:
			source = entry
	var source_id: int = int(source.get("id", 0))
	var definition_data: Dictionary = ConfigDatabase.get_item_data(source_id)
	var allowed: bool = materials.any(func(item: Dictionary) -> bool: return int(item.get("id", 0)) == source_id)
	if not allowed or source.is_empty() or bool(source.get("immovable", false)) or source.has("craft") or source.has("storage") or source.has("charges") or source.has("atk_base"):
		_input_label.text = "该物品不能投入万象炉"
		message_label.text = "请取消并拖入一件已解锁的普通材料。"
		return
	_input_label.text = "投入：%s ×1 · %d 级\n请选择同级物品，一件换一件。" % [str(definition_data.get("name", "")), int(definition_data.get("level", 0))]
	var cards := GridContainer.new()
	cards.columns = 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	choices.add_child(cards)
	for item: Dictionary in materials:
		var id: int = int(item.get("id", 0))
		if id == source_id or int(item.get("level", 0)) != int(definition_data.get("level", 0)):
			continue
		var card: Button = _button("", _select_target.bind(id), cards)
		card.custom_minimum_size = Vector2(190, 145)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggle_mode = true
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(76, 76)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = load(str(ConfigDatabase.get_item_data(id).get("icon", ""))) as Texture2D
		content.add_child(icon)
		var label: Label = _label(str(item.get("name", "")) + "\n%d 级" % int(item.get("level", 0)), 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		card.add_child(content)
		candidate_buttons[id] = card
	message_label.text = "请选择一种同级物品。" if not candidate_buttons.is_empty() else "暂无其他同级已解锁物品，请取消后解锁更多生产来源。"

func _select_target(id: int) -> void:
	if _pending or _previewing or _loading:
		return
	selected_target = id
	for candidate: int in candidate_buttons:
		(candidate_buttons[candidate] as Button).set_pressed_no_signal(candidate == id)
	_request_preview()

func _selection() -> Dictionary:
	return {"artifact": "furnace", "uids": [input_uid], "target_id": selected_target}

func _on_preview(data: Dictionary) -> void:
	if not _previewing:
		return
	super._on_preview(data)
	message_label.text = "转化为：%s ×1\n确定后消耗 1 次，物品飞入棋盘。" % str(data.get("output_name", ""))

func _confirm_use() -> void:
	if use_button.disabled or preview.is_empty():
		return
	var body: Dictionary = _body()
	body["quote"] = preview.get("quote", {})
	_send("use", body)

func _refresh_info() -> void:
	super._refresh_info()
	enter_button.hide()
	use_button.text = "确定转化 · 消耗 1 次"
	for card: Button in candidate_buttons.values():
		card.disabled = _pending or _previewing or _loading

func _on_confirmed(data: Dictionary) -> void:
	if str(data.get("artifact", "")) != "furnace":
		return
	if str(data.get("action", "")) == "use":
		_pending = false
		_close()
	else:
		super._on_confirmed(data)
