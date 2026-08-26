class_name DecisionEngine
extends RefCounted

const ACCEPT_THRESHOLD := 0.45
const NEGOTIATE_THRESHOLD := 0.05


static func evaluate(
	action_type: String,
	relationship: RefCounted,
	target_person: RefCounted,
	context: Dictionary = {}
) -> Dictionary:
	var costs := _action_costs(action_type, context)
	var traits: Dictionary = target_person.personality

	var positive_components: Array[Dictionary] = [
		{"type": "TRUST", "value": relationship.trust * 1.3},
		{"type": "AFFECTION", "value": relationship.affection},
		{"type": "OBLIGATION", "value": relationship.obligation * 1.5},
		{"type": "EXPECTED_BENEFIT", "value": costs.expected_benefit},
	]
	var negative_components: Array[Dictionary] = [
		{"type": "PERSONAL_RISK", "value": costs.risk * 1.5},
		{"type": "PERSONAL_COST", "value": costs.personal_cost},
		{"type": "LOW_TRUST", "value": (1.0 - relationship.trust) * 0.35},
		{"type": "MORAL_RESISTANCE", "value": costs.moral_resistance},
	]

	var utility := 0.0
	for component: Dictionary in positive_components:
		utility += component.value
	for component: Dictionary in negative_components:
		utility -= component.value

	var decision := "REFUSE"
	if utility >= ACCEPT_THRESHOLD:
		decision = "ACCEPT"
	elif utility >= NEGOTIATE_THRESHOLD:
		decision = "NEGOTIATE"

	var primary_reason := negative_components[0]
	for component: Dictionary in negative_components:
		if component.value > primary_reason.value:
			primary_reason = component

	var disclosure_score: float = (
		relationship.trust
		+ float(traits.get("honesty", 0.5)) * 0.35
		+ relationship.familiarity * 0.2
		- costs.secrecy * 0.5
		- relationship.fear * 0.4
	)
	var disclosure_level := "LOW"
	if disclosure_score >= 0.65:
		disclosure_level = "HIGH"
	elif disclosure_score >= 0.25:
		disclosure_level = "MEDIUM"

	return {
		"decision": decision,
		"utility": utility,
		"primary_reason": primary_reason.duplicate(true),
		"positive_components": positive_components,
		"negative_components": negative_components,
		"disclosure_score": disclosure_score,
		"disclosure_level": disclosure_level,
		"risk": costs.risk,
		"personal_cost": costs.personal_cost,
	}


static func _action_costs(action_type: String, context: Dictionary) -> Dictionary:
	var defaults := {
		"expected_benefit": 0.0,
		"personal_cost": 0.25,
		"risk": 0.35,
		"moral_resistance": 0.0,
		"secrecy": 0.25,
	}
	if action_type in [
		"GatherInformation", "DeliverMessage", "OfferSupport",
		"VerifySituation", "CoordinateResource"
	]:
		defaults.expected_benefit = 0.70
		defaults.personal_cost = 0.06
		defaults.risk = 0.08
		defaults.secrecy = 0.10
	match action_type:
		"BuildRapport":
			defaults.expected_benefit = 0.75
			defaults.personal_cost = 0.02
			defaults.risk = 0.02
			defaults.secrecy = 0.0
		"OfferHelp":
			defaults.expected_benefit = 0.75
			defaults.personal_cost = 0.03
			defaults.risk = 0.05
			defaults.secrecy = 0.0
		"JoinActivity":
			defaults.expected_benefit = 0.68
			defaults.personal_cost = 0.04
			defaults.risk = 0.03
			defaults.secrecy = 0.0
		"AskAbout":
			defaults.expected_benefit = 0.05
			defaults.personal_cost = 0.10
			defaults.risk = 0.25
		"AskLocalNews":
			defaults.expected_benefit = 0.12
			defaults.personal_cost = 0.05
			defaults.risk = 0.10
			defaults.secrecy = 0.12
		"AskFavor":
			defaults.personal_cost = 0.55
			defaults.risk = 0.65
			defaults.moral_resistance = 0.05
			defaults.secrecy = 0.45
		"AskIntroduction":
			defaults.expected_benefit = 0.02
			defaults.personal_cost = 0.25
			defaults.risk = 0.40
			defaults.secrecy = 0.35
		"AskInvitation":
			defaults.expected_benefit = 0.05
			defaults.personal_cost = 0.20
			defaults.risk = 0.25
			defaults.secrecy = 0.35
		"RequestAccess":
			defaults.expected_benefit = 0.05
			defaults.personal_cost = 0.22
			defaults.risk = 0.28
			defaults.secrecy = 0.35

	# Persistent NPCs read district fields as ambient pressure. The field never
	# decides an action by itself; it modifies the same explicit utility costs.
	defaults.risk = clampf(
		float(defaults.risk)
		+ float(context.get("district_fear", 0.0)) * 0.08
		+ float(context.get("district_social_tension", 0.0)) * 0.04,
		0.0, 1.0
	)
	defaults.personal_cost = clampf(
		float(defaults.personal_cost)
		+ (1.0 - float(context.get("district_employment", 1.0))) * 0.04,
		0.0, 1.0
	)

	for key: String in defaults:
		if context.has(key):
			defaults[key] = clampf(float(context[key]), 0.0, 1.0)
	return defaults
