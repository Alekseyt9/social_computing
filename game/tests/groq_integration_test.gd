extends SceneTree

const GroqClientScript := preload("res://llm/groq_client.gd")

var _client
var _started_at_ms := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_client = GroqClientScript.new()
	_client.response_received.connect(_on_response_received)
	_client.request_failed.connect(_on_request_failed)
	root.add_child(_client)

	_started_at_ms = Time.get_ticks_msec()
	var started: bool = _client.generate_text(
		"Ты выполняешь диагностический тест API. Следуй формату ответа буквально.",
		"Ответь строго одной строкой: GROQ_MODEL_OK"
	)
	if not started:
		quit(1)


func _on_response_received(text: String) -> void:
	var elapsed_ms := Time.get_ticks_msec() - _started_at_ms
	print("GROQ_INTEGRATION_OK elapsed_ms=%d response=%s" % [elapsed_ms, text])
	quit(0)


func _on_request_failed(message: String) -> void:
	var elapsed_ms := Time.get_ticks_msec() - _started_at_ms
	push_error("GROQ_INTEGRATION_FAILED elapsed_ms=%d error=%s" % [elapsed_ms, message])
	quit(1)
