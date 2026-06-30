extends Node

# StoragePouch: Player inventory pouch shared between boards.
# All operations go through the server — client syncs on confirmation.

signal pouch_updated(items: Array)
signal deposit_failed(reason: String)
signal withdraw_failed(reason: String)

var items: Array = []

var _pending_deposit_uid: int = -1
var _pending_withdraw_id: int = 0
var _pending_withdraw_pos: Vector2i = Vector2i(-1, -1)

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

func withdraw(item_id: int, target_pos: Vector2i) -> void:
	_pending_withdraw_id = item_id
	_pending_withdraw_pos = target_pos
	CloudService.submit_pouch_withdraw(item_id, target_pos.x, target_pos.y)

func _on_deposit_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	items = result.get("pouch", items)
	pouch_updated.emit(items)

	var uid: int = _pending_deposit_uid
	_pending_deposit_uid = -1
	if uid > 0:
		var pos := GridManager.find_pos_by_uid(uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)

func _on_withdraw_confirmed(result: Dictionary) -> void:
	GameState.version = result.get("new_version", GameState.version)
	items = result.get("pouch", items)
	pouch_updated.emit(items)

	if _pending_withdraw_id > 0:
		var item_data := ConfigDatabase.get_item_data(_pending_withdraw_id)
		if not item_data.is_empty():
			GridManager.add_item(item_data.duplicate(true), _pending_withdraw_pos)
	_pending_withdraw_id = 0
	_pending_withdraw_pos = Vector2i(-1, -1)

func _on_deposit_rejected(reason: String) -> void:
	_pending_deposit_uid = -1
	deposit_failed.emit(reason)

func _on_withdraw_rejected(reason: String) -> void:
	withdraw_failed.emit(reason)
