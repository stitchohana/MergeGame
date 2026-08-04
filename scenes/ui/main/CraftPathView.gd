class_name CraftPathView extends BasePopup

# CraftPathView mirrors the 780x1688 MasterGo layout. Visual surfaces are
# texture-backed so final sliced art can replace the current placeholders
# without changing the scene hierarchy or data logic.

signal item_selected(item_data: Dictionary)

const COLUMNS: int = 4
const MIN_VISIBLE_SLOTS: int = 12
const COMPACT_LAYOUT_ROWS: int = 4
const PATH_WIDTH: float = 655.2
const PATH_HEIGHT: float = 511.68
const ROW_HEIGHT: float = 158.08
const ROW_SEPARATION: float = 19.0
const NODE_SIZE: Vector2 = Vector2(128.96, 141.44)
const ARROW_SIZE: Vector2 = Vector2(27.04, 27.04)
const ITEM_WIDGET_SCENE: PackedScene = preload("res://scenes/ui/common/ItemWidget.tscn")

@export_group("Design Textures")
@export var arrow_texture: Texture2D = preload("res://assets/ui/craft_path_v1_layers/layers/craft_path_arrow.png")

var _items: Array[Dictionary] = []
var _item_controls: Array[ItemWidget] = []

@onready var title_label: Label = get_node_or_null("Panel/HeaderSurface/TitleGroup/TitleLabel") as Label
@onready var descript_label: Label = $Panel/DescriptLabel
@onready var close_button: TextureButton = $Panel/HeaderSurface/CloseButton
@onready var rows_container: VBoxContainer = $Panel/Rows
@onready var relation_label: Label = get_node_or_null("Panel/TitleSurface/RelationLabel") as Label
@onready var source_item: ItemWidget = $Panel/TitleSurface/SourceItem
@onready var source_name_label: Label = get_node_or_null("Panel/SourceCard/SourceNameLabel") as Label


func _ready() -> void:
	close_button.pressed.connect(_on_close)


func show_for_item(item_data: Dictionary) -> void:
	var group_id: int = int(item_data.get("group_id", 0))
	var source_items: Array = ConfigDatabase.get_items_by_group(group_id) if group_id > 0 else [item_data]
	_items.clear()
	for raw_item: Variant in source_items:
		if raw_item is Dictionary:
			_items.append(raw_item as Dictionary)
	if _items.is_empty():
		return

	_items.sort_custom(_sort_items)
	_update_selected_item(item_data)


func _sort_items(left: Dictionary, right: Dictionary) -> bool:
	var left_level: int = int(left.get("level", 0))
	var right_level: int = int(right.get("level", 0))
	if left_level != right_level:
		return left_level < right_level
	return int(left.get("id", 0)) < int(right.get("id", 0))


func _update_selected_item(selected: Dictionary) -> void:
	if title_label:
		title_label.text = String(selected.get("name", ""))
	descript_label.text = String(selected.get("describe", ""))
	_build_path(selected)
	_build_source_section(selected)


func _build_path(selected: Dictionary) -> void:
	for child: Node in rows_container.get_children():
		child.queue_free()
	_item_controls.clear()

	var selected_id: int = int(selected.get("id", 0))
	var slot_count: int = maxi(MIN_VISIBLE_SLOTS, _items.size())
	var row_count: int = ceili(float(slot_count) / float(COLUMNS))
	var layout_row_count: int = maxi(row_count, COMPACT_LAYOUT_ROWS)
	var row_height: float = minf(
		ROW_HEIGHT,
		(PATH_HEIGHT - float(maxi(0, layout_row_count - 1)) * ROW_SEPARATION) / float(layout_row_count)
	)
	var scale_factor: float = row_height / ROW_HEIGHT
	var node_size: Vector2 = NODE_SIZE * scale_factor
	var arrow_size: Vector2 = ARROW_SIZE * scale_factor
	rows_container.custom_minimum_size = Vector2(PATH_WIDTH, PATH_HEIGHT)

	for row_index: int in range(row_count):
		var row := HBoxContainer.new()
		row.name = "PathRow%d" % (row_index + 1)
		row.custom_minimum_size = Vector2(PATH_WIDTH, row_height)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 9)

		for column_index: int in range(COLUMNS):
			var item_index: int = row_index * COLUMNS + column_index
			var item_data: Dictionary = _items[item_index] if item_index < _items.size() else {}
			var is_selected: bool = (
				not item_data.is_empty()
				and int(item_data.get("id", 0)) == selected_id
			)
			var item_control: ItemWidget = _create_path_node(item_data, item_index, is_selected, node_size)
			row.add_child(item_control)
			if not item_data.is_empty():
				_item_controls.append(item_control)
			if column_index < COLUMNS - 1:
				row.add_child(_create_arrow(arrow_size))

		rows_container.add_child(row)

func _create_path_node(item_data: Dictionary, item_index: int, is_selected: bool, node_size: Vector2) -> ItemWidget:
	var widget: ItemWidget = ITEM_WIDGET_SCENE.instantiate() as ItemWidget
	widget.name = "UnknownNode" if item_data.is_empty() else "ItemNode%d" % int(item_data.get("level", item_index + 1))
	widget.custom_minimum_size = node_size
	widget.size = node_size
	widget.setup(item_data)
	widget.set_selected(is_selected)
	widget.set_clickable(not item_data.is_empty())
	var lock_icon: TextureRect = widget.get_node_or_null("IconLock") as TextureRect
	if lock_icon:
		lock_icon.visible = item_data.is_empty()
	if not item_data.is_empty():
		widget.pressed.connect(_on_item_clicked.bind(item_index))
	return widget


func _create_arrow(arrow_size: Vector2) -> Control:
	var holder := Control.new()
	holder.name = "PathArrow"
	holder.custom_minimum_size = arrow_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var texture_rect := TextureRect.new()
	texture_rect.name = "ArrowTexture"
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = arrow_texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.visible = arrow_texture != null
	holder.add_child(texture_rect)

	var fallback := Label.new()
	fallback.name = "ArrowFallback"
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.add_theme_font_size_override("font_size", 28)
	fallback.add_theme_color_override("font_color", Color(0.66, 0.49, 0.24, 1.0))
	fallback.text = "›"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.visible = arrow_texture == null
	holder.add_child(fallback)
	return holder


func _build_source_section(selected: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var selected_type: int = int(selected.get("type", 0))
	if selected_type == Constants.ItemType.LAUNCHER:
		if relation_label:
			relation_label.text = "可产出"
		var spawns: Array = selected.get("spawns", [])
		for spawn: Dictionary in spawns:
			var output_id: int = int(spawn.get("id", 0))
			var output_data: Dictionary = ConfigDatabase.get_item_data(output_id)
			if not output_data.is_empty():
				entries.append(output_data)
	else:
		if relation_label:
			relation_label.text = "来源"
		entries = _get_present_launchers_for_item(int(selected.get("id", 0)))

	_update_source_card(entries)


func _update_source_card(entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		source_item.hide()
		if source_name_label:
			source_name_label.text = "暂无来源"
		return

	var first_entry: Dictionary = entries[0]
	source_item.show()
	source_item.setup(first_entry)
	source_item.set_selected(false)
	source_item.set_clickable(false)
	var lock_icon: TextureRect = source_item.get_node_or_null("IconLock") as TextureRect
	if lock_icon:
		lock_icon.hide()
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		names.append(String(entry.get("name", "")))
	if source_name_label:
		source_name_label.text = "、".join(names)


func _get_present_launchers_for_item(item_id: int) -> Array[Dictionary]:
	var present_launcher_ids: Dictionary = {}
	for entry: Dictionary in GridManager.get_all_items():
		var board_item: Dictionary = entry.get("data", {})
		if int(board_item.get("type", 0)) != Constants.ItemType.LAUNCHER:
			continue
		var launcher_id: int = int(board_item.get("id", 0))
		if launcher_id > 0:
			present_launcher_ids[launcher_id] = true

	var result: Array[Dictionary] = []
	var launchers: Array = ConfigDatabase.get_launchers_for_item(item_id)
	for raw_launcher: Variant in launchers:
		if not raw_launcher is Dictionary:
			continue
		var launcher: Dictionary = raw_launcher as Dictionary
		var launcher_id: int = int(launcher.get("id", 0))
		if present_launcher_ids.has(launcher_id):
			result.append(launcher)
	return result


func _on_item_clicked(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	var item: Dictionary = _items[index]
	item_selected.emit(item)
	_update_selected_item(item)


func _on_close() -> void:
	UIManager.hide_popup(self)
