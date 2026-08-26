extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var world := SimulationWorldScript.new(424242)
	world.advance(120) # daytime schedules place workers at their workplaces
	var focus_aurora: Dictionary = world.update_adaptive_focus(1, [], 60)
	if not focus_aurora.ok or int(focus_aurora.state.light_agent_count) != 60:
		_fail("Place relevance did not maintain the LightAgent budget")
		return
	for agent_id: int in focus_aurora.state.refined_light_ids:
		if int(world.get_light_agent_view(agent_id).current_place_id) != 1:
			_fail("Aurora focus refined an unrelated resident %d" % agent_id)
			return
	var transitions_after_first := int(focus_aurora.state.transition_count)
	var repeated: Dictionary = world.update_adaptive_focus(1, [], 60)
	if int(repeated.changed_tier_count) != 0 or int(repeated.state.transition_count) != transitions_after_first:
		_fail("Identical relevance input caused refinement thrashing")
		return

	var remote_relevant_id := -1
	for agent_id in range(10_000, 11_200):
		if int(world.get_light_agent_view(agent_id).current_place_id) == 3:
			remote_relevant_id = agent_id
			break
	if remote_relevant_id == -1:
		_fail("Test fixture has no remote resident")
		return
	var social_focus: Dictionary = world.update_adaptive_focus(1, [remote_relevant_id], 60)
	if world.get_light_agent_tier(remote_relevant_id) != "LIGHT_AGENT":
		_fail("Social relevance did not override physical distance")
		return
	if int(social_focus.state.light_agent_count) != 60:
		_fail("Social relevance exceeded the refinement budget")
		return

	var promotion: Dictionary = world.promote_light_agent_to_persistent(
		remote_relevant_id, "GOAL_RELEVANCE"
	)
	if not promotion.ok:
		_fail("Goal-relevant resident could not become persistent")
		return
	var cafe_focus: Dictionary = world.update_adaptive_focus(2, [], 45)
	if world.get_light_agent_tier(remote_relevant_id) != "PERSISTENT_NPC":
		_fail("Place change coarsened a persistent relevant resident")
		return
	if int(cafe_focus.state.light_agent_count) != 45:
		_fail("Updated place focus ignored its new budget")
		return
	for agent_id: int in cafe_focus.state.refined_light_ids:
		var view: Dictionary = world.get_light_agent_view(agent_id)
		var is_persistent_contact: bool = agent_id in promotion.profile.dynamic_state.local_contact_ids
		if int(view.current_place_id) != 2 and not is_persistent_contact:
			_fail("Cafe focus selected an agent without local or social relevance")
			return
	var state: Dictionary = world.get_adaptive_population_snapshot()
	if not bool(state.conservation.all):
		_fail("Automatic relevance policy violated conservation")
		return
	if not world.validate_adaptive_population().is_empty():
		_fail("Automatic relevance policy left invalid tier references")
		return
	print("MILESTONE3_RELEVANCE_OK place_focus=45 persistent=1 remote_social=true thrash=0 conservation=true")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
