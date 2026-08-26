extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const SAMPLE_TICKS := 300


func _init() -> void:
	var world := SimulationWorldScript.new(20250308)
	var reference := SimulationWorldScript.new(20250308)
	world.advance(1, false)
	reference.advance(1)
	var started := Time.get_ticks_usec()
	var maximum_tick_usec := 0
	var maximum_tick := 0
	for _index in range(SAMPLE_TICKS):
		var tick_started := Time.get_ticks_usec()
		world.advance(1, false)
		var tick_usec := Time.get_ticks_usec() - tick_started
		if tick_usec > maximum_tick_usec:
			maximum_tick_usec = tick_usec
			maximum_tick = int(world.tick)
	var elapsed_usec := Time.get_ticks_usec() - started
	reference.advance(SAMPLE_TICKS)
	var actual := world.snapshot()
	var expected := reference.snapshot()
	if actual != expected:
		push_error("Fast runtime advance diverged from canonical advance")
		quit(1)
		return
	var average_ms := float(elapsed_usec) / 1000.0 / float(SAMPLE_TICKS)
	var maximum_ms := float(maximum_tick_usec) / 1000.0
	if average_ms > 20.0 or maximum_ms > 250.0:
		push_error("Runtime tick exceeded budget: average=%.2f ms max=%.2f ms" % [average_ms, maximum_ms])
		quit(1)
		return
	print("RUNTIME_TICK_OK ticks=%d total_ms=%.2f average_ms=%.2f max_ms=%.2f max_tick=%d parity=true" % [
		SAMPLE_TICKS, float(elapsed_usec) / 1000.0,
		average_ms, maximum_ms, maximum_tick,
	])
	quit(0)
