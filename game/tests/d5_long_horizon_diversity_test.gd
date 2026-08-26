extends SceneTree

const PopulationScript := preload("res://agents/light_population_simulation.gd")
const PlanSystemScript := preload("res://activities/activity_plan_system.gd")
const SimulationWorldScript := preload("res://core/simulation_world.gd")

const DAY_TICKS := 288
const DAYS := 14
const POPULATION := 180
const SAMPLED_AGENTS := 72
const SAMPLE_INTERVAL := 5
const SEEDS := [17011, 29023, 41039, 53051]
const REQUIRED_ACTIVITIES := [
	"WORK", "TEAMWORK", "WORK_BREAK", "HOME", "REST", "ERRANDS",
	"CAFE_MEAL", "LEISURE", "EXERCISE", "SOCIAL", "COMMUNITY", "HEALTH",
	"CRAFT", "JOB_SEARCH", "VISIT_FRIEND", "STUDY",
]
const REQUIRED_PHASES := ["TRAVEL", "RESERVE", "PERFORM", "FINISH", "INTERRUPT"]


func _init() -> void:
	_run()


func _run() -> void:
	var activity_counts: Dictionary = {}
	var transition_counts: Dictionary = {}
	var phase_counts: Dictionary = {}
	var visual_actions: Dictionary = {}
	var spot_ids: Dictionary = {}
	var schedule_activities: Dictionary = {}
	var peak_spot_occupancy := 0
	var maximum_phase_streak := 0
	var gossip_transfers := 0
	var money_transfers := 0
	var queue_samples := 0
	for simulation_seed: int in SEEDS:
		var report := _audit_population_seed(simulation_seed)
		if not bool(report.get("ok", false)):
			_fail("Seed %d failed: %s" % [simulation_seed, str(report.get("error", "UNKNOWN"))])
			return
		_merge_counts(activity_counts, report.activity_counts)
		_merge_counts(transition_counts, report.transition_counts)
		_merge_counts(phase_counts, report.phase_counts)
		_merge_counts(visual_actions, report.visual_actions)
		for spot_id: String in report.spot_ids:
			spot_ids[spot_id] = true
		_merge_nested_sets(schedule_activities, report.schedule_activities)
		peak_spot_occupancy = maxi(peak_spot_occupancy, int(report.peak_spot_occupancy))
		maximum_phase_streak = maxi(maximum_phase_streak, int(report.maximum_phase_streak))
		gossip_transfers += int(report.gossip_transfers)
		money_transfers += int(report.money_transfers)
		queue_samples += int(report.queue_samples)

	for activity: String in REQUIRED_ACTIVITIES:
		if int(activity_counts.get(activity, 0)) <= 0:
			_fail("Long horizon never selected activity %s" % activity)
			return
	for phase: String in REQUIRED_PHASES:
		if int(phase_counts.get(phase, 0)) <= 0:
			_fail("Long horizon never observed phase %s" % phase)
			return
	if transition_counts.size() < 12:
		_fail("Activity behavior remained too repetitive: only %d transition types" % transition_counts.size())
		return
	if visual_actions.size() < 10 or spot_ids.size() < 24:
		_fail("Visual/physical activity variety is too low: actions=%d spots=%d" % [
			visual_actions.size(), spot_ids.size(),
		])
		return
	if peak_spot_occupancy > 1:
		_fail("Detailed NPCs still share an exclusive spot: peak=%d" % peak_spot_occupancy)
		return
	for schedule_kind: String in schedule_activities:
		if schedule_activities[schedule_kind].size() < 5:
			_fail("Schedule %s produced only %d activity families" % [
				schedule_kind, schedule_activities[schedule_kind].size(),
			])
			return
	var plans := _audit_joint_plans()
	if not bool(plans.get("ok", false)):
		_fail(str(plans.get("error", "Joint plan audit failed")))
		return
	var minimum_strategies := 999
	for simulation_seed: int in SEEDS:
		var world := SimulationWorldScript.new(simulation_seed)
		var reachability: Dictionary = world.get_goal_reachability_report()
		if not bool(reachability.get("reachable", false)):
			_fail("Aurora became unreachable for seed %d" % simulation_seed)
			return
		minimum_strategies = mini(minimum_strategies, int(reachability.strategy_count))
	if minimum_strategies < 3:
		_fail("Aurora retained fewer than three systemic strategies")
		return

	print("D5_LONG_HORIZON_OK seeds=%d days=%d sampled_agents=%d activities=%d transitions=%d phases=%s visual_actions=%d spots=%d peak_spot_occupancy=%d queue_samples=%d max_phase_streak=%d plans=%s aurora_strategies_min=%d gossip=%d money_transfers=%d invariants=true" % [
		SEEDS.size(), DAYS, SAMPLED_AGENTS, activity_counts.size(), transition_counts.size(),
		JSON.stringify(phase_counts), visual_actions.size(), spot_ids.size(),
		peak_spot_occupancy, queue_samples, maximum_phase_streak, JSON.stringify(plans.status_counts),
		minimum_strategies, gossip_transfers, money_transfers,
	])
	quit(0)


func _audit_population_seed(simulation_seed: int) -> Dictionary:
	var population := PopulationScript.new(simulation_seed, POPULATION)
	population.set_ms6_gpu_enabled(false)
	var agent_ids: Array[int] = population.get_agent_ids()
	var initial_ids := agent_ids.duplicate()
	population.set_detail_tiers(agent_ids.slice(0, SAMPLED_AGENTS), [])
	var previous_activity: Dictionary = {}
	var previous_phase: Dictionary = {}
	var phase_streaks: Dictionary = {}
	var activity_counts: Dictionary = {}
	var transition_counts: Dictionary = {}
	var phase_counts: Dictionary = {}
	var visual_actions: Dictionary = {}
	var spot_ids: Dictionary = {}
	var schedule_activities: Dictionary = {}
	var peak_spot_occupancy := 0
	var maximum_phase_streak := 0
	var queue_samples := 0
	for day in range(DAYS):
		var day_end := (day + 1) * DAY_TICKS
		while population.tick < day_end:
			var step := mini(SAMPLE_INTERVAL, day_end - population.tick)
			population.advance(step)
			var occupied_spots: Dictionary = {}
			for sample_index in range(mini(SAMPLED_AGENTS, agent_ids.size())):
				var agent_id := int(agent_ids[sample_index])
				var state: Dictionary = population.get_agent_schedule_state(agent_id, population.tick)
				if state.is_empty():
					population.close_ms6_backend()
					return {"ok": false, "error": "Agent %d lost its activity state" % agent_id}
				var activity := str(state.activity)
				var phase := str(state.execution_phase)
				_increment(activity_counts, activity)
				_increment(phase_counts, phase)
				visual_actions[str(state.visual_action)] = true
				var agent: Dictionary = population.get_agent_view(agent_id)
				var schedule_kind := str(agent.schedule_kind)
				if not schedule_activities.has(schedule_kind):
					schedule_activities[schedule_kind] = {}
				schedule_activities[schedule_kind][activity] = true
				if previous_activity.has(agent_id) and str(previous_activity[agent_id]) != activity:
					_increment(transition_counts, "%s>%s" % [previous_activity[agent_id], activity])
				previous_activity[agent_id] = activity
				if str(previous_phase.get(agent_id, "")) == phase:
					phase_streaks[agent_id] = int(phase_streaks.get(agent_id, 0)) + step
				else:
					phase_streaks[agent_id] = step
				previous_phase[agent_id] = phase
				maximum_phase_streak = maxi(maximum_phase_streak, int(phase_streaks[agent_id]))
				if phase not in ["PERFORM", "WAIT_FOR_SPOT"] and int(phase_streaks[agent_id]) > 24:
					population.close_ms6_backend()
					return {"ok": false, "error": "Agent %d stuck in phase %s for %d ticks" % [
						agent_id, phase, int(phase_streaks[agent_id]),
					]}
				if int(state.plan_ends_tick) <= int(state.plan_started_tick) or (
					population.tick >= int(state.plan_ends_tick) + 12
				):
					population.close_ms6_backend()
					return {"ok": false, "error": "Agent %d retained an expired activity plan" % agent_id}
				var progress := float(state.phase_progress)
				if progress < 0.0 or progress > 1.0:
					population.close_ms6_backend()
					return {"ok": false, "error": "Phase progress escaped bounds"}
				var spot_id := str(state.activity_spot_id)
				if phase in ["RESERVE", "PERFORM"]:
					if spot_id.is_empty() or str(state.reservation_status) != "RESERVED":
						population.close_ms6_backend()
						return {"ok": false, "error": "Active phase has no reservation"}
					spot_ids[spot_id] = true
					occupied_spots[spot_id] = int(occupied_spots.get(spot_id, 0)) + 1
				elif phase == "WAIT_FOR_SPOT":
					queue_samples += 1
					if str(state.reservation_status) != "QUEUED" or int(state.queue_position) <= 0:
						population.close_ms6_backend()
						return {"ok": false, "error": "Waiting activity has invalid queue data"}
				elif not spot_id.is_empty() or bool(state.is_interactable):
					population.close_ms6_backend()
					return {"ok": false, "error": "Inactive phase retained a spot"}
				if phase in ["FINISH", "INTERRUPT"] and str(state.reservation_status) != "RELEASED":
					population.close_ms6_backend()
					return {"ok": false, "error": "Terminal phase retained reservation"}
			for occupancy: Variant in occupied_spots.values():
				peak_spot_occupancy = maxi(peak_spot_occupancy, int(occupancy))
		var snapshot: Dictionary = population.snapshot()
		if int(snapshot.population) != POPULATION or not bool(snapshot.money_conserved):
			population.close_ms6_backend()
			return {"ok": false, "error": "Population or money invariant failed on day %d" % (day + 1)}
	if population.get_agent_ids() != initial_ids:
		population.close_ms6_backend()
		return {"ok": false, "error": "Agent identity set changed"}
	for agent_id: int in population.get_agent_ids():
		if int(population.get_agent_view(agent_id).money_cents) < 0:
			population.close_ms6_backend()
			return {"ok": false, "error": "Agent %d has negative money" % agent_id}
	var validation_errors: Array[String] = population.validate()
	var final_snapshot: Dictionary = population.snapshot()
	population.close_ms6_backend()
	if not validation_errors.is_empty():
		return {"ok": false, "error": "Population validation: %s" % validation_errors[0]}
	return {
		"ok": true,
		"activity_counts": activity_counts,
		"transition_counts": transition_counts,
		"phase_counts": phase_counts,
		"visual_actions": visual_actions,
		"spot_ids": spot_ids.keys(),
		"schedule_activities": schedule_activities,
		"peak_spot_occupancy": peak_spot_occupancy,
		"maximum_phase_streak": maximum_phase_streak,
		"queue_samples": queue_samples,
		"gossip_transfers": int(final_snapshot.gossip_transfers),
		"money_transfers": int(final_snapshot.money_transfers),
	}


func _audit_joint_plans() -> Dictionary:
	var status_counts := {"COMPLETED": 0, "MISSED": 0, "LATE": 0}
	for case_index in range(12):
		var plans := PlanSystemScript.new()
		var place_id := 2 + posmod(case_index, 6)
		var participant_a := 100 + case_index * 2
		var participant_b := participant_a + 1
		var created: Dictionary = plans.create_plan({
			"participant_ids": [participant_a, participant_b],
			"creator_id": participant_a,
			"activity": REQUIRED_ACTIVITIES[case_index % REQUIRED_ACTIVITIES.size()],
			"activity_label": "batch plan %d" % case_index,
			"place_id": place_id,
			"created_tick": 0,
			"start_tick": 12,
			"duration_ticks": 12,
		})
		if not bool(created.get("ok", false)):
			return {"ok": false, "error": "Could not create plan case %d" % case_index}
		var locations := {participant_a: -1, participant_b: place_id}
		var resolver := func(person_id: int) -> int: return int(locations.get(person_id, -1))
		plans.advance(6, resolver)
		match case_index % 3:
			0:
				locations[participant_a] = place_id
				plans.advance(12, resolver)
				plans.advance(24, resolver)
			1:
				plans.advance(12, resolver)
				locations[participant_a] = place_id
				plans.advance(15, resolver)
				plans.advance(24, resolver)
			2:
				plans.advance(24, resolver)
		var plan: Dictionary = plans.get_plans()[0]
		var status := str(plan.status)
		status_counts[status] = int(status_counts.get(status, 0)) + 1
		if bool(plan.late_start):
			status_counts.LATE += 1
	if int(status_counts.COMPLETED) != 8 or int(status_counts.MISSED) != 4 or int(status_counts.LATE) != 4:
		return {"ok": false, "error": "Joint plan outcomes lack variety: %s" % JSON.stringify(status_counts)}
	return {"ok": true, "status_counts": status_counts}


func _increment(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _merge_counts(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		target[key] = int(target.get(key, 0)) + int(source[key])


func _merge_nested_sets(target: Dictionary, source: Dictionary) -> void:
	for outer_key: Variant in source:
		if not target.has(outer_key):
			target[outer_key] = {}
		for inner_key: Variant in source[outer_key]:
			target[outer_key][inner_key] = true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
