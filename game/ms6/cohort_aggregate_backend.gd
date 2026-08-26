class_name CohortAggregateBackend
extends RefCounted

const SHADER_PATH := "res://ms6/cohort_field_reduce.glsl"
const COHORT_COUNT := 24
const FIELDS_PER_AGENT := 4
const VALUES_PER_COHORT := 5
const BYTES_PER_VALUE := 4

var _rendering_device: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _field_buffer := RID()
var _code_buffer := RID()
var _parameter_buffer := RID()
var _output_buffer := RID()
var _uniform_set := RID()
var _capacity_agents := 0
var _last_error := ""
var _device_initializations := 0
var _dispatch_count := 0
var _buffer_reallocations := 0
var _uploaded_bytes := 0
var _downloaded_bytes := 0


func reduce(
	fields: PackedFloat32Array,
	cohort_codes: PackedInt32Array,
	prefer_gpu: bool = true
) -> Dictionary:
	if fields.size() != cohort_codes.size() * FIELDS_PER_AGENT:
		return {"ok": false, "error": "INVALID_COHORT_INPUT"}
	if prefer_gpu:
		var gpu_result := _run_gpu(fields, cohort_codes)
		if bool(gpu_result.get("ok", false)):
			return gpu_result
		var fallback := _run_cpu(fields, cohort_codes)
		fallback["backend"] = "CPU_FALLBACK"
		fallback["gpu_error"] = str(gpu_result.get("error", "GPU_UNAVAILABLE"))
		return fallback
	return _run_cpu(fields, cohort_codes)


func get_metrics() -> Dictionary:
	return {
		"persistent_device": _rendering_device != null,
		"device_initializations": _device_initializations,
		"dispatch_count": _dispatch_count,
		"buffer_reallocations": _buffer_reallocations,
		"uploaded_bytes": _uploaded_bytes,
		"downloaded_bytes": _downloaded_bytes,
		"capacity_agents": _capacity_agents,
		"cohort_count": COHORT_COUNT,
		"last_error": _last_error,
	}


func close() -> void:
	_free_buffers()
	if _rendering_device != null:
		_free_rid(_pipeline)
		_free_rid(_shader)
		_rendering_device.free()
	_rendering_device = null
	_shader = RID()
	_pipeline = RID()


func _run_cpu(fields: PackedFloat32Array, cohort_codes: PackedInt32Array) -> Dictionary:
	var totals := PackedFloat32Array()
	totals.resize(COHORT_COUNT * VALUES_PER_COHORT)
	for agent_index in range(cohort_codes.size()):
		var cohort := clampi(int(cohort_codes[agent_index]), 0, COHORT_COUNT - 1)
		var source_offset := agent_index * FIELDS_PER_AGENT
		var target_offset := cohort * VALUES_PER_COHORT
		for field_index in range(FIELDS_PER_AGENT):
			totals[target_offset + field_index] += fields[source_offset + field_index]
		totals[target_offset + 4] += 1.0
	return _result("CPU", totals)


func _run_gpu(fields: PackedFloat32Array, cohort_codes: PackedInt32Array) -> Dictionary:
	var agent_count := cohort_codes.size()
	if agent_count == 0:
		return _result("GPU", PackedFloat32Array())
	if not _ensure_resources(agent_count):
		return {"ok": false, "error": _last_error}
	var field_bytes := fields.to_byte_array()
	var code_bytes := cohort_codes.to_byte_array()
	var parameter_values := PackedFloat32Array([float(agent_count), float(COHORT_COUNT), 0.0, 0.0])
	var parameter_bytes := parameter_values.to_byte_array()
	_rendering_device.buffer_update(_field_buffer, 0, field_bytes.size(), field_bytes)
	_rendering_device.buffer_update(_code_buffer, 0, code_bytes.size(), code_bytes)
	_rendering_device.buffer_update(_parameter_buffer, 0, parameter_bytes.size(), parameter_bytes)
	_uploaded_bytes += field_bytes.size() + code_bytes.size() + parameter_bytes.size()
	var compute_list := _rendering_device.compute_list_begin()
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rendering_device.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	_rendering_device.compute_list_dispatch(compute_list, COHORT_COUNT, 1, 1)
	_rendering_device.compute_list_end()
	_rendering_device.submit()
	_rendering_device.sync()
	_dispatch_count += 1
	var output_bytes := _rendering_device.buffer_get_data(
		_output_buffer, 0, COHORT_COUNT * VALUES_PER_COHORT * BYTES_PER_VALUE
	)
	_downloaded_bytes += output_bytes.size()
	return _result("GPU", output_bytes.to_float32_array())


func _result(backend: String, totals: PackedFloat32Array) -> Dictionary:
	if totals.size() != COHORT_COUNT * VALUES_PER_COHORT:
		totals.resize(COHORT_COUNT * VALUES_PER_COHORT)
	var global := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var active_cohorts := 0
	for cohort in range(COHORT_COUNT):
		var offset := cohort * VALUES_PER_COHORT
		if totals[offset + 4] > 0.0:
			active_cohorts += 1
		for value_index in range(VALUES_PER_COHORT):
			global[value_index] += float(totals[offset + value_index])
	var divisor := maxf(1.0, global[4])
	return {
		"ok": true,
		"backend": backend,
		"values": totals,
		"active_cohorts": active_cohorts,
		"summary": {
			"average_wealth": global[0] / divisor,
			"average_stress": global[1] / divisor,
			"average_spending": global[2] / divisor,
			"average_activity": global[3] / divisor,
			"agent_count": int(round(global[4])),
		},
	}


func _ensure_resources(agent_count: int) -> bool:
	if _rendering_device == null and not _create_device():
		return false
	if agent_count <= _capacity_agents and _field_buffer.is_valid():
		return true
	_free_buffers()
	_capacity_agents = _next_power_of_two(agent_count)
	_field_buffer = _rendering_device.storage_buffer_create(
		_capacity_agents * FIELDS_PER_AGENT * BYTES_PER_VALUE
	)
	_code_buffer = _rendering_device.storage_buffer_create(_capacity_agents * BYTES_PER_VALUE)
	_parameter_buffer = _rendering_device.storage_buffer_create(4 * BYTES_PER_VALUE)
	_output_buffer = _rendering_device.storage_buffer_create(
		COHORT_COUNT * VALUES_PER_COHORT * BYTES_PER_VALUE
	)
	if (
		not _field_buffer.is_valid() or not _code_buffer.is_valid()
		or not _parameter_buffer.is_valid() or not _output_buffer.is_valid()
	):
		_last_error = "COHORT_BUFFER_CREATION_FAILED"
		_free_buffers()
		return false
	_uniform_set = _rendering_device.uniform_set_create(
		[
			_storage_uniform(0, _field_buffer), _storage_uniform(1, _code_buffer),
			_storage_uniform(2, _parameter_buffer), _storage_uniform(3, _output_buffer),
		],
		_shader,
		0
	)
	if not _uniform_set.is_valid():
		_last_error = "COHORT_UNIFORM_SET_CREATION_FAILED"
		_free_buffers()
		return false
	_buffer_reallocations += 1
	return true


func _create_device() -> bool:
	_rendering_device = RenderingServer.create_local_rendering_device()
	if _rendering_device == null:
		_last_error = "LOCAL_RENDERING_DEVICE_UNAVAILABLE"
		return false
	_device_initializations += 1
	var shader_file := load(SHADER_PATH) as RDShaderFile
	if shader_file == null:
		_last_error = "COHORT_SHADER_NOT_LOADED"
		close()
		return false
	_shader = _rendering_device.shader_create_from_spirv(shader_file.get_spirv())
	if not _shader.is_valid():
		_last_error = "COHORT_SHADER_CREATION_FAILED"
		close()
		return false
	_pipeline = _rendering_device.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		_last_error = "COHORT_PIPELINE_CREATION_FAILED"
		close()
		return false
	_last_error = ""
	return true


func _storage_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform


func _free_buffers() -> void:
	if _rendering_device != null:
		_free_rid(_uniform_set)
		_free_rid(_output_buffer)
		_free_rid(_parameter_buffer)
		_free_rid(_code_buffer)
		_free_rid(_field_buffer)
	_uniform_set = RID()
	_output_buffer = RID()
	_parameter_buffer = RID()
	_code_buffer = RID()
	_field_buffer = RID()
	_capacity_agents = 0


func _free_rid(rid: RID) -> void:
	if _rendering_device != null and rid.is_valid():
		_rendering_device.free_rid(rid)


func _next_power_of_two(value: int) -> int:
	var result := 1
	while result < value:
		result <<= 1
	return result
