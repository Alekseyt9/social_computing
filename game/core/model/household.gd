class_name HouseholdModel
extends RefCounted

var id: int
var home_place_id: int
var member_ids: Array[int] = []


func _init(household_id: int, household_home_place_id: int) -> void:
	id = household_id
	home_place_id = household_home_place_id


func add_member(person_id: int) -> void:
	if person_id not in member_ids:
		member_ids.append(person_id)
