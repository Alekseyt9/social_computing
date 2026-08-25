class_name TemplateSocialRenderer
extends RefCounted

const ActionPresenterScript := preload("res://rendering/social_action_presenter.gd")


static func player_line(action_type: String, context: Dictionary) -> String:
	return ActionPresenterScript.player_line(action_type, context)


static func render(communicative_act: Dictionary) -> String:
	var decision := str(communicative_act.get("decision", "REFUSE"))
	var reason: Dictionary = communicative_act.get("reason", {})
	var revealed: Array = communicative_act.get("revealed_facts", [])
	var effects: Array = communicative_act.get("effects", [])
	var clauses: PackedStringArray = []

	clauses.append(_decision_clause(decision, str(reason.get("type", ""))))
	for fact: Dictionary in revealed:
		var clause := _fact_clause(fact)
		if not clause.is_empty():
			clauses.append(clause)
	for effect: Dictionary in effects:
		var clause := _effect_clause(effect)
		if not clause.is_empty():
			clauses.append(clause)
	return " ".join(clauses).strip_edges()


static func _decision_clause(decision: String, reason: String) -> String:
	if decision == "ACCEPT":
		return "Да, это возможно."
	if decision == "NEGOTIATE":
		return "Я готов это обсудить, но мне нужны более веские основания."
	var reason_words: Variant = {
		"PERSONAL_RISK": "Риск для меня слишком велик.",
		"PERSONAL_COST": "Это потребует слишком многого.",
		"LOW_TRUST": "Мы пока недостаточно доверяем друг другу.",
		"MORAL_RESISTANCE": "Мне трудно согласиться из-за личного конфликта.",
	}.get(reason, "Сейчас я не готов согласиться.")
	return str(reason_words)


static func _fact_clause(fact: Dictionary) -> String:
	match str(fact.get("type", "")):
		"SOCIAL_CONNECTION":
			return "Полезный контакт — %s, связан с %s." % [
				str(fact.get("person_name", "этим человеком")),
				str(fact.get("organization", "организацией")),
			]
		"RELATIONSHIP_CONFLICT":
			return "Однако между нами есть серьёзное напряжение."
		_:
			return ""


static func _effect_clause(effect: Dictionary) -> String:
	match str(effect.get("type", "")):
		"IDENTITY_EXCHANGED":
			return "Теперь мы знаем, как обращаться друг к другу."
		"RELATIONSHIP_IMPROVED":
			return "Этот разговор помог нам лучше понять друг друга."
		"HELP_ACCEPTED":
			return "Я приму твою помощь и запомню это."
		"INTRODUCTION_CREATED":
			return "Я свяжу тебя с %s." % str(effect.get("person_name", "нужным человеком"))
		"INVITATION_GRANTED":
			return "Условия выполнены — приглашение твоё."
		_:
			return ""
