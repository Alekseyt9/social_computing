extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")

const DAYS := 30


func _init() -> void:
	_run()


func _run() -> void:
	var baseline := SimulationWorldScript.new(13579)
	var shocked := SimulationWorldScript.new(13579)
	var deterministic_copy := SimulationWorldScript.new(13579)
	var shock := {
		"employment_delta": -0.30,
		"wealth_delta": -0.22,
		"crime_delta": 0.24,
		"fear_delta": 0.18,
		"social_tension_delta": 0.22,
		"stress_delta": 0.12,
	}
	shocked.apply_district_field_shock(shock)
	deterministic_copy.apply_district_field_shock(shock)
	baseline.advance(DAYS * 288)
	shocked.advance(DAYS * 288)
	deterministic_copy.advance(DAYS * 288)
	var normal_fields: Dictionary = baseline.get_district_social_fields()
	var shock_fields: Dictionary = shocked.get_district_social_fields()
	if shock_fields != deterministic_copy.get_district_social_fields():
		_fail("Social fields are not deterministic for equal seed and shocks")
		return
	if not (
		float(shock_fields.stress) > float(normal_fields.stress)
		and float(shock_fields.spending) < float(normal_fields.spending)
		and float(shock_fields.business_health) < float(normal_fields.business_health)
		and float(shock_fields.employment) < float(normal_fields.employment)
	):
		_fail("Unemployment feedback loop has wrong direction: normal=%s shock=%s" % [
			normal_fields, shock_fields,
		])
		return
	var normal_population: Dictionary = baseline.get_light_population_snapshot()
	var shock_population: Dictionary = shocked.get_light_population_snapshot()
	if int(shock_population.unemployed) <= int(normal_population.unemployed):
		_fail("Field pressure did not feed back into actual job transitions")
		return
	if not shocked.validate_district_social_fields().is_empty():
		_fail("Social fields escaped finite normalized bounds")
		return
	if int(shock_fields.update_count) != DAYS:
		_fail("Social fields did not update at daily cadence")
		return
	var saw_field_event := false
	for event: Dictionary in shocked.get_recent_events(600):
		if str(event.type) == "district_fields_updated":
			saw_field_event = true
			break
	if not saw_field_event:
		_fail("Daily field update was not logged")
		return

	# Fields influence persistent NPC utility rather than bypassing it.
	var calm := SimulationWorldScript.new(24680)
	var afraid := SimulationWorldScript.new(24680)
	afraid.apply_district_field_shock({
		"fear_delta": 0.75,
		"social_tension_delta": 0.55,
		"employment_delta": -0.35,
	})
	var calm_request: Dictionary = calm.perform_social_action(
		"AskFavor", calm.player_id, 2, {"topic": "сложная просьба"}
	)
	var afraid_request: Dictionary = afraid.perform_social_action(
		"AskFavor", afraid.player_id, 2, {"topic": "сложная просьба"}
	)
	if float(afraid_request.decision.risk) <= float(calm_request.decision.risk) or (
		float(afraid_request.decision.utility) >= float(calm_request.decision.utility)
	):
		_fail("Persistent NPC did not read ambient fear/employment fields")
		return

	# Positive detailed interactions contribute back into the district trust field.
	var social_world := SimulationWorldScript.new(97531)
	var control_world := SimulationWorldScript.new(97531)
	for _index in range(8):
		social_world.perform_social_action(
			"BuildRapport", social_world.player_id, 2, {"topic": "район"}
		)
	social_world.advance(288)
	control_world.advance(288)
	if float(social_world.get_district_social_fields().trust) <= float(
		control_world.get_district_social_fields().trust
	):
		_fail("Agent outcomes did not contribute back to Social Fields")
		return
	print("MILESTONE4_FIELDS_OK days=%d normal_unemployed=%d shock_unemployed=%d stress_delta=%.4f spending_delta=%.4f business_delta=%.4f deterministic=true bounded=true" % [
		DAYS,
		normal_population.unemployed,
		shock_population.unemployed,
		float(shock_fields.stress) - float(normal_fields.stress),
		float(shock_fields.spending) - float(normal_fields.spending),
		float(shock_fields.business_health) - float(normal_fields.business_health),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
