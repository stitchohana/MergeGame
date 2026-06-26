class_name BattleScreen extends BaseScreen

@onready var grid_view: GridView = $GridView
@onready var detail_panel: ItemDetailPanel = $ItemDetailPanel
@onready var leave_btn: Button = $LeaveButton
@onready var map_label: Label = $MapHeader/MapLabel
@onready var char_label: Label = $CharPanel/CharLabel
@onready var char_hp_label: Label = $CharPanel/CharHpLabel
@onready var monster_label: Label = $MonsterPanel/MonsterLabel
@onready var pouch_zone: PouchDropZone = $PouchDropZone

var _current_map_id: int = 1
var _current_stage: int = 0
var _char_hp: int = 100
var _char_max_hp: int = 100
var _monsters: Array = []

func _ready() -> void:
	grid_view.item_clicked.connect(_on_item_clicked)
	grid_view.item_use_requested.connect(_on_item_use_requested)
	if not GridManager.grid_updated.is_connected(GameState.check_game_over):
		GridManager.grid_updated.connect(GameState.check_game_over)
	grid_view.set_pouch_zone(pouch_zone)
	leave_btn.pressed.connect(_on_leave_pressed)

func on_enter() -> void:
	GameState.current_board_type = Constants.BoardType.BATTLE
	_current_map_id = 1
	_current_stage = 0
	_char_hp = 100 + CultivationService.total_exp / 10
	_char_max_hp = _char_hp
	_monsters = _build_monster_list()

	if CloudService.online:
		CloudService.board_switch_confirmed.connect(_on_board_switch_confirmed, CONNECT_ONE_SHOT)
		CloudService.board_switch_rejected.connect(_on_board_switch_rejected, CONNECT_ONE_SHOT)
		CloudService.submit_board_switch("battle")
	else:
		_init_battle_grid()

	_refresh_char_display()
	_refresh_monster_display()
	_refresh_map_header()

func _on_board_switch_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	GridManager.init_grid(Constants.BoardType.BATTLE)
	var server_grid: Array = result.get("grid", [])
	for entry in server_grid:
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			var item := item_data.duplicate(true)
			if entry.has("charges"): item["charges"] = entry.charges
			GridManager.add_item(item, Vector2i(entry.col, entry.row))
	GameState.set_phase(GameState.GamePhase.IDLE)

func _on_board_switch_rejected(reason: String) -> void:
	print("[BattleScreen] Board switch rejected: ", reason)
	_init_battle_grid()

func _init_battle_grid() -> void:
	GridManager.init_grid(Constants.BoardType.BATTLE)
	_load_battle_setup()
	GameState.set_phase(GameState.GamePhase.IDLE)

func on_exit() -> void:
	detail_panel.clear()

func _load_battle_setup() -> void:
	var setup: Array = ConfigDatabase.get_initial_setup(Constants.BoardType.BATTLE)
	for entry in setup:
		if not entry.has("id") or not entry.has("col") or not entry.has("row"):
			continue
		var item_data: Dictionary = ConfigDatabase.get_item_data(entry.id)
		if not item_data.is_empty():
			GridManager.add_item(item_data.duplicate(true), Vector2i(entry.col, entry.row))

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
	var boss_data = stage_data.get("boss")
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

func _get_first_alive_monster() -> Dictionary:
	for m in _monsters:
		if m.hp > 0:
			return m
	return {}

func _on_item_use_requested(item_data: Dictionary, grid_pos: Vector2i) -> void:
	var effect_id: int = int(item_data.get("use_effect_id", 0))
	if effect_id <= 0:
		return
	var effect: Dictionary = ConfigDatabase.get_effect(effect_id)
	if effect.is_empty():
		return
	var effect_type: String = effect.get("type", "")

	match effect_type:
		"damage":
			var target: Dictionary = _get_first_alive_monster()
			if target.is_empty():
				EventBus.show_toast.emit("没有可攻击的目标")
				return
			if not _array_has_int(target.accept_effect_ids, effect_id):
				EventBus.show_toast.emit("无法对此目标使用")
				return
			var dmg: int = effect.get("amount", 0)
			target["hp"] = maxi(0, target.hp - dmg)
			GridManager.remove_item(grid_pos)
			EventBus.show_toast.emit("%s 受到 %d 点伤害！" % [target.name, dmg])
			if target.hp <= 0:
				EventBus.show_toast.emit("%s 被击败！" % target.name)
			_refresh_monster_display()
		"heal":
			var heal: int = effect.get("amount", 0)
			_char_hp = mini(_char_max_hp, _char_hp + heal)
			GridManager.remove_item(grid_pos)
			EventBus.show_toast.emit("恢复了 %d 点生命！" % heal)
			_refresh_char_display()
		"exp":
			CultivationService.consume_exp_pill(item_data.get("id", 0), grid_pos)
		"breakthrough":
			var pill_id: int = item_data.get("id", 0)
			CultivationService.try_breakthrough(pill_id)
		_:
			EventBus.show_toast.emit("此物品无法使用")

func _refresh_char_display() -> void:
	var realm_name: String = CultivationService.get_realm_name()
	var level: int = CultivationService.current_level
	var name_str: String = realm_name + " Lv." + str(level) if realm_name != "" else "修士"
	char_label.text = name_str
	char_hp_label.text = "HP %d/%d" % [_char_hp, _char_max_hp]

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

func _on_leave_pressed() -> void:
	EventBus.screen_change_requested.emit("home")

func _on_item_clicked(item_data: Dictionary, grid_pos: Vector2i) -> void:
	detail_panel.show_item(item_data, grid_pos)

func _array_has_int(arr: Array, value: int) -> bool:
	for v in arr:
		if int(v) == value:
			return true
	return false
