class_name BottomPanel extends BaseHUD

@onready var item_count_label: Label = $ItemCountLabel

func _ready() -> void:
	GridManager.grid_updated.connect(_on_grid_updated)
	_on_grid_updated()

func _on_grid_updated() -> void:
	var count := GridManager.count_items()
	var total := 63
	if item_count_label:
		item_count_label.text = "物品: %d/%d" % [count, total]
