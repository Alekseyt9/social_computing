extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	var world := SimulationWorldScript.new(818181)
	if world.get_place_count() < 8:
		_fail("Clinic/workshop places were not added")
		return
	var clinic_seen := false
	var workshop_seen := false
	for agent_id: int in world.get_light_population_snapshot().get("location_counts", {}).keys():
		# The snapshot keys verify the expanded spatial model; schedule samples
		# below verify that residents actually visit the new places.
		clinic_seen = clinic_seen or agent_id == 7
		workshop_seen = workshop_seen or agent_id == 8
	for candidate_id in range(10_000, 10_200):
		clinic_seen = clinic_seen or int(world.get_light_agent_schedule_state(candidate_id, 84).place_id) == 7
		workshop_seen = workshop_seen or int(world.get_light_agent_schedule_state(candidate_id, 30).place_id) == 8
	if not clinic_seen or not workshop_seen:
		_fail("Expanded schedules do not reach clinic/workshop")
		return
	world.introduce_people(world.player_id, 6)
	var refusal_context := _support_context(world, 6)
	var before := world.get_relationship_state(6, world.player_id)
	var refusal: Dictionary = world.perform_social_action(
		"AskDistrictSupport", world.player_id, 6, refusal_context
	)
	var after := world.get_relationship_state(6, world.player_id)
	if not refusal.ok or str(refusal.decision.decision) != "REFUSE" or float(after.resentment) <= float(before.resentment):
		_fail("Refusal did not create a simulated relationship consequence")
		return
	for person_id in [5, 8]:
		world.introduce_people(world.player_id, person_id)
		for _attempt in range(4):
			world.perform_social_action("BuildRapport", world.player_id, person_id, {"topic": "общие дела"})
		var context := _support_context(world, person_id)
		var result: Dictionary = world.perform_social_action(
			"AskDistrictSupport", world.player_id, person_id, context
		)
		if not result.ok or str(result.decision.decision) != "ACCEPT":
			_fail("Computed district support was not reachable through relationships: person=%d context=%s result=%s" % [
				person_id, str(context), str(result),
			])
			return
	var project: Dictionary = world.get_district_project_state(world.player_id)
	var journal: Dictionary = world.get_player_journal_view(world.player_id)
	if project.stage != "COMPLETED" or int(project.progress) < 2:
		_fail("Second systemic goal did not complete from two resource types")
		return
	if float(journal.reputation) <= 0.10 or journal.affiliations.is_empty():
		_fail("Reputation/group consequences are absent from the journal")
		return
	print("SYSTEMIC_EXPANSION_OK contributions=%d reputation=%.2f groups=%d conflict=true places=%d" % [
		int(project.progress), float(journal.reputation), journal.affiliations.size(), world.get_place_count(),
	])
	quit(0)


func _support_context(world: RefCounted, person_id: int) -> Dictionary:
	for action: Dictionary in world.get_available_social_actions(world.player_id, person_id):
		if str(action.type) == "AskDistrictSupport":
			return action.context
	return {}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
