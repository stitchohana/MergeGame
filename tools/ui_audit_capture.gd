extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	print("[UIAudit] args=", args)
	if args.size() < 2:
		push_error("[UIAudit] Expected scene path and output path")
		quit(1)
		return
	var packed: PackedScene = load(args[0]) as PackedScene
	if packed == null:
		push_error("[UIAudit] Failed to load " + args[0])
		quit(1)
		return
	var scene: Node = packed.instantiate()
	_strip_scripts(scene)
	get_root().size = Vector2i(780, 1688)
	get_root().add_child(scene)
	if scene is Control:
		var control := scene as Control
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		control.show()
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image: Image = get_root().get_texture().get_image()
	var error: Error = image.save_png(args[1])
	print("[UIAudit] saved=", args[1], " size=", image.get_size(), " error=", error)
	quit(0 if error == OK else 1)


func _strip_scripts(node: Node) -> void:
	for child: Node in node.get_children():
		_strip_scripts(child)
	node.set_script(null)
