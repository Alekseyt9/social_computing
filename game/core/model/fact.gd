class_name FactModel
extends RefCounted

var id: int
var subject_type: String
var subject_id: int
var predicate: String
var object_value: Variant
var timestamp: int
var importance: float
var secrecy: float
var truth_status: String


func _init(
	fact_id: int,
	fact_subject_type: String,
	fact_subject_id: int,
	fact_predicate: String,
	fact_object: Variant,
	fact_timestamp: int,
	fact_importance: float,
	fact_secrecy: float,
	fact_truth_status: String = "true"
) -> void:
	id = fact_id
	subject_type = fact_subject_type
	subject_id = fact_subject_id
	predicate = fact_predicate
	object_value = fact_object
	timestamp = fact_timestamp
	importance = clampf(fact_importance, 0.0, 1.0)
	secrecy = clampf(fact_secrecy, 0.0, 1.0)
	truth_status = fact_truth_status

