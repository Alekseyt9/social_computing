extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var world := SimulationWorldScript.new(20250308)
	var actor_id: int = world.player_id
	var first_press_contact := 5
	var meeting_actions: Array[Dictionary] = world.get_available_social_actions(
		actor_id, first_press_contact
	)
	var introduce_action := _find_action(meeting_actions, "IntroduceSelf")
	if introduce_action.is_empty():
		_fail("Unknown person did not expose model-driven IntroduceSelf operator")
		return
	var meeting: Dictionary = _perform(world, actor_id, first_press_contact, introduce_action)
	if not meeting.get("ok", false):
		_fail("Could not meet the first alternative-route contact")
		return
	if not _find_action(
		world.get_available_social_actions(actor_id, first_press_contact), "AskInvitation"
	).is_empty():
		_fail("A non-organizer exposed AskInvitation without a capability fact")
		return

	var current_contact := first_press_contact
	var visited: Dictionary = {}
	while str(world.get_goal_state(actor_id).stage) != "REQUEST_INVITATION":
		if visited.has(current_contact):
			_fail("Computed social graph entered a cycle at person %d" % current_contact)
			return
		visited[current_contact] = true
		var next_contact := _discover_and_unlock_next_contact(world, actor_id, current_contact)
		if next_contact == -1:
			return
		current_contact = next_contact

	if not _obtain_invitation(world, actor_id, current_contact):
		return
	if not world.has_aurora_invitation(actor_id):
		_fail("Invitation effect was not stored in canonical world state")
		return
	var entry: Dictionary = world.attempt_enter_aurora(actor_id)
	if not entry.get("ok", false):
		_fail("Aurora entrance rejected a valid computed invitation: %s" % entry)
		return
	if str(world.get_goal_state(actor_id).stage) != "COMPLETED":
		_fail("Goal did not reach COMPLETED after entering Aurora")
		return

	print("FULL_PLAYTHROUGH_OK contacts=%s invitation=true entered=true events=%d" % [
		str(visited.keys()), world.snapshot().event_count,
	])
	quit(0)


func _discover_and_unlock_next_contact(
	world: RefCounted, actor_id: int, target_id: int
) -> int:
	for _attempt in range(10):
		var actions: Array[Dictionary] = world.get_available_social_actions(actor_id, target_id)
		var introduction := _find_action(actions, "AskIntroduction")
		if not introduction.is_empty():
			var intro_result: Dictionary = _perform(world, actor_id, target_id, introduction)
			for effect: Dictionary in intro_result.get("effects", []):
				if effect.get("type") == "INTRODUCTION_CREATED":
					return int(effect.person_id)

		var help := _find_action(actions, "OfferHelp")
		if not help.is_empty():
			_perform(world, actor_id, target_id, help)

		var rapport := _find_action(actions, "BuildRapport")
		if not rapport.is_empty():
			_perform(world, actor_id, target_id, rapport)

		actions = world.get_available_social_actions(actor_id, target_id)
		var inquiry := _find_action(actions, "AskAbout")
		if not inquiry.is_empty():
			_perform(world, actor_id, target_id, inquiry)

	_fail("No computable introduction became available through person %d" % target_id)
	return -1


func _obtain_invitation(world: RefCounted, actor_id: int, organizer_id: int) -> bool:
	for _attempt in range(10):
		var actions: Array[Dictionary] = world.get_available_social_actions(actor_id, organizer_id)
		var request := _find_action(actions, "AskInvitation")
		if request.is_empty():
			return _fail("Organizer does not expose computed AskInvitation operator")
		var result: Dictionary = _perform(world, actor_id, organizer_id, request)
		for effect: Dictionary in result.get("effects", []):
			if effect.get("type") == "INVITATION_GRANTED":
				return true

		var help := _find_action(actions, "OfferHelp")
		if not help.is_empty():
			_perform(world, actor_id, organizer_id, help)
		var rapport := _find_action(actions, "BuildRapport")
		if not rapport.is_empty():
			_perform(world, actor_id, organizer_id, rapport)
	return _fail("Utility model never granted the invitation")


func _find_action(actions: Array[Dictionary], action_type: String) -> Dictionary:
	for action: Dictionary in actions:
		if str(action.get("type", "")) == action_type:
			return action
	return {}


func _perform(
	world: RefCounted, actor_id: int, target_id: int, action: Dictionary
) -> Dictionary:
	var result: Dictionary = world.perform_social_action(
		str(action.type), actor_id, target_id, action.get("context", {})
	)
	if not result.get("ok", false):
		_fail("Operator %s failed its preconditions: %s" % [action.type, result])
	return result


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
