extends Node


func _ready() -> void:
	CloudService.online = false
	GameState.pending_auto_acupoint = false
	var home: HomeScreen = preload("res://scenes/screens/HomeScreen.tscn").instantiate() as HomeScreen
	add_child(home)
	await get_tree().process_frame
	var defs: Array = ConfigDatabase.get_home_meridian_stages().duplicate(true)
	for level: int in [5, 6]:
		var current_stages: Array[int] = []
		for index in range(defs.size()):
			if int(defs[index].get("cultivation_level", 0)) == level:
				current_stages.append(index)
		# Match the inspected five-complete/sixth-ready progress at layer five;
		# also check the last circulation of layer four at 127/128.
		var ready_stage: int = current_stages[5]
		var progress: Array = []
		for index in range(ready_stage + 1):
			var lit: Array = []
			lit.resize(int(defs[index].get("acupoints", 0)))
			lit.fill(true)
			progress.append({"stage": index, "lit": lit, "circulation_completed": index < ready_stage})
		var threshold: int = ConfigDatabase.get_stage_exp(level)
		var cultivation: Dictionary = {"current_level": level, "current_exp": threshold - 1,
			"total_exp": 638, "current_qi": 308, "max_qi": 10000}
		var response: Dictionary = {"cultivation": cultivation, "home_meridian_defs": defs,
			"home_meridian_progress": progress, "storage_revision": 100}
		home._on_state_loaded(response)
		assert(CultivationService.current_exp == threshold - 1)
		assert(home._current_stage_idx == ready_stage)
		assert(home.get_node("RunCirculationBtn").visible)
		assert(not home.get_node("BreakthroughBtn").visible)
		# A fresh authoritative response replaces EXP and progress together.
		progress[-1]["circulation_completed"] = true
		cultivation["current_exp"] = threshold
		response["storage_revision"] = 101
		home._on_state_loaded(response)
		assert(CultivationService.current_exp == threshold)
		assert(not home.get_node("RunCirculationBtn").visible)
		assert(home.get_node("BreakthroughBtn").visible)
	print("CULTIVATION_EXP_TRACE_UI_SMOKE_OK")
	home.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
