class_name SimulationWorld
extends RefCounted

## Canonical, deterministic simulation state. UI code must use observer-facing
## query methods instead of reading the private truth stores directly.

const PersonScript := preload("res://core/model/person.gd")
const PlaceScript := preload("res://core/model/place.gd")
const OrganizationScript := preload("res://core/model/organization.gd")
const RelationshipScript := preload("res://core/model/relationship.gd")
const FactScript := preload("res://core/model/fact.gd")
const KnowledgeEntryScript := preload("res://core/model/knowledge_entry.gd")
const SocialEventScript := preload("res://core/model/social_event.gd")
const DecisionEngineScript := preload("res://social/decision_engine.gd")
const CommunicativeActScript := preload("res://rendering/communicative_act.gd")
const TemplateRendererScript := preload("res://rendering/template_social_renderer.gd")

const _LCG_MULTIPLIER := 1_103_515_245
const _LCG_INCREMENT := 12_345
const _LCG_MASK := 0x7fffffff

var seed: int
var tick: int = 0
var player_id: int = 1

var _random_state: int
var _people: Dictionary = {}
var _places: Dictionary = {}
var _organizations: Dictionary = {}
var _relationships: Dictionary = {}
var _facts: Dictionary = {}
var _knowledge_by_person: Dictionary = {}
var _events: Array = []
var _relationship_fact_ids: Dictionary = {}
var _action_counts: Dictionary = {}
var _invitation_fact_ids: Dictionary = {}
var _entered_aurora: Dictionary = {}
var _party_fact_id: int = -1
var _party_organizer_id: int = 4
var _next_fact_id: int = 1
var _next_event_id: int = 1


func _init(initial_seed: int) -> void:
	seed = initial_seed
	_random_state = initial_seed & _LCG_MASK
	_build_aurora_scenario()


func advance(ticks: int) -> Dictionary:
	assert(ticks >= 0, "Tick count cannot be negative")
	for _index in range(ticks):
		_next_random_int()
		tick += 1
	return snapshot()


func snapshot() -> Dictionary:
	return {
		"seed": seed,
		"tick": tick,
		"checksum": "%08x" % (
			_random_state ^ tick ^ _people.size() ^ (_facts.size() << 8)
			^ (_events.size() << 16) ^ (get_knowledge_edge_count() << 20)
		),
		"npc_count": get_npc_count(),
		"place_count": _places.size(),
		"organization_count": _organizations.size(),
		"relationship_count": _relationships.size(),
		"fact_count": _facts.size(),
		"knowledge_edge_count": get_knowledge_edge_count(),
		"event_count": _events.size(),
	}


func get_npc_count() -> int:
	return _people.size() - 1 if _people.has(player_id) else _people.size()


func get_place_count() -> int:
	return _places.size()


func get_organization_count() -> int:
	return _organizations.size()


func get_knowledge_edge_count() -> int:
	var count := 0
	for person_knowledge: Dictionary in _knowledge_by_person.values():
		count += person_knowledge.size()
	return count


func has_person(person_id: int) -> bool:
	return _people.has(person_id)


func get_person_name(person_id: int) -> String:
	var person: RefCounted = _people.get(person_id)
	return person.display_name if person != null else "Unknown"


func get_person_role(person_id: int) -> String:
	var person: RefCounted = _people.get(person_id)
	return person.role if person != null else ""


func is_person_known_to(observer_id: int, person_id: int) -> bool:
	if observer_id == person_id:
		return true
	var fact_id := get_relationship_fact_id(observer_id, person_id)
	return fact_id != -1 and person_knows_fact(observer_id, fact_id)


func get_visible_identity(observer_id: int, person_id: int) -> Dictionary:
	if not _people.has(person_id):
		return {"known": false, "name": "Неизвестно", "role": ""}
	var known := is_person_known_to(observer_id, person_id)
	return {
		"known": known,
		"name": get_person_name(person_id) if known else "Незнакомец",
		"role": get_person_role(person_id) if known else "",
	}


func introduce_people(first_person_id: int, second_person_id: int) -> Dictionary:
	if not _people.has(first_person_id) or not _people.has(second_person_id):
		return {"ok": false, "error": "UNKNOWN_PERSON"}
	if first_person_id == second_person_id:
		return {"ok": false, "error": "SAME_PERSON"}
	if not has_relationship(first_person_id, second_person_id):
		_add_mutual_relationship(first_person_id, second_person_id, 0.18, 0.12)
	_events.append(SocialEventScript.new(
		_next_event_id,
		"people_met",
		[first_person_id] as Array[int],
		[second_person_id] as Array[int],
		2,
		tick,
		0.30,
		0.18,
		0.08,
		[] as Array[int]
	))
	_next_event_id += 1
	return {
		"ok": true,
		"first_name": get_person_name(first_person_id),
		"second_name": get_person_name(second_person_id),
	}


func has_relationship(source_person_id: int, target_person_id: int) -> bool:
	return _relationships.has(_relationship_key(source_person_id, target_person_id))


func get_relationship_fact_id(source_person_id: int, target_person_id: int) -> int:
	return _relationship_fact_ids.get(_relationship_key(source_person_id, target_person_id), -1)


func person_knows_fact(person_id: int, fact_id: int) -> bool:
	var knowledge: Dictionary = _knowledge_by_person.get(person_id, {})
	return knowledge.has(fact_id)


func reveal_fact_to(
	person_id: int,
	fact_id: int,
	source_person_id: int,
	confidence: float = 1.0
) -> bool:
	if not _people.has(person_id) or not _facts.has(fact_id):
		return false
	_add_knowledge(person_id, fact_id, confidence, source_person_id, 0.5)
	return true


func get_known_relationships_for(observer_id: int) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	var knowledge: Dictionary = _knowledge_by_person.get(observer_id, {})
	for fact_id: int in knowledge:
		var fact: RefCounted = _facts[fact_id]
		if fact.predicate != "knows_person" or fact.truth_status != "true":
			continue
		var entry: RefCounted = knowledge[fact_id]
		visible.append({
			"fact_id": fact.id,
			"source_person_id": fact.subject_id,
			"source_name": get_person_name(fact.subject_id),
			"target_person_id": int(fact.object_value),
			"target_name": get_person_name(int(fact.object_value)),
			"confidence": entry.confidence,
		})
	return visible


func get_observer_view(observer_id: int) -> Dictionary:
	var known_relationships := get_known_relationships_for(observer_id)
	var known_contact_names: Array[String] = []
	for relationship: Dictionary in known_relationships:
		if relationship.source_person_id == observer_id:
			known_contact_names.append(relationship.target_name)
	return {
		"observer_id": observer_id,
		"observer_name": get_person_name(observer_id),
		"known_relationships": known_relationships,
		"known_contact_names": known_contact_names,
	}


func get_contact_cards_for(observer_id: int) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for visible_link: Dictionary in get_known_relationships_for(observer_id):
		if visible_link.source_person_id != observer_id:
			continue
		var target_id: int = visible_link.target_person_id
		var person: RefCounted = _people[target_id]
		var relationship: RefCounted = _relationships[
			_relationship_key(observer_id, target_id)
		]
		cards.append({
			"id": target_id,
			"name": person.display_name,
			"role": person.role,
			"familiarity_signal": _familiarity_signal(relationship.familiarity),
			"trust_signal": _trust_signal(relationship.trust),
		})
	return cards


func get_available_social_actions(actor_id: int, target_id: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not _people.has(actor_id) or not _people.has(target_id):
		return actions
	if not is_person_known_to(actor_id, target_id):
		return actions

	actions.append({"type": "BuildRapport", "context": {"topic": "повседневные дела"}})
	var help_key := _action_count_key("OfferHelp", actor_id, target_id)
	if int(_action_counts.get(help_key, 0)) == 0:
		actions.append({"type": "OfferHelp", "context": {"topic": "текущие трудности"}})

	var revealable_fact_id := _find_revealable_aurora_connection(target_id)
	if revealable_fact_id != -1 and not person_knows_fact(actor_id, revealable_fact_id):
		actions.append({"type": "AskAbout", "context": {"topic": "Aurora"}})

	for link: Dictionary in get_known_relationships_for(actor_id):
		if int(link.source_person_id) != target_id:
			continue
		var subject_id := int(link.target_person_id)
		if subject_id == actor_id or is_person_known_to(actor_id, subject_id):
			continue
		actions.append({
			"type": "AskIntroduction",
			"context": {
				"subject_person_id": subject_id,
				"subject_name": get_person_name(subject_id),
			},
		})

	if target_id == _party_organizer_id and _party_fact_id != -1:
		actions.append({
			"type": "AskInvitation",
			"context": {"topic": "мероприятие Aurora", "event_fact_id": _party_fact_id},
		})
	return actions


func get_relationship_state(source_person_id: int, target_person_id: int) -> Dictionary:
	var relationship: RefCounted = _relationships.get(
		_relationship_key(source_person_id, target_person_id)
	)
	if relationship == null:
		return {}
	return {
		"familiarity": relationship.familiarity,
		"trust": relationship.trust,
		"affection": relationship.affection,
		"respect": relationship.respect,
		"fear": relationship.fear,
		"resentment": relationship.resentment,
		"obligation": relationship.obligation,
	}


func has_aurora_invitation(person_id: int) -> bool:
	return _invitation_fact_ids.has(person_id)


func get_goal_state(observer_id: int) -> Dictionary:
	if bool(_entered_aurora.get(observer_id, false)):
		return {
			"stage": "COMPLETED",
			"title": "Цель выполнена",
			"hint": "Вы вошли на закрытое мероприятие Aurora.",
		}
	if has_aurora_invitation(observer_id):
		return {
			"stage": "ENTER_PLACE",
			"title": "Войти в Aurora",
			"hint": "Приглашение получено. Подойдите ко входу в офис.",
		}
	if is_person_known_to(observer_id, _party_organizer_id):
		return {
			"stage": "REQUEST_INVITATION",
			"title": "Договориться с организатором",
			"hint": "Укрепите отношения и попросите приглашение.",
		}
	var discovered_contacts: Array[String] = []
	for link: Dictionary in get_known_relationships_for(observer_id):
		var source_id := int(link.source_person_id)
		var target_id := int(link.target_person_id)
		if source_id != observer_id and not is_person_known_to(observer_id, target_id):
			discovered_contacts.append(str(link.target_name))
	if not discovered_contacts.is_empty():
		return {
			"stage": "SEEK_INTRODUCTION",
			"title": "Расширить круг знакомств",
			"hint": "Обнаружен контакт: %s. Попросите представить вас." % discovered_contacts[0],
		}
	return {
		"stage": "DISCOVER_ROUTE",
		"title": "Найти путь в Aurora",
		"hint": "Разговаривайте, помогайте людям и узнавайте их связи.",
	}


func attempt_enter_aurora(person_id: int) -> Dictionary:
	if not _people.has(person_id):
		return {"ok": false, "error": "UNKNOWN_PERSON"}
	if not has_aurora_invitation(person_id):
		return {
			"ok": false,
			"error": "INVITATION_REQUIRED",
			"act": "DENY_ENTRY",
			"reason": "ACCESS_REQUIREMENT",
		}
	_entered_aurora[person_id] = true
	_events.append(SocialEventScript.new(
		_next_event_id, "entered_private_event", [person_id] as Array[int],
		[] as Array[int], 1, tick, 0.8, 0.4, 0.2, [_invitation_fact_ids[person_id]] as Array[int]
	))
	_next_event_id += 1
	return {"ok": true, "act": "ENTER_PLACE", "goal": get_goal_state(person_id)}


func perform_social_action(
	action_type: String,
	actor_id: int,
	target_id: int,
	context: Dictionary = {}
) -> Dictionary:
	if action_type not in [
		"BuildRapport", "OfferHelp", "AskAbout", "AskFavor",
		"AskIntroduction", "AskInvitation"
	]:
		return {"ok": false, "error": "UNKNOWN_ACTION"}
	if not _people.has(actor_id) or not _people.has(target_id):
		return {"ok": false, "error": "UNKNOWN_PERSON"}
	var actor_target_fact_id := get_relationship_fact_id(actor_id, target_id)
	if actor_target_fact_id == -1 or not person_knows_fact(actor_id, actor_target_fact_id):
		return {"ok": false, "error": "ACTOR_DOES_NOT_KNOW_TARGET"}
	var relationship_key := _relationship_key(target_id, actor_id)
	if not _relationships.has(relationship_key):
		return {"ok": false, "error": "TARGET_DOES_NOT_KNOW_ACTOR"}
	if action_type == "AskIntroduction":
		if not context.has("subject_person_id"):
			return {"ok": false, "error": "INTRODUCTION_SUBJECT_REQUIRED"}
		var subject_id := int(context.subject_person_id)
		var target_subject_fact_id := get_relationship_fact_id(target_id, subject_id)
		if target_subject_fact_id == -1:
			return {"ok": false, "error": "TARGET_DOES_NOT_KNOW_SUBJECT"}
		if not person_knows_fact(actor_id, target_subject_fact_id):
			return {"ok": false, "error": "INTRODUCTION_SUBJECT_NOT_DISCOVERED"}

	if action_type == "AskInvitation" and target_id != _party_organizer_id:
		return {"ok": false, "error": "TARGET_CANNOT_INVITE"}

	var relationship: RefCounted = _relationships[relationship_key]
	var target_person: RefCounted = _people[target_id]
	var evaluation_context := context.duplicate(true)
	if action_type == "AskIntroduction":
		var introduction_subject_id := int(context.subject_person_id)
		var subject_relationship: RefCounted = _relationships.get(
			_relationship_key(target_id, introduction_subject_id)
		)
		if subject_relationship != null:
			evaluation_context["risk"] = clampf(0.40 + subject_relationship.resentment * 0.35, 0.0, 1.0)
			evaluation_context["moral_resistance"] = subject_relationship.resentment * 0.45
	var decision: Dictionary = DecisionEngineScript.evaluate(
		action_type,
		relationship,
		target_person,
		evaluation_context
	)

	var revealed_facts: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var affected_fact_ids: Array[int] = []
	if action_type == "AskAbout" and str(context.get("topic", "")) == "Aurora":
		var connection_fact_id := _find_revealable_aurora_connection(target_id)
		if connection_fact_id != -1 and (
			decision.decision == "ACCEPT" or decision.disclosure_level == "HIGH"
		):
			var connection_fact: RefCounted = _facts[connection_fact_id]
			reveal_fact_to(actor_id, connection_fact_id, target_id, 0.9)
			affected_fact_ids.append(connection_fact_id)
			revealed_facts.append({
				"type": "SOCIAL_CONNECTION",
				"person_name": get_person_name(int(connection_fact.object_value)),
				"organization": "Aurora",
			})
			var connection_relationship: RefCounted = _relationships.get(
				_relationship_key(target_id, int(connection_fact.object_value))
			)
			if connection_relationship != null and connection_relationship.resentment >= 0.5:
				revealed_facts.append({
					"type": "RELATIONSHIP_CONFLICT",
					"person_name": get_person_name(int(connection_fact.object_value)),
					"intensity": connection_relationship.resentment,
				})

	_apply_social_effects(
		action_type, actor_id, target_id, context, decision, effects, affected_fact_ids
	)

	var communicative_act: Dictionary = CommunicativeActScript.build(
		action_type,
		decision,
		relationship,
		target_person,
		context,
		revealed_facts,
		effects
	)
	var template_response: String = TemplateRendererScript.render(communicative_act)

	_events.append(SocialEventScript.new(
		_next_event_id,
		"social_action_resolved",
		[actor_id] as Array[int],
		[target_id] as Array[int],
		2,
		tick,
		0.45,
		0.35,
		0.2,
		affected_fact_ids
	))
	_next_event_id += 1

	return {
		"ok": true,
		"action_type": action_type,
		"actor_id": actor_id,
		"target_id": target_id,
		"player_line": TemplateRendererScript.player_line(action_type, context),
		"decision": decision,
		"communicative_act": communicative_act,
		"template_response": template_response,
		"feedback": _decision_feedback(decision),
		"effects": effects,
		"goal": get_goal_state(actor_id),
	}


func _apply_social_effects(
	action_type: String,
	actor_id: int,
	target_id: int,
	context: Dictionary,
	decision: Dictionary,
	effects: Array[Dictionary],
	affected_fact_ids: Array[int]
) -> void:
	var count_key := _action_count_key(action_type, actor_id, target_id)
	var previous_count := int(_action_counts.get(count_key, 0))
	_action_counts[count_key] = previous_count + 1
	if decision.decision != "ACCEPT":
		return

	var target_to_actor: RefCounted = _relationships[_relationship_key(target_id, actor_id)]
	var actor_to_target: RefCounted = _relationships[_relationship_key(actor_id, target_id)]
	if action_type == "BuildRapport":
		var traits: Dictionary = _people[target_id].personality
		var diminishing := 1.0 / (1.0 + float(previous_count) * 0.28)
		var trust_gain := (
			0.10 + float(traits.get("empathy", 0.5)) * 0.08
			+ float(traits.get("sociability", 0.5)) * 0.06
		) * diminishing
		target_to_actor.trust = clampf(target_to_actor.trust + trust_gain, 0.0, 1.0)
		target_to_actor.familiarity = clampf(target_to_actor.familiarity + 0.13 * diminishing, 0.0, 1.0)
		actor_to_target.trust = clampf(actor_to_target.trust + trust_gain * 0.65, 0.0, 1.0)
		actor_to_target.familiarity = clampf(actor_to_target.familiarity + 0.10 * diminishing, 0.0, 1.0)
		effects.append({"type": "RELATIONSHIP_IMPROVED", "trust_delta": trust_gain})
	elif action_type == "OfferHelp":
		target_to_actor.obligation = clampf(target_to_actor.obligation + 0.38, 0.0, 1.0)
		target_to_actor.trust = clampf(target_to_actor.trust + 0.11, 0.0, 1.0)
		actor_to_target.respect = clampf(actor_to_target.respect + 0.08, 0.0, 1.0)
		effects.append({"type": "HELP_ACCEPTED", "obligation_delta": 0.38})
	elif action_type == "AskIntroduction":
		var subject_id := int(context.subject_person_id)
		if not has_relationship(actor_id, subject_id):
			_add_mutual_relationship(actor_id, subject_id, 0.28, 0.20)
		effects.append({
			"type": "INTRODUCTION_CREATED",
			"person_id": subject_id,
			"person_name": get_person_name(subject_id),
		})
	elif action_type == "AskInvitation":
		if not _invitation_fact_ids.has(actor_id):
			var invitation_fact_id := _add_fact(
				"person", actor_id, "owns_access_token", "Aurora Invitation",
				tick, 1.0, 0.1
			)
			_invitation_fact_ids[actor_id] = invitation_fact_id
			_add_knowledge(actor_id, invitation_fact_id, 1.0, target_id, 0.0)
			affected_fact_ids.append(invitation_fact_id)
		effects.append({"type": "INVITATION_GRANTED", "event_fact_id": _party_fact_id})


func _familiarity_signal(value: float) -> String:
	if value >= 0.75:
		return "Давнее знакомство"
	if value >= 0.4:
		return "Недавнее знакомство"
	return "Едва знакомы"


func _trust_signal(value: float) -> String:
	if value >= 0.7:
		return "Высокое доверие"
	if value >= 0.4:
		return "Осторожное доверие"
	return "Доверия пока мало"


func _find_revealable_aurora_connection(person_id: int) -> int:
	var knowledge: Dictionary = _knowledge_by_person.get(person_id, {})
	for fact_id: int in knowledge:
		var fact: RefCounted = _facts[fact_id]
		if fact.predicate != "knows_person":
			continue
		var known_person_id := int(fact.object_value)
		var known_person: RefCounted = _people.get(known_person_id)
		if known_person != null and known_person.workplace_organization_id == 1:
			return fact_id
	return -1


func _decision_feedback(decision: Dictionary) -> String:
	var outcome: String = decision.decision
	var reason: String = decision.primary_reason.type
	var reason_text: String = {
		"PERSONAL_RISK": "личный риск",
		"PERSONAL_COST": "слишком высокая цена услуги",
		"LOW_TRUST": "недостаточное доверие",
		"MORAL_RESISTANCE": "моральное сопротивление",
	}.get(reason, "внутреннее сопротивление")
	match outcome:
		"ACCEPT":
			return "Запрос принят. NPC уже принял решение до вызова renderer."
		"NEGOTIATE":
			return "NPC готов обсуждать условия. Главный фактор: %s." % reason_text
		_:
			return "Запрос отклонён. Главный фактор: %s." % reason_text


func _build_aurora_scenario() -> void:
	_add_place(1, "Aurora Office", "office")
	_add_place(2, "Corner Cafe", "cafe")
	_add_place(3, "Player Apartment", "apartment")
	_add_organization(1, "Aurora", "company")
	_add_organization(2, "Corner Cafe", "business")
	_add_person(1, "Player", "independent", 3, 0, true)

	var npc_definitions: Array[Array] = [
		[2, "Anna", "designer", 3, 0],
		[3, "Sergey", "engineer", 3, 1],
		[4, "Maria", "event organizer", 3, 1],
		[5, "Daniel", "journalist", 3, 0],
		[6, "Victor", "security director", 3, 1],
		[7, "Elena", "security officer", 3, 1],
		[8, "Oleg", "barista", 3, 2],
		[9, "Irina", "catering manager", 3, 0],
		[10, "Pavel", "event contractor", 3, 0],
		[11, "Nina", "HR specialist", 3, 1],
		[12, "Alexey", "software engineer", 3, 1],
		[13, "Daria", "PR manager", 3, 1],
		[14, "Roman", "photographer", 3, 0],
		[15, "Sofia", "invited guest", 3, 0],
		[16, "Mikhail", "doorman", 3, 1],
		[17, "Katya", "Anna's friend", 3, 0],
		[18, "Leonid", "editor", 3, 0],
		[19, "Vera", "corporate lawyer", 3, 1],
		[20, "Andrey", "courier", 3, 0],
		[21, "Tamara", "cafe owner", 3, 2],
	]
	for definition: Array in npc_definitions:
		_add_person(definition[0], definition[1], definition[2], definition[3], definition[4], false)

	# Core route: Player -> Anna -> Sergey -> Maria.
	_add_mutual_relationship(1, 2, 0.45, 0.30)
	_add_mutual_relationship(2, 3, 0.80, 0.72)
	_add_mutual_relationship(3, 4, 0.85, 0.22, 0.80)
	# Alternative press and contractor routes, initially hidden from the player.
	_add_mutual_relationship(5, 13, 0.74, 0.61)
	_add_mutual_relationship(13, 4, 0.68, 0.58)
	_add_mutual_relationship(8, 9, 0.65, 0.55)
	_add_mutual_relationship(9, 10, 0.82, 0.70)
	_add_mutual_relationship(10, 4, 0.64, 0.49)

	_party_fact_id = _add_fact(
		"organization", 1, "hosts_event", "Aurora Party", 0, 1.0, 0.35
	)
	_add_knowledge(player_id, _party_fact_id, 1.0, player_id, 0.0)
	_add_knowledge(4, _party_fact_id, 1.0, 4, 0.25)
	_add_knowledge(3, _party_fact_id, 0.95, 4, 0.55)
	_add_knowledge(5, _party_fact_id, 0.80, 13, 0.30)
	_events.append(SocialEventScript.new(
		_next_event_id,
		"event_scheduled",
		[4] as Array[int],
		[] as Array[int],
		1,
		0,
		0.9,
		0.4,
		0.35,
		[_party_fact_id] as Array[int]
	))
	_next_event_id += 1


func _add_person(
	person_id: int,
	person_name: String,
	person_role: String,
	home_place_id: int,
	workplace_organization_id: int,
	is_player: bool
) -> void:
	var traits := {
		"sociability": _next_unit_float(),
		"empathy": _next_unit_float(),
		"honesty": _next_unit_float(),
		"conformity": _next_unit_float(),
		"ambition": _next_unit_float(),
		"aggression": _next_unit_float(),
		"impulsivity": _next_unit_float(),
		"loyalty": _next_unit_float(),
		"curiosity": _next_unit_float(),
		"risk_tolerance": _next_unit_float(),
	}
	var person := PersonScript.new(
		person_id, person_name, person_role, home_place_id,
		workplace_organization_id, is_player, traits
	)
	_people[person_id] = person
	_knowledge_by_person[person_id] = {}
	if workplace_organization_id != 0:
		var organization: RefCounted = _organizations[workplace_organization_id]
		organization.add_member(person_id)


func _add_place(place_id: int, place_name: String, place_kind: String) -> void:
	_places[place_id] = PlaceScript.new(place_id, place_name, place_kind)


func _add_organization(
	organization_id: int,
	organization_name: String,
	organization_kind: String
) -> void:
	_organizations[organization_id] = OrganizationScript.new(
		organization_id, organization_name, organization_kind
	)


func _add_mutual_relationship(
	first_person_id: int,
	second_person_id: int,
	familiarity: float,
	trust: float,
	resentment: float = 0.0
) -> void:
	_add_relationship(first_person_id, second_person_id, familiarity, trust, resentment)
	_add_relationship(second_person_id, first_person_id, familiarity, trust, resentment)


func _add_relationship(
	source_person_id: int,
	target_person_id: int,
	familiarity: float,
	trust: float,
	resentment: float
) -> void:
	var key := _relationship_key(source_person_id, target_person_id)
	_relationships[key] = RelationshipScript.new(
		source_person_id, target_person_id, familiarity, trust,
		0.0, 0.0, 0.0, resentment
	)
	var fact_id := _add_fact(
		"person", source_person_id, "knows_person", target_person_id, 0, 0.6, 0.25
	)
	_relationship_fact_ids[key] = fact_id
	_add_knowledge(source_person_id, fact_id, 1.0, source_person_id, 0.35)


func _add_fact(
	subject_type: String,
	subject_id: int,
	predicate: String,
	object_value: Variant,
	timestamp: int,
	importance: float,
	secrecy: float
) -> int:
	var fact_id := _next_fact_id
	_next_fact_id += 1
	_facts[fact_id] = FactScript.new(
		fact_id, subject_type, subject_id, predicate, object_value,
		timestamp, importance, secrecy
	)
	return fact_id


func _add_knowledge(
	person_id: int,
	fact_id: int,
	confidence: float,
	source_person_id: int,
	disclosure_threshold: float
) -> void:
	var knowledge: Dictionary = _knowledge_by_person[person_id]
	knowledge[fact_id] = KnowledgeEntryScript.new(
		person_id, fact_id, confidence, source_person_id, tick, disclosure_threshold
	)


func _relationship_key(source_person_id: int, target_person_id: int) -> String:
	return "%d:%d" % [source_person_id, target_person_id]


func _action_count_key(action_type: String, actor_id: int, target_id: int) -> String:
	return "%s:%d:%d" % [action_type, actor_id, target_id]


func _next_random_int() -> int:
	_random_state = (_LCG_MULTIPLIER * _random_state + _LCG_INCREMENT) & _LCG_MASK
	return _random_state


func _next_unit_float() -> float:
	return float(_next_random_int()) / float(_LCG_MASK)
