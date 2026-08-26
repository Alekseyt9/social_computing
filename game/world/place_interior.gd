class_name PlaceInterior
extends Node2D

const INTERIOR_SIZE := Vector2(1400, 820)
const ACTIVITY_ZONE := Rect2(95, 105, 1210, 590)
const ENTRY_POSITION := Vector2(700, 730)
const EXIT_POSITION := Vector2(700, 775)
const SPOT_COLUMNS := 8
const SPOT_ROWS := 12
const PLACE_SPOT_CAPACITY := {2: 36, 5: 28, 6: 32, 7: 18, 8: 28}

var place_id: int = -1
var display_name: String = ""
var accent := Color("72c8d7")


func _ready() -> void:
	_create_boundaries()
	queue_redraw()


func configure(id: int, title: String, color: Color) -> void:
	place_id = id
	display_name = title
	accent = color
	queue_redraw()


func get_activity_zone() -> Rect2:
	return Rect2(global_position + ACTIVITY_ZONE.position, ACTIVITY_ZONE.size)


func get_entry_position() -> Vector2:
	return global_position + ENTRY_POSITION


func get_exit_position() -> Vector2:
	return global_position + EXIT_POSITION


func get_camera_limits() -> Rect2:
	return Rect2(global_position, INTERIOR_SIZE)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, INTERIOR_SIZE), Color("10171b"))
	draw_rect(Rect2(35, 35, 1330, 740), Color("29363a"))
	for x in range(55, 1360, 70):
		for y in range(55, 760, 70):
			draw_rect(Rect2(x, y, 66, 66), Color("334246") if (x + y) % 140 == 0 else Color("304044"))
	draw_rect(Rect2(35, 35, 1330, 740), accent.darkened(0.25), false, 5.0)
	draw_string(
		ThemeDB.fallback_font, Vector2(70, 82), display_name,
		HORIZONTAL_ALIGNMENT_LEFT, 900, 28, accent.lightened(0.18)
	)
	match place_id:
		2:
			_draw_cafe()
		5:
			_draw_shops()
		6:
			_draw_community_center()
		7:
			_draw_clinic()
		8:
			_draw_workshop()
		_:
			_draw_generic()
	_draw_activity_spots()
	draw_rect(Rect2(630, 744, 140, 35), Color("131c20"))
	draw_string(
		ThemeDB.fallback_font, Vector2(648, 768), "ВЫХОД", HORIZONTAL_ALIGNMENT_CENTER,
		104, 18, Color("e8d392")
	)


func _draw_cafe() -> void:
	draw_rect(Rect2(105, 125, 1190, 75), Color("4b3829"))
	draw_rect(Rect2(125, 145, 1150, 35), accent.darkened(0.25))
	for point in [Vector2(260, 330), Vector2(550, 330), Vector2(850, 330), Vector2(1140, 330), Vector2(400, 560), Vector2(720, 560), Vector2(1040, 560)]:
		draw_circle(point + Vector2(5, 8), 49, Color(0, 0, 0, 0.22))
		draw_circle(point, 46, Color("6b4b35"))
		draw_circle(point, 37, Color("8b6344"), false, 4.0)


func _draw_shops() -> void:
	for x in [150, 430, 710, 990, 1270]:
		draw_rect(Rect2(x - 55, 150, 110, 450), Color("263238"))
		for y in range(175, 585, 65):
			draw_rect(Rect2(x - 43, y, 86, 38), accent.darkened(0.35))
	draw_rect(Rect2(1030, 640, 250, 55), Color("544333"))


func _draw_community_center() -> void:
	for point in [Vector2(260, 260), Vector2(560, 260), Vector2(860, 260), Vector2(1140, 260)]:
		draw_rect(Rect2(point - Vector2(90, 40), Vector2(180, 80)), Color("405057"))
		draw_rect(Rect2(point - Vector2(78, 28), Vector2(156, 56)), accent.darkened(0.38))
	draw_circle(Vector2(700, 535), 125, Color("384a4e"))
	draw_circle(Vector2(700, 535), 105, accent.darkened(0.42), false, 5.0)


func _draw_clinic() -> void:
	for room: Rect2 in [Rect2(105, 145, 330, 210), Rect2(485, 145, 330, 210), Rect2(865, 145, 330, 210)]:
		draw_rect(room, Color("d5e1df"))
		draw_rect(room.grow(-12), Color("71909a"), false, 4.0)
	for seat_x in range(180, 1230, 145):
		draw_rect(Rect2(seat_x, 520, 80, 36), Color("45636d"))
	draw_rect(Rect2(610, 390, 180, 70), Color("eef4ee"))
	draw_rect(Rect2(684, 405, 32, 40), Color("cf6565"))
	draw_rect(Rect2(670, 419, 60, 12), Color("cf6565"))


func _draw_workshop() -> void:
	for table: Rect2 in [Rect2(120, 170, 300, 100), Rect2(550, 170, 300, 100), Rect2(980, 170, 300, 100), Rect2(240, 470, 360, 110), Rect2(800, 470, 360, 110)]:
		draw_rect(Rect2(table.position + Vector2(6, 8), table.size), Color(0, 0, 0, 0.25))
		draw_rect(table, Color("72523a"))
		draw_rect(table.grow(-12), accent.darkened(0.38), false, 4.0)
	for point in [Vector2(180, 215), Vector2(610, 215), Vector2(1040, 215), Vector2(310, 520), Vector2(870, 520)]:
		draw_circle(point, 13, Color("d2b56c"), false, 4.0)
		draw_line(point - Vector2(9, 9), point + Vector2(9, 9), Color("d2b56c"), 3.0)


func _draw_generic() -> void:
	draw_rect(Rect2(160, 160, 1080, 430), accent.darkened(0.55))


func _draw_activity_spots() -> void:
	var capacity := get_activity_spot_count()
	for spot_index in range(capacity):
		var point := get_activity_spot_local_position(spot_index)
		draw_circle(point, 4.0, Color(accent, 0.24))
		draw_arc(point, 7.0, 0.0, TAU, 12, Color(accent, 0.32), 1.0)
	var legend_position := Vector2(1010, 92)
	draw_rect(Rect2(legend_position - Vector2(12, 22), Vector2(300, 32)), Color("10181cbb"))
	draw_circle(legend_position, 4.0, accent.lightened(0.18))
	draw_string(
		ThemeDB.fallback_font, legend_position + Vector2(14, 5),
		"точки занятий · %d мест" % capacity,
		HORIZONTAL_ALIGNMENT_LEFT, 250, 14, Color("c9d7d2")
	)
	for marker: Dictionary in _activity_area_markers():
		var point: Vector2 = marker.position
		draw_circle(point, 18.0, Color(accent, 0.12))
		draw_arc(point, 18.0, 0.0, TAU, 20, Color(accent, 0.56), 1.5)
		draw_string(
			ThemeDB.fallback_font, point + Vector2(25, 5), str(marker.label),
			HORIZONTAL_ALIGNMENT_LEFT, 180, 13, Color("d5dfda")
		)


func get_activity_spot_count() -> int:
	return int(PLACE_SPOT_CAPACITY.get(place_id, 24))


func get_activity_spot_local_position(spot_index: int) -> Vector2:
	var column := posmod(spot_index, SPOT_COLUMNS)
	var row := posmod(int(spot_index / SPOT_COLUMNS), SPOT_ROWS)
	return Vector2(
		ACTIVITY_ZONE.position.x + (float(column) + 0.5) * ACTIVITY_ZONE.size.x / float(SPOT_COLUMNS),
		ACTIVITY_ZONE.position.y + (float(row) + 0.5) * ACTIVITY_ZONE.size.y / float(SPOT_ROWS),
	)


func _activity_area_markers() -> Array[Dictionary]:
	return {
		2: [
			{"position": Vector2(220, 220), "label": "заказ / работа"},
			{"position": Vector2(700, 520), "label": "еда / общение"},
		],
		5: [
			{"position": Vector2(220, 650), "label": "касса"},
			{"position": Vector2(880, 600), "label": "покупки"},
		],
		6: [
			{"position": Vector2(230, 390), "label": "совместная работа"},
			{"position": Vector2(700, 535), "label": "встреча"},
		],
		7: [
			{"position": Vector2(700, 425), "label": "регистратура"},
			{"position": Vector2(330, 590), "label": "ожидание"},
		],
		8: [
			{"position": Vector2(260, 330), "label": "верстак"},
			{"position": Vector2(820, 650), "label": "совместный проект"},
		],
	}.get(place_id, [])


func _create_boundaries() -> void:
	_add_wall(Rect2(0, 0, INTERIOR_SIZE.x, 35))
	_add_wall(Rect2(0, INTERIOR_SIZE.y - 45, 610, 45))
	_add_wall(Rect2(790, INTERIOR_SIZE.y - 45, 610, 45))
	_add_wall(Rect2(0, 0, 35, INTERIOR_SIZE.y))
	_add_wall(Rect2(INTERIOR_SIZE.x - 35, 0, 35, INTERIOR_SIZE.y))


func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
