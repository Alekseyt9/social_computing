extends SceneTree

const BackendScript := preload("res://ms6/spatial_neighborhood_backend.gd")
const AGENT_COUNT := 4096


func _init() -> void:
	var positions := _build_positions(AGENT_COUNT, 0)
	var backend := BackendScript.new()
	var cpu: Dictionary = backend.find_nearest(positions, {}, false)
	var preferred: Dictionary = backend.find_nearest(positions, {}, true)
	if not cpu.ok or not preferred.ok:
		backend.close()
		_fail("Spatial backend failed")
		return
	if cpu.neighbors != preferred.neighbors:
		backend.close()
		_fail("CPU/GPU spatial neighbors differ")
		return
	if int(cpu.neighbor_count) < int(AGENT_COUNT * 0.9):
		backend.close()
		_fail("Spatial test did not produce enough physical neighbors")
		return
	for index in range(cpu.neighbors.size()):
		if int(cpu.neighbors[index]) == index:
			backend.close()
			_fail("Spatial query selected the agent itself")
			return
	var second_positions := _build_positions(AGENT_COUNT, 17)
	var cpu_second: Dictionary = backend.find_nearest(second_positions, {}, false)
	var preferred_second: Dictionary = backend.find_nearest(second_positions, {}, true)
	if cpu_second.neighbors != preferred_second.neighbors:
		backend.close()
		_fail("Repeated spatial dispatch failed parity")
		return
	var metrics: Dictionary = backend.get_metrics()
	if str(preferred.backend) == "GPU" and (
		int(metrics.device_initializations) != 1 or int(metrics.buffer_reallocations) != 1
		or int(metrics.dispatch_count) != 2
	):
		backend.close()
		_fail("Spatial GPU resources were not persistent: %s" % JSON.stringify(metrics))
		return
	print((
		"MILESTONE6_SPATIAL_OK agents=%d backend=%s neighbors=%d checksum=%s "
		+ "dispatches=%d device_inits=%d reallocations=%d"
	) % [
		AGENT_COUNT, str(preferred.backend), int(preferred.neighbor_count),
		str(preferred.checksum), int(metrics.dispatch_count),
		int(metrics.device_initializations), int(metrics.buffer_reallocations),
	])
	backend.close()
	quit(0)


func _build_positions(agent_count: int, phase: int) -> PackedFloat32Array:
	var positions := PackedFloat32Array()
	positions.resize(agent_count * 2)
	for index in range(agent_count):
		positions[index * 2] = 24.0 + float(posmod(index * 1103 + phase * 31, 2350))
		positions[index * 2 + 1] = 24.0 + float(posmod(index * 2017 + phase * 47, 1400))
	return positions


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
