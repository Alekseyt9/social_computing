extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var first := SimulationWorldScript.new(550055)
	var second := SimulationWorldScript.new(550055)
	var agent_id := int(first.get_adaptive_population_snapshot().refined_light_ids[0])
	for world: RefCounted in [first, second]:
		var activation: Dictionary = world.activate_light_agent_as_person(
			agent_id, "PLAYER_INTERACTION"
		)
		if not activation.ok:
			_fail("Could not activate MS5 test person")
			return
		var introduction: Dictionary = world.introduce_people(world.player_id, agent_id)
		if not introduction.ok:
			_fail("Could not make persistent person known to observer")
			return
		world.advance(14 * 288)
	var first_history: Array[Dictionary] = first.get_persistent_background_history(
		agent_id, first.player_id
	)
	var second_history: Array[Dictionary] = second.get_persistent_background_history(
		agent_id, second.player_id
	)
	if first_history.is_empty():
		_fail("Two offscreen weeks produced no reconstructed background history")
		return
	if first_history != second_history:
		_fail("Lazy history reconstruction is not deterministic")
		return
	for event: Dictionary in first_history:
		if not bool(event.canonical) or int(event.canonical_fact_id) <= 0:
			_fail("Disclosed reconstructed event did not become canonical: %s" % event)
			return
		if not first.person_knows_fact(first.player_id, int(event.canonical_fact_id)):
			_fail("Canonical background event is not in observer knowledge")
			return
	var repeated: Array[Dictionary] = first.get_persistent_background_history(
		agent_id, first.player_id
	)
	if not repeated.is_empty():
		_fail("Repeated history query duplicated already materialized events")
		return
	var profile: Dictionary = first.get_persistent_history_profile(agent_id)
	if profile.anchors.size() != 2 or profile.canonical_events.size() != first_history.size():
		_fail("History anchors/canonical event store are inconsistent: %s" % profile)
		return
	var stranger_id := int(first.get_adaptive_population_snapshot().refined_light_ids[0])
	first.activate_light_agent_as_person(stranger_id, "BACKGROUND_RELEVANCE")
	first.advance(8 * 288)
	if not first.get_persistent_background_history(stranger_id, first.player_id).is_empty():
		_fail("Unknown persistent history leaked to the player")
		return
	var errors: Array[String] = first.validate_lazy_histories()
	if not errors.is_empty():
		_fail("Lazy history validation failed: %s" % errors)
		return
	print("MILESTONE5_HISTORY_OK person=%d weeks=2 anchors=%d events=%d deterministic=true canonical=true no_duplicates=true" % [
		agent_id, profile.anchors.size(), first_history.size(),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
