class_name SocialGroupModel
extends RefCounted

var id: int
var display_name: String
var kind: String
var member_ids: Array[int] = []


func _init(group_id: int, group_name: String, group_kind: String) -> void:
	id = group_id
	display_name = group_name
	kind = group_kind


func add_member(person_id: int) -> void:
	if person_id not in member_ids:
		member_ids.append(person_id)
