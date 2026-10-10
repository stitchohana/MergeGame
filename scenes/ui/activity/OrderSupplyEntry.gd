class_name OrderSupplyEntry extends Button

signal claim_requested(activity_id: int, expected_claim_count: int)

var _activity_id: int = 0
var _claim_pending: bool = false


func _ready() -> void:
	pressed.connect(_on_pressed)
	ActivityManager.activity_updated.connect(_on_activity_updated)
	CloudService.order_supply_claim_confirmed.connect(_on_claim_confirmed)
	CloudService.order_supply_claim_rejected.connect(_on_claim_rejected)
	_refresh()


func _on_activity_updated(_id: int) -> void:
	_refresh()


func _refresh() -> void:
	visible = false
	for activity: Dictionary in ActivityManager.get_active_activities():
		if str(activity.get("widget", "")) != "OrderSupply":
			continue
		_activity_id = int(activity.get("id", 0))
		var settings: Dictionary = activity.get("config", {})
		var target: int = maxi(1, int(settings.get("target_count", 5)))
		var completed: int = clampi(int(ActivityManager.get_progress(_activity_id).get("current_count", 0)), 0, target)
		var ready_to_claim: bool = completed >= target
		tooltip_text = "直接生成或合成出当前订单需要的物品，或成功开始制作订单要求的成品，每次累计 1 次；子材料不计数；累计 %d 次可领取" % target
		text = "%s  %d/%d%s" % [str(activity.get("name", "订单补给")), completed, target,
			"  领取中" if _claim_pending else ("  领取" if ready_to_claim else "")]
		disabled = _claim_pending or not ready_to_claim
		visible = true
		return


func _on_pressed() -> void:
	if disabled or _claim_pending:
		return
	_claim_pending = true
	_refresh()
	var completed_rounds: int = int(ActivityManager.get_progress(_activity_id).get("claim_count", 0))
	claim_requested.emit(_activity_id, completed_rounds)


func _on_claim_confirmed(result: Dictionary) -> void:
	if int(result.get("activity_id", 0)) != _activity_id:
		return
	_claim_pending = false
	_refresh()


func _on_claim_rejected(_reason: String) -> void:
	_claim_pending = false
	_refresh()
