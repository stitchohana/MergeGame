class_name PendingRewardBar extends Control

@onready var claim_button: Button = $Button
@onready var item_icon: TextureRect = $Button/ItemIcon

var grid_view: Control = null
var _claim_pending: bool = false
var _claim_pending_uid: int = -1
var _pending_fly_source: Vector2 = Vector2.ZERO
var _pending_fly_texture: Texture2D = null
var _fly_node: TextureRect = null

func _ready() -> void:
	RewardManager.pending_rewards_changed.connect(_refresh)
	CloudService.pending_reward_claimed.connect(_on_claimed)
	CloudService.pending_reward_claimed_rejected.connect(_on_claim_rejected)
	claim_button.pressed.connect(_on_claim_button_pressed)
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_refresh(0)

func setup(grid: Control) -> void:
	grid_view = grid

func _refresh(_count: int) -> void:
	var rewards: Array = RewardManager.pending_rewards
	if rewards.is_empty():
		item_icon.texture = null
		claim_button.disabled = _claim_pending
		hide()
		return

	var reward: Dictionary = rewards[0]
	var item_id: int = int(reward.get("id", 0))
	var item_data: Dictionary = ConfigDatabase.get_item_data(item_id)
	var icon_path: String = str(item_data.get("icon", reward.get("icon", "")))
	var texture: Texture2D = load(icon_path) as Texture2D if not icon_path.is_empty() else null
	item_icon.texture = texture
	claim_button.tooltip_text = "%s (点击放入棋盘)" % str(reward.get("name", "暂存道具"))
	claim_button.disabled = _claim_pending
	show()

func _on_claim_button_pressed() -> void:
	if _claim_pending or RewardManager.pending_rewards.is_empty():
		return
	var reward: Dictionary = RewardManager.pending_rewards[0]
	var uid: int = int(reward.get("uid", -1))
	if uid < 0:
		return
	_claim_pending = true
	_claim_pending_uid = uid
	_pending_fly_source = item_icon.get_global_rect().get_center()
	_pending_fly_texture = item_icon.texture
	claim_button.disabled = true
	RewardManager.claim_pending_reward(uid)

func _on_claimed(result: Dictionary) -> void:
	if not _claim_pending:
		return
	var col: int = int(result.get("col", -1))
	var row: int = int(result.get("row", -1))
	var target: Vector2 = _grid_cell_center(col, row)
	var fly_texture: Texture2D = _pending_fly_texture
	if target.x >= 0.0 and target.y >= 0.0 and fly_texture != null:
		_play_fly_animation(fly_texture, target, result)
	else:
		_finish_claim(result)

func _on_claim_rejected(_reason: String) -> void:
	_claim_pending = false
	_claim_pending_uid = -1
	_pending_fly_texture = null
	claim_button.disabled = false
	_refresh(RewardManager.pending_rewards.size())

func _grid_cell_center(col: int, row: int) -> Vector2:
	if grid_view == null or not is_instance_valid(grid_view):
		return Vector2(-1.0, -1.0)
	if col < 0 or row < 0 or col >= Constants.GRID_COLS or row >= Constants.GRID_ROWS:
		return Vector2(-1.0, -1.0)
	var cell_origin: Vector2 = Vector2(col * Constants.CELL_STEP, row * Constants.CELL_STEP)
	var cell_center: Vector2 = cell_origin + Vector2(Constants.CELL_SIZE * 0.5, Constants.CELL_SIZE * 0.5)
	return grid_view.get_global_transform_with_canvas() * cell_center

func _play_fly_animation(texture: Texture2D, target: Vector2, result: Dictionary) -> void:
	var host: Control = UIManager.get_layer(UIManager.Layer.OVERLAY)
	if host == null or not is_instance_valid(host):
		_finish_claim(result)
		return
	var fly: TextureRect = TextureRect.new()
	fly.texture = texture
	fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.size = item_icon.get_global_rect().size
	fly.pivot_offset = fly.size * 0.5
	fly.z_index = 1000
	host.add_child(fly)
	fly.global_position = _pending_fly_source - fly.size * 0.5
	_fly_node = fly
	var tween: Tween = get_tree().create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly, "global_position", target - fly.size * 0.5, 0.34)
	tween.tween_property(fly, "scale", Vector2(0.7, 0.7), 0.34)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(fly):
			fly.queue_free()
		_fly_node = null
		_finish_claim(result)
	)

func _finish_claim(result: Dictionary) -> void:
	_claim_pending = false
	_claim_pending_uid = -1
	_pending_fly_texture = null
	claim_button.disabled = false
	if result.has("grid"):
		var server_grid: Array = result.get("grid", [])
		_sync_grid(server_grid)

func _sync_grid(grid: Array) -> void:
	GridManager._skip_anims = true
	GridManager.init_grid(GameState.current_board_type)
	GridManager.populate_from_server(grid)
	GridManager._skip_anims = false
