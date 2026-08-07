class_name RequirementList extends Control

signal complete_clicked(index: int)

const DRAG_THRESHOLD: float = 8.0

var _entry_scene: PackedScene = preload("res://scenes/ui/meridian/RequirementEntry.tscn")
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_start_x: float = 0.0
var _drag_start_scroll: int = 0

@onready var scroll: ScrollContainer = $Panel/ScrollContainer
@onready var container: HBoxContainer = $Panel/ScrollContainer/HBoxContainer
@onready var cultivation_button: TextureButton = $Panel/ScrollContainer/HBoxContainer/CultivationButton
@onready var pending_reward_bar: PendingRewardBar = $Panel/ScrollContainer/HBoxContainer/PendingRewardBar

func _ready() -> void:
	cultivation_button.pressed.connect(_on_cultivation_pressed)
	CultivationService.qi_changed.connect(_on_cultivation_changed)
	CultivationService.stage_changed.connect(_on_cultivation_changed)
	CloudService.state_loaded.connect(func(_state: Dictionary): call_deferred("_refresh_cultivation_button"))
	CloudService.home_meridian_light_confirmed.connect(func(_result: Dictionary): call_deferred("_refresh_cultivation_button"))
	_refresh_cultivation_button()

func setup_pending_reward_bar(grid: Control) -> void:
	if pending_reward_bar:
		pending_reward_bar.setup(grid)

func _input(event: InputEvent) -> void:
	if UIManager.is_input_blocked():
		_dragging = false
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		call_deferred("_reset_drag_gesture")
	if not is_inside_tree() or not scroll.get_global_rect().has_point(event.position):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
				_drag_start_x = event.position.x
				_drag_start_scroll = scroll.scroll_horizontal
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			scroll.scroll_horizontal = maxi(scroll.scroll_horizontal - 80, 0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			scroll.scroll_horizontal = mini(scroll.scroll_horizontal + 80, scroll.get_h_scroll_bar().max_value)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _dragging:
		var delta_x: float = _drag_start_x - event.position.x
		if absf(delta_x) >= DRAG_THRESHOLD:
			_drag_moved = true
		var target_scroll: int = int(_drag_start_scroll + delta_x)
		var max_scroll: int = int(scroll.get_h_scroll_bar().max_value)
		scroll.scroll_horizontal = clampi(target_scroll, 0, max_scroll)
		get_viewport().set_input_as_handled()

func set_title(_text: String) -> void:
	pass

func _on_cultivation_changed(_first: Variant = null, _second: Variant = null) -> void:
	_refresh_cultivation_button()

func _refresh_cultivation_button() -> void:
	if cultivation_button:
		cultivation_button.visible = _can_activate_acupoint()

func _can_activate_acupoint() -> bool:
	var home_defs: Array = GameState.home_meridian_defs
	if home_defs.is_empty():
		return false
	var stage_idx: int = _get_active_stage_index(home_defs, GameState.home_meridian_progress)
	if stage_idx < 0 or stage_idx >= home_defs.size():
		return false
	var def: Dictionary = home_defs[stage_idx]
	var qi_cost: int = int(def.get("qi_cost", 0))
	if qi_cost <= 0 or CultivationService.current_qi < qi_cost:
		return false
	var lit: Array = _get_stage_lit(GameState.home_meridian_progress, stage_idx)
	var total: int = int(def.get("acupoints", 0))
	for index in range(total):
		if index >= lit.size() or not bool(lit[index]):
			return true
	return false

func _get_active_stage_index(home_defs: Array, home_progress: Array) -> int:
	for stage_idx in range(home_defs.size()):
		var has_progress: bool = false
		for progress_variant in home_progress:
			var progress: Dictionary = progress_variant
			if int(progress.get("stage", -1)) != stage_idx:
				continue
			has_progress = true
			if not bool(progress.get("circulation_completed", false)):
				return _clamp_unlocked_stage_index(stage_idx, home_defs.size())
			break
		if not has_progress:
			return _clamp_unlocked_stage_index(stage_idx, home_defs.size())
	return _clamp_unlocked_stage_index(home_defs.size() - 1, home_defs.size())

func _clamp_unlocked_stage_index(stage_idx: int, stage_count: int) -> int:
	if stage_count <= 0:
		return -1
	return clampi(stage_idx, 0, mini(stage_count - 1, _max_unlocked_home_stage_index()))

func _max_unlocked_home_stage_index() -> int:
	var cultivation_level: int = CultivationService.current_level
	if cultivation_level <= 1:
		return 0
	if cultivation_level <= 10:
		return cultivation_level - 1
	return 9 + (cultivation_level - 10) * 10

func _get_stage_lit(home_progress: Array, stage_idx: int) -> Array:
	for progress_variant in home_progress:
		var progress: Dictionary = progress_variant
		if int(progress.get("stage", -1)) == stage_idx:
			return progress.get("lit", [])
	return []

func _on_cultivation_pressed() -> void:
	if not _can_activate_acupoint():
		_refresh_cultivation_button()
		return
	GameState.pending_auto_acupoint = true
	EventBus.screen_change_requested.emit("home")

func set_requirements(reqs: Array, available_indices: Dictionary = {}) -> void:
	for child in container.get_children():
		if child is RequirementEntry:
			container.remove_child(child)
			child.queue_free()

	var ordered_indices: Array[int] = []
	for i in range(reqs.size()):
		if bool(available_indices.get(i, false)):
			ordered_indices.append(i)
	for i in range(reqs.size()):
		if not bool(available_indices.get(i, false)):
			ordered_indices.append(i)

	for i in ordered_indices:
		var req: Dictionary = reqs[i]
		var entry: RequirementEntry = _entry_scene.instantiate()
		container.add_child(entry)
		entry.setup(req.get("items", []), i, req.get("completed", false), req.get("rewards", {}))
		entry.set_available(bool(available_indices.get(i, false)))
		var idx := i
		entry.complete_pressed.connect(_emit_complete.bind(idx))
		entry.item_pressed.connect(_on_entry_item_pressed)

func _on_entry_item_pressed(item_id: int) -> void:
	if _drag_moved:
		return
	_show_item_source(item_id)

func _reset_drag_gesture() -> void:
	_drag_moved = false

func _get_entries() -> Array[RequirementEntry]:
	var entries: Array[RequirementEntry] = []
	for child in container.get_children():
		if child is RequirementEntry and is_instance_valid(child):
			entries.append(child as RequirementEntry)
	return entries

func get_order_entries() -> Array[RequirementEntry]:
	return _get_entries()

func animate_reflow_from(previous_positions: Dictionary, removed_index: int = -1) -> void:
	var pending: Array[Dictionary] = []
	for entry in _get_entries():
		var old_index: int = entry.get_display_index()
		if removed_index >= 0 and old_index >= removed_index:
			old_index += 1
		var old_position_variant: Variant = previous_positions.get(old_index, null)
		if not old_position_variant is Vector2:
			continue
		var old_position: Vector2 = old_position_variant
		var target_modulate: Color = entry.modulate
		var hidden_modulate: Color = target_modulate
		hidden_modulate.a = 0.0
		entry.modulate = hidden_modulate
		entry.position = old_position
		pending.append({"entry": entry, "from": old_position, "modulate": target_modulate})
	await get_tree().process_frame
	for pending_variant in pending:
		var data: Dictionary = pending_variant
		var entry: RequirementEntry = data.get("entry") as RequirementEntry
		if entry == null or not is_instance_valid(entry):
			continue
		var from_position: Vector2 = data.get("from", Vector2.ZERO)
		var to_position: Vector2 = entry.position
		var target_modulate: Color = data.get("modulate", Color.WHITE)
		entry.position = from_position
		var tween: Tween = create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(entry, "position", to_position, 0.28)
		tween.tween_property(entry, "modulate:a", target_modulate.a, 0.18)

func set_entry_available(index: int, available: bool) -> void:
	var entry := _get_entry_by_display_index(index)
	if entry == null:
		return
	var changed: bool = entry.set_available(available)
	if not changed:
		return
	if available:
		_promote_entry(entry)
	else:
		_move_entry_after_available(entry)

func refresh_item_selection(present_item_ids: Dictionary) -> void:
	for entry in _get_entries():
		entry.refresh_item_selection(present_item_ids)


func _get_entry_by_display_index(index: int) -> RequirementEntry:
	for entry in _get_entries():
		if entry.get_display_index() == index:
			return entry
	return null


func _promote_entry(entry: RequirementEntry) -> void:
	var start_position: Vector2 = entry.position
	var target_modulate: Color = entry.modulate
	var hidden_modulate: Color = target_modulate
	hidden_modulate.a = 0.0
	entry.modulate = hidden_modulate
	container.move_child(entry, _get_order_start_index())
	_animate_promoted_entry(entry, start_position, target_modulate)


func _move_entry_after_available(entry: RequirementEntry) -> void:
	var available_count: int = 0
	for child in _get_entries():
		if child != entry and child.is_available():
			available_count += 1
	container.move_child(entry, _get_order_start_index() + available_count)

func _get_order_start_index() -> int:
	var fixed_child_count: int = 0
	for child in container.get_children():
		if not child is RequirementEntry:
			fixed_child_count += 1
	return fixed_child_count


func _animate_promoted_entry(entry: RequirementEntry, start_position: Vector2, target_modulate: Color) -> void:
	await get_tree().process_frame
	if not is_instance_valid(entry):
		return
	var target_position: Vector2 = entry.position
	entry.position = start_position
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(entry, "position", target_position, 0.28)
	tween.tween_property(entry, "modulate:a", target_modulate.a, 0.18)

func _emit_complete(idx: int) -> void:
	complete_clicked.emit(idx)

func _show_item_source(item_id: int) -> void:
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	if item_data.is_empty():
		return
	if int(item_data.get("type", Constants.ItemType.REGULAR)) == Constants.ItemType.RECIPE_PRODUCT:
		var source_popup := preload("res://scenes/ui/main/RecipeSourcePopup.tscn").instantiate() as RecipeSourcePopup
		UIManager.show_popup(source_popup)
		source_popup.setup_for_item(item_id)
		return
	var popup := preload("res://scenes/ui/main/CraftPathView.tscn").instantiate() as CraftPathView
	UIManager.show_popup(popup)
	popup.show_for_item(item_data)

func remove_entry(index: int) -> void:
	var entries := _get_entries()
	if index < 0 or index >= entries.size():
		return
	var entry := entries[index]
	container.remove_child(entry)
	entry.queue_free()
