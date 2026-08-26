class_name WorldMap
extends Node2D

const WORLD_SIZE := Vector2(2400.0, 1450.0)
const BUILDINGS := [
	{"rect": Rect2(95, 75, 500, 315), "name": "CORNER CAFE", "accent": Color("e6a75e")},
	{"rect": Rect2(1125, 70, 520, 330), "name": "AURORA", "accent": Color("72c8d7")},
	{"rect": Rect2(100, 790, 430, 220), "name": "ЖИЛОЙ ДОМ", "accent": Color("b69bd4")},
	{"rect": Rect2(1160, 805, 420, 195), "name": "МАГАЗИНЫ", "accent": Color("79c39a")},
	{"rect": Rect2(1840, 75, 440, 320), "name": "ОБЩЕСТВЕННЫЙ ЦЕНТР", "accent": Color("e2c36f")},
	{"rect": Rect2(1840, 805, 420, 215), "name": "ПОЛИКЛИНИКА", "accent": Color("81b6d9")},
	{"rect": Rect2(95, 1190, 505, 190), "name": "ЖИЛОЙ КВАРТАЛ", "accent": Color("aa91d2")},
	{"rect": Rect2(1210, 1210, 400, 170), "name": "МАСТЕРСКИЕ", "accent": Color("cc8d68")},
]


func _ready() -> void:
	_create_world_collisions()
	_create_signs()
	queue_redraw()


func _draw() -> void:
	# Ground and walkable blocks.
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("18251f"))
	_draw_grass_grid()
	draw_rect(Rect2(0, 435, WORLD_SIZE.x, 250), Color("303941"))
	draw_rect(Rect2(680, 0, 390, WORLD_SIZE.y), Color("303941"))
	draw_rect(Rect2(1645, 0, 165, WORLD_SIZE.y), Color("303941"))
	draw_rect(Rect2(0, 1035, WORLD_SIZE.x, 135), Color("303941"))
	draw_rect(Rect2(610, 455, 540, 210), Color("697269"))
	draw_rect(Rect2(632, 477, 496, 166), Color("7d857b"), false, 3.0)
	draw_rect(Rect2(1815, 455, 500, 270), Color("59675e"))
	draw_rect(Rect2(1834, 474, 462, 232), Color("788078"), false, 3.0)
	_draw_crosswalk(Vector2(715, 405), true)
	_draw_crosswalk(Vector2(1008, 705), true)
	_draw_crosswalk(Vector2(610, 505), false)
	_draw_crosswalk(Vector2(1150, 600), false)

	for building: Dictionary in BUILDINGS:
		_draw_building(building.rect, building.accent)

	_draw_park()
	_draw_east_square()
	_draw_street_details()
	_draw_sidewalks_and_props()
	_draw_aurora_entrance()


func _draw_grass_grid() -> void:
	for x in range(30, int(WORLD_SIZE.x), 70):
		for y in range(25, int(WORLD_SIZE.y), 65):
			if (x * 3 + y) % 5 == 0:
				draw_circle(Vector2(x, y), 2.0, Color("2b4938"))


func _draw_building(rect: Rect2, accent: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(12, 15), rect.size), Color(0, 0, 0, 0.30))
	draw_rect(rect, Color("26343a"))
	draw_rect(Rect2(rect.position + Vector2(10, 10), rect.size - Vector2(20, 20)), Color("33434a"))
	draw_line(rect.position + Vector2(12, 13), rect.position + Vector2(rect.size.x - 12, 13), accent, 4.0)
	var window_y: float = rect.position.y + 65
	var window_count: int = maxi(2, int((rect.size.x - 70) / 90.0))
	for index in range(window_count):
		var window_pos := Vector2(rect.position.x + 42 + index * 88, window_y)
		draw_rect(Rect2(window_pos, Vector2(45, 22)), Color("91b9b8"))
		draw_rect(Rect2(window_pos + Vector2(4, 4), Vector2(37, 14)), Color("b8d1c8"), false, 2.0)
	var door_rect := Rect2(rect.get_center().x - 30, rect.end.y - 58, 60, 58)
	draw_rect(door_rect, Color("151f23"))
	draw_rect(Rect2(door_rect.position + Vector2(7, 8), Vector2(46, 50)), accent.darkened(0.35))


func _draw_park() -> void:
	draw_rect(Rect2(70, 475, 455, 250), Color("254d38"))
	draw_rect(Rect2(84, 489, 427, 222), Color("50745e"), false, 3.0)
	for position in [Vector2(125, 520), Vector2(230, 670), Vector2(420, 525), Vector2(475, 665)]:
		draw_circle(position + Vector2(3, 5), 24.0, Color(0, 0, 0, 0.25))
		draw_circle(position, 23.0, Color("356b47"))
		draw_circle(position - Vector2(7, 5), 13.0, Color("4f8c5c"))
	for bench_pos in [Vector2(190, 555), Vector2(355, 650)]:
		draw_rect(Rect2(bench_pos, Vector2(65, 14)), Color("5b4432"))
		draw_line(bench_pos + Vector2(8, 14), bench_pos + Vector2(5, 24), Color("1c2526"), 4)
		draw_line(bench_pos + Vector2(57, 14), bench_pos + Vector2(60, 24), Color("1c2526"), 4)


func _draw_east_square() -> void:
	for position in [Vector2(1870, 505), Vector2(2240, 505), Vector2(1870, 675), Vector2(2240, 675)]:
		draw_circle(position + Vector2(3, 5), 20.0, Color(0, 0, 0, 0.24))
		draw_circle(position, 18.0, Color("3d7650"))
	draw_circle(Vector2(2065, 590), 38.0, Color("304a50"))
	draw_circle(Vector2(2065, 590), 30.0, Color("72aeb5"), false, 4.0)
	draw_circle(Vector2(2065, 590), 8.0, Color("d8c57c"))


func _draw_street_details() -> void:
	for x in range(45, int(WORLD_SIZE.x), 125):
		draw_line(Vector2(x, 555), Vector2(x + 55, 555), Color("869094"), 4.0)
	for y in range(25, int(WORLD_SIZE.y), 120):
		draw_line(Vector2(875, y), Vector2(875, y + 55), Color("869094"), 4.0)
		draw_line(Vector2(1725, y), Vector2(1725, y + 55), Color("869094"), 4.0)
	for x in range(45, int(WORLD_SIZE.x), 145):
		draw_line(Vector2(x, 1100), Vector2(x + 62, 1100), Color("869094"), 4.0)
	for light_pos in [Vector2(650, 445), Vector2(1110, 445), Vector2(650, 700), Vector2(1110, 700), Vector2(1640, 430), Vector2(1815, 430), Vector2(1640, 740), Vector2(1815, 740)]:
		draw_circle(light_pos + Vector2(3, 5), 10, Color(0, 0, 0, 0.3))
		draw_circle(light_pos, 8, Color("f2d38a"))


func _draw_sidewalks_and_props() -> void:
	# Pavement edges make the walkable street network legible at a glance.
	for y in [430.0, 690.0, 1030.0, 1175.0]:
		draw_line(Vector2(0, y), Vector2(WORLD_SIZE.x, y), Color("87918c"), 3.0)
	for x in [675.0, 1075.0, 1640.0, 1815.0]:
		draw_line(Vector2(x, 0), Vector2(x, WORLD_SIZE.y), Color("87918c"), 3.0)
	# Bus stops, bicycles, planters and parked service vehicles are landmarks,
	# not interactive objects; they visually distinguish the neighbourhoods.
	for stop in [Vector2(740, 650), Vector2(1555, 650), Vector2(1860, 1090)]:
		draw_rect(Rect2(stop, Vector2(54, 8)), Color("1d292e"))
		draw_line(stop + Vector2(5, 0), stop + Vector2(5, -34), Color("7ccbd2"), 4.0)
		draw_rect(Rect2(stop + Vector2(-2, -40), Vector2(28, 14)), Color("3f747b"))
	for bicycle in [Vector2(620, 720), Vector2(1110, 760), Vector2(1780, 780)]:
		draw_circle(bicycle, 8.0, Color("9aa7a5"), false, 2.0)
		draw_circle(bicycle + Vector2(20, 0), 8.0, Color("9aa7a5"), false, 2.0)
		draw_line(bicycle, bicycle + Vector2(10, -10), Color("d9b66e"), 2.0)
		draw_line(bicycle + Vector2(10, -10), bicycle + Vector2(20, 0), Color("d9b66e"), 2.0)
	for vehicle in [Rect2(720, 535, 82, 36), Rect2(1470, 574, 92, 38), Rect2(1850, 1060, 86, 36)]:
		draw_rect(vehicle, Color("415864"))
		draw_rect(Rect2(vehicle.position + Vector2(18, 5), Vector2(vehicle.size.x - 36, 12)), Color("83a7aa"))
		draw_circle(vehicle.position + Vector2(18, vehicle.size.y), 6.0, Color("151c20"))
		draw_circle(vehicle.end - Vector2(18, 0), 6.0, Color("151c20"))
	for planter in [Vector2(1140, 670), Vector2(1600, 1020), Vector2(1818, 750), Vector2(600, 1040)]:
		draw_rect(Rect2(planter - Vector2(15, 8), Vector2(30, 16)), Color("644c38"))
		draw_circle(planter - Vector2(0, 10), 12.0, Color("43805a"))


func _draw_crosswalk(origin: Vector2, horizontal: bool) -> void:
	for index in range(6):
		var offset := index * 20.0
		if horizontal:
			draw_rect(Rect2(origin + Vector2(offset, 0), Vector2(12, 45)), Color("d8dedb"))
		else:
			draw_rect(Rect2(origin + Vector2(0, offset), Vector2(45, 12)), Color("d8dedb"))


func _draw_aurora_entrance() -> void:
	var entrance := Vector2(1385, 418)
	draw_arc(entrance, 34.0, PI, TAU, 28, Color("72c8d7"), 4.0)
	draw_circle(entrance, 6.0, Color("f0d28b"))
	draw_string(ThemeDB.fallback_font, entrance + Vector2(-52, 30), "ВХОД AURORA", HORIZONTAL_ALIGNMENT_CENTER, 104, 14, Color("dcebea"))


func _create_world_collisions() -> void:
	for building: Dictionary in BUILDINGS:
		_add_static_rect(building.rect)
	_add_static_rect(Rect2(-40, -40, WORLD_SIZE.x + 80, 40))
	_add_static_rect(Rect2(-40, WORLD_SIZE.y, WORLD_SIZE.x + 80, 40))
	_add_static_rect(Rect2(-40, 0, 40, WORLD_SIZE.y))
	_add_static_rect(Rect2(WORLD_SIZE.x, 0, 40, WORLD_SIZE.y))


func _add_static_rect(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	body.add_child(shape)
	add_child(body)


func _create_signs() -> void:
	for building: Dictionary in BUILDINGS:
		var label := Label.new()
		label.text = building.name
		label.position = building.rect.position + Vector2(22, 22)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", building.accent)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(label)
	var plaza := Label.new()
	plaza.text = "ГОРОДСКАЯ ПЛОЩАДЬ"
	plaza.position = Vector2(746, 505)
	plaza.add_theme_font_size_override("font_size", 15)
	plaza.add_theme_color_override("font_color", Color("d8e1db"))
	add_child(plaza)
	var east_square := Label.new()
	east_square.text = "ПЛОЩАДЬ СООБЩЕСТВА"
	east_square.position = Vector2(1965, 485)
	east_square.add_theme_font_size_override("font_size", 15)
	east_square.add_theme_color_override("font_color", Color("e7debd"))
	add_child(east_square)
