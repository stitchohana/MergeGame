class_name CultivationDetail extends BasePopup

@onready var realm_label: Label = $Panel/RealmLabel
@onready var exp_bar: ProgressBar = $Panel/ExpBar
@onready var exp_label: Label = $Panel/ExpLabel
@onready var qi_label: Label = $Panel/QiLabel
@onready var breakthrough_label: Label = $Panel/BreakthroughLabel
@onready var close_btn: Button = $Panel/CloseButton
@onready var figure_rect: ColorRect = $Panel/FigureBg

func _ready() -> void:
	close_btn.pressed.connect(_on_close)
	_refresh()

func _refresh() -> void:
	var name: String = CultivationService.get_realm_name()
	var level: int = CultivationService.current_level
	var max_lv: int = CultivationService.get_max_level_for_realm(CultivationService.current_realm_id)
	var exp: int = CultivationService.current_exp
	var exp_to_next: int = CultivationService.get_exp_to_next_level()
	var qi: int = CultivationService.current_qi
	var max_qi: int = CultivationService.max_qi

	if max_lv <= 1:
		realm_label.text = name
	else:
		var level_name: String = CultivationService.get_realm_level_name(level)
		realm_label.text = "%s %s层" % [name, level_name]

	if exp_to_next > 0:
		exp_bar.value = (float(exp) / float(exp_to_next)) * 100.0
		exp_label.text = "修为: %d/%d" % [exp, exp_to_next]
	else:
		exp_bar.value = 0.0
		exp_label.text = "修为: %d" % [exp]

	qi_label.text = "灵力: %d/%d" % [qi, max_qi]

	if CultivationService.is_breakthrough_ready():
		var pill_id: int = CultivationService.get_required_breakthrough_pill()
		if pill_id > 0:
			var pill_data := ConfigDatabase.get_item_data(pill_id)
			var pill_name: String = pill_data.get("name", "未知丹药")
			breakthrough_label.text = "⚠ 需「%s」突破" % pill_name
			breakthrough_label.show()
		else:
			breakthrough_label.hide()
	else:
		breakthrough_label.hide()

	var buffs: Array = CultivationService.get_active_buffs()
	if buffs.is_empty():
		$Panel/BuffLabel.hide()
	else:
		var lines: PackedStringArray = []
		for b in buffs:
			lines.append("%s x%.1f (%ds)" % [b.name, b.multiplier, b.remaining])
		$Panel/BuffLabel.text = "丹药效果: " + ", ".join(lines)
		$Panel/BuffLabel.show()

func _on_close() -> void:
	UIManager.hide_popup(self)
	queue_free()
