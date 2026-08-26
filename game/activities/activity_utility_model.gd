class_name ActivityUtilityModel
extends RefCounted

const CatalogScript := preload("res://activities/activity_catalog.gd")
const DAY_TICKS := 288
const START_CLOCK_TICK := 120
const DECISION_INTERVAL := 12
const TAG_RECOVERY := 1
const TAG_SOCIAL := 2
const TAG_PURPOSE := 4
const TAG_CURIOUS := 8
const TAG_MONEY := 16
const TAG_HEALTH := 32
const TAG_COMMUNITY := 64
const TAG_WORK := 128

var _specs: Array[ActivitySpec]
var _by_id: Dictionary = {}


func _init() -> void:
	_specs = CatalogScript.build_specs()
	for spec: ActivitySpec in _specs:
		_by_id[spec.id] = spec


func get_spec(activity_id: String) -> ActivitySpec:
	return _by_id.get(activity_id)


func get_activity_ids() -> Array[String]:
	var result: Array[String] = []
	for spec: ActivitySpec in _specs:
		result.append(spec.id)
	return result


func resolve(
	agent: Dictionary,
	at_tick: int,
	district_fields: Dictionary = {},
	include_explanation: bool = true
) -> Dictionary:
	var time_of_day := posmod(at_tick + START_CLOCK_TICK, DAY_TICKS)
	var obligation := _obligation_for(str(agent.schedule_kind), time_of_day)
	var selected_spec: ActivitySpec
	var selected_utility := -INF
	for spec: ActivitySpec in _specs:
		if not spec.is_in_time_window(time_of_day):
			continue
		if not spec.allows_schedule(str(agent.schedule_kind)):
			continue
		if obligation != "FREE" and spec.obligation != obligation:
			continue
		if obligation == "FREE" and spec.obligation not in ["FREE", "HOME"]:
			continue
		var utility := _utility_score(spec, agent, at_tick, district_fields)
		if obligation == "FREE" and spec.obligation == "HOME":
			utility -= 0.35
		if (
			selected_spec == null or utility > selected_utility
			or (utility == selected_utility and spec.id < selected_spec.id)
		):
			selected_spec = spec
			selected_utility = utility
	if selected_spec == null:
		var fallback_id := "WORK" if obligation == "WORK" else "HOME"
		return _state(_by_id[fallback_id], agent, at_tick, 0.0, ["fallback"])
	var reasons: Array[String] = []
	if include_explanation:
		reasons = _utility_reasons(selected_spec, agent, at_tick, district_fields)
	return _state(selected_spec, agent, at_tick, selected_utility, reasons)


func _obligation_for(schedule_kind: String, time_of_day: int) -> String:
	if time_of_day < 72 or time_of_day >= 264:
		return "HOME"
	match schedule_kind:
		"DAY_WORK":
			if time_of_day >= 84 and time_of_day < 204:
				return "WORK"
		"EVENING_SHIFT":
			if time_of_day >= 156 and time_of_day < 264:
				return "WORK"
		"FLEXIBLE":
			if time_of_day >= 120 and time_of_day < 192:
				return "WORK"
	return "FREE"


func _utility_score(
	spec: ActivitySpec, agent: Dictionary, at_tick: int, district_fields: Dictionary
) -> float:
	var stress := clampf(float(agent.get("stress", 0.25)), 0.0, 1.0)
	var wealth := clampf(float(agent.get("wealth", 0.5)), 0.0, 1.0)
	var activity := clampf(float(agent.get("activity_level", 0.5)), 0.0, 1.0)
	var sociability := _unit(int(agent.id), 17)
	var curiosity := _unit(int(agent.id), 31)
	var conscientiousness := _unit(int(agent.id), 47)
	var score := spec.base_utility
	if spec.tag_mask & TAG_RECOVERY:
		score += stress * 0.42 + (1.0 - activity) * 0.16
	if spec.tag_mask & TAG_SOCIAL:
		score += sociability * 0.31 + (0.08 if agent.local_contact_ids.size() > 0 else 0.0)
	if spec.tag_mask & TAG_PURPOSE:
		score += conscientiousness * 0.25 + activity * 0.12
	if spec.tag_mask & TAG_CURIOUS:
		score += curiosity * 0.30
	if spec.tag_mask & TAG_MONEY:
		score += (1.0 - wealth) * 0.24
	if spec.tag_mask & TAG_HEALTH:
		score += stress * 0.24
	if spec.tag_mask & TAG_COMMUNITY:
		score += float(district_fields.get("social_tension", 0.15)) * 0.22
	if spec.tag_mask & TAG_WORK:
		score += conscientiousness * 0.28
	if spec.money_cost_cents > 0:
		score -= (1.0 - wealth) * minf(0.28, float(spec.money_cost_cents) / 1000.0)
	var decision_slot := int(at_tick / DECISION_INTERVAL)
	# Stable individual affinity is deliberately strong enough that two agents
	# with similar needs can still choose different valid activities.
	var variation := (_unit(int(agent.id) + decision_slot * 97, spec.stable_hash) - 0.5) * 0.90
	score += variation
	return score


func _utility_reasons(
	spec: ActivitySpec, agent: Dictionary, at_tick: int, district_fields: Dictionary
) -> Array[String]:
	var reasons: Array[String] = ["base=%.2f" % spec.base_utility]
	var stress := clampf(float(agent.get("stress", 0.25)), 0.0, 1.0)
	var wealth := clampf(float(agent.get("wealth", 0.5)), 0.0, 1.0)
	var activity := clampf(float(agent.get("activity_level", 0.5)), 0.0, 1.0)
	if spec.tag_mask & TAG_RECOVERY:
		reasons.append("recovery=%.2f" % (stress * 0.42 + (1.0 - activity) * 0.16))
	if spec.tag_mask & TAG_SOCIAL:
		reasons.append("sociability=%.2f" % (_unit(int(agent.id), 17) * 0.31))
	if spec.tag_mask & TAG_PURPOSE:
		reasons.append("purpose=%.2f" % (_unit(int(agent.id), 47) * 0.25 + activity * 0.12))
	if spec.tag_mask & TAG_CURIOUS:
		reasons.append("curiosity=%.2f" % (_unit(int(agent.id), 31) * 0.30))
	if spec.tag_mask & TAG_MONEY:
		reasons.append("money_need=%.2f" % ((1.0 - wealth) * 0.24))
	if spec.tag_mask & TAG_COMMUNITY:
		reasons.append("district_tension=%.2f" % (float(district_fields.get("social_tension", 0.15)) * 0.22))
	var decision_slot := int(at_tick / DECISION_INTERVAL)
	var variation := (_unit(int(agent.id) + decision_slot * 97, spec.stable_hash) - 0.5) * 0.90
	reasons.append("affinity=%+.2f" % variation)
	return reasons


func _state(
	spec: ActivitySpec, agent: Dictionary, at_tick: int, utility: float, reasons: Array
) -> Dictionary:
	var place_id := int(agent.home_place_id)
	if spec.obligation == "WORK":
		place_id = 1 if int(agent.workplace_organization_id) == 1 else 2
	elif not spec.place_ids.is_empty():
		var decision_slot := int(at_tick / DECISION_INTERVAL)
		place_id = spec.place_ids[posmod(int(agent.id) + decision_slot, spec.place_ids.size())]
	return {
		"place_id": place_id,
		"activity": spec.id,
		"activity_label": spec.label,
		"utility": utility,
		"utility_reasons": reasons.duplicate(),
		"duration_ticks": spec.duration_ticks,
		"money_cost_cents": spec.money_cost_cents,
		"min_participants": spec.min_participants,
	}


func _unit(first: int, second: int) -> float:
	var mixed := posmod(first * 1103515245 + second * 12345 + 0x51f15e, 1_000_003)
	return float(mixed) / 1_000_002.0
