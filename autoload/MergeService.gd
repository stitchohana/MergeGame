extends Node

# MergeService: Server-authoritative merge.

signal merge_performed(result_data: Dictionary, pos: Vector2i)
signal merge_failed(reason: String)

var _pending_merge: Dictionary = {}

func is_position_pending(pos: Vector2i) -> bool:
	if _pending_merge.is_empty():
		return false
	return (
		pos == _pending_merge.get("from_pos", Vector2i(-1, -1))
		or pos == _pending_merge.get("to_pos", Vector2i(-1, -1))
	)

func _ready() -> void:
	CloudService.merge_confirmed.connect(_on_merge_confirmed)
	CloudService.merge_rejected.connect(_on_merge_rejected)

func can_merge(item_a_data: Dictionary, item_b_data: Dictionary) -> bool:
	if item_a_data.is_empty() or item_b_data.is_empty():
		return false
	if item_a_data.get("group_id", 0) != item_b_data.get("group_id", 0):
		return false
	if item_a_data.get("id", 0) != item_b_data.get("id", 0):
		return false
	var type: int = item_a_data.get("type", 0)
	var level: int = item_a_data.get("level", 0)
	var gid: int = item_a_data.get("group_id", 0)
	var next = ConfigDatabase.get_next_level(type, level, gid)
	return not next.is_empty()

func try_merge(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	var item_a = GridManager.get_item(from_pos)
	var item_b = GridManager.get_item(to_pos)
	if item_a == null or item_b == null:
		merge_failed.emit("Invalid item")
		return false
	if not can_merge(item_a, item_b):
		print("[MergeService] can_merge failed: #" + str(item_a.get("id",0)) + " vs #" + str(item_b.get("id",0)))
		merge_failed.emit("Cannot merge")
		return false
	if not _pending_merge.is_empty():
		merge_failed.emit("merge_pending")
		return false

	var next_item: Dictionary = ConfigDatabase.get_next_level(
		item_a.get("type", 0) as int,
		item_a.get("level", 0) as int,
		item_a.get("group_id", 0) as int
	)
	if next_item.is_empty():
		merge_failed.emit("Cannot merge")
		return false
	_pending_merge = {
		"from_pos": from_pos,
		"to_pos": to_pos,
		"from_item": item_a.duplicate(true),
		"to_item": item_b.duplicate(true),
	}
	GridManager.remove_item(from_pos)
	GridManager.remove_item(to_pos)
	var predicted: Dictionary = next_item.duplicate(true)
	predicted["_uid"] = item_b.get("_uid", 0)
	predicted["_pending_merge"] = true
	GridManager.add_item(predicted, to_pos)

	print("[MergeService] submit_merge: from=" + str(from_pos) + " id=" + str(item_a.get("id",0)) + " to=" + str(to_pos) + " id=" + str(item_b.get("id",0)))
	CloudService.submit_merge(from_pos.x, from_pos.y, to_pos.x, to_pos.y)
	return true

func _on_merge_confirmed(result: Dictionary) -> void:
	var regen: float = result.get("regen_remaining_ms", 0.0)
	if regen > 0:
		GameState.regen_remaining_ms = regen

	var result_id: int = result.get("result_id", 0)
	var from_pos := Vector2i(result.get("from_col", -1), result.get("from_row", -1))
	var to_pos := Vector2i(result.get("to_col", -1), result.get("to_row", -1))
	_pending_merge = {}

	if result_id > 0 and from_pos.x >= 0:
		GridManager.remove_item(from_pos)
		GridManager.remove_item(to_pos)
		var merged_data: Dictionary = ConfigDatabase.get_item_data(result_id)
		if not merged_data.is_empty():
			var item := merged_data.duplicate(true)
			item["_uid"] = result.get("result_uid", 0)
			if Constants.has_launcher_config(item):
				item["charges"] = item.get("max_charges", 3)
			var atk_base: int = result.get("atk_base", 0) as int
			if atk_base > 0:
				item["atk_base"] = atk_base
			GridManager.add_item(item, to_pos)

	merge_performed.emit(result, to_pos)

func _on_merge_rejected(reason: String) -> void:
	_rollback_pending_merge()
	EventBus.show_toast.emit(_merge_error_text(reason))
	merge_failed.emit(reason)

func _rollback_pending_merge() -> void:
	if _pending_merge.is_empty():
		return
	var from_pos: Vector2i = _pending_merge.get("from_pos", Vector2i(-1, -1))
	var to_pos: Vector2i = _pending_merge.get("to_pos", Vector2i(-1, -1))
	var from_item: Dictionary = _pending_merge.get("from_item", {})
	var to_item: Dictionary = _pending_merge.get("to_item", {})
	_pending_merge = {}
	if GridManager.is_valid_pos(to_pos) and not GridManager.is_empty(to_pos):
		GridManager.remove_item(to_pos)
	if not from_item.is_empty() and GridManager.is_empty(from_pos):
		GridManager.add_item(from_item, from_pos)
	if not to_item.is_empty() and GridManager.is_empty(to_pos):
		GridManager.add_item(to_item, to_pos)

func _merge_error_text(reason: String) -> String:
	match reason:
		"source_item_not_found": return "合并失败：物品不存在"
		"target_item_not_found": return "合并失败：目标物品不存在"
		"group_id_mismatch": return "合并失败：物品类型不同"
		"item_id_mismatch": return "合并失败：物品不同"
		"already_max_level": return "合并失败：已达最高等级"
		"network_error": return "合并失败：网络错误"
		_: return "合并失败：" + reason
