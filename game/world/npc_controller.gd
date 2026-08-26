class_name NpcController
extends CharacterBody2D

var person_id := 0
var known_name := "Незнакомец"
var movement_zone := Rect2()
var movement_paused := false
var speed := 64.0
var accent := Color("72c8d7")
var role_hint := "resident"
var execution_phase := "PERFORM"
var visual_action := "IDLE"

var _target := Vector2.ZERO
var _wait_time := 0.0
var _rng := RandomNumberGenerator.new()
var _name_label: Label
var _walk_phase := 0.0
var _facing := Vector2.DOWN
var _activity_anchor_active := false


func setup(id: int, label_text: String, zone: Rect2, color: Color, role: String = "resident") -> void:
	person_id = id
	known_name = label_text
	movement_zone = zone
	accent = color
	role_hint = role.to_lower()
	_rng.seed = 9109 + id * 7919
	speed = 54.0 + float(id % 5) * 7.0


func _ready() -> void:
	add_to_group("npc")
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	collision.shape = shape
	add_child(collision)
	_name_label = Label.new()
	_name_label.text = known_name
	_name_label.position = Vector2(-58, -48)
	_name_label.size = Vector2(116, 24)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color("f4f0df"))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_name_label)
	_pick_target()
	queue_redraw()


func set_known_name(value: String) -> void:
	known_name = value
	if _name_label != null:
		_name_label.text = value


func set_movement_zone(zone: Rect2) -> void:
	movement_zone = zone
	if not movement_zone.grow(20.0).has_point(global_position):
		global_position = movement_zone.get_center()
	_pick_target()


func set_activity_state(state: Dictionary) -> void:
	execution_phase = str(state.get("execution_phase", "PERFORM"))
	visual_action = str(state.get("visual_action", "IDLE"))
	var spot_id := str(state.get("activity_spot_id", ""))
	_activity_anchor_active = (
		not spot_id.is_empty() and execution_phase in ["RESERVE", "PERFORM"]
	)
	if _activity_anchor_active:
		var parts := spot_id.split("-S")
		var spot_index := int(parts[1]) if parts.size() > 1 else 0
		var column := posmod(spot_index, 8)
		var row := posmod(int(spot_index / 8), 12)
		_target = Vector2(
			movement_zone.position.x + (float(column) + 0.5) * movement_zone.size.x / 8.0,
			movement_zone.position.y + (float(row) + 0.5) * movement_zone.size.y / 12.0,
		)
	elif execution_phase in ["FINISH", "INTERRUPT"]:
		_pick_target()


func _physics_process(delta: float) -> void:
	if movement_paused:
		velocity = velocity.move_toward(Vector2.ZERO, 480.0 * delta)
		move_and_slide()
		return
	if _wait_time > 0.0:
		_wait_time -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 420.0 * delta)
		move_and_slide()
		return
	if _activity_anchor_active and global_position.distance_to(_target) < 8.0:
		velocity = velocity.move_toward(Vector2.ZERO, 480.0 * delta)
		move_and_slide()
		queue_redraw()
		return
	var direction := global_position.direction_to(_target)
	if global_position.distance_to(_target) < 12.0:
		_wait_time = _rng.randf_range(0.7, 2.5)
		_pick_target()
		return
	velocity = velocity.move_toward(direction * speed, 320.0 * delta)
	move_and_slide()
	if velocity.length_squared() > 4.0:
		_facing = velocity.normalized()
		_walk_phase += delta * (6.0 + speed * 0.025)
		queue_redraw()
	if get_slide_collision_count() > 0:
		_pick_target()


func _pick_target() -> void:
	_target = Vector2(
		_rng.randf_range(movement_zone.position.x, movement_zone.end.x),
		_rng.randf_range(movement_zone.position.y, movement_zone.end.y)
	)


func _draw() -> void:
	var moving := velocity.length_squared() > 16.0
	var stride: float = sin(_walk_phase) * 4.5 if moving else 0.0
	var bob: float = abs(sin(_walk_phase)) * 1.4 if moving else 0.0
	draw_ellipse(Vector2(2, 11), 17.0, 8.0, Color(0, 0, 0, 0.28))
	draw_line(Vector2(-5, 7 - bob), Vector2(-6 + stride, 15), accent.darkened(0.42), 4.0)
	draw_line(Vector2(5, 7 - bob), Vector2(6 - stride, 15), accent.darkened(0.42), 4.0)
	draw_line(Vector2(-11, -1 - bob), Vector2(-13 - stride * 0.45, 6), accent.darkened(0.2), 3.0)
	draw_line(Vector2(11, -1 - bob), Vector2(13 + stride * 0.45, 6), accent.darkened(0.2), 3.0)
	draw_circle(Vector2(0, -bob), 15.5, accent.darkened(0.18))
	draw_circle(Vector2(0, -5 - bob), 10.5, accent)
	draw_arc(Vector2(0, -bob), 15.5, 0, TAU, 24, accent.lightened(0.35), 1.5)
	var face_offset := _facing * 3.0
	draw_circle(Vector2(-3, -6 - bob) + face_offset, 1.3, Color("17242a"))
	draw_circle(Vector2(3, -6 - bob) + face_offset, 1.3, Color("17242a"))
	_draw_role_marker(Vector2(0, -bob))
	if _activity_anchor_active:
		draw_arc(Vector2(0, 17), 5.0, 0.0, TAU, 10, accent.lightened(0.4), 1.5)


func _draw_role_marker(origin: Vector2) -> void:
	if "security" in role_hint or "doorman" in role_hint:
		draw_rect(Rect2(origin + Vector2(-7, 1), Vector2(14, 8)), Color("263f58"))
		draw_circle(origin + Vector2(0, 4), 2.0, Color("d5c777"))
	elif "journalist" in role_hint or "photographer" in role_hint or "editor" in role_hint:
		draw_rect(Rect2(origin + Vector2(8, -1), Vector2(7, 9)), Color("263039"))
		draw_circle(origin + Vector2(11.5, 2), 2.0, Color("9ed3d7"))
	elif "barista" in role_hint or "cafe" in role_hint or "catering" in role_hint:
		draw_arc(origin + Vector2(0, 1), 11.0, 0.15, PI - 0.15, 12, Color("f0dfbf"), 3.0)
	elif "engineer" in role_hint or "contractor" in role_hint:
		draw_arc(origin + Vector2(0, -8), 8.0, PI, TAU, 12, Color("e7bd62"), 4.0)
