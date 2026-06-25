class_name RequirementList extends Control

signal complete_clicked(index: int)

var _entry_scene: PackedScene = preload("res://scenes/ui/RequirementEntry.tscn")

@onready var title_label: Label = $Panel/TitleLabel
@onready var scroll: ScrollContainer = $Panel/ScrollContainer
@onready var container: HBoxContainer = $Panel/ScrollContainer/HBoxContainer

func set_title(text: String) -> void:
	title_label.text = text

func set_requirements(reqs: Array) -> void:
	# Remove old children immediately so new entries get correct indices
	while container.get_child_count() > 0:
		var child := container.get_child(0)
		container.remove_child(child)
		child.queue_free()

	for i in range(reqs.size()):
		var req: Dictionary = reqs[i]
		var entry: RequirementEntry = _entry_scene.instantiate()
		container.add_child(entry)
		entry.setup(req.get("items", []), i, req.get("completed", false))
		var idx := i
		entry.complete_pressed.connect(_emit_complete.bind(idx))

func set_entry_available(index: int, available: bool) -> void:
	if index < 0 or index >= container.get_child_count():
		return
	var entry := container.get_child(index) as RequirementEntry
	if entry and is_instance_valid(entry):
		entry.set_available(available)

func _emit_complete(idx: int) -> void:
	complete_clicked.emit(idx)

func remove_entry(index: int) -> void:
	if index < 0 or index >= container.get_child_count():
		return
	var entry := container.get_child(index)
	if entry and is_instance_valid(entry):
		container.remove_child(entry)
		entry.queue_free()
