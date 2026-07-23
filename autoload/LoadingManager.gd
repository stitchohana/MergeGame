extends Node

# LoadingManager: Ref-counted loading overlay.
# begin() / end() track async tasks. Progress = completed / total.
# Overlay auto-hides when all tasks complete.

var _loading_scene: PackedScene = null
var _loading_screen: Control = null
var _tokens: Array[int] = []  # pending token IDs
var _total: int = 0            # total begin() calls in current session
var _next_token: int = 1
var _progress_tween: Tween = null
var _current_progress: float = 0.0

func begin(message: String = "加载中") -> int:
	var token := _next_token
	_next_token += 1
	_tokens.append(token)
	_total += 1
	print("[LoadingMgr] begin token=", token, " msg=", message, " total_tokens=", _tokens.size())

	if _tokens.size() == 1 and _total == 1:
		_show()

	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.set_message(message)

	_update_progress()
	return token


func end(token: int) -> void:
	print("[LoadingMgr] end token=", token, " remaining=", _tokens.size() - 1)
	var idx := _tokens.find(token)
	if idx >= 0:
		_tokens.remove_at(idx)
	_update_progress()

	if _tokens.is_empty():
		print("[LoadingMgr] all tokens done, hiding loading")
		_hide()


func _show() -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		return
	if _loading_scene == null:
		_loading_scene = load("res://scenes/screens/LoadingScreen.tscn") as PackedScene
		if _loading_scene == null:
			push_error("[LoadingManager] Loading screen is unavailable")
			return

	_loading_screen = _loading_scene.instantiate()
	var layer := UIManager.get_layer(UIManager.Layer.LOADING)
	layer.add_child(_loading_screen)
	_current_progress = 0.0


func _hide() -> void:
	if not _loading_screen or not is_instance_valid(_loading_screen):
		return

	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()
	_loading_screen.hide()
	_loading_screen.queue_free()
	_loading_screen = null
	_progress_tween = null
	_total = 0
	_current_progress = 0.0


func _update_progress() -> void:
	if not _loading_screen or not is_instance_valid(_loading_screen):
		return
	if _total <= 0:
		return
	var target := float(_total - _tokens.size()) / float(_total)
	_animate_progress(target)


func _animate_progress(target: float) -> void:
	if target <= _current_progress:
		return
	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()
	_current_progress = target
	_progress_tween = create_tween()
	_progress_tween.tween_method(_set_progress_bar, _loading_screen.get_progress(), target, 0.3)


func _set_progress_bar(ratio: float) -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.set_progress(ratio)
