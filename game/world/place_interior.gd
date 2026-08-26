class_name PlaceInterior
extends Node2D

const INTERIOR_SIZE := Vector2(1400, 820)
const ACTIVITY_ZONE := Rect2(95, 105, 1210, 590)
const ENTRY_POSITION := Vector2(700, 730)
const EXIT_POSITION := Vector2(700, 775)

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
		_:
			_draw_generic()
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


func _draw_generic() -> void:
	draw_rect(Rect2(160, 160, 1080, 430), accent.darkened(0.55))


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
