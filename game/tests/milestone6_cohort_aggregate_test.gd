extends SceneTree

const BackendScript := preload("res://ms6/cohort_aggregate_backend.gd")
const AGENT_COUNT := 100_000
const TOLERANCE := 0.00001


func _init() -> void:
	var fields := PackedFloat32Array()
	var codes := PackedInt32Array()
	fields.resize(AGENT_COUNT * 4)
	codes.resize(AGENT_COUNT)
	for index in range(AGENT_COUNT):
		var offset := index * 4
		fields[offset] = float((index * 17) % 101) / 100.0
		fields[offset + 1] = float((index * 31) % 97) / 96.0
		fields[offset + 2] = float((index * 43) % 89) / 88.0
		fields[offset + 3] = float((index * 59) % 83) / 82.0
		codes[index] = posmod(index * 7 + index / 13, 24)
	var backend := BackendScript.new()
	var cpu: Dictionary = backend.reduce(fields, codes, false)
	var preferred: Dictionary = backend.reduce(fields, codes, true)
	var maximum_error := _maximum_error(cpu.values, preferred.values)
	if maximum_error > TOLERANCE:
		backend.close()
		_fail("Cohort CPU/GPU parity failed: %.8f" % maximum_error)
		return
	if int(preferred.summary.agent_count) != AGENT_COUNT or int(preferred.active_cohorts) != 24:
		backend.close()
		_fail("Cohort reduction lost agents or cohorts")
		return
	var second: Dictionary = backend.reduce(fields, codes, true)
	var metrics: Dictionary = backend.get_metrics()
	if str(preferred.backend) == "GPU" and (
		int(metrics.device_initializations) != 1 or int(metrics.buffer_reallocations) != 1
		or int(metrics.dispatch_count) != 2 or int(metrics.downloaded_bytes) != 960
	):
		backend.close()
		_fail("Cohort GPU resources were not persistent or compact: %s" % JSON.stringify(metrics))
		return
	print((
		"MILESTONE6_COHORT_OK agents=%d cohorts=%d backend=%s max_error=%.8f "
		+ "dispatches=%d downloaded_bytes=%d checksum_count=%d"
	) % [
		AGENT_COUNT, int(preferred.active_cohorts), str(preferred.backend), maximum_error,
		int(metrics.dispatch_count), int(metrics.downloaded_bytes), int(second.summary.agent_count),
	])
	backend.close()
	quit(0)


func _maximum_error(left: PackedFloat32Array, right: PackedFloat32Array) -> float:
	if left.size() != right.size():
		return INF
	var maximum_error := 0.0
	for index in range(left.size()):
		var divisor := 1.0
		if index % 5 != 4:
			divisor = maxf(1.0, float(left[index - index % 5 + 4]))
		maximum_error = maxf(
			maximum_error, absf(float(left[index]) - float(right[index])) / divisor
		)
	return maximum_error


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
