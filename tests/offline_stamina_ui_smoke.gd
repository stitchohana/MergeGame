extends Node


func _ready() -> void:
	await get_tree().process_frame
	CloudService.online = false
	GameState.stamina = 60
	GameState.max_stamina = 100
	GameState.regen_remaining_ms = 1000.0
	var bar: TopBar = preload("res://scenes/ui/common/TopBar.tscn").instantiate() as TopBar
	add_child(bar)
	bar.set_process(false)
	bar._process(1.1)
	assert(GameState.stamina == 60, "timer expiry must not grant unsaved stamina")
	assert(bar._regen_sync_due)
	bar._process(600.0)
	assert(GameState.stamina == 60, "offline display waits for authoritative catch-up")
	CloudService._dispatch_response("stamina_refresh", {"ok": true, "stamina": 65,
		"max_stamina": 100, "regen_remaining_ms": 60000, "storage_revision": 10})
	assert(GameState.stamina == 65)
	assert(is_equal_approx(bar._regen_remaining, 60.0))
	assert(not bar._regen_sync_due)
	bar._process(60.1)
	assert(GameState.stamina == 65)
	CloudService._dispatch_response("stamina_refresh", {"ok": true, "stamina": 66,
		"max_stamina": 100, "regen_remaining_ms": 120000, "storage_revision": 11})
	assert(GameState.stamina == 66)
	# A stale response must not remove a subsequently recovered point.
	CloudService._dispatch_response("stamina_refresh", {"ok": true, "stamina": 65,
		"max_stamina": 100, "regen_remaining_ms": 60000, "storage_revision": 10})
	assert(GameState.stamina == 66)
	# Simulate a fresh login using the saved, server-settled balance and remainder.
	SaveManager._restore_from_server({"stamina": 66, "max_stamina": 100, "regen_remaining_ms": 120000})
	assert(GameState.stamina == 66)
	assert(is_equal_approx(bar._regen_remaining, 120.0))
	CloudService._dispatch_response("stamina_refresh", {"ok": true, "stamina": 100,
		"max_stamina": 100, "regen_remaining_ms": 0, "storage_revision": 12})
	bar._process(600.0)
	assert(GameState.stamina == 100)
	assert(is_zero_approx(bar._regen_remaining))
	print("OFFLINE_STAMINA_UI_SMOKE_OK no_local_grant server_sync remainder relogin stale cap")
	get_tree().quit()
