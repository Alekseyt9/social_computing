extends Node2D

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const WorldMapScript := preload("res://world/world_map.gd")
const PlayerControllerScript := preload("res://world/player_controller.gd")
const NpcControllerScript := preload("res://world/npc_controller.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")

const INTERACTION_DISTANCE := 92.0
const NPC_DATA := [
	{"id": 2, "position": Vector2(745, 615), "zone": Rect2(725, 555, 95, 105), "color": Color("db7f8e")},
	{"id": 8, "position": Vector2(560, 500), "zone": Rect2(545, 455, 125, 225), "color": Color("e5ad62")},
	{"id": 5, "position": Vector2(1030, 560), "zone": Rect2(930, 450, 200, 220), "color": Color("6ebbc5")},
	{"id": 3, "position": Vector2(1080, 720), "zone": Rect2(930, 695, 195, 100), "color": Color("7fa7e8")},
	{"id": 13, "position": Vector2(1250, 630), "zone": Rect2(1170, 445, 235, 300), "color": Color("bf8cce")},
	{"id": 16, "position": Vector2(1045, 420), "zone": Rect2(925, 405, 185, 90), "color": Color("8ea0ac")},
	{"id": 20, "position": Vector2(620, 760), "zone": Rect2(560, 690, 300, 105), "color": Color("6ec18c")},
	{"id": 7, "position": Vector2(900, 320), "zone": Rect2(700, 220, 350, 180), "color": Color("d19466")},
]

var world: RefCounted
var player: CharacterBody2D
var groq_client: Node
var _nearby_npc: CharacterBody2D
var _dialogue_npc: CharacterBody2D
var _npc_by_id: Dictionary = {}
var _simulation_accumulator := 0.0
var _pending_act: Dictionary = {}
var _pending_fallback := ""

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


func _process(delta: float) -> void:
	_simulation_accumulator += delta
	if _simulation_accumulator >= 1.0:
		var elapsed_ticks := int(_simulation_accumulator)
		_simulation_accumulator -= float(elapsed_ticks)
		world.advance(elapsed_ticks)
		_update_hud()
	if not _dialogue_panel.visible:
		_update_nearby_npc()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if _dialogue_panel.visible:
				_close_dialogue()
			elif _nearby_npc != null:
				_open_dialogue(_nearby_npc)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _dialogue_panel.visible:
			_close_dialogue()
			get_viewport().set_input_as_handled()


func _build_map() -> void:
	var map := WorldMapScript.new()
	map.name = "WorldMap"
	add_child(map)


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
	header.size = Vector2(420, 102)
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
	controls.text = "WASD / стрелки — движение    E — взаимодействие"
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
	_nearby_npc = closest
	_prompt_panel.visible = closest != null
	if closest != null:
		var identity: Dictionary = world.get_visible_identity(world.player_id, closest.person_id)
		_prompt_label.text = "[ E ]  Поговорить  ·  %s" % identity.name


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
	_clear_actions()
	if identity.known:
		_conversation_label.text = "%s смотрит на вас и ждёт, что вы скажете." % identity.name
		_add_action_button("Спросить про Aurora", _perform_action.bind("AskAbout", {"topic": "Aurora"}), true)
		_add_action_button("Попросить об услуге", _perform_action.bind("AskFavor", {}), false)
		var intro_context := {"subject_person_id": 3}
		_add_action_button("Попросить знакомство", _perform_action.bind("AskIntroduction", intro_context), false)
	else:
		_conversation_label.text = "Незнакомец останавливается рядом. Можно представиться и начать знакомство."
		_add_action_button("Поздороваться и представиться", _introduce_current_npc, true)


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
	_update_nearby_npc()


func _introduce_current_npc() -> void:
	if _dialogue_npc == null:
		return
	var result: Dictionary = world.introduce_people(world.player_id, _dialogue_npc.person_id)
	if not result.ok:
		_conversation_label.text = "Не удалось начать знакомство: %s" % result.error
		return
	var person_name: String = world.get_person_name(_dialogue_npc.person_id)
	_dialogue_npc.set_known_name(person_name)
	_speaker_label.text = person_name
	_role_label.text = world.get_person_role(_dialogue_npc.person_id)
	_conversation_label.text = "Вы представляетесь друг другу.\n\n%s: «Приятно познакомиться. Что привело тебя в этот район?»" % person_name
	_clear_actions()
	_add_action_button("Спросить про Aurora", _perform_action.bind("AskAbout", {"topic": "Aurora"}), true)
	_add_action_button("Попросить об услуге", _perform_action.bind("AskFavor", {}), false)
	_update_hud()


func _perform_action(action_type: String, context: Dictionary) -> void:
	if _dialogue_npc == null or groq_client.is_busy():
		return
	var result: Dictionary = world.perform_social_action(
		action_type, world.player_id, _dialogue_npc.person_id, context
	)
	if not result.ok:
		_conversation_label.text = "Сейчас это действие недоступно (%s). Сначала узнайте нужную связь." % result.error
		return
	_set_action_buttons_disabled(true)
	_pending_act = result.communicative_act
	_pending_fallback = result.template_response
	var identity := {
		"name": world.get_person_name(_dialogue_npc.person_id),
		"role": world.get_person_role(_dialogue_npc.person_id),
	}
	_conversation_label.text = "%s\n\n%s думает…" % [result.player_line, identity.name]
	_status_label.text = result.feedback
	if groq_client.is_configured():
		var started: bool = groq_client.generate_text(
			SocialRendererScript.build_system_prompt(),
			SocialRendererScript.build_user_prompt(identity, result.communicative_act, {
				"player_line": result.player_line,
				"location": "Aurora district",
			})
		)
		if started:
			return
	_show_dialogue_response(result.template_response, "локальный шаблон")


func _on_groq_response(raw_text: String) -> void:
	var rendered := SocialRendererScript.sanitize_output(raw_text, _pending_act, _pending_fallback)
	var source := "Groq" if rendered != _pending_fallback else "локальный шаблон (ответ Groq отклонён)"
	_show_dialogue_response(rendered, source)


func _on_groq_failure(message: String) -> void:
	_show_dialogue_response(_pending_fallback, "локальный шаблон · %s" % message)


func _show_dialogue_response(response: String, source: String) -> void:
	if _dialogue_npc == null:
		return
	var name: String = world.get_person_name(_dialogue_npc.person_id)
	var player_line := ""
	if not _pending_act.is_empty():
		player_line = _player_line_for_act(_pending_act)
	_conversation_label.text = "%s\n\n%s: «%s»" % [player_line, name, response]
	_status_label.text = "Текст ответа: %s" % source
	_set_action_buttons_disabled(false)
	_pending_act = {}
	_pending_fallback = ""
	_update_hud()


func _player_line_for_act(act: Dictionary) -> String:
	match str(act.get("action_type", "")):
		"AskAbout":
			return "Вы: «Ты случайно не знаешь кого-нибудь в Aurora?»"
		"AskFavor":
			return "Вы: «Мне нужно попасть на закрытое мероприятие Aurora. Поможешь?»"
		"AskIntroduction":
			return "Вы: «Можешь представить меня этому человеку?»"
		_:
			return "Вы задаёте вопрос."


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
	var anna_sergey_fact: int = world.get_relationship_fact_id(2, 3)
	if anna_sergey_fact != -1 and world.person_knows_fact(world.player_id, anna_sergey_fact):
		_objective_label.text = "Цель: поговорить с Сергеем у офиса Aurora.\nСвязь Анны с ним уже обнаружена."
	else:
		_objective_label.text = "Цель: узнать, как попасть в Aurora.\nНачните с Анны на городской площади."


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
