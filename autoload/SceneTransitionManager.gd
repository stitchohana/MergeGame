extends Node

# SceneTransitionManager: Async scene loading with loading screen + transitions.
# Usage:
#   SceneTransitionManager.load_scene_and_replace("res://scenes/screens/GameScreen.tscn")
#   SceneTransitionManager.load_scene_and_replace("res://scenes/screens/GameScreen.tscn", UIManager.Transition.SLIDE_LEFT)

const MIN_DISPLAY_TIME: float = 0.5
const LOADING_FADE_DURATION: float = 0.25
const PROGRESS_LERP_SPEED: float = 5.0

var _loading_scene: PackedScene = null
var _loading_screen: LoadingScreen = null
var _is_loading: bool = false
var _target_scene_path: String = ""
var _target_transition: UIManager.Transition = UIManager.Transition.FADE
var _elapsed: float = 0.0
var _display_progress: float = 0.0
var _after_load: Callable = Callable()

func _ready() -> void:
	_loading_scene = preload("res://scenes/screens/LoadingScreen.tscn")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _process(delta: float) -> void:
	_elapsed += delta

	var status := ResourceLoader.load_threaded_get_status(_target_scene_path)
	var real_progress: float = 0.0

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			real_progress = _smooth_progress()
		ResourceLoader.THREAD_LOAD_LOADED:
			real_progress = 1.0
		_:
			printerr("[SceneTransitionManager] Load failed: ", _target_scene_path, " status=", status)
			_finish_loading(null)
			return

	# Smoothly lerp display progress toward real progress so bar animates visibly
	_display_progress = lerpf(_display_progress, real_progress, 1.0 - exp(-PROGRESS_LERP_SPEED * delta))
	# Snap at the very end to avoid infinite lerp tail
	if real_progress >= 1.0 and _display_progress > 0.99:
		_display_progress = 1.0

	_loading_screen.set_progress(_display_progress)

	if status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= MIN_DISPLAY_TIME and _display_progress >= 0.99:
		var resource := ResourceLoader.load_threaded_get(_target_scene_path)
		_finish_loading(resource)

func _smooth_progress() -> float:
	var progress: Array = []
	ResourceLoader.load_threaded_get_status(_target_scene_path, progress)
	if progress.size() >= 3:
		var stage_progress: float = float(progress[0])
		var stage: int = int(progress[1])
		var stage_count: int = int(progress[2])
		if stage_count > 0:
			return clampf((float(stage) + stage_progress) / float(stage_count), 0.05, 0.95)
		return clampf(stage_progress, 0.05, 0.95)
	return 0.5

func load_scene_and_replace(scene_path: String, transition: UIManager.Transition = UIManager.Transition.FADE, after_load: Callable = Callable()) -> void:
	if _is_loading:
		printerr("[SceneTransitionManager] Already loading, ignoring: ", scene_path)
		return

	_is_loading = true
	_target_scene_path = scene_path
	_target_transition = transition
	_after_load = after_load
	_elapsed = 0.0
	_display_progress = 0.0

	_show_loading_screen()

	var err := ResourceLoader.load_threaded_request(scene_path, "", true)
	if err != OK:
		printerr("[SceneTransitionManager] load_threaded_request failed: ", error_string(err))
		_finish_loading(null)
		return

	set_process(true)

func _show_loading_screen() -> void:
	_loading_screen = _loading_scene.instantiate()
	var layer := UIManager.get_layer(UIManager.Layer.LOADING)
	layer.add_child(_loading_screen)

	var tween := create_tween()
	tween.tween_property(_loading_screen, "modulate", Color.WHITE, LOADING_FADE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _finish_loading(resource: Resource) -> void:
	set_process(false)
	_is_loading = false

	if not _loading_screen or not is_instance_valid(_loading_screen):
		return

	var fade_out := create_tween()
	fade_out.tween_property(_loading_screen, "modulate", Color.TRANSPARENT, LOADING_FADE_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	fade_out.tween_callback(func():
		_remove_loading_screen()
		if resource:
			var new_screen: BaseScreen = resource.instantiate()
			if not new_screen is BaseScreen:
				printerr("[SceneTransitionManager] Loaded resource is not a BaseScreen: ", _target_scene_path)
				return
			if _after_load.is_valid():
				UIManager.post_screen_changed.connect(
					func(_name: String, _action: String): _after_load.call(),
					CONNECT_ONE_SHOT
				)
			UIManager.replace_top_screen(new_screen, _target_transition)
	)

func _remove_loading_screen() -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
		_loading_screen = null
