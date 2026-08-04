class_name RequirementList extends Control

signal complete_clicked(index: int)

const DRAG_THRESHOLD: float = 8.0

var _entry_scene: PackedScene = preload("res://scenes/ui/meridian/RequirementEntry.tscn")
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_start_x: float = 0.0
var _drag_start_scroll: int = 0

@onready var scroll: ScrollContainer = $Panel/ScrollContainer
@onready var container: HBoxContainer = $Panel/ScrollContainer/HBoxContainer

func _input(event: InputEvent) -> void:
	if UIManager.is_input_blocked():
		_dragging = false
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		call_deferred("_reset_drag_gesture")
	if not is_inside_tree() or not scroll.get_global_rect().has_point(event.position):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
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
		if absf(delta_x) >= DRAG_THRESHOLD:
			_drag_moved = true
		var target_scroll: int = int(_drag_start_scroll + delta_x)
		var max_scroll: int = int(scroll.get_h_scroll_bar().max_value)
		scroll.scroll_horizontal = clampi(target_scroll, 0, max_scroll)
		get_viewport().set_input_as_handled()

func set_title(_text: String) -> void:
	pass

func set_requirements(reqs: Array, available_indices: Dictionary = {}) -> void:
	for child in container.get_children():
		if child is RequirementEntry:
			container.remove_child(child)
			child.queue_free()

	var ordered_indices: Array[int] = []
	for i in range(reqs.size()):
		if bool(available_indices.get(i, false)):
			ordered_indices.append(i)
	for i in range(reqs.size()):
		if not bool(available_indices.get(i, false)):
			ordered_indices.append(i)

	for i in ordered_indices:
		var req: Dictionary = reqs[i]
		var entry: RequirementEntry = _entry_scene.instantiate()
		container.add_child(entry)
		entry.setup(req.get("items", []), i, req.get("completed", false), req.get("rewards", {}))
		entry.set_available(bool(available_indices.get(i, false)))
		var idx := i
		entry.complete_pressed.connect(_emit_complete.bind(idx))
		entry.item_pressed.connect(_on_entry_item_pressed)

func _on_entry_item_pressed(item_id: int) -> void:
	if _drag_moved:
		return
	_show_item_source(item_id)

func _reset_drag_gesture() -> void:
	_drag_moved = false

func _get_entries() -> Array[RequirementEntry]:
	var entries: Array[RequirementEntry] = []
	for child in container.get_children():
		if child is RequirementEntry and is_instance_valid(child):
			entries.append(child as RequirementEntry)
	return entries

func set_entry_available(index: int, available: bool) -> void:
	var entry := _get_entry_by_display_index(index)
	if entry == null:
		return
	var changed: bool = entry.set_available(available)
	if not changed:
		return
	if available:
		_promote_entry(entry)
	else:
		_move_entry_after_available(entry)

func refresh_item_selection(present_item_ids: Dictionary) -> void:
	for entry in _get_entries():
		entry.refresh_item_selection(present_item_ids)


func _get_entry_by_display_index(index: int) -> RequirementEntry:
	for entry in _get_entries():
		if entry.get_display_index() == index:
			return entry
	return null


func _promote_entry(entry: RequirementEntry) -> void:
	var start_position: Vector2 = entry.position
	container.move_child(entry, 1)
	_animate_promoted_entry(entry, start_position)


func _move_entry_after_available(entry: RequirementEntry) -> void:
	var available_count: int = 0
	for child in _get_entries():
		if child != entry and child.is_available():
			available_count += 1
	container.move_child(entry, available_count + 1)


func _animate_promoted_entry(entry: RequirementEntry, start_position: Vector2) -> void:
	await get_tree().process_frame
	if not is_instance_valid(entry):
		return
	var target_position: Vector2 = entry.position
	entry.position = start_position
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(entry, "position", target_position, 0.28)

func _emit_complete(idx: int) -> void:
	complete_clicked.emit(idx)

func _show_item_source(item_id: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		return
	if int(item_data.get("type", Constants.ItemType.REGULAR)) == Constants.ItemType.RECIPE_PRODUCT:
		var source_popup := preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
		UIManager.show_popup(source_popup)
		source_popup.setup_for_item(item_id)
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
