class_name AmbientCrowdLayer
extends Node2D

const MAX_VISIBLE := 45
const PLACE_ZONES := {
	1: Rect2(1160, 430, 430, 300),
	2: Rect2(625, 465, 470, 180),
	3: Rect2(620, 1180, 500, 190),
	4: Rect2(85, 480, 425, 225),
	5: Rect2(1165, 1015, 430, 170),
	6: Rect2(1815, 430, 500, 315),
	7: Rect2(1840, 1015, 420, 150),
	8: Rect2(1210, 1175, 400, 200),
}

var _world: RefCounted
var _citizens: Dictionary = {}
var _motion_clock: float = 0.0
var _interior_place_id: int = -1
var _interior_zone := Rect2()
var motion_paused := false


func setup(world: RefCounted) -> void:
	_world = world


func enter_interior(place_id: int, activity_zone: Rect2) -> void:
	_interior_place_id = place_id
	_interior_zone = activity_zone
	_citizens.clear()
	queue_redraw()


func exit_interior() -> void:
	_interior_place_id = -1
	_interior_zone = Rect2()
	_citizens.clear()
	queue_redraw()


func sync_from_simulation() -> void:
	if _world == null:
		return
	var adaptive: Dictionary = _world.get_adaptive_population_snapshot()
	var ids: Array = adaptive.get("refined_light_ids", [])
	var refined: Dictionary = {}
	for value: Variant in ids:
		refined[int(value)] = true
	# Existing residents get a chance to visibly finish a commute before they
	# leave the local detailed set. Interactively promoted people disappear
	# immediately because WorldScreen replaces them with a CharacterBody2D.
	for agent_id: int in _citizens.keys():
		if _world.has_person(agent_id):
			_citizens.erase(agent_id)
			continue
		var view: Dictionary = _world.get_light_agent_view(agent_id)
		if view.is_empty():
			_citizens.erase(agent_id)
			continue
		var state: Dictionary = _citizens[agent_id]
		var scheduled_place := int(view.current_place_id)
		if scheduled_place != int(state.get("destination_place_id", state.place_id)):
			_begin_trip(agent_id, state, scheduled_place, str(view.activity_label))
		elif not bool(state.get("traveling", false)):
			state["activity_label"] = str(view.activity_label)
		state["retiring"] = not refined.has(agent_id)
		state["accent"] = _agent_color(view)
		state["activity"] = str(view.current_activity)
		state["execution_phase"] = str(view.get("execution_phase", "PERFORM"))
		state["phase_label"] = str(view.get("phase_label", ""))
		state["activity_spot_id"] = str(view.get("activity_spot_id", ""))
		state["visual_action"] = str(view.get("visual_action", "IDLE"))
		if not bool(state.get("traveling", false)) and not str(state.activity_spot_id).is_empty():
			state["target"] = _activity_spot_point(
				str(state.activity_spot_id), get_place_zone(int(state.place_id))
			)
		if bool(state.retiring) and not bool(state.traveling):
			_citizens.erase(agent_id)
		else:
			_citizens[agent_id] = state
	# Fill the remaining visual budget. If a schedule boundary was crossed in
	# the last sync interval, the new citizen starts at the previous place and
	# walks the route instead of popping into existence at the destination.
	for value: Variant in ids:
		if _citizens.size() >= MAX_VISIBLE:
			break
		var agent_id := int(value)
		if _citizens.has(agent_id) or _world.has_person(agent_id):
			continue
		var view: Dictionary = _world.get_light_agent_view(agent_id)
		if view.is_empty():
			continue
		var place_id := int(view.current_place_id)
		var previous: Dictionary = _world.get_light_agent_schedule_state(
			agent_id, maxi(0, int(_world.tick) - 12)
		)
		var origin_place := int(previous.get("place_id", place_id))
		if _interior_place_id == place_id:
			origin_place = place_id
		var origin_zone: Rect2 = get_place_zone(origin_place)
		var state := {
			"position": _point_in_zone(agent_id, 11, origin_zone),
			"target": Vector2.ZERO,
			"place_id": origin_place,
			"destination_place_id": origin_place,
			"route": [] as Array[Vector2],
			"traveling": false,
			"retiring": false,
			"speed": 25.0 + float(agent_id % 23),
			"travel_speed": 86.0 + float(agent_id % 29),
			"accent": _agent_color(view),
			"phase": _unit(agent_id, 43) * TAU,
			"activity": str(view.current_activity),
			"activity_label": str(view.activity_label),
			"execution_phase": str(view.get("execution_phase", "PERFORM")),
			"phase_label": str(view.get("phase_label", "")),
			"activity_spot_id": str(view.get("activity_spot_id", "")),
			"visual_action": str(view.get("visual_action", "IDLE")),
		}
		if origin_place != place_id:
			_begin_trip(agent_id, state, place_id, str(view.activity_label))
		else:
			state["target"] = (
				_activity_spot_point(str(state.activity_spot_id), origin_zone)
				if not str(state.activity_spot_id).is_empty()
				else _point_in_zone(agent_id, 29, origin_zone)
			)
		_citizens[agent_id] = state
	queue_redraw()


func get_visible_count() -> int:
	return _citizens.size()


func get_visible_citizen_ids() -> Array[int]:
	var result: Array[int] = []
	for agent_id: int in _citizens:
		result.append(agent_id)
	result.sort()
	return result


func has_citizen(agent_id: int) -> bool:
	return _citizens.has(agent_id)


func get_traveling_count() -> int:
	var count := 0
	for state: Dictionary in _citizens.values():
		if bool(state.get("traveling", false)):
			count += 1
	return count


func get_nearest_citizen(world_position: Vector2, max_distance: float) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := maxf(0.0, max_distance)
	for agent_id: int in _citizens:
		var state: Dictionary = _citizens[agent_id]
		var distance := world_position.distance_to(state.position)
		if distance >= nearest_distance:
			continue
		nearest_distance = distance
		nearest = {
			"agent_id": agent_id,
			"position": state.position,
			"place_id": int(state.place_id),
			"accent": state.accent,
			"distance": distance,
			"activity": str(state.get("activity", "")),
			"activity_label": str(state.get("activity_label", "")),
			"traveling": bool(state.get("traveling", false)),
			"execution_phase": str(state.get("execution_phase", "PERFORM")),
			"phase_label": str(state.get("phase_label", "")),
			"activity_spot_id": str(state.get("activity_spot_id", "")),
			"visual_action": str(state.get("visual_action", "IDLE")),
		}
	return nearest


func get_place_zone(place_id: int) -> Rect2:
	if place_id == _interior_place_id and _interior_zone.has_area():
		return _interior_zone
	return PLACE_ZONES.get(place_id, PLACE_ZONES[2])


func get_spawn_point(agent_id: int, place_id: int) -> Vector2:
	return _point_in_zone(agent_id, 83 + place_id * 17, get_place_zone(place_id))


func _process(delta: float) -> void:
	if motion_paused:
		return
	_motion_clock += delta
	var completed_retirements: Array[int] = []
	for agent_id: int in _citizens:
		var state: Dictionary = _citizens[agent_id]
		var position_value: Vector2 = state.position
		var target_value: Vector2 = state.target
		if position_value.distance_to(target_value) < 5.0:
			if bool(state.get("traveling", false)):
				var route: Array = state.get("route", [])
				if not route.is_empty():
					state["target"] = route.pop_front()
					state["route"] = route
				else:
					state["traveling"] = false
					state["place_id"] = int(state.destination_place_id)
					state["activity_label"] = str(
						state.get("destination_activity_label", state.activity_label)
					)
					if bool(state.get("retiring", false)):
						completed_retirements.append(agent_id)
					else:
						var arrival_zone := get_place_zone(int(state.place_id))
						state["target"] = _point_in_zone(
							agent_id, int(_motion_clock * 10.0) + agent_id, arrival_zone
						)
			else:
				var spot_id := str(state.get("activity_spot_id", ""))
				if spot_id.is_empty():
					var zone: Rect2 = get_place_zone(int(state.place_id))
					state["target"] = _point_in_zone(
						agent_id, int(_motion_clock * 10.0) + agent_id, zone
					)
		else:
			var movement_speed := (
				float(state.travel_speed) if bool(state.get("traveling", false))
				else float(state.speed)
			)
			state["position"] = position_value.move_toward(
				target_value, movement_speed * delta
			)
		_citizens[agent_id] = state
	for agent_id: int in completed_retirements:
		_citizens.erase(agent_id)
	queue_redraw()


func _draw() -> void:
	for agent_id: int in _citizens:
		var state: Dictionary = _citizens[agent_id]
		var point: Vector2 = state.position
		var accent: Color = state.accent
		var bob := sin(_motion_clock * 4.0 + float(state.phase)) * 1.2
		draw_ellipse(point + Vector2(2, 8), 11.0, 5.0, Color(0, 0, 0, 0.22))
		draw_line(point + Vector2(-4, 5), point + Vector2(-5, 12), accent.darkened(0.35), 2.0)
		draw_line(point + Vector2(4, 5), point + Vector2(5, 12), accent.darkened(0.35), 2.0)
		draw_circle(point + Vector2(0, bob), 9.0, accent.darkened(0.15))
		draw_circle(point + Vector2(0, -7 + bob), 5.5, accent.lightened(0.18))
		if bool(state.get("traveling", false)):
			draw_rect(Rect2(point + Vector2(6, -1 + bob), Vector2(5, 8)), accent.lightened(0.35))
		elif not str(state.get("activity_spot_id", "")).is_empty():
			draw_arc(point + Vector2(0, 13), 4.0, 0.0, TAU, 10, accent.lightened(0.45), 1.5)
			_draw_activity_mark(point + Vector2(12, -12 + bob), str(state.get("visual_action", "IDLE")), accent)


func _begin_trip(
	agent_id: int, state: Dictionary, destination_place_id: int, activity_label: String
) -> void:
	var origin_place := int(state.get("place_id", destination_place_id))
	var destination_zone := get_place_zone(destination_place_id)
	var destination := _point_in_zone(
		agent_id, int(_world.tick) + destination_place_id * 41, destination_zone
	)
	var route := _route_between(
		state.position, origin_place, destination_place_id, destination
	)
	state["destination_place_id"] = destination_place_id
	state["traveling"] = true
	state["destination_activity_label"] = activity_label
	state["activity_label"] = "идёт: %s" % activity_label
	state["route"] = route
	state["target"] = route.pop_front() if not route.is_empty() else destination
	state["route"] = route


func _route_between(
	from_position: Vector2,
	from_place_id: int,
	destination_place_id: int,
	destination: Vector2
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var origin_gate := _place_gate(from_place_id)
	if from_position.distance_to(origin_gate) > 10.0:
		points.append(origin_gate)
	var origin_hubs := _hubs_to_center(from_place_id)
	for point: Vector2 in origin_hubs:
		points.append(point)
	var destination_hubs := _hubs_to_center(destination_place_id)
	destination_hubs.reverse()
	for point: Vector2 in destination_hubs:
		if points.is_empty() or points.back().distance_to(point) > 4.0:
			points.append(point)
	var destination_gate := _place_gate(destination_place_id)
	if points.is_empty() or points.back().distance_to(destination_gate) > 4.0:
		points.append(destination_gate)
	points.append(destination)
	return points


func _hubs_to_center(place_id: int) -> Array[Vector2]:
	match place_id:
		1:
			return [Vector2(1120, 560), Vector2(875, 560)] as Array[Vector2]
		2:
			return [Vector2(875, 560)] as Array[Vector2]
		3:
			return [Vector2(875, 1100), Vector2(875, 560)] as Array[Vector2]
		4:
			return [Vector2(610, 560), Vector2(875, 560)] as Array[Vector2]
		5:
			return [Vector2(1370, 1100), Vector2(1725, 1100), Vector2(1725, 560), Vector2(875, 560)] as Array[Vector2]
		6:
			return [Vector2(1815, 560), Vector2(1725, 560), Vector2(875, 560)] as Array[Vector2]
		7:
			return [Vector2(1815, 1100), Vector2(1725, 1100), Vector2(875, 1100), Vector2(875, 560)] as Array[Vector2]
		8:
			return [Vector2(1410, 1100), Vector2(875, 1100), Vector2(875, 560)] as Array[Vector2]
		_:
			return [Vector2(875, 560)] as Array[Vector2]


func _place_gate(place_id: int) -> Vector2:
	match place_id:
		1: return Vector2(1385, 430)
		2: return Vector2(875, 560)
		3: return Vector2(875, 1175)
		4: return Vector2(515, 560)
		5: return Vector2(1370, 1015)
		6: return Vector2(1815, 590)
		7: return Vector2(2060, 1015)
		8: return Vector2(1410, 1175)
		_: return Vector2(875, 560)


func _agent_color(view: Dictionary) -> Color:
	match int(view.get("workplace_organization_id", 0)):
		1:
			return Color("66aeb8c8")
		2:
			return Color("c59563c8")
		_:
			return Color("8796a0b8")


func _activity_spot_point(spot_id: String, zone: Rect2) -> Vector2:
	var parts := spot_id.split("-S")
	var spot_index := int(parts[1]) if parts.size() > 1 else 0
	var columns := 8
	var rows := 12
	var column := posmod(spot_index, columns)
	var row := posmod(int(spot_index / columns), rows)
	return Vector2(
		zone.position.x + (float(column) + 0.5) * zone.size.x / float(columns),
		zone.position.y + (float(row) + 0.5) * zone.size.y / float(rows),
	)


func _draw_activity_mark(point: Vector2, action: String, color: Color) -> void:
	draw_circle(point, 5.0, Color(0.06, 0.09, 0.11, 0.82))
	if action in ["TALK", "HELP"]:
		draw_circle(point, 2.2, color.lightened(0.35))
	elif action in ["READ", "TYPE", "CRAFT", "BROWSE"]:
		draw_rect(Rect2(point - Vector2(2.5, 2.0), Vector2(5.0, 4.0)), color.lightened(0.35))
	elif action in ["EAT", "DRINK"]:
		draw_line(point + Vector2(-2, 2), point + Vector2(2, -2), color.lightened(0.35), 2.0)
	else:
		draw_arc(point, 2.5, 0.0, TAU, 8, color.lightened(0.35), 1.5)


func _point_in_zone(agent_id: int, salt: int, zone: Rect2) -> Vector2:
	return Vector2(
		zone.position.x + 16.0 + _unit(agent_id, salt) * maxf(1.0, zone.size.x - 32.0),
		zone.position.y + 16.0 + _unit(agent_id, salt + 101) * maxf(1.0, zone.size.y - 32.0),
	)


func _unit(agent_id: int, salt: int) -> float:
	var value := (agent_id * 1_103_515_245 + salt * 12_345) & 0x7fffffff
	return float(value) / float(0x7fffffff)
