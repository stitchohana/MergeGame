class_name RecipePopup extends BasePopup

const ITEM_WIDGET_SCENE := preload("res://scenes/ui/common/ItemWidget.tscn")
const ITEM_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/recipe/recipe_item_button.png")

@onready var title_label: Label = $Panel/Margin/VBox/Header/TitleLabel
@onready var target_container: HBoxContainer = $Panel/Margin/VBox/TargetContainer
@onready var recipe_container: VBoxContainer = $Panel/Margin/VBox/ScrollContainer/RecipeContainer
@onready var empty_label: Label = $Panel/Margin/VBox/EmptyLabel
@onready var close_btn: Button = $Panel/Margin/VBox/Header/CloseButton

func _ready() -> void:
	close_btn.pressed.connect(_on_close)

# Existing crafting-table entry point.
func setup(recipes: Array, table_name: String) -> void:
	title_label.text = table_name + " 配方"
	target_container.hide()
	_populate(recipes, false)

# Requirement-order entry point.
func setup_for_item(item_id: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	var item_name: String = item_data.get("name", "未知道具")
	title_label.text = item_name + " · 制作配方"
	_populate_target(item_data)
	_populate(ConfigDatabase.get_recipes_for_result(item_id), true)

func _populate_target(item_data: Dictionary) -> void:
	_clear_children(target_container)
	target_container.show()
	if item_data.is_empty():
		return
	var widget := _make_item_widget(item_data, 64)
	target_container.add_child(widget)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _make_label(item_data.get("name", "未知道具"), 18, Color(0.28, 0.14, 0.08, 1))
	copy.add_child(name_label)
	var desc_label := _make_label(item_data.get("describe", "订单所需道具"), 13, Color(0.46, 0.31, 0.2, 1))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(desc_label)
	target_container.add_child(copy)

func _populate(recipes: Array, show_board_table: bool) -> void:
	_clear_children(recipe_container)
	empty_label.visible = recipes.is_empty()
	empty_label.text = "该道具暂无制作配方"
	for recipe in recipes:
		recipe_container.add_child(_build_entry(recipe, show_board_table))

func _build_entry(recipe: Dictionary, show_board_table: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 150 if show_board_table else 112)
	panel.add_theme_stylebox_override("panel", _make_recipe_card_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_child(_make_label(recipe.get("name", "未知配方"), 17, Color(0.34, 0.16, 0.08, 1)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var craft_time: float = float(recipe.get("craft_time", 0.0))
	header.add_child(_make_label("制作 %s" % _format_time(craft_time), 13, Color(0.48, 0.32, 0.2, 1)))
	content.add_child(header)

	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 8)
	for ingredient_id_value in recipe.get("ingredients", []):
		var ingredient_id: int = int(ingredient_id_value)
		var ingredient: Dictionary = ConfigDatabase.get_item_data(ingredient_id)
		flow.add_child(_make_item_widget(ingredient, 58))
		flow.add_child(_make_label("+", 20, Color(0.52, 0.31, 0.16, 1)))
	if flow.get_child_count() > 0:
		flow.get_child(flow.get_child_count() - 1).queue_free()
	content.add_child(flow)

	if show_board_table:
		var table: Dictionary = _find_highest_board_table(int(recipe.get("id", 0)))
		var table_row := HBoxContainer.new()
		table_row.add_theme_constant_override("separation", 10)
		table_row.add_child(_make_label("放入制作台", 13, Color(0.48, 0.32, 0.2, 1)))
		if table.is_empty():
			table_row.add_child(_make_label("棋盘上暂无可用制作台", 14, Color(1, 0.48, 0.42, 1)))
		else:
			table_row.add_child(_make_item_widget(table, 52))
			var table_name: String = "%s  Lv.%d" % [table.get("name", "制作台"), int(table.get("level", 0))]
			table_row.add_child(_make_label(table_name, 15, Color(0.58, 0.29, 0.12, 1)))
		content.add_child(table_row)

	return panel

func _find_highest_board_table(recipe_id: int) -> Dictionary:
	var best: Dictionary = {}
	for entry in GridManager.get_all_items():
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

func _make_item_widget(item_data: Dictionary, size_px: int) -> ItemWidget:
	var widget := ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	widget.custom_minimum_size = Vector2(size_px, size_px)
	widget.size = Vector2(size_px, size_px)
	widget.setup(item_data)

	var padding: int = 6
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
	button.add_theme_stylebox_override("hover", _make_item_button_style(Color(1, 0.96, 0.82, 1)))
	button.add_theme_stylebox_override("pressed", _make_item_button_style(Color(0.82, 0.8, 0.74, 1)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.tooltip_text = "查看合成链"
	widget.set_clickable(true)
	widget.pressed.connect(_open_item_source.bind(item_data))
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


func _make_recipe_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.9, 0.78, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.34, 0.16, 0.92)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	return style

func _open_item_source(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	var item_id: int = int(item_data.get("id", 0))
	var recipes: Array = ConfigDatabase.get_recipes_for_result(item_id)
	if not recipes.is_empty():
		var source_popup := preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
		UIManager.show_popup(source_popup)
		source_popup.setup_for_item(item_id)
		return
	var popup := preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(item_data)

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
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
