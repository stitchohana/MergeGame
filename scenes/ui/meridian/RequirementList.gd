class_name RequirementList extends Control

signal complete_clicked(index: int)

var _entry_scene: PackedScene = preload("res://scenes/ui/meridian/RequirementEntry.tscn")

@onready var scroll: ScrollContainer = $Panel/ScrollContainer
@onready var container: HBoxContainer = $Panel/ScrollContainer/HBoxContainer

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
