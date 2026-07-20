class_name RequirementList extends Control

signal complete_clicked(index: int)

var _entry_scene: PackedScene = preload("res://scenes/ui/meridian/RequirementEntry.tscn")
var _dragging: bool = false
var _drag_start_x: float = 0.0
var _drag_start_scroll: int = 0

@onready var scroll: ScrollContainer = $Panel/ScrollContainer
@onready var container: HBoxContainer = $Panel/ScrollContainer/HBoxContainer

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	if not is_inside_tree() or not scroll.get_global_rect().has_point(event.position):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start_x = event.position.x
				_drag_start_scroll = scroll.scroll_horizontal
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			scroll.scroll_horizontal = maxi(scroll.scroll_horizontal - 80, 0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			scroll.scroll_horizontal = mini(scroll.scroll_horizontal + 80, scroll.get_h_scroll_bar().max_value)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _dragging:
		var delta_x: float = _drag_start_x - event.position.x
		var target_scroll: int = int(_drag_start_scroll + delta_x)
		var max_scroll: int = int(scroll.get_h_scroll_bar().max_value)
		scroll.scroll_horizontal = clampi(target_scroll, 0, max_scroll)
		get_viewport().set_input_as_handled()

func set_title(_text: String) -> void:
	pass

func set_requirements(reqs: Array) -> void:
	for child in container.get_children():
		if child is RequirementEntry:
			container.remove_child(child)
			child.queue_free()

	for i in range(reqs.size()):
		var req: Dictionary = reqs[i]
		var entry: RequirementEntry = _entry_scene.instantiate()
		container.add_child(entry)
		entry.setup(req.get("items", []), i, req.get("completed", false), req.get("rewards", {}))
		var idx := i
		entry.complete_pressed.connect(_emit_complete.bind(idx))
		entry.item_pressed.connect(_show_item_source)

func _get_entries() -> Array[RequirementEntry]:
	var entries: Array[RequirementEntry] = []
	for child in container.get_children():
		if child is RequirementEntry and is_instance_valid(child):
			entries.append(child as RequirementEntry)
	return entries

func set_entry_available(index: int, available: bool) -> void:
	var entries := _get_entries()
	if index < 0 or index >= entries.size():
		return
	entries[index].set_available(available)

func _emit_complete(idx: int) -> void:
	complete_clicked.emit(idx)

func _show_item_source(item_id: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		return
	if int(item_data.get("type", Constants.ItemType.REGULAR)) == Constants.ItemType.RECIPE_PRODUCT:
		var recipe_popup := preload("res://scenes/ui/main/RecipePopup.tscn").instantiate() as RecipePopup
		UIManager.show_popup(recipe_popup)
		recipe_popup.setup_for_item(item_id)
		return
	var popup := preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(item_data)

func remove_entry(index: int) -> void:
	var entries := _get_entries()
	if index < 0 or index >= entries.size():
		return
	var entry := entries[index]
	container.remove_child(entry)
	entry.queue_free()
