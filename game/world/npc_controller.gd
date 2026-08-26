class_name NpcController
extends CharacterBody2D

var person_id := 0
var known_name := "Незнакомец"
var movement_zone := Rect2()
var movement_paused := false
var speed := 64.0
var accent := Color("72c8d7")

var _target := Vector2.ZERO
var _wait_time := 0.0
var _rng := RandomNumberGenerator.new()
var _name_label: Label


func setup(id: int, label_text: String, zone: Rect2, color: Color) -> void:
	person_id = id
	known_name = label_text
	movement_zone = zone
	accent = color
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
	var direction := global_position.direction_to(_target)
	if global_position.distance_to(_target) < 12.0:
		_wait_time = _rng.randf_range(0.7, 2.5)
		_pick_target()
		return
	velocity = velocity.move_toward(direction * speed, 320.0 * delta)
	move_and_slide()
	if get_slide_collision_count() > 0:
		_pick_target()


func _pick_target() -> void:
	_target = Vector2(
		_rng.randf_range(movement_zone.position.x, movement_zone.end.x),
		_rng.randf_range(movement_zone.position.y, movement_zone.end.y)
	)


func _draw() -> void:
	draw_ellipse(Vector2(2, 9), 17.0, 9.0, Color(0, 0, 0, 0.28))
	draw_circle(Vector2.ZERO, 15.5, accent.darkened(0.18))
	draw_circle(Vector2(0, -4), 11.0, accent)
	draw_arc(Vector2.ZERO, 15.5, 0, TAU, 24, accent.lightened(0.35), 1.5)
	draw_circle(Vector2(-4, -6), 1.5, Color("17242a"))
	draw_circle(Vector2(4, -6), 1.5, Color("17242a"))
