class_name AdaptivePopulationSystem
extends RefCounted

## Reversible representation controller for one canonical lightweight
## population. Tier membership changes; population records do not get cloned,
## so identity and conserved quantities have a single source of truth.

const TIER_AGGREGATE := "AGGREGATE"
const TIER_LIGHT_AGENT := "LIGHT_AGENT"
const TIER_PERSISTENT_NPC := "PERSISTENT_NPC"

var _population: RefCounted
var _story_persistent_count: int
var _light_agent_ids: Dictionary = {}
var _persistent_profiles: Dictionary = {}
var _transition_count: int = 0


func _init(
	population: RefCounted,
	story_persistent_count: int,
	initial_light_count: int = 60
) -> void:
	_population = population
	_story_persistent_count = story_persistent_count
	var ids: Array[int] = _population.get_agent_ids()
	for index in range(mini(initial_light_count, ids.size())):
		_light_agent_ids[ids[index]] = true
	_sync_population_detail_sets()


func refine_neighborhood(anchor_agent_id: int, max_depth: int = 1, limit: int = 60) -> Dictionary:
	if _population.get_agent_view(anchor_agent_id).is_empty():
		return {"ok": false, "error": "UNKNOWN_LIGHT_AGENT"}
	var previous_ids := _light_agent_ids.keys()
	_light_agent_ids.clear()
	var frontier: Array[Dictionary] = [{"id": anchor_agent_id, "depth": 0}]
	var visited: Dictionary = {}
	while not frontier.is_empty() and _light_agent_ids.size() < maxi(1, limit):
		var state: Dictionary = frontier.pop_front()
		var agent_id := int(state.id)
		if visited.has(agent_id):
			continue
		visited[agent_id] = true
		if not _persistent_profiles.has(agent_id):
			_light_agent_ids[agent_id] = true
		if int(state.depth) >= maxi(0, max_depth):
			continue
		var agent: Dictionary = _population.get_agent_view(agent_id)
		for contact_id: int in agent.get("local_contact_ids", []):
			if not visited.has(contact_id):
				frontier.append({"id": contact_id, "depth": int(state.depth) + 1})
	_transition_count += _symmetric_difference_size(previous_ids, _light_agent_ids.keys())
	_sync_population_detail_sets()
	return {
		"ok": true,
		"anchor_agent_id": anchor_agent_id,
		"refined_ids": _sorted_int_keys(_light_agent_ids),
		"state": snapshot(),
	}


func refine_all() -> Dictionary:
	var previous_ids := _light_agent_ids.keys()
	_light_agent_ids.clear()
	for agent_id: int in _population.get_agent_ids():
		if not _persistent_profiles.has(agent_id):
			_light_agent_ids[agent_id] = true
	_transition_count += _symmetric_difference_size(previous_ids, _light_agent_ids.keys())
	_sync_population_detail_sets()
	return {"ok": true, "state": snapshot()}


func promote_to_persistent(agent_id: int, reason: String = "PLAYER_RELEVANCE") -> Dictionary:
	var agent: Dictionary = _population.get_agent_view(agent_id)
	if agent.is_empty():
		return {"ok": false, "error": "UNKNOWN_LIGHT_AGENT"}
	if not _persistent_profiles.has(agent_id):
		_persistent_profiles[agent_id] = {
			"id": agent_id,
			"household_id": int(agent.household_id),
			"promoted_tick": int(_population.tick),
			"reason": reason,
		}
		_light_agent_ids.erase(agent_id)
		_transition_count += 1
		_sync_population_detail_sets()
	return {"ok": true, "profile": get_persistent_profile(agent_id), "state": snapshot()}


func release_persistent(agent_id: int, keep_as_light_agent: bool = false) -> Dictionary:
	if not _persistent_profiles.has(agent_id):
		return {"ok": false, "error": "NOT_ADAPTIVE_PERSISTENT"}
	_persistent_profiles.erase(agent_id)
	if keep_as_light_agent:
		_light_agent_ids[agent_id] = true
	_transition_count += 1
	_sync_population_detail_sets()
	return {"ok": true, "tier": get_tier(agent_id), "state": snapshot()}


func coarsen(agent_id: int) -> Dictionary:
	if _persistent_profiles.has(agent_id):
		return {"ok": false, "error": "PERSISTENT_REQUIRES_RELEASE"}
	if not _light_agent_ids.has(agent_id):
		return {"ok": true, "tier": get_tier(agent_id), "state": snapshot()}
	_light_agent_ids.erase(agent_id)
	_transition_count += 1
	_sync_population_detail_sets()
	return {"ok": true, "tier": TIER_AGGREGATE, "state": snapshot()}


func get_tier(agent_id: int) -> String:
	if _persistent_profiles.has(agent_id):
		return TIER_PERSISTENT_NPC
	if _light_agent_ids.has(agent_id):
		return TIER_LIGHT_AGENT
	return TIER_AGGREGATE if not _population.get_agent_view(agent_id).is_empty() else "UNKNOWN"


func get_persistent_profile(agent_id: int) -> Dictionary:
	if not _persistent_profiles.has(agent_id):
		return {}
	var profile: Dictionary = _persistent_profiles[agent_id].duplicate(true)
	profile["dynamic_state"] = _population.get_agent_view(agent_id)
	return profile


func snapshot() -> Dictionary:
	var aggregate_cohorts: Dictionary = {}
	var tier_totals := {
		TIER_AGGREGATE: _empty_totals(),
		TIER_LIGHT_AGENT: _empty_totals(),
		TIER_PERSISTENT_NPC: _empty_totals(),
	}
	for agent_id: int in _population.get_agent_ids():
		var agent: Dictionary = _population.get_agent_view(agent_id)
		var tier := get_tier(agent_id)
		_accumulate(tier_totals[tier], agent)
		if tier == TIER_AGGREGATE:
			var cohort_key := _cohort_key(agent)
			if not aggregate_cohorts.has(cohort_key):
				aggregate_cohorts[cohort_key] = _empty_totals()
			_accumulate(aggregate_cohorts[cohort_key], agent)
	var canonical: Dictionary = _population.snapshot()
	var represented := _sum_totals(tier_totals.values())
	var conservation := {
		"population": int(represented.count) == int(canonical.population),
		"employed": int(represented.employed) == int(canonical.employed),
		"unemployed": int(represented.unemployed) == int(canonical.unemployed),
		"money": int(represented.money_cents) == int(canonical.total_money_cents),
	}
	conservation["all"] = (
		bool(conservation.population) and bool(conservation.employed)
		and bool(conservation.unemployed) and bool(conservation.money)
	)
	return {
		"aggregate_count": int(tier_totals[TIER_AGGREGATE].count),
		"light_agent_count": int(tier_totals[TIER_LIGHT_AGENT].count),
		"promoted_persistent_count": int(tier_totals[TIER_PERSISTENT_NPC].count),
		"story_persistent_count": _story_persistent_count,
		"aggregate_cohorts": aggregate_cohorts,
		"tier_totals": tier_totals,
		"refined_light_ids": _sorted_int_keys(_light_agent_ids),
		"promoted_persistent_ids": _sorted_int_keys(_persistent_profiles),
		"transition_count": _transition_count,
		"conservation": conservation,
	}


func validate() -> Array[String]:
	var errors: Array[String] = _population.validate()
	for agent_id: int in _light_agent_ids:
		if _persistent_profiles.has(agent_id):
			errors.append("Agent %d exists in LIGHT_AGENT and PERSISTENT_NPC tiers" % agent_id)
		if _population.get_agent_view(agent_id).is_empty():
			errors.append("Unknown refined agent %d" % agent_id)
	for agent_id: int in _persistent_profiles:
		if _population.get_agent_view(agent_id).is_empty():
			errors.append("Unknown persistent agent %d" % agent_id)
	var state := snapshot()
	if not bool(state.conservation.all):
		errors.append("Adaptive tier conservation failed: %s" % state.conservation)
	return errors


func _cohort_key(agent: Dictionary) -> String:
	if str(agent.employment_status) == "UNEMPLOYED":
		return "UNEMPLOYED:%s" % str(agent.schedule_kind)
	return "WORKPLACE_%d:%s" % [
		int(agent.workplace_organization_id), str(agent.schedule_kind),
	]


func _sync_population_detail_sets() -> void:
	_population.set_detail_tiers(_light_agent_ids.keys(), _persistent_profiles.keys())


func _empty_totals() -> Dictionary:
	return {"count": 0, "employed": 0, "unemployed": 0, "money_cents": 0}


func _accumulate(totals: Dictionary, agent: Dictionary) -> void:
	totals["count"] = int(totals.count) + 1
	totals["money_cents"] = int(totals.money_cents) + int(agent.money_cents)
	if str(agent.employment_status) == "EMPLOYED":
		totals["employed"] = int(totals.employed) + 1
	else:
		totals["unemployed"] = int(totals.unemployed) + 1


func _sum_totals(parts: Array) -> Dictionary:
	var result := _empty_totals()
	for part: Dictionary in parts:
		result.count += int(part.count)
		result.employed += int(part.employed)
		result.unemployed += int(part.unemployed)
		result.money_cents += int(part.money_cents)
	return result


func _sorted_int_keys(dictionary: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in dictionary.keys():
		result.append(int(value))
	result.sort()
	return result


func _symmetric_difference_size(first: Array, second: Array) -> int:
	var first_set: Dictionary = {}
	var second_set: Dictionary = {}
	for value: Variant in first:
		first_set[int(value)] = true
	for value: Variant in second:
		second_set[int(value)] = true
	var count := 0
	for value: int in first_set:
		if not second_set.has(value):
			count += 1
	for value: int in second_set:
		if not first_set.has(value):
			count += 1
	return count
