class_name ActivityCatalog
extends RefCounted

const ActivitySpecScript := preload("res://activities/activity_spec.gd")


static func build_specs() -> Array[ActivitySpec]:
	var definitions: Array[Dictionary] = [
		_spec("WORK", "занят рабочей задачей", [], 0, 288, 12, 0.82, ["WORK", "PURPOSE"], "WORK", 0, 0.01, 0.04),
		_spec("TEAMWORK", "обсуждает задачу с коллегами", [], 0, 288, 12, 0.68, ["WORK", "SOCIAL", "PURPOSE"], "WORK", 0, -0.01, 0.05, 2),
		_spec("WORK_BREAK", "делает короткий перерыв", [], 0, 288, 6, 0.80, ["WORK", "RECOVERY"], "WORK", 0, -0.05, -0.01),
		_spec("HOME", "занимается домашними делами", [], 0, 288, 18, 0.90, ["HOME", "SECURITY"], "HOME", 0, -0.02, -0.01),
		_spec("REST", "отдыхает дома", [], 252, 84, 36, 0.78, ["HOME", "RECOVERY"], "HOME", 0, -0.09, -0.04),
		_spec("ERRANDS", "делает покупки", [5], 108, 246, 18, 0.46, ["MONEY", "ERRAND"], "FREE", 140, 0.01, 0.02),
		_spec("CAFE_MEAL", "обедает в кафе", [2], 120, 204, 12, 0.50, ["RECOVERY", "SOCIAL", "COST"], "FREE", 220, -0.04, 0.01),
		_spec("LEISURE", "гуляет в парке", [4], 84, 252, 18, 0.48, ["RECOVERY", "OUTDOOR"], "FREE", 0, -0.06, 0.03),
		_spec("EXERCISE", "занимается физическими упражнениями", [4], 72, 240, 18, 0.38, ["HEALTH", "OUTDOOR"], "FREE", 0, -0.04, 0.09),
		_spec("SOCIAL", "встречается со знакомыми", [2, 4, 6], 102, 258, 18, 0.43, ["SOCIAL"], "FREE", 90, -0.05, 0.03, 2),
		_spec("COMMUNITY", "помогает в общественном центре", [6], 84, 228, 24, 0.34, ["SOCIAL", "PURPOSE", "COMMUNITY"], "FREE", 0, -0.02, 0.06, 2),
		_spec("HEALTH", "занимается вопросами здоровья", [7], 96, 216, 18, 0.50, ["HEALTH", "SECURITY"], "FREE", 120, -0.07, -0.02),
		_spec("CRAFT", "работает над личным проектом", [8], 90, 252, 24, 0.36, ["PURPOSE", "CURIOUS"], "FREE", 80, -0.02, 0.06),
		_spec("JOB_SEARCH", "ищет подходящую работу", [6, 2], 84, 210, 24, 0.64, ["MONEY", "PURPOSE"], "FREE", 0, 0.02, 0.05, 1, ["UNEMPLOYED"]),
		_spec("VISIT_FRIEND", "заходит к знакомому", [2, 4, 6], 150, 258, 18, 0.31, ["SOCIAL", "RECOVERY"], "FREE", 60, -0.06, 0.02, 2),
		_spec("STUDY", "изучает полезные материалы", [6, 2], 78, 240, 24, 0.33, ["CURIOUS", "PURPOSE"], "FREE", 40, 0.00, 0.04),
	]
	var result: Array[ActivitySpec] = []
	for definition: Dictionary in definitions:
		result.append(ActivitySpecScript.new().configure(definition))
	return result


static func _spec(
	id: String, label: String, place_ids: Array, window_start: int, window_end: int,
	duration_ticks: int, base_utility: float, tags: Array, obligation: String,
	money_cost_cents: int, stress_delta: float, activity_delta: float,
	min_participants: int = 1, allowed_schedules: Array = []
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"place_ids": place_ids,
		"window_start": window_start,
		"window_end": window_end,
		"duration_ticks": duration_ticks,
		"base_utility": base_utility,
		"tags": tags,
		"obligation": obligation,
		"money_cost_cents": money_cost_cents,
		"stress_delta": stress_delta,
		"activity_delta": activity_delta,
		"min_participants": min_participants,
		"allowed_schedules": allowed_schedules,
	}
