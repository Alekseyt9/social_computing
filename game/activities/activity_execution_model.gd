class_name ActivityExecutionModel
extends RefCounted

const DECISION_INTERVAL := 12
const TRAVEL_TICKS := 3
const RESERVE_TICKS := 1
const PLACE_SPOT_CAPACITY := {
	1: 48,
	2: 36,
	3: 96,
	4: 48,
	5: 28,
	6: 32,
	7: 18,
	8: 28,
}
const PHASE_LABELS := {
	"TRAVEL": "идёт к месту занятия",
	"RESERVE": "занимает место",
	"PERFORM": "выполняет занятие",
	"FINISH": "заканчивает занятие",
	"INTERRUPT": "прерывает занятие",
}

var _utility_model: RefCounted


func _init(utility_model: RefCounted) -> void:
	_utility_model = utility_model


func resolve(
	agent: Dictionary,
	at_tick: int,
	district_fields: Dictionary = {},
	include_explanation: bool = true
) -> Dictionary:
	var slot_start := at_tick - posmod(at_tick, DECISION_INTERVAL)
	var offset := posmod(at_tick, DECISION_INTERVAL)
	var selected: Dictionary = _utility_model.resolve(
		agent, slot_start, district_fields, include_explanation
	)
	var previous: Dictionary = _utility_model.resolve(
		agent, slot_start - DECISION_INTERVAL, district_fields, false
	)
	var next: Dictionary = _utility_model.resolve(
		agent, slot_start + DECISION_INTERVAL, district_fields, false
	)
	var destination_place_id := int(selected.place_id)
	var origin_place_id := int(previous.get("place_id", destination_place_id))
	var requires_travel := origin_place_id != destination_place_id
	var phase := _phase_for(
		agent, selected, previous, next, slot_start, offset, requires_travel, district_fields
	)
	var phase_start := TRAVEL_TICKS if requires_travel else 0
	if phase == "TRAVEL":
		phase_start = 0
	elif phase == "RESERVE":
		phase_start = TRAVEL_TICKS if requires_travel else 0
	elif phase in ["FINISH", "INTERRUPT"]:
		phase_start = DECISION_INTERVAL - 1
	else:
		phase_start = (TRAVEL_TICKS if requires_travel else 0) + RESERVE_TICKS
	var phase_end := _phase_end(phase, requires_travel)
	var capacity := int(PLACE_SPOT_CAPACITY.get(destination_place_id, 24))
	var spot_index := posmod(
		int(agent.id) * 1103 + slot_start * 31 + str(selected.activity).hash(), capacity
	)
	var has_reservation := phase in ["RESERVE", "PERFORM"]
	var released := phase in ["FINISH", "INTERRUPT"]
	var physical_place_id := origin_place_id if phase == "TRAVEL" else destination_place_id
	selected["tick"] = at_tick
	selected["plan_started_tick"] = slot_start
	selected["plan_ends_tick"] = slot_start + DECISION_INTERVAL
	selected["origin_place_id"] = origin_place_id
	selected["destination_place_id"] = destination_place_id
	selected["physical_place_id"] = physical_place_id
	selected["execution_phase"] = phase
	selected["phase_label"] = str(PHASE_LABELS[phase])
	selected["phase_progress"] = clampf(
		float(offset - phase_start + 1) / float(maxi(1, phase_end - phase_start)), 0.0, 1.0
	)
	selected["reservation_status"] = (
		"RESERVED" if has_reservation else ("RELEASED" if released else "PENDING")
	)
	selected["activity_spot_id"] = (
		"P%d-S%02d" % [destination_place_id, spot_index] if has_reservation else ""
	)
	selected["reservation_token"] = (
		"%d:%d:%s:%d" % [slot_start, int(agent.id), str(selected.activity), spot_index]
		if has_reservation else ""
	)
	selected["spot_capacity"] = capacity
	selected["is_interactable"] = phase == "PERFORM"
	selected["interrupted"] = phase == "INTERRUPT"
	selected["visual_action"] = _visual_action(str(selected.activity), phase)
	return selected


func _phase_for(
	agent: Dictionary,
	selected: Dictionary,
	previous: Dictionary,
	next: Dictionary,
	slot_start: int,
	offset: int,
	requires_travel: bool,
	district_fields: Dictionary
) -> String:
	if requires_travel and offset < TRAVEL_TICKS:
		return "TRAVEL"
	var reserve_start := TRAVEL_TICKS if requires_travel else 0
	if offset < reserve_start + RESERVE_TICKS:
		return "RESERVE"
	if offset < DECISION_INTERVAL - 1 or _same_plan(selected, next):
		return "PERFORM"
	var spec: ActivitySpec = _utility_model.get_spec(str(selected.activity))
	var continuous_ticks := DECISION_INTERVAL
	var cursor := previous
	var cursor_tick := slot_start - DECISION_INTERVAL
	while (
		spec != null and continuous_ticks < spec.duration_ticks
		and _same_plan(selected, cursor)
	):
		continuous_ticks += DECISION_INTERVAL
		cursor_tick -= DECISION_INTERVAL
		cursor = _utility_model.resolve(agent, cursor_tick, district_fields, false)
	return "FINISH" if spec == null or continuous_ticks >= spec.duration_ticks else "INTERRUPT"


func _phase_end(phase: String, requires_travel: bool) -> int:
	match phase:
		"TRAVEL":
			return TRAVEL_TICKS
		"RESERVE":
			return (TRAVEL_TICKS if requires_travel else 0) + RESERVE_TICKS
		"FINISH", "INTERRUPT":
			return DECISION_INTERVAL
		_:
			return DECISION_INTERVAL - 1


func _same_plan(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("activity", "")) == str(right.get("activity", "")) and (
		int(left.get("place_id", -1)) == int(right.get("place_id", -2))
	)


func _visual_action(activity: String, phase: String) -> String:
	if phase == "TRAVEL":
		return "WALK"
	if phase == "RESERVE":
		return "APPROACH_SPOT"
	if phase in ["FINISH", "INTERRUPT"]:
		return "LEAVE_SPOT"
	return {
		"WORK": "TYPE",
		"TEAMWORK": "TALK",
		"WORK_BREAK": "DRINK",
		"HOME": "CHORES",
		"REST": "SIT",
		"ERRANDS": "BROWSE",
		"CAFE_MEAL": "EAT",
		"LEISURE": "STROLL",
		"EXERCISE": "EXERCISE",
		"SOCIAL": "TALK",
		"COMMUNITY": "HELP",
		"HEALTH": "WAIT",
		"CRAFT": "CRAFT",
		"JOB_SEARCH": "READ",
		"VISIT_FRIEND": "TALK",
		"STUDY": "READ",
	}.get(activity, "IDLE")
