class_name RecipeSourcePopup extends BasePopup

const ITEM_WIDGET_SCENE := preload("res://scenes/ui/common/ItemWidget.tscn")
const INGREDIENT_SIZE: int = 96

@onready var title_label: Label = $Panel/TitleLabel
@onready var target_item: ItemWidget = $Panel/TargetArea/TargetItem
@onready var target_descript_label: Label = $Panel/TargetArea/TargetDescript
@onready var material_items_row: HBoxContainer = $Panel/SourceContainer/SourceBg/HBoxContainer
@onready var recipe_template: Control = $Panel/SourceContainer/RecipeRegionsTemplate
@onready var product_icon: ItemWidget = $Panel/SourceContainer/RecipeRegionsTemplate/ProductTimerArea/ProductIcon
@onready var craft_time_label: Label = $Panel/SourceContainer/RecipeRegionsTemplate/ProductTimerArea/CraftTime
@onready var close_btn: TextureButton = $Panel/CloseButton


func _ready() -> void:
	close_btn.pressed.connect(_on_close)


func setup_for_item(item_id: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		return
	if title_label:
		title_label.text = String(item_data.get("name", "未知道具"))
	_populate_target(item_data)
	_populate_sources(ConfigDatabase.get_recipes_for_result(item_id), item_data)


func _populate_target(item_data: Dictionary) -> void:
	_configure_item_widget(target_item, item_data, false)
	var description: String = item_data.get("describe", "")
	target_descript_label.text = description if not description.is_empty() else String(item_data.get("name", "未知道具"))


func _populate_sources(recipes: Array, result_data: Dictionary) -> void:
	if recipes.is_empty():
		recipe_template.hide()
		for widget: ItemWidget in _get_material_widgets():
			widget.hide()
		return

	recipe_template.show()
	var recipe: Dictionary = recipes[0] as Dictionary
	var ingredients: Array = recipe.get("ingredients", [])
	var widgets: Array[ItemWidget] = _get_material_widgets()
	while widgets.size() < ingredients.size():
		var widget := _make_item_widget({}, INGREDIENT_SIZE, true)
		widget.name = "IngredientItem%d" % (widgets.size() + 1)
		material_items_row.add_child(widget)
		widgets.append(widget)
	for index: int in range(widgets.size()):
		var widget: ItemWidget = widgets[index]
		if index >= ingredients.size():
			widget.hide()
			continue
		var ingredient_id: int = int(ingredients[index])
		widget.show()
		_configure_item_widget(widget, ConfigDatabase.get_item_data(ingredient_id), true)

	_configure_item_widget(product_icon, result_data, false)
	craft_time_label.text = _format_time(float(recipe.get("craft_time", 0.0)))


func _get_material_widgets() -> Array[ItemWidget]:
	var widgets: Array[ItemWidget] = []
	for child: Node in material_items_row.get_children():
		if child is ItemWidget:
			widgets.append(child as ItemWidget)
	return widgets


func _make_item_widget(item_data: Dictionary, size_px: int, clickable: bool) -> ItemWidget:
	var widget := ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	widget.custom_minimum_size = Vector2(size_px, size_px)
	widget.size = Vector2(size_px, size_px)
	widget.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_configure_item_widget(widget, item_data, clickable)
	return widget


func _configure_item_widget(widget: ItemWidget, item_data: Dictionary, clickable: bool) -> void:
	widget.setup(item_data)
	widget.set_selected(false)

	var padding: int = 7
	for node_name: String in ["SelectIcon", "IconRect"]:
		var texture_rect := widget.get_node_or_null(node_name) as TextureRect
		if texture_rect:
			texture_rect.offset_left = padding
			texture_rect.offset_top = padding
			texture_rect.offset_right = -padding
			texture_rect.offset_bottom = -padding

	var button := widget.get_node_or_null("ClickButton") as Button
	if not button:
		return
	button.flat = true
	if clickable:
		button.tooltip_text = "查看该材料的合成链"
		widget.set_clickable(true)
		if not widget.has_meta("recipe_source_click_connected"):
			widget.pressed.connect(_on_ingredient_pressed.bind(widget))
			widget.set_meta("recipe_source_click_connected", true)
	else:
		widget.set_clickable(false)
		button.focus_mode = Control.FOCUS_NONE


func _on_ingredient_pressed(widget: ItemWidget) -> void:
	_open_craft_path(widget.item_data)


func _open_craft_path(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	var popup := preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(item_data)


func _format_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%d秒" % int(ceil(seconds))
	return "%d分%d秒" % [int(seconds / 60.0), int(seconds) % 60]


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _on_close() -> void:
	UIManager.hide_popup(self)
