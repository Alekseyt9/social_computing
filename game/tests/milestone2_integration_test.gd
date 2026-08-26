extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var world := SimulationWorldScript.new(314159)
	var actor_id: int = world.player_id
	world.advance(288)
	var population: Dictionary = world.get_light_population_snapshot()
	if int(population.job_changes) <= 0 or int(population.gossip_transfers) <= 0:
		_fail("Light population produced no causal district signals")
		return
	var found_population_signal := false
	for event: Dictionary in world.get_recent_events(80):
		if str(event.type) == "district_population_signal":
			found_population_signal = true
			break
	if not found_population_signal:
		_fail("Population events were not imported into the canonical EventStore")
		return
	if not world.get_district_opportunities(actor_id).is_empty():
		_fail("Player learned district opportunities without an observation source")
		return

	var source_id := -1
	for person_id in range(2, 22):
		if not world.is_person_known_to(actor_id, person_id):
			world.introduce_people(actor_id, person_id)
		if not _find_action(
			world.get_available_social_actions(actor_id, person_id), "AskLocalNews"
		).is_empty():
			source_id = person_id
			break
	if source_id == -1:
		_fail("No persistent NPC received a lightweight population signal")
		return

	var disclosed := false
	for _attempt in range(12):
		var actions: Array[Dictionary] = world.get_available_social_actions(actor_id, source_id)
		var ask := _find_action(actions, "AskLocalNews")
		if not ask.is_empty():
			var result: Dictionary = world.perform_social_action(
				"AskLocalNews", actor_id, source_id, ask.context
			)
			for fact: Dictionary in result.communicative_act.revealed_facts:
				if str(fact.type) == "DISTRICT_OPPORTUNITY":
					disclosed = true
					break
		if disclosed:
			break
		var rapport := _find_action(actions, "BuildRapport")
		if not rapport.is_empty():
			world.perform_social_action("BuildRapport", actor_id, source_id, rapport.context)
	if not disclosed:
		_fail("Computed dialogue never disclosed the population-driven opportunity")
		return
	var known_opportunities: Array[Dictionary] = world.get_district_opportunities(actor_id)
	if known_opportunities.is_empty() or str(known_opportunities[0].summary).is_empty():
		_fail("Disclosed opportunity did not enter Player Knowledge")
		return

	# Thirty simulated days exercise schedules, jobs, money and bounded gossip
	# without graphics or an LLM.
	world.advance(30 * 288 - 288)
	population = world.get_light_population_snapshot()
	if int(population.population) != 1200:
		_fail("Population changed unexpectedly during the stability run")
		return
	if int(population.employed) + int(population.unemployed) != 1200:
		_fail("Employment totals violated population consistency")
		return
	if not bool(population.money_conserved):
		_fail("Money was created or destroyed during the stability run")
		return
	if int(population.rumor_knowledge_edges) > int(population.population) * 8:
		_fail("Per-agent gossip memory exceeded its bound")
		return
	var errors: Array[String] = world.validate_light_population()
	if not errors.is_empty():
		_fail("Invalid references after 30 simulated days: %s" % errors)
		return
	print("MILESTONE2_INTEGRATION_OK days=30 source=%s opportunities=%d events=%d job_changes=%d money_conserved=true" % [
		world.get_person_name(source_id),
		known_opportunities.size(),
		world.snapshot().event_count,
		population.job_changes,
	])
	quit(0)


func _find_action(actions: Array[Dictionary], action_type: String) -> Dictionary:
	for action: Dictionary in actions:
		if str(action.get("type", "")) == action_type:
			return action
	return {}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
