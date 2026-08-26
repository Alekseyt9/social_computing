class_name LazyHistorySystem
extends RefCounted

## Stores sparse state anchors for adaptive PersistentNPCs. Intermediate
## events are reconstructed only when somebody requests/discloses that history.

const DAY_TICKS := 288
const ROUTINE_INTERVAL := 7 * DAY_TICKS
const MAX_ANCHORS := 32

var _profiles: Dictionary = {}
var _next_history_event_id: int = 1


func register_person(person_id: int, at_tick: int, state: Dictionary) -> void:
	if _profiles.has(person_id):
		return
	_profiles[person_id] = {
		"person_id": person_id,
		"anchors": [_anchor(at_tick, state)],
		"canonical_events": [] as Array[Dictionary],
	}


func materialize_known_history(
	person_id: int, current_tick: int, current_state: Dictionary
) -> Array[Dictionary]:
	if not _profiles.has(person_id):
		register_person(person_id, current_tick, current_state)
		return []
	var profile: Dictionary = _profiles[person_id]
	var anchors: Array = profile.anchors
	var previous: Dictionary = anchors.back()
	if current_tick <= int(previous.tick):
		return []
	var current := _anchor(current_tick, current_state)
	var reconstructed := _reconstruct_between(person_id, previous, current)
	for event: Dictionary in reconstructed:
		event["history_event_id"] = _next_history_event_id
		event["canonical"] = true
		event["canonical_fact_id"] = -1
		_next_history_event_id += 1
		profile.canonical_events.append(event.duplicate(true))
	anchors.append(current)
	if anchors.size() > MAX_ANCHORS:
		anchors.remove_at(1) # Preserve the origin anchor and recent history.
	profile["anchors"] = anchors
	_profiles[person_id] = profile
	return reconstructed


func attach_canonical_fact(person_id: int, history_event_id: int, fact_id: int) -> void:
	if not _profiles.has(person_id):
		return
	var profile: Dictionary = _profiles[person_id]
	var events: Array = profile.canonical_events
	for index in range(events.size()):
		var event: Dictionary = events[index]
		if int(event.history_event_id) == history_event_id:
			event["canonical_fact_id"] = fact_id
			events[index] = event
			break
	profile["canonical_events"] = events
	_profiles[person_id] = profile


func get_profile(person_id: int) -> Dictionary:
	return _profiles.get(person_id, {}).duplicate(true)


func validate() -> Array[String]:
	var errors: Array[String] = []
	for person_id: int in _profiles:
		var profile: Dictionary = _profiles[person_id]
		var previous_tick := -1
		for anchor: Dictionary in profile.anchors:
			if int(anchor.tick) <= previous_tick:
				errors.append("History anchors are not ordered for %d" % person_id)
			previous_tick = int(anchor.tick)
		for event: Dictionary in profile.canonical_events:
			if not bool(event.get("canonical", false)):
				errors.append("Materialized history is not canonical for %d" % person_id)
			if int(event.tick) < int(profile.anchors[0].tick) or int(event.tick) > previous_tick:
				errors.append("History event is outside anchors for %d" % person_id)
	return errors


func _reconstruct_between(
	person_id: int, previous: Dictionary, current: Dictionary
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var elapsed := int(current.tick) - int(previous.tick)
	var midpoint := int(previous.tick) + maxi(1, int(elapsed / 2))
	var was_employed := str(previous.employment_status) == "EMPLOYED"
	var is_employed := str(current.employment_status) == "EMPLOYED"
	if was_employed != is_employed:
		events.append(_event(
			person_id,
			"JOB_STARTED" if is_employed else "JOB_LOST",
			midpoint,
			{"from_workplace": int(previous.workplace_id), "to_workplace": int(current.workplace_id)}
		))
	elif is_employed and int(previous.workplace_id) != int(current.workplace_id):
		events.append(_event(person_id, "JOB_CHANGED", midpoint, {
			"from_workplace": int(previous.workplace_id),
			"to_workplace": int(current.workplace_id),
		}))
	var money_delta := int(current.money_cents) - int(previous.money_cents)
	if absi(money_delta) >= 500:
		events.append(_event(person_id, (
			"FINANCES_IMPROVED" if money_delta > 0 else "FINANCIAL_PRESSURE"
		), int(previous.tick) + maxi(1, int(elapsed * 3 / 4)), {
			"money_delta_cents": money_delta,
		}))
	if events.is_empty() and elapsed >= ROUTINE_INTERVAL:
		events.append(_event(person_id, "ROUTINE_CONTINUED", midpoint, {
			"days": int(elapsed / DAY_TICKS),
			"employment_status": str(current.employment_status),
			"workplace_id": int(current.workplace_id),
			"schedule_kind": str(current.schedule_kind),
		}))
	events.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.tick) == int(right.tick):
			return str(left.type) < str(right.type)
		return int(left.tick) < int(right.tick)
	)
	return events


func _anchor(at_tick: int, state: Dictionary) -> Dictionary:
	return {
		"tick": at_tick,
		"employment_status": str(state.get("employment_status", "UNEMPLOYED")),
		"workplace_id": int(state.get("workplace_organization_id", 0)),
		"money_cents": int(state.get("money_cents", 0)),
		"schedule_kind": str(state.get("schedule_kind", "UNEMPLOYED")),
		"rumor_count": state.get("rumor_ids", []).size(),
	}


func _event(
	person_id: int, event_type: String, at_tick: int, details: Dictionary
) -> Dictionary:
	return {
		"person_id": person_id,
		"type": event_type,
		"tick": at_tick,
		"details": details.duplicate(true),
	}
