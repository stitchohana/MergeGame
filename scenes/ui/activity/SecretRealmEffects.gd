extends Control

signal finished

const ITEM_SCENE := preload("res://scenes/items/GridItem.tscn")
const ATTACK_DURATION: float = 0.48
const DEFEAT_DURATION: float = 0.28
const DROP_SPEED: float = 2.0
const DROP_DURATION: float = 0.72 / DROP_SPEED
var phase: String = "idle"
var drop_visuals: Array[GridItem] = []
var _timeline: Tween
var _tweens: Array[Tween] = []
var _monster: Control
var _drops: Array = []
var _definitions: Dictionary = {}
var _origin: Vector2


func play(monster: Control, drops: Array, definitions: Dictionary, origin: Vector2) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	_monster = monster
	_drops = drops
	_definitions = definitions
	_origin = origin
	_timeline = create_tween()
	if is_instance_valid(monster):
		_start_attack()
		_timeline.tween_interval(ATTACK_DURATION)
		_timeline.tween_callback(_fade_monster)
		_timeline.tween_interval(DEFEAT_DURATION)
	if not drops.is_empty():
		if is_instance_valid(monster):
			_timeline.tween_callback(_start_drops)
		else:
			_start_drops()
		_timeline.tween_interval(DROP_DURATION)
	_timeline.tween_callback(_finish)


func _track(tween: Tween) -> Tween:
	_tweens.append(tween)
	return tween


func _start_attack() -> void:
	phase = "attack"
	var index: int = 0
	for badge: Control in _monster.submitted_icons:
		var id: String = str(badge.get_meta("item_id", ""))
		var definition: Dictionary = _definitions.get(id, {})
		var projectile := TextureRect.new()
		projectile.texture = load("res://assets/ui/secret_realm/%s.svg" % definition.get("chain", "sword")) as Texture2D
		projectile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		projectile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		projectile.size = Vector2(42, 42)
		projectile.pivot_offset = projectile.size * 0.5
		projectile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(projectile)
		var start: Vector2 = get_global_transform_with_canvas().affine_inverse() * badge.get_global_rect().get_center() - projectile.size * 0.5
		projectile.position = start
		projectile.rotation = -0.65 if definition.get("chain", "") == "sword" else 0.0
		var tween: Tween = _track(create_tween())
		tween.tween_interval(index * 0.025)
		tween.tween_method(_move_arc.bind(projectile, start, _origin + Vector2(-21, -21), 28.0), 0.0, 1.0, 0.24)
		tween.parallel().tween_property(projectile, "scale", Vector2(1.25, 1.25), 0.24)
		tween.tween_property(projectile, "modulate:a", 0.0, 0.08)
		badge.hide()
		index += 1
	# Expanding qi ring and a bright impact illuminate the monster.
	var ring := Panel.new()
	ring.size = Vector2(70, 70)
	ring.pivot_offset = ring.size * 0.5
	ring.position = _origin - ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.9, 1.0, 0.12)
	style.border_color = Color("acf2ec")
	style.set_border_width_all(3)
	style.set_corner_radius_all(35)
	ring.add_theme_stylebox_override("panel", style)
	ring.scale = Vector2(0.3, 0.3)
	ring.modulate.a = 0.0
	add_child(ring)
	var pulse: Tween = _track(create_tween())
	pulse.tween_interval(0.20)
	pulse.tween_property(ring, "modulate:a", 1.0, 0.04)
	pulse.tween_property(ring, "scale", Vector2(1.5, 1.5), 0.24)
	pulse.parallel().tween_property(ring, "modulate:a", 0.0, 0.24)
	var visual: TextureRect = _monster.monster_visual
	if is_instance_valid(visual):
		var hit: Tween = _track(create_tween())
		hit.tween_interval(0.24)
		hit.tween_property(visual, "modulate", Color(2.5, 2.2, 1.5), 0.04)
		hit.tween_property(visual, "position:x", 5.0, 0.035)
		hit.tween_property(visual, "position:x", -5.0, 0.035)
		hit.tween_property(visual, "position:x", 0.0, 0.035)
		hit.parallel().tween_property(visual, "modulate", Color.WHITE, 0.105)


func _fade_monster() -> void:
	phase = "defeat"
	var visual: TextureRect = _monster.monster_visual
	if is_instance_valid(visual):
		visual.pivot_offset = visual.size * 0.5
		var tween: Tween = _track(create_tween().set_parallel(true))
		tween.tween_property(visual, "scale", Vector2(0.25, 0.25), DEFEAT_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "modulate:a", 0.0, DEFEAT_DURATION)


func _start_drops() -> void:
	phase = "drops"
	for index: int in range(_drops.size()):
		var drop: Dictionary = _drops[index]
		var item: Dictionary = drop.item
		var definition: Dictionary = _definitions.get(str(item.get("id", "")), {})
		var visual := ITEM_SCENE.instantiate() as GridItem
		add_child(visual)
		visual.setup({"type": Constants.ItemType.REGULAR, "icon": "res://assets/ui/secret_realm/%s.svg" % definition.get("chain", "sword"), "immovable": item.get("immovable", false)}, Vector2i.ZERO, Constants.CELL_STEP)
		visual.level_label.text = str(int(definition.get("level", 1)))
		visual.level_label.add_theme_color_override("font_color", Color.BLACK)
		visual.level_label.show()
		visual.set_meta("drop_uid", item.get("uid", 0))
		drop_visuals.append(visual)
		var start: Vector2 = _origin - Vector2.ONE * Constants.CELL_SIZE * 0.5
		var destination: Vector2 = drop.destination
		visual.position = start
		visual.scale = Vector2(0.25, 0.25)
		visual.modulate.a = 0.0
		var tween: Tween = _track(create_tween().set_speed_scale(DROP_SPEED))
		tween.tween_interval(minf(index * 0.035, 0.14))
		tween.tween_property(visual, "modulate:a", 1.0, 0.04)
		tween.tween_method(_move_arc.bind(visual, start, destination, 40.0 + (index % 3) * 12.0), 0.0, 1.0, 0.32)
		tween.parallel().tween_property(visual, "scale", Vector2.ONE * (0.5 if drop.get("stash", false) else 1.0), 0.32)
		if drop.get("stash", false):
			tween.tween_property(visual, "modulate:a", 0.0, 0.12)
		else:
			tween.tween_property(visual, "scale", Vector2(1.12, 1.12), 0.07)
			tween.tween_property(visual, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _move_arc(progress: float, visual: Control, start: Vector2, destination: Vector2, height: float) -> void:
	if is_instance_valid(visual):
		visual.position = start.lerp(destination, progress) + Vector2(0.0, -4.0 * height * progress * (1.0 - progress))


func _finish() -> void:
	phase = "finished"
	# Retain landed visuals on the outgoing rows until the Boss scroll completes.
	for index: int in range(drop_visuals.size()):
		var cell: Control = _drops[index].get("cell")
		if is_instance_valid(cell) and not _drops[index].get("stash", false):
			var visual: GridItem = drop_visuals[index]
			visual.reparent(cell)
			visual.position = Vector2.ZERO
			visual.scale = Vector2.ONE
			cell.item_visual = visual
	finished.emit()


func cancel() -> void:
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()


func _exit_tree() -> void:
	cancel()
