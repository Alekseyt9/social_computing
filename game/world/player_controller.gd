class_name PlayerController
extends CharacterBody2D

const SPEED := 235.0
const ACCELERATION := 1500.0

var input_enabled := true
var facing := Vector2.DOWN
var _walk_phase := 0.0


func _ready() -> void:
	add_to_group("player")
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 15.0
	collision.shape = shape
	add_child(collision)
	queue_redraw()


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if input_enabled:
		input_vector = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		input_vector += Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)
		input_vector = input_vector.limit_length(1.0)
	if input_vector.length_squared() > 0.01:
		facing = input_vector.normalized()
	velocity = velocity.move_toward(input_vector * SPEED, ACCELERATION * delta)
	move_and_slide()
	if velocity.length_squared() > 16.0:
		_walk_phase += delta * 10.0
	queue_redraw()


func _draw() -> void:
	var moving := velocity.length_squared() > 16.0
	var stride: float = sin(_walk_phase) * 5.0 if moving else 0.0
	var bob: float = abs(sin(_walk_phase)) * 1.6 if moving else 0.0
	draw_ellipse(Vector2(2, 12), 19.0, 9.0, Color(0, 0, 0, 0.32))
	draw_line(Vector2(-6, 7 - bob), Vector2(-7 + stride, 16), Color("7f633c"), 4.5)
	draw_line(Vector2(6, 7 - bob), Vector2(7 - stride, 16), Color("7f633c"), 4.5)
	draw_circle(Vector2(0, -bob), 17.0, Color("e9bf75"))
	draw_circle(Vector2(0, -4 - bob), 12.0, Color("efcf91"))
	draw_arc(Vector2(0, -bob), 17.0, 0, TAU, 28, Color("fff0ca"), 2.0)
	draw_circle(facing * 8.0 + Vector2(0, -bob), 3.0, Color("31434e"))
	draw_arc(Vector2(0, -9 - bob), 8.0, PI, TAU, 14, Color("36434b"), 5.0)
