class_name LightPopulationSimulation
extends RefCounted

const HouseholdScript := preload("res://core/model/household.gd")
const SocialGroupScript := preload("res://core/model/social_group.gd")
const LightScheduleScript := preload("res://agents/light_schedule.gd")
const PackedAgentStoreScript := preload("res://adaptive/packed_light_agent_store.gd")
const GpuPopulationBackendScript := preload("res://ms6/gpu_population_backend.gd")
const SpatialNeighborhoodBackendScript := preload("res://ms6/spatial_neighborhood_backend.gd")
const CohortAggregateBackendScript := preload("res://ms6/cohort_aggregate_backend.gd")
const ActivityUtilityModelScript := preload("res://activities/activity_utility_model.gd")

const FIRST_AGENT_ID := 10_000
const DEFAULT_POPULATION := 1_200
const GOSSIP_INTERVAL := 12
const MONEY_INTERVAL := 24
const CONTACT_TARGET := 6
const MS6_GPU_AGENT_THRESHOLD := 1024
const MS6_PARITY_TOLERANCE := 0.00001
const MS6_FULL_PARITY_INTERVAL := 7
const MS6_SPATIAL_INTERVAL := 144
const MS6_SPATIAL_RADIUS := 72.0
const RUMOR_TOPICS := [
	"вакансии в Aurora", "изменения смен в кафе", "закрытое мероприятие Aurora",
	"новый подряд на обслуживание", "рост цен в районе", "встреча журналистов",
	"соседская взаимопомощь", "проверка безопасности", "новый городской проект",
	"конфликт внутри команды", "поиск временных работников", "местный благотворительный сбор",
]
const _LCG_MULTIPLIER := 1_103_515_245
const _LCG_INCREMENT := 12_345
const _LCG_MASK := 0x7fffffff

var tick: int = 0
var _random_state: int
var _store: RefCounted
var _households: Dictionary = {}
var _groups: Dictionary = {}
var _job_change_count: int = 0
var _gossip_transfer_count: int = 0
var _money_transfer_count: int = 0
var _contextual_activity_count: int = 0
var _initial_total_money_cents: int = 0
var _pending_events: Array[Dictionary] = []
var _detailed_agent_steps: int = 0
var _aggregate_agent_steps: int = 0
var _detailed_agent_ids: Dictionary = {}
var _social_field_influence: Dictionary = {}
var _gpu_backend: RefCounted
var _spatial_backend: RefCounted
var _cohort_backend: RefCounted
var _activity_model: RefCounted
var _ms6_update_count := 0
var _ms6_backend_status := "NOT_RUN"
var _ms6_max_error := 0.0
var _ms6_summary_max_error := 0.0
var _ms6_last_elapsed_usec := 0
var _ms6_gpu_disabled := false
var _ms6_gpu_unavailable := false
var _ms6_prefer_gpu := true
var _spatial_neighbors := PackedInt32Array()
var _ms6_spatial_update_count := 0
var _ms6_spatial_status := "NOT_RUN"
var _ms6_spatial_mismatch_count := 0
var _ms6_spatial_gpu_disabled := false
var _ms6_spatial_gpu_unavailable := false
var _spatial_gossip_source_count := 0
var _latest_cohort_summary: Dictionary = {}
var _ms6_cohort_update_count := 0
var _ms6_cohort_status := "NOT_RUN"
var _ms6_cohort_max_error := 0.0
var _ms6_cohort_gpu_disabled := false
var _ms6_cohort_gpu_unavailable := false


func _init(initial_seed: int, population_size: int = DEFAULT_POPULATION) -> void:
	_random_state = (initial_seed ^ 0x51f15e) & _LCG_MASK
	_store = PackedAgentStoreScript.new(FIRST_AGENT_ID, maxi(1, population_size))
	_gpu_backend = GpuPopulationBackendScript.new()
	_spatial_backend = SpatialNeighborhoodBackendScript.new()
	_cohort_backend = CohortAggregateBackendScript.new()
	_activity_model = ActivityUtilityModelScript.new()
	_build_groups()
	_build_population(maxi(1, population_size))
	_build_local_contacts()
	_update_locations()
	_initial_total_money_cents = _total_money_cents()


func advance(ticks_to_advance: int) -> void:
	for _index in range(maxi(0, ticks_to_advance)):
		tick += 1
		if tick % GOSSIP_INTERVAL == 0:
			if tick % MS6_SPATIAL_INTERVAL == 0:
				run_ms6_spatial_batch(_ms6_prefer_gpu)
			_propagate_gossip()
			_update_locations()
		if tick % MONEY_INTERVAL == 0:
			_transfer_money_between_contacts()
		if tick % LightScheduleScript.DAY_TICKS == 0:
			run_ms6_feedback_batch(_ms6_prefer_gpu)
			run_ms6_cohort_batch(_ms6_prefer_gpu)
			_update_employment()


func snapshot() -> Dictionary:
	var employed := 0
	var location_counts: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0}
	var contact_edges := 0
	var rumor_edges := 0
	var activity_distribution: Dictionary = {}
	for agent_id: int in get_agent_ids():
		var agent: Dictionary = get_agent_view(agent_id)
		if str(agent.employment_status) == "EMPLOYED":
			employed += 1
		var place_id := int(agent.current_place_id)
		location_counts[place_id] = int(location_counts.get(place_id, 0)) + 1
		contact_edges += agent.local_contact_ids.size()
		rumor_edges += agent.rumor_ids.size()
		var activity_id := str(agent.current_activity)
		activity_distribution[activity_id] = int(activity_distribution.get(activity_id, 0)) + 1
	var total_money := _total_money_cents()
	return {
		"tick": tick,
		"population": _store.size(),
		"employed": employed,
		"unemployed": _store.size() - employed,
		"households": _households.size(),
		"workplaces": 2,
		"social_groups": _groups.size(),
		"local_contact_edges": contact_edges,
		"rumor_knowledge_edges": rumor_edges,
		"gossip_transfers": _gossip_transfer_count,
		"spatial_gossip_sources": _spatial_gossip_source_count,
		"job_changes": _job_change_count,
		"money_transfers": _money_transfer_count,
		"contextual_activities": _contextual_activity_count,
		"total_money_cents": total_money,
		"money_conserved": total_money == _initial_total_money_cents,
		"detailed_agent_steps": _detailed_agent_steps,
		"aggregate_agent_steps": _aggregate_agent_steps,
		"storage": _store.storage_metrics(),
		"feedback": _current_feedback_summary(),
		"activity_model": {
			"kind": "UTILITY_BASED",
			"catalog_size": _activity_model.get_activity_ids().size(),
			"decision_interval_ticks": 12,
			"distribution": activity_distribution,
		},
		"location_counts": location_counts,
		"checksum": "%08x" % (
			_random_state ^ tick ^ (_store.size() << 4)
			^ (employed << 11) ^ (rumor_edges << 17) ^ _job_change_count
		),
	}


func get_ms6_metrics() -> Dictionary:
	return {
		"status": _ms6_backend_status,
		"update_count": _ms6_update_count,
		"max_error": _ms6_max_error,
		"summary_max_error": _ms6_summary_max_error,
		"last_elapsed_usec": _ms6_last_elapsed_usec,
		"gpu_disabled": _ms6_gpu_disabled,
		"gpu_unavailable": _ms6_gpu_unavailable,
		"agent_threshold": MS6_GPU_AGENT_THRESHOLD,
		"parity_tolerance": MS6_PARITY_TOLERANCE,
		"full_parity_interval": MS6_FULL_PARITY_INTERVAL,
		"feedback": _current_feedback_summary(),
		"gpu_backend": _gpu_backend.get_metrics(),
		"spatial": get_ms6_spatial_metrics(),
		"cohorts": get_ms6_cohort_metrics(),
	}


func close_ms6_backend() -> void:
	_gpu_backend.close()
	_spatial_backend.close()
	_cohort_backend.close()


func set_ms6_gpu_enabled(enabled: bool) -> void:
	_ms6_prefer_gpu = enabled


func get_ms6_spatial_metrics() -> Dictionary:
	return {
		"status": _ms6_spatial_status,
		"update_count": _ms6_spatial_update_count,
		"mismatch_count": _ms6_spatial_mismatch_count,
		"gpu_disabled": _ms6_spatial_gpu_disabled,
		"gpu_unavailable": _ms6_spatial_gpu_unavailable,
		"interval": MS6_SPATIAL_INTERVAL,
		"radius": MS6_SPATIAL_RADIUS,
		"neighbor_count": _spatial_neighbor_count(),
		"gossip_sources": _spatial_gossip_source_count,
		"backend": _spatial_backend.get_metrics(),
	}


func get_ms6_cohort_metrics() -> Dictionary:
	return {
		"status": _ms6_cohort_status,
		"update_count": _ms6_cohort_update_count,
		"max_error": _ms6_cohort_max_error,
		"gpu_disabled": _ms6_cohort_gpu_disabled,
		"gpu_unavailable": _ms6_cohort_gpu_unavailable,
		"active_cohorts": int(_latest_cohort_summary.get("active_cohorts", 0)),
		"summary": _latest_cohort_summary.duplicate(true),
		"backend": _cohort_backend.get_metrics(),
	}


func run_ms6_spatial_batch(prefer_gpu: bool = true) -> Dictionary:
	var place_ids := PackedInt32Array()
	place_ids.resize(_store.size())
	for index in range(_store.size()):
		var agent_id := FIRST_AGENT_ID + index
		var agent: Dictionary = _store.get_agent(agent_id)
		place_ids[index] = int(
			_activity_model.resolve(agent, tick, _social_field_influence, false).place_id
		)
	var positions: PackedFloat32Array = _store.export_spatial_positions_for_places(place_ids)
	var parameters := {
		"world_width": 2400.0,
		"world_height": 1450.0,
		"cell_size": 96.0,
		"radius": MS6_SPATIAL_RADIUS,
	}
	var cpu: Dictionary = _spatial_backend.find_nearest(positions, parameters, false)
	if not bool(cpu.get("ok", false)):
		_ms6_spatial_status = "CPU_ERROR"
		return {"ok": false, "error": "CPU_SPATIAL_REFERENCE_FAILED"}
	var should_attempt_gpu: bool = (
		prefer_gpu and not _ms6_spatial_gpu_disabled and not _ms6_spatial_gpu_unavailable
		and _store.size() >= MS6_GPU_AGENT_THRESHOLD
	)
	var preferred: Dictionary = (
		_spatial_backend.find_nearest(positions, parameters, true)
		if should_attempt_gpu else cpu
	)
	var mismatch_count := 0
	if bool(preferred.get("ok", false)) and str(preferred.backend) == "GPU":
		mismatch_count = _neighbor_mismatch_count(cpu.neighbors, preferred.neighbors)
	_ms6_spatial_mismatch_count = mismatch_count
	if str(preferred.get("backend", "")) == "GPU" and mismatch_count == 0:
		_ms6_spatial_status = "GPU_SHADOW_VERIFIED"
	elif str(preferred.get("backend", "")) == "GPU":
		_ms6_spatial_status = "GPU_PARITY_FAILED"
		_ms6_spatial_gpu_disabled = true
	else:
		_ms6_spatial_status = (
			"CPU_FALLBACK"
			if prefer_gpu and (should_attempt_gpu or _ms6_spatial_gpu_unavailable)
			else "CPU"
		)
		if should_attempt_gpu and not str(preferred.get("gpu_error", "")).is_empty():
			_ms6_spatial_gpu_unavailable = true
	_spatial_neighbors = cpu.neighbors
	_ms6_spatial_update_count += 1
	return {
		"ok": true,
		"status": _ms6_spatial_status,
		"agent_count": _store.size(),
		"neighbor_count": int(cpu.neighbor_count),
		"checksum": str(cpu.checksum),
		"mismatch_count": mismatch_count,
		"gpu_attempted": should_attempt_gpu,
		"gpu_error": str(preferred.get("gpu_error", "")),
		"canonical_backend": "CPU",
	}


func run_ms6_cohort_batch(prefer_gpu: bool = true) -> Dictionary:
	var fields: PackedFloat32Array = _store.export_feedback_buffer()
	var codes: PackedInt32Array = _store.export_feedback_cohort_codes()
	var cpu: Dictionary = _cohort_backend.reduce(fields, codes, false)
	if not bool(cpu.get("ok", false)):
		_ms6_cohort_status = "CPU_ERROR"
		return {"ok": false, "error": "CPU_COHORT_REFERENCE_FAILED"}
	var should_attempt_gpu: bool = (
		prefer_gpu and not _ms6_cohort_gpu_disabled and not _ms6_cohort_gpu_unavailable
		and _store.size() >= MS6_GPU_AGENT_THRESHOLD
	)
	var preferred: Dictionary = (
		_cohort_backend.reduce(fields, codes, true) if should_attempt_gpu else cpu
	)
	var maximum_error := 0.0
	if str(preferred.get("backend", "")) == "GPU":
		maximum_error = _maximum_cohort_error(cpu.values, preferred.values)
	_ms6_cohort_max_error = maximum_error
	if str(preferred.get("backend", "")) == "GPU" and maximum_error <= MS6_PARITY_TOLERANCE:
		_ms6_cohort_status = "GPU_SHADOW_VERIFIED"
	elif str(preferred.get("backend", "")) == "GPU":
		_ms6_cohort_status = "GPU_PARITY_FAILED"
		_ms6_cohort_gpu_disabled = true
	else:
		_ms6_cohort_status = (
			"CPU_FALLBACK"
			if prefer_gpu and (should_attempt_gpu or _ms6_cohort_gpu_unavailable)
			else "CPU"
		)
		if should_attempt_gpu and not str(preferred.get("gpu_error", "")).is_empty():
			_ms6_cohort_gpu_unavailable = true
	_latest_cohort_summary = cpu.summary.duplicate(true)
	_latest_cohort_summary["active_cohorts"] = int(cpu.active_cohorts)
	_ms6_cohort_update_count += 1
	return {
		"ok": true,
		"status": _ms6_cohort_status,
		"agent_count": int(cpu.summary.agent_count),
		"active_cohorts": int(cpu.active_cohorts),
		"max_error": maximum_error,
		"gpu_attempted": should_attempt_gpu,
		"gpu_error": str(preferred.get("gpu_error", "")),
		"canonical_backend": "CPU",
		"summary": _latest_cohort_summary.duplicate(true),
	}


func run_ms6_feedback_batch(prefer_gpu: bool = true) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var input: PackedFloat32Array = _store.export_feedback_buffer()
	var parameters := _feedback_parameters()
	var cpu: Dictionary = _gpu_backend.run_feedback(input, parameters, false)
	if not bool(cpu.get("ok", false)):
		_ms6_backend_status = "CPU_ERROR"
		return {"ok": false, "error": "CPU_REFERENCE_FAILED"}
	var should_attempt_gpu: bool = (
		prefer_gpu and not _ms6_gpu_disabled and not _ms6_gpu_unavailable
		and _store.size() >= MS6_GPU_AGENT_THRESHOLD
	)
	var parity_due := _ms6_update_count % MS6_FULL_PARITY_INTERVAL == 0
	var upload_range: Dictionary = (
		{} if parity_due else {"ranges": _store.feedback_dirty_ranges()}
	)
	var preferred: Dictionary = (
		_gpu_backend.run_feedback(input, parameters, true, parity_due, upload_range)
		if should_attempt_gpu else cpu
	)
	var gpu_completed := bool(preferred.get("ok", false)) and str(preferred.backend) == "GPU"
	var maximum_error := 0.0
	if gpu_completed and parity_due:
		maximum_error = _maximum_buffer_error(cpu.values, preferred.values)
	var summary_error := _maximum_summary_error(cpu.summary, preferred.get("summary", {}))
	_ms6_max_error = maximum_error
	_ms6_summary_max_error = summary_error
	if not bool(preferred.get("ok", false)):
		_ms6_backend_status = "CPU_FALLBACK"
	elif (
		gpu_completed and parity_due and maximum_error <= MS6_PARITY_TOLERANCE
		and summary_error <= MS6_PARITY_TOLERANCE
	):
		_ms6_backend_status = "GPU_SHADOW_VERIFIED"
		_store.clear_feedback_dirty_range()
	elif gpu_completed and parity_due:
		_ms6_backend_status = "GPU_PARITY_FAILED"
		_ms6_gpu_disabled = true
	elif gpu_completed and summary_error <= MS6_PARITY_TOLERANCE:
		_ms6_backend_status = "GPU_SHADOW_SUMMARY"
		_store.clear_feedback_dirty_range()
	elif gpu_completed:
		_ms6_backend_status = "GPU_SUMMARY_FAILED"
		_ms6_gpu_disabled = true
	else:
		_ms6_backend_status = (
			"CPU_FALLBACK" if prefer_gpu and (should_attempt_gpu or _ms6_gpu_unavailable)
			else "CPU"
		)
		if should_attempt_gpu and not str(preferred.get("gpu_error", "")).is_empty():
			_ms6_gpu_unavailable = true
	if not _store.apply_feedback_buffer(cpu.values):
		_ms6_backend_status = "APPLY_FAILED"
		return {"ok": false, "error": "PACKED_BUFFER_APPLY_FAILED"}
	_ms6_update_count += 1
	_ms6_last_elapsed_usec = Time.get_ticks_usec() - started_usec
	return {
		"ok": true,
		"status": _ms6_backend_status,
		"agent_count": _store.size(),
		"max_error": maximum_error,
		"summary_max_error": summary_error,
		"gpu_attempted": should_attempt_gpu,
		"parity_performed": should_attempt_gpu and parity_due,
		"gpu_error": str(preferred.get("gpu_error", "")),
		"uploaded_agent_count": int(preferred.get("uploaded_agent_count", 0)),
		"canonical_backend": "CPU",
		"elapsed_usec": _ms6_last_elapsed_usec,
		"feedback": _store.feedback_summary(),
	}


func _maximum_summary_error(cpu_summary: Dictionary, gpu_summary: Dictionary) -> float:
	if gpu_summary.is_empty():
		return 0.0
	var maximum_error := 0.0
	for key in ["average_wealth", "average_stress", "average_spending", "average_activity"]:
		maximum_error = maxf(
			maximum_error,
			absf(float(cpu_summary.get(key, 0.0)) - float(gpu_summary.get(key, 0.0)))
		)
	return maximum_error


func _maximum_cohort_error(left: PackedFloat32Array, right: PackedFloat32Array) -> float:
	if left.size() != right.size():
		return INF
	var maximum_error := 0.0
	for index in range(left.size()):
		var divisor := 1.0
		if index % 5 != 4:
			divisor = maxf(1.0, float(left[index - index % 5 + 4]))
		maximum_error = maxf(
			maximum_error, absf(float(left[index]) - float(right[index])) / divisor
		)
	return maximum_error


func _current_feedback_summary() -> Dictionary:
	var result: Dictionary = _store.feedback_summary()
	if _latest_cohort_summary.is_empty():
		return result
	for key in ["average_wealth", "average_stress", "average_spending", "average_activity"]:
		result[key] = float(_latest_cohort_summary.get(key, result[key]))
	return result


func _neighbor_mismatch_count(left: PackedInt32Array, right: PackedInt32Array) -> int:
	if left.size() != right.size():
		return maxi(left.size(), right.size())
	var count := 0
	for index in range(left.size()):
		if left[index] != right[index]:
			count += 1
	return count


func _spatial_neighbor_count() -> int:
	var count := 0
	for neighbor_index in _spatial_neighbors:
		if neighbor_index >= 0:
			count += 1
	return count


func get_agent_view(agent_id: int) -> Dictionary:
	var agent: Dictionary = _store.get_agent(agent_id)
	if agent.is_empty():
		return agent
	var schedule_state: Dictionary = _activity_model.resolve(
		agent, tick, _social_field_influence, false
	)
	agent["current_place_id"] = int(schedule_state.place_id)
	agent["current_activity"] = str(schedule_state.activity)
	agent["activity_label"] = str(schedule_state.activity_label)
	return agent


func get_agent_schedule_state(agent_id: int, at_tick: int) -> Dictionary:
	var agent: Dictionary = _store.get_agent(agent_id)
	if agent.is_empty():
		return {}
	var state: Dictionary = _activity_model.resolve(agent, at_tick, _social_field_influence, true)
	state["tick"] = at_tick
	return state


func get_agent_ids() -> Array[int]:
	return _store.get_agent_ids()


func get_agent_ids_at_place(place_id: int) -> Array[int]:
	var result: Array[int] = []
	for agent_id: int in get_agent_ids():
		if int(get_agent_view(agent_id).current_place_id) == place_id:
			result.append(agent_id)
	result.sort()
	return result


func drain_events() -> Array[Dictionary]:
	var result := _pending_events.duplicate(true)
	_pending_events.clear()
	return result


func set_detail_tiers(light_agent_ids: Array, persistent_agent_ids: Array) -> void:
	_detailed_agent_ids.clear()
	for value: Variant in light_agent_ids:
		_detailed_agent_ids[int(value)] = true
	for value: Variant in persistent_agent_ids:
		_detailed_agent_ids[int(value)] = true


func set_social_field_influence(fields: Dictionary) -> void:
	_social_field_influence = fields.duplicate(true)


func resolve_contextual_activity(agent_id: int, activity: String) -> Dictionary:
	var agent: Dictionary = get_agent_view(agent_id)
	if agent.is_empty():
		return {"ok": false, "error": "UNKNOWN_LIGHT_AGENT"}
	if str(agent.current_activity) != activity:
		return {
			"ok": false,
			"error": "ACTIVITY_CHANGED",
			"current_activity": str(agent.current_activity),
		}
	var money_delta := 0
	var transfer_amount := 0
	var canonical_agent: Dictionary = _store.get_agent(agent_id)
	var spec: ActivitySpec = _activity_model.get_spec(activity)
	if spec != null and spec.money_cost_cents > 0 and not canonical_agent.local_contact_ids.is_empty():
		var payer: Dictionary = canonical_agent
		var receiver_id := int(payer.local_contact_ids[
			posmod(agent_id + tick + activity.hash(), payer.local_contact_ids.size())
		])
		var receiver: Dictionary = _store.get_agent(receiver_id)
		var desired_amount := spec.money_cost_cents + posmod(agent_id * 31 + tick * 17, 61) - 30
		desired_amount = int(round(
			float(desired_amount) * (0.65 + float(payer.get("spending", 0.4)) * 0.70)
		))
		transfer_amount = mini(desired_amount, maxi(0, int(payer.money_cents)))
		if transfer_amount > 0:
			payer["money_cents"] = int(payer.money_cents) - transfer_amount
			receiver["money_cents"] = int(receiver.money_cents) + transfer_amount
			_sync_financial_feedback(payer)
			_sync_financial_feedback(receiver)
			_store.update_agent(payer)
			_store.update_agent(receiver)
			canonical_agent = payer
			_money_transfer_count += 1
			money_delta = -transfer_amount
	if spec != null:
		canonical_agent["stress"] = clampf(
			float(canonical_agent.get("stress", 0.2)) + spec.stress_delta, 0.0, 1.0
		)
		canonical_agent["activity_level"] = clampf(
			float(canonical_agent.get("activity_level", 0.5)) + spec.activity_delta,
			0.0, 1.0
		)
		_store.update_agent(canonical_agent)
	_contextual_activity_count += 1
	return {
		"ok": true,
		"agent_id": agent_id,
		"activity": activity,
		"activity_label": str(agent.activity_label),
		"place_id": int(agent.current_place_id),
		"money_delta_cents": money_delta,
		"transfer_amount_cents": transfer_amount,
		"stress_delta": spec.stress_delta if spec != null else 0.0,
		"activity_delta": spec.activity_delta if spec != null else 0.0,
	}


func validate() -> Array[String]:
	var errors: Array[String] = []
	for agent_id: int in get_agent_ids():
		var agent: Dictionary = _store.get_agent(agent_id)
		var household_id := int(agent.household_id)
		if not _households.has(household_id):
			errors.append("Agent %d has invalid household %d" % [agent_id, household_id])
		var workplace_id := int(agent.workplace_organization_id)
		if workplace_id not in [0, 1, 2]:
			errors.append("Agent %d has invalid workplace %d" % [agent_id, workplace_id])
		for group_id: int in agent.social_group_ids:
			if not _groups.has(group_id):
				errors.append("Agent %d has invalid group %d" % [agent_id, group_id])
		for contact_id: int in agent.local_contact_ids:
			if contact_id == agent_id or not _store.has(contact_id):
				errors.append("Agent %d has invalid local contact %d" % [agent_id, contact_id])
		if errors.size() >= 20:
			break
	return errors


func _build_groups() -> void:
	_groups[1] = SocialGroupScript.new(1, "Aurora professional circle", "PROFESSIONAL")
	_groups[2] = SocialGroupScript.new(2, "Corner Cafe regulars", "LOCAL")
	_groups[3] = SocialGroupScript.new(3, "Mutual aid network", "SUPPORT")
	_groups[4] = SocialGroupScript.new(4, "District families", "HOUSEHOLD")


func _build_population(population_size: int) -> void:
	var household_count := int(ceil(float(population_size) / 2.6))
	for household_id in range(1, household_count + 1):
		_households[household_id] = HouseholdScript.new(household_id, 3)
	for index in range(population_size):
		var agent_id := FIRST_AGENT_ID + index
		var household_id := 1 + int(float(index) * float(household_count) / float(population_size))
		var employed := (_next_random_int() % 100) < 84
		var workplace_id := 0
		if employed:
			workplace_id = 1 if (_next_random_int() % 100) < 36 else 2
		var schedule_kind := "UNEMPLOYED"
		if employed:
			var schedule_roll := _next_random_int() % 100
			schedule_kind = "DAY_WORK" if schedule_roll < 68 else (
				"EVENING_SHIFT" if schedule_roll < 88 else "FLEXIBLE"
			)
		var group_ids: Array[int] = [4 if household_id % 3 == 0 else 3]
		group_ids.append(1 if workplace_id == 1 else 2)
		var rumors: Array[int] = []
		if index < 12:
			rumors.append(index + 1)
		var money_cents := 4_000 + (_next_random_int() % 196_001)
		var wealth := clampf(float(money_cents) / 200_000.0, 0.02, 1.0)
		var stress := clampf(
			(0.16 if employed else 0.48) + float(agent_id % 11) * 0.012,
			0.0, 1.0
		)
		var spending := clampf(wealth * (1.0 - stress * 0.60), 0.0, 1.0)
		var agent := {
			"id": agent_id,
			"household_id": household_id,
			"home_place_id": 3,
			"workplace_organization_id": workplace_id,
			"employment_status": "EMPLOYED" if employed else "UNEMPLOYED",
			"schedule_kind": schedule_kind,
			"current_place_id": 3,
			"money_cents": money_cents,
			"wealth": wealth,
			"stress": stress,
			"spending": spending,
			"activity_level": 0.68 if employed else 0.42,
			"social_group_ids": group_ids,
			"local_contact_ids": [] as Array[int],
			"rumor_ids": rumors,
		}
		_store.add_agent(agent)
		_households[household_id].add_member(agent_id)
		for group_id: int in group_ids:
			_groups[group_id].add_member(agent_id)


func _build_local_contacts() -> void:
	var population_size: int = _store.size()
	for agent_id: int in get_agent_ids():
		var agent: Dictionary = _store.get_agent(agent_id)
		var contacts: Array[int] = []
		var household: RefCounted = _households[int(agent.household_id)]
		for member_id: int in household.member_ids:
			if member_id != agent_id and member_id not in contacts:
				contacts.append(member_id)
		for offset in [1, -1, 7, -7, 31, -31, 97, -97]:
			if contacts.size() >= CONTACT_TARGET:
				break
			var normalized_index := posmod((agent_id - FIRST_AGENT_ID) + offset, population_size)
			var contact_id := FIRST_AGENT_ID + normalized_index
			if contact_id != agent_id and contact_id not in contacts:
				contacts.append(contact_id)
		agent["local_contact_ids"] = contacts
		_store.update_agent(agent)


func _update_locations() -> void:
	# Aggregate locations are derived from schedule cohorts on demand. Only the
	# detailed working set receives a materialized location update.
	for agent_id: int in _detail_agent_ids():
		var agent: Dictionary = get_agent_view(agent_id)
		var workplace_id := int(agent.workplace_organization_id)
		var work_place_id := 1 if workplace_id == 1 else 2
		agent["current_place_id"] = LightScheduleScript.resolve_place(
			str(agent.schedule_kind), tick, int(agent.home_place_id), work_place_id
		)
		_store.update_agent(agent)


func _propagate_gossip() -> void:
	var transfers_before := _gossip_transfer_count
	var candidates := _detail_agent_ids()
	var aggregate_candidates: Array[int] = []
	if tick % 72 == 0:
		aggregate_candidates = _cohort_sample_ids(6)
		candidates.append_array(aggregate_candidates)
	for agent_id: int in candidates:
		if _detailed_agent_ids.has(agent_id):
			_detailed_agent_steps += 1
		else:
			_aggregate_agent_steps += 1
		var agent: Dictionary = _store.get_agent(agent_id)
		var source_id := -1
		var spatial_index := agent_id - FIRST_AGENT_ID
		if (
			tick % MS6_SPATIAL_INTERVAL == 0
			and spatial_index >= 0 and spatial_index < _spatial_neighbors.size()
			and int(_spatial_neighbors[spatial_index]) >= 0
		):
			source_id = FIRST_AGENT_ID + int(_spatial_neighbors[spatial_index])
			_spatial_gossip_source_count += 1
		elif not agent.local_contact_ids.is_empty():
			var contact_index: int = (
				(_next_random_int() + agent_id + tick) % agent.local_contact_ids.size()
			)
			source_id = int(agent.local_contact_ids[contact_index])
		if source_id < 0:
			continue
		var source: Dictionary = _store.get_agent(source_id)
		if source.rumor_ids.is_empty():
			continue
		var rumor_id := int(source.rumor_ids[(_next_random_int() + tick) % source.rumor_ids.size()])
		if rumor_id not in agent.rumor_ids and agent.rumor_ids.size() < 8:
			agent.rumor_ids.append(rumor_id)
			_store.update_agent(agent)
			_gossip_transfer_count += 1
	if tick % 72 == 0 and _gossip_transfer_count > transfers_before:
		var trend := _find_trending_rumor()
		if not trend.is_empty():
			_pending_events.append({
				"type": "GOSSIP_TREND",
				"tick": tick,
				"rumor_id": int(trend.rumor_id),
				"topic": RUMOR_TOPICS[int(trend.rumor_id) - 1],
				"reach": int(trend.reach),
			})


func _transfer_money_between_contacts() -> void:
	var candidates := _detail_agent_ids()
	if tick % 96 == 0:
		candidates.append_array(_cohort_sample_ids(19))
	for agent_id: int in candidates:
		if _detailed_agent_ids.has(agent_id):
			_detailed_agent_steps += 1
		else:
			_aggregate_agent_steps += 1
		if agent_id % 19 != tick % 19:
			continue
		var payer: Dictionary = _store.get_agent(agent_id)
		if payer.local_contact_ids.is_empty() or int(payer.money_cents) < 100:
			continue
		var receiver_id := int(payer.local_contact_ids[_next_random_int() % payer.local_contact_ids.size()])
		var receiver: Dictionary = _store.get_agent(receiver_id)
		var amount := 25 + (_next_random_int() % 176)
		amount = maxi(1, int(round(
			float(amount) * (0.65 + float(payer.get("spending", 0.4)) * 0.70)
		)))
		amount = mini(amount, int(payer.money_cents))
		payer["money_cents"] = int(payer.money_cents) - amount
		receiver["money_cents"] = int(receiver.money_cents) + amount
		_sync_financial_feedback(payer)
		_sync_financial_feedback(receiver)
		_store.update_agent(payer)
		_store.update_agent(receiver)
		_money_transfer_count += 1


func _update_employment() -> void:
	var hires := 0
	var departures := 0
	var feedback: Dictionary = _current_feedback_summary()
	var cohort_keys: Array[String] = _store.get_cohort_keys()
	for cohort_key: String in cohort_keys:
		var members: Array[int] = _store.get_cohort_agent_ids(cohort_key)
		var rate_per_thousand := _employment_transition_rate(
			cohort_key.contains(":UNEMPLOYED:"), feedback
		)
		var changed_ids := _select_cohort_changes(members, rate_per_thousand)
		for agent_id: int in changed_ids:
			var agent: Dictionary = _store.get_agent(agent_id)
			if str(agent.employment_status) == "UNEMPLOYED":
				agent["employment_status"] = "EMPLOYED"
				agent["workplace_organization_id"] = 1 if (_next_random_int() % 100) < 36 else 2
				agent["schedule_kind"] = "DAY_WORK" if (_next_random_int() % 100) < 75 else "EVENING_SHIFT"
				agent["stress"] = clampf(float(agent.stress) - 0.08, 0.0, 1.0)
				agent["activity_level"] = clampf(float(agent.activity_level) + 0.12, 0.0, 1.0)
				_job_change_count += 1
				hires += 1
			else:
				agent["employment_status"] = "UNEMPLOYED"
				agent["workplace_organization_id"] = 0
				agent["schedule_kind"] = "UNEMPLOYED"
				agent["stress"] = clampf(float(agent.stress) + 0.12, 0.0, 1.0)
				agent["activity_level"] = clampf(float(agent.activity_level) - 0.10, 0.0, 1.0)
				_job_change_count += 1
				departures += 1
			_store.update_agent(agent)
	_update_locations()
	if hires + departures > 0:
		_pending_events.append({
			"type": "JOB_MARKET_CHANGED",
			"tick": tick,
			"hires": hires,
			"departures": departures,
		})
	_pending_events.append({
		"type": "GROUP_ACTIVITY",
		"tick": tick,
		"group_id": 1 + int((_next_random_int() + tick) % _groups.size()),
	})


func _find_trending_rumor() -> Dictionary:
	var counts: Dictionary = {}
	for agent_id: int in get_agent_ids():
		var agent: Dictionary = _store.get_agent(agent_id)
		for rumor_id: int in agent.rumor_ids:
			counts[rumor_id] = int(counts.get(rumor_id, 0)) + 1
	var best_id := -1
	var best_reach := -1
	for rumor_id: int in counts:
		var reach := int(counts[rumor_id])
		if reach > best_reach or (reach == best_reach and rumor_id < best_id):
			best_id = rumor_id
			best_reach = reach
	return {} if best_id == -1 else {"rumor_id": best_id, "reach": best_reach}


func _detail_agent_ids() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in _detailed_agent_ids.keys():
		result.append(int(value))
	result.sort()
	return result


func _cohort_sample_ids(stride: int) -> Array[int]:
	var result: Array[int] = []
	for cohort_key: String in _store.get_cohort_keys():
		var members: Array[int] = _store.get_cohort_agent_ids(cohort_key)
		if members.is_empty():
			continue
		var start := int((tick + members[0]) % maxi(1, stride))
		for index in range(start, members.size(), maxi(1, stride)):
			var agent_id := members[index]
			if not _detailed_agent_ids.has(agent_id):
				result.append(agent_id)
	return result


func _select_cohort_changes(members: Array[int], rate_per_thousand: int) -> Array[int]:
	var result: Array[int] = []
	if members.is_empty() or rate_per_thousand <= 0:
		return result
	var numerator := members.size() * rate_per_thousand
	var change_count := int(numerator / 1000)
	if _next_random_int() % 1000 < numerator % 1000:
		change_count += 1
	var start := _next_random_int() % members.size()
	for offset in range(mini(change_count, members.size())):
		result.append(members[(start + offset) % members.size()])
	return result


func _employment_transition_rate(is_unemployed: bool, feedback: Dictionary) -> int:
	if _social_field_influence.is_empty():
		return 45 if is_unemployed else 8
	var business := float(_social_field_influence.get("business_health", 0.6))
	var field_stress := float(_social_field_influence.get("stress", 0.2))
	var tension := float(_social_field_influence.get("social_tension", 0.15))
	var agent_stress := float(feedback.get("average_stress", field_stress))
	var agent_activity := float(feedback.get("average_activity", 0.5))
	if is_unemployed:
		return clampi(int(round(
			25.0 + business * 35.0 - field_stress * 7.0 - agent_stress * 6.0
			- tension * 5.0 + agent_activity * 3.0
		)), 8, 60)
	return clampi(int(round(
		3.0 + (1.0 - business) * 8.0 + field_stress * 4.0
		+ agent_stress * 4.0 + tension * 4.0
	)), 3, 35)


func _total_money_cents() -> int:
	var total := 0
	for agent_id: int in get_agent_ids():
		var agent: Dictionary = _store.get_agent(agent_id)
		total += int(agent.money_cents)
	return total


func _sync_financial_feedback(agent: Dictionary) -> void:
	var observed_wealth := clampf(float(agent.money_cents) / 200_000.0, 0.02, 1.0)
	agent["wealth"] = lerpf(float(agent.get("wealth", observed_wealth)), observed_wealth, 0.08)
	agent["stress"] = clampf(
		float(agent.get("stress", 0.2)) + (0.45 - observed_wealth) * 0.004,
		0.0, 1.0
	)


func _feedback_parameters() -> Dictionary:
	var field_stress := float(_social_field_influence.get("stress", 0.20))
	var business_health := float(_social_field_influence.get("business_health", 0.55))
	var tension := float(_social_field_influence.get("social_tension", 0.15))
	return {
		"stress_delta": (field_stress - 0.30) * 0.035,
		"wealth_delta": (business_health - 0.50) * 0.012,
		"spending_sensitivity": 0.06 + tension * 0.16,
	}


func _maximum_buffer_error(first: PackedFloat32Array, second: PackedFloat32Array) -> float:
	if first.size() != second.size():
		return INF
	var maximum_error := 0.0
	for index in range(first.size()):
		maximum_error = maxf(maximum_error, absf(float(first[index]) - float(second[index])))
	return maximum_error


func _next_random_int() -> int:
	_random_state = (_LCG_MULTIPLIER * _random_state + _LCG_INCREMENT) & _LCG_MASK
	return _random_state
