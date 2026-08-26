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
		"ACCESS_CAPABILITY":
			return "%s может оформить способ доступа %s." % [
				str(fact.get("issuer_name", "Этот человек")),
				str(fact.get("access_type", "ACCESS")),
			]
		"DISTRICT_OPPORTUNITY":
			return str(fact.get("summary", "В районе появилось новое событие."))
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
		"ACTIVITY_SHARED":
			return "Хорошо, давай вместе: %s." % str(effect.get("activity_label", "это дело"))
		"ACTIVITY_INVITATION_CREATED":
			return "Хорошо, договорились вместе: %s." % str(effect.get("activity_label", "это занятие"))
		"ACTIVITY_ASSISTED":
			return "Спасибо, с твоей помощью стало легче: %s." % str(effect.get("activity_label", "это дело"))
		"ACTIVITY_OBSERVED":
			return "Хорошо, можешь посмотреть, как я этим занимаюсь."
		"ACTIVITY_HINDERED":
			return "Ты действительно помешал моему занятию, и это не останется без последствий."
		"ACTIVITY_INTERRUPTED":
			return "Хорошо, я прервусь и освобожу место."
		"TASK_CREATED":
			return "Тогда поговори с %s — это поможет с моей текущей потребностью." % str(effect.get("counterpart_name", "нужным человеком"))
		"TASK_COMPLETED":
			return "Дело завершено; %s узнает о результате." % str(effect.get("requester_name", "заказчик"))
		"INTRODUCTION_CREATED":
			return "Я свяжу тебя с %s." % str(effect.get("person_name", "нужным человеком"))
		"INVITATION_GRANTED":
			return "Условия выполнены — приглашение твоё."
		"ACCESS_GRANTED":
			return "Условия выполнены — доступ %s оформлен." % str(effect.get("access_type", "ACCESS"))
		"DISTRICT_CONTRIBUTION":
			return "Я помогу: %s. Сейчас собрано %d из %d видов поддержки." % [
				str(effect.get("contribution_label", "ресурс")),
				int(effect.get("progress", 0)), int(effect.get("required", 2)),
			]
		"RELATIONSHIP_DAMAGED":
			return "Этот запрос усилил напряжение между нами."
		_:
			return ""
