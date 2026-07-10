extends Node

# SceneTransitionManager: Scene loading with loading overlay.
# Delegates loading display to LoadingManager.
# Usage:
#   SceneTransitionManager.load_scene_and_replace("res://scenes/screens/GameScreen.tscn")

const MIN_DISPLAY_TIME: float = 0.5

var _is_loading: bool = false
var _after_load: Callable = Callable()
var _target_transition: UIManager.Transition = UIManager.Transition.FADE
var _target_scene: PackedScene = null


func load_scene_and_replace(scene_path: String, transition: UIManager.Transition = UIManager.Transition.FADE, after_load: Callable = Callable()) -> void:
	if _is_loading:
		return

	_is_loading = true
	_target_transition = transition
	_after_load = after_load

	var token := LoadingManager.begin("加载场景...")

	_target_scene = load(scene_path)
	if _target_scene == null:
		printerr("[SceneTransitionManager] Failed to load: ", scene_path)
		_is_loading = false
		LoadingManager.end(token)
		return

	var screen := _target_scene.instantiate()
	if _after_load.is_valid():
		UIManager.post_screen_changed.connect(
			func(_name: String, _action: String): _after_load.call(),
			CONNECT_ONE_SHOT
		)
	UIManager.replace_top_screen(screen, _target_transition)

	# Hold loading for min display time, then release
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = MIN_DISPLAY_TIME
	timer.timeout.connect(func():
		timer.queue_free()
		LoadingManager.end(token)
		_is_loading = false
	)
	add_child(timer)
	timer.start()
