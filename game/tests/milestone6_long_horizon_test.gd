extends SceneTree

const PopulationScript := preload("res://agents/light_population_simulation.gd")
const DAY_TICKS := 288
const DAYS := 30


func _init() -> void:
	var gpu_population := PopulationScript.new(676767, 1200)
	var cpu_population := PopulationScript.new(676767, 1200)
	cpu_population.set_ms6_gpu_enabled(false)
	var started_usec := Time.get_ticks_usec()
	for day in range(DAYS):
		gpu_population.advance(DAY_TICKS)
		cpu_population.advance(DAY_TICKS)
		var gpu_snapshot: Dictionary = gpu_population.snapshot()
		var cpu_snapshot: Dictionary = cpu_population.snapshot()
		if gpu_snapshot != cpu_snapshot:
			gpu_population.close_ms6_backend()
			cpu_population.close_ms6_backend()
			_fail("CPU canonical state diverged on day %d" % (day + 1))
			return
		if not bool(gpu_snapshot.money_conserved):
			gpu_population.close_ms6_backend()
			cpu_population.close_ms6_backend()
			_fail("Money conservation failed on day %d" % (day + 1))
			return
	var metrics: Dictionary = gpu_population.get_ms6_metrics()
	var backend: Dictionary = metrics.gpu_backend
	var cohorts: Dictionary = metrics.cohorts
	var cohort_backend: Dictionary = cohorts.backend
	if int(metrics.update_count) != DAYS:
		gpu_population.close_ms6_backend()
		cpu_population.close_ms6_backend()
		_fail("Expected one MS6 update per day")
		return
	if int(cohorts.update_count) != DAYS or int(cohorts.active_cohorts) <= 0:
		gpu_population.close_ms6_backend()
		cpu_population.close_ms6_backend()
		_fail("Expected one cohort reduction per day")
		return
	if bool(backend.persistent_device):
		if (
			int(backend.device_initializations) != 1 or int(backend.buffer_reallocations) != 1
			or int(backend.dispatch_count) != DAYS or int(backend.full_readbacks) != 5
			or float(metrics.max_error) > 0.00001
		):
			gpu_population.close_ms6_backend()
			cpu_population.close_ms6_backend()
			_fail("Unexpected 30-day GPU metrics: %s" % JSON.stringify(metrics))
			return
	if bool(cohort_backend.persistent_device) and (
		int(cohort_backend.device_initializations) != 1
		or int(cohort_backend.buffer_reallocations) != 1
		or int(cohort_backend.dispatch_count) != DAYS
		or float(cohorts.max_error) > 0.00001
	):
		gpu_population.close_ms6_backend()
		cpu_population.close_ms6_backend()
		_fail("Unexpected 30-day cohort metrics: %s" % JSON.stringify(cohorts))
		return
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	print((
		"MILESTONE6_LONG_HORIZON_OK days=%d agents=1200 status=%s dispatches=%d "
		+ "full_readbacks=%d cohort_dispatches=%d money_conserved=true deterministic=true elapsed_ms=%.2f"
	) % [
		DAYS, str(metrics.status), int(backend.dispatch_count),
		int(backend.full_readbacks), int(cohort_backend.dispatch_count),
		float(elapsed_usec) / 1000.0,
	])
	gpu_population.close_ms6_backend()
	cpu_population.close_ms6_backend()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
