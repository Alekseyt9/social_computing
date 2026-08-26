class_name GoalSolver
extends RefCounted

## Internal bounded reachability solver. Results are for generation/tests/debug
## and must never be exposed as a quest solution in the player UI.


static func find_access_strategies(
	planning_state: Dictionary,
	max_depth: int = 5,
	beam_width: int = 20,
	top_k: int = 10
) -> Dictionary:
	var adjacency := _build_adjacency(planning_state.get("edges", []))
	var results: Array[Dictionary] = []
	for issuer: Dictionary in planning_state.get("access_issuers", []):
		var route := _bounded_path(
			int(planning_state.get("player_id", 1)),
			int(issuer.person_id),
			planning_state.get("locally_meetable_ids", []),
			adjacency,
			max_depth,
			beam_width
		)
		if route.is_empty():
			continue
		results.append({
			"strategy": _strategy_name(str(issuer.access_type)),
			"access_type": str(issuer.access_type),
			"issuer_person_id": int(issuer.person_id),
			"path": route.path,
			"score": route.score,
		})
	results.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.score) > float(right.score)
	)
	if results.size() > top_k:
		results.resize(top_k)
	return {
		"reachable": not results.is_empty(),
		"strategy_count": results.size(),
		"strategies": results,
		"search_limits": {
			"max_depth": max_depth,
			"beam_width": beam_width,
			"top_k": top_k,
		},
	}


static func _build_adjacency(edges: Array) -> Dictionary:
	var adjacency: Dictionary = {}
	for edge: Dictionary in edges:
		var source_id := int(edge.source_person_id)
		if not adjacency.has(source_id):
			adjacency[source_id] = []
		adjacency[source_id].append({
			"person_id": int(edge.target_person_id),
			"score": float(edge.trust) - float(edge.resentment) * 0.8,
		})
	return adjacency


static func _bounded_path(
	player_id: int,
	goal_person_id: int,
	locally_meetable_ids: Array,
	adjacency: Dictionary,
	max_depth: int,
	beam_width: int
) -> Dictionary:
	var frontier: Array[Dictionary] = []
	for meetable_value: Variant in locally_meetable_ids:
		var meetable_id := int(meetable_value)
		frontier.append({
			"person_id": meetable_id,
			"path": [player_id, meetable_id],
			"score": -0.12 if meetable_id != player_id else 0.0,
		})
	for _depth in range(1, max_depth + 1):
		var next_frontier: Array[Dictionary] = []
		for state: Dictionary in frontier:
			if int(state.person_id) == goal_person_id:
				return state
			for edge: Dictionary in adjacency.get(int(state.person_id), []):
				var next_id := int(edge.person_id)
				if next_id in state.path:
					continue
				var next_path: Array = state.path.duplicate()
				next_path.append(next_id)
				next_frontier.append({
					"person_id": next_id,
					"path": next_path,
					"score": float(state.score) + float(edge.score),
				})
		next_frontier.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return float(left.score) > float(right.score)
		)
		if next_frontier.size() > beam_width:
			next_frontier.resize(beam_width)
		frontier = next_frontier
		if frontier.is_empty():
			break
	return {}


static func _strategy_name(access_type: String) -> String:
	return {
		"GUEST_INVITATION": "PERSONAL_INVITATION",
		"MEDIA_PASS": "MEDIA_ACCESS",
		"CONTRACTOR_BADGE": "SERVICE_PROVIDER",
	}.get(access_type, "SOCIAL_CONNECTION")
