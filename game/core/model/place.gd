class_name PlaceModel
extends RefCounted

var id: int
var display_name: String
var kind: String


func _init(place_id: int, place_name: String, place_kind: String) -> void:
	id = place_id
	display_name = place_name
	kind = place_kind

