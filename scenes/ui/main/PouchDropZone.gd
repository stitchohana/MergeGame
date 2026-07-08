class_name PouchDropZone extends Control

# PouchDropZone: Visual drop target for depositing items into the storage pouch.

signal item_deposited(item_data: Dictionary, from_pos: Vector2i)

@onready var icon_rect: TextureRect = $IconRect
@onready var count_label: Label = $CountLabel

func _ready() -> void:
	StoragePouch.pouch_updated.connect(_on_pouch_updated)
	_update_count()
	gui_input.connect(_on_gui_input)

func get_drop_rect() -> Rect2:
	return Rect2(global_position, size)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_pouch()

func _open_pouch() -> void:
	var popup := preload("res://scenes/ui/main/PouchPopup.tscn").instantiate()
	UIManager.show_popup(popup)

func _on_pouch_updated(_items: Array) -> void:
	_update_count()

func _update_count() -> void:
	if count_label:
		count_label.text = "%d" % StoragePouch.items.size()
