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
const ConversationScript := preload("res://core/model/conversation.gd")
const DecisionEngineScript := preload("res://social/decision_engine.gd")
const GoalSolverScript := preload("res://social/goal_solver.gd")
const LightPopulationSimulationScript := preload("res://agents/light_population_simulation.gd")
const AdaptivePopulationSystemScript := preload("res://adaptive/adaptive_population_system.gd")
const DistrictSocialFieldSystemScript := preload("res://social_fields/district_social_field_system.gd")
const LazyHistorySystemScript := preload("res://history/lazy_history_system.gd")
const CommunicativeActScript := preload("res://rendering/communicative_act.gd")
const TemplateRendererScript := preload("res://rendering/template_social_renderer.gd")

const _LCG_MULTIPLIER := 1_103_515_245
const _LCG_INCREMENT := 12_345
const _LCG_MASK := 0x7fffffff
const TASK_OPERATORS := [
	"GatherInformation", "DeliverMessage", "OfferSupport",
	"VerifySituation", "CoordinateResource",
]

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
var _conversations: Dictionary = {}
var _last_decision_by_person: Dictionary = {}
var _workplace_fact_ids: Dictionary = {}
var _district_opportunity_fact_ids: Array[int] = []
var _relationship_fact_ids: Dictionary = {}
var _action_counts: Dictionary = {}
var _invitation_fact_ids: Dictionary = {}
var _access_token_fact_ids_by_person: Dictionary = {}
var _access_issuer_fact_ids: Dictionary = {}
var _entered_aurora: Dictionary = {}
var _current_place_by_person: Dictionary = {}
var _party_fact_id: int = -1
var _event_organizer_fact_ids: Dictionary = {}
var _needs_by_person: Dictionary = {}
var _tasks: Dictionary = {}
var _next_task_id: int = 1
var _next_fact_id: int = 1
var _next_event_id: int = 1
var _planner_meetable_ids: Array[int] = [2, 5, 8]
var _light_population: RefCounted
var _adaptive_population: RefCounted
var _district_fields: RefCounted
var _lazy_history: RefCounted
var _activated_adaptive_person_ids: Dictionary = {}
var _command_log: Array[Dictionary] = []
var _is_replaying: bool = false
var _district_project_contributions: Dictionary = {}
var _reputation_by_person: Dictionary = {}
var _affiliations_by_person: Dictionary = {}

const RESIDENT_FIRST_NAMES := [
	"Алексей", "Анна", "Борис", "Вера", "Глеб", "Дарья", "Егор", "Жанна",
	"Илья", "Кира", "Лев", "Марина", "Никита", "Ольга", "Павел", "Рита",
	"Семён", "Таисия", "Фёдор", "Юлия",
]
const RESIDENT_LAST_NAMES := [
	"Белов", "Волков", "Громов", "Денисов", "Ершов", "Захаров", "Исаев",
	"Крылов", "Лебедев", "Морозов", "Новиков", "Орлов", "Поляков", "Романов",
	"Соколов", "Титов", "Устинов", "Фролов", "Чернов", "Шестаков",
]


func _init(initial_seed: int) -> void:
	seed = initial_seed
	_random_state = initial_seed & _LCG_MASK
	_build_aurora_scenario()
	_current_place_by_person[player_id] = 2
	_light_population = LightPopulationSimulationScript.new(initial_seed, 1200)
	_adaptive_population = AdaptivePopulationSystemScript.new(
		_light_population, get_npc_count(), 60
	)
	_district_fields = DistrictSocialFieldSystemScript.new(_light_population.snapshot())
	_light_population.set_social_field_influence(_district_fields.snapshot())
	_lazy_history = LazyHistorySystemScript.new()


func advance(ticks: int) -> Dictionary:
	assert(ticks >= 0, "Tick count cannot be negative")
	if ticks > 0:
		_record_command("ADVANCE", {"ticks": ticks})
	for _index in range(ticks):
		_next_random_int()
		tick += 1
		_light_population.advance(1)
		_ingest_light_population_events()
		if tick % 288 == 0:
			_update_district_social_fields()
		_update_task_deadlines()
		if tick % 12 == 0:
			_propagate_one_fact()
	return snapshot()


func snapshot() -> Dictionary:
	var light_snapshot: Dictionary = _light_population.snapshot() if _light_population != null else {}
	var adaptive_snapshot: Dictionary = _adaptive_population.snapshot() if _adaptive_population != null else {}
	var field_snapshot: Dictionary = _district_fields.snapshot() if _district_fields != null else {}
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
		"active_task_count": _count_tasks_with_status("ACTIVE"),
		"completed_task_count": _count_tasks_with_status("COMPLETED"),
		"light_agent_count": int(light_snapshot.get("population", 0)),
		"light_household_count": int(light_snapshot.get("households", 0)),
		"light_employed_count": int(light_snapshot.get("employed", 0)),
		"light_population_checksum": str(light_snapshot.get("checksum", "")),
		"aggregate_population_count": int(adaptive_snapshot.get("aggregate_count", 0)),
		"refined_light_agent_count": int(adaptive_snapshot.get("light_agent_count", 0)),
		"adaptive_persistent_count": int(adaptive_snapshot.get("promoted_persistent_count", 0)),
		"district_field_update_count": int(field_snapshot.get("update_count", 0)),
		"district_project_contribution_count": _district_project_contributions.size(),
		"player_reputation": float(_reputation_by_person.get(player_id, 0.0)),
	}


func get_npc_count() -> int:
	return _people.size() - 1 if _people.has(player_id) else _people.size()


func get_place_count() -> int:
	return _places.size()


func visit_public_place(person_id: int, place_id: int) -> Dictionary:
	if not _people.has(person_id):
		return {"ok": false, "error": "UNKNOWN_PERSON"}
	if not _places.has(place_id):
		return {"ok": false, "error": "UNKNOWN_PLACE"}
	var previous_place_id := int(_current_place_by_person.get(person_id, -1))
	_current_place_by_person[person_id] = place_id
	if previous_place_id != place_id:
		_record_command("VISIT_PLACE", {"person_id": person_id, "place_id": place_id})
		_events.append(SocialEventScript.new(
			_next_event_id, "entered_public_place", [person_id] as Array[int],
			[] as Array[int], place_id, tick, 0.20, 0.08, 0.0,
			[] as Array[int]
		))
		_next_event_id += 1
	return {
		"ok": true,
		"place_id": place_id,
		"place_name": str(_places[place_id].display_name),
		"previous_place_id": previous_place_id,
	}


func get_current_place_id(person_id: int) -> int:
	return int(_current_place_by_person.get(person_id, -1))


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


func get_need_profile(person_id: int) -> Dictionary:
	var profile: Dictionary = _needs_by_person.get(person_id, {})
	return profile.duplicate(true)


func get_active_tasks_for(actor_id: int) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for task: Dictionary in _tasks.values():
		if int(task.actor_id) != actor_id or str(task.status) != "ACTIVE":
			continue
		var view := task.duplicate(true)
		view["requester_name"] = get_person_name(int(task.requester_id))
		view["counterpart_name"] = get_person_name(int(task.counterpart_id))
		visible.append(view)
	return visible


func get_district_project_state(observer_id: int) -> Dictionary:
	var contributions: Array[Dictionary] = []
	for contribution_type: String in _district_project_contributions:
		var contribution: Dictionary = _district_project_contributions[contribution_type]
		contributions.append({
			"type": contribution_type,
			"label": _district_contribution_label(contribution_type),
			"contributor_id": int(contribution.contributor_id),
			"contributor_name": get_person_name(int(contribution.contributor_id)),
			"tick": int(contribution.tick),
		})
	contributions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.type) < str(b.type)
	)
	var completed := contributions.size() >= 2
	return {
		"stage": "COMPLETED" if completed else "BUILD_COALITION",
		"title": "Районная ярмарка готова" if completed else "Собрать районную ярмарку",
		"hint": (
			"Жители собрали достаточно разных ресурсов для общего события."
			if completed else
			"Заручитесь двумя разными видами поддержки. Возможны разные сочетания людей и ресурсов."
		),
		"required": 2,
		"progress": contributions.size(),
		"contributions": contributions,
		"observer_id": observer_id,
	}


func get_player_journal_view(observer_id: int) -> Dictionary:
	var contacts: Array[Dictionary] = []
	for card: Dictionary in get_contact_cards_for(observer_id):
		var person_id := int(card.id)
		var relationship := get_relationship_state(observer_id, person_id)
		var activity := get_person_activity_view(person_id)
		contacts.append({
			"id": person_id,
			"name": str(card.name),
			"role": str(card.role),
			"relationship": _relationship_category(relationship),
			"activity": str(activity.get("activity_label", "распорядок пока неизвестен")),
		})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.name) < str(b.name)
	)
	return {
		"primary_goal": get_goal_state(observer_id),
		"district_project": get_district_project_state(observer_id),
		"tasks": get_active_tasks_for(observer_id),
		"contacts": contacts,
		"news": get_player_news_feed(observer_id, 8),
		"reputation": float(_reputation_by_person.get(observer_id, 0.0)),
		"affiliations": Array(_affiliations_by_person.get(observer_id, {}).keys()),
	}


func get_goal_reachability_report() -> Dictionary:
	return GoalSolverScript.find_access_strategies(_get_internal_planning_state(), 5, 20, 10)


func get_light_population_snapshot() -> Dictionary:
	return _light_population.snapshot()


func get_ms6_metrics() -> Dictionary:
	return _light_population.get_ms6_metrics()


func get_light_agent_view(agent_id: int) -> Dictionary:
	return _light_population.get_agent_view(agent_id)


func get_light_agent_schedule_state(agent_id: int, at_tick: int) -> Dictionary:
	return _light_population.get_agent_schedule_state(agent_id, at_tick)


func get_person_activity_view(person_id: int) -> Dictionary:
	if not _activated_adaptive_person_ids.has(person_id):
		return {}
	return _light_population.get_agent_schedule_state(person_id, tick)


func validate_light_population() -> Array[String]:
	return _light_population.validate()


func get_adaptive_population_snapshot() -> Dictionary:
	return _adaptive_population.snapshot()


func refine_light_neighborhood(
	anchor_agent_id: int, max_depth: int = 1, limit: int = 60
) -> Dictionary:
	var result: Dictionary = _adaptive_population.refine_neighborhood(anchor_agent_id, max_depth, limit)
	if bool(result.get("ok", false)):
		_record_command("REFINE_NEIGHBORHOOD", {
			"anchor_agent_id": anchor_agent_id, "max_depth": max_depth, "limit": limit,
		})
	return result


func refine_all_light_agents() -> Dictionary:
	var result: Dictionary = _adaptive_population.refine_all()
	if bool(result.get("ok", false)):
		_record_command("REFINE_ALL", {})
	return result


func update_adaptive_focus(
	player_place_id: int,
	socially_relevant_light_ids: Array = [],
	light_budget: int = 60
) -> Dictionary:
	var result: Dictionary = _adaptive_population.update_relevance_focus(
		player_place_id, socially_relevant_light_ids, light_budget
	)
	if bool(result.get("ok", false)):
		_record_command("UPDATE_FOCUS", {
			"player_place_id": player_place_id,
			"socially_relevant_light_ids": socially_relevant_light_ids.duplicate(),
			"light_budget": light_budget,
		})
	return result


func promote_light_agent_to_persistent(
	agent_id: int, reason: String = "PLAYER_RELEVANCE"
) -> Dictionary:
	var result: Dictionary = _adaptive_population.promote_to_persistent(agent_id, reason)
	if bool(result.get("ok", false)):
		_record_command("PROMOTE", {"agent_id": agent_id, "reason": reason})
	return result


func activate_light_agent_as_person(
	agent_id: int, reason: String = "PLAYER_INTERACTION"
) -> Dictionary:
	## Materializes the social/interactive projection of a canonical population
	## agent. Population state is not copied or removed, so conservation remains
	## the responsibility of AdaptivePopulationSystem.
	var agent: Dictionary = _light_population.get_agent_view(agent_id)
	if agent.is_empty():
		return {"ok": false, "error": "UNKNOWN_LIGHT_AGENT"}
	var promotion: Dictionary = _adaptive_population.promote_to_persistent(agent_id, reason)
	if not bool(promotion.get("ok", false)):
		return promotion
	var newly_activated := not _people.has(agent_id)
	if newly_activated:
		var person_name := _resident_name(agent_id)
		var person_role := _resident_role(agent)
		var traits := _resident_traits(agent_id)
		_register_person(
			agent_id,
			person_name,
			person_role,
			int(agent.home_place_id),
			int(agent.workplace_organization_id),
			false,
			traits
		)
		_activated_adaptive_person_ids[agent_id] = true
		# A newly focused citizen retains the public district information that
		# reached their population cohort. It only becomes visible to the player
		# through the normal disclosure/action rules.
		for fact_id: int in _district_opportunity_fact_ids:
			_add_knowledge(agent_id, fact_id, 0.85, agent_id, 0.70)
		_lazy_history.register_person(agent_id, tick, agent)
	_record_command("ACTIVATE_PERSON", {"agent_id": agent_id, "reason": reason})
	return {
		"ok": true,
		"person_id": agent_id,
		"name": get_person_name(agent_id),
		"role": get_person_role(agent_id),
		"newly_activated": newly_activated,
		"adaptive_profile": promotion.get("profile", {}).duplicate(true),
	}


func get_activated_adaptive_person_ids() -> Array[int]:
	var result: Array[int] = []
	for person_id: int in _activated_adaptive_person_ids:
		result.append(person_id)
	result.sort()
	return result


func get_persistent_background_history(
	person_id: int, observer_id: int
) -> Array[Dictionary]:
	if not _activated_adaptive_person_ids.has(person_id):
		return []
	if not is_person_known_to(observer_id, person_id):
		return [] # Unknown histories cannot leak identity or offscreen state.
	var current_state: Dictionary = _light_population.get_agent_view(person_id)
	if current_state.is_empty():
		return []
	var reconstructed: Array[Dictionary] = _lazy_history.materialize_known_history(
		person_id, tick, current_state
	)
	if reconstructed.is_empty():
		return []
	_sync_activated_person_employment(person_id, current_state, observer_id)
	var result: Array[Dictionary] = []
	for history_event: Dictionary in reconstructed:
		var summary := _background_history_summary(history_event)
		var payload := history_event.duplicate(true)
		payload["summary"] = summary
		var fact_id := _add_fact(
			"person", person_id, "background_event", payload,
			int(history_event.tick), 0.55, 0.15
		)
		_add_knowledge(person_id, fact_id, 1.0, person_id, 0.10)
		_add_knowledge(observer_id, fact_id, 0.90, person_id, 0.10)
		_lazy_history.attach_canonical_fact(
			person_id, int(history_event.history_event_id), fact_id
		)
		payload["canonical_fact_id"] = fact_id
		result.append(payload)
		_events.append(SocialEventScript.new(
			_next_event_id, "background_history_reconstructed",
			[person_id] as Array[int], [observer_id] as Array[int],
			int(current_state.current_place_id), int(history_event.tick),
			0.55, 0.25, 0.15, [fact_id] as Array[int]
		))
		_next_event_id += 1
	_record_command("MATERIALIZE_HISTORY", {
		"person_id": person_id, "observer_id": observer_id,
	})
	return result


func get_persistent_history_profile(person_id: int) -> Dictionary:
	return _lazy_history.get_profile(person_id)


func validate_lazy_histories() -> Array[String]:
	return _lazy_history.validate()


func release_adaptive_persistent(
	agent_id: int, keep_as_light_agent: bool = false
) -> Dictionary:
	var result: Dictionary = _adaptive_population.release_persistent(agent_id, keep_as_light_agent)
	if bool(result.get("ok", false)):
		_record_command("RELEASE_PERSISTENT", {
			"agent_id": agent_id, "keep_as_light_agent": keep_as_light_agent,
		})
	return result


func coarsen_light_agent(agent_id: int) -> Dictionary:
	var result: Dictionary = _adaptive_population.coarsen(agent_id)
	if bool(result.get("ok", false)):
		_record_command("COARSEN", {"agent_id": agent_id})
	return result


func get_light_agent_tier(agent_id: int) -> String:
	return _adaptive_population.get_tier(agent_id)


func validate_adaptive_population() -> Array[String]:
	return _adaptive_population.validate()


func get_district_social_fields() -> Dictionary:
	return _district_fields.snapshot()


func apply_district_field_shock(shock: Dictionary) -> Dictionary:
	var result: Dictionary = _district_fields.apply_shock(shock)
	_light_population.set_social_field_influence(result)
	_record_command("FIELD_SHOCK", {"shock": shock.duplicate(true)})
	return result


func validate_district_social_fields() -> Array[String]:
	return _district_fields.validate()


func get_district_opportunities(observer_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact_id: int in _district_opportunity_fact_ids:
		if not person_knows_fact(observer_id, fact_id):
			continue
		var fact: RefCounted = _facts[fact_id]
		var payload: Dictionary = fact.object_value
		result.append({
			"fact_id": fact_id,
			"kind": str(payload.get("kind", "LOCAL_NEWS")),
			"summary": str(payload.get("summary", "")),
			"tick": fact.timestamp,
		})
	return result


func get_district_pulse_view(_observer_id: int) -> Dictionary:
	var fields: Dictionary = get_district_social_fields()
	var pressure := maxf(
		float(fields.social_tension),
		maxf(float(fields.fear), maxf(float(fields.crime), float(fields.unemployment)))
	)
	var overall := "Спокойная обстановка"
	var tone := "POSITIVE"
	if pressure >= 0.68:
		overall = "Район под сильным давлением"
		tone = "DANGER"
	elif pressure >= 0.42:
		overall = "В районе ощущается напряжение"
		tone = "WARNING"
	var employment_label := _level_label(
		float(fields.employment), "Работы мало", "Рынок труда нестабилен", "Работы достаточно"
	)
	var business_label := _level_label(
		float(fields.business_health), "Бизнес слабеет", "Бизнес держится", "Бизнес оживлён"
	)
	var safety_value := 1.0 - maxf(float(fields.crime), float(fields.fear))
	var safety_label := _level_label(
		safety_value, "Люди избегают риска", "Есть опасения", "На улицах спокойно"
	)
	var social_value := 1.0 - float(fields.social_tension)
	var social_label := _level_label(
		social_value, "Сообщество расколото", "Мнения расходятся", "Сообщество сплочено"
	)
	return {
		"overall": overall,
		"tone": tone,
		"signals": [employment_label, business_label, safety_label, social_label],
		"updated_tick": int(fields.tick),
	}


func get_player_news_feed(observer_id: int, limit: int = 6) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(_events.size() - 1, -1, -1):
		var event: RefCounted = _events[index]
		var item := _player_news_item(observer_id, event)
		if item.is_empty():
			continue
		result.append(item)
		if result.size() >= maxi(0, limit):
			break
	return result


func get_conversation_context(observer_id: int, other_person_id: int) -> Dictionary:
	var conversation: RefCounted = _conversations.get(
		_conversation_key(observer_id, other_person_id)
	)
	if conversation == null:
		return {
			"participants": [get_person_name(observer_id), get_person_name(other_person_id)],
			"active_topics": [],
			"recently_mentioned_facts": [],
			"emotional_tone": "NEUTRAL",
			"previous_acts": [],
		}
	var safe_facts: Array[String] = []
	for fact_id: int in conversation.recently_mentioned_fact_ids:
		if person_knows_fact(observer_id, fact_id):
			safe_facts.append(_fact_summary_for_observer(fact_id, observer_id))
	return {
		"participants": [get_person_name(observer_id), get_person_name(other_person_id)],
		"active_topics": conversation.active_topics.duplicate(),
		"recently_mentioned_facts": safe_facts,
		"emotional_tone": conversation.emotional_tone,
		"previous_acts": conversation.previous_acts.duplicate(true),
	}


func get_social_map_view(observer_id: int) -> Dictionary:
	## This projection is deliberately built from the observer's KnowledgeStore.
	var nodes_by_key: Dictionary = {}
	var edges: Array[Dictionary] = []
	_add_map_node(nodes_by_key, "person:%d" % observer_id, "PERSON", get_person_name(observer_id), true)
	var knowledge: Dictionary = _knowledge_by_person.get(observer_id, {})
	for fact_id: int in knowledge:
		var fact: RefCounted = _facts[fact_id]
		if fact.truth_status != "true":
			continue
		match fact.predicate:
			"knows_person":
				var target_id := int(fact.object_value)
				_add_map_node(nodes_by_key, "person:%d" % fact.subject_id, "PERSON", get_person_name(fact.subject_id), fact.subject_id == observer_id)
				_add_map_node(nodes_by_key, "person:%d" % target_id, "PERSON", get_person_name(target_id), target_id == observer_id)
				edges.append({
					"source": "person:%d" % fact.subject_id,
					"target": "person:%d" % target_id,
					"kind": "KNOWS",
				})
			"works_for":
				var organization_id := int(fact.object_value)
				if not _organizations.has(organization_id):
					continue
				_add_map_node(nodes_by_key, "person:%d" % fact.subject_id, "PERSON", get_person_name(fact.subject_id), fact.subject_id == observer_id)
				_add_map_node(nodes_by_key, "organization:%d" % organization_id, "ORGANIZATION", _organizations[organization_id].display_name, false)
				edges.append({
					"source": "person:%d" % fact.subject_id,
					"target": "organization:%d" % organization_id,
					"kind": "WORKS_FOR",
				})
			"can_issue_access":
				_add_map_node(nodes_by_key, "person:%d" % fact.subject_id, "PERSON", get_person_name(fact.subject_id), false)
				_add_map_node(nodes_by_key, "organization:1", "ORGANIZATION", _organizations[1].display_name, false)
				edges.append({
					"source": "person:%d" % fact.subject_id,
					"target": "organization:1",
					"kind": str(fact.object_value),
				})
	var observer: RefCounted = _people.get(observer_id)
	if observer != null and _places.has(observer.home_place_id):
		var place_key := "place:%d" % observer.home_place_id
		_add_map_node(nodes_by_key, place_key, "PLACE", _places[observer.home_place_id].display_name, false)
		edges.append({"source": "person:%d" % observer_id, "target": place_key, "kind": "HOME"})
	return {"observer_id": observer_id, "nodes": nodes_by_key.values(), "edges": edges}


func get_recent_events(limit: int = 12) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first_index := maxi(0, _events.size() - maxi(0, limit))
	for index in range(first_index, _events.size()):
		var event: RefCounted = _events[index]
		result.append({
			"id": event.id,
			"type": event.event_type,
			"actor_ids": event.actor_ids.duplicate(),
			"target_ids": event.target_ids.duplicate(),
			"tick": event.timestamp,
			"fact_ids": event.affected_fact_ids.duplicate(),
		})
	return result


func get_metrics() -> Dictionary:
	var interactions := 0
	for event: RefCounted in _events:
		if event.event_type == "social_action_resolved" or event.event_type == "people_met":
			interactions += 1
	var light_metrics: Dictionary = get_light_population_snapshot()
	var adaptive_metrics: Dictionary = get_adaptive_population_snapshot()
	var field_metrics: Dictionary = get_district_social_fields()
	return {
		"tick": tick,
		"events": _events.size(),
		"interactions": interactions,
		"knowledge_edges": get_knowledge_edge_count(),
		"active_tasks": _count_tasks_with_status("ACTIVE"),
		"completed_tasks": _count_tasks_with_status("COMPLETED"),
		"events_per_tick": float(_events.size()) / float(maxi(1, tick)),
		"goal_reachable_strategies": int(get_goal_reachability_report().strategy_count),
		"light_population": light_metrics,
		"adaptive_population": adaptive_metrics,
		"district_social_fields": field_metrics,
		"ms6": get_ms6_metrics(),
	}


func get_debug_inspector(person_id: int, observer_id: int) -> Dictionary:
	if not _people.has(person_id):
		return {"error": "UNKNOWN_PERSON"}
	var known_fact_summaries: Array[String] = []
	for fact_id: int in _knowledge_by_person.get(person_id, {}):
		known_fact_summaries.append(_fact_summary_for_observer(fact_id, person_id))
	known_fact_summaries.sort()
	var related_events: Array[Dictionary] = []
	for event_view: Dictionary in get_recent_events(30):
		if person_id in event_view.actor_ids or person_id in event_view.target_ids:
			related_events.append(event_view)
		if related_events.size() >= 8:
			break
	return {
		"person": {
			"id": person_id,
			"name": get_person_name(person_id),
			"role": get_person_role(person_id),
			"personality": _people[person_id].personality.duplicate(true),
		},
		"relationship_to_observer": get_relationship_state(person_id, observer_id),
		"needs": get_need_profile(person_id),
		"known_fact_count": known_fact_summaries.size(),
		"known_facts": known_fact_summaries,
		"last_decision": _last_decision_by_person.get(person_id, {}).duplicate(true),
		"recent_events": related_events,
		"lazy_history": get_persistent_history_profile(person_id),
	}


func _add_map_node(
	nodes_by_key: Dictionary,
	key: String,
	kind: String,
	label: String,
	is_player: bool
) -> void:
	if not nodes_by_key.has(key):
		nodes_by_key[key] = {"id": key, "kind": kind, "label": label, "is_player": is_player}


func _player_news_item(observer_id: int, event: RefCounted) -> Dictionary:
	var involves_observer: bool = observer_id in event.actor_ids or observer_id in event.target_ids
	match event.event_type:
		"people_met":
			if not involves_observer:
				return {}
			var other_ids: Array[int] = []
			for person_id: int in event.actor_ids + event.target_ids:
				if person_id != observer_id:
					other_ids.append(person_id)
			return _news_item(event.timestamp, "CONTACT", "Новый контакт", get_person_name(other_ids[0]) if not other_ids.is_empty() else "Знакомство состоялось")
		"social_action_resolved":
			if not involves_observer:
				return {}
			var counterpart_id := int(event.target_ids[0]) if not event.target_ids.is_empty() else -1
			return _news_item(event.timestamp, "SOCIAL", "Разговор завершён", "Собеседник: %s" % get_person_name(counterpart_id))
		"social_task_created":
			if not involves_observer:
				return {}
			return _news_item(event.timestamp, "TASK", "Появилось поручение", "Оно может изменить отношения и открыть новый путь.")
		"social_task_completed":
			if not involves_observer:
				return {}
			return _news_item(event.timestamp, "TASK", "Поручение выполнено", "Результат учтён моделью отношений.")
		"entered_private_event":
			if not involves_observer:
				return {}
			return _news_item(event.timestamp, "GOAL", "Доступ в Aurora получен", "Вы вошли на закрытое мероприятие.")
		"district_population_signal":
			for fact_id: int in event.affected_fact_ids:
				if person_knows_fact(observer_id, fact_id):
					return _news_item(event.timestamp, "DISTRICT", "Новости района", _fact_summary_for_observer(fact_id, observer_id))
			return {}
		"district_fields_updated":
			var pulse: Dictionary = get_district_pulse_view(observer_id)
			return _news_item(event.timestamp, "PULSE", "Обстановка изменилась", str(pulse.overall))
		"event_scheduled":
			for fact_id: int in event.affected_fact_ids:
				if person_knows_fact(observer_id, fact_id):
					return _news_item(event.timestamp, "AURORA", "В Aurora готовится мероприятие", "Доступ ограничен — потребуется социальный путь.")
			return {}
		"background_history_reconstructed":
			if not involves_observer or event.affected_fact_ids.is_empty():
				return {}
			var fact_id := int(event.affected_fact_ids[0])
			if not person_knows_fact(observer_id, fact_id):
				return {}
			var payload: Dictionary = _facts[fact_id].object_value
			return _news_item(event.timestamp, "HISTORY", "Что изменилось", str(payload.summary))
		"contextual_activity_shared":
			if not involves_observer:
				return {}
			var person_id := -1
			for candidate_id: int in event.actor_ids:
				if candidate_id != observer_id:
					person_id = candidate_id
					break
			return _news_item(
				event.timestamp, "ACTIVITY", "Совместное занятие",
				"Время проведено вместе с %s." % get_person_name(person_id)
			)
		"entered_public_place":
			if not involves_observer or not _places.has(event.location_id):
				return {}
			return _news_item(
				event.timestamp, "PLACE", "Новое место",
				"Вы пришли: %s." % str(_places[event.location_id].display_name)
			)
		"district_project_contribution":
			if not involves_observer:
				return {}
			var contributor_id := int(event.target_ids[0]) if not event.target_ids.is_empty() else -1
			return _news_item(
				event.timestamp, "PROJECT", "Поддержка районной ярмарки",
				"%s присоединился к общей инициативе." % get_person_name(contributor_id)
			)
		_:
			return {}


func _news_item(event_tick: int, category: String, title: String, detail: String) -> Dictionary:
	return {"tick": event_tick, "category": category, "title": title, "detail": detail}


func _level_label(value: float, low: String, medium: String, high: String) -> String:
	if value < 0.34:
		return low
	if value < 0.67:
		return medium
	return high


func _get_internal_planning_state() -> Dictionary:
	var edges: Array[Dictionary] = []
	for relationship: RefCounted in _relationships.values():
		edges.append({
			"source_person_id": relationship.source_person_id,
			"target_person_id": relationship.target_person_id,
			"trust": relationship.trust,
			"resentment": relationship.resentment,
		})
	var issuers: Array[Dictionary] = []
	for issuer_id: int in _access_issuer_fact_ids:
		var fact: RefCounted = _facts[_access_issuer_fact_ids[issuer_id]]
		issuers.append({"person_id": issuer_id, "access_type": str(fact.object_value)})
	return {
		"player_id": player_id,
		"locally_meetable_ids": _planner_meetable_ids.duplicate(),
		"edges": edges,
		"access_issuers": issuers,
	}


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
	var second_workplace_fact_id := int(_workplace_fact_ids.get(second_person_id, -1))
	if second_workplace_fact_id != -1:
		reveal_fact_to(first_person_id, second_workplace_fact_id, second_person_id, 1.0)
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
	var relationship: RefCounted = _relationships[
		_relationship_key(second_person_id, first_person_id)
	]
	var decision := {
		"decision": "ACCEPT",
		"utility": 1.0,
		"primary_reason": {"type": "SOCIAL_OPENNESS", "value": 1.0},
		"positive_components": [],
		"negative_components": [],
		"disclosure_score": 1.0,
		"disclosure_level": "HIGH",
		"risk": 0.0,
		"personal_cost": 0.0,
	}
	var context := {
		"actor_name": get_person_name(first_person_id),
		"target_name": get_person_name(second_person_id),
	}
	var effects: Array[Dictionary] = [{
		"type": "IDENTITY_EXCHANGED",
		"person_id": second_person_id,
		"person_name": get_person_name(second_person_id),
	}]
	var communicative_act: Dictionary = CommunicativeActScript.build(
		"IntroduceSelf", decision, relationship, _people[second_person_id],
		context, [], effects
	)
	_record_conversation(first_person_id, second_person_id, "IntroduceSelf", communicative_act, [])
	_record_command("INTRODUCE", {
		"first_person_id": first_person_id, "second_person_id": second_person_id,
	})
	return {
		"ok": true,
		"first_name": get_person_name(first_person_id),
		"second_name": get_person_name(second_person_id),
		"action_type": "IntroduceSelf",
		"player_line": TemplateRendererScript.player_line("IntroduceSelf", context),
		"decision": decision,
		"communicative_act": communicative_act,
		"template_response": TemplateRendererScript.render(communicative_act),
		"feedback": "Личности раскрыты через событие people_met.",
		"effects": effects,
		"goal": get_goal_state(first_person_id),
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
		actions.append({
			"type": "IntroduceSelf",
			"context": {"actor_name": get_person_name(actor_id)},
		})
		return actions

	for task: Dictionary in get_active_tasks_for(actor_id):
		if int(task.counterpart_id) == target_id:
			actions.append({
				"type": str(task.operator),
				"context": {
					"task_id": int(task.id),
					"requester_person_id": int(task.requester_id),
					"requester_name": str(task.requester_name),
					"need_type": str(task.need_type),
					"topic": str(task.topic),
				},
			})
	var activity: Dictionary = get_person_activity_view(target_id)
	if not activity.is_empty():
		actions.append({
			"type": "JoinActivity",
			"context": {
				"topic": str(activity.activity_label),
				"activity": str(activity.activity),
				"activity_label": str(activity.activity_label),
				"place_id": int(activity.place_id),
			},
		})

	actions.append({"type": "BuildRapport", "context": {"topic": "повседневные дела"}})
	if not _has_active_task_from(actor_id, target_id):
		actions.append({"type": "OfferHelp", "context": {"topic": "текущие трудности"}})
	if _find_revealable_district_fact(target_id, actor_id) != -1:
		actions.append({"type": "AskLocalNews", "context": {"topic": "новости района"}})

	var revealable_fact_id := _find_revealable_aurora_fact(target_id, actor_id)
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

	var issuer_fact_id := int(_access_issuer_fact_ids.get(target_id, -1))
	if issuer_fact_id != -1 and person_knows_fact(actor_id, issuer_fact_id):
		var issuer_fact: RefCounted = _facts[issuer_fact_id]
		actions.append({
			"type": "RequestAccess",
			"context": {
				"topic": "мероприятие Aurora",
				"event_fact_id": _party_fact_id,
				"access_type": str(issuer_fact.object_value),
			},
		})

	var contribution_type := _district_support_type_for(target_id)
	if not contribution_type.is_empty() and not _district_project_contributions.has(contribution_type):
		actions.append({
			"type": "AskDistrictSupport",
			"context": {
				"topic": "районную ярмарку",
				"contribution_type": contribution_type,
				"contribution_label": _district_contribution_label(contribution_type),
			},
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


func has_valid_aurora_access(person_id: int) -> bool:
	var tokens: Array = _access_token_fact_ids_by_person.get(person_id, [])
	return not tokens.is_empty()


func get_aurora_access_types(person_id: int) -> Array[String]:
	var result: Array[String] = []
	for fact_id: int in _access_token_fact_ids_by_person.get(person_id, []):
		var fact: RefCounted = _facts.get(fact_id)
		if fact != null:
			result.append(str(fact.object_value))
	return result


func get_goal_state(observer_id: int) -> Dictionary:
	if bool(_entered_aurora.get(observer_id, false)):
		return {
			"stage": "COMPLETED",
			"title": "Цель выполнена",
			"hint": "Вы вошли на закрытое мероприятие Aurora.",
		}
	if has_valid_aurora_access(observer_id):
		return {
			"stage": "ENTER_PLACE",
			"title": "Войти в Aurora",
			"hint": "Доступ подтверждён. Подойдите ко входу в офис.",
		}
	for issuer_id: int in _access_issuer_fact_ids:
		var issuer_fact_id := int(_access_issuer_fact_ids[issuer_id])
		if person_knows_fact(observer_id, issuer_fact_id):
			return {
				"stage": "REQUEST_ACCESS",
				"title": "Получить доступ в Aurora",
				"hint": "Известен способ %s через %s." % [
					str(_facts[issuer_fact_id].object_value), get_person_name(issuer_id),
				],
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
	if not has_valid_aurora_access(person_id):
		return {
			"ok": false,
			"error": "ACCESS_TOKEN_REQUIRED",
			"act": "DENY_ENTRY",
			"reason": "ACCESS_REQUIREMENT",
		}
	_entered_aurora[person_id] = true
	var access_fact_ids: Array[int] = []
	for fact_id: int in _access_token_fact_ids_by_person.get(person_id, []):
		access_fact_ids.append(fact_id)
	_events.append(SocialEventScript.new(
		_next_event_id, "entered_private_event", [person_id] as Array[int],
		[] as Array[int], 1, tick, 0.8, 0.4, 0.2, access_fact_ids
	))
	_next_event_id += 1
	_record_command("ENTER_AURORA", {"person_id": person_id})
	return {"ok": true, "act": "ENTER_PLACE", "goal": get_goal_state(person_id)}


func perform_social_action(
	action_type: String,
	actor_id: int,
	target_id: int,
	context: Dictionary = {}
) -> Dictionary:
	if action_type == "IntroduceSelf":
		return introduce_people(actor_id, target_id)
	if action_type not in [
		"BuildRapport", "OfferHelp", "JoinActivity", "AskAbout", "AskLocalNews", "AskFavor",
		"AskIntroduction", "AskInvitation", "RequestAccess", "AskDistrictSupport"
	] and action_type not in TASK_OPERATORS:
		return {"ok": false, "error": "UNKNOWN_ACTION"}
	if not _people.has(actor_id) or not _people.has(target_id):
		return {"ok": false, "error": "UNKNOWN_PERSON"}
	context = context.duplicate(true)
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
	if action_type == "JoinActivity":
		var current_activity: Dictionary = get_person_activity_view(target_id)
		if current_activity.is_empty():
			return {"ok": false, "error": "TARGET_HAS_NO_CONTEXTUAL_ACTIVITY"}
		if str(context.get("activity", "")) != str(current_activity.activity) or (
			int(context.get("place_id", -1)) != int(current_activity.place_id)
		):
			return {"ok": false, "error": "ACTIVITY_CHANGED"}
		context["activity_label"] = str(current_activity.activity_label)
		context["topic"] = str(current_activity.activity_label)

	if action_type == "AskInvitation" and not _event_organizer_fact_ids.has(target_id):
		return {"ok": false, "error": "TARGET_CANNOT_INVITE"}
	if action_type == "RequestAccess":
		var access_issuer_fact_id := int(_access_issuer_fact_ids.get(target_id, -1))
		if access_issuer_fact_id == -1:
			return {"ok": false, "error": "TARGET_CANNOT_ISSUE_ACCESS"}
		if not person_knows_fact(actor_id, access_issuer_fact_id):
			return {"ok": false, "error": "ACCESS_CAPABILITY_NOT_DISCOVERED"}
		var access_issuer_fact: RefCounted = _facts[access_issuer_fact_id]
		if str(context.get("access_type", "")) != str(access_issuer_fact.object_value):
			return {"ok": false, "error": "ACCESS_TYPE_MISMATCH"}
	if action_type == "AskDistrictSupport":
		var expected_contribution := _district_support_type_for(target_id)
		if expected_contribution.is_empty():
			return {"ok": false, "error": "TARGET_HAS_NO_PROJECT_RESOURCE"}
		if str(context.get("contribution_type", "")) != expected_contribution:
			return {"ok": false, "error": "PROJECT_RESOURCE_MISMATCH"}
		if _district_project_contributions.has(expected_contribution):
			return {"ok": false, "error": "PROJECT_RESOURCE_ALREADY_SECURED"}
	if action_type in TASK_OPERATORS:
		var task_id := int(context.get("task_id", -1))
		var task: Dictionary = _tasks.get(task_id, {})
		if task.is_empty() or str(task.get("status", "")) != "ACTIVE":
			return {"ok": false, "error": "TASK_NOT_ACTIVE"}
		if int(task.get("actor_id", -1)) != actor_id or int(task.get("counterpart_id", -1)) != target_id:
			return {"ok": false, "error": "TASK_PARTICIPANT_MISMATCH"}
		if str(task.get("operator", "")) != action_type:
			return {"ok": false, "error": "TASK_OPERATOR_MISMATCH"}

	var relationship: RefCounted = _relationships[relationship_key]
	var target_person: RefCounted = _people[target_id]
	var evaluation_context := context.duplicate(true)
	var district_fields: Dictionary = get_district_social_fields()
	evaluation_context["district_fear"] = float(district_fields.fear)
	evaluation_context["district_social_tension"] = float(district_fields.social_tension)
	evaluation_context["district_employment"] = float(district_fields.employment)
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
	_district_fields.record_social_outcome(action_type, str(decision.decision))
	_last_decision_by_person[target_id] = decision.duplicate(true)

	var revealed_facts: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var affected_fact_ids: Array[int] = []
	if action_type == "AskAbout" and str(context.get("topic", "")) == "Aurora":
		var revealed_fact_id := _find_revealable_aurora_fact(target_id, actor_id)
		if revealed_fact_id != -1 and (
			decision.decision == "ACCEPT" or decision.disclosure_level == "HIGH"
		):
			var revealed_fact: RefCounted = _facts[revealed_fact_id]
			reveal_fact_to(actor_id, revealed_fact_id, target_id, 0.9)
			affected_fact_ids.append(revealed_fact_id)
			if revealed_fact.predicate == "can_issue_access":
				revealed_facts.append({
					"type": "ACCESS_CAPABILITY",
					"issuer_name": get_person_name(target_id),
					"access_type": str(revealed_fact.object_value),
				})
			elif revealed_fact.predicate == "knows_person":
				revealed_facts.append({
					"type": "SOCIAL_CONNECTION",
					"person_name": get_person_name(int(revealed_fact.object_value)),
					"organization": "Aurora",
				})
				var connection_relationship: RefCounted = _relationships.get(
					_relationship_key(target_id, int(revealed_fact.object_value))
				)
				if connection_relationship != null and connection_relationship.resentment >= 0.5:
					revealed_facts.append({
						"type": "RELATIONSHIP_CONFLICT",
						"person_name": get_person_name(int(revealed_fact.object_value)),
						"intensity": connection_relationship.resentment,
					})
	elif action_type == "AskLocalNews":
		var opportunity_fact_id := _find_revealable_district_fact(target_id, actor_id)
		if opportunity_fact_id != -1 and (
			decision.decision == "ACCEPT" or decision.disclosure_level == "HIGH"
		):
			var opportunity_fact: RefCounted = _facts[opportunity_fact_id]
			var opportunity: Dictionary = opportunity_fact.object_value
			reveal_fact_to(actor_id, opportunity_fact_id, target_id, 0.85)
			affected_fact_ids.append(opportunity_fact_id)
			revealed_facts.append({
				"type": "DISTRICT_OPPORTUNITY",
				"kind": str(opportunity.get("kind", "LOCAL_NEWS")),
				"summary": str(opportunity.get("summary", "")),
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
	_record_conversation(
		actor_id, target_id, action_type, communicative_act, affected_fact_ids
	)

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
	_record_command("SOCIAL_ACTION", {
		"action_type": action_type,
		"actor_id": actor_id,
		"target_id": target_id,
		"context": context.duplicate(true),
	})

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
		if decision.decision == "REFUSE" and _relationships.has(
			_relationship_key(target_id, actor_id)
		):
			var refused_target: RefCounted = _relationships[_relationship_key(target_id, actor_id)]
			refused_target.resentment = clampf(refused_target.resentment + 0.025, 0.0, 1.0)
			refused_target.trust = clampf(refused_target.trust - 0.015, 0.0, 1.0)
			effects.append({"type": "RELATIONSHIP_DAMAGED", "resentment_delta": 0.025})
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
		target_to_actor.obligation = clampf(target_to_actor.obligation + 0.12, 0.0, 1.0)
		target_to_actor.trust = clampf(target_to_actor.trust + 0.04, 0.0, 1.0)
		actor_to_target.respect = clampf(actor_to_target.respect + 0.04, 0.0, 1.0)
		var task := _create_task(actor_id, target_id)
		if task.is_empty():
			effects.append({"type": "HELP_ACCEPTED", "obligation_delta": 0.12})
		else:
			effects.append({
				"type": "TASK_CREATED",
				"task_id": int(task.id),
				"task_kind": str(task.kind),
				"counterpart_id": int(task.counterpart_id),
				"counterpart_name": get_person_name(int(task.counterpart_id)),
				"need_type": str(task.need_type),
			})
	elif action_type == "JoinActivity":
		var activity_result: Dictionary = _light_population.resolve_contextual_activity(
			target_id, str(context.get("activity", ""))
		)
		if bool(activity_result.get("ok", false)):
			target_to_actor.trust = clampf(target_to_actor.trust + 0.06, 0.0, 1.0)
			target_to_actor.familiarity = clampf(target_to_actor.familiarity + 0.08, 0.0, 1.0)
			actor_to_target.familiarity = clampf(actor_to_target.familiarity + 0.06, 0.0, 1.0)
			var activity_need := _activity_need_type(str(activity_result.activity))
			_reduce_need(target_id, activity_need, 0.10)
			effects.append({
				"type": "ACTIVITY_SHARED",
				"activity": str(activity_result.activity),
				"activity_label": str(activity_result.activity_label),
				"place_id": int(activity_result.place_id),
				"money_delta_cents": int(activity_result.money_delta_cents),
				"need_type": activity_need,
			})
			_events.append(SocialEventScript.new(
				_next_event_id, "contextual_activity_shared",
				[actor_id, target_id] as Array[int], [] as Array[int],
				int(activity_result.place_id), tick, 0.45, 0.30, 0.05,
				[] as Array[int]
			))
			_next_event_id += 1
			_increase_reputation(actor_id, 0.018)
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
		_grant_access_token(actor_id, target_id, "GUEST_INVITATION", effects, affected_fact_ids)
	elif action_type == "RequestAccess":
		_grant_access_token(
			actor_id, target_id, str(context.get("access_type", "")),
			effects, affected_fact_ids
		)
	elif action_type == "AskDistrictSupport":
		var contribution_type := str(context.get("contribution_type", ""))
		if not contribution_type.is_empty() and not _district_project_contributions.has(contribution_type):
			_district_project_contributions[contribution_type] = {
				"contributor_id": target_id,
				"tick": tick,
			}
			_increase_reputation(actor_id, 0.08)
			_add_affiliation(actor_id, "Организаторы района")
			effects.append({
				"type": "DISTRICT_CONTRIBUTION",
				"contribution_type": contribution_type,
				"contribution_label": _district_contribution_label(contribution_type),
				"progress": _district_project_contributions.size(),
				"required": 2,
			})
			_events.append(SocialEventScript.new(
				_next_event_id, "district_project_contribution",
				[actor_id] as Array[int], [target_id] as Array[int],
				6, tick, 0.72, 0.42, 0.05, [] as Array[int]
			))
			_next_event_id += 1
	elif action_type in TASK_OPERATORS:
		_complete_task(int(context.get("task_id", -1)), effects, affected_fact_ids)

	if target_to_actor.trust >= 0.72 and target_to_actor.familiarity >= 0.62:
		_add_affiliation(actor_id, "Близкие знакомые")


func _grant_access_token(
	actor_id: int,
	issuer_id: int,
	access_type: String,
	effects: Array[Dictionary],
	affected_fact_ids: Array[int]
) -> void:
	var existing_types := get_aurora_access_types(actor_id)
	if access_type not in existing_types:
		var access_fact_id := _add_fact(
			"person", actor_id, "owns_access_token", access_type, tick, 1.0, 0.1
		)
		var token_ids: Array[int] = []
		for stored_id: int in _access_token_fact_ids_by_person.get(actor_id, []):
			token_ids.append(stored_id)
		token_ids.append(access_fact_id)
		_access_token_fact_ids_by_person[actor_id] = token_ids
		if access_type == "GUEST_INVITATION":
			_invitation_fact_ids[actor_id] = access_fact_id
		_add_knowledge(actor_id, access_fact_id, 1.0, issuer_id, 0.0)
		affected_fact_ids.append(access_fact_id)
	effects.append({
		"type": "ACCESS_GRANTED",
		"access_type": access_type,
		"event_fact_id": _party_fact_id,
	})


func _create_task(actor_id: int, requester_id: int) -> Dictionary:
	if _has_active_task_from(actor_id, requester_id):
		return {}
	var counterpart_id := _select_task_counterpart(requester_id, actor_id)
	if counterpart_id == -1:
		return {}
	var profile: Dictionary = _needs_by_person.get(requester_id, {})
	var need_type := str(profile.get("dominant_type", "SUPPORT"))
	var task_definition: Dictionary = {
		"INFORMATION": {
			"kind": "INQUIRY", "operator": "GatherInformation",
			"topic": "сведения о недавних событиях",
		},
		"REPUTATION": {
			"kind": "MESSAGE", "operator": "DeliverMessage",
			"topic": "профессиональная репутация",
		},
		"SUPPORT": {
			"kind": "SOCIAL_SUPPORT", "operator": "OfferSupport",
			"topic": "личная напряжённость",
		},
		"SECURITY": {
			"kind": "VERIFICATION", "operator": "VerifySituation",
			"topic": "надёжность договорённости",
		},
		"RESOURCES": {
			"kind": "COORDINATION", "operator": "CoordinateResource",
			"topic": "организация ресурсов",
		},
	}.get(need_type, {})
	if task_definition.is_empty():
		return {}

	var task_id := _next_task_id
	_next_task_id += 1
	var task := {
		"id": task_id,
		"actor_id": actor_id,
		"requester_id": requester_id,
		"counterpart_id": counterpart_id,
		"need_type": need_type,
		"kind": str(task_definition.kind),
		"operator": str(task_definition.operator),
		"topic": str(task_definition.topic),
		"created_tick": tick,
		"deadline_tick": tick + 180,
		"status": "ACTIVE",
	}
	_tasks[task_id] = task
	var link_fact_id := get_relationship_fact_id(requester_id, counterpart_id)
	var affected: Array[int] = []
	if link_fact_id != -1:
		reveal_fact_to(actor_id, link_fact_id, requester_id, 0.85)
		affected.append(link_fact_id)
	_events.append(SocialEventScript.new(
		_next_event_id, "social_task_created", [requester_id] as Array[int],
		[actor_id, counterpart_id] as Array[int], 2, tick, 0.45, 0.25, 0.15, affected
	))
	_next_event_id += 1
	return task.duplicate(true)


func _select_task_counterpart(requester_id: int, actor_id: int) -> int:
	var candidates: Array[int] = []
	for relationship: RefCounted in _relationships.values():
		if relationship.source_person_id != requester_id:
			continue
		if relationship.target_person_id == actor_id:
			continue
		candidates.append(relationship.target_person_id)
	if candidates.is_empty():
		for person_id: int in _people:
			if person_id != requester_id and person_id != actor_id:
				candidates.append(person_id)
	if candidates.is_empty():
		return -1
	candidates.sort()
	var index := _next_random_int() % candidates.size()
	return candidates[index]


func _complete_task(
	task_id: int, effects: Array[Dictionary], affected_fact_ids: Array[int]
) -> void:
	var task: Dictionary = _tasks.get(task_id, {})
	if task.is_empty() or str(task.status) != "ACTIVE":
		return
	task["status"] = "COMPLETED"
	task["completed_tick"] = tick
	_tasks[task_id] = task
	var actor_id := int(task.actor_id)
	var requester_id := int(task.requester_id)
	var requester_to_actor: RefCounted = _relationships.get(
		_relationship_key(requester_id, actor_id)
	)
	var actor_to_requester: RefCounted = _relationships.get(
		_relationship_key(actor_id, requester_id)
	)
	if requester_to_actor != null:
		requester_to_actor.obligation = clampf(requester_to_actor.obligation + 0.34, 0.0, 1.0)
		requester_to_actor.trust = clampf(requester_to_actor.trust + 0.15, 0.0, 1.0)
	if actor_to_requester != null:
		actor_to_requester.respect = clampf(actor_to_requester.respect + 0.12, 0.0, 1.0)
	_reduce_need(requester_id, str(task.need_type), 0.22)
	effects.append({
		"type": "TASK_COMPLETED",
		"task_id": task_id,
		"requester_id": requester_id,
		"requester_name": get_person_name(requester_id),
		"need_type": str(task.need_type),
	})
	_events.append(SocialEventScript.new(
		_next_event_id, "social_task_completed", [actor_id] as Array[int],
		[requester_id, int(task.counterpart_id)] as Array[int], 2, tick,
		0.6, 0.4, 0.2, affected_fact_ids
	))
	_next_event_id += 1


func _has_active_task_from(actor_id: int, requester_id: int) -> bool:
	for task: Dictionary in _tasks.values():
		if int(task.actor_id) == actor_id and int(task.requester_id) == requester_id \
		and str(task.status) == "ACTIVE":
			return true
	return false


func _count_tasks_with_status(status: String) -> int:
	var count := 0
	for task: Dictionary in _tasks.values():
		if str(task.status) == status:
			count += 1
	return count


func _update_task_deadlines() -> void:
	for task_id: int in _tasks:
		var task: Dictionary = _tasks[task_id]
		if str(task.status) == "ACTIVE" and tick > int(task.deadline_tick):
			task["status"] = "EXPIRED"
			_tasks[task_id] = task


func _reduce_need(person_id: int, need_type: String, amount: float) -> void:
	var profile: Dictionary = _needs_by_person.get(person_id, {})
	var scores: Dictionary = profile.get("scores", {})
	if not scores.has(need_type):
		return
	scores[need_type] = clampf(float(scores[need_type]) - amount, 0.0, 1.0)
	profile["scores"] = scores
	profile["dominant_type"] = _highest_scored_key(scores)
	_needs_by_person[person_id] = profile


func _activity_need_type(activity: String) -> String:
	return {
		"WORK": "REPUTATION",
		"JOB_SEARCH": "RESOURCES",
		"ERRANDS": "RESOURCES",
		"LEISURE": "SUPPORT",
		"SOCIAL": "SUPPORT",
		"COMMUNITY": "REPUTATION",
		"HEALTH": "SECURITY",
		"CRAFT": "RESOURCES",
		"HOME": "SECURITY",
	}.get(activity, "SUPPORT")


func _derive_need_profile(person: RefCounted) -> Dictionary:
	var traits: Dictionary = person.personality
	var role := str(person.role).to_lower()
	var scores := {
		"INFORMATION": clampf(
			float(traits.curiosity) * 0.68 + float(traits.honesty) * 0.12
			+ (0.22 if role in ["journalist", "engineer", "pr manager"] else 0.0), 0.0, 1.0
		),
		"REPUTATION": clampf(
			float(traits.ambition) * 0.65 + float(traits.conformity) * 0.16
			+ (0.20 if role in ["event organizer", "pr manager", "hr specialist"] else 0.0), 0.0, 1.0
		),
		"SUPPORT": clampf(
			float(traits.empathy) * 0.38 + float(traits.sociability) * 0.42
			+ (0.16 if role in ["designer", "invited guest", "anna's friend"] else 0.0), 0.0, 1.0
		),
		"SECURITY": clampf(
			(1.0 - float(traits.risk_tolerance)) * 0.62 + float(traits.loyalty) * 0.18
			+ (0.25 if role in ["security director", "security officer", "corporate lawyer", "doorman"] else 0.0), 0.0, 1.0
		),
		"RESOURCES": clampf(
			float(traits.ambition) * 0.32 + (1.0 - float(traits.conformity)) * 0.25
			+ (0.28 if role in ["barista", "catering manager", "event contractor", "courier", "cafe owner"] else 0.0), 0.0, 1.0
		),
	}
	return {"dominant_type": _highest_scored_key(scores), "scores": scores}


func _highest_scored_key(scores: Dictionary) -> String:
	var best_key := "SUPPORT"
	var best_score := -1.0
	for key: String in scores:
		var score := float(scores[key])
		if score > best_score:
			best_key = key
			best_score = score
	return best_key


func _propagate_one_fact() -> void:
	var links: Array = _relationships.values()
	if links.is_empty():
		return
	for _attempt in range(6):
		var relationship: RefCounted = links[_next_random_int() % links.size()]
		if relationship.source_person_id == player_id or relationship.target_person_id == player_id:
			continue
		var source_knowledge: Dictionary = _knowledge_by_person.get(relationship.source_person_id, {})
		if source_knowledge.is_empty():
			continue
		var fact_ids: Array = source_knowledge.keys()
		var fact_id := int(fact_ids[_next_random_int() % fact_ids.size()])
		if person_knows_fact(relationship.target_person_id, fact_id):
			continue
		var fact: RefCounted = _facts[fact_id]
		var source: RefCounted = _people[relationship.source_person_id]
		var disclosure_capacity: float = relationship.trust * 0.72 + float(source.personality.honesty) * 0.28
		if fact.secrecy > disclosure_capacity:
			continue
		_add_knowledge(
			relationship.target_person_id, fact_id, disclosure_capacity,
			relationship.source_person_id, fact.secrecy
		)
		_events.append(SocialEventScript.new(
			_next_event_id, "information_shared", [relationship.source_person_id] as Array[int],
			[relationship.target_person_id] as Array[int], 2, tick, 0.3, 0.2, 0.1,
			[fact_id] as Array[int]
		))
		_next_event_id += 1
		return


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


func _find_revealable_aurora_fact(person_id: int, observer_id: int) -> int:
	var issuer_fact_id := int(_access_issuer_fact_ids.get(person_id, -1))
	if issuer_fact_id != -1 and not person_knows_fact(observer_id, issuer_fact_id):
		return issuer_fact_id
	var connection_fact_id := _find_revealable_aurora_connection(person_id)
	if connection_fact_id != -1 and not person_knows_fact(observer_id, connection_fact_id):
		return connection_fact_id
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
	_add_place(4, "District Park", "park")
	_add_place(5, "Shopping Quarter", "retail")
	_add_place(6, "Community Center", "community")
	_add_place(7, "District Clinic", "clinic")
	_add_place(8, "Workshop Yard", "workshop")
	_add_organization(1, "Aurora", "company")
	_add_organization(2, "Corner Cafe", "business")
	_add_person(1, "Player", "independent", 3, 0, true)
	_reputation_by_person[player_id] = 0.10
	_affiliations_by_person[player_id] = {}

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
	var organizer_fact_id := _add_fact(
		"person", 4, "organizes_event", _party_fact_id, 0, 1.0, 0.25
	)
	_event_organizer_fact_ids[4] = organizer_fact_id
	_add_knowledge(4, organizer_fact_id, 1.0, 4, 0.0)
	_add_knowledge(13, organizer_fact_id, 0.9, 4, 0.25)
	var access_issuers := {
		4: "GUEST_INVITATION",
		13: "MEDIA_PASS",
		10: "CONTRACTOR_BADGE",
	}
	for issuer_id: int in access_issuers:
		var access_capability_fact_id := _add_fact(
			"person", issuer_id, "can_issue_access", str(access_issuers[issuer_id]),
			0, 0.95, 0.30
		)
		_access_issuer_fact_ids[issuer_id] = access_capability_fact_id
		_add_knowledge(issuer_id, access_capability_fact_id, 1.0, issuer_id, 0.05)
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
	_register_person(
		person_id, person_name, person_role, home_place_id,
		workplace_organization_id, is_player, traits
	)


func _register_person(
	person_id: int,
	person_name: String,
	person_role: String,
	home_place_id: int,
	workplace_organization_id: int,
	is_player: bool,
	traits: Dictionary
) -> void:
	var person := PersonScript.new(
		person_id, person_name, person_role, home_place_id,
		workplace_organization_id, is_player, traits
	)
	_people[person_id] = person
	_knowledge_by_person[person_id] = {}
	_needs_by_person[person_id] = _derive_need_profile(person)
	if workplace_organization_id != 0:
		var organization: RefCounted = _organizations[workplace_organization_id]
		organization.add_member(person_id)
		var workplace_fact_id := _add_fact(
			"person", person_id, "works_for", workplace_organization_id,
			0, 0.65, 0.15
		)
		_workplace_fact_ids[person_id] = workplace_fact_id
		_add_knowledge(person_id, workplace_fact_id, 1.0, person_id, 0.1)


func _resident_name(agent_id: int) -> String:
	var first_index := _stable_resident_value(agent_id, 17) % RESIDENT_FIRST_NAMES.size()
	var last_index := _stable_resident_value(agent_id, 53) % RESIDENT_LAST_NAMES.size()
	var last_name: String = RESIDENT_LAST_NAMES[last_index]
	if first_index % 2 == 1:
		last_name += "а"
	return "%s %s" % [RESIDENT_FIRST_NAMES[first_index], last_name]


func _resident_role(agent: Dictionary) -> String:
	if str(agent.employment_status) != "EMPLOYED":
		return "житель района · ищет работу"
	match int(agent.workplace_organization_id):
		1:
			return "сотрудник Aurora"
		2:
			return "сотрудник Corner Cafe"
		_:
			return "житель района"


func _resident_traits(agent_id: int) -> Dictionary:
	var trait_names := [
		"sociability", "empathy", "honesty", "conformity", "ambition",
		"aggression", "impulsivity", "loyalty", "curiosity", "risk_tolerance",
	]
	var result: Dictionary = {}
	for index in range(trait_names.size()):
		result[trait_names[index]] = float(
			_stable_resident_value(agent_id, 101 + index * 37)
		) / float(_LCG_MASK)
	return result


func _stable_resident_value(agent_id: int, salt: int) -> int:
	# This deliberately does not touch the world's simulation RNG: merely
	# looking at a citizen cannot alter future social outcomes.
	return (
		agent_id * _LCG_MULTIPLIER + salt * 97_531 + seed * 65_537
	) & _LCG_MASK


func _sync_activated_person_employment(
	person_id: int, agent: Dictionary, observer_id: int
) -> void:
	var person: RefCounted = _people.get(person_id)
	if person == null:
		return
	var previous_workplace := int(person.workplace_organization_id)
	var current_workplace := int(agent.workplace_organization_id)
	person.role = _resident_role(agent)
	if previous_workplace == current_workplace:
		return
	if _organizations.has(previous_workplace):
		_organizations[previous_workplace].remove_member(person_id)
	var old_fact_id := int(_workplace_fact_ids.get(person_id, -1))
	if old_fact_id != -1 and _facts.has(old_fact_id):
		_facts[old_fact_id].truth_status = "false"
	person.workplace_organization_id = current_workplace
	_workplace_fact_ids.erase(person_id)
	if current_workplace == 0 or not _organizations.has(current_workplace):
		return
	_organizations[current_workplace].add_member(person_id)
	var workplace_fact_id := _add_fact(
		"person", person_id, "works_for", current_workplace, tick, 0.65, 0.10
	)
	_workplace_fact_ids[person_id] = workplace_fact_id
	_add_knowledge(person_id, workplace_fact_id, 1.0, person_id, 0.05)
	_add_knowledge(observer_id, workplace_fact_id, 0.90, person_id, 0.10)


func _background_history_summary(history_event: Dictionary) -> String:
	var person_name := get_person_name(int(history_event.person_id))
	var details: Dictionary = history_event.details
	match str(history_event.type):
		"JOB_STARTED":
			return "%s: новая работа — %s." % [
				person_name, _organization_name(int(details.to_workplace)),
			]
		"JOB_LOST":
			return "%s: прежняя работа закончилась, начался поиск нового места." % person_name
		"JOB_CHANGED":
			return "%s: смена работы — %s → %s." % [
				person_name,
				_organization_name(int(details.from_workplace)),
				_organization_name(int(details.to_workplace)),
			]
		"FINANCES_IMPROVED":
			return "%s: финансовое положение за это время улучшилось." % person_name
		"FINANCIAL_PRESSURE":
			return "%s: за это время усилилось денежное давление." % person_name
		_:
			return "%s: обычная жизнь по своему графику (%d дн.)." % [
				person_name, int(details.get("days", 0)),
			]


func _organization_name(organization_id: int) -> String:
	if _organizations.has(organization_id):
		return str(_organizations[organization_id].display_name)
	return "без постоянного места работы"


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


func _district_support_type_for(person_id: int) -> String:
	var person: RefCounted = _people.get(person_id)
	if person == null or person_id == player_id:
		return ""
	var role := str(person.role).to_lower()
	if "journalist" in role or "editor" in role or "photographer" in role or "pr" in role:
		return "PUBLICITY"
	if "barista" in role or "cafe" in role or "catering" in role or "courier" in role or "contractor" in role:
		return "SUPPLIES"
	if "lawyer" in role or "security" in role or "organizer" in role or "hr" in role:
		return "VENUE_APPROVAL"
	var activity := get_person_activity_view(person_id)
	if str(activity.get("activity", "")) == "COMMUNITY":
		return "VOLUNTEERS"
	var selector := posmod(person_id + int(float(person.personality.get("sociability", 0.5)) * 10.0), 4)
	return ["VOLUNTEERS", "PUBLICITY", "SUPPLIES", "VENUE_APPROVAL"][selector]


func _district_contribution_label(contribution_type: String) -> String:
	return {
		"VOLUNTEERS": "команда волонтёров",
		"PUBLICITY": "информационная поддержка",
		"SUPPLIES": "материалы и снабжение",
		"VENUE_APPROVAL": "согласование площадки",
	}.get(contribution_type, "поддержка района")


func _increase_reputation(person_id: int, amount: float) -> void:
	_reputation_by_person[person_id] = clampf(
		float(_reputation_by_person.get(person_id, 0.0)) + amount, 0.0, 1.0
	)


func _add_affiliation(person_id: int, affiliation: String) -> void:
	var affiliations: Dictionary = _affiliations_by_person.get(person_id, {})
	affiliations[affiliation] = true
	_affiliations_by_person[person_id] = affiliations


func _relationship_category(relationship: Dictionary) -> String:
	if relationship.is_empty():
		return "незнакомы"
	if float(relationship.get("resentment", 0.0)) >= 0.55:
		return "конфликт"
	if float(relationship.get("trust", 0.0)) >= 0.72 and float(relationship.get("familiarity", 0.0)) >= 0.62:
		return "дружба"
	if float(relationship.get("trust", 0.0)) >= 0.42:
		return "доверие"
	return "знакомство"


func _conversation_key(first_person_id: int, second_person_id: int) -> String:
	return "%d:%d" % [mini(first_person_id, second_person_id), maxi(first_person_id, second_person_id)]


func _record_conversation(
	first_person_id: int,
	second_person_id: int,
	action_type: String,
	act: Dictionary,
	fact_ids: Array[int]
) -> void:
	var key := _conversation_key(first_person_id, second_person_id)
	if not _conversations.has(key):
		_conversations[key] = ConversationScript.new(first_person_id, second_person_id)
	var tone := "WARM" if str(act.get("decision", "")) == "ACCEPT" else "TENSE"
	_conversations[key].record(action_type, act, fact_ids, tone)


func _fact_summary_for_observer(fact_id: int, observer_id: int) -> String:
	if not _facts.has(fact_id) or not person_knows_fact(observer_id, fact_id):
		return ""
	var fact: RefCounted = _facts[fact_id]
	match fact.predicate:
		"knows_person":
			return "%s знает %s" % [get_person_name(fact.subject_id), get_person_name(int(fact.object_value))]
		"works_for":
			return "%s работает в %s" % [get_person_name(fact.subject_id), _organizations[int(fact.object_value)].display_name]
		"can_issue_access":
			return "%s может оформить %s" % [get_person_name(fact.subject_id), str(fact.object_value)]
		"owns_access_token":
			return "%s владеет пропуском %s" % [get_person_name(fact.subject_id), str(fact.object_value)]
		"district_opportunity":
			return str((fact.object_value as Dictionary).get("summary", "Новости района"))
		_:
			return "%s: %s" % [fact.predicate, str(fact.object_value)]


func _find_revealable_district_fact(person_id: int, observer_id: int) -> int:
	for index in range(_district_opportunity_fact_ids.size() - 1, -1, -1):
		var fact_id := _district_opportunity_fact_ids[index]
		if person_knows_fact(person_id, fact_id) and not person_knows_fact(observer_id, fact_id):
			return fact_id
	return -1


func _ingest_light_population_events() -> void:
	for population_event: Dictionary in _light_population.drain_events():
		var payload := _population_event_payload(population_event)
		if payload.is_empty():
			continue
		var subject_type := "place"
		var subject_id := 2
		if str(population_event.type) == "JOB_MARKET_CHANGED":
			subject_type = "organization"
			subject_id = 1
		var fact_id := _add_fact(
			subject_type, subject_id, "district_opportunity", payload,
			tick, 0.55, 0.2
		)
		_district_opportunity_fact_ids.append(fact_id)
		if _district_opportunity_fact_ids.size() > 24:
			_district_opportunity_fact_ids.pop_front()
		var informed_people: Array[int] = []
		for person_id: int in _people:
			if person_id == player_id or not _persistent_person_receives_signal(person_id, str(population_event.type)):
				continue
			_add_knowledge(person_id, fact_id, 0.8, person_id, 0.3)
			informed_people.append(person_id)
		if informed_people.is_empty():
			_add_knowledge(2, fact_id, 0.8, 2, 0.3)
			informed_people.append(2)
		_events.append(SocialEventScript.new(
			_next_event_id, "district_population_signal", [] as Array[int],
			informed_people, 2, tick, 0.5, 0.25, 0.2, [fact_id] as Array[int]
		))
		_next_event_id += 1


func _update_district_social_fields() -> void:
	var fields: Dictionary = _district_fields.advance_day(_light_population.snapshot())
	_light_population.set_social_field_influence(fields)
	_events.append(SocialEventScript.new(
		_next_event_id, "district_fields_updated", [] as Array[int],
		[] as Array[int], 2, tick, 0.45, float(fields.social_tension), 0.0,
		[] as Array[int]
	))
	_next_event_id += 1


func _population_event_payload(population_event: Dictionary) -> Dictionary:
	match str(population_event.get("type", "")):
		"GOSSIP_TREND":
			return {
				"kind": "LOCAL_RUMOR",
				"summary": "В районе активно обсуждают: %s (охват: %d)." % [
					str(population_event.get("topic", "местные события")),
					int(population_event.get("reach", 0)),
				],
			}
		"JOB_MARKET_CHANGED":
			return {
				"kind": "JOB_MARKET",
				"summary": "На рынке труда появились изменения: наймов %d, уходов %d." % [
					int(population_event.get("hires", 0)),
					int(population_event.get("departures", 0)),
				],
			}
		"GROUP_ACTIVITY":
			return {
				"kind": "GROUP_ACTIVITY",
				"summary": "Одна из районных социальных групп собирается на встречу.",
			}
		_:
			return {}


func _persistent_person_receives_signal(person_id: int, signal_type: String) -> bool:
	var person: RefCounted = _people[person_id]
	var role := str(person.role).to_lower()
	match signal_type:
		"GOSSIP_TREND":
			return (
				"journal" in role or "editor" in role or "cafe" in role
				or "courier" in role or float(person.personality.get("curiosity", 0.0)) >= 0.58
			)
		"JOB_MARKET_CHANGED":
			return person.workplace_organization_id != 0 or "contract" in role or "security" in role
		"GROUP_ACTIVITY":
			return float(person.personality.get("sociability", 0.0)) >= 0.55
		_:
			return false


func _action_count_key(action_type: String, actor_id: int, target_id: int) -> String:
	return "%s:%d:%d" % [action_type, actor_id, target_id]


func _get_event_organizer_id() -> int:
	for person_id: int in _event_organizer_fact_ids:
		return person_id
	return -1


func _next_random_int() -> int:
	_random_state = (_LCG_MULTIPLIER * _random_state + _LCG_INCREMENT) & _LCG_MASK
	return _random_state


func _next_unit_float() -> float:
	return float(_next_random_int()) / float(_LCG_MASK)


func export_save_data() -> Dictionary:
	var state: Dictionary = snapshot()
	var adaptive: Dictionary = get_adaptive_population_snapshot()
	return {
		"format": "AURORA_SIMULATION_COMMAND_LOG",
		"version": 1,
		"seed": seed,
		"commands": _command_log.duplicate(true),
		"integrity": {
			"tick": tick,
			"checksum": str(state.checksum),
			"light_population_checksum": str(state.light_population_checksum),
			"event_count": int(state.event_count),
			"fact_count": int(state.fact_count),
			"knowledge_edge_count": int(state.knowledge_edge_count),
			"adaptive_transition_count": int(adaptive.transition_count),
			"district_project_contribution_count": int(state.district_project_contribution_count),
			"player_reputation": float(state.player_reputation),
			"light_feedback_checksum": str(
				get_light_population_snapshot().feedback.checksum
			),
		},
	}


static func create_from_save_data(data: Dictionary) -> RefCounted:
	if str(data.get("format", "")) != "AURORA_SIMULATION_COMMAND_LOG" or (
		int(data.get("version", 0)) != 1
	):
		return null
	var restored := SimulationWorld.new(int(data.get("seed", 0)))
	restored._is_replaying = true
	var saved_commands: Array[Dictionary] = []
	for value: Variant in data.get("commands", []):
		if not value is Dictionary:
			restored._is_replaying = false
			return null
		var command: Dictionary = value
		if not restored._replay_command(command):
			restored._is_replaying = false
			return null
		saved_commands.append(command.duplicate(true))
	restored._is_replaying = false
	restored._command_log = saved_commands
	var expected: Dictionary = data.get("integrity", {})
	var actual: Dictionary = restored.snapshot()
	var adaptive: Dictionary = restored.get_adaptive_population_snapshot()
	if int(expected.get("tick", -1)) != int(actual.tick) or (
		str(expected.get("checksum", "")) != str(actual.checksum)
	) or str(expected.get("light_population_checksum", "")) != str(
		actual.light_population_checksum
	) or int(expected.get("event_count", -1)) != int(actual.event_count) or (
		int(expected.get("fact_count", -1)) != int(actual.fact_count)
	) or int(expected.get("knowledge_edge_count", -1)) != int(
		actual.knowledge_edge_count
	) or int(expected.get("adaptive_transition_count", -1)) != int(
		adaptive.transition_count
	) or (
		expected.has("district_project_contribution_count")
		and int(expected.district_project_contribution_count) != int(actual.district_project_contribution_count)
	) or (
		expected.has("player_reputation")
		and not is_equal_approx(float(expected.player_reputation), float(actual.player_reputation))
	) or (
		expected.has("light_feedback_checksum")
		and str(expected.light_feedback_checksum) != str(
			restored.get_light_population_snapshot().feedback.checksum
		)
	):
		return null
	return restored


func _record_command(operation: String, arguments: Dictionary) -> void:
	if _is_replaying:
		return
	if operation == "ADVANCE" and not _command_log.is_empty() and (
		str(_command_log.back().op) == "ADVANCE"
	):
		var previous: Dictionary = _command_log.back()
		previous.args.ticks = int(previous.args.ticks) + int(arguments.ticks)
		_command_log[_command_log.size() - 1] = previous
		return
	_command_log.append({"op": operation, "args": arguments.duplicate(true)})


func _replay_command(command: Dictionary) -> bool:
	var operation := str(command.get("op", ""))
	var args: Dictionary = command.get("args", {})
	var result: Dictionary = {"ok": true}
	match operation:
		"ADVANCE":
			advance(int(args.get("ticks", 0)))
		"VISIT_PLACE":
			result = visit_public_place(int(args.person_id), int(args.place_id))
		"REFINE_NEIGHBORHOOD":
			result = refine_light_neighborhood(
				int(args.anchor_agent_id), int(args.max_depth), int(args.limit)
			)
		"REFINE_ALL":
			result = refine_all_light_agents()
		"UPDATE_FOCUS":
			result = update_adaptive_focus(
				int(args.player_place_id), args.get("socially_relevant_light_ids", []),
				int(args.light_budget)
			)
		"PROMOTE":
			result = promote_light_agent_to_persistent(int(args.agent_id), str(args.reason))
		"ACTIVATE_PERSON":
			result = activate_light_agent_as_person(int(args.agent_id), str(args.reason))
		"MATERIALIZE_HISTORY":
			get_persistent_background_history(int(args.person_id), int(args.observer_id))
		"RELEASE_PERSISTENT":
			result = release_adaptive_persistent(
				int(args.agent_id), bool(args.keep_as_light_agent)
			)
		"COARSEN":
			result = coarsen_light_agent(int(args.agent_id))
		"FIELD_SHOCK":
			apply_district_field_shock(args.get("shock", {}))
		"INTRODUCE":
			result = introduce_people(int(args.first_person_id), int(args.second_person_id))
		"ENTER_AURORA":
			result = attempt_enter_aurora(int(args.person_id))
		"SOCIAL_ACTION":
			result = perform_social_action(
				str(args.action_type), int(args.actor_id), int(args.target_id),
				args.get("context", {})
			)
		_:
			return false
	return bool(result.get("ok", true))
