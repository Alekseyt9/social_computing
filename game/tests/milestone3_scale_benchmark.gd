extends SceneTree

const LightPopulationScript := preload("res://agents/light_population_simulation.gd")
const AdaptivePopulationScript := preload("res://adaptive/adaptive_population_system.gd")

const POPULATION := 10_000
const DAYS := 7


func _init() -> void:
	_run()


func _run() -> void:
	var started_ms := Time.get_ticks_msec()
	var population := LightPopulationScript.new(8675309, POPULATION)
	var adaptive := AdaptivePopulationScript.new(population, 20, 100)
	population.advance(DAYS * 288)
	var population_state: Dictionary = population.snapshot()
	var adaptive_state: Dictionary = adaptive.snapshot()
	var elapsed_ms := Time.get_ticks_msec() - started_ms

	if int(population_state.population) != POPULATION:
		_fail("10k benchmark lost population records")
		return
	if int(population_state.employed) + int(population_state.unemployed) != POPULATION:
		_fail("10k employment totals violate conservation")
		return
	if not bool(population_state.money_conserved) or not bool(adaptive_state.conservation.all):
		_fail("10k adaptive conservation failed")
		return
	if str(population_state.storage.layout) != "STRUCT_OF_ARRAYS" or (
		int(population_state.storage.dictionary_records) != 0
	):
		_fail("10k residents are not using packed storage")
		return
	var naive_detailed_steps := POPULATION * (
		int(DAYS * 288 / 12) + int(DAYS * 288 / 24)
	)
	var actual_steps := (
		int(population_state.detailed_agent_steps)
		+ int(population_state.aggregate_agent_steps)
	)
	if actual_steps >= int(naive_detailed_steps * 0.15):
		_fail("Cohort cadence did not materially reduce agent updates: %d / %d" % [
			actual_steps, naive_detailed_steps,
		])
		return
	var validation_errors: Array[String] = adaptive.validate()
	if not validation_errors.is_empty():
		_fail("10k adaptive state has invalid references: %s" % validation_errors)
		return
	# This is a regression ceiling, not a product performance target. It catches
	# accidental quadratic behavior while remaining tolerant of slower CI hosts.
	if elapsed_ms > 15_000:
		_fail("10k seven-day benchmark exceeded 15 seconds: %d ms" % elapsed_ms)
		return
	print("MILESTONE3_SCALE_OK population=%d days=%d elapsed_ms=%d updates=%d naive=%d reduction=%.1f%% cohorts=%d conservation=true" % [
		POPULATION,
		DAYS,
		elapsed_ms,
		actual_steps,
		naive_detailed_steps,
		100.0 * (1.0 - float(actual_steps) / float(naive_detailed_steps)),
		population_state.storage.cohort_count,
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
