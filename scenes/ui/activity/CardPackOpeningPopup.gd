class_name CardPackOpeningPopup extends CardCollectionPanel

var selected_reward: Dictionary = {}
var _open_selected: Button
var _open_all: Button


func _ready() -> void:
	super._ready()
	_title.text = "开启卡包"
	RewardManager.pending_rewards_changed.connect(func(_count: int) -> void: _refresh())


func setup_pack(reward: Dictionary) -> void:
	selected_reward = reward.duplicate(true)
	collection_id = int(reward.get("collection_id", 1))
	for collection: Dictionary in ConfigDatabase.card_collection.get("collections", []):
		if int(collection.collection_id) == collection_id:
			_activity_id = int(collection.activity_id)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_card_grids.clear()
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var busy: bool = CloudService.card_collection_busy or not CloudService.card_collection_request.is_empty()
	_retry.visible = not CloudService.card_collection_request.is_empty()
	_retry.disabled = CloudService.card_collection_busy
	var selected_exists: bool = RewardManager.pending_rewards.any(func(reward: Dictionary) -> bool: return int(reward.get("uid", -1)) == int(selected_reward.get("uid", -2)))
	var pack_def: Dictionary = {}
	for pack: Dictionary in ConfigDatabase.card_collection.get("packs", []):
		if int(pack.pack_id) == int(selected_reward.get("pack_id", 0)):
			pack_def = pack
	var star: int = clampi(int(pack_def.get("star", 1)), 1, 5)
	_summary.text = str(selected_reward.get("name", "卡包"))
	_status.text = "正在开启，请稍候…" if CloudService.card_collection_busy else ("上次操作未确认，请重试以恢复结果" if busy else "卡包从物品暂存区开启，卡片自动收入仙册")
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", _style(Color("203a3d"), STAR_COLORS[star - 1], 24))
	_body.add_child(hero)
	var hero_layout := VBoxContainer.new()
	hero_layout.add_theme_constant_override("separation", 16)
	hero.add_child(hero_layout)
	var stars: Label = _label("★".repeat(star), 34, STAR_COLORS[star - 1])
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_layout.add_child(stars)
	var guarantee: Label = _label("必得一张 %d 星卡片" % star, 24, Color("eed5a3"))
	guarantee.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_layout.add_child(guarantee)
	var detail: Label = _label("内含 %d 张卡片 · 收集山海万象" % int(pack_def.get("card_count", 0)), 16)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_layout.add_child(detail)
	_open_selected = _button("打开当前卡包" if selected_exists else "当前卡包已开启")
	_open_selected.disabled = busy or not selected_exists or not _is_active()
	_open_selected.pressed.connect(_open_pack.bind(false))
	_body.add_child(_open_selected)
	_open_all = _button("一键全开暂存区卡包")
	_open_all.disabled = busy or not _is_active() or not RewardManager.pending_rewards.any(func(reward: Dictionary) -> bool: return str(reward.get("kind", "")) == "card_pack")
	_open_all.pressed.connect(_open_pack.bind(true))
	_body.add_child(_open_all)
	var details: Button = _button("查看卡包概率与来源")
	details.disabled = pack_def.is_empty()
	details.pressed.connect(_show_pack_details.bind(pack_def))
	_body.add_child(details)
	if not _result_data.is_empty():
		_build_result(_result_data)
	else:
		var last_open: Dictionary = GameState.get_card_collection_progress(collection_id).get("last_open", {})
		if not last_open.is_empty():
			var last_button: Button = _button("查看上次开包结果")
			last_button.pressed.connect(func() -> void:
				_result_data = last_open
				_refresh()
			)
			_body.add_child(last_button)
	_resize_grids()


func _open_pack(all_packs: bool) -> void:
	var target: Dictionary = selected_reward
	if all_packs:
		# The original selection may already be opened; anchor all-open to a remaining pack.
		for reward: Dictionary in RewardManager.pending_rewards:
			if str(reward.get("kind", "")) == "card_pack":
				target = reward
				break
	CloudService.submit_card_collection("open_all" if all_packs else "open_selected", int(target.get("collection_id", 1)), int(target.get("uid", 0)))
	_refresh()


func _on_confirmed(data: Dictionary) -> void:
	if not visible or not data.has("cards"):
		return
	_result_data = data
	_refresh()
	_reveal_tween = create_tween()
	for child: Node in _result.get_children():
		if child is GridContainer:
			for tile: Control in child.get_children():
				tile.modulate.a = 0.0
				_reveal_tween.tween_property(tile, "modulate:a", 1.0, 0.12)
