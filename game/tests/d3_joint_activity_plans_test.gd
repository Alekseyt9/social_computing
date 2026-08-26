extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	var success_fixture := _create_invited_world()
	var deterministic_fixture := _create_invited_world()
	if success_fixture.is_empty() or deterministic_fixture.is_empty():
		return
	var success: RefCounted = success_fixture.world
	var deterministic: RefCounted = deterministic_fixture.world
	var agent_id := int(success_fixture.agent_id)
	var plan_id := int(success_fixture.plan_id)
	var relationship_before: Dictionary = success.get_relationship_state(agent_id, success.player_id)
	success.advance(2)
	deterministic.advance(2)
	if str(success.get_activity_plan_snapshot().plans[0].status) != "GATHERING":
		_fail("Plan did not enter GATHERING before its start")
		return
	success.advance(6)
	deterministic.advance(6)
	var active: Dictionary = success.get_activity_plan_snapshot().plans[0]
	if str(active.status) != "ACTIVE" or int(active.arrival_ticks.size()) < 2:
		_fail("Present participants did not start the plan: %s" % JSON.stringify(active))
		return
	var remaining := int(active.end_tick) - int(success.tick)
	success.advance(remaining)
	deterministic.advance(remaining)
	var completed: Dictionary = success.get_activity_plan_snapshot().plans[0]
	if str(completed.status) != "COMPLETED" or bool(completed.late_start):
		_fail("On-time plan did not complete: %s" % JSON.stringify(completed))
		return
	if success.get_activity_plan_snapshot() != deterministic.get_activity_plan_snapshot():
		_fail("Equal-seed plan execution is not deterministic")
		return
	var restored: RefCounted = SimulationWorldScript.create_from_save_data(
		success.export_save_data()
	)
	if restored == null or restored.get_activity_plan_snapshot() != success.get_activity_plan_snapshot():
		_fail("Joint plans did not survive command-log save/load")
		return
	var relationship_after: Dictionary = success.get_relationship_state(agent_id, success.player_id)
	if float(relationship_after.trust) <= float(relationship_before.trust):
		_fail("Completed joint plan did not improve participant trust")
		return
	if not _has_event(success, "activity_plan_completed"):
		_fail("Completed plan produced no canonical event")
		return
	var journal: Dictionary = success.get_player_journal_view(success.player_id)
	if journal.activity_plans.is_empty() or str(journal.activity_plans[0].status) != "COMPLETED":
		_fail("Completed plan is absent from observer-facing journal")
		return

	var late_fixture := _create_invited_world()
	if late_fixture.is_empty():
		return
	var late: RefCounted = late_fixture.world
	var late_place := int(late_fixture.place_id)
	late.visit_public_place(late.player_id, 2 if late_place != 2 else 4)
	late.advance(9) # The target is present, but the player misses the start tick.
	late.visit_public_place(late.player_id, late_place)
	late.advance(1)
	var late_active: Dictionary = late.get_activity_plan_snapshot().plans[0]
	if str(late_active.status) != "ACTIVE" or not bool(late_active.late_start):
		_fail("Late arrival did not start a recoverable plan: %s" % JSON.stringify(late_active))
		return
	late.advance(int(late_active.end_tick) - int(late.tick))
	if str(late.get_activity_plan_snapshot().plans[0].status) != "COMPLETED" or (
		not _has_event(late, "activity_plan_late_arrival")
	):
		_fail("Late plan did not preserve arrival and completion events")
		return

	var missed_fixture := _create_invited_world()
	if missed_fixture.is_empty():
		return
	var missed: RefCounted = missed_fixture.world
	var missed_agent_id := int(missed_fixture.agent_id)
	var missed_place := int(missed_fixture.place_id)
	missed.visit_public_place(missed.player_id, 2 if missed_place != 2 else 4)
	var missed_relation_before: Dictionary = missed.get_relationship_state(missed_agent_id, missed.player_id)
	var missed_plan: Dictionary = missed.get_activity_plan_snapshot().plans[0]
	missed.advance(int(missed_plan.end_tick) - int(missed.tick))
	var missed_result: Dictionary = missed.get_activity_plan_snapshot().plans[0]
	var missed_relation_after: Dictionary = missed.get_relationship_state(missed_agent_id, missed.player_id)
	if str(missed_result.status) != "MISSED" or not missed_result.arrival_ticks.has(missed_agent_id):
		_fail("Absent creator did not produce MISSED plan: %s" % JSON.stringify(missed_result))
		return
	if float(missed_relation_after.resentment) <= float(missed_relation_before.resentment) or (
		float(missed_relation_after.trust) >= float(missed_relation_before.trust)
	):
		_fail("Missed plan did not damage the waiting participant's relationship")
		return
	if not _has_event(missed, "activity_plan_missed"):
		_fail("Missed plan produced no canonical event")
		return
	if not bool(success.get_light_population_snapshot().money_conserved) or (
		not bool(late.get_light_population_snapshot().money_conserved)
	) or not bool(missed.get_light_population_snapshot().money_conserved):
		_fail("Joint plan lifecycle broke money conservation")
		return
	print("D3_JOINT_PLANS_OK plan=%d on_time=COMPLETED late=COMPLETED missed=MISSED deterministic=true save_load=true events=true" % plan_id)
	quit(0)


func _create_invited_world() -> Dictionary:
	var world := SimulationWorldScript.new(939393)
	world.advance(4)
	world.update_adaptive_focus(1, [], 60)
	var agent_id := -1
	for candidate_id: int in world.get_adaptive_population_snapshot().refined_light_ids:
		var activity: Dictionary = world.get_light_agent_schedule_state(candidate_id, world.tick)
		if str(activity.execution_phase) == "PERFORM":
			agent_id = candidate_id
			break
	if agent_id < 0:
		_fail("No performing NPC found for D3 fixture")
		return {}
	world.activate_light_agent_as_person(agent_id, "D3_TEST")
	world.introduce_people(world.player_id, agent_id)
	for _index in range(3):
		var rapport: Dictionary = _find_action(
			world.get_available_social_actions(world.player_id, agent_id), "BuildRapport"
		)
		world.perform_social_action("BuildRapport", world.player_id, agent_id, rapport.context)
	var activity: Dictionary = world.get_person_activity_view(agent_id)
	world.visit_public_place(world.player_id, int(activity.place_id))
	var invitation: Dictionary = _find_action(
		world.get_available_social_actions(world.player_id, agent_id), "InviteToActivity"
	)
	if invitation.is_empty():
		_fail("D3 fixture has no invitation affordance")
		return {}
	var result: Dictionary = world.perform_social_action(
		"InviteToActivity", world.player_id, agent_id, invitation.context
	)
	if not bool(result.get("ok", false)) or str(result.decision.decision) != "ACCEPT":
		_fail("D3 invitation was not accepted: %s" % JSON.stringify(result))
		return {}
	var plan_effect: Dictionary = _find_effect(result.effects, "ACTIVITY_INVITATION_CREATED")
	if plan_effect.is_empty() or int(plan_effect.get("plan_id", -1)) < 0:
		_fail("Accepted invitation did not create an activity plan")
		return {}
	return {
		"world": world,
		"agent_id": agent_id,
		"plan_id": int(plan_effect.plan_id),
		"place_id": int(activity.place_id),
	}


func _find_action(actions: Array[Dictionary], action_type: String) -> Dictionary:
	for action: Dictionary in actions:
		if str(action.type) == action_type:
			return action
	return {}


func _find_effect(effects: Array, effect_type: String) -> Dictionary:
	for effect: Dictionary in effects:
		if str(effect.get("type", "")) == effect_type:
			return effect
	return {}


func _has_event(world: RefCounted, event_type: String) -> bool:
	for event: Dictionary in world.get_recent_events(50):
		if str(event.type) == event_type:
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
