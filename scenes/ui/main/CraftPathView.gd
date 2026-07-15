class_name CraftPathView extends BasePopup

# CraftPathView: Shows all items in the same group as the selected item,
# plus launchers that can spawn them.

signal item_selected(item_data: Dictionary)

var _items: Array = []
var _item_widgets: Array = []

@onready var name_list: HBoxContainer = $Panel/NameList
@onready var item_grid: GridContainer = $Panel/ItemGrid
@onready var launcher_container: HBoxContainer = $Panel/LauncherSection/LauncherContainer
@onready var launcher_section: Control = $Panel/LauncherSection
@onready var relation_label: Label = $Panel/LauncherSection/Label
@onready var close_btn: Button = $Panel/CloseButton

func _ready() -> void:
	if close_btn:
		close_btn.pressed.connect(_on_close)

func show_for_item(item_data: Dictionary) -> void:
	var group_id: int = item_data.get("group_id", 0)
	_items = ConfigDatabase.get_items_by_group(group_id) if group_id > 0 else [item_data]
	if _items.is_empty():
		return

	# Sort by level then id
	_items.sort_custom(func(a, b): return a.get("level", 0) < b.get("level", 0) if a.get("level", 0) != b.get("level", 0) else a.get("id", 0) < b.get("id", 0))

	_build_name_list(item_data)
	_build_item_grid(item_data)
	_build_launcher_section(item_data)

func _build_name_list(selected: Dictionary) -> void:
	for child in name_list.get_children():
		child.queue_free()

	var lbl := Label.new()
	lbl.text = selected.get("name", "")
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_list.add_child(lbl)

func _build_item_grid(selected: Dictionary) -> void:
	for child in item_grid.get_children():
		child.queue_free()
	_item_widgets.clear()

	for i in range(_items.size()):
		var it: Dictionary = _items[i]
		var widget := preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
		widget.setup(it)
		widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if it.get("id", 0) == selected.get("id", 0):
			widget.set_selected(true)
		var btn := Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(80, 100)
		btn.add_child(widget)
		btn.pressed.connect(_on_item_clicked.bind(i))
		item_grid.add_child(btn)
		_item_widgets.append(widget)

func _build_launcher_section(selected: Dictionary) -> void:
	for child in launcher_container.get_children():
		child.queue_free()

	if int(selected.get("type", 0)) == Constants.ItemType.LAUNCHER:
		_build_spawn_outputs(selected)
		return

	var launchers: Array = ConfigDatabase.get_launchers_for_item(selected.get("id", 0))
	if launchers.is_empty():
		launcher_section.hide()
		return

	launcher_section.show()
	relation_label.text = "来源"
	for l in launchers:
		launcher_container.add_child(_build_relation_item(l, ""))
func _build_spawn_outputs(launcher: Dictionary) -> void:
	var spawns: Array = launcher.get("spawns", [])
	if spawns.is_empty():
		launcher_section.hide()
		return

	var total_weight: int = 0
	for spawn: Dictionary in spawns:
		total_weight += int(spawn.get("weight", 0))

	launcher_section.show()
	relation_label.text = "可产出"
	for spawn: Dictionary in spawns:
		var output_id: int = int(spawn.get("id", 0))
		var output_data: Dictionary = ConfigDatabase.get_item_data(output_id)
		if output_data.is_empty():
			continue
		var weight: int = int(spawn.get("weight", 0))
		var probability_text: String = ""
		if total_weight > 0:
			probability_text = "%.1f%%" % (float(weight) * 100.0 / float(total_weight))
		launcher_container.add_child(_build_relation_item(output_data, probability_text))

func _build_relation_item(item_data: Dictionary, detail_text: String) -> VBoxContainer:
	var widget := preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	widget.setup(item_data)
	widget.custom_minimum_size = Vector2(40, 40)
	widget.size = Vector2(40, 40)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.text = item_data.get("name", "")
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.add_child(widget)
	vbox.add_child(name_label)
	if not detail_text.is_empty():
		var detail_label := Label.new()
		detail_label.text = detail_text
		detail_label.add_theme_font_size_override("font_size", 11)
		detail_label.add_theme_color_override("font_color", Color(0.56, 0.9, 0.72, 1))
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(detail_label)
	return vbox

func _on_item_clicked(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	var item := _items[index] as Dictionary
	item_selected.emit(item)
	_build_name_list(item)
	_build_item_grid(item)
	_build_launcher_section(item)

func _on_close() -> void:
	UIManager.hide_popup(self)
