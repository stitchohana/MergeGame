class_name RecipeSourcePopup extends BasePopup

const ITEM_WIDGET_SCENE := preload("res://scenes/ui/common/ItemWidget.tscn")
const ITEM_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/recipe/recipe_item_button.png")

@onready var title_label: Label = $Panel/Margin/VBox/Header/TitleLabel
@onready var target_item_host: HBoxContainer = $Panel/Margin/VBox/TargetPanel/TargetMargin/TargetRow/TargetItemHost
@onready var target_name_label: Label = $Panel/Margin/VBox/TargetPanel/TargetMargin/TargetRow/TargetCopy/TargetName
@onready var target_desc_label: Label = $Panel/Margin/VBox/TargetPanel/TargetMargin/TargetRow/TargetCopy/TargetDescription
@onready var source_container: VBoxContainer = $Panel/Margin/VBox/ScrollContainer/SourceContainer
@onready var empty_label: Label = $Panel/Margin/VBox/EmptyLabel
@onready var close_btn: Button = $Panel/Margin/VBox/Header/CloseButton


func _ready() -> void:
	close_btn.pressed.connect(_on_close)


func setup_for_item(item_id: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		return
	title_label.text = "来源配方"
	_populate_target(item_data)
	_populate_sources(ConfigDatabase.get_recipes_for_result(item_id), item_data)


func _populate_target(item_data: Dictionary) -> void:
	_clear_children(target_item_host)
	target_item_host.add_child(_make_item_widget(item_data, 78, false))
	target_name_label.text = item_data.get("name", "未知道具")
	var description: String = item_data.get("describe", "")
	target_desc_label.text = description if not description.is_empty() else "订单所需道具，查看下方制作来源"


func _populate_sources(recipes: Array, result_data: Dictionary) -> void:
	_clear_children(source_container)
	empty_label.visible = recipes.is_empty()
	for recipe_value in recipes:
		var recipe: Dictionary = recipe_value
		source_container.add_child(_build_source_card(recipe, result_data))


func _build_source_card(recipe: Dictionary, result_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 174)
	panel.add_theme_stylebox_override("panel", _make_source_card_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_child(_make_label(recipe.get("name", "未知配方"), 17, Color(0.25, 0.15, 0.11, 1)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var craft_time: float = float(recipe.get("craft_time", 0.0))
	header.add_child(_make_label("耗时 %s" % _format_time(craft_time), 13, Color(0.34, 0.3, 0.42, 1)))
	content.add_child(header)

	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 7)
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	var ingredients: Array = recipe.get("ingredients", [])
	for index in range(ingredients.size()):
		var ingredient_id: int = int(ingredients[index])
		var ingredient_data: Dictionary = ConfigDatabase.get_item_data(ingredient_id)
		flow.add_child(_make_item_widget(ingredient_data, 58, true))
		if index < ingredients.size() - 1:
			flow.add_child(_make_label("+", 19, Color(0.54, 0.22, 0.16, 1)))
	flow.add_child(_make_label("→", 23, Color(0.18, 0.27, 0.4, 1)))
	flow.add_child(_make_item_widget(result_data, 58, false))
	content.add_child(flow)

	var table_row := HBoxContainer.new()
	table_row.add_theme_constant_override("separation", 8)
	table_row.add_child(_make_label("可用制作台", 13, Color(0.39, 0.25, 0.18, 1)))
	var table: Dictionary = _find_highest_board_table(int(recipe.get("id", 0)))
	if table.is_empty():
		table_row.add_child(_make_label("棋盘上暂无支持该配方的制作台", 13, Color(0.68, 0.24, 0.18, 1)))
	else:
		table_row.add_child(_make_item_widget(table, 42, false))
		var table_name: String = "%s  Lv.%d" % [table.get("name", "制作台"), int(table.get("level", 0))]
		table_row.add_child(_make_label(table_name, 14, Color(0.22, 0.28, 0.4, 1)))
	content.add_child(table_row)

	return panel


func _find_highest_board_table(recipe_id: int) -> Dictionary:
	var best: Dictionary = {}
	for entry: Dictionary in GridManager.get_all_items():
		var board_item: Dictionary = entry.get("data", {})
		if int(board_item.get("type", 0)) != Constants.ItemType.CRAFTING:
			continue
		var config: Dictionary = ConfigDatabase.get_item_data(int(board_item.get("id", 0)))
		var recipe_ids: Array = config.get("recipes", [])
		if not recipe_ids.has(recipe_id):
			continue
		if best.is_empty() or int(config.get("level", 0)) > int(best.get("level", 0)):
			best = config
	return best


func _make_item_widget(item_data: Dictionary, size_px: int, clickable: bool) -> ItemWidget:
	var widget := ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	widget.custom_minimum_size = Vector2(size_px, size_px)
	widget.size = Vector2(size_px, size_px)
	widget.setup(item_data)

	var padding: int = 5
	for node_name: String in ["IconBg", "SelectIcon", "IconRect"]:
		var texture_rect := widget.get_node_or_null(node_name) as TextureRect
		if texture_rect:
			texture_rect.offset_left = padding
			texture_rect.offset_top = padding
			texture_rect.offset_right = -padding
			texture_rect.offset_bottom = -padding

	var button := widget.get_node_or_null("ClickButton") as Button
	button.flat = false
	button.add_theme_stylebox_override("normal", _make_item_button_style(Color.WHITE))
	button.add_theme_stylebox_override("hover", _make_item_button_style(Color(1, 0.95, 0.82, 1)))
	button.add_theme_stylebox_override("pressed", _make_item_button_style(Color(0.82, 0.8, 0.74, 1)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if clickable:
		button.tooltip_text = "查看该材料的合成链"
		widget.set_clickable(true)
		widget.pressed.connect(_open_craft_path.bind(item_data))
	else:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
	return widget


func _make_item_button_style(modulate_color: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ITEM_BUTTON_TEXTURE
	style.texture_margin_left = 22.0
	style.texture_margin_top = 22.0
	style.texture_margin_right = 22.0
	style.texture_margin_bottom = 22.0
	style.modulate_color = modulate_color
	return style


func _make_source_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.93, 0.84, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.29, 0.33, 0.45, 0.78)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_right = 9
	style.corner_radius_bottom_left = 9
	return style


func _open_craft_path(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	var popup := preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(item_data)


func _make_label(label_text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _format_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%d秒" % int(ceil(seconds))
	return "%d分%d秒" % [int(seconds / 60.0), int(seconds) % 60]


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _on_close() -> void:
	UIManager.hide_popup(self)
