extends Node

# MergeService: Server-authoritative merge. Uses client positions for local update on confirm.

signal merge_performed(result_data: Dictionary, pos: Vector2i)
signal merge_failed(reason: String)

var _pending_from: Vector2i = Vector2i(-1, -1)
var _pending_to: Vector2i = Vector2i(-1, -1)

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
	var type: String = item_a_data.get("type", "")
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
		merge_failed.emit("Cannot merge")
		return false

	if CloudService.online:
		_pending_from = from_pos
		_pending_to = to_pos
		CloudService.submit_merge(from_pos.x, from_pos.y, to_pos.x, to_pos.y, GameState.version)
		return true
	return false

func _on_merge_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)

	var result_id: int = result.get("result_id", 0)
	if result_id > 0 and _pending_from.x >= 0:
		GridManager.remove_item(_pending_from)
		GridManager.remove_item(_pending_to)
		var merged_data: Dictionary = ConfigDatabase.get_item_data(result_id)
		if not merged_data.is_empty():
			var item := merged_data.duplicate(true)
			if item.get("type", "") == "launcher":
				item["charges"] = item.get("max_charges", 3)
			GridManager.add_item(item, _pending_to)

	GameState.add_score(maxi(0, result.get("new_score", GameState.score) - GameState.score))
	merge_performed.emit(result, _pending_to)
	_pending_from = Vector2i(-1, -1)
	_pending_to = Vector2i(-1, -1)

func _on_merge_rejected(reason: String) -> void:
	_pending_from = Vector2i(-1, -1)
	_pending_to = Vector2i(-1, -1)
	EventBus.show_toast.emit(_merge_error_text(reason))
	merge_failed.emit(reason)

func _merge_error_text(reason: String) -> String:
	match reason:
		"source_item_not_found": return "合并失败：物品不存在"
		"target_item_not_found": return "合并失败：目标物品不存在"
		"group_id_mismatch": return "合并失败：物品类型不同"
		"item_id_mismatch": return "合并失败：物品不同"
		"already_max_level": return "合并失败：已达最高等级"
		"network_error": return "合并失败：网络错误"
		"version_mismatch": return "合并失败：数据过期，请重试"
		_: return "合并失败：" + reason
