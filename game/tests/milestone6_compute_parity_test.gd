extends SceneTree

const BackendScript := preload("res://ms6/gpu_population_backend.gd")


func _init() -> void:
	var input := PackedFloat32Array()
	for index in range(4096):
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
	var cpu: Dictionary = backend.run_feedback(input, parameters, false)
	var preferred: Dictionary = backend.run_feedback(input, parameters, true)
	if not cpu.ok or not preferred.ok or preferred.values.size() != cpu.values.size():
		_fail("MS6 backend could not produce matching buffers")
		return
	var maximum_error := 0.0
	for index in range(cpu.values.size()):
		maximum_error = maxf(maximum_error, absf(float(cpu.values[index]) - float(preferred.values[index])))
	if maximum_error > 0.00001:
		backend.close()
		_fail("GPU/CPU parity error is too large: %.8f" % maximum_error)
		return
	print("MILESTONE6_COMPUTE_OK agents=4096 backend=%s max_error=%.8f fallback=%s gpu_error=%s" % [
		str(preferred.backend), maximum_error, str(preferred.backend != "GPU"),
		str(preferred.get("gpu_error", "none")),
	])
	backend.close()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
