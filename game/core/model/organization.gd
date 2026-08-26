class_name OrganizationModel
extends RefCounted

var id: int
var display_name: String
var kind: String
var member_ids: Array[int] = []


func _init(organization_id: int, organization_name: String, organization_kind: String) -> void:
	id = organization_id
	display_name = organization_name
	kind = organization_kind


func add_member(person_id: int) -> void:
	if not member_ids.has(person_id):
		member_ids.append(person_id)


func remove_member(person_id: int) -> void:
	member_ids.erase(person_id)
