class_name ActivityPlanSystem
extends RefCounted

const TERMINAL_STATUSES := ["COMPLETED", "MISSED", "CANCELLED"]

var _plans: Dictionary = {}
var _next_plan_id := 1


func create_plan(definition: Dictionary) -> Dictionary:
	var participant_ids: Array[int] = []
	for value: Variant in definition.get("participant_ids", []):
		var participant_id := int(value)
		if participant_id not in participant_ids:
			participant_ids.append(participant_id)
	participant_ids.sort()
	if participant_ids.size() < 2:
		return {"ok": false, "error": "PLAN_REQUIRES_PARTICIPANTS"}
	var created_tick := int(definition.get("created_tick", 0))
	var start_tick := maxi(created_tick + 1, int(definition.get("start_tick", created_tick + 12)))
	var duration_ticks := maxi(6, int(definition.get("duration_ticks", 12)))
	var plan_id := _next_plan_id
	_next_plan_id += 1
	var plan := {
		"id": plan_id,
		"activity": str(definition.get("activity", "SOCIAL")),
		"activity_label": str(definition.get("activity_label", "совместное занятие")),
		"place_id": int(definition.get("place_id", -1)),
		"creator_id": int(definition.get("creator_id", participant_ids[0])),
		"participant_ids": participant_ids,
		"required_participants": clampi(
			int(definition.get("required_participants", 2)), 2, participant_ids.size()
		),
		"created_tick": created_tick,
		"gathering_tick": maxi(created_tick, start_tick - 6),
		"start_tick": start_tick,
		"end_tick": start_tick + duration_ticks,
		"status": "PLANNED",
		"arrival_ticks": {},
		"started_tick": -1,
		"completed_tick": -1,
		"late_start": false,
	}
	_plans[plan_id] = plan
	return {"ok": true, "plan": plan.duplicate(true)}


func advance(current_tick: int, location_resolver: Callable) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var plan_ids: Array[int] = []
	for value: Variant in _plans.keys():
		plan_ids.append(int(value))
	plan_ids.sort()
	for plan_id: int in plan_ids:
		var plan: Dictionary = _plans[plan_id]
		if str(plan.status) in TERMINAL_STATUSES or current_tick < int(plan.gathering_tick):
			continue
		if str(plan.status) == "PLANNED":
			plan["status"] = "GATHERING"
			transitions.append(_transition("GATHERING", plan, current_tick))
		var arrival_ticks: Dictionary = plan.arrival_ticks
		for participant_id: int in plan.participant_ids:
			if arrival_ticks.has(participant_id):
				continue
			if int(location_resolver.call(participant_id)) == int(plan.place_id):
				arrival_ticks[participant_id] = current_tick
				if current_tick > int(plan.start_tick):
					transitions.append(_transition(
						"LATE_ARRIVAL", plan, current_tick, {"participant_id": participant_id}
					))
		plan["arrival_ticks"] = arrival_ticks
		if (
			current_tick >= int(plan.start_tick) and str(plan.status) == "GATHERING"
			and arrival_ticks.size() >= int(plan.required_participants)
		):
			plan["status"] = "ACTIVE"
			plan["started_tick"] = current_tick
			plan["late_start"] = current_tick > int(plan.start_tick)
			transitions.append(_transition(
				"STARTED_LATE" if bool(plan.late_start) else "STARTED", plan, current_tick
			))
		if current_tick >= int(plan.end_tick):
			if str(plan.status) == "ACTIVE":
				plan["status"] = "COMPLETED"
				plan["completed_tick"] = current_tick
				transitions.append(_transition("COMPLETED", plan, current_tick))
			else:
				plan["status"] = "MISSED"
				plan["completed_tick"] = current_tick
				transitions.append(_transition("MISSED", plan, current_tick, {
					"absent_participant_ids": _absent_participants(plan),
				}))
		_plans[plan_id] = plan
	return transitions


func get_plan(plan_id: int) -> Dictionary:
	return _plans.get(plan_id, {}).duplicate(true)


func get_plans() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[int] = []
	for value: Variant in _plans.keys():
		ids.append(int(value))
	ids.sort()
	for plan_id: int in ids:
		result.append(_plans[plan_id].duplicate(true))
	return result


func snapshot() -> Dictionary:
	var status_counts: Dictionary = {
		"PLANNED": 0, "GATHERING": 0, "ACTIVE": 0,
		"COMPLETED": 0, "MISSED": 0, "CANCELLED": 0,
	}
	var late_starts := 0
	for plan: Dictionary in _plans.values():
		var status := str(plan.status)
		status_counts[status] = int(status_counts.get(status, 0)) + 1
		if bool(plan.get("late_start", false)):
			late_starts += 1
	return {
		"count": _plans.size(),
		"next_plan_id": _next_plan_id,
		"status_counts": status_counts,
		"late_starts": late_starts,
		"plans": get_plans(),
	}


func _absent_participants(plan: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var arrival_ticks: Dictionary = plan.arrival_ticks
	for participant_id: int in plan.participant_ids:
		if not arrival_ticks.has(participant_id):
			result.append(participant_id)
	return result


func _transition(
	type: String, plan: Dictionary, at_tick: int, extra: Dictionary = {}
) -> Dictionary:
	var result := {
		"type": type,
		"tick": at_tick,
		"plan": plan.duplicate(true),
	}
	for key: Variant in extra:
		result[key] = extra[key]
	return result
