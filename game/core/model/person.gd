class_name PersonModel
extends RefCounted

var id: int
var display_name: String
var role: String
var home_place_id: int
var workplace_organization_id: int
var is_player: bool
var personality: Dictionary


func _init(
	person_id: int,
	person_name: String,
	person_role: String,
	home_id: int,
	workplace_id: int,
	player_controlled: bool,
	traits: Dictionary
) -> void:
	id = person_id
	display_name = person_name
	role = person_role
	home_place_id = home_id
	workplace_organization_id = workplace_id
	is_player = player_controlled
	personality = traits.duplicate(true)

