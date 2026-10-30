extends Node

# StoragePouch: Player inventory pouch shared between boards.
# All operations go through the server — client syncs on confirmation.

signal pouch_updated(items: Array)
signal deposit_failed(reason: String)
signal withdraw_failed(reason: String)

var items: Array = []
var capacity: int = 7
var next_unlock_cost: int = 100
var unlock_pending: bool = false

var _pending_deposit_uid: int = -1
var _pending_withdraw_uid: int = 0

func _ready() -> void:
	capacity = maxi(1, int(ConfigDatabase.get_game_config("pouch.initial_slots", 7)))
	next_unlock_cost = maxi(1, int(ConfigDatabase.get_game_config("pouch.unlock_cost_base", 100)))
	CloudService.pouch_deposit_confirmed.connect(_on_deposit_confirmed)
	CloudService.pouch_withdraw_confirmed.connect(_on_withdraw_confirmed)
	CloudService.pouch_deposit_rejected.connect(_on_deposit_rejected)
	CloudService.pouch_withdraw_rejected.connect(_on_withdraw_rejected)
	CloudService.pouch_unlock_confirmed.connect(_on_unlock_confirmed)
	CloudService.pouch_unlock_rejected.connect(_on_unlock_rejected)
	CloudService.state_loaded.connect(sync_state)

func restore_from_server(data: Array, state: Dictionary = {}) -> void:
	items = data.duplicate()
	_apply_capacity(state)
	pouch_updated.emit(items)

func sync_state(state: Dictionary) -> void:
	if state.has("pouch"):
		items = (state.get("pouch", []) as Array).duplicate()
	_apply_capacity(state)
	if state.has("spirit_stones"):
		GameState.spirit_stones = int(state.get("spirit_stones", GameState.spirit_stones))
		GameState.spirit_stones_changed.emit(GameState.spirit_stones)
	pouch_updated.emit(items)

func _apply_capacity(state: Dictionary) -> void:
	capacity = int(state.get("pouch_capacity", capacity))
	next_unlock_cost = int(state.get("pouch_next_unlock_cost", next_unlock_cost))

func unlock_slot() -> void:
	if unlock_pending:
		return
	if not CloudService.online:
		EventBus.show_toast.emit("请联网后解锁储物袋格子")
		return
	if GameState.spirit_stones < next_unlock_cost:
		EventBus.show_toast.emit("灵石不足")
		return
	unlock_pending = true
	pouch_updated.emit(items)
	CloudService.submit_pouch_unlock(capacity)

func _on_unlock_confirmed(result: Dictionary) -> void:
	unlock_pending = false
	_apply_capacity(result)
	GameState.spirit_stones = int(result.get("spirit_stones", GameState.spirit_stones))
	GameState.spirit_stones_changed.emit(GameState.spirit_stones)
	pouch_updated.emit(items)
	EventBus.show_toast.emit("储物袋已解锁 1 格")

func _on_unlock_rejected(reason: String) -> void:
	unlock_pending = false
	pouch_updated.emit(items)
	match reason:
		"insufficient_stones": EventBus.show_toast.emit("灵石不足")
		"state_conflict": EventBus.show_toast.emit("储物袋状态已更新，请稍后重试")
		"pouch_limit_reached": EventBus.show_toast.emit("储物袋已达到容量上限")
		_: EventBus.show_toast.emit("解锁失败，请稍后重试")
	if CloudService.online:
		CloudService.fetch_state()

func deposit(uid: int) -> void:
	if _pending_deposit_uid > 0:
		deposit_failed.emit("request_in_flight")
		return
	if items.size() >= capacity:
		deposit_failed.emit("pouch_full")
		return
	_pending_deposit_uid = uid
	CloudService.submit_pouch_deposit(uid)

func withdraw(uid: int) -> void:
	if _pending_withdraw_uid > 0:
		return
	_pending_withdraw_uid = uid
	CloudService.submit_pouch_withdraw(uid)



func _on_deposit_confirmed(result: Dictionary) -> void:
	items = result.get("pouch", items)
	_apply_capacity(result)
	pouch_updated.emit(items)

	var uid: int = _pending_deposit_uid
	_pending_deposit_uid = -1
	if uid > 0:
		var pos := GridManager.find_pos_by_uid(uid)
		if pos != Vector2i(-1, -1):
			GridManager.remove_item(pos)

func _on_withdraw_confirmed(result: Dictionary) -> void:
	var entry: Dictionary = result.get("item", {}) as Dictionary
	if entry.is_empty():
		for stored: Variant in items:
			if stored is Dictionary and int(stored.get("uid", 0)) == _pending_withdraw_uid:
				entry = stored as Dictionary
				break
	items = result.get("pouch", items)
	_apply_capacity(result)
	if _pending_withdraw_uid > 0 and not entry.is_empty():
		var pos := Vector2i(int(result.get("col", 3)), int(result.get("row", 3)))
		var item: Dictionary = GridManager.item_data_from_server(entry)
		if not item.is_empty():
			GridManager.add_item(item, pos)
			if int(item.get("type", 0)) == Constants.ItemType.CRAFTING:
				CraftingService.restore_craft_timer_for_item(item)
	_pending_withdraw_uid = 0
	pouch_updated.emit(items)


func _on_deposit_rejected(reason: String) -> void:
	_pending_deposit_uid = -1
	deposit_failed.emit(reason)

func _on_withdraw_rejected(reason: String) -> void:
	_pending_withdraw_uid = 0
	withdraw_failed.emit(reason)
