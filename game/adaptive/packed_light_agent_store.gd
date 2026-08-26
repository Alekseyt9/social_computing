class_name PackedLightAgentStore
extends RefCounted

## Compact struct-of-arrays backing store. Individual Dictionaries are
## reconstructed only at query/refinement boundaries.

const SCHEDULE_TO_CODE := {
	"UNEMPLOYED": 0,
	"DAY_WORK": 1,
	"EVENING_SHIFT": 2,
	"FLEXIBLE": 3,
}
const CODE_TO_SCHEDULE := ["UNEMPLOYED", "DAY_WORK", "EVENING_SHIFT", "FLEXIBLE"]
const FEEDBACK_DIRTY_BLOCK_SIZE := 64
const LightScheduleScript := preload("res://agents/light_schedule.gd")
const SPATIAL_PLACE_ZONES := {
	1: Rect2(1160, 430, 430, 300),
	2: Rect2(625, 465, 470, 180),
	3: Rect2(620, 1180, 500, 190),
	4: Rect2(85, 480, 425, 225),
	5: Rect2(1165, 1015, 430, 170),
	6: Rect2(1815, 430, 500, 315),
	7: Rect2(1840, 1015, 420, 150),
	8: Rect2(1210, 1175, 400, 200),
}

var _first_id: int
var _capacity: int
var _count: int = 0
var _household_ids := PackedInt32Array()
var _home_place_ids := PackedInt32Array()
var _workplace_ids := PackedInt32Array()
var _employment_codes := PackedByteArray()
var _schedule_codes := PackedByteArray()
var _current_place_ids := PackedInt32Array()
var _money_cents := PackedInt64Array()
var _wealth := PackedFloat32Array()
var _stress := PackedFloat32Array()
var _spending := PackedFloat32Array()
var _activity_level := PackedFloat32Array()
var _social_group_ids: Array = []
var _local_contact_ids: Array = []
var _rumor_ids: Array = []
var _cohort_members: Dictionary = {}
var _feedback_dirty_blocks: Dictionary = {}


func _init(first_agent_id: int, capacity: int) -> void:
	_first_id = first_agent_id
	_capacity = capacity


func add_agent(agent: Dictionary) -> void:
	assert(_count < _capacity, "PackedLightAgentStore capacity exceeded")
	assert(int(agent.id) == _first_id + _count, "Packed agents must use contiguous stable ids")
	_household_ids.append(int(agent.household_id))
	_home_place_ids.append(int(agent.home_place_id))
	_workplace_ids.append(int(agent.workplace_organization_id))
	_employment_codes.append(1 if str(agent.employment_status) == "EMPLOYED" else 0)
	_schedule_codes.append(int(SCHEDULE_TO_CODE.get(str(agent.schedule_kind), 0)))
	_current_place_ids.append(int(agent.current_place_id))
	_money_cents.append(int(agent.money_cents))
	_wealth.append(clampf(float(agent.get("wealth", 0.5)), 0.0, 1.0))
	_stress.append(clampf(float(agent.get("stress", 0.2)), 0.0, 1.0))
	_spending.append(clampf(float(agent.get("spending", 0.4)), 0.0, 1.0))
	_activity_level.append(clampf(float(agent.get("activity_level", 0.5)), 0.0, 1.0))
	_mark_feedback_dirty(_count)
	_social_group_ids.append(agent.social_group_ids.duplicate())
	_local_contact_ids.append(agent.local_contact_ids.duplicate())
	_rumor_ids.append(agent.rumor_ids.duplicate())
	_add_to_cohort(_cohort_key_for_agent(agent), int(agent.id))
	_count += 1


func has(agent_id: int) -> bool:
	return agent_id >= _first_id and agent_id < _first_id + _count


func size() -> int:
	return _count


func get_agent_ids() -> Array[int]:
	var result: Array[int] = []
	for index in range(_count):
		result.append(_first_id + index)
	return result


func get_agent(agent_id: int) -> Dictionary:
	if not has(agent_id):
		return {}
	var index := agent_id - _first_id
	return {
		"id": agent_id,
		"household_id": int(_household_ids[index]),
		"home_place_id": int(_home_place_ids[index]),
		"workplace_organization_id": int(_workplace_ids[index]),
		"employment_status": "EMPLOYED" if int(_employment_codes[index]) == 1 else "UNEMPLOYED",
		"schedule_kind": CODE_TO_SCHEDULE[int(_schedule_codes[index])],
		"current_place_id": int(_current_place_ids[index]),
		"money_cents": int(_money_cents[index]),
		"wealth": float(_wealth[index]),
		"stress": float(_stress[index]),
		"spending": float(_spending[index]),
		"activity_level": float(_activity_level[index]),
		"social_group_ids": _social_group_ids[index].duplicate(),
		"local_contact_ids": _local_contact_ids[index].duplicate(),
		"rumor_ids": _rumor_ids[index].duplicate(),
	}


func update_agent(agent: Dictionary) -> void:
	var agent_id := int(agent.id)
	assert(has(agent_id), "Cannot update unknown packed agent")
	var index := agent_id - _first_id
	var old_cohort_key := _cohort_key_from_columns(index)
	var new_cohort_key := _cohort_key_for_agent(agent)
	if old_cohort_key != new_cohort_key:
		_remove_from_cohort(old_cohort_key, agent_id)
	_household_ids[index] = int(agent.household_id)
	_home_place_ids[index] = int(agent.home_place_id)
	_workplace_ids[index] = int(agent.workplace_organization_id)
	_employment_codes[index] = 1 if str(agent.employment_status) == "EMPLOYED" else 0
	_schedule_codes[index] = int(SCHEDULE_TO_CODE.get(str(agent.schedule_kind), 0))
	_current_place_ids[index] = int(agent.current_place_id)
	_money_cents[index] = int(agent.money_cents)
	var new_wealth := clampf(float(agent.get("wealth", _wealth[index])), 0.0, 1.0)
	var new_stress := clampf(float(agent.get("stress", _stress[index])), 0.0, 1.0)
	var new_spending := clampf(float(agent.get("spending", _spending[index])), 0.0, 1.0)
	var new_activity := clampf(
		float(agent.get("activity_level", _activity_level[index])), 0.0, 1.0
	)
	if (
		new_wealth != _wealth[index] or new_stress != _stress[index]
		or new_spending != _spending[index] or new_activity != _activity_level[index]
	):
		_mark_feedback_dirty(index)
	_wealth[index] = new_wealth
	_stress[index] = new_stress
	_spending[index] = new_spending
	_activity_level[index] = new_activity
	_social_group_ids[index] = agent.social_group_ids.duplicate()
	_local_contact_ids[index] = agent.local_contact_ids.duplicate()
	_rumor_ids[index] = agent.rumor_ids.duplicate()
	if old_cohort_key != new_cohort_key:
		_add_to_cohort(new_cohort_key, agent_id)


func get_cohort_keys() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _cohort_members.keys():
		result.append(str(key))
	result.sort()
	return result


func get_cohort_agent_ids(cohort_key: String) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in _cohort_members.get(cohort_key, []):
		result.append(int(value))
	return result


func storage_metrics() -> Dictionary:
	return {
		"layout": "STRUCT_OF_ARRAYS",
		"record_count": _count,
		"scalar_columns": 11,
		"sparse_array_columns": 3,
		"dictionary_records": 0,
		"cohort_count": _cohort_members.size(),
	}


func export_feedback_buffer() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(_count * 4)
	for index in range(_count):
		var offset := index * 4
		values[offset] = _wealth[index]
		values[offset + 1] = _stress[index]
		values[offset + 2] = _spending[index]
		values[offset + 3] = _activity_level[index]
	return values


func export_spatial_positions(at_tick: int) -> PackedFloat32Array:
	var positions := PackedFloat32Array()
	positions.resize(_count * 2)
	for index in range(_count):
		var workplace_id := int(_workplace_ids[index])
		var work_place_id := 1 if workplace_id == 1 else 2
		var place_id := LightScheduleScript.resolve_place(
			CODE_TO_SCHEDULE[int(_schedule_codes[index])],
			at_tick,
			int(_home_place_ids[index]),
			work_place_id
		)
		var zone: Rect2 = SPATIAL_PLACE_ZONES.get(place_id, SPATIAL_PLACE_ZONES[2])
		var agent_id := _first_id + index
		var usable_width := maxf(1.0, zone.size.x - 24.0)
		var usable_height := maxf(1.0, zone.size.y - 24.0)
		var unit_x := float(posmod(agent_id * 1103 + place_id * 7919, 10_007)) / 10_006.0
		var unit_y := float(posmod(agent_id * 2017 + place_id * 3571, 10_009)) / 10_008.0
		positions[index * 2] = zone.position.x + 12.0 + unit_x * usable_width
		positions[index * 2 + 1] = zone.position.y + 12.0 + unit_y * usable_height
	return positions


func feedback_dirty_ranges() -> Array[Dictionary]:
	var block_ids: Array[int] = []
	for value: Variant in _feedback_dirty_blocks.keys():
		block_ids.append(int(value))
	block_ids.sort()
	var ranges: Array[Dictionary] = []
	if block_ids.is_empty():
		return ranges
	var run_start := block_ids[0]
	var run_end := run_start
	for index in range(1, block_ids.size()):
		var block_id := block_ids[index]
		if block_id == run_end + 1:
			run_end = block_id
		else:
			ranges.append(_export_feedback_block_run(run_start, run_end))
			run_start = block_id
			run_end = block_id
	ranges.append(_export_feedback_block_run(run_start, run_end))
	return ranges


func _export_feedback_block_run(start_block: int, end_block: int) -> Dictionary:
	var start_agent := start_block * FEEDBACK_DIRTY_BLOCK_SIZE
	var end_agent := mini(_count, (end_block + 1) * FEEDBACK_DIRTY_BLOCK_SIZE)
	var count := end_agent - start_agent
	var values := PackedFloat32Array()
	values.resize(count * 4)
	for local_index in range(count):
		var source_index := start_agent + local_index
		var source_offset := source_index * 4
		var target_offset := local_index * 4
		values[target_offset] = _wealth[source_index]
		values[target_offset + 1] = _stress[source_index]
		values[target_offset + 2] = _spending[source_index]
		values[target_offset + 3] = _activity_level[source_index]
	return {
		"start_agent": start_agent,
		"agent_count": count,
		"values": values,
	}


func clear_feedback_dirty_range() -> void:
	_feedback_dirty_blocks.clear()


func apply_feedback_buffer(values: PackedFloat32Array) -> bool:
	if values.size() != _count * 4:
		return false
	for index in range(_count):
		var offset := index * 4
		_wealth[index] = clampf(values[offset], 0.0, 1.0)
		_stress[index] = clampf(values[offset + 1], 0.0, 1.0)
		_spending[index] = clampf(values[offset + 2], 0.0, 1.0)
		_activity_level[index] = clampf(values[offset + 3], 0.0, 1.0)
	return true


func feedback_summary() -> Dictionary:
	var totals := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var checksum := 0
	for index in range(_count):
		totals[0] += _wealth[index]
		totals[1] += _stress[index]
		totals[2] += _spending[index]
		totals[3] += _activity_level[index]
		checksum = checksum ^ (int(_wealth[index] * 10_000.0) << (index % 5))
		checksum = checksum ^ (int(_stress[index] * 10_000.0) << ((index + 1) % 5))
		checksum = checksum ^ (int(_spending[index] * 10_000.0) << ((index + 2) % 5))
		checksum = checksum ^ (int(_activity_level[index] * 10_000.0) << ((index + 3) % 5))
	var divisor := float(maxi(1, _count))
	return {
		"average_wealth": totals[0] / divisor,
		"average_stress": totals[1] / divisor,
		"average_spending": totals[2] / divisor,
		"average_activity": totals[3] / divisor,
		"checksum": "%08x" % (checksum & 0xffffffff),
	}


func _cohort_key_for_agent(agent: Dictionary) -> String:
	return "%d:%s:%s" % [
		int(agent.workplace_organization_id),
		str(agent.employment_status),
		str(agent.schedule_kind),
	]


func _cohort_key_from_columns(index: int) -> String:
	return "%d:%s:%s" % [
		int(_workplace_ids[index]),
		"EMPLOYED" if int(_employment_codes[index]) == 1 else "UNEMPLOYED",
		CODE_TO_SCHEDULE[int(_schedule_codes[index])],
	]


func _add_to_cohort(cohort_key: String, agent_id: int) -> void:
	if not _cohort_members.has(cohort_key):
		_cohort_members[cohort_key] = [] as Array[int]
	_cohort_members[cohort_key].append(agent_id)


func _remove_from_cohort(cohort_key: String, agent_id: int) -> void:
	var members: Array = _cohort_members.get(cohort_key, [])
	members.erase(agent_id)
	if members.is_empty():
		_cohort_members.erase(cohort_key)
	else:
		_cohort_members[cohort_key] = members


func _mark_feedback_dirty(index: int) -> void:
	_feedback_dirty_blocks[int(index / FEEDBACK_DIRTY_BLOCK_SIZE)] = true
