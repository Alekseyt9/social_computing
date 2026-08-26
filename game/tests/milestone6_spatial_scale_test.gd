extends SceneTree

const BackendScript := preload("res://ms6/spatial_neighborhood_backend.gd")
const SCALES := [1200, 10_000, 100_000]


func _init() -> void:
	var backend := BackendScript.new()
	var started_usec := Time.get_ticks_usec()
	var last_result: Dictionary = {}
	for agent_count in SCALES:
		var positions := _build_positions(agent_count)
		var gpu: Dictionary = backend.find_nearest(positions, {}, true)
		if str(gpu.backend) != "GPU":
			print("MILESTONE6_SPATIAL_SCALE_CPU_FALLBACK gpu_error=%s" % str(gpu.get("gpu_error", "none")))
			backend.close()
			quit(0)
			return
		if agent_count <= 10_000:
			var cpu: Dictionary = backend.find_nearest(positions, {}, false)
			if cpu.neighbors != gpu.neighbors:
				backend.close()
				_fail("Spatial scale parity failed at %d agents" % agent_count)
				return
		for index in range(gpu.neighbors.size()):
			var neighbor := int(gpu.neighbors[index])
			if neighbor < 0 or neighbor >= agent_count or neighbor == index:
				backend.close()
				_fail("Invalid neighbor at scale %d index %d" % [agent_count, index])
				return
		last_result = gpu
	var metrics: Dictionary = backend.get_metrics()
	if (
		int(metrics.device_initializations) != 1 or int(metrics.buffer_reallocations) != 3
		or int(metrics.dispatch_count) != SCALES.size()
	):
		backend.close()
		_fail("Unexpected spatial scale metrics: %s" % JSON.stringify(metrics))
		return
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	print((
		"MILESTONE6_SPATIAL_SCALE_OK scales=1200,10000,100000 device_inits=1 "
		+ "reallocations=3 dispatches=3 neighbors=%d checksum=%s elapsed_ms=%.2f"
	) % [
		int(last_result.neighbor_count), str(last_result.checksum),
		float(elapsed_usec) / 1000.0,
	])
	backend.close()
	quit(0)


func _build_positions(agent_count: int) -> PackedFloat32Array:
	var positions := PackedFloat32Array()
	positions.resize(agent_count * 2)
	for index in range(agent_count):
		positions[index * 2] = 20.0 + float(posmod(index * 1103, 2360))
		positions[index * 2 + 1] = 20.0 + float(posmod(index * 2017, 1410))
	return positions


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
