class_name GpuPopulationBackend
extends RefCounted

const FEEDBACK_SHADER_PATH := "res://ms6/light_agent_feedback.glsl"
const REDUCTION_SHADER_PATH := "res://ms6/light_agent_reduce.glsl"
const VALUES_PER_AGENT := 4
const WORKGROUP_SIZE := 64
const BYTES_PER_FLOAT := 4
const PARAMETER_BYTES := 4 * BYTES_PER_FLOAT
const PARTIAL_BYTES_PER_GROUP := 4 * BYTES_PER_FLOAT

var _rendering_device: RenderingDevice
var _feedback_shader := RID()
var _reduction_shader := RID()
var _feedback_pipeline := RID()
var _reduction_pipeline := RID()
var _state_buffer := RID()
var _parameter_buffer := RID()
var _partial_buffer := RID()
var _feedback_uniform_set := RID()
var _reduction_uniform_set := RID()
var _capacity_agents := 0
var _capacity_groups := 0
var _last_error := ""
var _device_initializations := 0
var _dispatch_count := 0
var _buffer_reallocations := 0
var _full_readbacks := 0
var _summary_readbacks := 0
var _uploaded_bytes := 0
var _downloaded_bytes := 0


func run_feedback(
	agent_state: PackedFloat32Array,
	parameters: Dictionary,
	prefer_gpu: bool = true,
	readback_values: bool = true,
	upload_range: Dictionary = {}
) -> Dictionary:
	if agent_state.size() % VALUES_PER_AGENT != 0:
		return {"ok": false, "error": "INVALID_AGENT_BUFFER"}
	if prefer_gpu:
		var gpu_result := _run_gpu(agent_state, parameters, readback_values, upload_range)
		if bool(gpu_result.get("ok", false)):
			return gpu_result
		var fallback := _run_cpu(agent_state, parameters)
		fallback["backend"] = "CPU_FALLBACK"
		fallback["gpu_error"] = str(gpu_result.get("error", "GPU_UNAVAILABLE"))
		return fallback
	return _run_cpu(agent_state, parameters)


func get_metrics() -> Dictionary:
	return {
		"persistent_device": _rendering_device != null,
		"device_initializations": _device_initializations,
		"dispatch_count": _dispatch_count,
		"buffer_reallocations": _buffer_reallocations,
		"full_readbacks": _full_readbacks,
		"summary_readbacks": _summary_readbacks,
		"uploaded_bytes": _uploaded_bytes,
		"downloaded_bytes": _downloaded_bytes,
		"capacity_agents": _capacity_agents,
		"last_error": _last_error,
	}


func close() -> void:
	_free_buffer_resources()
	if _rendering_device != null:
		_free_rid(_reduction_pipeline)
		_free_rid(_feedback_pipeline)
		_free_rid(_reduction_shader)
		_free_rid(_feedback_shader)
		_rendering_device.free()
	_rendering_device = null
	_feedback_shader = RID()
	_reduction_shader = RID()
	_feedback_pipeline = RID()
	_reduction_pipeline = RID()


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
	return {
		"ok": true,
		"backend": "CPU",
		"values": output,
		"summary": _summarize_values(output),
	}


func _run_gpu(
	agent_state: PackedFloat32Array,
	parameters: Dictionary,
	readback_values: bool,
	upload_range: Dictionary
) -> Dictionary:
	var agent_count := int(agent_state.size() / VALUES_PER_AGENT)
	if agent_count == 0:
		return {
			"ok": true,
			"backend": "GPU",
			"values": PackedFloat32Array(),
			"summary": _empty_summary(),
			"full_readback": readback_values,
		}
	var previous_capacity := _capacity_agents
	if not _ensure_gpu_resources(agent_count):
		return {"ok": false, "error": _last_error}
	var effective_upload_range := upload_range
	if previous_capacity == 0 or agent_count > previous_capacity:
		effective_upload_range = {}
	var uploads := _resolve_uploads(agent_state, effective_upload_range)
	var uploaded_agent_count := 0
	for upload: Dictionary in uploads:
		var upload_values: PackedFloat32Array = upload.values
		if upload_values.is_empty():
			continue
		var upload_bytes := upload_values.to_byte_array()
		var byte_offset := int(upload.start_agent) * VALUES_PER_AGENT * BYTES_PER_FLOAT
		_rendering_device.buffer_update(
			_state_buffer, byte_offset, upload_bytes.size(), upload_bytes
		)
		_uploaded_bytes += upload_bytes.size()
		uploaded_agent_count += int(upload.agent_count)
	var parameter_values := PackedFloat32Array([
		float(agent_count),
		float(parameters.get("stress_delta", 0.0)),
		float(parameters.get("wealth_delta", 0.0)),
		float(parameters.get("spending_sensitivity", 0.0)),
	])
	var parameter_bytes := parameter_values.to_byte_array()
	_rendering_device.buffer_update(_parameter_buffer, 0, parameter_bytes.size(), parameter_bytes)
	_uploaded_bytes += parameter_bytes.size()
	var workgroup_count := int(ceil(float(agent_count) / float(WORKGROUP_SIZE)))
	var compute_list := _rendering_device.compute_list_begin()
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _feedback_pipeline)
	_rendering_device.compute_list_bind_uniform_set(compute_list, _feedback_uniform_set, 0)
	_rendering_device.compute_list_dispatch(compute_list, workgroup_count, 1, 1)
	_rendering_device.compute_list_add_barrier(compute_list)
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _reduction_pipeline)
	_rendering_device.compute_list_bind_uniform_set(compute_list, _reduction_uniform_set, 0)
	_rendering_device.compute_list_dispatch(compute_list, workgroup_count, 1, 1)
	_rendering_device.compute_list_end()
	_rendering_device.submit()
	_rendering_device.sync()
	_dispatch_count += 1
	var partial_byte_count := workgroup_count * PARTIAL_BYTES_PER_GROUP
	var partial_bytes := _rendering_device.buffer_get_data(_partial_buffer, 0, partial_byte_count)
	_summary_readbacks += 1
	_downloaded_bytes += partial_bytes.size()
	var summary := _summarize_partials(partial_bytes.to_float32_array(), agent_count)
	var output := PackedFloat32Array()
	if readback_values:
		var output_bytes := _rendering_device.buffer_get_data(
			_state_buffer, 0, agent_state.size() * BYTES_PER_FLOAT
		)
		output = output_bytes.to_float32_array()
		_full_readbacks += 1
		_downloaded_bytes += output_bytes.size()
	return {
		"ok": true,
		"backend": "GPU",
		"values": output,
		"summary": summary,
		"full_readback": readback_values,
		"uploaded_agent_count": uploaded_agent_count,
		"upload_range_count": uploads.size(),
		"workgroup_count": workgroup_count,
	}


func _ensure_gpu_resources(agent_count: int) -> bool:
	if _rendering_device == null:
		if not _create_device_and_pipelines():
			return false
	if agent_count <= _capacity_agents and _state_buffer.is_valid():
		return true
	_free_buffer_resources()
	_capacity_agents = _next_power_of_two(agent_count)
	_capacity_groups = int(ceil(float(_capacity_agents) / float(WORKGROUP_SIZE)))
	_state_buffer = _rendering_device.storage_buffer_create(
		_capacity_agents * VALUES_PER_AGENT * BYTES_PER_FLOAT
	)
	_parameter_buffer = _rendering_device.storage_buffer_create(PARAMETER_BYTES)
	_partial_buffer = _rendering_device.storage_buffer_create(
		_capacity_groups * PARTIAL_BYTES_PER_GROUP
	)
	if (
		not _state_buffer.is_valid() or not _parameter_buffer.is_valid()
		or not _partial_buffer.is_valid()
	):
		_last_error = "COMPUTE_BUFFER_CREATION_FAILED"
		_free_buffer_resources()
		return false
	_feedback_uniform_set = _create_uniform_set(
		_feedback_shader, [_storage_uniform(0, _state_buffer), _storage_uniform(1, _parameter_buffer)]
	)
	_reduction_uniform_set = _create_uniform_set(
		_reduction_shader,
		[
			_storage_uniform(0, _state_buffer),
			_storage_uniform(1, _parameter_buffer),
			_storage_uniform(2, _partial_buffer),
		]
	)
	if not _feedback_uniform_set.is_valid() or not _reduction_uniform_set.is_valid():
		_last_error = "COMPUTE_UNIFORM_SET_CREATION_FAILED"
		_free_buffer_resources()
		return false
	_buffer_reallocations += 1
	return true


func _create_device_and_pipelines() -> bool:
	_rendering_device = RenderingServer.create_local_rendering_device()
	if _rendering_device == null:
		_last_error = "LOCAL_RENDERING_DEVICE_UNAVAILABLE"
		return false
	_device_initializations += 1
	var feedback_file := load(FEEDBACK_SHADER_PATH) as RDShaderFile
	var reduction_file := load(REDUCTION_SHADER_PATH) as RDShaderFile
	if feedback_file == null or reduction_file == null:
		_last_error = "COMPUTE_SHADER_NOT_LOADED"
		close()
		return false
	_feedback_shader = _rendering_device.shader_create_from_spirv(feedback_file.get_spirv())
	_reduction_shader = _rendering_device.shader_create_from_spirv(reduction_file.get_spirv())
	if not _feedback_shader.is_valid() or not _reduction_shader.is_valid():
		_last_error = "COMPUTE_SHADER_CREATION_FAILED"
		close()
		return false
	_feedback_pipeline = _rendering_device.compute_pipeline_create(_feedback_shader)
	_reduction_pipeline = _rendering_device.compute_pipeline_create(_reduction_shader)
	if not _feedback_pipeline.is_valid() or not _reduction_pipeline.is_valid():
		_last_error = "COMPUTE_PIPELINE_CREATION_FAILED"
		close()
		return false
	_last_error = ""
	return true


func _resolve_uploads(agent_state: PackedFloat32Array, upload_range: Dictionary) -> Array[Dictionary]:
	if upload_range.is_empty():
		return [{
			"start_agent": 0,
			"agent_count": int(agent_state.size() / VALUES_PER_AGENT),
			"values": agent_state,
		}]
	if upload_range.has("ranges"):
		var resolved: Array[Dictionary] = []
		for value: Variant in upload_range.get("ranges", []):
			if value is Dictionary:
				resolved.append(_resolve_single_upload(agent_state, value))
		return resolved
	return [_resolve_single_upload(agent_state, upload_range)]


func _resolve_single_upload(agent_state: PackedFloat32Array, upload_range: Dictionary) -> Dictionary:
	var agent_count := int(agent_state.size() / VALUES_PER_AGENT)
	var start_agent := int(upload_range.get("start_agent", 0))
	var upload_values: PackedFloat32Array = upload_range.get("values", PackedFloat32Array())
	var count := int(upload_range.get("agent_count", upload_values.size() / VALUES_PER_AGENT))
	if (
		start_agent < 0 or count < 0 or start_agent + count > agent_count
		or upload_values.size() != count * VALUES_PER_AGENT
	):
		return {"start_agent": 0, "agent_count": agent_count, "values": agent_state}
	return {"start_agent": start_agent, "agent_count": count, "values": upload_values}


func _storage_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform


func _create_uniform_set(shader: RID, uniforms: Array[RDUniform]) -> RID:
	return _rendering_device.uniform_set_create(uniforms, shader, 0)


func _free_buffer_resources() -> void:
	if _rendering_device != null:
		_free_rid(_reduction_uniform_set)
		_free_rid(_feedback_uniform_set)
		_free_rid(_partial_buffer)
		_free_rid(_parameter_buffer)
		_free_rid(_state_buffer)
	_reduction_uniform_set = RID()
	_feedback_uniform_set = RID()
	_partial_buffer = RID()
	_parameter_buffer = RID()
	_state_buffer = RID()
	_capacity_agents = 0
	_capacity_groups = 0


func _free_rid(rid: RID) -> void:
	if _rendering_device != null and rid.is_valid():
		_rendering_device.free_rid(rid)


func _next_power_of_two(value: int) -> int:
	var result := 1
	while result < value:
		result <<= 1
	return result


func _summarize_values(values: PackedFloat32Array) -> Dictionary:
	var totals := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for offset in range(0, values.size(), VALUES_PER_AGENT):
		for field_index in range(VALUES_PER_AGENT):
			totals[field_index] += float(values[offset + field_index])
	return _summary_from_totals(totals, int(values.size() / VALUES_PER_AGENT))


func _summarize_partials(values: PackedFloat32Array, agent_count: int) -> Dictionary:
	var totals := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for offset in range(0, values.size(), VALUES_PER_AGENT):
		for field_index in range(VALUES_PER_AGENT):
			totals[field_index] += float(values[offset + field_index])
	return _summary_from_totals(totals, agent_count)


func _summary_from_totals(totals: PackedFloat64Array, agent_count: int) -> Dictionary:
	var divisor := float(maxi(1, agent_count))
	return {
		"average_wealth": totals[0] / divisor,
		"average_stress": totals[1] / divisor,
		"average_spending": totals[2] / divisor,
		"average_activity": totals[3] / divisor,
	}


func _empty_summary() -> Dictionary:
	return {
		"average_wealth": 0.0,
		"average_stress": 0.0,
		"average_spending": 0.0,
		"average_activity": 0.0,
	}
