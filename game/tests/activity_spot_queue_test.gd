extends SceneTree

const AllocatorScript := preload("res://activities/activity_spot_allocator.gd")
const PopulationScript := preload("res://agents/light_population_simulation.gd")
const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	if not _test_allocator_fixture():
		return
	if not _test_population_integration():
		return
	if not _test_waiting_affordances():
		return
	quit(0)


func _test_allocator_fixture() -> bool:
	var states: Array[Dictionary] = []
	for index in range(10):
		states.append({
			"agent_id": 100 + index,
			"activity": "WORK",
			"destination_place_id": 1,
			"plan_started_tick": 24,
			"spot_capacity": 3,
			"activity_spot_id": "P1-S%02d" % (index % 3),
		})
	var allocator := AllocatorScript.new()
	var first: Dictionary = allocator.allocate(states)
	var reversed := states.duplicate(true)
	reversed.reverse()
	var second: Dictionary = allocator.allocate(reversed)
	if first != second:
		return _fail("Spot allocation depends on input/query order")
	if int(first.metrics.reserved) != 3 or int(first.metrics.queued) != 7:
		return _fail("Synthetic capacity did not create 3 claims and 7 queue entries")
	var unique_spots: Dictionary = {}
	for assignment: Dictionary in first.assignments.values():
		if bool(assignment.admitted):
			if unique_spots.has(str(assignment.activity_spot_id)):
				return _fail("Allocator created a duplicate exclusive claim")
			unique_spots[str(assignment.activity_spot_id)] = true
		elif int(assignment.queue_position) <= 0:
			return _fail("Queued assignment has no stable queue position")
	return true


func _test_population_integration() -> bool:
	var population := PopulationScript.new(606060, 180)
	var deterministic := PopulationScript.new(606060, 180)
	population.set_ms6_gpu_enabled(false)
	deterministic.set_ms6_gpu_enabled(false)
	var detail_ids: Array[int] = population.get_agent_ids().slice(0, 120)
	population.set_detail_tiers(detail_ids, [])
	deterministic.set_detail_tiers(detail_ids, [])
	var occupied: Dictionary = {}
	var queued_ids: Dictionary = {}
	for agent_id: int in detail_ids:
		var state: Dictionary = population.get_agent_schedule_state(agent_id, 270)
		var copy: Dictionary = deterministic.get_agent_schedule_state(agent_id, 270)
		if state != copy:
			_close(population, deterministic)
			return _fail("Equal-seed queue allocation diverged")
		if str(state.execution_phase) == "WAIT_FOR_SPOT":
			queued_ids[agent_id] = true
			if str(state.reservation_status) != "QUEUED" or int(state.queue_position) <= 0:
				_close(population, deterministic)
				return _fail("Waiting agent has invalid queue state")
			continue
		if str(state.execution_phase) != "PERFORM":
			_close(population, deterministic)
			return _fail("Night fixture produced unexpected phase %s" % state.execution_phase)
		var spot_id := str(state.activity_spot_id)
		if occupied.has(spot_id):
			_close(population, deterministic)
			return _fail("Detailed NPCs share physical spot %s" % spot_id)
		occupied[spot_id] = agent_id
	var metrics: Dictionary = population.get_activity_spot_metrics(270)
	if queued_ids.is_empty() or occupied.size() != int(metrics.reserved) or (
		queued_ids.size() != int(metrics.queued)
	):
		_close(population, deterministic)
		return _fail("Population queue did not respect place capacities: occupied=%d queued=%d metrics=%s" % [
			occupied.size(), queued_ids.size(), JSON.stringify(metrics),
		])
	var admitted_after_rotation := false
	for agent_id: int in queued_ids:
		var next_state: Dictionary = population.get_agent_schedule_state(agent_id, 282)
		if str(next_state.execution_phase) == "PERFORM":
			admitted_after_rotation = true
			break
	if not admitted_after_rotation:
		_close(population, deterministic)
		return _fail("Queue priority did not rotate at the next plan slot")
	var reduced_ids: Array[int] = detail_ids.slice(0, 10)
	population.set_detail_tiers(reduced_ids, [])
	var reduced_metrics: Dictionary = population.get_activity_spot_metrics(270)
	if int(reduced_metrics.queued) != 0 or int(reduced_metrics.reserved) != 10:
		_close(population, deterministic)
		return _fail("Released detail claims did not admit the remaining queue")
	print("ACTIVITY_SPOT_QUEUE_OK reserved=%d queued=%d unique=true rotating=true released=true deterministic=true" % [
		occupied.size(), queued_ids.size(),
	])
	_close(population, deterministic)
	return true


func _close(first: RefCounted, second: RefCounted) -> void:
	first.close_ms6_backend()
	second.close_ms6_backend()


func _test_waiting_affordances() -> bool:
	var world := SimulationWorldScript.new(707070)
	world.advance(4, false)
	world.update_adaptive_focus(2, [], 240, false)
	var waiting_id := -1
	for agent_id: int in world.get_adaptive_focus_view().refined_light_ids:
		var state: Dictionary = world.get_light_agent_schedule_state(agent_id, world.tick)
		if str(state.execution_phase) == "WAIT_FOR_SPOT":
			waiting_id = agent_id
			break
	if waiting_id < 0:
		return _fail("Large detailed cohort produced no waiting NPC fixture")
	world.activate_light_agent_as_person(waiting_id, "QUEUE_TEST")
	world.introduce_people(world.player_id, waiting_id)
	var activity: Dictionary = world.get_person_activity_view(waiting_id)
	if str(activity.execution_phase) != "WAIT_FOR_SPOT":
		return _fail("Promoted waiting NPC lost its queue state")
	var action_types: Dictionary = {}
	for action: Dictionary in world.get_available_social_actions(world.player_id, waiting_id):
		action_types[str(action.type)] = true
	for forbidden: String in [
		"InviteToActivity", "JoinActivity", "AssistActivity", "ObserveActivity",
		"HinderActivity", "InterruptActivity",
	]:
		if action_types.has(forbidden):
			return _fail("Waiting NPC exposed unavailable activity action %s" % forbidden)
	if not action_types.has("BuildRapport"):
		return _fail("Waiting NPC lost ordinary conversation affordances")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
