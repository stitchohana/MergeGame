class_name BattleScreen extends BaseScreen

@onready var grid_view: GridView = $GridView
@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var leave_btn: Button = $LeaveButton
@onready var map_label: Label = $MapHeader/MapLabel
@onready var char_label: Label = $CharPanel/CharLabel
@onready var qi_label: Label = $CharPanel/QiLabel
@onready var monster_label: Label = $MonsterPanel/MonsterLabel
@onready var pouch_zone: PouchDropZone = $PouchDropZone

var _current_map_id: int = 1
var _current_stage: int = 0
var _char_hp: int = 100
var _char_max_hp: int = 100
var _monsters: Array = []

var _pending_stamina_uid: int = -1
var _pending_attack_uid: int = -1
var _pending_attack_effect_id: int = -1
var _pending_heal_amount: int = 0

func _ready() -> void:
	grid_view.item_clicked.connect(_on_item_clicked)
	grid_view.item_use_requested.connect(_on_item_use_requested)
	if not GridManager.grid_updated.is_connected(GameState.check_game_over):
		GridManager.grid_updated.connect(GameState.check_game_over)
	grid_view.set_pouch_zone(pouch_zone)
	leave_btn.pressed.connect(_on_leave_pressed)
	CloudService.battle_attack_confirmed.connect(_on_battle_attack_confirmed)
	CloudService.battle_attack_rejected.connect(_on_battle_attack_rejected)
	CloudService.stamina_restore_confirmed.connect(_on_stamina_restore_confirmed)
	CloudService.stamina_restore_rejected.connect(_on_stamina_restore_rejected)
	CloudService.battle_heal_confirmed.connect(_on_battle_heal_confirmed)
	CloudService.battle_heal_rejected.connect(_on_battle_heal_rejected)
	CultivationService.qi_changed.connect(_on_qi_changed)

func on_enter() -> void:
	GameState.current_board_type = Constants.BoardType.BATTLE
	_char_hp = 100 + CultivationService.total_exp / 10
	_char_max_hp = _char_hp
	_monsters = _build_monster_list()

	if CloudService.online:
		if CloudService.board_switch_confirmed.is_connected(_on_board_switch_confirmed):
			CloudService.board_switch_confirmed.disconnect(_on_board_switch_confirmed)
		if CloudService.board_switch_rejected.is_connected(_on_board_switch_rejected):
			CloudService.board_switch_rejected.disconnect(_on_board_switch_rejected)
		CloudService.board_switch_confirmed.connect(_on_board_switch_confirmed, CONNECT_ONE_SHOT)
		CloudService.board_switch_rejected.connect(_on_board_switch_rejected, CONNECT_ONE_SHOT)
		CloudService.submit_board_switch("battle", _current_map_id, _current_stage)
	else:
		_init_battle_grid()

	_refresh_char_display()
	_refresh_monster_display()
	_refresh_map_header()

func _on_board_switch_confirmed(result: Dictionary) -> void:
	if result.get("board_type", "") != "battle":
		return
	GameState.version = result.get("new_version", GameState.version)
	_current_map_id = result.get("battle_map_id", _current_map_id)
	_current_stage = result.get("battle_stage", _current_stage)
	_sync_grid_from_result(result)
	var server_monsters: Array = result.get("monsters", [])
	if not server_monsters.is_empty():
		_monsters = server_monsters.duplicate(true)
	GameState.set_phase(GameState.GamePhase.IDLE)
	_refresh_monster_display()
	_refresh_map_header()

func _on_board_switch_rejected(reason: String) -> void:
	print("[BattleScreen] Board switch rejected: ", reason)
	_init_battle_grid()

func _init_battle_grid() -> void:
	GridManager.init_grid(Constants.BoardType.BATTLE)
	GameState.set_phase(GameState.GamePhase.IDLE)

func on_exit() -> void:
	detail_panel.clear()

func _build_monster_list() -> Array:
	var result: Array = []
	var map_data: Dictionary = ConfigDatabase.get_expedition_map(_current_map_id)
	if map_data.is_empty():
		return result
	var stages: Array = map_data.get("stages", [])
	if _current_stage >= stages.size():
		return result
	var stage_data: Dictionary = stages[_current_stage]
	var monster_list: Array = stage_data.get("monsters", [])
	for entry in monster_list:
		var monster_data: Dictionary = ConfigDatabase.get_monster(entry.monster_id)
		if monster_data.is_empty():
			continue
		for i in range(entry.count):
			result.append({
				"monster_id": entry.monster_id,
				"name": monster_data.name,
				"hp": monster_data.hp,
				"max_hp": monster_data.hp,
				"atk": monster_data.atk,
				"accept_effect_ids": monster_data.get("accept_effect_ids", []),
			})
	var boss_data: Variant = stage_data.get("boss")
	if boss_data != null:
		var boss_monster: Dictionary = ConfigDatabase.get_monster(boss_data.monster_id)
		if not boss_monster.is_empty():
			result.append({
				"monster_id": boss_data.monster_id,
				"name": "[Boss]" + boss_monster.name,
				"hp": boss_monster.hp,
				"max_hp": boss_monster.hp,
				"atk": boss_monster.atk,
				"accept_effect_ids": boss_monster.get("accept_effect_ids", []),
			})
	return result


func _on_item_use_requested(item_data: Dictionary, grid_pos: Vector2i) -> void:
	var effect_id: int = int(item_data.get("use_effect_id", 0))
	if effect_id <= 0:
		return
	var effect: Dictionary = ConfigDatabase.get_effect(effect_id)
	if effect.is_empty():
		return
	var effect_type: String = effect.get("type", "")
	var uid: int = item_data.get("_uid", 0)

	match effect_type:
		"damage":
			if CloudService.online:
				_pending_attack_uid = uid
				_pending_attack_effect_id = effect_id
				_play_attack_animation(item_data, grid_pos, effect_id)
		"heal":
			var heal: int = effect.get("amount", 0)
			_char_hp = mini(_char_max_hp, _char_hp + heal)
			if not CloudService.online:
				if uid > 0:
					var pos := GridManager.find_pos_by_uid(uid)
					if pos != Vector2i(-1, -1):
						GridManager.remove_item(pos)
			EventBus.show_toast.emit("恢复了 %d 点生命！" % heal)
		"exp":
			CultivationService.consume_exp_pill(item_data.get("id", 0), uid)
		"stamina":
			_pending_stamina_uid = uid
			CloudService.submit_restore_stamina(item_data.get("id", 0), uid, GameState.version)
		"breakthrough":
			var pill_id: int = item_data.get("id", 0)
			if uid <= 0:
				EventBus.show_toast.emit("物品数据异常，请重新登录")
				return
			CultivationService.try_breakthrough(pill_id, uid)
		_:
			EventBus.show_toast.emit("此物品无法使用")

func _on_qi_changed(current_qi: int, max_qi: int) -> void:
	_qi_label()

func _qi_label() -> void:
	if qi_label:
		qi_label.text = "灵力 %d/%d" % [CultivationService.current_qi, CultivationService.max_qi]

func _on_battle_attack_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	_sync_grid_from_result(result)
	var server_monsters: Array = result.get("monsters", [])
	if not server_monsters.is_empty():
		_monsters = server_monsters.duplicate(true)
	var loot_arr: Array = result.get("loot", [])
	var killed: bool = not loot_arr.is_empty()
	var stage_done: bool = result.get("stage_complete", false)
	if killed or stage_done:
		var timer := Timer.new()
		timer.wait_time = 0.5
		timer.one_shot = true
		timer.timeout.connect(func():
			_refresh_monster_display()
			if killed:
				EventBus.show_toast.emit("击败怪物！掉落物品 x%d" % loot_arr.size())
			if stage_done:
				_current_stage = result.get("battle_stage", _current_stage)
				EventBus.show_toast.emit("关卡通过！进入第 %d 关" % (_current_stage + 1))
				_refresh_map_header()
			timer.queue_free()
		)
		add_child(timer)
		timer.start()
	else:
		_refresh_monster_display()

func _on_battle_attack_rejected(reason: String) -> void:
	EventBus.show_toast.emit("攻击失败：" + reason)

func _sync_grid_from_result(result: Dictionary) -> void:
	var server_grid: Array = result.get("grid", [])
	if server_grid.is_empty():
		return
	grid_view.set_skip_animations(true)
	GridManager.init_grid(Constants.BoardType.BATTLE)
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			if entry.has("uid"): item["_uid"] = entry.uid
			if entry.has("immovable"): item["immovable"] = entry.immovable
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	grid_view.set_skip_animations(false)

func _refresh_char_display() -> void:
	var realm_name: String = CultivationService.get_stage_name()
	var level: int = CultivationService.current_level
	var name_str: String = realm_name + " Lv." + str(level) if realm_name != "" else "修士"
	char_label.text = name_str
	_qi_label()

func _refresh_monster_display() -> void:
	var lines: PackedStringArray = []
	for m in _monsters:
		if m.hp > 0:
			lines.append("%s  HP %d/%d" % [m.name, m.hp, m.max_hp])
		else:
			lines.append("%s  [已击败]" % m.name)
	if lines.is_empty():
		monster_label.text = "无怪物"
	else:
		monster_label.text = "\n".join(lines)

func _refresh_map_header() -> void:
	var map_data: Dictionary = ConfigDatabase.get_expedition_map(_current_map_id)
	if map_data.is_empty():
		map_label.text = "无地图数据"
		return
	var stages: Array = map_data.get("stages", [])
	var stage_name: String = ""
	if _current_stage < stages.size():
		stage_name = stages[_current_stage].get("name", "")
	map_label.text = "%s — 第%d关 %s" % [map_data.get("name", ""), _current_stage + 1, stage_name]

func _on_battle_heal_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	_sync_grid_from_result(result)
	_char_hp = mini(_char_max_hp, _char_hp + _pending_heal_amount)
	_refresh_char_display()
	EventBus.show_toast.emit("恢复了 %d 点生命！" % _pending_heal_amount)
	_pending_heal_amount = 0

func _on_battle_heal_rejected(reason: String) -> void:
	_pending_heal_amount = 0
	EventBus.show_toast.emit("恢复失败：" + reason)

func _on_leave_pressed() -> void:
	var prev: String = GameState.previous_screen_name
	if prev == "":
		prev = "home"
	EventBus.screen_change_requested.emit(prev)

func _on_item_clicked(item_data: Dictionary, grid_pos: Vector2i) -> void:
	detail_panel.show_item(item_data, grid_pos)

func _play_attack_animation(item_data: Dictionary, grid_pos: Vector2i, effect_id: int) -> void:
	var cell_size := Constants.CELL_SIZE
	var from_pos := grid_view.global_position + Vector2(grid_pos.x * cell_size + cell_size * 0.5, grid_pos.y * cell_size + cell_size * 0.5)
	var target_pos := _get_monster_target_pos()

	# Capture pending state immediately and clear globals to prevent race with overlapping attacks
	var captured_uid: int = _pending_attack_uid
	var captured_eid: int = _pending_attack_effect_id
	_pending_attack_uid = -1
	_pending_attack_effect_id = -1

	var proj := ColorRect.new()
	proj.custom_minimum_size = Vector2(16, 16)
	proj.size = Vector2(16, 16)
	proj.pivot_offset = Vector2(8, 8)
	proj.position = from_pos
	var group_id: int = item_data.get("group_id", 0)
	var level: int = item_data.get("level", 0)
	var hue: float = float(level - 1) / 8.0 if group_id != 6 else 0.6
	proj.color = Color.from_hsv(hue, 0.8, 0.9)
	add_child(proj)

	var tween := create_tween()
	tween.tween_property(proj, "position", target_pos, 0.3).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(_play_monster_hit)
	tween.tween_callback(proj.queue_free)
	tween.tween_callback(func():
		if captured_uid > 0:
			var pos := GridManager.find_pos_by_uid(captured_uid)
			if pos != Vector2i(-1, -1):
				GridManager.remove_item(pos)
		CloudService.submit_battle_attack(item_data.get("id", 0), captured_eid, grid_pos.x, grid_pos.y)
	)

func _get_monster_target_pos() -> Vector2:
	if $MonsterPanel:
		var rect := $MonsterPanel as Control
		return rect.global_position + rect.size * 0.5
	return grid_view.global_position + Vector2(400, 100)

func _play_monster_hit() -> void:
	var panel := $MonsterPanel
	if not panel:
		return
	var flash := panel.get_node_or_null("HitFlash") as ColorRect
	if not flash:
		flash = ColorRect.new()
		flash.name = "HitFlash"
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.anchors_preset = Control.PRESET_FULL_RECT
		flash.anchor_right = 1.0
		flash.anchor_bottom = 1.0
		flash.color = Color(1, 0.3, 0.3, 0)
		panel.add_child(flash)

	var tween := create_tween()
	tween.tween_property(flash, "color", Color(1, 0.3, 0.3, 0.5), 0.1)
	tween.tween_property(flash, "color", Color(1, 0.3, 0.3, 0.0), 0.3)

func _on_stamina_restore_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	var stam: int = result.get("stamina", 0)
	if stam > 0:
		GameState.stamina = stam
		GameState.stamina_changed.emit(GameState.stamina, GameState.max_stamina)
	if _pending_stamina_uid > 0:
		var pos := GridManager.find_pos_by_uid(_pending_stamina_uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)
		_pending_stamina_uid = -1

func _on_stamina_restore_rejected(reason: String) -> void:
	EventBus.show_toast.emit("回复体力失败：" + reason)
	_pending_stamina_uid = -1
