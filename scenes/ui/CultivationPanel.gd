class_name CultivationPanel extends BaseHUD

signal cultivation_clicked()

@onready var realm_label: Label = $RealmLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var exp_label: Label = $ExpLabel
@onready var qi_label: Label = $QiLabel
func _ready() -> void:
	CultivationService.exp_changed.connect(_on_exp_changed)
	CultivationService.stage_changed.connect(_on_stage_changed)
	CultivationService.qi_changed.connect(_on_qi_changed)
	CultivationService.breakthrough_pill_needed.connect(_on_breakthrough_pill_needed)
	_refresh()

func _on_exp_changed(current_exp: int, exp_to_next: int) -> void:
	if exp_to_next > 0:
		exp_bar.value = (float(current_exp) / float(exp_to_next)) * 100.0
		exp_label.text = "%d/%d" % [current_exp, exp_to_next]
	else:
		exp_bar.value = 0.0
		exp_label.text = "%d" % [current_exp]

func _on_stage_changed(level: int, stage_name: String) -> void:
	realm_label.text = stage_name

func _on_qi_changed(current_qi: int, max_qi: int) -> void:
	qi_label.text = "灵力 %d/%d" % [current_qi, max_qi]

func _on_breakthrough_pill_needed(pill_id: int) -> void:
	var pill_data := ConfigDatabase.get_item_data(pill_id)
	if pill_data.is_empty():
		return
	exp_label.text = "需要突破丹: %s" % pill_data.get("name", str(pill_id))
	exp_bar.value = 100.0

func _refresh() -> void:
	_on_stage_changed(CultivationService.current_level, CultivationService.get_stage_name())
	_on_exp_changed(CultivationService.current_exp, CultivationService.get_exp_to_next_level())
	_on_qi_changed(CultivationService.current_qi, CultivationService.max_qi)
