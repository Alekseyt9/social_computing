extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var need_types: Dictionary = {}
	var task_kinds: Dictionary = {}
	for simulation_seed in range(1, 33):
		var world := SimulationWorldScript.new(simulation_seed)
		for person_id in range(2, 22):
			var profile: Dictionary = world.get_need_profile(person_id)
			need_types[str(profile.get("dominant_type", ""))] = true

		for requester_id in range(2, 22):
			var actions: Array[Dictionary] = world.get_available_social_actions(
				world.player_id, requester_id
			)
			var introduction := _find_action(actions, "IntroduceSelf")
			if not introduction.is_empty():
				_perform(world, requester_id, introduction)
			actions = world.get_available_social_actions(world.player_id, requester_id)
			var help_action := _find_action(actions, "OfferHelp")
			if help_action.is_empty():
				_fail("Seed %d produced no OfferHelp action for person %d" % [simulation_seed, requester_id])
				return
			var help_result: Dictionary = _perform(world, requester_id, help_action)
			if not help_result.get("ok", false):
				return
		for task: Dictionary in world.get_active_tasks_for(world.player_id):
			task_kinds[str(task.kind)] = true

	if need_types.size() < 5:
		_fail("Need model did not cover all dimensions: %s" % need_types.keys())
		return
	if task_kinds.size() < 5:
		_fail("Task generation lacks seed diversity: %s" % task_kinds.keys())
		return
	if not _assert_task_lifecycle():
		return
	if not _assert_information_propagation():
		return

	print("DIVERSITY_BATCH_OK seeds=32 needs=%s task_kinds=%s" % [
		str(need_types.keys()), str(task_kinds.keys()),
	])
	quit(0)


func _assert_task_lifecycle() -> bool:
	var world := SimulationWorldScript.new(73)
	var actor_id: int = world.player_id
	var requester_id := 2
	var help := _find_action(world.get_available_social_actions(actor_id, requester_id), "OfferHelp")
	var help_result: Dictionary = _perform(world, requester_id, help)
	if not help_result.get("ok", false):
		return false
	var incomplete_effect_render: String = SocialRendererScript.sanitize_output(
		"Да, это возможно.", help_result.communicative_act, help_result.template_response
	)
	if incomplete_effect_render != help_result.template_response:
		return _fail("Renderer accepted a reply that omitted the computed task counterpart")
	var tasks: Array[Dictionary] = world.get_active_tasks_for(actor_id)
	if tasks.is_empty():
		return _fail("Lifecycle fixture created no task")
	var task: Dictionary = tasks[0]
	var counterpart_id := int(task.counterpart_id)
	var before: Dictionary = world.get_relationship_state(requester_id, actor_id)

	var meeting_actions: Array[Dictionary] = world.get_available_social_actions(actor_id, counterpart_id)
	var introduce := _find_action(meeting_actions, "IntroduceSelf")
	if not introduce.is_empty():
		_perform(world, counterpart_id, introduce)
	for _attempt in range(5):
		var actions: Array[Dictionary] = world.get_available_social_actions(actor_id, counterpart_id)
		var task_action := _find_action(actions, str(task.operator))
		if not task_action.is_empty():
			var result: Dictionary = _perform(world, counterpart_id, task_action)
			for effect: Dictionary in result.get("effects", []):
				if effect.get("type") == "TASK_COMPLETED":
					var after: Dictionary = world.get_relationship_state(requester_id, actor_id)
					if float(after.obligation) <= float(before.obligation):
						return _fail("Completed task did not increase requester obligation")
					if world.snapshot().completed_task_count != 1:
						return _fail("Completed task was not stored in canonical state")
					return true
		var rapport := _find_action(actions, "BuildRapport")
		if not rapport.is_empty():
			_perform(world, counterpart_id, rapport)
	return _fail("Task operator never completed after rapport building")


func _assert_information_propagation() -> bool:
	var first := SimulationWorldScript.new(91)
	var second := SimulationWorldScript.new(91)
	var knowledge_before: int = first.get_knowledge_edge_count()
	var first_state: Dictionary = first.advance(360)
	var second_state: Dictionary = second.advance(360)
	if first_state != second_state:
		return _fail("Information propagation broke determinism")
	if first.get_knowledge_edge_count() <= knowledge_before:
		return _fail("No fact propagated across NPC relationships in 360 ticks")
	return true


func _find_action(actions: Array[Dictionary], action_type: String) -> Dictionary:
	for action: Dictionary in actions:
		if str(action.get("type", "")) == action_type:
			return action
	return {}


func _perform(world: RefCounted, target_id: int, action: Dictionary) -> Dictionary:
	if action.is_empty():
		_fail("Attempted to perform an empty action")
		return {}
	var result: Dictionary = world.perform_social_action(
		str(action.type), world.player_id, target_id, action.get("context", {})
	)
	if not result.get("ok", false):
		_fail("Operator %s failed: %s" % [action.type, result])
	return result


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
