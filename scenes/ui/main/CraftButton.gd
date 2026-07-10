class_name CraftButton extends Control

signal craft_pressed()

@onready var recipe_label: Label = $RecipeLabel
@onready var craft_btn: Button = $CraftBtn

func _ready() -> void:
	hide()
	craft_btn.pressed.connect(func(): craft_pressed.emit())

func show_for_recipe(recipe: Dictionary) -> void:
	if recipe_label:
		recipe_label.text = recipe.get("name", "合成")
	show()

func set_table_pos(cell_pos: Vector2i, cell_size: int) -> void:
	# Position above the cell: centered horizontally, above vertically
	var cell_x := cell_pos.x * cell_size
	var cell_y := cell_pos.y * cell_size
	var btn_w := size.x
	var btn_h := size.y
	var gx := cell_x + (cell_size - btn_w) * 0.5
	var gy := cell_y - btn_h - 4
	position = Vector2(gx, gy)
