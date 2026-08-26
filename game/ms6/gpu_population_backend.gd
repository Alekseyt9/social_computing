class_name GpuPopulationBackend
extends RefCounted

const SHADER_PATH := "res://ms6/light_agent_feedback.glsl"
const VALUES_PER_AGENT := 4
const WORKGROUP_SIZE := 64


func run_feedback(
	agent_state: PackedFloat32Array,
	parameters: Dictionary,
	prefer_gpu: bool = true
) -> Dictionary:
	if agent_state.size() % VALUES_PER_AGENT != 0:
		return {"ok": false, "error": "INVALID_AGENT_BUFFER"}
	if prefer_gpu:
		var gpu_result := _run_gpu(agent_state, parameters)
		if bool(gpu_result.get("ok", false)):
			return gpu_result
		var fallback := _run_cpu(agent_state, parameters)
		fallback["backend"] = "CPU_FALLBACK"
		fallback["gpu_error"] = str(gpu_result.get("error", "GPU_UNAVAILABLE"))
		return fallback
	return _run_cpu(agent_state, parameters)


func _run_cpu(agent_state: PackedFloat32Array, parameters: Dictionary) -> Dictionary:
	var output := agent_state.duplicate()
	var stress_delta := float(parameters.get("stress_delta", 0.0))
	var wealth_delta := float(parameters.get("wealth_delta", 0.0))
	var spending_sensitivity := float(parameters.get("spending_sensitivity", 0.0))
	for offset in range(0, output.size(), VALUES_PER_AGENT):
		var wealth := float(output[offset])
		var stress := clampf(
			float(output[offset + 1]) + stress_delta * (1.0 - wealth), 0.0, 1.0
		)
		var spending := clampf(
			float(output[offset + 2]) * (1.0 - stress * spending_sensitivity)
			+ wealth_delta * 0.1,
			0.0, 1.0
		)
		wealth = clampf(wealth + wealth_delta - spending * 0.002, 0.0, 1.0)
		var activity := clampf(
			float(output[offset + 3]) + (spending - 0.5) * 0.01, 0.0, 1.0
		)
		output[offset] = wealth
		output[offset + 1] = stress
		output[offset + 2] = spending
		output[offset + 3] = activity
	return {"ok": true, "backend": "CPU", "values": output}


func _run_gpu(agent_state: PackedFloat32Array, parameters: Dictionary) -> Dictionary:
	var rendering_device := RenderingServer.create_local_rendering_device()
	if rendering_device == null:
		return {"ok": false, "error": "LOCAL_RENDERING_DEVICE_UNAVAILABLE"}
	var shader_file := load(SHADER_PATH) as RDShaderFile
	if shader_file == null:
		rendering_device.free()
		return {"ok": false, "error": "COMPUTE_SHADER_NOT_LOADED"}
	var shader_rid := rendering_device.shader_create_from_spirv(shader_file.get_spirv())
	if not shader_rid.is_valid():
		rendering_device.free()
		return {"ok": false, "error": "COMPUTE_SHADER_CREATION_FAILED"}
	var state_buffer := rendering_device.storage_buffer_create(
		agent_state.size() * 4, agent_state.to_byte_array()
	)
	var agent_count := int(agent_state.size() / VALUES_PER_AGENT)
	var parameter_values := PackedFloat32Array([
		float(agent_count),
		float(parameters.get("stress_delta", 0.0)),
		float(parameters.get("wealth_delta", 0.0)),
		float(parameters.get("spending_sensitivity", 0.0)),
	])
	var parameter_buffer := rendering_device.storage_buffer_create(
		parameter_values.size() * 4, parameter_values.to_byte_array()
	)
	var state_uniform := RDUniform.new()
	state_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	state_uniform.binding = 0
	state_uniform.add_id(state_buffer)
	var parameter_uniform := RDUniform.new()
	parameter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	parameter_uniform.binding = 1
	parameter_uniform.add_id(parameter_buffer)
	var uniform_set := rendering_device.uniform_set_create(
		[state_uniform, parameter_uniform], shader_rid, 0
	)
	var pipeline := rendering_device.compute_pipeline_create(shader_rid)
	var compute_list := rendering_device.compute_list_begin()
	rendering_device.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rendering_device.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rendering_device.compute_list_dispatch(
		compute_list, int(ceil(float(agent_count) / float(WORKGROUP_SIZE))), 1, 1
	)
	rendering_device.compute_list_end()
	rendering_device.submit()
	rendering_device.sync()
	var output := rendering_device.buffer_get_data(state_buffer).to_float32_array()
	rendering_device.free_rid(pipeline)
	rendering_device.free_rid(uniform_set)
	rendering_device.free_rid(parameter_buffer)
	rendering_device.free_rid(state_buffer)
	rendering_device.free_rid(shader_rid)
	rendering_device.free()
	return {"ok": true, "backend": "GPU", "values": output}
