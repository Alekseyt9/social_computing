extends SceneTree

const BackendScript := preload("res://ms6/gpu_population_backend.gd")
const SCALES := [1200, 10_000, 100_000]
const SUMMARY_DAYS := 3
const TOLERANCE := 0.00001


func _init() -> void:
	var backend := BackendScript.new()
	var expected_naive_download_bytes := 0
	var maximum_error := 0.0
	var started_usec := Time.get_ticks_usec()
	for agent_count in SCALES:
		var canonical := _build_input(agent_count)
		var parameters := {
			"stress_delta": 0.021,
			"wealth_delta": -0.006,
			"spending_sensitivity": 0.14,
		}
		var cpu: Dictionary = backend.run_feedback(canonical, parameters, false)
		var gpu: Dictionary = backend.run_feedback(canonical, parameters, true, true)
		if str(gpu.backend) != "GPU":
			print("MILESTONE6_SCALE_CPU_FALLBACK gpu_error=%s" % str(gpu.get("gpu_error", "none")))
			backend.close()
			quit(0)
			return
		maximum_error = maxf(maximum_error, _maximum_buffer_error(cpu.values, gpu.values))
		expected_naive_download_bytes += canonical.size() * 4
		canonical = cpu.values
		for _day in range(SUMMARY_DAYS):
			cpu = backend.run_feedback(canonical, parameters, false)
			gpu = backend.run_feedback(
				canonical,
				parameters,
				true,
				false,
				{"start_agent": 0, "agent_count": 0, "values": PackedFloat32Array()}
			)
			maximum_error = maxf(
				maximum_error, _maximum_summary_error(cpu.summary, gpu.summary)
			)
			expected_naive_download_bytes += canonical.size() * 4
			canonical = cpu.values
		cpu = backend.run_feedback(canonical, parameters, false)
		gpu = backend.run_feedback(canonical, parameters, true, true)
		maximum_error = maxf(maximum_error, _maximum_buffer_error(cpu.values, gpu.values))
		expected_naive_download_bytes += canonical.size() * 4
	if maximum_error > TOLERANCE:
		backend.close()
		_fail("Scale transfer GPU/CPU parity exceeded tolerance: %.8f" % maximum_error)
		return
	var metrics: Dictionary = backend.get_metrics()
	var transfer_ratio := float(metrics.downloaded_bytes) / float(expected_naive_download_bytes)
	if (
		int(metrics.device_initializations) != 1 or int(metrics.buffer_reallocations) != 3
		or int(metrics.dispatch_count) != SCALES.size() * (SUMMARY_DAYS + 2)
		or int(metrics.full_readbacks) != SCALES.size() * 2
		or transfer_ratio >= 0.45
	):
		backend.close()
		_fail("Unexpected MS6 scale/transfer metrics: %s" % JSON.stringify(metrics))
		return
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	print((
		"MILESTONE6_SCALE_OK scales=1200,10000,100000 device_inits=1 reallocations=3 "
		+ "dispatches=%d full_readbacks=%d transfer_ratio=%.3f max_error=%.8f elapsed_ms=%.2f"
	) % [
		int(metrics.dispatch_count), int(metrics.full_readbacks), transfer_ratio,
		maximum_error, float(elapsed_usec) / 1000.0,
	])
	backend.close()
	quit(0)


func _build_input(agent_count: int) -> PackedFloat32Array:
	var input := PackedFloat32Array()
	input.resize(agent_count * 4)
	for index in range(agent_count):
		var offset := index * 4
		input[offset] = float((index * 17 + agent_count) % 101) / 100.0
		input[offset + 1] = float((index * 31 + 7) % 97) / 96.0
		input[offset + 2] = float((index * 43 + 11) % 89) / 88.0
		input[offset + 3] = float((index * 59 + 13) % 83) / 82.0
	return input


func _maximum_buffer_error(left: PackedFloat32Array, right: PackedFloat32Array) -> float:
	if left.size() != right.size():
		return INF
	var maximum_error := 0.0
	for index in range(left.size()):
		maximum_error = maxf(maximum_error, absf(float(left[index]) - float(right[index])))
	return maximum_error


func _maximum_summary_error(left: Dictionary, right: Dictionary) -> float:
	var maximum_error := 0.0
	for key in ["average_wealth", "average_stress", "average_spending", "average_activity"]:
		maximum_error = maxf(
			maximum_error, absf(float(left.get(key, 0.0)) - float(right.get(key, 0.0)))
		)
	return maximum_error


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
