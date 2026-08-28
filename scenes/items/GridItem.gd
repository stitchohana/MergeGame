class_name GridItem extends Control

# GridItem: A single item on the game board.
# Shows item icon, name, level, and optional status overlays.

var item_data: Dictionary = {}
var grid_position: Vector2i
var is_launcher: bool = false

var _orig_modulate: Color
var _orig_scale: Vector2
var _cell_step: int = Constants.CELL_STEP

@onready var name_label: Label = $NameLabel
@onready var level_label: Label = $LevelLabel
@onready var icon_rect: TextureRect = $IconRect
@onready var charge_label: Label = $ChargeLabel
@onready var immovable_icon: TextureRect = $ImmovableIcon
@onready var select_icon: TextureRect = $SelectIcon
@onready var require_icon: TextureRect = $RequireIcon
@onready var status_available_overlay: TextureRect = $StatusAvailableOverlay
@onready var status_charging_icon: TextureRect = $StatusChargingIcon
@onready var status_idle_icon: TextureRect = $StatusIdleIcon
@onready var status_loaded_icon: TextureRect = $StatusLoadedIcon
@onready var status_working_icon: TextureRect = $StatusWorkingIcon
@onready var status_ready_icon: TextureRect = $StatusReadyIcon
@onready var craft_hint_bubble: Control = $CraftHintBubble
@onready var craft_hint_icon: TextureRect = $CraftHintBubble/BubblePanel/HintIcon

var _is_selected: bool = false
var _craft_hint_tween: Tween = null
var _merge_hint_tween: Tween = null
var _available_breathe_tween: Tween = null

const AVAILABLE_OVERLAY_BASE_SCALE: float = 0.5
const AVAILABLE_OVERLAY_PEAK_SCALE: float = 0.7
const AVAILABLE_OVERLAY_HIDDEN_DURATION: float = 2.0
const AVAILABLE_OVERLAY_BREATHE_IN_DURATION: float = 0.5
const AVAILABLE_OVERLAY_HOLD_DURATION: float = 1.0
const AVAILABLE_OVERLAY_BREATHE_OUT_DURATION: float = 0.5
const AVAILABLE_OVERLAY_MAX_ALPHA: float = 0.7

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orig_modulate = modulate
	_orig_scale = scale

	select_icon.visible = false
	status_available_overlay.visible = false
	status_available_overlay.scale = Vector2.ONE * AVAILABLE_OVERLAY_BASE_SCALE
	status_available_overlay.modulate = Color(1, 1, 1, 0)
	status_charging_icon.visible = false
	status_idle_icon.visible = false
	status_loaded_icon.visible = false
	status_working_icon.visible = false
	status_ready_icon.visible = false
	craft_hint_bubble.hide()

func set_selected(active: bool) -> void:
	_is_selected = active
	if select_icon:
		select_icon.visible = active

func setup(data: Dictionary, pos: Vector2i, cell_step: int) -> void:
	item_data = data
	grid_position = pos
	_cell_step = cell_step
	is_launcher = _item_type() == Constants.ItemType.LAUNCHER

	custom_minimum_size = Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)
	size = Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)
	position = Vector2(pos.x * cell_step, pos.y * cell_step)

	_update_visuals()

func _update_visuals() -> void:
	# Apply crafting state visual if present (restored from server).
	if _item_type() == Constants.ItemType.CRAFTING:
		var cs: int = int(item_data.get("_craft_state", 0))
		set_crafting_state(cs)

	# Optional icon overlay
	var icon_path: String = item_data.get("icon", "")
	if icon_path and icon_rect:
		var tex := load(icon_path) as Texture2D
		if tex:
			icon_rect.texture = tex
			icon_rect.show()

	# The board shows item art only; text details live in the item detail panel.
	if name_label:
		name_label.hide()
	if level_label:
		level_label.hide()
	if charge_label:
		charge_label.hide()

	if immovable_icon:
		immovable_icon.visible = item_data.get("immovable") == true

	_update_status_icons()

func _update_status_icons() -> void:
	var is_immovable: bool = bool(item_data.get("immovable", false))
	# These six textures are facility-agnostic; only the state routing is facility-specific.
	if status_available_overlay:
		# Initial/immovable launchers may not have a runtime `charges` field yet.
		var charges: int = int(item_data.get("charges", item_data.get("max_charges", 0)))
		var is_charging: bool = is_launcher and charges <= 0 \
			and float(item_data.get("_recharge_remaining", 0.0)) > 0.0
		var is_available: bool = not is_immovable and is_launcher and charges > 0 and not is_charging
		_set_available_overlay_visible(is_available)
		if status_charging_icon:
			status_charging_icon.visible = is_charging
	if status_idle_icon:
		var is_crafting_table: bool = _item_type() == Constants.ItemType.CRAFTING
		var craft_state: int = int(item_data.get("_craft_state", 0))
		status_idle_icon.visible = is_crafting_table and craft_state == CraftingService.TableState.IDLE
		status_loaded_icon.visible = is_crafting_table and craft_state == CraftingService.TableState.HAS_ITEMS
		status_working_icon.visible = is_crafting_table and craft_state == CraftingService.TableState.CRAFTING
		status_ready_icon.visible = is_crafting_table and craft_state == CraftingService.TableState.READY

func _item_type() -> int:
	return int(item_data.get("type", Constants.ItemType.REGULAR))

func refresh_status_icons() -> void:
	_update_status_icons()

func _set_available_overlay_visible(should_show: bool) -> void:
	if status_available_overlay == null:
		return
	if not should_show:
		if _available_breathe_tween != null and _available_breathe_tween.is_valid():
			_available_breathe_tween.kill()
		_available_breathe_tween = null
		status_available_overlay.visible = false
		status_available_overlay.scale = Vector2.ONE * AVAILABLE_OVERLAY_BASE_SCALE
		status_available_overlay.modulate = Color(1, 1, 1, 0)
		return

	status_available_overlay.visible = true
	status_available_overlay.pivot_offset = status_available_overlay.size * 0.5
	if _available_breathe_tween != null and _available_breathe_tween.is_valid():
		return
	status_available_overlay.scale = Vector2.ONE * AVAILABLE_OVERLAY_BASE_SCALE
	status_available_overlay.modulate = Color(1, 1, 1, 0)
	_available_breathe_tween = create_tween().set_loops()
	_available_breathe_tween.tween_interval(AVAILABLE_OVERLAY_HIDDEN_DURATION)
	_available_breathe_tween.tween_property(status_available_overlay, "scale", Vector2.ONE * AVAILABLE_OVERLAY_PEAK_SCALE, AVAILABLE_OVERLAY_BREATHE_IN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_available_breathe_tween.parallel().tween_property(status_available_overlay, "modulate", Color(1, 1, 1, AVAILABLE_OVERLAY_MAX_ALPHA), AVAILABLE_OVERLAY_BREATHE_IN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_available_breathe_tween.tween_interval(AVAILABLE_OVERLAY_HOLD_DURATION)
	_available_breathe_tween.tween_property(status_available_overlay, "scale", Vector2.ONE * AVAILABLE_OVERLAY_BASE_SCALE, AVAILABLE_OVERLAY_BREATHE_OUT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_available_breathe_tween.parallel().tween_property(status_available_overlay, "modulate", Color(1, 1, 1, 0), AVAILABLE_OVERLAY_BREATHE_OUT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# Called by GridView during drag
func set_drag_active(active: bool) -> void:
	if active:
		modulate = Color(1, 1, 1, 0.4)
		scale = Vector2(0.9, 0.9)
	else:
		modulate = Color.WHITE
		scale = Vector2(1, 1)

func set_crafting_state(state: int) -> void:
	# state: 0=IDLE, 1=HAS_ITEMS, 2=CRAFTING, 3=READY
	item_data["_craft_state"] = state
	_update_status_icons()

func set_visual_position(pos: Vector2) -> void:
	position = pos

func set_required(required: bool) -> void:
	if require_icon:
		require_icon.visible = required

func is_required() -> bool:
	return require_icon != null and require_icon.visible

func show_crafting_hint(icon: Texture2D) -> void:
	if craft_hint_bubble == null or craft_hint_icon == null or icon == null:
		return
	if _craft_hint_tween != null and _craft_hint_tween.is_valid():
		_craft_hint_tween.kill()
	craft_hint_icon.texture = icon
	craft_hint_bubble.rotation_degrees = 0.0
	craft_hint_bubble.scale = Vector2.ONE
	craft_hint_bubble.show()
	print("[CraftHint] bubble_show table_id=", int(item_data.get("id", 0)), " table_pos=", grid_position,
		" visible=", craft_hint_bubble.visible, " global_rect=", craft_hint_bubble.get_global_rect(),
		" icon_path=", icon.resource_path)
	_craft_hint_tween = create_tween().set_loops()
	_craft_hint_tween.tween_property(craft_hint_bubble, "rotation_degrees", -6.0, 0.16).set_trans(Tween.TRANS_SINE)
	_craft_hint_tween.parallel().tween_property(craft_hint_bubble, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_SINE)
	_craft_hint_tween.tween_property(craft_hint_bubble, "rotation_degrees", 6.0, 0.32).set_trans(Tween.TRANS_SINE)
	_craft_hint_tween.parallel().tween_property(craft_hint_bubble, "scale", Vector2(0.96, 0.96), 0.32).set_trans(Tween.TRANS_SINE)
	_craft_hint_tween.tween_property(craft_hint_bubble, "rotation_degrees", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
	_craft_hint_tween.parallel().tween_property(craft_hint_bubble, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)

func hide_crafting_hint() -> void:
	var was_visible: bool = craft_hint_bubble != null and craft_hint_bubble.visible
	if _craft_hint_tween != null and _craft_hint_tween.is_valid():
		_craft_hint_tween.kill()
	_craft_hint_tween = null
	if craft_hint_bubble:
		craft_hint_bubble.rotation_degrees = 0.0
		craft_hint_bubble.scale = Vector2.ONE
		craft_hint_bubble.hide()
	if was_visible:
		print("[CraftHint] bubble_hide table_id=", int(item_data.get("id", 0)), " table_pos=", grid_position)

func play_merge_hint(offset: Vector2, scale_factor: float = 1.08,
		move_duration: float = 0.22, pause_duration: float = 0.14) -> void:
	# Loop a subtle move-toward-peer and scale-up hint on this item.
	stop_merge_hint()
	pivot_offset = size * 0.5
	var base_position: Vector2 = Vector2(grid_position.x * _cell_step, grid_position.y * _cell_step)
	position = base_position
	scale = Vector2.ONE
	_merge_hint_tween = create_tween().set_loops()
	_merge_hint_tween.tween_property(self, "position", base_position + offset, move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_merge_hint_tween.parallel().tween_property(self, "scale", Vector2(scale_factor, scale_factor), move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_merge_hint_tween.chain().tween_interval(pause_duration)
	_merge_hint_tween.tween_property(self, "position", base_position, move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_merge_hint_tween.parallel().tween_property(self, "scale", Vector2.ONE, move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_merge_hint_tween.chain().tween_interval(pause_duration)

func stop_merge_hint() -> void:
	if _merge_hint_tween != null and _merge_hint_tween.is_valid():
		_merge_hint_tween.kill()
	_merge_hint_tween = null
	pivot_offset = size * 0.5
	position = Vector2(grid_position.x * _cell_step, grid_position.y * _cell_step)
	scale = Vector2.ONE

func play_merge_animation() -> void:
	stop_merge_hint()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)

func play_spawn_animation() -> void:
	scale = Vector2(0, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.25)
