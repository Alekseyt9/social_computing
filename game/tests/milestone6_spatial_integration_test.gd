extends SceneTree

const PopulationScript := preload("res://agents/light_population_simulation.gd")
const DAY_TICKS := 288
const DAYS := 7


func _init() -> void:
	var gpu_population := PopulationScript.new(686868, 1200)
	var cpu_population := PopulationScript.new(686868, 1200)
	cpu_population.set_ms6_gpu_enabled(false)
	for _day in range(DAYS):
		gpu_population.advance(DAY_TICKS)
		cpu_population.advance(DAY_TICKS)
	var gpu_snapshot: Dictionary = gpu_population.snapshot()
	var cpu_snapshot: Dictionary = cpu_population.snapshot()
	var spatial: Dictionary = gpu_population.get_ms6_spatial_metrics()
	var backend: Dictionary = spatial.backend
	if gpu_snapshot != cpu_snapshot:
		_close(gpu_population, cpu_population)
		_fail("Spatial GPU shadow changed canonical simulation state")
		return
	if (
		int(spatial.update_count) != DAYS * 2 or int(spatial.neighbor_count) < 1000
		or int(spatial.gossip_sources) <= 0 or int(spatial.mismatch_count) != 0
		or not bool(gpu_snapshot.money_conserved)
	):
		_close(gpu_population, cpu_population)
		_fail("Spatial neighborhood was not integrated into gossip: %s" % JSON.stringify(spatial))
		return
	if bool(backend.persistent_device) and (
		int(backend.device_initializations) != 1 or int(backend.buffer_reallocations) != 1
		or int(backend.dispatch_count) != DAYS * 2
	):
		_close(gpu_population, cpu_population)
		_fail("Live spatial GPU resources were not persistent: %s" % JSON.stringify(backend))
		return
	print((
		"MILESTONE6_SPATIAL_INTEGRATION_OK days=%d agents=1200 status=%s "
		+ "neighbors=%d physical_gossip=%d dispatches=%d deterministic=true money_conserved=true"
	) % [
		DAYS, str(spatial.status), int(spatial.neighbor_count),
		int(spatial.gossip_sources), int(backend.dispatch_count),
	])
	_close(gpu_population, cpu_population)
	quit(0)


func _close(first: RefCounted, second: RefCounted) -> void:
	first.close_ms6_backend()
	second.close_ms6_backend()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
