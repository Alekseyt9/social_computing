extends SceneTree

const BackendScript := preload("res://ms6/gpu_population_backend.gd")
const AGENT_COUNT := 8192
const TOLERANCE := 0.00001


func _init() -> void:
	var input := PackedFloat32Array()
	for index in range(AGENT_COUNT):
		input.append(float((index * 17) % 101) / 100.0)
		input.append(float((index * 31) % 97) / 96.0)
		input.append(float((index * 43) % 89) / 88.0)
		input.append(float((index * 59) % 83) / 82.0)
	var parameters := {
		"stress_delta": 0.035,
		"wealth_delta": -0.012,
		"spending_sensitivity": 0.18,
	}
	var backend := BackendScript.new()
	var cpu_first: Dictionary = backend.run_feedback(input, parameters, false)
	var gpu_first: Dictionary = backend.run_feedback(input, parameters, true, true)
	if str(gpu_first.backend) != "GPU":
		print("MILESTONE6_PERSISTENT_CPU_FALLBACK gpu_error=%s" % str(gpu_first.get("gpu_error", "none")))
		backend.close()
		quit(0)
		return
	if _maximum_buffer_error(cpu_first.values, gpu_first.values) > TOLERANCE:
		backend.close()
		_fail("Initial persistent GPU dispatch failed parity")
		return

	var second_input: PackedFloat32Array = cpu_first.values.duplicate()
	var changed_agent := 173
	var changed_offset := changed_agent * 4
	second_input[changed_offset + 1] = 0.91
	second_input[changed_offset + 3] = 0.12
	var partial_values := PackedFloat32Array()
	for field_index in range(4):
		partial_values.append(second_input[changed_offset + field_index])
	var cpu_second: Dictionary = backend.run_feedback(second_input, parameters, false)
	var gpu_second: Dictionary = backend.run_feedback(
		second_input,
		parameters,
		true,
		false,
		{"start_agent": changed_agent, "agent_count": 1, "values": partial_values}
	)
	if not gpu_second.values.is_empty() or int(gpu_second.uploaded_agent_count) != 1:
		backend.close()
		_fail("Summary dispatch unexpectedly read the full buffer or ignored the dirty range")
		return
	if _maximum_summary_error(cpu_second.summary, gpu_second.summary) > TOLERANCE:
		backend.close()
		_fail("Reduced GPU summary failed CPU parity")
		return

	var cpu_third: Dictionary = backend.run_feedback(cpu_second.values, parameters, false)
	var gpu_third: Dictionary = backend.run_feedback(cpu_second.values, parameters, true, true)
	var final_error := _maximum_buffer_error(cpu_third.values, gpu_third.values)
	var metrics: Dictionary = backend.get_metrics()
	if final_error > TOLERANCE:
		backend.close()
		_fail("Final full parity dispatch failed")
		return
	if (
		int(metrics.device_initializations) != 1 or int(metrics.buffer_reallocations) != 1
		or int(metrics.dispatch_count) != 3 or int(metrics.full_readbacks) != 2
		or int(metrics.summary_readbacks) != 3
	):
		backend.close()
		_fail("GPU resources were not reused: %s" % JSON.stringify(metrics))
		return
	var full_transfer_bytes := AGENT_COUNT * 4 * 4
	if int(metrics.downloaded_bytes) >= full_transfer_bytes * 3:
		backend.close()
		_fail("Summary reduction did not reduce GPU readback volume")
		return
	print((
		"MILESTONE6_PERSISTENT_OK agents=%d dispatches=3 device_inits=1 reallocations=1 "
		+ "full_readbacks=2 partial_upload_agents=1 downloaded_bytes=%d max_error=%.8f"
	) % [AGENT_COUNT, int(metrics.downloaded_bytes), final_error])
	backend.close()
	quit(0)


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
