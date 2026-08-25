class_name RelationshipModel
extends RefCounted

var source_person_id: int
var target_person_id: int
var familiarity: float
var trust: float
var affection: float
var respect: float
var fear: float
var resentment: float
var attraction: float
var obligation: float


func _init(
	source_id: int,
	target_id: int,
	initial_familiarity: float,
	initial_trust: float,
	initial_affection: float = 0.0,
	initial_respect: float = 0.0,
	initial_fear: float = 0.0,
	initial_resentment: float = 0.0,
	initial_attraction: float = 0.0,
	initial_obligation: float = 0.0
) -> void:
	source_person_id = source_id
	target_person_id = target_id
	familiarity = clampf(initial_familiarity, 0.0, 1.0)
	trust = clampf(initial_trust, 0.0, 1.0)
	affection = clampf(initial_affection, 0.0, 1.0)
	respect = clampf(initial_respect, 0.0, 1.0)
	fear = clampf(initial_fear, 0.0, 1.0)
	resentment = clampf(initial_resentment, 0.0, 1.0)
	attraction = clampf(initial_attraction, 0.0, 1.0)
	obligation = clampf(initial_obligation, 0.0, 1.0)

