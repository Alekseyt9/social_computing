extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var first_world := SimulationWorldScript.new(424242)
	var second_world := SimulationWorldScript.new(424242)
	var refined: Array = first_world.get_adaptive_population_snapshot().refined_light_ids
	if refined.is_empty():
		_fail("No refined citizen is available for interaction")
		return
	var agent_id := int(refined[0])
	var money_before := int(first_world.get_light_population_snapshot().total_money_cents)
	var first_activation: Dictionary = first_world.activate_light_agent_as_person(
		agent_id, "PLAYER_INTERACTION"
	)
	var second_activation: Dictionary = second_world.activate_light_agent_as_person(
		agent_id, "PLAYER_INTERACTION"
	)
	if not first_activation.ok or not second_activation.ok:
		_fail("Adaptive citizen activation failed: %s" % first_activation)
		return
	if not first_world.has_person(agent_id):
		_fail("Activated LightAgent did not become a PersonModel")
		return
	if first_world.get_light_agent_tier(agent_id) != "PERSISTENT_NPC":
		_fail("Activated citizen did not enter the persistent adaptive tier")
		return
	if first_world.get_person_name(agent_id) != second_world.get_person_name(agent_id) or (
		first_world.get_person_role(agent_id) != second_world.get_person_role(agent_id)
	):
		_fail("Generated citizen identity is not deterministic")
		return
	var first_traits: Dictionary = first_world.get_debug_inspector(
		agent_id, first_world.player_id
	).person.personality
	var second_traits: Dictionary = second_world.get_debug_inspector(
		agent_id, second_world.player_id
	).person.personality
	if first_traits != second_traits:
		_fail("Generated citizen personality is not deterministic")
		return
	if first_world.is_person_known_to(first_world.player_id, agent_id):
		_fail("Activation leaked a stranger's identity to the player")
		return
	var actions: Array[Dictionary] = first_world.get_available_social_actions(
		first_world.player_id, agent_id
	)
	if actions.size() != 1 or str(actions[0].type) != "IntroduceSelf":
		_fail("A stranger did not enter the universal introduction flow: %s" % actions)
		return
	var introduction: Dictionary = first_world.perform_social_action(
		"IntroduceSelf", first_world.player_id, agent_id
	)
	if not introduction.ok or not first_world.is_person_known_to(
		first_world.player_id, agent_id
	):
		_fail("Player could not form a persistent relationship with citizen")
		return
	actions = first_world.get_available_social_actions(first_world.player_id, agent_id)
	var action_types := PackedStringArray()
	for action: Dictionary in actions:
		action_types.append(str(action.type))
	if "BuildRapport" not in action_types or "OfferHelp" not in action_types:
		_fail("Activated citizen did not receive model-driven social actions: %s" % action_types)
		return
	var name_before := first_world.get_person_name(agent_id)
	first_world.advance(7 * 288)
	if first_world.get_person_name(agent_id) != name_before or not first_world.has_person(agent_id):
		_fail("Citizen identity did not survive background simulation")
		return
	var adaptive: Dictionary = first_world.get_adaptive_population_snapshot()
	var money_after := int(first_world.get_light_population_snapshot().total_money_cents)
	if not adaptive.conservation.all or money_before != money_after:
		_fail("Activation broke population/money conservation: %s" % adaptive.conservation)
		return
	if first_world.get_activated_adaptive_person_ids() != [agent_id]:
		_fail("Activated citizen registry is inconsistent")
		return
	if not first_world.validate_adaptive_population().is_empty():
		_fail("Adaptive validation failed after interactive promotion")
		return
	print("ADAPTIVE_CITIZEN_OK id=%d name=%s role=%s actions=%s persistent=true conservation=true" % [
		agent_id,
		first_world.get_person_name(agent_id),
		first_world.get_person_role(agent_id),
		",".join(action_types),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
