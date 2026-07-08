class_name RecipePopup extends BasePopup

@onready var title_label: Label = $Panel/TitleLabel
@onready var recipe_container: VBoxContainer = $Panel/RecipeContainer
@onready var close_btn: Button = $Panel/CloseButton

func _ready() -> void:
	close_btn.pressed.connect(_on_close)

func setup(recipes: Array, table_name: String) -> void:
	title_label.text = table_name + " 配方"
	_populate(recipes)

func _populate(recipes: Array) -> void:
	for child in recipe_container.get_children():
		child.queue_free()

	for recipe in recipes:
		var entry := _build_entry(recipe)
		recipe_container.add_child(entry)

func _build_entry(recipe: Dictionary) -> Control:
	var entry := VBoxContainer.new()

	# Recipe name
	var name_label := Label.new()
	name_label.text = recipe.get("name", "")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	entry.add_child(name_label)

	# Ingredients line
	var ingredients: Array = recipe.get("ingredients", [])
	var result_id: int = recipe.get("result", 0)
	var craft_time: float = recipe.get("craft_time", 0.0)

	var parts: PackedStringArray = []
	for ing_id in ingredients:
		var ing_data := ConfigDatabase.get_item_data(ing_id)
		var ing_name: String = ing_data.get("name", "未知")
		parts.append(ing_name)

	var result_data := ConfigDatabase.get_item_data(result_id)
	var result_name: String = result_data.get("name", "未知")

	var info_label := Label.new()
	info_label.text = "%s → %s   [%.1fs]" % [" + ".join(parts), result_name, craft_time]
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(info_label)

	return entry

func _on_close() -> void:
	UIManager.hide_popup(self)
	queue_free()
