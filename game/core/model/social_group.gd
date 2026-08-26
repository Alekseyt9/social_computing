class_name SocialGroupModel
extends RefCounted

var id: int
var display_name: String
var kind: String
var member_ids: Array[int] = []
var _member_lookup: Dictionary = {}


func _init(group_id: int, group_name: String, group_kind: String) -> void:
	id = group_id
	display_name = group_name
	kind = group_kind


func add_member(person_id: int) -> void:
	if _member_lookup.has(person_id):
		return
	_member_lookup[person_id] = true
	member_ids.append(person_id)
