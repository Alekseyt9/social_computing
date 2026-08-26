extends SceneTree

const PopulationScript := preload("res://agents/light_population_simulation.gd")
const DAY_TICKS := 288
const SAMPLE_SIZE := 120


func _init() -> void:
	var first := PopulationScript.new(818181, SAMPLE_SIZE)
	var second := PopulationScript.new(818181, SAMPLE_SIZE)
	var phase_counts: Dictionary = {}
	var spot_ids: Dictionary = {}
	var reserved_by_plan: Dictionary = {}
	var traveled_between_places := false
	for sample_tick in range(DAY_TICKS):
		for agent_id: int in first.get_agent_ids():
			var state: Dictionary = first.get_agent_schedule_state(agent_id, sample_tick)
			var copy: Dictionary = second.get_agent_schedule_state(agent_id, sample_tick)
			if state != copy:
				_close(first, second)
				_fail("Activity lifecycle is not deterministic")
				return
			var phase := str(state.execution_phase)
			phase_counts[phase] = int(phase_counts.get(phase, 0)) + 1
			var progress := float(state.phase_progress)
			if progress < 0.0 or progress > 1.0:
				_close(first, second)
				_fail("Phase progress escaped normalized bounds")
				return
			var has_spot := not str(state.activity_spot_id).is_empty()
			if phase in ["RESERVE", "PERFORM"]:
				if not has_spot or str(state.reservation_status) != "RESERVED":
					_close(first, second)
					_fail("Active phase has no reserved activity spot")
					return
				if bool(state.is_interactable) != (phase == "PERFORM"):
					_close(first, second)
					_fail("Interaction affordance does not follow PERFORM phase")
					return
				spot_ids[str(state.activity_spot_id)] = true
				var plan_key := "%d:%d" % [agent_id, int(state.plan_started_tick)]
				var previous_spot := str(reserved_by_plan.get(plan_key, state.activity_spot_id))
				if previous_spot != str(state.activity_spot_id):
					_close(first, second)
					_fail("Reservation changed inside one activity plan")
					return
				reserved_by_plan[plan_key] = str(state.activity_spot_id)
			else:
				if has_spot or bool(state.is_interactable):
					_close(first, second)
					_fail("Travel/terminal phase retained a spot or interaction")
					return
			if phase in ["FINISH", "INTERRUPT"] and str(state.reservation_status) != "RELEASED":
				_close(first, second)
				_fail("Terminal phase did not release its activity spot")
				return
			if phase == "TRAVEL" and int(state.origin_place_id) != int(state.destination_place_id):
				traveled_between_places = traveled_between_places or (
					int(state.physical_place_id) == int(state.origin_place_id)
				)
	var required_phases := ["TRAVEL", "RESERVE", "PERFORM", "FINISH", "INTERRUPT"]
	for phase: String in required_phases:
		if int(phase_counts.get(phase, 0)) <= 0:
			_close(first, second)
			_fail("Lifecycle phase was never observed: %s counts=%s" % [
				phase, JSON.stringify(phase_counts),
			])
			return
	if not traveled_between_places or spot_ids.size() < 8:
		_close(first, second)
		_fail("Lifecycle produced no physical travel or insufficient spot variety")
		return
	print("D1_ACTIVITY_LIFECYCLE_OK agents=%d ticks=%d phases=%s spots=%d deterministic=true released=true" % [
		SAMPLE_SIZE, DAY_TICKS, JSON.stringify(phase_counts), spot_ids.size(),
	])
	_close(first, second)
	quit(0)


func _close(first: RefCounted, second: RefCounted) -> void:
	first.close_ms6_backend()
	second.close_ms6_backend()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
