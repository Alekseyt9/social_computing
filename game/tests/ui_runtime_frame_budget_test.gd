extends SceneTree

const SAMPLE_TICKS := 24


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._start_new_game()
	scene.set_process(false)
	var maximum_usec := 0
	var maximum_tick := 0
	var total_usec := 0
	for _index in range(SAMPLE_TICKS):
		var started := Time.get_ticks_usec()
		scene._process(1.01)
		var elapsed := Time.get_ticks_usec() - started
		total_usec += elapsed
		if elapsed > maximum_usec:
			maximum_usec = elapsed
			maximum_tick = int(scene.world.tick)
	var average_ms := float(total_usec) / 1000.0 / float(SAMPLE_TICKS)
	var maximum_ms := float(maximum_usec) / 1000.0
	if average_ms > 12.0 or maximum_ms > 120.0:
		push_error("Playable UI tick exceeded budget: average=%.2f max=%.2f" % [
			average_ms, maximum_ms,
		])
		scene.queue_free()
		quit(1)
		return
	print("UI_RUNTIME_OK ticks=%d average_ms=%.2f max_ms=%.2f max_tick=%d" % [
		SAMPLE_TICKS, average_ms, maximum_ms, maximum_tick,
	])
	scene.queue_free()
	quit(0)
