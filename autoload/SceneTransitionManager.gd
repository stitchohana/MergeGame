extends Node

# SceneTransitionManager: Scene loading with loading screen + transitions.
# Usage:
#   SceneTransitionManager.load_scene_and_replace("res://scenes/screens/GameScreen.tscn")

const MIN_DISPLAY_TIME: float = 0.5
const LOADING_FADE_DURATION: float = 0.25
const PROGRESS_LERP_SPEED: float = 5.0

var _loading_scene: PackedScene = null
var _loading_screen: LoadingScreen = null
var _is_loading: bool = false
var _after_load: Callable = Callable()
var _target_transition: UIManager.Transition = UIManager.Transition.FADE
var _target_scene: PackedScene = null
var _display_progress: float = 0.0
var _start_ms: int = 0

func _ready() -> void:
	_loading_scene = preload("res://scenes/screens/LoadingScreen.tscn")
	set_process(false)

func _process(_delta: float) -> void:
	var elapsed_ms := Time.get_ticks_msec() - _start_ms
	_display_progress = lerpf(_display_progress, 1.0, 1.0 - exp(-PROGRESS_LERP_SPEED * _delta))
	if _display_progress > 0.99:
		_display_progress = 1.0
	_loading_screen.set_progress(_display_progress)

	if elapsed_ms >= MIN_DISPLAY_TIME * 1000 and _display_progress >= 0.99:
		set_process(false)
		_finish_loading()

func load_scene_and_replace(scene_path: String, transition: UIManager.Transition = UIManager.Transition.FADE, after_load: Callable = Callable()) -> void:
	if _is_loading:
		return

	_is_loading = true
	_target_transition = transition
	_after_load = after_load
	_display_progress = 0.0
	_show_loading_screen()

	_target_scene = load(scene_path)
	if _target_scene == null:
		printerr("[SceneTransitionManager] Failed to load: ", scene_path)
		_is_loading = false
		_remove_loading_screen()
		return

	_start_ms = Time.get_ticks_msec()
	set_process(true)

func _show_loading_screen() -> void:
	_loading_screen = _loading_scene.instantiate()
	var layer := UIManager.get_layer(UIManager.Layer.LOADING)
	layer.add_child(_loading_screen)

	var tween := create_tween()
	tween.tween_property(_loading_screen, "modulate", Color.WHITE, LOADING_FADE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _finish_loading() -> void:
	_is_loading = false

	if not _loading_screen or not is_instance_valid(_loading_screen):
		return

	_loading_screen.set_progress(1.0)

	var fade_out := create_tween()
	fade_out.tween_property(_loading_screen, "modulate", Color.TRANSPARENT, LOADING_FADE_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	fade_out.tween_callback(func():
		_remove_loading_screen()
		if _target_scene:
			if _after_load.is_valid():
				UIManager.post_screen_changed.connect(
					func(_name: String, _action: String): _after_load.call(),
					CONNECT_ONE_SHOT
				)
			UIManager.replace_top_screen(_target_scene.instantiate(), _target_transition)
	)

func _remove_loading_screen() -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
		_loading_screen = null
