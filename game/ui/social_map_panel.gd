class_name SocialMapPanel
extends Control

var _graph: Dictionary = {"nodes": [], "edges": []}
var _positions: Dictionary = {}


func set_graph(graph: Dictionary) -> void:
	_graph = graph.duplicate(true)
	_layout_nodes()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_nodes()
		queue_redraw()


func _layout_nodes() -> void:
	_positions.clear()
	var center := size * 0.5
	var people: Array[Dictionary] = []
	var organizations: Array[Dictionary] = []
	var places: Array[Dictionary] = []
	for node: Dictionary in _graph.get("nodes", []):
		match str(node.get("kind", "")):
			"ORGANIZATION": organizations.append(node)
			"PLACE": places.append(node)
			_: people.append(node)
	people.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.id) < str(right.id)
	)
	for index in range(people.size()):
		var node: Dictionary = people[index]
		if bool(node.get("is_player", false)):
			_positions[node.id] = center
		else:
			var angle := TAU * float(index) / float(maxi(1, people.size())) - PI * 0.5
			_positions[node.id] = center + Vector2(cos(angle), sin(angle)) * minf(size.x, size.y) * 0.31
	for index in range(organizations.size()):
		_positions[organizations[index].id] = Vector2(size.x - 100.0, 90.0 + index * 105.0)
	for index in range(places.size()):
		_positions[places[index].id] = Vector2(100.0, size.y - 85.0 - index * 90.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10191ff2"), true)
	var font := ThemeDB.fallback_font
	for edge: Dictionary in _graph.get("edges", []):
		if not _positions.has(edge.source) or not _positions.has(edge.target):
			continue
		var start: Vector2 = _positions[edge.source]
		var finish: Vector2 = _positions[edge.target]
		draw_line(start, finish, Color("57727b"), 2.0, true)
		var midpoint := start.lerp(finish, 0.5)
		draw_string(font, midpoint + Vector2(5, -4), str(edge.kind), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8ca7ad"))
	for node: Dictionary in _graph.get("nodes", []):
		if not _positions.has(node.id):
			continue
		var point: Vector2 = _positions[node.id]
		var color := Color("e1b66d") if bool(node.get("is_player", false)) else Color("6faeb8")
		if str(node.kind) == "ORGANIZATION":
			color = Color("b888cc")
		elif str(node.kind) == "PLACE":
			color = Color("78a57f")
		draw_circle(point, 24.0, Color("17262c"))
		draw_circle(point, 20.0, color)
		var label := str(node.label)
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, point + Vector2(-label_width * 0.5, 42), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("eef4ef"))
