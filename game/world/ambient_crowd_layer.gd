class_name AmbientCrowdLayer
extends Node2D

const MAX_VISIBLE := 45
const PLACE_ZONES := {
	1: Rect2(1160, 430, 430, 300),
	2: Rect2(625, 465, 470, 180),
	3: Rect2(545, 705, 500, 250),
}

var _world: RefCounted
var _citizens: Dictionary = {}
var _motion_clock: float = 0.0


func setup(world: RefCounted) -> void:
	_world = world


func sync_from_simulation() -> void:
	if _world == null:
		return
	var adaptive: Dictionary = _world.get_adaptive_population_snapshot()
	var desired: Dictionary = {}
	var ids: Array = adaptive.get("refined_light_ids", [])
	for index in range(mini(MAX_VISIBLE, ids.size())):
		var agent_id := int(ids[index])
		var view: Dictionary = _world.get_light_agent_view(agent_id)
		if view.is_empty():
			continue
		var place_id := int(view.current_place_id)
		var zone: Rect2 = PLACE_ZONES.get(place_id, PLACE_ZONES[2])
		desired[agent_id] = true
		if not _citizens.has(agent_id):
			var start := _point_in_zone(agent_id, 11, zone)
			_citizens[agent_id] = {
				"position": start,
				"target": _point_in_zone(agent_id, 29, zone),
				"place_id": place_id,
				"speed": 25.0 + float(agent_id % 23),
				"accent": _agent_color(view),
				"phase": _unit(agent_id, 43) * TAU,
			}
		else:
			var state: Dictionary = _citizens[agent_id]
			if int(state.place_id) != place_id:
				state["place_id"] = place_id
				state["position"] = _point_in_zone(agent_id, int(_motion_clock) + 47, zone)
				state["target"] = _point_in_zone(agent_id, int(_motion_clock) + 71, zone)
			state["accent"] = _agent_color(view)
			_citizens[agent_id] = state
	for agent_id: int in _citizens.keys():
		if not desired.has(agent_id):
			_citizens.erase(agent_id)
	queue_redraw()


func get_visible_count() -> int:
	return _citizens.size()


func has_citizen(agent_id: int) -> bool:
	return _citizens.has(agent_id)


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
		}
	return nearest


func get_place_zone(place_id: int) -> Rect2:
	return PLACE_ZONES.get(place_id, PLACE_ZONES[2])


func _process(delta: float) -> void:
	_motion_clock += delta
	for agent_id: int in _citizens:
		var state: Dictionary = _citizens[agent_id]
		var position_value: Vector2 = state.position
		var target_value: Vector2 = state.target
		if position_value.distance_to(target_value) < 5.0:
			var zone: Rect2 = PLACE_ZONES.get(int(state.place_id), PLACE_ZONES[2])
			state["target"] = _point_in_zone(
				agent_id, int(_motion_clock * 10.0) + agent_id, zone
			)
		else:
			state["position"] = position_value.move_toward(
				target_value, float(state.speed) * delta
			)
		_citizens[agent_id] = state
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


func _agent_color(view: Dictionary) -> Color:
	match int(view.get("workplace_organization_id", 0)):
		1:
			return Color("66aeb8c8")
		2:
			return Color("c59563c8")
		_:
			return Color("8796a0b8")


func _point_in_zone(agent_id: int, salt: int, zone: Rect2) -> Vector2:
	return Vector2(
		zone.position.x + 16.0 + _unit(agent_id, salt) * maxf(1.0, zone.size.x - 32.0),
		zone.position.y + 16.0 + _unit(agent_id, salt + 101) * maxf(1.0, zone.size.y - 32.0),
	)


func _unit(agent_id: int, salt: int) -> float:
	var value := (agent_id * 1_103_515_245 + salt * 12_345) & 0x7fffffff
	return float(value) / float(0x7fffffff)
