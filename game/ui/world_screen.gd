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

const INTERACTION_DISTANCE := 92.0
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
var _renderer_debug: Dictionary = {}
var _last_adaptive_focus_tick: int = -1
var _ambient_crowd: Node2D

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


func _process(delta: float) -> void:
	_update_toast(delta)
	_simulation_accumulator += delta
	if _simulation_accumulator >= 1.0:
		var elapsed_ticks := int(_simulation_accumulator)
		_simulation_accumulator -= float(elapsed_ticks)
		world.advance(elapsed_ticks)
		_update_adaptive_focus(false)
		_update_hud()
	if not _dialogue_panel.visible:
		_update_nearby_npc()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
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
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _social_map_overlay.visible:
				_toggle_social_map()
			elif _debug_overlay.visible:
				_toggle_debug_inspector()
			elif _dialogue_panel.visible:
				_close_dialogue()
			get_viewport().set_input_as_handled()


func _build_map() -> void:
	var map := WorldMapScript.new()
	map.name = "WorldMap"
	add_child(map)
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
	world.update_adaptive_focus(_player_place_id(), [], 60)
	if _ambient_crowd != null:
		_ambient_crowd.sync_from_simulation()


func _player_place_id() -> int:
	var position_in_world := player.global_position
	if position_in_world.y >= 735.0 and position_in_world.x <= 650.0:
		return 3 # Player Apartment / residential block
	if position_in_world.x >= 1070.0:
		return 1 # Aurora side of the district
	return 2 # Cafe, park and public square


func _build_npcs() -> void:
	for data: Dictionary in NPC_DATA:
		var npc := NpcControllerScript.new()
		var person_id: int = data.id
		var identity: Dictionary = world.get_visible_identity(world.player_id, person_id)
		npc.setup(person_id, identity.name, data.zone, data.color)
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
	controls.text = "WASD — движение   E — диалог   M — связи   F3 — debug"
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
	_build_news_feed(canvas)
	_build_toast(canvas)
	_build_social_map(canvas)
	_build_debug_inspector(canvas)


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


func _sync_player_input() -> void:
	player.input_enabled = not (
		_dialogue_panel.visible or _social_map_overlay.visible or _debug_overlay.visible
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
	_dialogue_panel.position = Vector2(-475, -355)
	_dialogue_panel.size = Vector2(950, 325)
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
	_conversation_label = Label.new()
	_conversation_label.custom_minimum_size = Vector2(0, 108)
	_conversation_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conversation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conversation_label.add_theme_font_size_override("font_size", 17)
	_conversation_label.add_theme_color_override("font_color", Color("f0eee5"))
	content.add_child(_conversation_label)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 10)
	content.add_child(_action_row)
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
	_near_aurora_entrance = player.global_position.distance_to(Vector2(1385, 425)) < 88.0
	_prompt_panel.visible = (
		closest != null or not _nearby_light_citizen.is_empty() or _near_aurora_entrance
	)
	if closest != null:
		var identity: Dictionary = world.get_visible_identity(world.player_id, closest.person_id)
		_prompt_label.text = "[ E ]  Поговорить  ·  %s" % identity.name
	elif not _nearby_light_citizen.is_empty():
		_prompt_label.text = "[ E ]  Поговорить  ·  Житель района"
	elif _near_aurora_entrance:
		_prompt_label.text = "[ E ]  Войти в Aurora"


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
	npc.setup(agent_id, str(identity.name), zone, accent)
	npc.name = "AdaptiveNPC_%d" % agent_id
	npc.position = citizen.position
	add_child(npc)
	_npc_by_id[agent_id] = npc
	return npc


func _open_dialogue(npc: CharacterBody2D) -> void:
	_dialogue_npc = npc
	_dialogue_npc.movement_paused = true
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	_prompt_panel.visible = false
	_dialogue_panel.visible = true
	var identity: Dictionary = world.get_visible_identity(world.player_id, npc.person_id)
	_speaker_label.text = identity.name
	_role_label.text = identity.role if identity.known else "Вы ещё не знакомы"
	_status_label.text = "Решения принимает симуляция · текст: Groq или локальный шаблон"
	_status_label.text += " · %s" % _relationship_signal(npc.person_id)
	_clear_actions()
	if identity.known:
		_conversation_label.text = "%s смотрит на вас и ждёт, что вы скажете." % identity.name
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
	player.input_enabled = true
	_pending_act = {}
	_pending_fallback = ""
	_pending_player_line = ""
	_update_nearby_npc()


func _refresh_dialogue_actions() -> void:
	_clear_actions()
	if _dialogue_npc == null:
		return
	var actions: Array[Dictionary] = world.get_available_social_actions(
		world.player_id, _dialogue_npc.person_id
	)
	for index in range(actions.size()):
		var action: Dictionary = actions[index]
		_add_action_button(
			SocialActionPresenterScript.button_label(action),
			_perform_model_action.bind(action),
			index == 0
		)


func _perform_model_action(action: Dictionary) -> void:
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
		render_context["location"] = "Aurora district"
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
	_clear_actions()
	if result.ok:
		_conversation_label.text = "Пропуск подтверждён. Цель достигнута: вы вошли на закрытое мероприятие."
		_status_label.text = "Результат вычислен по факту владения пропуском."
	else:
		_conversation_label.text = "Доступ пока закрыт: модель мира не нашла у вас действующего пропуска."
		_status_label.text = "Требование модели: действующий Aurora access token"


func _clear_actions() -> void:
	for child: Node in _action_row.get_children():
		child.queue_free()


func _add_action_button(label_text: String, callback: Callable, primary: bool) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(190, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	_style_button(button, primary)
	_action_row.add_child(button)


func _set_action_buttons_disabled(disabled: bool) -> void:
	for child: Node in _action_row.get_children():
		if child is Button:
			child.disabled = disabled


func _update_hud() -> void:
	var minutes: int = (int(world.tick) * 5) % (24 * 60)
	var hour: int = 10 + int(minutes / 60)
	var minute: int = minutes % 60
	_clock_label.text = "День 1  ·  %02d:%02d" % [hour, minute]
	var goal: Dictionary = world.get_goal_state(world.player_id)
	_objective_label.text = "%s\n%s" % [goal.title, goal.hint]
	var tasks: Array[Dictionary] = world.get_active_tasks_for(world.player_id)
	if not tasks.is_empty():
		var task: Dictionary = tasks[0]
		_objective_label.text += "\nПоручение: найти %s · %s" % [
			str(task.counterpart_name), str(task.topic),
		]
	_update_district_pulse()
	_update_news_feed()
	_refresh_debug_inspector()


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
	var total_minutes := event_tick * 5
	var day := 1 + int(total_minutes / (24 * 60))
	var minute_of_day := (10 * 60 + total_minutes) % (24 * 60)
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
