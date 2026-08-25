class_name KnowledgeEntryModel
extends RefCounted

var person_id: int
var fact_id: int
var confidence: float
var source_person_id: int
var learned_at: int
var disclosure_threshold: float


func _init(
	knower_id: int,
	known_fact_id: int,
	knowledge_confidence: float,
	knowledge_source_id: int,
	knowledge_learned_at: int,
	knowledge_disclosure_threshold: float
) -> void:
	person_id = knower_id
	fact_id = known_fact_id
	confidence = clampf(knowledge_confidence, 0.0, 1.0)
	source_person_id = knowledge_source_id
	learned_at = knowledge_learned_at
	disclosure_threshold = clampf(knowledge_disclosure_threshold, 0.0, 1.0)

