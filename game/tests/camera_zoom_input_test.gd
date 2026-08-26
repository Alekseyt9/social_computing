extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var before_start := float(scene._camera_zoom_target)
	scene._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	if not is_equal_approx(float(scene._camera_zoom_target), before_start):
		_fail(scene, "Start menu allowed camera zoom")
		return
	scene._start_new_game()
	var initial := float(scene._camera_zoom_target)
	scene._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	if float(scene._camera_zoom_target) <= initial:
		_fail(scene, "Mouse wheel up did not zoom in")
		return
	scene._update_camera_zoom(0.5)
	var camera := scene.player.get_node("Camera2D") as Camera2D
	if camera.zoom.x <= initial or not is_equal_approx(camera.zoom.x, camera.zoom.y):
		_fail(scene, "Camera did not smoothly apply uniform zoom")
		return
	for _index in range(60):
		scene._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	if not is_equal_approx(float(scene._camera_zoom_target), float(scene._camera_zoom_min)):
		_fail(scene, "Zoom out did not stop at the map-safe minimum")
		return
	var captured: Dictionary = scene._capture_view_state()
	if not captured.has("camera_zoom") or not is_equal_approx(
		float(captured.camera_zoom), float(scene._camera_zoom_target)
	):
		_fail(scene, "Save view state does not contain camera zoom")
		return
	var blocked_zoom := float(scene._camera_zoom_target)
	scene._dialogue_panel.visible = true
	scene._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	if not is_equal_approx(float(scene._camera_zoom_target), blocked_zoom):
		_fail(scene, "Dialogue allowed world camera zoom")
		return
	scene._dialogue_panel.visible = false
	print("CAMERA_ZOOM_OK initial=%.2f min=%.2f max=%.2f smooth=true saved=true modal_safe=true" % [
		initial, float(scene._camera_zoom_min), float(scene.CAMERA_ZOOM_MAX),
	])
	scene.queue_free()
	quit(0)


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _fail(scene: Node, message: String) -> void:
	push_error(message)
	scene.queue_free()
	quit(1)
