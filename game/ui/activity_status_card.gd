class_name ActivityStatusCard
extends PanelContainer

var _activity_label: Label
var _phase_label: Label
var _details_label: Label
var _progress: ProgressBar


func _ready() -> void:
	name = "ActivityStatusCard"
	custom_minimum_size = Vector2(0, 82)
	add_theme_stylebox_override(
		"panel", _style(Color("17262c"), Color("4e747b"), 10)
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_activity_label = Label.new()
	_activity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity_label.add_theme_font_size_override("font_size", 15)
	_activity_label.add_theme_color_override("font_color", Color("edf3e9"))
	top.add_child(_activity_label)
	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", 12)
	top.add_child(_phase_label)
	_details_label = Label.new()
	_details_label.add_theme_font_size_override("font_size", 11)
	_details_label.add_theme_color_override("font_color", Color("a9c0c2"))
	_details_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_details_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 7)
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background", _style(Color("0e171a"), Color("263a3f"), 4))
	_progress.add_theme_stylebox_override("fill", _style(Color("62bdc5"), Color("7ed5d9"), 4))
	box.add_child(_progress)
	clear_activity()


func set_activity(state: Dictionary) -> void:
	if state.is_empty():
		clear_activity()
		return
	visible = true
	var phase := str(state.get("execution_phase", "PERFORM"))
	_activity_label.text = "ЗАНЯТИЕ · %s" % str(state.get("activity_label", "текущее дело"))
	_phase_label.text = str(state.get("phase_label", phase))
	_phase_label.add_theme_color_override("font_color", _phase_color(phase))
	var details := PackedStringArray()
	var action := _visual_action_label(str(state.get("visual_action", "IDLE")))
	if not action.is_empty():
		details.append(action)
	var spot_id := str(state.get("activity_spot_id", ""))
	if not spot_id.is_empty():
		details.append("точка %s" % spot_id.get_slice("-", 1))
	var ends_tick := int(state.get("plan_ends_tick", -1))
	if ends_tick >= 0:
		details.append("до тика %d" % ends_tick)
	_details_label.text = " · ".join(details)
	_progress.value = clampf(float(state.get("phase_progress", 0.0)), 0.0, 1.0) * 100.0


func clear_activity() -> void:
	visible = false
	if _activity_label != null:
		_activity_label.text = ""
		_phase_label.text = ""
		_details_label.text = ""
		_progress.value = 0.0


func get_activity_text() -> String:
	return _activity_label.text if _activity_label != null else ""


func get_phase_text() -> String:
	return _phase_label.text if _phase_label != null else ""


func get_progress_value() -> float:
	return _progress.value if _progress != null else 0.0


func _phase_color(phase: String) -> Color:
	return {
		"TRAVEL": Color("87bdd9"),
		"RESERVE": Color("e1bf72"),
		"PERFORM": Color("81d19a"),
		"FINISH": Color("b9a5dc"),
		"INTERRUPT": Color("e28379"),
	}.get(phase, Color("a9c0c2"))


func _visual_action_label(action: String) -> String:
	return {
		"WALK": "направляется к цели",
		"APPROACH_SPOT": "занимает рабочую точку",
		"LEAVE_SPOT": "освобождает место",
		"TYPE": "работает за терминалом",
		"TALK": "общается",
		"DRINK": "пьёт",
		"CHORES": "занимается делами",
		"SIT": "отдыхает",
		"BROWSE": "осматривает товары",
		"EAT": "ест",
		"STROLL": "гуляет",
		"EXERCISE": "тренируется",
		"HELP": "помогает",
		"WAIT": "ожидает",
		"CRAFT": "мастерит",
		"READ": "читает",
	}.get(action, "")


func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style
