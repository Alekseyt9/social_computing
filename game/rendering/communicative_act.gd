class_name CommunicativeActFactory
extends RefCounted


static func build(
	action_type: String,
	decision_result: Dictionary,
	relationship: RefCounted,
	target_person: RefCounted,
	context: Dictionary,
	revealed_facts: Array[Dictionary],
	effects: Array[Dictionary] = []
) -> Dictionary:
	return {
		"act": _act_name(decision_result.decision),
		"action_type": action_type,
		"decision": decision_result.decision,
		"reason": decision_result.primary_reason.duplicate(true),
		"disclosure_level": decision_result.disclosure_level,
		"topic": str(context.get("topic", "")),
		"revealed_facts": revealed_facts.duplicate(true),
		"effects": effects.duplicate(true),
		"emotion": {
			"fear": clampf(float(decision_result.risk), 0.0, 1.0),
			"irritation": clampf(float(decision_result.personal_cost) * 0.35, 0.0, 1.0),
		},
		"relationship": {
			"familiarity": relationship.familiarity,
			"trust": relationship.trust,
		},
		"speech_style": {
			"directness": clampf(1.0 - float(target_person.personality.get("conformity", 0.5)) * 0.4, 0.0, 1.0),
			"politeness": clampf(float(target_person.personality.get("empathy", 0.5)), 0.0, 1.0),
			"verbosity": 0.3,
		},
	}


static func _act_name(decision: String) -> String:
	match decision:
		"ACCEPT":
			return "ACCEPT_REQUEST"
		"NEGOTIATE":
			return "NEGOTIATE_REQUEST"
		_:
			return "REFUSE_REQUEST"
