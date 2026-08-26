extends SceneTree

const PopulationScript := preload("res://agents/light_population_simulation.gd")
const DAY_TICKS := 288


func _init() -> void:
	var population := PopulationScript.new(717171, 1200)
	var deterministic_copy := PopulationScript.new(717171, 1200)
	var activity_counts: Dictionary = {}
	var place_counts: Dictionary = {}
	for sample_tick in range(0, DAY_TICKS, 12):
		for agent_id: int in population.get_agent_ids():
			var state: Dictionary = population.get_agent_schedule_state(agent_id, sample_tick)
			var copy_state: Dictionary = deterministic_copy.get_agent_schedule_state(agent_id, sample_tick)
			if state != copy_state:
				_close(population, deterministic_copy)
				_fail("Activity utility selection is not deterministic")
				return
			var activity := str(state.activity)
			activity_counts[activity] = int(activity_counts.get(activity, 0)) + 1
			place_counts[int(state.place_id)] = int(place_counts.get(int(state.place_id), 0)) + 1
			if state.get("utility_reasons", []).is_empty():
				_close(population, deterministic_copy)
				_fail("Activity choice has no utility explanation")
				return
	var required := [
		"WORK", "TEAMWORK", "WORK_BREAK", "HOME", "REST", "ERRANDS",
		"CAFE_MEAL", "LEISURE", "EXERCISE", "SOCIAL", "COMMUNITY", "HEALTH",
		"CRAFT", "JOB_SEARCH", "VISIT_FRIEND", "STUDY",
	]
	for activity: String in required:
		if int(activity_counts.get(activity, 0)) <= 0:
			_close(population, deterministic_copy)
			_fail("Activity catalog entry was never selected: %s counts=%s" % [activity, JSON.stringify(activity_counts)])
			return
	for place_id in range(1, 9):
		if int(place_counts.get(place_id, 0)) <= 0:
			_close(population, deterministic_copy)
			_fail("Utility model never used place %d" % place_id)
			return
	var day_worker_id := -1
	for agent_id: int in population.get_agent_ids():
		if str(population.get_agent_view(agent_id).schedule_kind) == "DAY_WORK":
			day_worker_id = agent_id
			break
	if day_worker_id < 0:
		_close(population, deterministic_copy)
		_fail("No day worker found")
		return
	var work_state: Dictionary = population.get_agent_schedule_state(day_worker_id, 0)
	var night_state: Dictionary = population.get_agent_schedule_state(day_worker_id, 168)
	if str(work_state.activity) not in ["WORK", "TEAMWORK", "WORK_BREAK"]:
		_close(population, deterministic_copy)
		_fail("Work obligation was displaced by a free-time activity")
		return
	if str(night_state.activity) not in ["HOME", "REST"] or int(night_state.place_id) != 3:
		_close(population, deterministic_copy)
		_fail("Home obligation was displaced at night")
		return
	print("D1_ACTIVITY_UTILITY_OK activities=%d places=%d samples=%d deterministic=true explained=true obligations=true counts=%s" % [
		activity_counts.size(), place_counts.size(), 1200 * 24, JSON.stringify(activity_counts),
	])
	_close(population, deterministic_copy)
	quit(0)


func _close(first: RefCounted, second: RefCounted) -> void:
	first.close_ms6_backend()
	second.close_ms6_backend()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
