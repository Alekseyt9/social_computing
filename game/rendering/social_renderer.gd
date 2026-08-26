class_name SocialRenderer
extends RefCounted

const MAX_RENDERED_LENGTH := 500


static func build_system_prompt() -> String:
	return (
		"Ты Social Renderer русскоязычной игры. Симуляция уже приняла решение NPC. "
		+ "Сформулируй только одну естественную реплику персонажа, без пояснений и JSON. "
		+ "Строго сохрани decision. Не соглашайся при REFUSE и не отказывай при ACCEPT. "
		+ "Не добавляй имена, события, связи или факты, которых нет в revealed_facts или effects. "
		+ "Если effects не пуст, естественно отрази каждый эффект и указанного в нём персонажа. "
		+ "Не предлагай изменить состояние игры. Ответ — не более трёх коротких предложений."
	)


static func build_user_prompt(
	character_identity: Dictionary,
	communicative_act: Dictionary,
	conversation_context: Dictionary
) -> String:
	var safe_payload := {
		"character": character_identity,
		"communicative_act": communicative_act,
		"conversation_context": conversation_context,
	}
	return JSON.stringify(safe_payload)


static func sanitize_output(
	raw_text: String,
	communicative_act: Dictionary,
	fallback: String
) -> String:
	var cleaned := raw_text.strip_edges()
	if cleaned.length() >= 2 and (
		(cleaned.begins_with("\"") and cleaned.ends_with("\""))
		or (cleaned.begins_with("«") and cleaned.ends_with("»"))
	):
		cleaned = cleaned.substr(1, cleaned.length() - 2).strip_edges()
	if cleaned.is_empty() or cleaned.length() > MAX_RENDERED_LENGTH:
		return fallback
	if not _looks_like_complete_sentence(cleaned):
		return fallback
	if not _decision_is_preserved(cleaned, communicative_act.decision):
		return fallback
	if not _effects_are_preserved(cleaned, communicative_act.get("effects", [])):
		return fallback
	return cleaned


static func _looks_like_complete_sentence(text: String) -> bool:
	var ending := text.right(1)
	return ending in [".", "!", "?", "…", "»", "\""]


static func _decision_is_preserved(text: String, decision: String) -> bool:
	var normalized := text.to_lower()
	var acceptance_markers := [
		"я согласна", "я согласен", "конечно, помогу", "договорились",
		"я тебя познакомлю", "я вас познакомлю",
	]
	var refusal_markers := ["не могу", "не буду", "не хочу", "нет,", "нет."]
	if decision == "REFUSE":
		for marker: String in acceptance_markers:
			if normalized.contains(marker):
				return false
	elif decision == "ACCEPT":
		for marker: String in refusal_markers:
			if normalized.contains(marker):
				return false
	return true


static func _effects_are_preserved(text: String, effects: Array) -> bool:
	var normalized := text.to_lower()
	for effect: Dictionary in effects:
		var effect_type := str(effect.get("type", ""))
		if effect_type in ["TASK_CREATED", "INTRODUCTION_CREATED"]:
			var required_name := str(
				effect.get("counterpart_name", effect.get("person_name", ""))
			).to_lower()
			if not required_name.is_empty() and not normalized.contains(required_name):
				return false
		elif effect_type in ["INVITATION_GRANTED", "ACCESS_GRANTED"]:
			if not normalized.contains("приглаш"):
				var access_type := str(effect.get("access_type", "")).to_lower()
				if access_type.is_empty() or not normalized.contains(access_type):
					return false
	return true
