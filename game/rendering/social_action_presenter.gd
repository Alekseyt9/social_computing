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
		"AskAbout":
			return "Спросить: %s" % str(context.get("topic", "тема"))
		"AskIntroduction":
			return "Попросить знакомство: %s" % str(context.get("subject_name", "контакт"))
		"AskInvitation":
			return "Попросить приглашение"
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
		"AskAbout":
			return _join(["Ты", "можешь", "рассказать", "мне", "про", topic], "?")
		"AskIntroduction":
			return _join(["Ты", "можешь", "познакомить", "меня", "с", subject], "?")
		"AskInvitation":
			return _join(["Можно", "получить", "приглашение", "на", topic], "?")
		_:
			return _join(["Можно", "обсудить", topic], "?")


static func _join(tokens: Array, punctuation: String) -> String:
	var words: PackedStringArray = []
	for token: Variant in tokens:
		var word := str(token).strip_edges()
		if not word.is_empty():
			words.append(word)
	return " ".join(words) + punctuation
