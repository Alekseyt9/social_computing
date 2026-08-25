extends Control

const INITIAL_SEED := 42
const SimulationWorldScript := preload("res://core/simulation_world.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")

var _world: RefCounted
var _groq_client: Node
var _contacts_box: VBoxContainer
var _conversation: RichTextLabel
var _contact_name_label: Label
var _contact_role_label: Label
var _relationship_label: Label
var _world_metrics_label: Label
var _time_label: Label
var _status_label: Label
var _groq_status_label: Label
var _groq_button: Button
var _action_buttons: Array[Button] = []
var _selected_contact_id: int = -1
var _pending_render_kind: String = ""
var _pending_communicative_act: Dictionary = {}
var _pending_template_response: String = ""
var _pending_speaker_name: String = ""

var _color_bg := Color("0b0f14")
var _color_surface := Color("121821")
var _color_surface_raised := Color("18212d")
var _color_border := Color("263241")
var _color_text := Color("e8edf2")
var _color_muted := Color("8d9bab")
var _color_accent := Color("e7a64b")
var _color_accent_soft := Color("35291b")
var _color_teal := Color("58c9b9")
var _color_danger := Color("d47575")


func _ready() -> void:
	_world = SimulationWorldScript.new(INITIAL_SEED)
	_build_interface()
	_setup_groq()
	_refresh_world_view("Сценарий Aurora активен")
	var contacts: Array[Dictionary] = _world.get_contact_cards_for(_world.player_id)
	if not contacts.is_empty():
		_select_contact(contacts[0].id)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = _color_bg
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 22)
	outer_margin.add_theme_constant_override("margin_top", 18)
	outer_margin.add_theme_constant_override("margin_right", 22)
	outer_margin.add_theme_constant_override("margin_bottom", 14)
	add_child(outer_margin)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 14)
	outer_margin.add_child(shell)

	shell.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	shell.add_child(body)

	body.add_child(_build_contacts_panel())
	body.add_child(_build_conversation_panel())
	body.add_child(_build_context_column())

	_status_label = _make_label("", 13, _color_muted)
	_status_label.custom_minimum_size.y = 22
	shell.add_child(_status_label)


func _build_header() -> Control:
	var panel := _make_panel(_color_surface, 12, _color_border)
	panel.custom_minimum_size.y = 80

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 235
	brand.add_theme_constant_override("separation", 0)
	row.add_child(brand)
	var brand_name := _make_label("SOCIAL // SIM", 21, _color_text)
	brand_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	brand.add_child(brand_name)
	brand.add_child(_make_label("ADAPTIVE PROTOTYPE  ·  BUILD 001", 11, _color_muted))

	var objective := _make_panel(_color_accent_soft, 9, _color_accent)
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(objective)
	var objective_box := VBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 2)
	objective.add_child(objective_box)
	objective_box.add_child(_make_label("ТЕКУЩАЯ ЦЕЛЬ", 11, _color_accent))
	objective_box.add_child(_make_label("Попасть на закрытую вечеринку Aurora", 17, _color_text))

	_time_label = _make_label("", 14, _color_teal)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.custom_minimum_size.x = 92
	row.add_child(_time_label)

	var advance_button := _make_button("ПРОПУСТИТЬ 1 ЧАС", false)
	advance_button.custom_minimum_size = Vector2(160, 46)
	advance_button.pressed.connect(_on_advance_pressed)
	row.add_child(advance_button)
	return panel


func _build_contacts_panel() -> Control:
	var panel := _make_panel(_color_surface, 12, _color_border)
	panel.custom_minimum_size.x = 268

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_make_section_heading("ИЗВЕСТНЫЕ КОНТАКТЫ", "01"))

	_contacts_box = VBoxContainer.new()
	_contacts_box.add_theme_constant_override("separation", 8)
	box.add_child(_contacts_box)

	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", _color_border)
	box.add_child(divider)

	var discovery_hint := _make_label(
		"Новые связи открываются через разговоры, наблюдения и общих знакомых.",
		13,
		_color_muted
	)
	discovery_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(discovery_hint)

	var unknown := _make_panel(Color("0f141b"), 8, _color_border)
	unknown.custom_minimum_size.y = 62
	box.add_child(unknown)
	var unknown_row := HBoxContainer.new()
	unknown.add_child(unknown_row)
	var mark := _make_label("?", 22, _color_muted)
	mark.custom_minimum_size.x = 38
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unknown_row.add_child(mark)
	var unknown_text := VBoxContainer.new()
	unknown_row.add_child(unknown_text)
	unknown_text.add_child(_make_label("НЕИЗВЕСТНАЯ СВЯЗЬ", 12, _color_muted))
	unknown_text.add_child(_make_label("Нужна новая информация", 12, Color("647181")))
	return panel


func _build_conversation_panel() -> Control:
	var panel := _make_panel(_color_surface, 12, _color_border)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 12)
	box.add_child(profile_row)
	var avatar := _make_panel(_color_accent_soft, 10, _color_accent)
	avatar.custom_minimum_size = Vector2(58, 58)
	profile_row.add_child(avatar)
	var avatar_label := _make_label("A", 26, _color_accent)
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(avatar_label)

	var profile_text := VBoxContainer.new()
	profile_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(profile_text)
	_contact_name_label = _make_label("Выберите контакт", 21, _color_text)
	profile_text.add_child(_contact_name_label)
	_contact_role_label = _make_label("", 13, _color_muted)
	profile_text.add_child(_contact_role_label)

	_relationship_label = _make_label("", 12, _color_teal)
	_relationship_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_relationship_label.custom_minimum_size.x = 190
	profile_row.add_child(_relationship_label)

	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", _color_border)
	box.add_child(divider)

	_conversation = RichTextLabel.new()
	_conversation.bbcode_enabled = true
	_conversation.fit_content = false
	_conversation.scroll_active = true
	_conversation.scroll_following = true
	_conversation.selection_enabled = true
	_conversation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conversation.add_theme_font_size_override("normal_font_size", 15)
	_conversation.add_theme_color_override("default_color", _color_text)
	_conversation.add_theme_stylebox_override("normal", _panel_style(Color("0d1218"), 9, _color_border))
	box.add_child(_conversation)

	box.add_child(_make_label("ДОСТУПНЫЕ ДЕЙСТВИЯ", 11, _color_muted))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	_add_action_button(actions, "Спросить об Aurora", "ask_about")
	_add_action_button(actions, "Попросить об услуге", "ask_favor")
	var introduce := _add_action_button(actions, "Попросить представить", "ask_introduction")
	introduce.disabled = true
	introduce.tooltip_text = "Сначала узнайте, с кем именно вас могут познакомить"
	return panel


func _build_context_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 300
	column.add_theme_constant_override("separation", 14)

	var goal_panel := _make_panel(_color_surface, 12, _color_border)
	goal_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(goal_panel)
	var goal_box := VBoxContainer.new()
	goal_box.add_theme_constant_override("separation", 11)
	goal_panel.add_child(goal_box)
	goal_box.add_child(_make_section_heading("СОЦИАЛЬНЫЙ МАРШРУТ", "СКРЫТ"))
	goal_box.add_child(_make_route_step("01", "Поговорить с Анной", "Текущий шаг", true))
	goal_box.add_child(_make_route_step("02", "Найти связь с Aurora", "Путь неизвестен", false))
	goal_box.add_child(_make_route_step("03", "Получить приглашение", "Условия неизвестны", false))

	var metrics_panel := _make_panel(_color_surface, 12, _color_border)
	column.add_child(metrics_panel)
	var metrics_box := VBoxContainer.new()
	metrics_box.add_theme_constant_override("separation", 8)
	metrics_panel.add_child(metrics_box)
	metrics_box.add_child(_make_section_heading("СОСТОЯНИЕ МИРА", "LIVE"))
	_world_metrics_label = _make_label("", 13, _color_muted)
	metrics_box.add_child(_world_metrics_label)

	var renderer_panel := _make_panel(_color_surface, 12, _color_border)
	column.add_child(renderer_panel)
	var renderer_box := VBoxContainer.new()
	renderer_box.add_theme_constant_override("separation", 8)
	renderer_panel.add_child(renderer_box)
	renderer_box.add_child(_make_section_heading("SOCIAL RENDERER", "OPTIONAL"))
	_groq_status_label = _make_label("Проверка конфигурации…", 12, _color_muted)
	_groq_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	renderer_box.add_child(_groq_status_label)
	_groq_button = _make_button("ПРОВЕРИТЬ GROQ", true)
	_groq_button.pressed.connect(_on_groq_pressed)
	renderer_box.add_child(_groq_button)
	return column


func _setup_groq() -> void:
	_groq_client = GroqClientScript.new()
	_groq_client.response_received.connect(_on_groq_response_received)
	_groq_client.request_failed.connect(_on_groq_request_failed)
	add_child(_groq_client)
	var configured: bool = _groq_client.is_configured()
	_groq_button.disabled = not configured
	if configured:
		_groq_status_label.text = "Готов к рендерингу реплик. Решения NPC остаются в симуляции."
		_groq_status_label.add_theme_color_override("font_color", _color_teal)
	else:
		_groq_status_label.text = "Не настроен. Игра использует безопасный шаблонный renderer."
		_groq_button.tooltip_text = "Задайте GROQ_API_KEY перед запуском"


func _refresh_contacts() -> void:
	for child: Node in _contacts_box.get_children():
		child.queue_free()
	for contact: Dictionary in _world.get_contact_cards_for(_world.player_id):
		var button := _make_button(
			"%s\n%s  ·  %s" % [contact.name, contact.role, contact.trust_signal],
			false
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 72
		button.pressed.connect(_select_contact.bind(contact.id))
		_contacts_box.add_child(button)


func _select_contact(contact_id: int) -> void:
	_selected_contact_id = contact_id
	var selected: Dictionary = {}
	for contact: Dictionary in _world.get_contact_cards_for(_world.player_id):
		if contact.id == contact_id:
			selected = contact
			break
	if selected.is_empty():
		return

	_contact_name_label.text = selected.name
	_contact_role_label.text = "%s  ·  Corner Cafe" % selected.role
	_relationship_label.text = "%s\n%s" % [
		selected.familiarity_signal,
		selected.trust_signal,
	]
	_conversation.text = (
		"[color=#718091]18:40  ·  CORNER CAFE[/color]\n\n"
		+ "[color=#8d9bab]Вы замечаете Анну за столиком у окна. Она узнаёт вас и откладывает телефон.[/color]\n\n"
		+ "[color=#e7a64b][b]ANNA[/b][/color]\n"
		+ "Привет. Не ожидала тебя здесь увидеть. Как ты?"
	)
	for button: Button in _action_buttons:
		if button.text != "Попросить представить":
			button.disabled = false
	_status_label.text = "Вы разговариваете с %s. Числовые параметры отношений скрыты." % selected.name


func _on_action_pressed(action: String) -> void:
	if _selected_contact_id < 0:
		return
	var action_type := ""
	var context: Dictionary = {}
	match action:
		"ask_about":
			action_type = "AskAbout"
			context = {"topic": "Aurora"}
		"ask_favor":
			action_type = "AskFavor"
			context = {"topic": "Aurora Party"}
		_:
			return

	var result: Dictionary = _world.perform_social_action(
		action_type,
		_world.player_id,
		_selected_contact_id,
		context
	)
	if not result.get("ok", false):
		_status_label.text = "Действие недоступно: %s" % str(result.get("error", "UNKNOWN"))
		return

	_append_player_line(result.player_line)
	_refresh_world_view(result.feedback)

	if _groq_client.is_configured() and not _groq_client.is_busy():
		_pending_render_kind = "dialogue"
		_pending_communicative_act = result.communicative_act.duplicate(true)
		_pending_template_response = result.template_response
		_pending_speaker_name = _world.get_person_name(_selected_contact_id)
		_set_action_buttons_busy(true)
		_groq_button.disabled = true
		_groq_status_label.text = "Groq формулирует уже принятое решение NPC…"
		var started: bool = _groq_client.generate_text(
			SocialRendererScript.build_system_prompt(),
			SocialRendererScript.build_user_prompt(
				{
					"name": _pending_speaker_name,
					"role": "designer",
				},
				_pending_communicative_act,
				{
					"location": "Corner Cafe",
					"player_line": result.player_line,
				}
			)
		)
		if not started and _pending_render_kind == "dialogue":
			_finish_with_template("LLM-запрос не запущен")
	else:
		_append_npc_line(result.template_response, "TEMPLATE")
		_groq_status_label.text = "Реплика создана локальным template renderer."
		_groq_status_label.add_theme_color_override("font_color", _color_muted)


func _on_advance_pressed() -> void:
	_world.advance(60)
	_refresh_world_view("Прошёл один игровой час")


func _on_groq_pressed() -> void:
	_pending_render_kind = "diagnostic"
	_groq_button.disabled = true
	_groq_status_label.text = "Рендеринг тестовой реплики…"
	var started: bool = _groq_client.generate_text(
		"Ты лаконичный renderer реплик для социальной симуляции. Не изменяй состояние мира.",
		"Ответь одной короткой фразой: система диалогов готова."
	)
	if not started:
		_groq_button.disabled = false


func _on_groq_response_received(text: String) -> void:
	if _pending_render_kind == "dialogue":
		var rendered: String = SocialRendererScript.sanitize_output(
			text,
			_pending_communicative_act,
			_pending_template_response
		)
		var source := "GROQ"
		if rendered == _pending_template_response and text.strip_edges() != rendered:
			source = "SAFE FALLBACK"
		_append_npc_line(rendered, source)
		_groq_status_label.text = (
			"Groq сформулировал реплику. Решение и последствия взяты из симуляции."
			if source == "GROQ"
			else "Ответ Groq не прошёл semantic validation; использован fallback."
		)
		_groq_status_label.add_theme_color_override(
			"font_color", _color_teal if source == "GROQ" else _color_accent
		)
		_clear_pending_render()
		return

	_pending_render_kind = ""
	_groq_button.disabled = false
	_groq_status_label.text = "Renderer: %s" % text
	_groq_status_label.add_theme_color_override("font_color", _color_teal)


func _on_groq_request_failed(message: String) -> void:
	if _pending_render_kind == "dialogue":
		_finish_with_template(message)
		return

	_pending_render_kind = ""
	_groq_button.disabled = false
	_groq_status_label.text = message
	_groq_status_label.add_theme_color_override("font_color", _color_danger)


func _append_player_line(text: String) -> void:
	_conversation.append_text("\n\n[color=#58c9b9][b]ВЫ[/b][/color]\n%s" % text)


func _append_npc_line(text: String, source: String) -> void:
	_conversation.append_text(
		(
			"\n\n[color=#e7a64b][b]%s[/b][/color]"
			+ " [color=#718091]· %s[/color]\n%s"
		) % [
			_pending_speaker_name if not _pending_speaker_name.is_empty() else "ANNA",
			source,
			text,
		]
	)


func _finish_with_template(reason: String) -> void:
	_append_npc_line(_pending_template_response, "TEMPLATE FALLBACK")
	_groq_status_label.text = "Groq недоступен: %s. Использован fallback." % reason
	_groq_status_label.add_theme_color_override("font_color", _color_accent)
	_clear_pending_render()


func _clear_pending_render() -> void:
	_pending_render_kind = ""
	_pending_communicative_act = {}
	_pending_template_response = ""
	_pending_speaker_name = ""
	_groq_button.disabled = not _groq_client.is_configured()
	_set_action_buttons_busy(false)


func _set_action_buttons_busy(is_busy: bool) -> void:
	for button: Button in _action_buttons:
		button.disabled = is_busy or button.text == "Попросить представить"


func _refresh_world_view(status: String) -> void:
	var state: Dictionary = _world.snapshot()
	var player_view: Dictionary = _world.get_observer_view(_world.player_id)
	_refresh_contacts()
	_update_time()
	_world_metrics_label.text = (
		"NPC в симуляции             %d\n"
		+ "Мест                          %d\n"
		+ "Фактов мира                   %d\n"
		+ "Известных связей              %d\n"
		+ "Тик симуляции                 %d"
	) % [
		state.npc_count,
		state.place_count,
		state.fact_count,
		player_view.known_relationships.size(),
		state.tick,
	]
	_status_label.text = "%s  ·  Seed %d  ·  Checksum %s" % [status, state.seed, state.checksum]


func _update_time() -> void:
	var total_minutes: int = 18 * 60 + 40 + _world.tick
	var day: int = 1 + int(total_minutes / 1440)
	var minute_of_day: int = total_minutes % 1440
	_time_label.text = "DAY %02d\n%02d:%02d" % [
		day,
		int(minute_of_day / 60),
		minute_of_day % 60,
	]


func _add_action_button(parent: Control, title: String, action: String) -> Button:
	var button := _make_button(title, false)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 48
	button.pressed.connect(_on_action_pressed.bind(action))
	parent.add_child(button)
	_action_buttons.append(button)
	return button


func _make_route_step(number: String, title: String, detail: String, active: bool) -> Control:
	var color := _color_accent if active else _color_muted
	var panel := _make_panel(_color_accent_soft if active else Color("0f141b"), 8, color if active else _color_border)
	panel.custom_minimum_size.y = 62
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var number_label := _make_label(number, 14, color)
	number_label.custom_minimum_size.x = 28
	row.add_child(number_label)
	var text_box := VBoxContainer.new()
	row.add_child(text_box)
	text_box.add_child(_make_label(title, 14, _color_text if active else _color_muted))
	text_box.add_child(_make_label(detail, 11, color))
	return panel


func _make_section_heading(title: String, badge: String) -> Control:
	var row := HBoxContainer.new()
	var title_label := _make_label(title, 12, _color_muted)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	row.add_child(_make_label(badge, 11, _color_accent))
	return row


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, subtle: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", _color_text)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("596472"))
	var normal_color := Color("111820") if subtle else _color_surface_raised
	button.add_theme_stylebox_override("normal", _panel_style(normal_color, 8, _color_border))
	button.add_theme_stylebox_override("hover", _panel_style(Color("202c39"), 8, _color_accent))
	button.add_theme_stylebox_override("pressed", _panel_style(_color_accent_soft, 8, _color_accent))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("0e1319"), 8, Color("1c2530")))
	return button


func _make_panel(color: Color, radius: int, border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(color, radius, border_color))
	return panel


func _panel_style(color: Color, radius: int, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	return style
