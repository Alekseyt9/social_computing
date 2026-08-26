extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var first := SimulationWorldScript.new(20260826)
	var second := SimulationWorldScript.new(20260826)
	var initial: Dictionary = first.get_light_population_snapshot()
	if int(initial.population) < 1000:
		_fail("MS2 requires at least 1000 lightweight agents: %s" % initial)
		return
	if int(initial.households) < 300 or int(initial.social_groups) < 3:
		_fail("Households or social groups were not generated: %s" % initial)
		return
	if int(initial.employed) + int(initial.unemployed) != int(initial.population):
		_fail("Employment categories do not conserve population")
		return
	if int(initial.local_contact_edges) < int(initial.population) * 3:
		_fail("Sparse local contact graph is too empty")
		return
	if int(initial.local_contact_edges) > int(initial.population) * 10:
		_fail("Local contact graph unexpectedly became dense")
		return
	var validation_errors: Array[String] = first.validate_light_population()
	if not validation_errors.is_empty():
		_fail("Invalid lightweight references: %s" % validation_errors)
		return

	var identity_before: Dictionary = first.get_light_agent_view(10_000)
	first.advance(120)
	second.advance(120)
	var daytime: Dictionary = first.get_light_population_snapshot()
	if daytime != second.get_light_population_snapshot():
		_fail("Light population is not deterministic for an equal seed")
		return
	if daytime.location_counts == initial.location_counts:
		_fail("Schedules did not move agents between places")
		return
	if int(daytime.rumor_knowledge_edges) <= int(initial.rumor_knowledge_edges):
		_fail("Local gossip did not propagate any knowledge")
		return
	if not bool(daytime.money_conserved) or int(daytime.money_transfers) <= 0:
		_fail("Money transfers failed conservation or never happened")
		return

	first.advance(168)
	second.advance(168)
	var day_one: Dictionary = first.get_light_population_snapshot()
	if day_one != second.get_light_population_snapshot():
		_fail("Day-boundary job changes are not deterministic")
		return
	if int(day_one.job_changes) <= 0:
		_fail("No modeled job change occurred during a simulated day")
		return
	if int(day_one.employed) + int(day_one.unemployed) != int(day_one.population):
		_fail("Job changes lost or duplicated agents")
		return
	var identity_after: Dictionary = first.get_light_agent_view(10_000)
	if int(identity_before.id) != int(identity_after.id) or (
		int(identity_before.household_id) != int(identity_after.household_id)
	):
		_fail("Light agent identity was not persistent across simulation")
		return
	validation_errors = first.validate_light_population()
	if not validation_errors.is_empty():
		_fail("Light population became invalid after updates: %s" % validation_errors)
		return
	print("MILESTONE2_FOUNDATION_OK population=%d households=%d employed=%d unemployed=%d contacts=%d gossip=%d job_changes=%d" % [
		day_one.population,
		day_one.households,
		day_one.employed,
		day_one.unemployed,
		day_one.local_contact_edges,
		day_one.gossip_transfers,
		day_one.job_changes,
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
