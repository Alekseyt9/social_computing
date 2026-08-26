extends SceneTree

const PopulationScript := preload("res://agents/light_population_simulation.gd")


func _init() -> void:
	var population := PopulationScript.new(626262, 4096)
	var control := PopulationScript.new(626262, 4096)
	var before: Dictionary = population.snapshot()
	var gpu_shadow: Dictionary = population.run_ms6_feedback_batch(true)
	var cpu_only: Dictionary = control.run_ms6_feedback_batch(false)
	if not gpu_shadow.ok or not cpu_only.ok:
		_fail("Live packed-store feedback batch failed")
		return
	var after: Dictionary = population.snapshot()
	var control_after: Dictionary = control.snapshot()
	if int(after.storage.scalar_columns) != 11 or int(after.storage.dictionary_records) != 0:
		_fail("MS6 fields are not stored as packed scalar columns")
		return
	if before.feedback == after.feedback:
		_fail("Live LightAgent feedback fields did not evolve")
		return
	if after.feedback != control_after.feedback:
		_fail("GPU shadow path changed canonical CPU feedback state")
		return
	if int(before.total_money_cents) != int(after.total_money_cents) or not bool(after.money_conserved):
		_fail("MS6 feedback operator violated money conservation")
		return
	if str(gpu_shadow.status) not in ["GPU_SHADOW_VERIFIED", "CPU_FALLBACK"]:
		_fail("Unexpected MS6 backend status: %s" % str(gpu_shadow.status))
		return
	if str(gpu_shadow.status) == "GPU_SHADOW_VERIFIED" and float(gpu_shadow.max_error) > 0.00001:
		population.close_ms6_backend()
		control.close_ms6_backend()
		_fail("Live GPU buffer exceeded parity tolerance")
		return
	var saw_summary_only := false
	for _day in range(7):
		gpu_shadow = population.run_ms6_feedback_batch(true)
		cpu_only = control.run_ms6_feedback_batch(false)
		if str(gpu_shadow.status) == "GPU_SHADOW_SUMMARY":
			saw_summary_only = true
	after = population.snapshot()
	control_after = control.snapshot()
	if after.feedback != control_after.feedback:
		population.close_ms6_backend()
		control.close_ms6_backend()
		_fail("Periodic shadow mode changed canonical CPU state")
		return
	var backend_metrics: Dictionary = population.get_ms6_metrics().gpu_backend
	if str(gpu_shadow.status) == "GPU_SHADOW_VERIFIED":
		if not saw_summary_only:
			population.close_ms6_backend()
			control.close_ms6_backend()
			_fail("Live GPU path did not exercise compact summary readback")
			return
		if (
			int(backend_metrics.device_initializations) != 1
			or int(backend_metrics.buffer_reallocations) != 1
			or int(backend_metrics.dispatch_count) != 8
			or int(backend_metrics.full_readbacks) != 2
		):
			population.close_ms6_backend()
			control.close_ms6_backend()
			_fail("Live GPU resources were not persistent: %s" % JSON.stringify(backend_metrics))
			return
	print((
		"MILESTONE6_LIVE_OK agents=4096 status=%s max_error=%.8f packed_columns=11 "
		+ "canonical=CPU money_conserved=true dispatches=%d full_readbacks=%d"
	) % [
		str(gpu_shadow.status), float(gpu_shadow.max_error),
		int(backend_metrics.dispatch_count), int(backend_metrics.full_readbacks),
	])
	population.close_ms6_backend()
	control.close_ms6_backend()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
