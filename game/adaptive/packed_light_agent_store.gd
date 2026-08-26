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
var _social_group_ids: Array = []
var _local_contact_ids: Array = []
var _rumor_ids: Array = []
var _cohort_members: Dictionary = {}


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
		"scalar_columns": 7,
		"sparse_array_columns": 3,
		"dictionary_records": 0,
		"cohort_count": _cohort_members.size(),
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
