class_name CultivationPanel extends BaseHUD

signal cultivation_clicked()

@onready var realm_label: Label = $RealmLabel
@onready var exp_bar: ProgressBar = $ExpBar
@onready var exp_label: Label = $ExpLabel
@onready var qi_label: Label = $QiLabel
@onready var buff_label: Label = $BuffLabel
@onready var click_area: Control = $ClickArea

func _ready() -> void:
	click_area.gui_input.connect(_on_click_area_input)
	CultivationService.exp_changed.connect(_on_exp_changed)
	CultivationService.realm_changed.connect(_on_realm_changed)
	CultivationService.qi_changed.connect(_on_qi_changed)
	CultivationService.buff_changed.connect(_on_buff_changed)
	CultivationService.breakthrough_pill_needed.connect(_on_breakthrough_pill_needed)
	_refresh()

func _on_click_area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			cultivation_clicked.emit()

func _on_exp_changed(current_exp: int, exp_to_next: int) -> void:
	if exp_to_next > 0:
		exp_bar.value = (float(current_exp) / float(exp_to_next)) * 100.0
		exp_label.text = "%d/%d" % [current_exp, exp_to_next]
	else:
		exp_bar.value = 0.0
		exp_label.text = "%d" % [current_exp]

func _on_realm_changed(realm_id: int, realm_name: String, level: int) -> void:
	var max_lv: int = CultivationService.get_max_level_for_realm(realm_id)
	if max_lv <= 1:
		realm_label.text = realm_name
	else:
		var level_name: String = CultivationService.get_realm_level_name(level)
		realm_label.text = "%s %s层" % [realm_name, level_name]

func _on_qi_changed(current_qi: int, max_qi: int) -> void:
	qi_label.text = "灵力 %d/%d" % [current_qi, max_qi]

func _on_buff_changed(buffs: Array) -> void:
	if buffs.is_empty():
		buff_label.hide()
	else:
		var names: PackedStringArray = []
		for b in buffs:
			names.append("%s x%.1f %ds" % [b.name, b.multiplier, b.remaining])
		buff_label.text = "加成: %s" % ", ".join(names)
		buff_label.show()

func _on_breakthrough_pill_needed(pill_id: int) -> void:
	var pill_data := ConfigDatabase.get_item_data(pill_id)
	if pill_data.is_empty():
		return
	exp_label.text = "需要突破丹: %s" % pill_data.get("name", str(pill_id))
	exp_bar.value = 100.0

func _refresh() -> void:
	_on_realm_changed(CultivationService.current_realm_id, CultivationService.get_realm_name(), CultivationService.current_level)
	_on_exp_changed(CultivationService.current_exp, CultivationService.get_exp_to_next_level())
	_on_qi_changed(CultivationService.current_qi, CultivationService.max_qi)
