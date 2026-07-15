class_name CraftingController extends Node

# Handles crafting server communication and pending state.
# GridView handles visuals through signals.

signal item_accepted_for_craft(src_key: String, src_pos: Vector2i)
signal craft_rejected(reason: String)
signal craft_retrieve_ready(result_id: int, result_uid: int, table_pos: Vector2i)
signal table_visual_update(table_item: Dictionary, state: int)
signal craft_start_requested(table_pos: Vector2i)

var _craft_button: Node = null
var _craft_table_pos: Vector2i = Vector2i(-1, -1)
var _craft_table_item: Dictionary = {}
var _cell_size: int = 0

# Pending state for craft_add (deferred until server confirms)
var _pending_src_key: String = ""
var _pending_src_pos: Vector2i = Vector2i(-1, -1)
var _pending_table_item: Dictionary = {}
var _pending_dragged_item: Dictionary = {}
var _pending_table_pos: Vector2i = Vector2i(-1, -1)
var _pending_ingredient_id: int = -1

func setup_signals() -> void:
	CloudService.craft_add_confirmed.connect(_on_craft_add_confirmed)
	CloudService.craft_add_rejected.connect(_on_craft_add_rejected)
	CloudService.craft_start_confirmed.connect(_on_craft_start_confirmed)
	CloudService.craft_start_rejected.connect(_on_craft_start_rejected)
	CloudService.craft_retrieve_confirmed.connect(_on_craft_retrieve_confirmed)
	CloudService.craft_retrieve_rejected.connect(_on_craft_retrieve_rejected)
	CraftingService.table_state_changed.connect(_on_table_state_changed)

func setup_button(parent: Node) -> void:
	_craft_button = preload("res://scenes/ui/main/CraftButton.tscn").instantiate() as CraftButton
	parent.add_child(_craft_button)
	_craft_button.hide()
	_craft_button.craft_pressed.connect(_on_craft_button_pressed)
	_cell_size = Constants.CELL_SIZE

# --- Called by GridView ---

func try_add_ingredient(table_pos: Vector2i, table_item: Dictionary, src_pos: Vector2i, ingredient_id: int, drag_item_data: Dictionary) -> bool:
	var craft_state: int = table_item.get("_craft_state", CraftingService.TableState.IDLE)
	if craft_state == CraftingService.TableState.CRAFTING or craft_state == CraftingService.TableState.READY:
		craft_rejected.emit("snap_back")
		return false

	# Validate ingredient against table's recipes
	var table_id: int = table_item.get("id", 0) as int
	var allowed_recipes: Array = ConfigDatabase.get_recipes_for_item(table_id)
	var valid := false
	for r in allowed_recipes:
		for ing in r.get("ingredients", []):
			if ing == ingredient_id:
				valid = true
				break
		if valid:
			break
	if not valid:
		craft_rejected.emit("此材料无法放入")
		return false

	# Check duplicate
	var stored: Array = CraftingService.get_stored_items(table_item)
	for s in stored:
		if s.get("id", 0) == ingredient_id:
			craft_rejected.emit("该材料已放入")
			return false

	# Check compatibility with existing stored items
	if not stored.is_empty():
		var can_match := false
		for r in allowed_recipes:
			var recipe_ings: Array = r.get("ingredients", [])
			var all_stored_match := true
			for s in stored:
				var sid: int = s.get("id", 0) as int
				var found_s := false
				for ri in recipe_ings:
					if ri == sid:
						found_s = true
						break
				if not found_s:
					all_stored_match = false
					break
			if not all_stored_match:
				continue
			for ri in recipe_ings:
				if ri == ingredient_id:
					can_match = true
					break
			if can_match:
				break
		if not can_match:
			craft_rejected.emit("无法与已有材料形成配方")
			return false

	# Save pending state and submit to server
	_pending_src_key = "%d,%d" % [src_pos.x, src_pos.y]
	_pending_src_pos = src_pos
	_pending_table_item = table_item
	_pending_dragged_item = drag_item_data
	_pending_table_pos = table_pos
	_pending_ingredient_id = ingredient_id

	if CloudService.online:
		CloudService.submit_craft_add(src_pos.x, src_pos.y, table_pos.x, table_pos.y, ingredient_id)

	return true

func try_retrieve(table_item: Dictionary, table_pos: Vector2i) -> void:
	if table_item.is_empty():
		return
	_craft_table_item = table_item
	_craft_table_pos = table_pos
	CloudService.submit_craft_retrieve(table_pos.x, table_pos.y)

func show_button_for_table(recipe: Dictionary, table_pos: Vector2i, cell_size: int) -> void:
	if not _craft_button:
		return
	_craft_button.show_for_recipe(recipe)
	_craft_button.set_table_pos(table_pos, cell_size)

func hide_button() -> void:
	if _craft_button:
		_craft_button.hide()
	_craft_table_pos = Vector2i(-1, -1)
	_craft_table_item = {}

func is_button_visible() -> bool:
	return _craft_button != null and _craft_button.visible

func is_point_over_button(point: Vector2) -> bool:
	if not is_button_visible():
		return false
	var rect := Rect2(_craft_button.position, _craft_button.size)
	return rect.has_point(point)

# --- Server response handlers ---

func _on_craft_add_confirmed(_result: Dictionary) -> void:
	if not _pending_dragged_item.is_empty():
		item_accepted_for_craft.emit(_pending_src_key, _pending_src_pos)
		CraftingService.add_ingredient(_pending_table_item, _pending_dragged_item)
		_clear_pending()

func _on_craft_add_rejected(reason: String) -> void:
	_clear_pending()
	craft_rejected.emit("放入材料失败：" + reason)

func _on_craft_start_confirmed(_result: Dictionary) -> void:
	_craft_start_pending = false
	if not _craft_table_item.is_empty():
		CraftingService.start_craft(_craft_table_item)

func _on_craft_start_rejected(reason: String) -> void:
	_craft_start_pending = false
	craft_rejected.emit("开始制作失败：" + reason)

func _on_craft_retrieve_confirmed(result: Dictionary) -> void:
	var result_id: int = result.get("result_id", 0) as int
	if result_id <= 0:
		return
	var table_pos := _craft_table_pos
	if not _craft_table_item.is_empty():
		CraftingService.retrieve(_craft_table_item)
		_craft_table_item = {}
	craft_retrieve_ready.emit(result_id, result.get("result_uid", 0) as int, table_pos)

func _on_craft_retrieve_rejected(reason: String) -> void:
	craft_rejected.emit("取件失败：" + reason)

var _craft_start_pending: bool = false

func _on_craft_button_pressed() -> void:
	if _craft_table_item.is_empty():
		return
	if _craft_start_pending:
		return
	_craft_start_pending = true
	var table_pos: Vector2i = _get_table_grid_pos(_craft_table_item)
	if table_pos.x < 0 or table_pos.y < 0:
		_craft_start_pending = false
		return
	craft_start_requested.emit(table_pos)
	if CloudService.online:
		CloudService.submit_craft_start(table_pos.x, table_pos.y)

func _on_table_state_changed(table_item: Dictionary, state: int) -> void:
	if state == CraftingService.TableState.HAS_ITEMS:
		table_visual_update.emit(table_item, state)
		var recipe := CraftingService.get_current_recipe(table_item)
		if not recipe.is_empty():
			_craft_table_item = table_item
			var tpos := _get_table_grid_pos(table_item)
			if tpos.x >= 0:
				_craft_table_pos = tpos
			if _craft_button:
				_craft_button.show_for_recipe(recipe)
				_craft_button.set_table_pos(tpos, _cell_size)
		else:
			hide_button()
	elif state == CraftingService.TableState.CRAFTING:
		table_visual_update.emit(table_item, state)
		hide_button()
	else:
		table_visual_update.emit(table_item, state)

# --- Internal ---

func _clear_pending() -> void:
	_pending_src_key = ""
	_pending_src_pos = Vector2i(-1, -1)
	_pending_table_item = {}
	_pending_dragged_item = {}
	_pending_table_pos = Vector2i(-1, -1)
	_pending_ingredient_id = -1

func _get_table_grid_pos(table_item: Dictionary) -> Vector2i:
	for entry in GridManager.get_all_items():
		if entry.data == table_item:
			return entry.pos
	return Vector2i(-1, -1)

func sync_states() -> void:
	for entry in GridManager.get_all_items():
		var item: Dictionary = entry.data
		var cs: int = item.get("_craft_state", CraftingService.TableState.IDLE) as int
		if cs != CraftingService.TableState.IDLE:
			table_visual_update.emit(item, cs)
