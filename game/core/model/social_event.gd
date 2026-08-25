class_name SocialEventModel
extends RefCounted

var id: int
var event_type: String
var actor_ids: Array[int]
var target_ids: Array[int]
var location_id: int
var timestamp: int
var importance: float
var emotional_intensity: float
var secrecy: float
var affected_fact_ids: Array[int]


func _init(
	event_id: int,
	kind: String,
	event_actor_ids: Array[int],
	event_target_ids: Array[int],
	event_location_id: int,
	event_timestamp: int,
	event_importance: float,
	event_emotional_intensity: float,
	event_secrecy: float,
	event_affected_fact_ids: Array[int]
) -> void:
	id = event_id
	event_type = kind
	actor_ids = event_actor_ids.duplicate()
	target_ids = event_target_ids.duplicate()
	location_id = event_location_id
	timestamp = event_timestamp
	importance = clampf(event_importance, 0.0, 1.0)
	emotional_intensity = clampf(event_emotional_intensity, 0.0, 1.0)
	secrecy = clampf(event_secrecy, 0.0, 1.0)
	affected_fact_ids = event_affected_fact_ids.duplicate()
