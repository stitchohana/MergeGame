class_name GridCell extends ColorRect

# GridCell: Represents a single cell on the game board.

enum HighlightType { NONE, VALID_DROP, MERGE_TARGET, INVALID }

var grid_position: Vector2i

@onready var highlight_rect: ColorRect = $Highlight

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_highlight(HighlightType.NONE)

func setup(pos: Vector2i, cell_step: int) -> void:
	grid_position = pos
	custom_minimum_size = Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)
	size = Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)
	position = Vector2(pos.x * cell_step, pos.y * cell_step)

func set_highlight(type: HighlightType) -> void:
	if highlight_rect == null:
		return
	match type:
		HighlightType.NONE:  # NONE
			highlight_rect.hide()
		HighlightType.VALID_DROP:  # VALID_DROP
			highlight_rect.color = Color(0, 1, 0, 0.2)
			highlight_rect.show()
		HighlightType.MERGE_TARGET:  # MERGE_TARGET
			highlight_rect.color = Color(1, 1, 0, 0.35)
			highlight_rect.show()
		HighlightType.INVALID:  # INVALID
			highlight_rect.color = Color(1, 0, 0, 0.2)
			highlight_rect.show()
