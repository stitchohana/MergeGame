extends "res://tests/secret_realm_ui_smoke.gd"

var _clicks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	GridManager.init_grid()
	GridManager.populate_from_server([
		{"id":1001,"uid":990001,"col":0,"row":0},
		{"id":1001,"uid":990002,"col":1,"row":0},
		{"id":1001,"uid":990003,"col":2,"row":0,"immovable":true},
	])
	CultivationService.current_level = 20
	var grid := preload("res://scenes/grid/GridView.tscn").instantiate() as GridView
	# Headless Viewport mouse polling remains at the origin for pushed events.
	grid.position = Vector2.ZERO
	grid.scale = Vector2.ONE * Constants.BOARD_DISPLAY_SCALE
	UIManager.get_layer(UIManager.Layer.GAME).add_child(grid)
	grid.item_clicked.connect(func(_item: Dictionary, _pos: Vector2i) -> void: _clicks += 1)
	await get_tree().process_frame
	var visual: GridItem = grid._item_nodes["0,0"]
	var start: Vector2 = visual.get_global_rect().get_center()
	# Click jitter below the shared logical threshold must remain a click.
	_mouse_button(start,true)
	_mouse_move(start+Vector2(5,0),Vector2(5,0))
	_mouse_button(start+Vector2(5,0),false)
	assert(_clicks==1 and not grid._is_dragging)
	# Above threshold starts the main board's drag; a second motion follows.
	_mouse_button(start,true)
	_mouse_move(start+Vector2(20,0),Vector2(20,0))
	assert(grid._is_dragging)
	var outside: Vector2 = grid.global_position-Vector2(20,20)
	_mouse_move(outside,outside-start-Vector2(20,0))
	var expected: Vector2 = grid.get_global_transform_with_canvas().affine_inverse()*outside-Vector2.ONE*Constants.CELL_STEP*0.5
	assert(visual.position.is_equal_approx(expected))
	_mouse_button(outside,false)
	assert(not grid._is_dragging and _clicks==1)
	await get_tree().create_timer(Constants.SNAP_BACK_DURATION+0.05).timeout
	assert(visual.position.is_equal_approx(Vector2.ZERO))
	# Fixed items never become drag sources under the shared gesture handling.
	var fixed: GridItem = grid._item_nodes["2,0"]
	start = fixed.get_global_rect().get_center()
	_mouse_button(start,true)
	_mouse_move(start+Vector2(20,0),Vector2(20,0))
	assert(not grid._is_dragging)
	_mouse_button(start+Vector2(20,0),false)
	assert(_clicks==1)
	# A real pointer drop still reaches the original main-board batch transaction.
	start = visual.get_global_rect().get_center()
	var target: GridItem = grid._item_nodes["1,0"]
	var finish: Vector2 = target.get_global_rect().get_center()
	_mouse_button(start,true)
	_mouse_move(start+Vector2(20,0),Vector2(20,0))
	_mouse_move(finish,finish-start-Vector2(20,0))
	_mouse_button(finish,false)
	assert(GridManager.get_item(Vector2i.ZERO)==null)
	assert(int(GridManager.get_item(Vector2i(1,0)).id)==1002)
	assert(grid._pending_spawn_actions.size()==1)
	assert(grid._pending_spawn_actions[0].operation.type=="merge")
	# Hold the deferred offline batch; this test checks input and routing only.
	grid._pending_spawn_actions.clear()
	grid.queue_free()
	await get_tree().process_frame
	print("BOARD_DRAG_REUSE_SMOKE_OK: main pointer click threshold follow snap fixed merge")
	get_tree().quit()
