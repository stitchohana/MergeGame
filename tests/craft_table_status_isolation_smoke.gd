extends Node

const EMPTY_POS := Vector2i(2, 3)
const ACTIVE_POS := Vector2i(4, 3)
const EMPTY_UID: int = 996001
const ACTIVE_UID: int = 996002

var _view: GridView
var _recipe: Dictionary = {}


func _ready() -> void:
	CloudService.online = false
	await get_tree().process_frame
	for candidate: Dictionary in ConfigDatabase.get_recipes_for_item(17002):
		if int(candidate.get("id", 0)) == 1:
			_recipe = candidate
	assert(not _recipe.is_empty())
	GridManager.init_grid()
	# An old completed state can be corrected to an empty table by a server
	# snapshot while another identical furnace is still crafting.
	GridManager.populate_from_server([
		_entry(EMPTY_UID, EMPTY_POS, CraftingService.TableState.READY),
		_entry(ACTIVE_UID, ACTIVE_POS, CraftingService.TableState.CRAFTING),
	])
	_view = GridView.new()
	_view.grid_item_scene = preload("res://scenes/items/GridItem.tscn")
	_view.size = Vector2(Constants.CELL_STEP * 7, Constants.CELL_STEP * 9)
	add_child(_view)
	await get_tree().process_frame
	assert(_node_at(EMPTY_POS).status_ready_icon.visible)
	assert(_node_at(ACTIVE_POS).status_working_icon.visible)
	assert(GridManager.reconcile_from_server([
		_entry(EMPTY_UID, EMPTY_POS, CraftingService.TableState.IDLE),
		_entry(ACTIVE_UID, ACTIVE_POS, CraftingService.TableState.CRAFTING),
	]))
	_assert_empty(EMPTY_POS)
	assert(_node_at(ACTIVE_POS).status_working_icon.visible)

	# A late notification holds a detached snapshot with the same UID. It
	# must not replace the live empty table or reintroduce its READY badge.
	var stale: Dictionary = GridManager.get_item(EMPTY_POS).duplicate(true)
	stale["_craft_state"] = CraftingService.TableState.READY
	stale["_craft_result_id"] = 27001
	CraftingService.table_state_changed.emit(stale, CraftingService.TableState.READY)
	_assert_empty(EMPTY_POS)

	# Completion, movement, and retrieval update only the active instance.
	var active: Dictionary = GridManager.get_item(ACTIVE_POS) as Dictionary
	CraftingService.complete_craft_now(active)
	assert(_node_at(ACTIVE_POS).status_ready_icon.visible)
	_assert_empty(EMPTY_POS)
	var moved_pos := Vector2i(5, 3)
	assert(GridManager.move_item(ACTIVE_POS, moved_pos))
	assert(_node_at(moved_pos).status_ready_icon.visible)
	CraftingService.retrieve(active)
	_assert_empty(moved_pos)
	_assert_empty(EMPTY_POS)

	# Swapping authoritative UIDs at two same-ID positions must refresh the
	# existing nodes from the corresponding live board dictionaries.
	assert(GridManager.reconcile_from_server([
		_entry(ACTIVE_UID, EMPTY_POS, CraftingService.TableState.CRAFTING),
		_entry(EMPTY_UID, moved_pos, CraftingService.TableState.IDLE),
	]))
	assert(_node_at(EMPTY_POS).status_working_icon.visible)
	_assert_empty(moved_pos)
	var crafting: Dictionary = GridManager.get_item(EMPTY_POS) as Dictionary
	CraftingService.complete_craft_now(crafting)
	assert(_node_at(EMPTY_POS).status_ready_icon.visible)
	_assert_empty(moved_pos)

	# UID-less optimistic tables may have identical dictionary contents.
	# State notifications must use reference identity in that case.
	GridManager.init_grid()
	var optimistic: Dictionary = ConfigDatabase.get_item_data(17002).duplicate(true)
	optimistic["_uid"] = 0
	optimistic["_optimistic_action"] = true
	optimistic["_craft_state"] = CraftingService.TableState.READY
	optimistic["_craft_result_id"] = 27001
	assert(GridManager.add_item(optimistic, EMPTY_POS))
	assert(GridManager.add_item(optimistic, ACTIVE_POS))
	var second: Dictionary = GridManager.get_item(ACTIVE_POS) as Dictionary
	CraftingService.table_state_changed.emit(second, CraftingService.TableState.READY)
	assert(is_same(_node_at(EMPTY_POS).item_data, GridManager.get_item(EMPTY_POS)))
	assert(is_same(_node_at(ACTIVE_POS).item_data, second))
	CraftingService.retrieve(second)
	assert(_node_at(EMPTY_POS).status_ready_icon.visible)
	_assert_empty(ACTIVE_POS)
	CraftingService.reset_all()
	print("CRAFT_TABLE_STATUS_ISOLATION_SMOKE_OK identical_tables=true idle_sync=true stale_signal=true move=true retrieve=true uid_swap=true optimistic=true")
	get_tree().quit()


func _entry(uid: int, pos: Vector2i, state: int) -> Dictionary:
	var entry: Dictionary = {"id": 17002, "uid": uid, "col": pos.x, "row": pos.y}
	if state != CraftingService.TableState.IDLE:
		entry["craft"] = {
			"_craft_init": true,
			"_craft_state": state,
			"_craft_stored": [],
			"_craft_recipe": _recipe,
			"_craft_result_id": 27001,
			"_craft_start_time": int(Time.get_unix_time_from_system() * 1000),
		}
	return entry


func _node_at(pos: Vector2i) -> GridItem:
	return _view._item_nodes.get("%d,%d" % [pos.x, pos.y]) as GridItem


func _assert_empty(pos: Vector2i) -> void:
	var item: Dictionary = GridManager.get_item(pos) as Dictionary
	assert(int(item.get("_craft_state", CraftingService.TableState.IDLE)) == CraftingService.TableState.IDLE)
	assert(CraftingService.get_stored_items(item).is_empty())
	assert(_node_at(pos).status_idle_icon.visible, "An empty furnace must refresh its idle badge after sync")
	assert(not _node_at(pos).status_ready_icon.visible, "An empty furnace must not keep a completed badge")
	assert(not _node_at(pos).status_working_icon.visible)
	assert(is_same(_node_at(pos).item_data, item), "The badge must use the live furnace instance")
