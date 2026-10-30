class_name ResourcePurchasePopup extends ConfirmPopup

var resource: String = "stamina"
var _quote: Dictionary = {}
var _period_key: String = ""
var _request_id: String = ""
var _pending: bool = false


func _ready() -> void:
	hide_animation_finished.connect(queue_free)
	title_label.text = "购买" + _resource_name()
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(_on_cancel)
	CloudService.resource_purchase_info_loaded.connect(_on_info_loaded)
	CloudService.resource_purchase_info_rejected.connect(_on_info_rejected)
	CloudService.resource_purchase_confirmed.connect(_on_purchased)
	CloudService.resource_purchase_rejected.connect(_on_purchase_rejected)
	_load_quote()


func _resource_name() -> String:
	return "体力" if resource == "stamina" else "灵力"


func _load_quote() -> void:
	_quote.clear()
	_request_id = ""
	confirm_btn.disabled = true
	confirm_btn.text = "加载中"
	message_label.text = "正在获取购买价格…"
	CloudService.fetch_resource_purchase_info()


func _on_info_loaded(data: Dictionary) -> void:
	if _pending:
		return
	var offers: Dictionary = data.get("resource_purchase", {})
	_quote = offers.get(resource, {})
	_period_key = String(offers.get("period_key", ""))
	if _quote.is_empty() or _period_key.is_empty():
		_on_info_rejected("invalid_response")
		return
	var cost: int = int(_quote.get("cost", 0))
	var amount: int = int(_quote.get("amount", 0))
	var increment: int = int(offers.get("cost_increment", 100))
	var reset_hour: int = int(offers.get("reset_hour", 5))
	message_label.text = "消耗 %d 灵石，购买 %d %s。\n今日每次购买加价 %d 灵石，\n北京时间每日 %d 点重置价格。" % [cost, amount, _resource_name(), increment, reset_hour]
	confirm_btn.text = "%d 灵石购买" % cost
	confirm_btn.disabled = false


func _on_info_rejected(_reason: String) -> void:
	message_label.text = "购买价格获取失败，请重试。"
	confirm_btn.text = "重试"
	confirm_btn.disabled = false


func _on_confirm() -> void:
	if _pending:
		return
	if CloudService.resource_purchase_busy:
		EventBus.show_toast.emit("上一笔购买正在确认，请稍候")
		return
	if _quote.is_empty():
		_load_quote()
		return
	if _request_id.is_empty() and GameState.spirit_stones < int(_quote.get("cost", 0)):
		EventBus.show_toast.emit("灵石不足")
		return
	if _request_id.is_empty():
		_request_id = "resource-%s-%s-%s" % [resource, str(Time.get_unix_time_from_system()), str(Time.get_ticks_usec())]
	_pending = true
	confirm_btn.disabled = true
	cancel_btn.disabled = true
	confirm_btn.text = "购买中…"
	CloudService.submit_resource_purchase(resource, int(_quote.get("purchase_count", 0)), _period_key, _request_id)


func _on_cancel() -> void:
	if not _pending:
		UIManager.hide_popup(self)


func _on_purchased(result: Dictionary) -> void:
	if not _pending or String(result.get("resource", "")) != resource:
		return
	_pending = false
	EventBus.show_toast.emit("购买成功，获得 %d %s" % [int(result.get("amount", 100)), _resource_name()])
	UIManager.hide_popup(self)


func _on_purchase_rejected(reason: String) -> void:
	if not _pending:
		return
	_pending = false
	cancel_btn.disabled = false
	confirm_btn.disabled = false
	confirm_btn.text = "重试购买"
	if reason == "state_conflict":
		EventBus.show_toast.emit("购买价格已更新，请重新确认")
		_load_quote()
	elif reason == "insufficient_stones":
		EventBus.show_toast.emit("灵石不足")
	else:
		EventBus.show_toast.emit("购买失败，请重试")
