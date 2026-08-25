extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")

var _client: Node
var _action_result: Dictionary


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := SimulationWorldScript.new(42)
	_action_result = world.perform_social_action(
		"AskAbout",
		world.player_id,
		2,
		{"topic": "Aurora"}
	)
	if not _action_result.get("ok", false):
		push_error("DIALOGUE_INTEGRATION_FAILED action pipeline")
		quit(1)
		return

	_client = GroqClientScript.new()
	_client.response_received.connect(_on_response_received)
	_client.request_failed.connect(_on_request_failed)
	root.add_child(_client)
	var started: bool = _client.generate_text(
		SocialRendererScript.build_system_prompt(),
		SocialRendererScript.build_user_prompt(
			{"name": "Anna", "role": "designer"},
			_action_result.communicative_act,
			{
				"location": "Corner Cafe",
				"player_line": _action_result.player_line,
			}
		)
	)
	if not started:
		quit(1)


func _on_response_received(text: String) -> void:
	var rendered: String = SocialRendererScript.sanitize_output(
		text,
		_action_result.communicative_act,
		_action_result.template_response
	)
	var source := "groq" if rendered == text.strip_edges() else "safe_fallback"
	print("DIALOGUE_INTEGRATION_OK source=%s chars=%d response=%s" % [
		source,
		rendered.length(),
		rendered,
	])
	quit(0)


func _on_request_failed(message: String) -> void:
	push_error("DIALOGUE_INTEGRATION_FAILED %s" % message)
	quit(1)
