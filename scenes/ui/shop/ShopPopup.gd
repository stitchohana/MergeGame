class_name ShopPopup extends BasePopup

@onready var title_label: Label = $Panel/TitleLabel
@onready var item_container: GridContainer = $Panel/ScrollContainer/ItemContainer
@onready var close_btn: Button = $Panel/CloseButton
@onready var refresh_btn: Button = $Panel/RefreshButton
@onready var countdown_label: Label = $Panel/CountdownLabel

var _revision: int = -1
var _refresh_cost: int = 100
var _remaining_seconds: int = 0
var _received_ticks: int = 0
var _retry_at: int = 0
var _pending: bool = false
var _load_error: String = ""
var _buy_buttons: Array[Button] = []

func _ready() -> void:
	close_btn.pressed.connect(_on_close)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	CloudService.shop_updated.connect(_on_shop_updated)
	CloudService.shop_failed.connect(_on_shop_failed)
	CloudService.shop_refresh_rejected.connect(_on_refresh_rejected)
	CloudService.buy_confirmed.connect(_on_buy_confirmed)
	CloudService.buy_rejected.connect(_on_buy_rejected)
	_fetch_items()

func _process(_delta: float) -> void:
	_update_controls()
	if _revision > 0 and _seconds_left() == 0 and not _pending \
			and not CloudService.shop_busy and CloudService.online and Time.get_ticks_msec() >= _retry_at:
		_fetch_items()

func _seconds_left() -> int:
	return maxi(0, _remaining_seconds - int((Time.get_ticks_msec() - _received_ticks) / 1000))

func _fetch_items() -> void:
	if CloudService.shop_busy:
		return
	_pending = true
	_load_error = ""
	_update_controls()
	CloudService.fetch_shop_items()

func show_items(items: Array) -> void:
	_clear_items()
	if items.is_empty():
		var hint: Label = Label.new()
		hint.text = "暂无商品"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_container.add_child(hint)
		return
	for entry: Dictionary in items:
		var item_data: Dictionary = ConfigDatabase.get_item_data(int(entry.get("id", 0)))
		if not item_data.is_empty():
			item_container.add_child(_build_item_button(item_data, entry))
	_update_controls()

func _build_item_button(item_data: Dictionary, entry: Dictionary) -> VBoxContainer:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(112, 168)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 5)
	var widget: ItemWidget = preload("res://scenes/ui/common/ItemWidget.tscn").instantiate() as ItemWidget
	vbox.add_child(widget)
	widget.setup(item_data)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var marker: Label = Label.new()
	marker.text = "订单需要" if bool(entry.get("order_required", false)) else ""
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 16)
	marker.add_theme_color_override("font_color", Color(0.25, 0.44, 0.26))
	vbox.add_child(marker)
	var limit: Label = Label.new()
	limit.text = "剩余 %d/%d 次" % [int(entry.get("remaining", 5)), int(entry.get("purchase_limit", 5))]
	limit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit.add_theme_font_size_override("font_size", 16)
	limit.add_theme_color_override("font_color", Color(0.32, 0.26, 0.2))
	vbox.add_child(limit)
	var buy_button: Button = Button.new()
	var remaining: int = int(entry.get("remaining", 5))
	var price: int = int(entry.get("price", 0))
	buy_button.text = "%d 灵石" % price if remaining > 0 else "已售罄"
	buy_button.custom_minimum_size = Vector2(112, 36)
	buy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy_button.set_meta("remaining", remaining)
	vbox.add_child(buy_button)
	_buy_buttons.append(buy_button)
	var item_id: int = int(item_data.get("id", 0))
	buy_button.pressed.connect(func(): _on_buy_pressed(item_id, price))
	return vbox

func _update_controls() -> void:
	var busy: bool = _pending or CloudService.shop_busy
	refresh_btn.text = "加载中…" if _revision < 0 and busy else "刷新全部 · %d 灵石" % _refresh_cost
	if _revision < 0 and not busy:
		refresh_btn.text = "重新加载"
	refresh_btn.disabled = busy
	if not _load_error.is_empty():
		countdown_label.text = _load_error
	elif _revision > 0:
		countdown_label.text = "自动刷新：%s" % TimeUtils.format_countdown(_seconds_left())
	for button: Button in _buy_buttons:
		button.disabled = busy or int(button.get_meta("remaining", 0)) <= 0

func _on_refresh_pressed() -> void:
	if _pending or CloudService.shop_busy:
		return
	if _revision < 0 or _seconds_left() == 0:
		_fetch_items()
		return
	if GameState.spirit_stones < _refresh_cost:
		EventBus.show_toast.emit("灵石不足")
		return
	_pending = true
	_update_controls()
	CloudService.submit_shop_refresh(_revision)

func _on_buy_pressed(item_id: int, price: int) -> void:
	if _pending or CloudService.shop_busy:
		return
	if _seconds_left() == 0:
		_fetch_items()
		return
	if GameState.spirit_stones < price:
		EventBus.show_toast.emit("灵石不足")
		return
	var spawn_pos: Vector2i = GridManager.find_nearest_empty(Vector2i(3, 3))
	if spawn_pos == Vector2i(-1, -1):
		EventBus.show_toast.emit("棋盘已满")
		return
	_pending = true
	_update_controls()
	CloudService.submit_buy(item_id, spawn_pos.x, spawn_pos.y, _revision)

func _on_shop_updated(data: Dictionary) -> void:
	var revision: int = int(data.get("revision", -1))
	if revision < _revision:
		return
	_pending = false
	_revision = revision
	_retry_at = 0
	_load_error = ""
	_refresh_cost = int(data.get("refresh_cost", 100))
	_remaining_seconds = int(data.get("remaining_seconds", 0))
	_received_ticks = Time.get_ticks_msec()
	show_items(data.get("items", []))

func _on_buy_confirmed(_result: Dictionary) -> void:
	_pending = false
	_update_controls()

func _on_shop_failed(reason: String) -> void:
	_pending = false
	_retry_at = Time.get_ticks_msec() + 10000
	_load_error = "请联网加载商品" if reason == "offline" else "商品加载失败，请重试"
	_update_controls()

func _on_refresh_rejected(reason: String) -> void:
	_pending = false
	_update_controls()
	EventBus.show_toast.emit("刷新失败：" + _error_text(reason))
	if CloudService.online:
		_fetch_items()

func _on_buy_rejected(reason: String) -> void:
	_pending = false
	_update_controls()
	EventBus.show_toast.emit("购买失败：" + _error_text(reason))
	if CloudService.online:
		_fetch_items()

func _error_text(reason: String) -> String:
	match reason:
		"purchase_limit_reached": return "该商品本轮已达限购次数"
		"shop_changed": return "商品已刷新，正在重新加载"
		"insufficient_stones": return "灵石不足"
		"offline": return "请先连接服务器"
		"target_occupied": return "目标格子已被占用"
	return reason

func _clear_items() -> void:
	_buy_buttons.clear()
	for child: Node in item_container.get_children():
		item_container.remove_child(child)
		child.queue_free()

func _on_close() -> void:
	UIManager.hide_popup(self)
