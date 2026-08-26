class_name DistrictSocialFieldSystem
extends RefCounted

## Continuous district-level state. Agents contribute through population
## summaries and social outcomes; the resulting fields feed back into agent
## employment and persistent-NPC risk evaluation.

var tick: int = 0
var wealth: float = 0.5
var fear: float = 0.1
var crime: float = 0.08
var employment: float = 0.8
var trust: float = 0.55
var social_tension: float = 0.15
var information_exposure: float = 0.05
var stress: float = 0.2
var spending: float = 0.45
var business_health: float = 0.55
var _update_count: int = 0
var _social_contributions: Dictionary = {"trust": 0.0, "tension": 0.0, "fear": 0.0}


func _init(population_snapshot: Dictionary = {}) -> void:
	if not population_snapshot.is_empty():
		_initialize_from_population(population_snapshot)


func advance_day(population_snapshot: Dictionary) -> Dictionary:
	var population := maxi(1, int(population_snapshot.get("population", 1)))
	var observed_employment := clampf(
		float(population_snapshot.get("employed", 0)) / float(population), 0.0, 1.0
	)
	var average_money := float(population_snapshot.get("total_money_cents", 0)) / float(population)
	var observed_wealth := clampf(average_money / 200_000.0, 0.02, 1.0)
	var agent_feedback: Dictionary = population_snapshot.get("feedback", {})
	var observed_agent_wealth := clampf(
		float(agent_feedback.get("average_wealth", observed_wealth)), 0.0, 1.0
	)
	var observed_agent_stress := clampf(
		float(agent_feedback.get("average_stress", stress)), 0.0, 1.0
	)
	var observed_agent_spending := clampf(
		float(agent_feedback.get("average_spending", spending)), 0.0, 1.0
	)
	observed_wealth = observed_wealth * 0.70 + observed_agent_wealth * 0.30
	var rumor_capacity := float(population * 8)
	var observed_information := clampf(
		float(population_snapshot.get("rumor_knowledge_edges", 0)) / maxf(1.0, rumor_capacity),
		0.0, 1.0
	)

	var unemployment := 1.0 - employment
	var target_stress := clampf(
		0.06 + unemployment * 0.72 + fear * 0.24 + social_tension * 0.22
		+ (1.0 - wealth) * 0.15,
		0.0, 1.0
	)
	target_stress = clampf(target_stress * 0.80 + observed_agent_stress * 0.20, 0.0, 1.0)
	var target_spending := clampf(
		wealth * (1.0 - target_stress * 0.72) * (0.75 + trust * 0.25), 0.0, 1.0
	)
	target_spending = clampf(
		target_spending * 0.75 + observed_agent_spending * 0.25, 0.0, 1.0
	)
	var target_business := clampf(
		0.10 + target_spending * 0.92 - crime * 0.20 - social_tension * 0.12,
		0.0, 1.0
	)
	var feedback_employment := clampf(
		observed_employment * 0.72 + target_business * 0.25
		- target_stress * 0.08 - social_tension * 0.06,
		0.0, 1.0
	)
	var target_crime := clampf(
		0.02 + (1.0 - feedback_employment) * 0.32 + target_stress * 0.24
		- trust * 0.20 - observed_wealth * 0.08,
		0.0, 1.0
	)
	var target_fear := clampf(0.03 + target_crime * 0.68 + social_tension * 0.25, 0.0, 1.0)
	var target_tension := clampf(
		0.03 + (1.0 - feedback_employment) * 0.30 + target_stress * 0.28
		+ target_fear * 0.18 - trust * 0.24,
		0.0, 1.0
	)
	var target_trust := clampf(
		0.62 - target_crime * 0.25 - target_tension * 0.30
		+ observed_information * 0.05,
		0.0, 1.0
	)

	stress = _approach(stress, target_stress, 0.28)
	spending = _approach(spending, target_spending, 0.25)
	business_health = _approach(business_health, target_business, 0.22)
	employment = _approach(employment, feedback_employment, 0.22)
	crime = _approach(crime, target_crime, 0.20)
	fear = _approach(fear, target_fear, 0.22)
	social_tension = _approach(social_tension, target_tension, 0.20)
	trust = _approach(trust, target_trust, 0.16)
	wealth = _approach(
		wealth,
		clampf(observed_wealth * 0.65 + business_health * 0.25 + spending * 0.10, 0.0, 1.0),
		0.12
	)
	information_exposure = _approach(information_exposure, observed_information, 0.30)
	_apply_social_contributions()
	tick = int(population_snapshot.get("tick", tick + 288))
	_update_count += 1
	return snapshot()


func apply_shock(shock: Dictionary) -> Dictionary:
	wealth = clampf(wealth + float(shock.get("wealth_delta", 0.0)), 0.0, 1.0)
	fear = clampf(fear + float(shock.get("fear_delta", 0.0)), 0.0, 1.0)
	crime = clampf(crime + float(shock.get("crime_delta", 0.0)), 0.0, 1.0)
	employment = clampf(employment + float(shock.get("employment_delta", 0.0)), 0.0, 1.0)
	trust = clampf(trust + float(shock.get("trust_delta", 0.0)), 0.0, 1.0)
	social_tension = clampf(
		social_tension + float(shock.get("social_tension_delta", 0.0)), 0.0, 1.0
	)
	stress = clampf(stress + float(shock.get("stress_delta", 0.0)), 0.0, 1.0)
	return snapshot()


func record_social_outcome(action_type: String, decision: String) -> void:
	if decision == "ACCEPT":
		_social_contributions.trust += 0.002 if action_type in ["BuildRapport", "OfferHelp", "JoinActivity"] else 0.0005
		_social_contributions.tension -= 0.001
	elif decision == "REFUSE":
		_social_contributions.tension += 0.001
		_social_contributions.fear += 0.0004


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"wealth": wealth,
		"fear": fear,
		"crime": crime,
		"employment": employment,
		"unemployment": 1.0 - employment,
		"trust": trust,
		"social_tension": social_tension,
		"information_exposure": information_exposure,
		"stress": stress,
		"spending": spending,
		"business_health": business_health,
		"update_count": _update_count,
	}


func validate() -> Array[String]:
	var errors: Array[String] = []
	for key: String in [
		"wealth", "fear", "crime", "employment", "trust", "social_tension",
		"information_exposure", "stress", "spending", "business_health",
	]:
		var value := float(snapshot()[key])
		if is_nan(value) or is_inf(value) or value < 0.0 or value > 1.0:
			errors.append("District field %s is invalid: %s" % [key, value])
	return errors


func _initialize_from_population(population_snapshot: Dictionary) -> void:
	var population := maxi(1, int(population_snapshot.get("population", 1)))
	employment = clampf(float(population_snapshot.get("employed", 0)) / float(population), 0.0, 1.0)
	wealth = clampf(
		float(population_snapshot.get("total_money_cents", 0)) / float(population) / 200_000.0,
		0.02, 1.0
	)
	stress = clampf(0.10 + (1.0 - employment) * 0.55, 0.0, 1.0)
	spending = clampf(wealth * (1.0 - stress * 0.6), 0.0, 1.0)
	business_health = clampf(0.15 + spending * 0.85, 0.0, 1.0)


func _apply_social_contributions() -> void:
	trust = clampf(trust + float(_social_contributions.trust), 0.0, 1.0)
	social_tension = clampf(
		social_tension + float(_social_contributions.tension), 0.0, 1.0
	)
	fear = clampf(fear + float(_social_contributions.fear), 0.0, 1.0)
	_social_contributions = {"trust": 0.0, "tension": 0.0, "fear": 0.0}


func _approach(current: float, target: float, rate: float) -> float:
	return clampf(current + (target - current) * rate, 0.0, 1.0)
