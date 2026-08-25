extends Control

const INITIAL_SEED := 42
const SimulationWorldScript := preload("res://core/simulation_world.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")

var _world: RefCounted
var _groq_client
var _status_label: Label
var _snapshot_label: Label
var _groq_status_label: Label
var _groq_button: Button


func _ready() -> void:
	_build_interface()
	_setup_groq()
	_world = SimulationWorldScript.new(INITIAL_SEED)
	_refresh_world_view("Сценарий Aurora загружен")


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Adaptive Social Immersive Sim — walking skeleton"
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)

	var description := Label.new()
	description.text = "Интерфейс и детерминированное ядро работают нативно в Godot на GDScript."
	content.add_child(description)

	_status_label = Label.new()
	content.add_child(_status_label)

	_snapshot_label = Label.new()
	content.add_child(_snapshot_label)

	var advance_button := Button.new()
	advance_button.text = "Продвинуть симуляцию на 60 тиков"
	advance_button.custom_minimum_size = Vector2(320, 48)
	advance_button.pressed.connect(_on_advance_pressed)
	content.add_child(advance_button)

	_groq_status_label = Label.new()
	_groq_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_groq_status_label)

	_groq_button = Button.new()
	_groq_button.text = "Проверить Groq API"
	_groq_button.custom_minimum_size = Vector2(320, 48)
	_groq_button.pressed.connect(_on_groq_pressed)
	content.add_child(_groq_button)


func _setup_groq() -> void:
	_groq_client = GroqClientScript.new()
	_groq_client.response_received.connect(_on_groq_response_received)
	_groq_client.request_failed.connect(_on_groq_request_failed)
	add_child(_groq_client)
	if _groq_client.is_configured():
		_groq_status_label.text = "Groq настроен. Ключ читается из окружения."
	else:
		_groq_status_label.text = "Groq не настроен: задайте GROQ_API_KEY."


func _on_advance_pressed() -> void:
	_world.advance(60)
	_refresh_world_view("Симуляция выполнена")


func _on_groq_pressed() -> void:
	_groq_button.disabled = true
	_groq_status_label.text = "Запрос к Groq..."
	var started: bool = _groq_client.generate_text(
		"Ты лаконичный renderer реплик для социальной симуляции. Не изменяй состояние мира.",
		"Ответь одной короткой фразой: система диалогов готова."
	)
	if not started:
		_groq_button.disabled = false


func _on_groq_response_received(text: String) -> void:
	_groq_button.disabled = false
	_groq_status_label.text = "Groq ответил: %s" % text


func _on_groq_request_failed(message: String) -> void:
	_groq_button.disabled = false
	_groq_status_label.text = message


func _refresh_world_view(status: String) -> void:
	var state: Dictionary = _world.snapshot()
	var player_view: Dictionary = _world.get_observer_view(_world.player_id)
	_status_label.text = status
	_snapshot_label.text = (
		"Seed: %d\nTick: %d\nChecksum: %s\n\n"
		+ "NPC: %d | Места: %d | Организации: %d\n"
		+ "Факты мира: %d | Известные игроку связи: %d\n"
		+ "Знакомые игрока: %s"
	) % [
		state.seed,
		state.tick,
		state.checksum,
		state.npc_count,
		state.place_count,
		state.organization_count,
		state.fact_count,
		player_view.known_relationships.size(),
		", ".join(player_view.known_contact_names),
	]
