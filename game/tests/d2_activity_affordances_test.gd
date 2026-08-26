extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const REQUIRED_ACTIONS := [
	"InviteToActivity", "JoinActivity", "AssistActivity",
	"ObserveActivity", "HinderActivity", "InterruptActivity",
]
const EXPECTED_EFFECTS := {
	"InviteToActivity": "ACTIVITY_INVITATION_CREATED",
	"JoinActivity": "ACTIVITY_SHARED",
	"AssistActivity": "ACTIVITY_ASSISTED",
	"ObserveActivity": "ACTIVITY_OBSERVED",
	"HinderActivity": "ACTIVITY_HINDERED",
	"InterruptActivity": "ACTIVITY_INTERRUPTED",
}


func _init() -> void:
	var probe := _prepared_world()
	if probe.is_empty():
		return
	var probe_world: RefCounted = probe.world
	var agent_id := int(probe.agent_id)
	var available := _action_map(
		probe_world.get_available_social_actions(probe_world.player_id, agent_id)
	)
	for action_type: String in REQUIRED_ACTIONS:
		if not available.has(action_type):
			_fail("Missing calculated D2 affordance %s: %s" % [
				action_type, JSON.stringify(available.keys()),
			])
			return
	var outcomes: Dictionary = {}
	for action_type: String in REQUIRED_ACTIONS:
		var prepared := _prepared_world(agent_id)
		if prepared.is_empty():
			return
		var world: RefCounted = prepared.world
		var actions := _action_map(world.get_available_social_actions(world.player_id, agent_id))
		var action: Dictionary = actions.get(action_type, {})
		if action.is_empty():
			_fail("Prepared world lost action %s" % action_type)
			return
		var money_before := int(world.get_light_population_snapshot().total_money_cents)
		var relation_before: Dictionary = world.get_relationship_state(agent_id, world.player_id)
		var result: Dictionary = world.perform_social_action(
			action_type, world.player_id, agent_id, action.context
		)
		if not bool(result.get("ok", false)) or str(result.template_response).is_empty():
			_fail("D2 action did not resolve through DecisionEngine/renderer: %s %s" % [
				action_type, JSON.stringify(result),
			])
			return
		var effect_type := str(EXPECTED_EFFECTS[action_type])
		if not _has_effect(result.effects, effect_type):
			_fail("D2 action %s produced no %s effect decision=%s: %s" % [
				action_type, effect_type, str(result.decision.decision), JSON.stringify(result.effects),
			])
			return
		if int(world.get_light_population_snapshot().total_money_cents) != money_before:
			_fail("D2 action broke money conservation: %s" % action_type)
			return
		var relation_after: Dictionary = world.get_relationship_state(agent_id, world.player_id)
		if action_type == "AssistActivity" and float(relation_after.trust) <= float(relation_before.trust):
			_fail("Assistance did not improve trust")
			return
		if action_type == "HinderActivity" and float(relation_after.resentment) <= float(relation_before.resentment):
			_fail("Hindering did not create resentment")
			return
		if action_type == "InviteToActivity" and int(world.snapshot().activity_invitation_count) != 1:
			_fail("Accepted invitation was not stored in canonical state")
			return
		if action_type == "InterruptActivity":
			var interrupted: Dictionary = world.get_person_activity_view(agent_id)
			if str(interrupted.execution_phase) != "INTERRUPT" or not str(interrupted.activity_spot_id).is_empty():
				_fail("Interruption did not release the activity spot")
				return
			var after_interrupt := _action_map(
				world.get_available_social_actions(world.player_id, agent_id)
			)
			for blocked_type: String in REQUIRED_ACTIONS:
				if after_interrupt.has(blocked_type):
					_fail("Activity affordance remained after interruption: %s" % blocked_type)
					return
		outcomes[action_type] = str(result.decision.decision)
	print("D2_ACTIVITY_AFFORDANCES_OK actions=%d outcomes=%s effects=systemic money_conserved=true" % [
		REQUIRED_ACTIONS.size(), JSON.stringify(outcomes),
	])
	quit(0)


func _prepared_world(required_agent_id: int = -1) -> Dictionary:
	var world := SimulationWorldScript.new(929292)
	world.advance(4)
	world.update_adaptive_focus(1, [], 60)
	var agent_id := required_agent_id
	if agent_id < 0:
		for candidate_id: int in world.get_adaptive_population_snapshot().refined_light_ids:
			var state: Dictionary = world.get_light_agent_schedule_state(candidate_id, world.tick)
			if str(state.execution_phase) == "PERFORM" and str(state.activity) in [
				"WORK", "TEAMWORK", "ERRANDS", "COMMUNITY", "HEALTH", "CRAFT",
				"JOB_SEARCH", "STUDY",
			]:
				agent_id = candidate_id
				break
	if agent_id < 0:
		_fail("No performing assistable NPC found for D2 fixture")
		return {}
	var activation: Dictionary = world.activate_light_agent_as_person(agent_id, "D2_TEST")
	if not bool(activation.get("ok", false)):
		_fail("Could not activate D2 fixture agent")
		return {}
	world.introduce_people(world.player_id, agent_id)
	for _index in range(8):
		var rapport: Dictionary = _action_map(
			world.get_available_social_actions(world.player_id, agent_id)
		).get("BuildRapport", {})
		if rapport.is_empty():
			_fail("D2 fixture lost BuildRapport")
			return {}
		world.perform_social_action(
			"BuildRapport", world.player_id, agent_id, rapport.context
		)
	return {"world": world, "agent_id": agent_id}


func _action_map(actions: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for action: Dictionary in actions:
		result[str(action.type)] = action
	return result


func _has_effect(effects: Array, effect_type: String) -> bool:
	for effect: Dictionary in effects:
		if str(effect.get("type", "")) == effect_type:
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
