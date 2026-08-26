class_name SocialActionPresenter
extends RefCounted

## Localized presentation for parameterized social operators. The model provides
## action type, topic, subject and result; this class only composes UI wording.


static func button_label(action: Dictionary) -> String:
	var context: Dictionary = action.get("context", {})
	match str(action.get("type", "")):
		"IntroduceSelf":
			return "Поздороваться и представиться"
		"BuildRapport":
			return "Поговорить по-дружески"
		"OfferHelp":
			return "Предложить помощь"
		"JoinActivity":
			return _activity_button(str(context.get("activity", "")))
		"InviteToActivity":
			return "Предложить заняться этим вместе"
		"AssistActivity":
			return "Помочь с занятием"
		"ObserveActivity":
			return "Понаблюдать"
		"HinderActivity":
			return "Помешать"
		"InterruptActivity":
			return "Попросить прерваться"
		"AskAbout":
			return "Спросить: %s" % str(context.get("topic", "тема"))
		"AskLocalNews":
			return "Спросить местные новости"
		"AskIntroduction":
			return "Попросить знакомство: %s" % str(context.get("subject_name", "контакт"))
		"AskInvitation":
			return "Попросить приглашение"
		"RequestAccess":
			return {
				"GUEST_INVITATION": "Попросить гостевое приглашение",
				"MEDIA_PASS": "Запросить аккредитацию прессы",
				"CONTRACTOR_BADGE": "Запросить пропуск подрядчика",
			}.get(str(context.get("access_type", "")), "Запросить доступ")
		"AskDistrictSupport":
			return "Попросить: %s" % str(context.get("contribution_label", "поддержка района"))
		"GatherInformation":
			return "Узнать сведения для %s" % str(context.get("requester_name", "знакомого"))
		"DeliverMessage":
			return "Передать сообщение от %s" % str(context.get("requester_name", "знакомого"))
		"OfferSupport":
			return "Обсудить проблему от имени %s" % str(context.get("requester_name", "знакомого"))
		"VerifySituation":
			return "Проверить договорённость для %s" % str(context.get("requester_name", "знакомого"))
		"CoordinateResource":
			return "Согласовать ресурсы для %s" % str(context.get("requester_name", "знакомого"))
		_:
			return "Взаимодействовать"


static func player_line(action_type: String, context: Dictionary) -> String:
	var topic := str(context.get("topic", "")).strip_edges()
	var subject := str(context.get("subject_name", "")).strip_edges()
	match action_type:
		"IntroduceSelf":
			return _join(["Меня", "зовут", str(context.get("actor_name", ""))], ".")
		"BuildRapport":
			return _join(["Как", "у тебя", "сегодня", "дела"], "?")
		"OfferHelp":
			return _join(["Если", "тебе", "нужна", "помощь", "я", "могу", "помочь"], ".")
		"JoinActivity":
			return _join(["Можно", "присоединиться", "к", str(context.get("activity_label", "этому занятию"))], "?")
		"InviteToActivity":
			return _join(["Предлагаю", "заняться", str(context.get("activity_label", "этим")), "вместе"], ".")
		"AssistActivity":
			return _join(["Давай", "я", "помогу", "с", str(context.get("activity_label", "этим занятием"))], ".")
		"ObserveActivity":
			return _join(["Можно", "я", "посмотрю", "как", "ты", str(context.get("activity_label", "занимаешься этим"))], "?")
		"HinderActivity":
			return _join(["Я", "собираюсь", "помешать", "тебе", str(context.get("activity_label", "заниматься этим"))], ".")
		"InterruptActivity":
			return _join(["Можешь", "ненадолго", "прерваться"], "?")
		"AskAbout":
			return _join(["Ты", "можешь", "рассказать", "мне", "про", topic], "?")
		"AskLocalNews":
			return _join(["Что", "нового", "происходит", "в", "районе"], "?")
		"AskIntroduction":
			return _join(["Ты", "можешь", "познакомить", "меня", "с", subject], "?")
		"AskInvitation":
			return _join(["Можно", "получить", "приглашение", "на", topic], "?")
		"RequestAccess":
			return _join(["Можно", "оформить", str(context.get("access_type", "доступ")), "на", topic], "?")
		"AskDistrictSupport":
			return _join([
				"Ты", "можешь", "поддержать", topic,
				"и", "предоставить", str(context.get("contribution_label", "нужный ресурс")),
			], "?")
		"GatherInformation":
			return _join(["Мне", "нужно", "уточнить", topic, "для", str(context.get("requester_name", "знакомого"))], ".")
		"DeliverMessage":
			return _join(["Я", "передаю", "сообщение", "от", str(context.get("requester_name", "знакомого"))], ".")
		"OfferSupport":
			return _join(["Давай", "попробуем", "разобраться", "с", topic], ".")
		"VerifySituation":
			return _join(["Мне", "нужно", "проверить", topic], ".")
		"CoordinateResource":
			return _join(["Предлагаю", "согласовать", topic], ".")
		_:
			return _join(["Можно", "обсудить", topic], "?")


static func _join(tokens: Array, punctuation: String) -> String:
	var words: PackedStringArray = []
	for token: Variant in tokens:
		var word := str(token).strip_edges()
		if not word.is_empty():
			words.append(word)
	return " ".join(words) + punctuation


static func _activity_button(activity: String) -> String:
	return {
		"WORK": "Поговорить о работе",
		"ERRANDS": "Помочь с текущими делами",
		"LEISURE": "Присоединиться к прогулке",
		"JOB_SEARCH": "Вместе посмотреть вакансии",
		"SOCIAL": "Посидеть вместе",
		"COMMUNITY": "Присоединиться к общему делу",
		"HEALTH": "Поддержать во время визита",
		"CRAFT": "Помочь с проектом в мастерской",
		"HOME": "Поговорить о домашних делах",
	}.get(activity, "Присоединиться к занятию")
