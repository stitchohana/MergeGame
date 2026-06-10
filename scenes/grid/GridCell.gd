class_name GridCell extends ColorRect

# GridCell: Represents a single cell on the game board.

enum HighlightType { NONE, VALID_DROP, MERGE_TARGET, INVALID }

var grid_position: Vector2i

@onready var highlight_rect: ColorRect = $Highlight

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_highlight(HighlightType.NONE)

func setup(pos: Vector2i, cell_size: int) -> void:
	grid_position = pos
	custom_minimum_size = Vector2(cell_size, cell_size)
	size = Vector2(cell_size, cell_size)
	position = Vector2(pos.x * cell_size, pos.y * cell_size)

func set_highlight(type: int) -> void:
	if highlight_rect == null:
		return
	match type:
		0:  # NONE
			highlight_rect.hide()
		1:  # VALID_DROP
			highlight_rect.color = Color(0, 1, 0, 0.2)
			highlight_rect.show()
		2:  # MERGE_TARGET
			highlight_rect.color = Color(1, 1, 0, 0.35)
			highlight_rect.show()
		3:  # INVALID
			highlight_rect.color = Color(1, 0, 0, 0.2)
			highlight_rect.show()
