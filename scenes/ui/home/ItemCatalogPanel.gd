class_name ItemCatalogPanel extends BasePopup

const CATEGORIES: Array[Dictionary] = [
	{"type": Constants.ItemType.REGULAR, "name": "材料"},
	{"type": Constants.ItemType.LAUNCHER, "name": "发射器"},
	{"type": Constants.ItemType.CRAFTING, "name": "制作台"},
	{"type": Constants.ItemType.RECIPE_PRODUCT, "name": "配方产物"},
	{"type": Constants.ItemType.EFFECT, "name": "效果物品"},
]
const ENERGY_ICON: Texture2D = preload("res://assets/ui/xianxia_v3_layers_v2/layers/energy_lightning_icon.png")

var _tabs: TabContainer
var _summary: Label
var _status: Label
var _grids: Array[GridContainer] = []
var _tiles: Dictionary = {}


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.035, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_anchor(SIDE_LEFT, 0.04)
	panel.set_anchor(SIDE_TOP, 0.12)
	panel.set_anchor(SIDE_RIGHT, 0.96)
	panel.set_anchor(SIDE_BOTTOM, 0.92)
	panel.add_theme_stylebox_override("panel", _style(Color("14292d"), Color("9d8454"), 18))
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title: Label = _label("万物图鉴", 30, Color("eed5a3"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "关闭"
	close.custom_minimum_size = Vector2(86, 54)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void: UIManager.hide_popup(self))
	header.add_child(close)
	_summary = _label("", 20, Color("eed5a3"))
	layout.add_child(_summary)
	var help: Label = _label("首次获得即可解锁 · 点击奖励图标领取 1 体力", 17)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)
	_tabs = TabContainer.new()
	_tabs.name = "CategoryTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	_tabs.get_tab_bar().add_theme_font_size_override("font_size", 18)
	_tabs.get_tab_bar().tab_alignment = TabBar.ALIGNMENT_LEFT
	_tabs.add_theme_stylebox_override("panel", _style(Color("14292d"), Color("526b69"), 10))
	layout.add_child(_tabs)
	for category: Dictionary in CATEGORIES:
		_build_category(category)
	_status = _label("每件物品的解锁奖励只能领取一次", 17)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	GameState.item_catalog_changed.connect(_refresh)
	CloudService.item_catalog_claim_rejected.connect(_on_rejected)
	CloudService.item_catalog_claim_confirmed.connect(_on_confirmed)
	_tabs.tab_changed.connect(_on_tab_changed)
	resized.connect(_resize_grids)
	_refresh()
	_resize_grids.call_deferred()


func _build_category(category: Dictionary) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = str(category.name)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tabs.add_child(scroll)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	_grids.append(grid)
	var items: Array = ConfigDatabase.get_items_for_catalog(int(category.type))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if ConfigDatabase._coerce_int(a.get("group_id")) != ConfigDatabase._coerce_int(b.get("group_id")):
			return ConfigDatabase._coerce_int(a.get("group_id")) < ConfigDatabase._coerce_int(b.get("group_id"))
		if ConfigDatabase._coerce_int(a.get("level")) != ConfigDatabase._coerce_int(b.get("level")):
			return ConfigDatabase._coerce_int(a.get("level")) < ConfigDatabase._coerce_int(b.get("level"))
		return int(a.id) < int(b.id)
	)
	for item: Dictionary in items:
		grid.add_child(_build_tile(item, scroll))


func _build_tile(item: Dictionary, scroll: ScrollContainer) -> Button:
	var item_id: int = int(item.id)
	var tile := Button.new()
	tile.name = "Item_%d" % item_id
	tile.set_meta("item_id", item_id)
	tile.custom_minimum_size = Vector2(124, 172)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var level: Label = _label("%d阶" % ConfigDatabase._coerce_int(item.get("level"), 1), 15)
	box.add_child(level)
	var visual := Control.new()
	visual.custom_minimum_size = Vector2(0, 72)
	visual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(visual)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(icon)
	var mark: Label = _label("？", 44, Color("7e9690"))
	mark.name = "Unknown"
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	visual.add_child(mark)
	var title: Label = _label("", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var status: Label = _label("", 15, Color("eed5a3"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	# A scroll gesture must not claim the tile under the release position.
	tile.button_down.connect(func() -> void:
		tile.set_meta("press_position", get_global_mouse_position())
		tile.set_meta("press_scroll", scroll.scroll_vertical)
	)
	tile.pressed.connect(func() -> void:
		var press_position: Vector2 = tile.get_meta("press_position", get_global_mouse_position())
		if press_position.distance_to(get_global_mouse_position()) > 12.0 or int(tile.get_meta("press_scroll", scroll.scroll_vertical)) != scroll.scroll_vertical:
			return
		CloudService.submit_item_catalog_claim(item_id)
	)
	_tiles[item_id] = {"button": tile, "icon": icon, "mark": mark, "title": title, "status": status, "item": item}
	return tile


func _refresh() -> void:
	if not is_node_ready():
		return
	var unlocked: int = 0
	for item_id: int in _tiles:
		var data: Dictionary = _tiles[item_id]
		var item: Dictionary = data.item
		var discovered: bool = GameState.has_crafted_item(item_id)
		var claimable: bool = GameState.can_claim_item_catalog_reward(item_id)
		var claimed: bool = GameState.item_catalog_claimed_ids.has(item_id)
		var pending: bool = CloudService.item_catalog_claim_pending == item_id
		if discovered:
			unlocked += 1
		var tile: Button = data.button
		tile.disabled = not claimable or CloudService.item_catalog_claim_pending > 0
		tile.tooltip_text = "%s · %s" % [str(item.name), str(item.get("describe", ""))] if discovered else "首次获得该物品后解锁"
		var style: StyleBoxFlat = _style(Color("274442") if claimable else Color("1b3235"), Color("d7b56d") if claimable else Color("526b69"), 10)
		for state: String in ["normal", "disabled", "hover", "pressed", "focus"]:
			tile.add_theme_stylebox_override(state, style)
		var icon: TextureRect = data.icon
		icon.texture = ENERGY_ICON if claimable else null
		if claimed:
			var path: String = str(item.get("icon", ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				icon.texture = load(path) as Texture2D
		icon.visible = icon.texture != null
		var mark: Label = data.mark
		mark.visible = icon.texture == null
		mark.text = str(item.name).left(1) if claimed else "？"
		var title: Label = data.title
		title.text = str(item.name) if discovered else "未解锁"
		var status: Label = data.status
		status.text = "领取中…" if pending else ("领取 +1 体力" if claimable else ("已领取" if claimed else "尚未获得"))
	_summary.text = "已解锁 %d / %d · 待领奖励 %d" % [unlocked, _tiles.size(), GameState.get_item_catalog_claimable_count()]
	if CloudService.item_catalog_claim_pending > 0:
		_status.text = "正在领取，请稍候…"


func _on_confirmed(data: Dictionary) -> void:
	_status.text = "奖励已领取" if bool(data.get("already_claimed", false)) else "领取成功 · 体力 +1"
	_scroll_to_next_claimable.call_deferred(ConfigDatabase._coerce_int(data.get("item_id")))


func _scroll_to_next_claimable(claimed_item_id: int) -> void:
	# Let container layout finish before using the target row's position.
	await get_tree().process_frame
	if not is_visible_in_tree() or not _tiles.has(claimed_item_id):
		return
	var tab_index: int = _tabs.current_tab
	if tab_index < 0 or tab_index >= _grids.size():
		return
	var grid: GridContainer = _grids[tab_index]
	var claimed_tile: Button = _tiles[claimed_item_id].button
	# Keep the user's chosen page if they switched tabs during the request.
	if claimed_tile.get_parent() != grid:
		return
	var count: int = grid.get_child_count()
	var start_index: int = claimed_tile.get_index() + 1
	for offset: int in range(count):
		var tile: Button = grid.get_child((start_index + offset) % count) as Button
		var item_id: int = int(tile.get_meta("item_id", 0))
		if GameState.can_claim_item_catalog_reward(item_id):
			var scroll: ScrollContainer = grid.get_parent() as ScrollContainer
			# Use the absolute row offset so consecutive confirmations cannot
			# accumulate scroll deltas before the container updates its position.
			scroll.scroll_vertical = roundi(tile.position.y)
			return


func _on_rejected(reason: String) -> void:
	var messages: Dictionary = {"item_locked": "该物品尚未解锁，正在同步", "state_conflict": "进度已更新，正在同步，请稍后重试", "save_failed": "奖励保存未完成，请点击重试"}
	_status.text = str(messages.get(reason, "领取未确认，请检查网络后点击奖励图标重试"))


func _on_tab_changed(_index: int) -> void:
	_resize_grids.call_deferred()


func _resize_grids() -> void:
	for grid: GridContainer in _grids:
		grid.columns = clampi(int((size.x * 0.92 - 70.0) / 136.0), 1, 5)


func _label(text: String, font_size: int, color: Color = Color("b9ccc4")) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style
