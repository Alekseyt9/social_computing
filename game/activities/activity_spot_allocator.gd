class_name ActivitySpotAllocator
extends RefCounted

## Deterministically turns proposed activity spots into exclusive claims.
## The allocator is intentionally independent from Nodes/UI and accepts only
## calculated activity states, so the same seed and detail set produce the same
## queue regardless of query order.


func allocate(states: Array[Dictionary]) -> Dictionary:
	var groups: Dictionary = {}
	for source: Dictionary in states:
		var agent_id := int(source.get("agent_id", source.get("id", -1)))
		var place_id := int(source.get("destination_place_id", source.get("place_id", -1)))
		if agent_id < 0 or place_id < 0:
			continue
		if not groups.has(place_id):
			groups[place_id] = [] as Array[Dictionary]
		var candidate := source.duplicate(true)
		candidate["agent_id"] = agent_id
		candidate["place_id"] = place_id
		candidate["desired_spot"] = _desired_spot(candidate)
		candidate["priority"] = _priority(candidate)
		groups[place_id].append(candidate)

	var assignments: Dictionary = {}
	var place_metrics: Dictionary = {}
	var total_reserved := 0
	var total_queued := 0
	var place_ids: Array = groups.keys()
	place_ids.sort()
	for place_value: Variant in place_ids:
		var place_id := int(place_value)
		var candidates: Array[Dictionary] = groups[place_id]
		candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			if int(left.priority) == int(right.priority):
				return int(left.agent_id) < int(right.agent_id)
			return int(left.priority) < int(right.priority)
		)
		var capacity := 1
		for candidate: Dictionary in candidates:
			capacity = maxi(capacity, int(candidate.get("spot_capacity", 1)))
		var occupied: Dictionary = {}
		var queued_ids: Array[int] = []
		for candidate: Dictionary in candidates:
			var assigned_index := -1
			var desired := posmod(int(candidate.desired_spot), capacity)
			for probe in range(capacity):
				var spot_index := posmod(desired + probe, capacity)
				if not occupied.has(spot_index):
					assigned_index = spot_index
					occupied[spot_index] = int(candidate.agent_id)
					break
			if assigned_index >= 0:
				assignments[int(candidate.agent_id)] = {
					"admitted": true,
					"place_id": place_id,
					"spot_index": assigned_index,
					"activity_spot_id": "P%d-S%02d" % [place_id, assigned_index],
					"reservation_token": "%d:%d:%d" % [
						int(candidate.get("plan_started_tick", 0)), int(candidate.agent_id), assigned_index,
					],
					"queue_position": 0,
					"queue_length": maxi(0, candidates.size() - capacity),
				}
				total_reserved += 1
			else:
				queued_ids.append(int(candidate.agent_id))
		for queue_index in range(queued_ids.size()):
			assignments[queued_ids[queue_index]] = {
				"admitted": false,
				"place_id": place_id,
				"spot_index": -1,
				"activity_spot_id": "",
				"reservation_token": "",
				"queue_position": queue_index + 1,
				"queue_length": queued_ids.size(),
			}
			total_queued += 1
		place_metrics[place_id] = {
			"capacity": capacity,
			"demand": candidates.size(),
			"reserved": occupied.size(),
			"queued": queued_ids.size(),
		}
	return {
		"assignments": assignments,
		"metrics": {
			"reserved": total_reserved,
			"queued": total_queued,
			"places": place_metrics,
		},
	}


func _desired_spot(candidate: Dictionary) -> int:
	var spot_id := str(candidate.get("activity_spot_id", ""))
	var parts := spot_id.split("-S")
	if parts.size() > 1:
		return int(parts[1])
	return posmod(
		int(candidate.agent_id) * 1103 + int(candidate.get("plan_started_tick", 0)) * 31
		+ str(candidate.get("activity", "")).hash(),
		maxi(1, int(candidate.get("spot_capacity", 1)))
	)


func _priority(candidate: Dictionary) -> int:
	return posmod(
		int(candidate.agent_id) * 7919
		+ int(candidate.get("plan_started_tick", 0)) * 104729
		+ int(candidate.place_id) * 31337
		+ str(candidate.get("activity", "")).hash(),
		0x7fffffff
	)
