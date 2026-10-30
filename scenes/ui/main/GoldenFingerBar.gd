extends HBoxContainer

signal artifact_pressed(artifact_id: String)
var entries: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	for artifact: Dictionary in ConfigDatabase.golden_finger.get("artifacts", []):
		var id: String = str(artifact.get("id", ""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(116, 110)
		button.flat = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if id == "basin":
			button.tooltip_text = "拖入一件低级材料，飞出同链最高级物品 ×2；棋盘空位不足时暂存"
		elif id == "furnace":
			button.tooltip_text = "拖入一件物品，选择同级已解锁的其他物品，确认后飞回棋盘"
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 0)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(58, 58)
		icon.texture = load("res://assets/ui/artifact_%s.svg" % id) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		var title := Label.new()
		title.text = str(artifact.get("name", "法宝"))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", Color("345c50"))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(title)
		var status := Label.new()
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_font_size_override("font_size", 16)
		status.add_theme_color_override("font_color", Color("715934"))
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(status)
		button.add_child(content)
		button.pressed.connect(func(): artifact_pressed.emit(id))
		add_child(button)
		entries[id] = {"button": button, "status": status, "definition": artifact}
	CloudService.golden_finger_updated.connect(_refresh)
	CultivationService.stage_changed.connect(func(_level: int, _stage: String):
		_refresh({})
		if CloudService.online:
			CloudService.fetch_golden_finger()
	)
	_refresh({})
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(func():
		if CloudService.online and int(Time.get_unix_time_from_system() * 1000) >= int(CloudService.golden_finger_state.get("next_reset_at", 9223372036854775807)):
			CloudService.fetch_golden_finger()
	)
	add_child(timer)
	timer.start()

func _refresh(_data: Dictionary) -> void:
	for id: String in entries:
		var entry: Dictionary = entries[id]
		var definition: Dictionary = entry.definition
		var status: Label = entry.status
		var unlocked: bool = CultivationService.current_level >= int(definition.get("unlock_level", 999))
		status.text = "剩余 —" if unlocked else str(definition.get("unlock_label", "")) + "解锁"
		(entry.button as Button).modulate = Color.WHITE if unlocked else Color(0.75, 0.75, 0.75)
		for offer: Dictionary in CloudService.golden_finger_state.get("artifacts", []):
			if str(offer.get("id", "")) == id and unlocked:
				status.text = "剩余 %d 次" % int(offer.get("remaining", 0))
