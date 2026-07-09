extends Node

# StoragePouch: Player inventory pouch shared between boards.
# All operations go through the server — client syncs on confirmation.

signal pouch_updated(items: Array)
signal deposit_failed(reason: String)
signal withdraw_failed(reason: String)

var items: Array = []

var _pending_deposit_uid: int = -1
var _pending_withdraw_uid: int = 0

func _ready() -> void:
	CloudService.pouch_deposit_confirmed.connect(_on_deposit_confirmed)
	CloudService.pouch_withdraw_confirmed.connect(_on_withdraw_confirmed)
	CloudService.pouch_deposit_rejected.connect(_on_deposit_rejected)
	CloudService.pouch_withdraw_rejected.connect(_on_withdraw_rejected)

func restore_from_server(data: Array) -> void:
	items = data.duplicate()
	pouch_updated.emit(items)

func deposit(uid: int) -> void:
	_pending_deposit_uid = uid
	CloudService.submit_pouch_deposit(uid)

func withdraw(uid: int) -> void:
	_pending_withdraw_uid = uid
	CloudService.submit_pouch_withdraw(uid)



func _on_deposit_confirmed(result: Dictionary) -> void:
	items = result.get("pouch", items)
	pouch_updated.emit(items)

	var uid: int = _pending_deposit_uid
	_pending_deposit_uid = -1
	if uid > 0:
		var pos := GridManager.find_pos_by_uid(uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)

func _on_withdraw_confirmed(result: Dictionary) -> void:
	var target_id: int = 0
	if _pending_withdraw_uid > 0:
		for p in items:
			if p.get("uid", 0) == _pending_withdraw_uid:
				target_id = p.get("id", 0) as int
				break

	items = result.get("pouch", items)
	pouch_updated.emit(items)

	if _pending_withdraw_uid > 0 and target_id > 0:
		var pos := Vector2i(result.get("col", 3) as int, result.get("row", 3) as int)
		var item_data := ConfigDatabase.get_item_data(target_id)
		if not item_data.is_empty():
			var new_item := item_data.duplicate(true)
			new_item["_uid"] = _pending_withdraw_uid
			GridManager.add_item(new_item, pos)
	# was: _add_current_cache(_pending_withdraw_uid, target_id, pos.x, pos.y)
	_pending_withdraw_uid = 0

func _on_deposit_rejected(reason: String) -> void:
	_pending_deposit_uid = -1
	deposit_failed.emit(reason)

func _on_withdraw_rejected(reason: String) -> void:
	withdraw_failed.emit(reason)
