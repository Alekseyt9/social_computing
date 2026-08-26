class_name DistrictMinimap
extends Control

const WORLD_SIZE := Vector2(2400.0, 1450.0)
const BUILDINGS := [
	Rect2(95, 75, 500, 315), Rect2(1125, 70, 520, 330),
	Rect2(100, 790, 430, 220), Rect2(1160, 805, 420, 195),
	Rect2(1840, 75, 440, 320), Rect2(1840, 805, 420, 215),
	Rect2(95, 1190, 505, 190), Rect2(1210, 1210, 400, 170),
]
const PLACE_MARKERS := {
	2: {"position": Vector2(345, 418), "label": "Кафе"},
	4: {"position": Vector2(300, 600), "label": "Парк"},
	1: {"position": Vector2(1385, 418), "label": "Aurora"},
	5: {"position": Vector2(1370, 1025), "label": "Магазины"},
	6: {"position": Vector2(2060, 420), "label": "Центр"},
	7: {"position": Vector2(2060, 1035), "label": "Клиника"},
	8: {"position": Vector2(1410, 1195), "label": "Мастерские"},
}

var player_position := Vector2(790, 585)
var current_place_id := 2
var known_place_ids: Array[int] = [1, 2, 3, 4, 5, 6]
var interior_name := ""


func set_state(position_value: Vector2, place_id: int, interior: String = "") -> void:
	player_position = position_value
	current_place_id = place_id
	interior_name = interior
	if place_id not in known_place_ids:
		known_place_ids.append(place_id)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	draw_rect(bounds, Color("132127"))
	draw_rect(bounds, Color("5a777d"), false, 2.0)
	var scale := Vector2(bounds.size.x / WORLD_SIZE.x, bounds.size.y / WORLD_SIZE.y)
	for rect: Rect2 in BUILDINGS:
		var mapped := Rect2(bounds.position + rect.position * scale, rect.size * scale)
		draw_rect(mapped, Color("3a4b51"))
	# Main streets remain readable at HUD scale.
	draw_rect(Rect2(bounds.position + Vector2(0, 435) * scale, Vector2(WORLD_SIZE.x, 250) * scale), Color("586269"))
	draw_rect(Rect2(bounds.position + Vector2(680, 0) * scale, Vector2(390, WORLD_SIZE.y) * scale), Color("586269"))
	draw_rect(Rect2(bounds.position + Vector2(1645, 0) * scale, Vector2(165, WORLD_SIZE.y) * scale), Color("586269"))
	for place_id: int in PLACE_MARKERS:
		if place_id not in known_place_ids:
			continue
		var marker: Dictionary = PLACE_MARKERS[place_id]
		var point: Vector2 = bounds.position + Vector2(marker.position) * scale
		var color := Color("efce80") if place_id == current_place_id else Color("87cbd0")
		draw_circle(point, 3.5, color)
	if interior_name.is_empty():
		var player_point := bounds.position + player_position * scale
		draw_circle(player_point, 6.0, Color("fff1bd"))
		draw_circle(player_point, 8.0, Color("fff1bd"), false, 1.5)
	else:
		draw_string(
			ThemeDB.fallback_font, bounds.position + Vector2(10, 20),
			"Внутри: %s" % interior_name, HORIZONTAL_ALIGNMENT_LEFT,
			bounds.size.x - 20, 12, Color("efce80")
		)
