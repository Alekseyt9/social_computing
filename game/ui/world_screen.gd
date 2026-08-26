extends Node2D

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const WorldMapScript := preload("res://world/world_map.gd")
const PlayerControllerScript := preload("res://world/player_controller.gd")
const NpcControllerScript := preload("res://world/npc_controller.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")
const SocialActionPresenterScript := preload("res://rendering/social_action_presenter.gd")
const SocialMapPanelScript := preload("res://ui/social_map_panel.gd")
const AmbientCrowdLayerScript := preload("res://world/ambient_crowd_layer.gd")
const PlaceInteriorScript := preload("res://world/place_interior.gd")
const SaveGameServiceScript := preload("res://core/save_game_service.gd")
const DistrictMinimapScript := preload("res://ui/district_minimap.gd")
const ActivityStatusCardScript := preload("res://ui/activity_status_card.gd")

const INTERACTION_DISTANCE := 92.0
const INTERIOR_ORIGIN := Vector2(2600, 0)
const CAMERA_ZOOM_MIN_ABSOLUTE := 0.58
const CAMERA_ZOOM_MAX := 2.0
const CAMERA_ZOOM_STEP := 1.14
const CAMERA_ZOOM_SMOOTH_SPEED := 12.0
const INTERACTIVE_PLACES := {
	2: {"name": "Corner Cafe", "entrance": Vector2(345, 418), "color": Color("e6a75e")},
	5: {"name": "Торговый квартал", "entrance": Vector2(1370, 1025), "color": Color("79c39a")},
	6: {"name": "Общественный центр", "entrance": Vector2(2060, 420), "color": Color("e2c36f")},
	7: {"name": "Районная поликлиника", "entrance": Vector2(2060, 1035), "color": Color("81b6d9")},
	8: {"name": "Двор мастерских", "entrance": Vector2(1410, 1195), "color": Color("cc8d68")},
}
const NPC_DATA := [
	{"id": 2, "position": Vector2(745, 615), "zone": Rect2(725, 555, 95, 105), "color": Color("db7f8e")},
	{"id": 8, "position": Vector2(560, 500), "zone": Rect2(545, 455, 125, 225), "color": Color("e5ad62")},
	{"id": 5, "position": Vector2(1030, 560), "zone": Rect2(930, 450, 200, 220), "color": Color("6ebbc5")},
	{"id": 3, "position": Vector2(1080, 720), "zone": Rect2(930, 695, 195, 100), "color": Color("7fa7e8")},
	{"id": 13, "position": Vector2(1250, 630), "zone": Rect2(1170, 445, 235, 300), "color": Color("bf8cce")},
	{"id": 4, "position": Vector2(1430, 720), "zone": Rect2(1320, 690, 220, 95), "color": Color("d96f78")},
	{"id": 16, "position": Vector2(1045, 420), "zone": Rect2(925, 405, 185, 90), "color": Color("8ea0ac")},
	{"id": 20, "position": Vector2(620, 760), "zone": Rect2(560, 690, 300, 105), "color": Color("6ec18c")},
	{"id": 7, "position": Vector2(900, 320), "zone": Rect2(700, 220, 350, 180), "color": Color("d19466")},
	{"id": 6, "position": Vector2(1510, 470), "zone": Rect2(1410, 420, 210, 115), "color": Color("879aa8")},
	{"id": 9, "position": Vector2(560, 420), "zone": Rect2(450, 405, 190, 115), "color": Color("d5a36d")},
	{"id": 10, "position": Vector2(700, 735), "zone": Rect2(560, 695, 285, 90), "color": Color("77b58e")},
	{"id": 11, "position": Vector2(970, 740), "zone": Rect2(900, 695, 215, 90), "color": Color("aa91d2")},
	{"id": 12, "position": Vector2(1030, 500), "zone": Rect2(930, 450, 185, 190), "color": Color("6e9ed8")},
	{"id": 14, "position": Vector2(315, 560), "zone": Rect2(110, 495, 370, 205), "color": Color("d08c6e")},
	{"id": 15, "position": Vector2(850, 520), "zone": Rect2(660, 485, 375, 155), "color": Color("d7bd75")},
	{"id": 17, "position": Vector2(430, 675), "zone": Rect2(110, 495, 370, 205), "color": Color("d989ac")},
	{"id": 18, "position": Vector2(610, 610), "zone": Rect2(545, 455, 120, 220), "color": Color("829bb2")},
	{"id": 19, "position": Vector2(1210, 520), "zone": Rect2(1160, 450, 220, 275), "color": Color("9b86bc")},
	{"id": 21, "position": Vector2(520, 700), "zone": Rect2(490, 610, 175, 170), "color": Color("c59563")},
]

var world: RefCounted
var player: CharacterBody2D
var groq_client: Node
var _nearby_npc: CharacterBody2D
var _nearby_light_citizen: Dictionary = {}
var _dialogue_npc: CharacterBody2D
var _npc_by_id: Dictionary = {}
var _simulation_accumulator := 0.0
var _pending_act: Dictionary = {}
var _pending_fallback := ""
var _pending_player_line := ""
var _near_aurora_entrance := false
var _nearby_place: Dictionary = {}
var _near_interior_exit := false
var _current_interior: Dictionary = {}
var _outdoor_return_position := Vector2.ZERO
var _renderer_debug: Dictionary = {}
var _last_adaptive_focus_tick: int = -1
var _ambient_crowd: Node2D
var _world_map: Node2D
var _interior_map: Node2D

var _prompt_panel: PanelContainer
var _prompt_label: Label
var _clock_label: Label
var _objective_label: Label
var _dialogue_panel: PanelContainer
var _speaker_label: Label
var _role_label: Label
var _conversation_label: Label
var _action_row: HBoxContainer
var _status_label: Label
var _activity_card: PanelContainer
var _plan_panel: PanelContainer
var _plan_title_label: Label
var _plan_details_label: Label
var _plan_progress: ProgressBar
var _conflict_confirm_overlay: PanelContainer
var _conflict_confirm_label: Label
var _pending_conflict_action: Dictionary = {}
var _social_map_overlay: PanelContainer
var _social_map_control: Control
var _debug_overlay: PanelContainer
var _debug_text: RichTextLabel
var _pulse_overall_label: Label
var _pulse_signals_label: Label
var _news_feed_label: RichTextLabel
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_remaining: float = 0.0
var _save_menu_overlay: PanelContainer
var _save_slot_labels: Dictionary = {}
var _save_status_label: Label
var _save_slot_save_buttons: Dictionary = {}
var _start_menu_overlay: PanelContainer
var _journal_overlay: PanelContainer
var _journal_text: RichTextLabel
var _minimap: Control
var _time_scale := 1.0
var _time_paused := false
var _save_menu_from_start := false
var _game_started := false
var _last_autosave_tick := -9999
var _start_status_label: Label
var _camera_zoom_target := 1.05
var _camera_zoom_min := CAMERA_ZOOM_MIN_ABSOLUTE
var _camera_bounds := Rect2(Vector2.ZERO, WorldMapScript.WORLD_SIZE)


func _ready() -> void:
	world = SimulationWorldScript.new(20250308)
	_build_map()
	_build_player()
	_build_npcs()
	_build_hud()
	groq_client = GroqClientScript.new()
	groq_client.response_received.connect(_on_groq_response)
	groq_client.request_failed.connect(_on_groq_failure)
	add_child(groq_client)
	_update_hud()
	_update_adaptive_focus(true)
	_show_start_menu()


func _process(delta: float) -> void:
	_update_toast(delta)
	_update_minimap()
	_update_camera_zoom(delta)
	if _gameplay_paused():
		return
	_simulation_accumulator += delta * _time_scale
	if _simulation_accumulator >= 1.0:
		var elapsed_ticks := int(_simulation_accumulator)
		_simulation_accumulator -= float(elapsed_ticks)
		world.advance(elapsed_ticks, false)
		_update_adaptive_focus(false)
		_update_hud()
	if not _dialogue_panel.visible:
		_update_nearby_npc()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	]:
		if _can_adjust_camera_zoom():
			var factor := CAMERA_ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / CAMERA_ZOOM_STEP
			_set_camera_zoom_target(_camera_zoom_target * factor)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _start_menu_overlay != null and _start_menu_overlay.visible:
			get_viewport().set_input_as_handled()
			return
		if _save_menu_overlay != null and _save_menu_overlay.visible:
			if event.keycode == KEY_ESCAPE:
				_toggle_save_menu()
			get_viewport().set_input_as_handled()
			return
		if _conflict_confirm_overlay != null and _conflict_confirm_overlay.visible:
			if event.keycode == KEY_ESCAPE:
				_cancel_conflict_action()
			get_viewport().set_input_as_handled()
			return
		if _journal_overlay != null and _journal_overlay.visible:
			if event.keycode in [KEY_ESCAPE, KEY_J]:
				_toggle_journal()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			_save_to_slot(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			_load_from_slot(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_J:
			_toggle_journal()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_set_time_paused(not _time_paused)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_1, KEY_2, KEY_3]:
			_set_time_scale({KEY_1: 1.0, KEY_2: 4.0, KEY_3: 12.0}[event.keycode])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T and not (
			_dialogue_panel.visible or _social_map_overlay.visible or _debug_overlay.visible
		):
			world.advance(12, false) # One visible hour; useful for observing daily routines.
			_update_adaptive_focus(true)
			_update_hud()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			_toggle_social_map()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			_toggle_debug_inspector()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and not _social_map_overlay.visible and not _debug_overlay.visible:
			if _dialogue_panel.visible:
				_close_dialogue()
			elif _nearby_npc != null:
				_open_dialogue(_nearby_npc)
			elif not _nearby_light_citizen.is_empty():
				_activate_nearby_light_citizen()
			elif _near_aurora_entrance:
				_open_aurora_entrance()
			elif not _nearby_place.is_empty():
				_enter_place(int(_nearby_place.id))
			elif _near_interior_exit:
				_exit_place()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _social_map_overlay.visible:
				_toggle_social_map()
			elif _debug_overlay.visible:
				_toggle_debug_inspector()
			elif _dialogue_panel.visible:
				_close_dialogue()
			else:
				_toggle_save_menu()
			get_viewport().set_input_as_handled()


func _build_map() -> void:
	_world_map = WorldMapScript.new()
	_world_map.name = "WorldMap"
	add_child(_world_map)
	_interior_map = PlaceInteriorScript.new()
	_interior_map.name = "PlaceInterior"
	_interior_map.position = INTERIOR_ORIGIN
	_interior_map.visible = false
	add_child(_interior_map)
	_ambient_crowd = AmbientCrowdLayerScript.new()
	_ambient_crowd.name = "AmbientCrowd"
	_ambient_crowd.setup(world)
	add_child(_ambient_crowd)


func _build_player() -> void:
	player = PlayerControllerScript.new()
	player.name = "Player"
	player.position = Vector2(790, 585)
	add_child(player)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.5
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WorldMapScript.WORLD_SIZE.x)
	camera.limit_bottom = int(WorldMapScript.WORLD_SIZE.y)
	camera.zoom = Vector2(1.05, 1.05)
	player.add_child(camera)


func _update_adaptive_focus(force: bool) -> void:
	var current_tick := int(world.tick)
	if not force and (
		current_tick == _last_adaptive_focus_tick or current_tick % 12 != 0
	):
		return
	_last_adaptive_focus_tick = current_tick
	world.update_adaptive_focus(_player_place_id(), [], 60, false)
	if _ambient_crowd != null:
		_ambient_crowd.sync_from_simulation()
	_sync_active_adaptive_npcs()


func _player_place_id() -> int:
	if not _current_interior.is_empty():
		return int(_current_interior.id)
	var position_in_world := player.global_position
	if position_in_world.x >= 1780.0 and position_in_world.y < 780.0:
		return 6 # Community center and east square
	if position_in_world.x >= 1780.0 and position_in_world.y >= 780.0:
		return 7 # Clinic quarter
	if position_in_world.y >= 1140.0 and position_in_world.x >= 1080.0:
		return 8 # Workshop yard
	if position_in_world.y >= 1000.0 and position_in_world.x >= 1080.0:
		return 5 # Shopping and workshop quarter
	if position_in_world.x <= 540.0 and position_in_world.y >= 430.0 and position_in_world.y < 760.0:
		return 4 # Park
	if position_in_world.y >= 760.0:
		return 3 # Residential blocks
	if position_in_world.x >= 1070.0 and position_in_world.x < 1780.0:
		return 1 # Aurora side of the district
	return 2 # Cafe, park and public square


func _enter_place(place_id: int) -> void:
	if not INTERACTIVE_PLACES.has(place_id) or not _current_interior.is_empty():
		return
	var definition: Dictionary = INTERACTIVE_PLACES[place_id]
	_outdoor_return_position = player.global_position
	_current_interior = definition.duplicate(true)
	_current_interior["id"] = place_id
	world.visit_public_place(world.player_id, place_id)
	_world_map.visible = false
	_interior_map.configure(place_id, str(definition.name), definition.color)
	_interior_map.visible = true
	_set_story_npcs_active(false)
	_dematerialize_all_adaptive_npcs()
	_ambient_crowd.enter_interior(place_id, _interior_map.get_activity_zone())
	player.global_position = _interior_map.get_entry_position()
	_set_camera_limits(_interior_map.get_camera_limits(), Vector2(0.92, 0.92))
	_update_adaptive_focus(true)
	_update_hud()
	_update_nearby_npc()
	_toast_label.text = "Вы вошли: %s · посетители зависят от расписания" % str(definition.name)
	_toast_remaining = 3.0
	_toast_panel.visible = true
	_autosave("вход в %s" % str(definition.name))


func _exit_place() -> void:
	if _current_interior.is_empty():
		return
	_dematerialize_all_adaptive_npcs()
	_ambient_crowd.exit_interior()
	_interior_map.visible = false
	_world_map.visible = true
	_current_interior = {}
	player.global_position = _outdoor_return_position
	world.visit_public_place(world.player_id, _player_place_id())
	_set_camera_limits(Rect2(Vector2.ZERO, WorldMapScript.WORLD_SIZE), Vector2(1.05, 1.05))
	_set_story_npcs_active(true)
	_update_adaptive_focus(true)
	_update_hud()
	_update_nearby_npc()
	_autosave("возвращение на улицу")


func _set_camera_limits(bounds: Rect2, zoom: Vector2) -> void:
	var camera := player.get_node("Camera2D") as Camera2D
	_camera_bounds = bounds
	var viewport_size := get_viewport().get_visible_rect().size
	_camera_zoom_min = clampf(maxf(
		CAMERA_ZOOM_MIN_ABSOLUTE,
		maxf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y)
	), CAMERA_ZOOM_MIN_ABSOLUTE, CAMERA_ZOOM_MAX)
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)
	_set_camera_zoom_target(zoom.x, true)
	camera.reset_smoothing()


func _can_adjust_camera_zoom() -> bool:
	return (
		_game_started
		and not _dialogue_panel.visible
		and not _social_map_overlay.visible
		and not _debug_overlay.visible
		and not (_start_menu_overlay != null and _start_menu_overlay.visible)
		and not (_save_menu_overlay != null and _save_menu_overlay.visible)
		and not (_journal_overlay != null and _journal_overlay.visible)
		and not (_conflict_confirm_overlay != null and _conflict_confirm_overlay.visible)
	)


func _set_camera_zoom_target(value: float, immediate: bool = false) -> void:
	_camera_zoom_target = clampf(value, _camera_zoom_min, CAMERA_ZOOM_MAX)
	if immediate and player != null:
		var camera := player.get_node("Camera2D") as Camera2D
		camera.zoom = Vector2.ONE * _camera_zoom_target


func _update_camera_zoom(delta: float) -> void:
	if player == null:
		return
	var camera := player.get_node("Camera2D") as Camera2D
	var weight := 1.0 - exp(-CAMERA_ZOOM_SMOOTH_SPEED * maxf(0.0, delta))
	var value := lerpf(camera.zoom.x, _camera_zoom_target, weight)
	camera.zoom = Vector2.ONE * value


func _set_story_npcs_active(active: bool) -> void:
	for person_id: int in _npc_by_id:
		if person_id >= 10_000:
			continue
		var npc: CharacterBody2D = _npc_by_id[person_id]
		npc.visible = active
		npc.set_physics_process(active)


func _sync_active_adaptive_npcs() -> void:
	if world == null or _ambient_crowd == null:
		return
	var player_place := _player_place_id()
	for person_id: int in world.get_activated_adaptive_person_ids():
		var schedule: Dictionary = world.get_person_activity_view(person_id)
		var should_be_active := (
			not schedule.is_empty() and int(schedule.place_id) == player_place
		)
		var existing: CharacterBody2D = _npc_by_id.get(person_id)
		if existing != null and not is_instance_valid(existing):
			_npc_by_id.erase(person_id)
			existing = null
		if not should_be_active:
			if existing != null and existing != _dialogue_npc:
				existing.queue_free()
				_npc_by_id.erase(person_id)
			continue
		var zone: Rect2 = _ambient_crowd.get_place_zone(player_place)
		if existing != null:
			existing.visible = true
			existing.set_physics_process(true)
			existing.set_movement_zone(zone)
			existing.set_activity_state(schedule)
			continue
		var citizen := {
			"place_id": player_place,
			"position": _ambient_crowd.get_spawn_point(person_id, player_place),
			"accent": _adaptive_person_color(person_id),
		}
		_spawn_adaptive_npc(person_id, citizen)


func _dematerialize_all_adaptive_npcs() -> void:
	for person_id: int in _npc_by_id.keys():
		if person_id < 10_000:
			continue
		var npc: CharacterBody2D = _npc_by_id[person_id]
		if is_instance_valid(npc):
			npc.queue_free()
		_npc_by_id.erase(person_id)
	_dialogue_npc = null


func _adaptive_person_color(person_id: int) -> Color:
	var view: Dictionary = world.get_light_agent_view(person_id)
	match int(view.get("workplace_organization_id", 0)):
		1: return Color("66aeb8")
		2: return Color("c59563")
		_: return Color("8796a0")


func get_active_adaptive_npc_count() -> int:
	var count := 0
	for person_id: int in _npc_by_id:
		if person_id >= 10_000 and is_instance_valid(_npc_by_id[person_id]):
			count += 1
	return count


func _build_npcs() -> void:
	for data: Dictionary in NPC_DATA:
		var npc := NpcControllerScript.new()
		var person_id: int = data.id
		var identity: Dictionary = world.get_visible_identity(world.player_id, person_id)
		npc.setup(person_id, identity.name, data.zone, data.color, world.get_person_role(person_id))
		npc.name = "NPC_%d" % person_id
		npc.position = data.position
		add_child(npc)
		_npc_by_id[person_id] = npc


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var header := PanelContainer.new()
	header.position = Vector2(22, 20)
	header.size = Vector2(460, 130)
	header.add_theme_stylebox_override("panel", _panel_style(Color("162128e8"), Color("47616a"), 12))
	canvas.add_child(header)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	header.add_child(header_box)
	var game_title := Label.new()
	game_title.text = "AURORA DISTRICT"
	game_title.add_theme_font_size_override("font_size", 20)
	game_title.add_theme_color_override("font_color", Color("8ed9de"))
	header_box.add_child(game_title)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.add_theme_color_override("font_color", Color("d6ddd8"))
	header_box.add_child(_objective_label)

	var clock_panel := PanelContainer.new()
	clock_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock_panel.position = Vector2(-225, 20)
	clock_panel.size = Vector2(203, 64)
	clock_panel.add_theme_stylebox_override("panel", _panel_style(Color("162128e8"), Color("47616a"), 12))
	canvas.add_child(clock_panel)
	_clock_label = Label.new()
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 17)
	_clock_label.add_theme_color_override("font_color", Color("f0d39b"))
	clock_panel.add_child(_clock_label)

	var controls := Label.new()
	controls.text = "WASD · E действие · колесо масштаб · J журнал · Space пауза · 1/2/3 скорость"
	controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls.position = Vector2(-455, 94)
	controls.size = Vector2(430, 30)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color("c5cec9"))
	canvas.add_child(controls)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.position = Vector2(-220, -92)
	_prompt_panel.size = Vector2(440, 52)
	_prompt_panel.add_theme_stylebox_override("panel", _panel_style(Color("102027ee"), Color("78cbd3"), 14))
	_prompt_panel.visible = false
	canvas.add_child(_prompt_panel)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 17)
	_prompt_label.add_theme_color_override("font_color", Color("eff7ef"))
	_prompt_panel.add_child(_prompt_label)

	_build_dialogue_panel(canvas)
	_build_district_pulse(canvas)
	_build_plan_panel(canvas)
	_build_news_feed(canvas)
	_build_toast(canvas)
	_build_conflict_confirmation(canvas)
	_build_save_menu(canvas)
	_build_social_map(canvas)
	_build_debug_inspector(canvas)
	_build_minimap(canvas)
	_build_journal(canvas)
	_build_start_menu(canvas)


func _build_district_pulse(canvas: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "DistrictPulse"
	panel.position = Vector2(22, 162)
	panel.size = Vector2(460, 142)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("162128e8"), Color("526f75"), 12))
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var title := Label.new()
	title.text = "ПУЛЬС РАЙОНА"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color("83cbd2"))
	box.add_child(title)
	_pulse_overall_label = Label.new()
	_pulse_overall_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_pulse_overall_label)
	_pulse_signals_label = Label.new()
	_pulse_signals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pulse_signals_label.add_theme_font_size_override("font_size", 12)
	_pulse_signals_label.add_theme_color_override("font_color", Color("c7d2cd"))
	box.add_child(_pulse_signals_label)


func _build_plan_panel(canvas: CanvasLayer) -> void:
	_plan_panel = PanelContainer.new()
	_plan_panel.name = "JointPlanPanel"
	_plan_panel.position = Vector2(22, 316)
	_plan_panel.size = Vector2(460, 118)
	_plan_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("172128ed"), Color("927a4e"), 12)
	)
	_plan_panel.visible = false
	canvas.add_child(_plan_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_plan_panel.add_child(box)
	var caption := Label.new()
	caption.text = "СОВМЕСТНЫЙ ПЛАН"
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", Color("efc979"))
	box.add_child(caption)
	_plan_title_label = Label.new()
	_plan_title_label.add_theme_font_size_override("font_size", 16)
	_plan_title_label.add_theme_color_override("font_color", Color("f0eee5"))
	box.add_child(_plan_title_label)
	_plan_details_label = Label.new()
	_plan_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_details_label.add_theme_font_size_override("font_size", 11)
	_plan_details_label.add_theme_color_override("font_color", Color("bdc9c5"))
	box.add_child(_plan_details_label)
	_plan_progress = ProgressBar.new()
	_plan_progress.custom_minimum_size = Vector2(0, 7)
	_plan_progress.show_percentage = false
	_plan_progress.add_theme_stylebox_override("background", _panel_style(Color("11191c"), Color("2d3c40"), 4))
	_plan_progress.add_theme_stylebox_override("fill", _panel_style(Color("b9934d"), Color("e0bd73"), 4))
	box.add_child(_plan_progress)


func _build_conflict_confirmation(canvas: CanvasLayer) -> void:
	_conflict_confirm_overlay = PanelContainer.new()
	_conflict_confirm_overlay.name = "ActivityConflictConfirm"
	_conflict_confirm_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_conflict_confirm_overlay.position = Vector2(-280, -105)
	_conflict_confirm_overlay.size = Vector2(560, 210)
	_conflict_confirm_overlay.add_theme_stylebox_override(
		"panel", _panel_style(Color("21181afb"), Color("c56d63"), 15)
	)
	_conflict_confirm_overlay.visible = false
	canvas.add_child(_conflict_confirm_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_conflict_confirm_overlay.add_child(box)
	var title := Label.new()
	title.text = "КОНФЛИКТНОЕ ДЕЙСТВИЕ"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("ef9a8e"))
	box.add_child(title)
	_conflict_confirm_label = Label.new()
	_conflict_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict_confirm_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conflict_confirm_label.add_theme_font_size_override("font_size", 15)
	_conflict_confirm_label.add_theme_color_override("font_color", Color("eee7df"))
	box.add_child(_conflict_confirm_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(actions)
	var cancel := Button.new()
	cancel.text = "Отмена  [Esc]"
	cancel.custom_minimum_size = Vector2(150, 42)
	cancel.pressed.connect(_cancel_conflict_action)
	_style_button(cancel, false)
	actions.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Всё равно помешать"
	confirm.custom_minimum_size = Vector2(190, 42)
	confirm.pressed.connect(_confirm_conflict_action)
	_style_conflict_button(confirm)
	actions.add_child(confirm)


func _build_news_feed(canvas: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "NewsFeed"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-430, 128)
	panel.size = Vector2(408, 238)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("111b20e8"), Color("536b72"), 12))
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "СОБЫТИЯ РАЙОНА"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color("e7be7a"))
	box.add_child(title)
	_news_feed_label = RichTextLabel.new()
	_news_feed_label.bbcode_enabled = true
	_news_feed_label.fit_content = false
	_news_feed_label.scroll_active = false
	_news_feed_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_news_feed_label.add_theme_font_size_override("normal_font_size", 11)
	_news_feed_label.add_theme_color_override("default_color", Color("cbd4cf"))
	box.add_child(_news_feed_label)


func _build_toast(canvas: CanvasLayer) -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ConsequenceToast"
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.position = Vector2(-260, 28)
	_toast_panel.size = Vector2(520, 62)
	_toast_panel.add_theme_stylebox_override("panel", _panel_style(Color("173138f5"), Color("85d4d7"), 12))
	_toast_panel.visible = false
	canvas.add_child(_toast_panel)
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast_label.add_theme_color_override("font_color", Color("eef7ed"))
	_toast_panel.add_child(_toast_label)


func _build_minimap(canvas: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "DistrictMinimapPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-310, -220)
	panel.size = Vector2(288, 192)
	panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("10191fe8"), Color("55737a"), 12)
	)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "MinimapContent"
	panel.add_child(box)
	var title := Label.new()
	title.text = "КАРТА РАЙОНА"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("82cbd1"))
	box.add_child(title)
	_minimap = DistrictMinimapScript.new()
	_minimap.name = "DistrictMinimap"
	_minimap.custom_minimum_size = Vector2(260, 145)
	_minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_minimap)


func _build_journal(canvas: CanvasLayer) -> void:
	_journal_overlay = PanelContainer.new()
	_journal_overlay.name = "SocialJournal"
	_journal_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_journal_overlay.position = Vector2(-520, -320)
	_journal_overlay.size = Vector2(1040, 640)
	_journal_overlay.add_theme_stylebox_override(
		"panel", _panel_style(Color("0d171cfa"), Color("d0a85e"), 16)
	)
	_journal_overlay.visible = false
	canvas.add_child(_journal_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	_journal_overlay.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "СОЦИАЛЬНЫЙ ЖУРНАЛ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("efcd88"))
	top.add_child(title)
	var close := Button.new()
	close.text = "Закрыть  [J]"
	close.pressed.connect(_toggle_journal)
	_style_button(close, false)
	top.add_child(close)
	_journal_text = RichTextLabel.new()
	_journal_text.bbcode_enabled = true
	_journal_text.scroll_active = true
	_journal_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_text.add_theme_font_size_override("normal_font_size", 15)
	_journal_text.add_theme_color_override("default_color", Color("d8e0dc"))
	box.add_child(_journal_text)


func _build_start_menu(canvas: CanvasLayer) -> void:
	_start_menu_overlay = PanelContainer.new()
	_start_menu_overlay.name = "StartMenu"
	_start_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_menu_overlay.add_theme_stylebox_override(
		"panel", _panel_style(Color("081116fd"), Color("42666e"), 0)
	)
	canvas.add_child(_start_menu_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_menu_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(620, 560)
	card.add_theme_stylebox_override(
		"panel", _panel_style(Color("142229"), Color("79cbd2"), 18)
	)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 15)
	card.add_child(box)
	var title := Label.new()
	title.text = "AURORA DISTRICT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("91dce1"))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Социальный immersive sim · живой район"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("d0d9d4"))
	box.add_child(subtitle)
	var continue_button := Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "ПРОДОЛЖИТЬ"
	continue_button.custom_minimum_size = Vector2(0, 58)
	continue_button.disabled = not SaveGameServiceScript.has_any_save()
	continue_button.pressed.connect(_continue_latest_game)
	_style_button(continue_button, true)
	box.add_child(continue_button)
	for definition: Dictionary in [
		{"text": "НОВАЯ ИГРА", "callback": _start_new_game},
		{"text": "ЗАГРУЗИТЬ", "callback": _open_load_menu_from_start},
		{"text": "ВЫХОД", "callback": _quit_game},
	]:
		var button := Button.new()
		button.text = str(definition.text)
		button.custom_minimum_size = Vector2(0, 54)
		button.pressed.connect(definition.callback)
		_style_button(button, false)
		box.add_child(button)
	var note := Label.new()
	note.text = "Мир работает детерминированно; реплики Groq не управляют решениями NPC."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("809ba0"))
	box.add_child(note)
	_start_status_label = Label.new()
	_start_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_status_label.add_theme_font_size_override("font_size", 13)
	_start_status_label.add_theme_color_override("font_color", Color("d99a7e"))
	box.add_child(_start_status_label)


func _build_save_menu(canvas: CanvasLayer) -> void:
	_save_menu_overlay = PanelContainer.new()
	_save_menu_overlay.name = "SaveLoadMenu"
	_save_menu_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_save_menu_overlay.position = Vector2(-390, -270)
	_save_menu_overlay.size = Vector2(780, 540)
	_save_menu_overlay.add_theme_stylebox_override(
		"panel", _panel_style(Color("0d171cf8"), Color("78cbd3"), 16)
	)
	_save_menu_overlay.visible = false
	canvas.add_child(_save_menu_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_save_menu_overlay.add_child(box)
	var title := Label.new()
	title.text = "СОХРАНЕНИЕ И ЗАГРУЗКА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("8ed9de"))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Сохраняется весь мир: люди, отношения, деньги, история и текущее место"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("c7d2cd"))
	box.add_child(hint)
	for slot in range(1, SaveGameServiceScript.SLOT_COUNT + 1):
		var row_panel := PanelContainer.new()
		row_panel.custom_minimum_size = Vector2(0, 92)
		row_panel.add_theme_stylebox_override(
			"panel", _panel_style(Color("1b292f"), Color("475e66"), 10)
		)
		box.add_child(row_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_panel.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color("e9eee9"))
		row.add_child(label)
		_save_slot_labels[slot] = label
		var save_button := Button.new()
		save_button.text = "Сохранить"
		save_button.custom_minimum_size = Vector2(130, 46)
		save_button.pressed.connect(_save_to_slot.bind(slot))
		_style_button(save_button, true)
		row.add_child(save_button)
		_save_slot_save_buttons[slot] = save_button
		var load_button := Button.new()
		load_button.text = "Загрузить"
		load_button.custom_minimum_size = Vector2(130, 46)
		load_button.pressed.connect(_load_from_slot.bind(slot))
		_style_button(load_button, false)
		row.add_child(load_button)
	_save_status_label = Label.new()
	_save_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_status_label.add_theme_font_size_override("font_size", 14)
	_save_status_label.add_theme_color_override("font_color", Color("e6c478"))
	box.add_child(_save_status_label)
	var close_button := Button.new()
	close_button.text = "Вернуться в игру  [Esc]"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(_toggle_save_menu)
	_style_button(close_button, false)
	box.add_child(close_button)
	var menu_row := HBoxContainer.new()
	menu_row.add_theme_constant_override("separation", 10)
	box.add_child(menu_row)
	var main_menu_button := Button.new()
	main_menu_button.text = "Главное меню"
	main_menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_menu_button.pressed.connect(_return_to_start_menu)
	_style_button(main_menu_button, false)
	menu_row.add_child(main_menu_button)
	var exit_button := Button.new()
	exit_button.text = "Выйти из игры"
	exit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_button.pressed.connect(_quit_game)
	_style_button(exit_button, false)
	menu_row.add_child(exit_button)
	_refresh_save_slots()


func _build_social_map(canvas: CanvasLayer) -> void:
	_social_map_overlay = PanelContainer.new()
	_social_map_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_social_map_overlay.position = Vector2(-510, -290)
	_social_map_overlay.size = Vector2(1020, 580)
	_social_map_overlay.add_theme_stylebox_override("panel", _panel_style(Color("10191ff8"), Color("78cbd3"), 14))
	_social_map_overlay.visible = false
	canvas.add_child(_social_map_overlay)
	var box := VBoxContainer.new()
	_social_map_overlay.add_child(box)
	var title := Label.new()
	title.text = "СОЦИАЛЬНАЯ КАРТА  ·  только известные вам связи  ·  M / Esc — закрыть"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("8ed9de"))
	box.add_child(title)
	_social_map_control = SocialMapPanelScript.new()
	_social_map_control.custom_minimum_size = Vector2(980, 515)
	_social_map_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_social_map_control)


func _build_debug_inspector(canvas: CanvasLayer) -> void:
	_debug_overlay = PanelContainer.new()
	_debug_overlay.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_debug_overlay.position = Vector2(-570, -320)
	_debug_overlay.size = Vector2(550, 640)
	_debug_overlay.add_theme_stylebox_override("panel", _panel_style(Color("0d1519fa"), Color("b985c9"), 12))
	_debug_overlay.visible = false
	canvas.add_child(_debug_overlay)
	_debug_text = RichTextLabel.new()
	_debug_text.bbcode_enabled = true
	_debug_text.fit_content = false
	_debug_text.scroll_active = true
	_debug_text.add_theme_font_size_override("normal_font_size", 12)
	_debug_overlay.add_child(_debug_text)


func _toggle_social_map() -> void:
	_social_map_overlay.visible = not _social_map_overlay.visible
	if _social_map_overlay.visible:
		_debug_overlay.visible = false
		_social_map_control.set_graph(world.get_social_map_view(world.player_id))
	_sync_player_input()


func _toggle_debug_inspector() -> void:
	_debug_overlay.visible = not _debug_overlay.visible
	if _debug_overlay.visible:
		_social_map_overlay.visible = false
		_refresh_debug_inspector()
	_sync_player_input()


func _show_start_menu() -> void:
	_game_started = false
	_start_menu_overlay.visible = true
	_start_status_label.text = ""
	_save_menu_overlay.visible = false
	_journal_overlay.visible = false
	var continue_button := _start_menu_overlay.find_child("ContinueButton", true, false) as Button
	if continue_button != null:
		continue_button.disabled = not SaveGameServiceScript.has_any_save()
	_apply_motion_pause()
	_sync_player_input()


func _start_new_game() -> void:
	_save_menu_from_start = false
	var fresh_world := SimulationWorldScript.new(20250308)
	_restore_loaded_game(fresh_world, {
		"player": {"x": 790.0, "y": 585.0},
		"outdoor_return": {"x": 790.0, "y": 585.0},
		"interior_place_id": -1,
		"story_npc_positions": [],
		"simulation_accumulator": 0.0,
		"time_scale": 1.0,
		"time_paused": false,
	})
	_game_started = true
	_start_menu_overlay.visible = false
	_set_time_paused(false)
	_show_save_status("Новая история началась", true)


func _continue_latest_game() -> void:
	var latest: Dictionary = SaveGameServiceScript.get_latest_save()
	if latest.is_empty():
		return
	if _restore_save_envelope(latest):
		_game_started = true
		_save_menu_from_start = false
		_start_menu_overlay.visible = false
		_apply_motion_pause()
		_sync_player_input()
		_show_save_status("Продолжено последнее сохранение", true)
	else:
		_start_status_label.text = "Последнее сохранение повреждено или создано несовместимой версией."


func _open_load_menu_from_start() -> void:
	_save_menu_from_start = true
	_start_menu_overlay.visible = false
	_save_menu_overlay.visible = true
	for button: Button in _save_slot_save_buttons.values():
		button.disabled = true
	_refresh_save_slots()
	_save_status_label.text = "Выберите слот для загрузки"
	_sync_player_input()


func _return_to_start_menu() -> void:
	_save_menu_from_start = false
	_show_start_menu()


func _quit_game() -> void:
	get_tree().quit()


func _toggle_journal() -> void:
	_journal_overlay.visible = not _journal_overlay.visible
	if _journal_overlay.visible:
		_social_map_overlay.visible = false
		_debug_overlay.visible = false
		_refresh_journal()
	_apply_motion_pause()
	_sync_player_input()


func _set_time_paused(paused: bool) -> void:
	_time_paused = paused
	_apply_motion_pause()
	_sync_player_input()
	_update_hud()


func _set_time_scale(value: float) -> void:
	_time_scale = clampf(value, 1.0, 12.0)
	_time_paused = false
	_apply_motion_pause()
	_sync_player_input()
	_update_hud()


func _gameplay_paused() -> bool:
	return (
		not _game_started or _time_paused
		or (_start_menu_overlay != null and _start_menu_overlay.visible)
		or (_save_menu_overlay != null and _save_menu_overlay.visible)
		or (_journal_overlay != null and _journal_overlay.visible)
		or (_conflict_confirm_overlay != null and _conflict_confirm_overlay.visible)
	)


func _apply_motion_pause() -> void:
	var paused := _gameplay_paused()
	if _ambient_crowd != null:
		_ambient_crowd.motion_paused = paused
	for person_id: int in _npc_by_id:
		var npc: CharacterBody2D = _npc_by_id[person_id]
		if is_instance_valid(npc):
			npc.movement_paused = paused or npc == _dialogue_npc


func _toggle_save_menu() -> void:
	if _save_menu_overlay.visible and _save_menu_from_start:
		_save_menu_overlay.visible = false
		_start_menu_overlay.visible = true
	else:
		_save_menu_overlay.visible = not _save_menu_overlay.visible
	if _save_menu_overlay.visible:
		_refresh_save_slots()
		_save_status_label.text = "F5/F9 используют слот 1"
		for button: Button in _save_slot_save_buttons.values():
			button.disabled = _save_menu_from_start
	elif not _save_menu_from_start:
		_save_menu_from_start = false
	_apply_motion_pause()
	_sync_player_input()


func _save_to_slot(slot: int) -> void:
	var result: Dictionary = SaveGameServiceScript.save_slot(
		slot, world.export_save_data(), _capture_view_state()
	)
	if bool(result.get("ok", false)):
		_show_save_status("Слот %d сохранён" % slot, true)
		_refresh_save_slots()
	else:
		_show_save_status("Не удалось сохранить: %s" % str(result.get("error", "ERROR")), false)


func _load_from_slot(slot: int) -> void:
	if groq_client != null and groq_client.is_busy():
		_show_save_status("Дождитесь ответа персонажа перед загрузкой", false)
		return
	var loaded: Dictionary = SaveGameServiceScript.load_slot(slot)
	if not bool(loaded.get("ok", false)):
		_show_save_status("Слот %d пуст или повреждён" % slot, false)
		return
	if not _restore_save_envelope(loaded):
		_show_save_status("Контрольная сумма слота %d не совпала" % slot, false)
		return
	_game_started = true
	_start_menu_overlay.visible = false
	_save_menu_from_start = false
	_apply_motion_pause()
	_sync_player_input()
	_show_save_status("Слот %d загружен" % slot, true)


func _restore_save_envelope(loaded: Dictionary) -> bool:
	var restored: RefCounted = SimulationWorldScript.create_from_save_data(loaded.world)
	if restored == null:
		return false
	_restore_loaded_game(restored, loaded.view)
	return true


func _autosave(reason: String) -> void:
	if not _game_started:
		return
	var result := SaveGameServiceScript.save_slot(
		SaveGameServiceScript.AUTO_SAVE_SLOT, world.export_save_data(), _capture_view_state()
	)
	if bool(result.get("ok", false)):
		_last_autosave_tick = int(world.tick)
		_show_save_status("Автосохранение · %s" % reason, true)


func _capture_view_state() -> Dictionary:
	var story_positions: Array[Dictionary] = []
	for person_id: int in _npc_by_id:
		if person_id >= 10_000:
			continue
		var npc: CharacterBody2D = _npc_by_id[person_id]
		story_positions.append({
			"person_id": person_id,
			"x": npc.global_position.x,
			"y": npc.global_position.y,
		})
	return {
		"player": {"x": player.global_position.x, "y": player.global_position.y},
		"outdoor_return": {
			"x": _outdoor_return_position.x, "y": _outdoor_return_position.y,
		},
		"interior_place_id": int(_current_interior.get("id", -1)),
		"story_npc_positions": story_positions,
		"simulation_accumulator": _simulation_accumulator,
		"time_scale": _time_scale,
		"time_paused": _time_paused,
		"camera_zoom": _camera_zoom_target,
	}


func _restore_loaded_game(restored: RefCounted, view: Dictionary) -> void:
	_dialogue_panel.visible = false
	_social_map_overlay.visible = false
	_debug_overlay.visible = false
	_pending_act = {}
	_pending_fallback = ""
	_pending_player_line = ""
	_dematerialize_all_adaptive_npcs()
	_ambient_crowd.exit_interior()
	_interior_map.visible = false
	_world_map.visible = true
	_current_interior = {}
	_set_story_npcs_active(true)
	world = restored
	_ambient_crowd.setup(world)
	var player_state: Dictionary = view.get("player", {})
	player.global_position = Vector2(
		float(player_state.get("x", 790.0)), float(player_state.get("y", 585.0))
	)
	var return_state: Dictionary = view.get("outdoor_return", {})
	_outdoor_return_position = Vector2(
		float(return_state.get("x", 790.0)), float(return_state.get("y", 585.0))
	)
	for position_state: Dictionary in view.get("story_npc_positions", []):
		var person_id := int(position_state.get("person_id", -1))
		if _npc_by_id.has(person_id):
			_npc_by_id[person_id].global_position = Vector2(
				float(position_state.get("x", 0.0)), float(position_state.get("y", 0.0))
			)
	_simulation_accumulator = float(view.get("simulation_accumulator", 0.0))
	_time_scale = clampf(float(view.get("time_scale", 1.0)), 1.0, 12.0)
	_time_paused = bool(view.get("time_paused", false))
	var interior_place_id := int(view.get("interior_place_id", -1))
	if INTERACTIVE_PLACES.has(interior_place_id):
		var definition: Dictionary = INTERACTIVE_PLACES[interior_place_id]
		_current_interior = definition.duplicate(true)
		_current_interior["id"] = interior_place_id
		_world_map.visible = false
		_interior_map.configure(interior_place_id, str(definition.name), definition.color)
		_interior_map.visible = true
		_set_story_npcs_active(false)
		_ambient_crowd.enter_interior(
			interior_place_id, _interior_map.get_activity_zone()
		)
		_set_camera_limits(_interior_map.get_camera_limits(), Vector2(0.92, 0.92))
	else:
		_set_camera_limits(Rect2(Vector2.ZERO, WorldMapScript.WORLD_SIZE), Vector2(1.05, 1.05))
	if view.has("camera_zoom"):
		_set_camera_zoom_target(float(view.camera_zoom), true)
	_ambient_crowd.sync_from_simulation()
	_sync_active_adaptive_npcs()
	_last_adaptive_focus_tick = int(world.tick)
	_update_npc_labels()
	_update_hud()
	_save_menu_overlay.visible = false
	_journal_overlay.visible = false
	_start_menu_overlay.visible = false
	_apply_motion_pause()
	_sync_player_input()
	_update_nearby_npc()


func _refresh_save_slots() -> void:
	for slot in range(1, SaveGameServiceScript.SLOT_COUNT + 1):
		var metadata: Dictionary = SaveGameServiceScript.get_slot_metadata(slot)
		var label: Label = _save_slot_labels.get(slot)
		if bool(metadata.get("empty", true)):
			label.text = "СЛОТ %d\nПусто" % slot
		else:
			label.text = "СЛОТ %d · тик %d\n%s" % [
				slot, int(metadata.get("tick", 0)), str(metadata.get("saved_at", "")),
			]


func _show_save_status(message: String, success: bool) -> void:
	if _save_status_label != null:
		_save_status_label.text = message
		_save_status_label.add_theme_color_override(
			"font_color", Color("8fd0a2") if success else Color("e28484")
		)
	if _toast_label != null:
		_toast_label.text = message
		_toast_remaining = 3.0
		_toast_panel.visible = true


func _sync_player_input() -> void:
	player.input_enabled = not (
		not _game_started or _time_paused or
		_dialogue_panel.visible or _social_map_overlay.visible or _debug_overlay.visible
		or (_save_menu_overlay != null and _save_menu_overlay.visible)
		or (_start_menu_overlay != null and _start_menu_overlay.visible)
		or (_journal_overlay != null and _journal_overlay.visible)
		or (_conflict_confirm_overlay != null and _conflict_confirm_overlay.visible)
	)
	if not player.input_enabled:
		player.velocity = Vector2.ZERO


func _refresh_debug_inspector() -> void:
	if _debug_text == null or not _debug_overlay.visible:
		return
	var inspected_id := 2
	if _dialogue_npc != null:
		inspected_id = _dialogue_npc.person_id
	elif _nearby_npc != null:
		inspected_id = _nearby_npc.person_id
	var payload := {
		"inspector": world.get_debug_inspector(inspected_id, world.player_id),
		"metrics": world.get_metrics(),
		"renderer": _renderer_debug,
	}
	_debug_text.text = "[b]DEV INSPECTOR · F3 / Esc[/b]\n" + JSON.stringify(payload, "  ", false)


func _build_dialogue_panel(canvas: CanvasLayer) -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_panel.position = Vector2(-475, -430)
	_dialogue_panel.size = Vector2(950, 400)
	_dialogue_panel.add_theme_stylebox_override("panel", _panel_style(Color("10191ff5"), Color("65858d"), 16))
	_dialogue_panel.visible = false
	canvas.add_child(_dialogue_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_dialogue_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var top_row := HBoxContainer.new()
	content.add_child(top_row)
	var identity_box := VBoxContainer.new()
	identity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(identity_box)
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 23)
	_speaker_label.add_theme_color_override("font_color", Color("f1cf8d"))
	identity_box.add_child(_speaker_label)
	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", 13)
	_role_label.add_theme_color_override("font_color", Color("92b7bd"))
	identity_box.add_child(_role_label)
	var close_button := Button.new()
	close_button.text = "Закрыть  [E]"
	close_button.custom_minimum_size = Vector2(120, 38)
	close_button.pressed.connect(_close_dialogue)
	_style_button(close_button, false)
	top_row.add_child(close_button)
	var separator := HSeparator.new()
	content.add_child(separator)
	_activity_card = ActivityStatusCardScript.new()
	content.add_child(_activity_card)
	_conversation_label = Label.new()
	_conversation_label.custom_minimum_size = Vector2(0, 92)
	_conversation_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conversation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conversation_label.add_theme_font_size_override("font_size", 17)
	_conversation_label.add_theme_color_override("font_color", Color("f0eee5"))
	content.add_child(_conversation_label)
	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size = Vector2(0, 56)
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(action_scroll)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 10)
	action_scroll.add_child(_action_row)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color("86a9ae"))
	content.add_child(_status_label)


func _update_nearby_npc() -> void:
	var closest: CharacterBody2D = null
	var closest_distance := INTERACTION_DISTANCE
	for candidate: Node in get_tree().get_nodes_in_group("npc"):
		var npc := candidate as CharacterBody2D
		var distance := player.global_position.distance_to(npc.global_position)
		if distance < closest_distance:
			closest = npc
			closest_distance = distance
	_nearby_light_citizen = {}
	if _ambient_crowd != null:
		var ambient_candidate: Dictionary = _ambient_crowd.get_nearest_citizen(
			player.global_position, closest_distance
		)
		if not ambient_candidate.is_empty():
			_nearby_light_citizen = ambient_candidate
			closest = null
	_nearby_npc = closest
	_near_aurora_entrance = _current_interior.is_empty() and (
		player.global_position.distance_to(Vector2(1385, 425)) < 88.0
	)
	_nearby_place = {}
	_near_interior_exit = false
	if _current_interior.is_empty():
		var nearest_place_distance := INTERACTION_DISTANCE
		for place_id: int in INTERACTIVE_PLACES:
			var place: Dictionary = INTERACTIVE_PLACES[place_id]
			var place_distance := player.global_position.distance_to(place.entrance)
			if place_distance < nearest_place_distance:
				nearest_place_distance = place_distance
				_nearby_place = place.duplicate(true)
				_nearby_place["id"] = place_id
	else:
		_near_interior_exit = player.global_position.distance_to(
			_interior_map.get_exit_position()
		) < INTERACTION_DISTANCE
	_prompt_panel.visible = (
		closest != null or not _nearby_light_citizen.is_empty()
		or _near_aurora_entrance or not _nearby_place.is_empty() or _near_interior_exit
	)
	if closest != null:
		var identity: Dictionary = world.get_visible_identity(world.player_id, closest.person_id)
		_prompt_label.text = "[ E ]  Поговорить  ·  %s" % identity.name
	elif not _nearby_light_citizen.is_empty():
		var activity := str(_nearby_light_citizen.get("activity_label", ""))
		var phase_label := str(_nearby_light_citizen.get("phase_label", ""))
		_prompt_label.text = "[ E ]  Поговорить  ·  Житель района"
		if not activity.is_empty():
			_prompt_label.text += " · %s" % activity
		if not phase_label.is_empty():
			_prompt_label.text += " · %s" % phase_label
	elif _near_aurora_entrance:
		_prompt_label.text = "[ E ]  Войти в Aurora"
	elif not _nearby_place.is_empty():
		_prompt_label.text = "[ E ]  Войти · %s" % str(_nearby_place.name)
	elif _near_interior_exit:
		_prompt_label.text = "[ E ]  Выйти на улицу"


func _activate_nearby_light_citizen() -> void:
	if _nearby_light_citizen.is_empty():
		return
	var citizen := _nearby_light_citizen.duplicate(true)
	var agent_id := int(citizen.agent_id)
	var activation: Dictionary = world.activate_light_agent_as_person(
		agent_id, "PLAYER_INTERACTION"
	)
	if not bool(activation.get("ok", false)):
		_toast_label.text = "Сейчас житель недоступен для разговора"
		_toast_remaining = 2.5
		_toast_panel.visible = true
		return
	var npc := _spawn_adaptive_npc(agent_id, citizen)
	_nearby_light_citizen = {}
	_ambient_crowd.sync_from_simulation()
	_open_dialogue(npc)


func _spawn_adaptive_npc(agent_id: int, citizen: Dictionary) -> CharacterBody2D:
	if _npc_by_id.has(agent_id):
		return _npc_by_id[agent_id]
	var npc := NpcControllerScript.new()
	var identity: Dictionary = world.get_visible_identity(world.player_id, agent_id)
	var zone: Rect2 = _ambient_crowd.get_place_zone(int(citizen.place_id))
	var accent: Color = citizen.get("accent", Color("8796a0"))
	npc.setup(agent_id, str(identity.name), zone, accent, world.get_person_role(agent_id))
	npc.name = "AdaptiveNPC_%d" % agent_id
	npc.position = citizen.position
	add_child(npc)
	var activity_state: Dictionary = world.get_person_activity_view(agent_id)
	if not activity_state.is_empty():
		npc.set_activity_state(activity_state)
	_npc_by_id[agent_id] = npc
	return npc


func _open_dialogue(npc: CharacterBody2D) -> void:
	_dialogue_npc = npc
	_dialogue_npc.movement_paused = true
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	_prompt_panel.visible = false
	_dialogue_panel.visible = true
	var background_history: Array[Dictionary] = []
	if world.is_person_known_to(world.player_id, npc.person_id):
		background_history = world.get_persistent_background_history(
			npc.person_id, world.player_id
		)
	var identity: Dictionary = world.get_visible_identity(world.player_id, npc.person_id)
	_speaker_label.text = identity.name
	_role_label.text = identity.role if identity.known else "Вы ещё не знакомы"
	var activity: Dictionary = world.get_person_activity_view(npc.person_id)
	_activity_card.set_activity(activity)
	if identity.known and not activity.is_empty():
		_role_label.text += " · %s" % str(activity.activity_label)
		_role_label.text += " · %s" % str(activity.get("phase_label", ""))
	_status_label.text = "Решения принимает симуляция · текст: Groq или локальный шаблон"
	_status_label.text += " · %s" % _relationship_signal(npc.person_id)
	_clear_actions()
	if identity.known:
		if background_history.is_empty():
			_conversation_label.text = "%s смотрит на вас и ждёт, что вы скажете." % identity.name
		else:
			var history_lines := PackedStringArray()
			for event: Dictionary in background_history:
				history_lines.append("• %s" % str(event.summary))
			_conversation_label.text = "С прошлой встречи:\n%s\n\n%s ждёт, что вы скажете." % [
				"\n".join(history_lines), identity.name,
			]
			_update_news_feed()
	else:
		_conversation_label.text = "Незнакомец останавливается рядом. Можно представиться и начать знакомство."
	_refresh_dialogue_actions()


func _close_dialogue() -> void:
	if groq_client != null and groq_client.is_busy():
		_status_label.text = "Подождите, персонаж формулирует ответ…"
		return
	if _dialogue_npc != null:
		_dialogue_npc.movement_paused = false
	_dialogue_npc = null
	_dialogue_panel.visible = false
	_pending_conflict_action = {}
	if _conflict_confirm_overlay != null:
		_conflict_confirm_overlay.visible = false
	_pending_act = {}
	_pending_fallback = ""
	_pending_player_line = ""
	_sync_active_adaptive_npcs()
	_apply_motion_pause()
	_sync_player_input()
	_update_nearby_npc()


func _refresh_dialogue_actions() -> void:
	_clear_actions()
	if _dialogue_npc == null:
		return
	var actions: Array[Dictionary] = world.get_available_social_actions(
		world.player_id, _dialogue_npc.person_id
	)
	actions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _action_category_order(str(left.get("type", ""))) < _action_category_order(str(right.get("type", "")))
	)
	var last_category := ""
	for index in range(actions.size()):
		var action: Dictionary = actions[index]
		var category := _action_category(str(action.get("type", "")))
		if category != last_category:
			_add_action_category_label(category)
			last_category = category
		_add_action_button(
			SocialActionPresenterScript.button_label(action),
			_perform_model_action.bind(action),
			index == 0,
			category
		)


func _perform_model_action(action: Dictionary) -> void:
	if _dialogue_npc == null or groq_client.is_busy():
		return
	if str(action.get("type", "")) == "HinderActivity":
		_pending_conflict_action = action.duplicate(true)
		_conflict_confirm_label.text = (
			"Вы намеренно помешаете занятию «%s». Это повысит стресс персонажа, "
			+ "ухудшит отношения и может изменить события района."
		) % str(action.get("context", {}).get("activity_label", "текущее дело"))
		_conflict_confirm_overlay.visible = true
		_apply_motion_pause()
		_sync_player_input()
		return
	_execute_model_action(action)


func _execute_model_action(action: Dictionary) -> void:
	if _dialogue_npc == null or groq_client.is_busy():
		return
	var action_type := str(action.get("type", ""))
	var context: Dictionary = action.get("context", {})
	var result: Dictionary = world.perform_social_action(
		action_type, world.player_id, _dialogue_npc.person_id, context
	)
	if not result.ok:
		_conversation_label.text = "Сейчас это действие недоступно (%s). Сначала узнайте нужную связь." % result.error
		return
	_autosave("важное социальное действие")
	_set_action_buttons_disabled(true)
	_pending_act = result.communicative_act
	_pending_fallback = result.template_response
	_pending_player_line = result.player_line
	var identity := {
		"name": world.get_person_name(_dialogue_npc.person_id),
		"role": world.get_person_role(_dialogue_npc.person_id),
	}
	_conversation_label.text = "%s\n\n%s думает…" % [result.player_line, identity.name]
	_status_label.text = result.feedback
	_show_effect_toast(result.get("effects", []))
	_update_news_feed()
	if groq_client.is_configured():
		var system_prompt := SocialRendererScript.build_system_prompt()
		var render_context: Dictionary = world.get_conversation_context(
			world.player_id, _dialogue_npc.person_id
		)
		render_context["player_line"] = result.player_line
		render_context["location"] = (
			str(_current_interior.name) if not _current_interior.is_empty()
			else "Aurora district"
		)
		var user_prompt := SocialRendererScript.build_user_prompt(
			identity, result.communicative_act, render_context
		)
		_renderer_debug = {
			"decision": result.decision,
			"communicative_act": result.communicative_act,
			"system_prompt": system_prompt,
			"user_prompt": user_prompt,
			"raw_response": "",
			"final_response": "",
		}
		var started: bool = groq_client.generate_text(
			system_prompt,
			user_prompt
		)
		if started:
			return
	_show_dialogue_response(result.template_response, "локальный шаблон")


func _confirm_conflict_action() -> void:
	var action := _pending_conflict_action.duplicate(true)
	_pending_conflict_action = {}
	_conflict_confirm_overlay.visible = false
	_apply_motion_pause()
	_sync_player_input()
	if not action.is_empty():
		_execute_model_action(action)


func _cancel_conflict_action() -> void:
	_pending_conflict_action = {}
	_conflict_confirm_overlay.visible = false
	_apply_motion_pause()
	_sync_player_input()


func _on_groq_response(raw_text: String) -> void:
	var rendered := SocialRendererScript.sanitize_output(raw_text, _pending_act, _pending_fallback)
	var source := "Groq" if rendered != _pending_fallback else "локальный шаблон (ответ Groq отклонён)"
	_renderer_debug["raw_response"] = raw_text
	_renderer_debug["final_response"] = rendered
	_renderer_debug["source"] = source
	_show_dialogue_response(rendered, source)


func _on_groq_failure(message: String) -> void:
	_renderer_debug["failure"] = message
	_renderer_debug["final_response"] = _pending_fallback
	_show_dialogue_response(_pending_fallback, "локальный шаблон · %s" % message)


func _show_dialogue_response(response: String, source: String) -> void:
	if _dialogue_npc == null:
		return
	var name: String = world.get_person_name(_dialogue_npc.person_id)
	_conversation_label.text = "Вы: «%s»\n\n%s: «%s»" % [_pending_player_line, name, response]
	_status_label.text = "Текст ответа: %s" % source
	_status_label.text += " · %s" % _relationship_signal(_dialogue_npc.person_id)
	_pending_act = {}
	_pending_fallback = ""
	_pending_player_line = ""
	_update_npc_labels()
	_speaker_label.text = name
	_role_label.text = world.get_person_role(_dialogue_npc.person_id)
	var activity: Dictionary = world.get_person_activity_view(_dialogue_npc.person_id)
	_activity_card.set_activity(activity)
	if not activity.is_empty():
		_role_label.text += " · %s" % str(activity.activity_label)
		_role_label.text += " · %s" % str(activity.get("phase_label", ""))
	_refresh_dialogue_actions()
	_update_hud()
	_refresh_debug_inspector()




func _update_npc_labels() -> void:
	for person_id: int in _npc_by_id:
		var npc: CharacterBody2D = _npc_by_id[person_id]
		var identity: Dictionary = world.get_visible_identity(world.player_id, person_id)
		npc.set_known_name(identity.name)


func _open_aurora_entrance() -> void:
	var result: Dictionary = world.attempt_enter_aurora(world.player_id)
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	_prompt_panel.visible = false
	_dialogue_panel.visible = true
	_dialogue_npc = null
	_speaker_label.text = "Aurora"
	_role_label.text = "Контроль доступа"
	_activity_card.clear_activity()
	_clear_actions()
	if result.ok:
		_conversation_label.text = "Пропуск подтверждён. Цель достигнута: вы вошли на закрытое мероприятие."
		_status_label.text = "Результат вычислен по факту владения пропуском."
		_autosave("цель Aurora выполнена")
	else:
		_conversation_label.text = "Доступ пока закрыт: модель мира не нашла у вас действующего пропуска."
		_status_label.text = "Требование модели: действующий Aurora access token"


func _clear_actions() -> void:
	for child: Node in _action_row.get_children():
		child.queue_free()


func _add_action_button(
	label_text: String, callback: Callable, primary: bool, category: String = "ОБЩЕНИЕ"
) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(190, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	_style_action_button(button, primary, category)
	_action_row.add_child(button)


func _add_action_category_label(category: String) -> void:
	var label := Label.new()
	label.text = category
	label.custom_minimum_size = Vector2(100, 42)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override(
		"font_color", Color("8fd0a2") if category == "СОВМЕСТНО" else (
			Color("e38d82") if category == "КОНФЛИКТ" else Color("8fbfc7")
		)
	)
	_action_row.add_child(label)


func _set_action_buttons_disabled(disabled: bool) -> void:
	for child: Node in _action_row.get_children():
		if child is Button:
			child.disabled = disabled


func _update_hud() -> void:
	var absolute_clock_ticks := int(world.tick) + 120
	var day := 1 + int(absolute_clock_ticks / 288)
	var minute_of_day := (absolute_clock_ticks % 288) * 5
	var hour := int(minute_of_day / 60)
	var minute := minute_of_day % 60
	var speed_label := "ПАУЗА" if _time_paused else "×%d" % int(_time_scale)
	_clock_label.text = "День %d  ·  %02d:%02d  ·  %s" % [day, hour, minute, speed_label]
	var goal: Dictionary = world.get_goal_state(world.player_id)
	if str(goal.stage) == "COMPLETED":
		goal = world.get_district_project_state(world.player_id)
	_objective_label.text = "%s\n%s" % [goal.title, goal.hint]
	var tasks: Array[Dictionary] = world.get_active_tasks_for(world.player_id)
	if not tasks.is_empty():
		var task: Dictionary = tasks[0]
		_objective_label.text += "\nПоручение: найти %s · %s" % [
			str(task.counterpart_name), str(task.topic),
		]
	var plans: Array[Dictionary] = world.get_activity_plans_view(world.player_id)
	_update_district_pulse()
	_update_plan_panel(plans)
	_update_news_feed()
	_refresh_debug_inspector()
	if _journal_overlay != null and _journal_overlay.visible:
		_refresh_journal()


func _refresh_journal() -> void:
	if _journal_text == null:
		return
	var journal: Dictionary = world.get_player_journal_view(world.player_id)
	var primary: Dictionary = journal.primary_goal
	var project: Dictionary = journal.district_project
	var lines := PackedStringArray([
		"[color=#8ed9de][font_size=20]ГЛАВНЫЕ ЦЕЛИ[/font_size][/color]",
		"[b]%s[/b] · %s" % [str(primary.title), str(primary.hint)],
		"[b]%s[/b] · %d/%d · %s" % [
			str(project.title), int(project.progress), int(project.required), str(project.hint),
		],
	])
	for contribution: Dictionary in project.contributions:
		lines.append("  [color=#8fd0a2]✓ %s[/color] · %s" % [
			str(contribution.label), str(contribution.contributor_name),
		])
	lines.append("\n[color=#efcd88][font_size=18]РЕПУТАЦИЯ И ГРУППЫ[/font_size][/color]")
	lines.append("Репутация в районе: %d%%" % int(float(journal.reputation) * 100.0))
	var affiliations: Array = journal.affiliations
	lines.append("Группы: %s" % (
		", ".join(PackedStringArray(affiliations)) if not affiliations.is_empty() else "пока нет"
	))
	lines.append("\n[color=#efcd88][font_size=18]ПОРУЧЕНИЯ[/font_size][/color]")
	if journal.tasks.is_empty():
		lines.append("Активных обещаний нет.")
	else:
		for task: Dictionary in journal.tasks:
			lines.append("• %s → %s · %s · до тика %d" % [
				str(task.requester_name), str(task.counterpart_name),
				str(task.topic), int(task.deadline_tick),
			])
	lines.append("\n[color=#efcd88][font_size=18]СОВМЕСТНЫЕ ПЛАНЫ[/font_size][/color]")
	if journal.activity_plans.is_empty():
		lines.append("Совместных планов пока нет.")
	else:
		for plan: Dictionary in journal.activity_plans:
			var participant_names := PackedStringArray()
			for participant: Dictionary in plan.participants:
				participant_names.append(str(participant.name))
			lines.append("• %s · %s · тик %d · %s · %s" % [
				str(plan.activity_label), str(plan.place_name), int(plan.start_tick),
				_activity_plan_status_label(str(plan.status)), ", ".join(participant_names),
			])
	lines.append("\n[color=#efcd88][font_size=18]ЗНАКОМЫЕ И ИХ ДЕЛА[/font_size][/color]")
	for contact: Dictionary in journal.contacts:
		lines.append("• [b]%s[/b] · %s · %s · %s" % [
			str(contact.name), str(contact.role), str(contact.relationship), str(contact.activity),
		])
	_journal_text.text = "\n".join(lines)


func _activity_plan_status_label(status: String) -> String:
	return {
		"PLANNED": "запланировано",
		"GATHERING": "участники собираются",
		"ACTIVE": "идёт сейчас",
		"COMPLETED": "выполнено",
		"MISSED": "сорвано",
		"CANCELLED": "отменено",
	}.get(status, status.to_lower())


func _update_plan_panel(plans: Array) -> void:
	if _plan_panel == null:
		return
	var active_plan: Dictionary = {}
	for plan: Dictionary in plans:
		if str(plan.get("status", "")) not in ["COMPLETED", "MISSED", "CANCELLED"]:
			active_plan = plan
			break
	if active_plan.is_empty():
		_plan_panel.visible = false
		return
	_plan_panel.visible = true
	var status := str(active_plan.get("status", "PLANNED"))
	_plan_title_label.text = "%s · %s" % [
		str(active_plan.get("activity_label", "Совместное занятие")),
		_activity_plan_status_label(status),
	]
	var participant_marks := PackedStringArray()
	for participant: Dictionary in active_plan.get("participants", []):
		participant_marks.append("✓ %s" % str(participant.name) if bool(participant.arrived) else "○ %s" % str(participant.name))
	var start_tick := int(active_plan.get("start_tick", int(world.tick)))
	var timing := (
		"начало через %d т." % (start_tick - int(world.tick))
		if int(world.tick) < start_tick else "идёт сейчас"
	)
	_plan_details_label.text = "%s · %s\n%s" % [
		str(active_plan.get("place_name", "место не указано")), timing,
		"  ".join(participant_marks),
	]
	var gathering_tick := int(active_plan.get("gathering_tick", start_tick))
	var end_tick := maxi(start_tick + 1, int(active_plan.get("end_tick", start_tick + 1)))
	_plan_progress.min_value = 0.0
	_plan_progress.max_value = 100.0
	_plan_progress.value = clampf(
		float(int(world.tick) - gathering_tick) / float(maxi(1, end_tick - gathering_tick)),
		0.0, 1.0
	) * 100.0


func _update_minimap() -> void:
	if _minimap == null or player == null:
		return
	_minimap.set_state(
		player.global_position, _player_place_id(),
		str(_current_interior.get("name", ""))
	)


func _update_district_pulse() -> void:
	if _pulse_overall_label == null:
		return
	var pulse: Dictionary = world.get_district_pulse_view(world.player_id)
	_pulse_overall_label.text = str(pulse.overall)
	var pulse_color := Color("8fd0a2")
	if str(pulse.tone) == "WARNING":
		pulse_color = Color("e2bc72")
	elif str(pulse.tone) == "DANGER":
		pulse_color = Color("e28484")
	_pulse_overall_label.add_theme_color_override("font_color", pulse_color)
	var signals: Array = pulse.get("signals", [])
	_pulse_signals_label.text = "  ·  ".join(PackedStringArray(signals))


func _update_news_feed() -> void:
	if _news_feed_label == null:
		return
	var items: Array[Dictionary] = world.get_player_news_feed(world.player_id, 4)
	var lines := PackedStringArray()
	for item: Dictionary in items:
		lines.append("[color=#e7be7a]• %s  %s[/color]" % [
			_tick_label(int(item.tick)), str(item.title),
		])
		lines.append("  %s" % str(item.detail))
	if lines.is_empty():
		lines.append("Пока ничего заметного. Разговаривайте с людьми и исследуйте район.")
	_news_feed_label.text = "\n".join(lines)


func _tick_label(event_tick: int) -> String:
	var absolute_ticks := event_tick + 120
	var day := 1 + int(absolute_ticks / 288)
	var minute_of_day := (absolute_ticks % 288) * 5
	return "Д%d %02d:%02d" % [day, int(minute_of_day / 60), minute_of_day % 60]


func _relationship_signal(target_id: int) -> String:
	var relationship: Dictionary = world.get_relationship_state(target_id, world.player_id)
	if relationship.is_empty():
		return "отношение ещё не сформировано"
	var trust := float(relationship.trust)
	var label := "настороженное отношение"
	if trust >= 0.7:
		label = "доверительное отношение"
	elif trust >= 0.4:
		label = "ровное отношение"
	if float(relationship.obligation) >= 0.45:
		label += ", чувствует обязательство"
	return label


func _show_effect_toast(effects: Array) -> void:
	for effect: Dictionary in effects:
		var message := ""
		match str(effect.get("type", "")):
			"RELATIONSHIP_IMPROVED": message = "Отношение стало теплее"
			"TASK_CREATED": message = "Новое поручение: поговорить с %s" % str(effect.get("counterpart_name", "контактом"))
			"TASK_COMPLETED": message = "Поручение выполнено — отношения изменились"
			"INTRODUCTION_CREATED": message = "Открыт новый контакт: %s" % str(effect.get("person_name", "человек"))
			"ACCESS_GRANTED": message = "Получен новый способ доступа в Aurora"
			"IDENTITY_EXCHANGED": message = "Новый человек добавлен в социальную карту"
			"ACTIVITY_SHARED": message = "Вы провели время вместе · занятие повлияло на отношения"
			"ACTIVITY_INVITATION_CREATED": message = "Создано приглашение к совместному занятию"
			"ACTIVITY_ASSISTED": message = "Помощь снизила стресс и улучшила отношения"
			"ACTIVITY_OBSERVED": message = "Вы наблюдали за занятием"
			"ACTIVITY_HINDERED": message = "Помеха повысила стресс и испортила отношения"
			"ACTIVITY_INTERRUPTED": message = "NPC прервал занятие и освободил место"
		if not message.is_empty():
			_toast_label.text = message
			_toast_remaining = 3.2
			_toast_panel.modulate = Color.WHITE
			_toast_panel.visible = true
			return


func _update_toast(delta: float) -> void:
	if _toast_panel == null or not _toast_panel.visible:
		return
	_toast_remaining -= delta
	if _toast_remaining <= 0.0:
		_toast_panel.visible = false
		return
	_toast_panel.modulate.a = clampf(_toast_remaining / 0.45, 0.0, 1.0)


func _style_button(button: Button, primary: bool) -> void:
	var background := Color("356d73") if primary else Color("28383f")
	var border := Color("80cbd1") if primary else Color("536c73")
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 8))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.12), border.lightened(0.15), 8))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.12), border, 8))
	button.add_theme_color_override("font_color", Color("eff6ef"))
	button.add_theme_font_size_override("font_size", 14)


func _style_action_button(button: Button, primary: bool, category: String) -> void:
	var background := Color("356d73") if primary else Color("28383f")
	var border := Color("80cbd1") if primary else Color("536c73")
	if category == "СОВМЕСТНО":
		background = Color("315d49")
		border = Color("73b88a")
	elif category == "КОНФЛИКТ":
		background = Color("633a39")
		border = Color("c36e66")
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 8))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.12), border.lightened(0.15), 8))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.12), border, 8))
	button.add_theme_color_override("font_color", Color("eff6ef"))
	button.add_theme_font_size_override("font_size", 14)


func _style_conflict_button(button: Button) -> void:
	var background := Color("793f3b")
	var border := Color("df8177")
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 8))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.12), border.lightened(0.12), 8))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.12), border, 8))
	button.add_theme_color_override("font_color", Color("fff0e9"))
	button.add_theme_font_size_override("font_size", 14)


func _action_category(action_type: String) -> String:
	if action_type in ["InviteToActivity", "JoinActivity", "AssistActivity"]:
		return "СОВМЕСТНО"
	if action_type in ["HinderActivity", "InterruptActivity"]:
		return "КОНФЛИКТ"
	return "ОБЩЕНИЕ"


func _action_category_order(action_type: String) -> int:
	return {"СОВМЕСТНО": 0, "ОБЩЕНИЕ": 1, "КОНФЛИКТ": 2}[_action_category(action_type)]


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style
