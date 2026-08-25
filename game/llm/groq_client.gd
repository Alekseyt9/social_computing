extends Node
class_name GroqClient

signal response_received(text: String)
signal request_failed(message: String)

const API_URL := "https://api.groq.com/openai/v1/chat/completions"
const DEFAULT_MODEL := "openai/gpt-oss-20b"

var _http_request: HTTPRequest
var _busy := false


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)


func is_configured() -> bool:
	return not OS.get_environment("GROQ_API_KEY").strip_edges().is_empty()


func is_busy() -> bool:
	return _busy


func generate_text(system_prompt: String, user_prompt: String) -> bool:
	if _busy:
		request_failed.emit("Groq-запрос уже выполняется")
		return false

	var api_key := OS.get_environment("GROQ_API_KEY").strip_edges()
	if api_key.is_empty():
		request_failed.emit("Переменная окружения GROQ_API_KEY не задана")
		return false

	var model := OS.get_environment("GROQ_MODEL").strip_edges()
	if model.is_empty():
		model = DEFAULT_MODEL

	var payload := {
		"model": model,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
		"temperature": 0.7,
		"max_completion_tokens": 256,
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])
	var error := _http_request.request(
		API_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		request_failed.emit("Не удалось запустить Groq-запрос: %s" % error_string(error))
		return false

	_busy = true
	return true


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Сетевая ошибка Groq: код %d" % result)
		return

	var parsed := parse_completion_response(response_code, body)
	if parsed.ok:
		response_received.emit(parsed.text)
	else:
		request_failed.emit(parsed.error)


static func parse_completion_response(response_code: int, body: PackedByteArray) -> Dictionary:
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Groq вернул некорректный JSON"}

	if response_code < 200 or response_code >= 300:
		var api_error := "HTTP %d" % response_code
		var error_data: Variant = data.get("error", {})
		if typeof(error_data) == TYPE_DICTIONARY:
			api_error = str(error_data.get("message", api_error))
		return {"ok": false, "error": "Ошибка Groq: %s" % api_error}

	var choices: Variant = data.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return {"ok": false, "error": "В ответе Groq нет вариантов текста"}

	var first_choice: Variant = choices[0]
	if typeof(first_choice) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Некорректный формат ответа Groq"}
	var message: Variant = first_choice.get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		return {"ok": false, "error": "В ответе Groq нет сообщения"}
	var content := str(message.get("content", "")).strip_edges()
	if content.is_empty():
		return {"ok": false, "error": "Groq вернул пустой текст"}

	return {"ok": true, "text": content}
