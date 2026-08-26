class_name SpatialNeighborhoodBackend
extends RefCounted

const BUILD_SHADER_PATH := "res://ms6/spatial_grid_build.glsl"
const QUERY_SHADER_PATH := "res://ms6/spatial_neighbor_query.glsl"
const WORKGROUP_SIZE := 64
const BYTES_PER_FLOAT := 4
const BYTES_PER_INT := 4
const VALUES_PER_POSITION := 2
const CELL_REPRESENTATIVE_LANES := 8
const EMPTY_CELL_VALUE := 0x7fffffff

var _rendering_device: RenderingDevice
var _build_shader := RID()
var _query_shader := RID()
var _build_pipeline := RID()
var _query_pipeline := RID()
var _position_buffer := RID()
var _parameter_buffer := RID()
var _cell_head_buffer := RID()
var _neighbor_buffer := RID()
var _build_uniform_set := RID()
var _query_uniform_set := RID()
var _capacity_agents := 0
var _capacity_cells := 0
var _last_error := ""
var _device_initializations := 0
var _dispatch_count := 0
var _buffer_reallocations := 0
var _uploaded_bytes := 0
var _downloaded_bytes := 0


func find_nearest(
	positions: PackedFloat32Array,
	parameters: Dictionary = {},
	prefer_gpu: bool = true
) -> Dictionary:
	if positions.size() % VALUES_PER_POSITION != 0:
		return {"ok": false, "error": "INVALID_POSITION_BUFFER"}
	var resolved := _resolved_parameters(positions.size() / VALUES_PER_POSITION, parameters)
	if prefer_gpu:
		var gpu_result := _run_gpu(positions, resolved)
		if bool(gpu_result.get("ok", false)):
			return gpu_result
		var fallback := _run_cpu(positions, resolved)
		fallback["backend"] = "CPU_FALLBACK"
		fallback["gpu_error"] = str(gpu_result.get("error", "GPU_UNAVAILABLE"))
		return fallback
	return _run_cpu(positions, resolved)


func get_metrics() -> Dictionary:
	return {
		"persistent_device": _rendering_device != null,
		"device_initializations": _device_initializations,
		"dispatch_count": _dispatch_count,
		"buffer_reallocations": _buffer_reallocations,
		"uploaded_bytes": _uploaded_bytes,
		"downloaded_bytes": _downloaded_bytes,
		"capacity_agents": _capacity_agents,
		"capacity_cells": _capacity_cells,
		"representative_lanes": CELL_REPRESENTATIVE_LANES,
		"last_error": _last_error,
	}


func close() -> void:
	_free_buffer_resources()
	if _rendering_device != null:
		_free_rid(_query_pipeline)
		_free_rid(_build_pipeline)
		_free_rid(_query_shader)
		_free_rid(_build_shader)
		_rendering_device.free()
	_rendering_device = null
	_build_shader = RID()
	_query_shader = RID()
	_build_pipeline = RID()
	_query_pipeline = RID()


func _run_cpu(positions: PackedFloat32Array, parameters: Dictionary) -> Dictionary:
	var agent_count := int(parameters.agent_count)
	var grid_width := int(parameters.grid_width)
	var grid_height := int(parameters.grid_height)
	var cell_size := float(parameters.cell_size)
	var radius_squared := pow(float(parameters.radius), 2.0)
	var cells: Array = []
	cells.resize(grid_width * grid_height)
	for cell_index in range(cells.size()):
		var lanes := PackedInt32Array()
		lanes.resize(CELL_REPRESENTATIVE_LANES)
		lanes.fill(EMPTY_CELL_VALUE)
		cells[cell_index] = lanes
	for agent_index in range(agent_count):
		var cell := _cell_for_position(
			positions[agent_index * 2], positions[agent_index * 2 + 1],
			grid_width, grid_height, cell_size
		)
		var cell_index := cell.y * grid_width + cell.x
		var lane := agent_index % CELL_REPRESENTATIVE_LANES
		var representatives: PackedInt32Array = cells[cell_index]
		representatives[lane] = mini(representatives[lane], agent_index)
		cells[cell_index] = representatives
	var neighbors := PackedInt32Array()
	neighbors.resize(agent_count)
	neighbors.fill(-1)
	for agent_index in range(agent_count):
		var x := float(positions[agent_index * 2])
		var y := float(positions[agent_index * 2 + 1])
		var center := _cell_for_position(x, y, grid_width, grid_height, cell_size)
		var best_index := -1
		var best_distance := radius_squared
		for delta_y in range(-1, 2):
			var cell_y := center.y + delta_y
			if cell_y < 0 or cell_y >= grid_height:
				continue
			for delta_x in range(-1, 2):
				var cell_x := center.x + delta_x
				if cell_x < 0 or cell_x >= grid_width:
					continue
				for candidate: int in cells[cell_y * grid_width + cell_x]:
					if candidate == EMPTY_CELL_VALUE:
						continue
					if candidate == agent_index:
						continue
					var difference_x := float(positions[candidate * 2]) - x
					var difference_y := float(positions[candidate * 2 + 1]) - y
					var distance_squared := difference_x * difference_x + difference_y * difference_y
					if (
						distance_squared <= radius_squared
						and (
							best_index < 0 or distance_squared < best_distance
							or (distance_squared == best_distance and candidate < best_index)
						)
					):
						best_index = candidate
						best_distance = distance_squared
		neighbors[agent_index] = best_index
	return {
		"ok": true,
		"backend": "CPU",
		"neighbors": neighbors,
		"neighbor_count": _neighbor_count(neighbors),
		"checksum": _neighbor_checksum(neighbors),
	}


func _run_gpu(positions: PackedFloat32Array, parameters: Dictionary) -> Dictionary:
	var agent_count := int(parameters.agent_count)
	if agent_count == 0:
		return {
			"ok": true, "backend": "GPU", "neighbors": PackedInt32Array(),
			"neighbor_count": 0, "checksum": "00000000",
		}
	var cell_count := int(parameters.grid_width) * int(parameters.grid_height)
	if not _ensure_resources(agent_count, cell_count):
		return {"ok": false, "error": _last_error}
	var position_bytes := positions.to_byte_array()
	_rendering_device.buffer_update(_position_buffer, 0, position_bytes.size(), position_bytes)
	var parameter_values := PackedFloat32Array([
		float(agent_count), float(parameters.grid_width), float(parameters.grid_height),
		float(parameters.cell_size), float(parameters.radius),
		float(CELL_REPRESENTATIVE_LANES), 0.0, 0.0,
	])
	var parameter_bytes := parameter_values.to_byte_array()
	_rendering_device.buffer_update(_parameter_buffer, 0, parameter_bytes.size(), parameter_bytes)
	var cell_heads := PackedInt32Array()
	cell_heads.resize(cell_count * CELL_REPRESENTATIVE_LANES)
	cell_heads.fill(EMPTY_CELL_VALUE)
	var cell_head_bytes := cell_heads.to_byte_array()
	_rendering_device.buffer_update(_cell_head_buffer, 0, cell_head_bytes.size(), cell_head_bytes)
	_uploaded_bytes += position_bytes.size() + parameter_bytes.size() + cell_head_bytes.size()
	var workgroup_count := int(ceil(float(agent_count) / float(WORKGROUP_SIZE)))
	var compute_list := _rendering_device.compute_list_begin()
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _build_pipeline)
	_rendering_device.compute_list_bind_uniform_set(compute_list, _build_uniform_set, 0)
	_rendering_device.compute_list_dispatch(compute_list, workgroup_count, 1, 1)
	_rendering_device.compute_list_add_barrier(compute_list)
	_rendering_device.compute_list_bind_compute_pipeline(compute_list, _query_pipeline)
	_rendering_device.compute_list_bind_uniform_set(compute_list, _query_uniform_set, 0)
	_rendering_device.compute_list_dispatch(compute_list, workgroup_count, 1, 1)
	_rendering_device.compute_list_end()
	_rendering_device.submit()
	_rendering_device.sync()
	_dispatch_count += 1
	var output_bytes := _rendering_device.buffer_get_data(
		_neighbor_buffer, 0, agent_count * BYTES_PER_INT
	)
	_downloaded_bytes += output_bytes.size()
	var neighbors := output_bytes.to_int32_array()
	return {
		"ok": true,
		"backend": "GPU",
		"neighbors": neighbors,
		"neighbor_count": _neighbor_count(neighbors),
		"checksum": _neighbor_checksum(neighbors),
		"workgroup_count": workgroup_count,
	}


func _ensure_resources(agent_count: int, cell_count: int) -> bool:
	if _rendering_device == null and not _create_device_and_pipelines():
		return false
	if (
		agent_count <= _capacity_agents and cell_count <= _capacity_cells
		and _position_buffer.is_valid()
	):
		return true
	_free_buffer_resources()
	_capacity_agents = _next_power_of_two(agent_count)
	_capacity_cells = _next_power_of_two(cell_count)
	_position_buffer = _rendering_device.storage_buffer_create(
		_capacity_agents * VALUES_PER_POSITION * BYTES_PER_FLOAT
	)
	_parameter_buffer = _rendering_device.storage_buffer_create(8 * BYTES_PER_FLOAT)
	_cell_head_buffer = _rendering_device.storage_buffer_create(
		_capacity_cells * CELL_REPRESENTATIVE_LANES * BYTES_PER_INT
	)
	_neighbor_buffer = _rendering_device.storage_buffer_create(_capacity_agents * BYTES_PER_INT)
	if (
		not _position_buffer.is_valid() or not _parameter_buffer.is_valid()
		or not _cell_head_buffer.is_valid() or not _neighbor_buffer.is_valid()
	):
		_last_error = "SPATIAL_BUFFER_CREATION_FAILED"
		_free_buffer_resources()
		return false
	_build_uniform_set = _rendering_device.uniform_set_create(
		[
			_storage_uniform(0, _position_buffer), _storage_uniform(1, _parameter_buffer),
			_storage_uniform(2, _cell_head_buffer),
		],
		_build_shader,
		0
	)
	_query_uniform_set = _rendering_device.uniform_set_create(
		[
			_storage_uniform(0, _position_buffer), _storage_uniform(1, _parameter_buffer),
			_storage_uniform(2, _cell_head_buffer), _storage_uniform(3, _neighbor_buffer),
		],
		_query_shader,
		0
	)
	if not _build_uniform_set.is_valid() or not _query_uniform_set.is_valid():
		_last_error = "SPATIAL_UNIFORM_SET_CREATION_FAILED"
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
	var build_file := load(BUILD_SHADER_PATH) as RDShaderFile
	var query_file := load(QUERY_SHADER_PATH) as RDShaderFile
	if build_file == null or query_file == null:
		_last_error = "SPATIAL_SHADER_NOT_LOADED"
		close()
		return false
	_build_shader = _rendering_device.shader_create_from_spirv(build_file.get_spirv())
	_query_shader = _rendering_device.shader_create_from_spirv(query_file.get_spirv())
	if not _build_shader.is_valid() or not _query_shader.is_valid():
		_last_error = "SPATIAL_SHADER_CREATION_FAILED"
		close()
		return false
	_build_pipeline = _rendering_device.compute_pipeline_create(_build_shader)
	_query_pipeline = _rendering_device.compute_pipeline_create(_query_shader)
	if not _build_pipeline.is_valid() or not _query_pipeline.is_valid():
		_last_error = "SPATIAL_PIPELINE_CREATION_FAILED"
		close()
		return false
	_last_error = ""
	return true


func _resolved_parameters(agent_count: int, parameters: Dictionary) -> Dictionary:
	var cell_size := maxf(16.0, float(parameters.get("cell_size", 96.0)))
	var world_width := maxf(cell_size, float(parameters.get("world_width", 2400.0)))
	var world_height := maxf(cell_size, float(parameters.get("world_height", 1450.0)))
	return {
		"agent_count": agent_count,
		"cell_size": cell_size,
		"radius": clampf(float(parameters.get("radius", 72.0)), 1.0, cell_size),
		"grid_width": int(ceil(world_width / cell_size)),
		"grid_height": int(ceil(world_height / cell_size)),
	}


func _cell_for_position(
	x: float, y: float, grid_width: int, grid_height: int, cell_size: float
) -> Vector2i:
	return Vector2i(
		clampi(int(floor(x / cell_size)), 0, grid_width - 1),
		clampi(int(floor(y / cell_size)), 0, grid_height - 1)
	)


func _storage_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform


func _free_buffer_resources() -> void:
	if _rendering_device != null:
		_free_rid(_query_uniform_set)
		_free_rid(_build_uniform_set)
		_free_rid(_neighbor_buffer)
		_free_rid(_cell_head_buffer)
		_free_rid(_parameter_buffer)
		_free_rid(_position_buffer)
	_query_uniform_set = RID()
	_build_uniform_set = RID()
	_neighbor_buffer = RID()
	_cell_head_buffer = RID()
	_parameter_buffer = RID()
	_position_buffer = RID()
	_capacity_agents = 0
	_capacity_cells = 0


func _free_rid(rid: RID) -> void:
	if _rendering_device != null and rid.is_valid():
		_rendering_device.free_rid(rid)


func _next_power_of_two(value: int) -> int:
	var result := 1
	while result < value:
		result <<= 1
	return result


func _neighbor_count(neighbors: PackedInt32Array) -> int:
	var count := 0
	for neighbor in neighbors:
		if neighbor >= 0:
			count += 1
	return count


func _neighbor_checksum(neighbors: PackedInt32Array) -> String:
	var checksum := 0
	for index in range(neighbors.size()):
		checksum = checksum ^ ((int(neighbors[index]) + 1) << (index % 13))
	return "%08x" % (checksum & 0xffffffff)
