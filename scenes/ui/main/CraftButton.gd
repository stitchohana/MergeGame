class_name CraftButton extends Control

signal craft_pressed()

@onready var output_slot: ItemWidget = $OutputSlot
@onready var craft_btn: Button = $CraftBtn

var _output_item_id: int = 0

func _ready() -> void:
	hide()
	craft_btn.pressed.connect(func(): craft_pressed.emit())

func show_for_recipe(recipe: Dictionary) -> void:
	_update_output_slot(recipe)
	show()

func _update_output_slot(recipe: Dictionary) -> void:
	_output_item_id = int(recipe.get("result", 0))
	var result_data: Dictionary = ConfigDatabase.get_item_data(_output_item_id)
	if result_data.is_empty():
		_output_item_id = 0
		output_slot.hide()
		return
	output_slot.setup(result_data)
	output_slot.set_clickable(false)
	output_slot.show()

func get_output_item_id() -> int:
	return _output_item_id

func set_table_pos(cell_pos: Vector2i, cell_size: int) -> void:
	# Position above the cell: centered horizontally, above vertically
	var cell_x := cell_pos.x * cell_size
	var cell_y := cell_pos.y * cell_size
	var btn_w := size.x
	var btn_h := size.y
	var gx := cell_x + (cell_size - btn_w) * 0.5
	var gy := cell_y - btn_h - 4
	position = Vector2(gx, gy)
