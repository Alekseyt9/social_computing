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

	var party_fact_id := _add_fact(
		"organization", 1, "hosts_event", "Aurora Party", 0, 1.0, 0.35
	)
	_add_knowledge(4, party_fact_id, 1.0, 4, 0.25)
	_add_knowledge(3, party_fact_id, 0.95, 4, 0.55)
	_add_knowledge(5, party_fact_id, 0.80, 13, 0.30)
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
		[party_fact_id] as Array[int]
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


func _next_random_int() -> int:
	_random_state = (_LCG_MULTIPLIER * _random_state + _LCG_INCREMENT) & _LCG_MASK
	return _random_state


func _next_unit_float() -> float:
	return float(_next_random_int()) / float(_LCG_MASK)
