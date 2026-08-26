class_name LightSchedule
extends RefCounted

const DAY_TICKS := 288
const START_CLOCK_TICK := 120 # The playable slice starts at 10:00.


static func resolve_place(
	schedule_kind: String,
	tick: int,
	home_place_id: int,
	work_place_id: int
) -> int:
	return int(resolve_state(schedule_kind, tick, home_place_id, work_place_id).place_id)


static func resolve_state(
	schedule_kind: String,
	tick: int,
	home_place_id: int,
	work_place_id: int
) -> Dictionary:
	var time_of_day := posmod(tick + START_CLOCK_TICK, DAY_TICKS)
	match schedule_kind:
		"DAY_WORK":
			if time_of_day >= 84 and time_of_day < 204:
				return _state(work_place_id, "WORK", "работает")
			if time_of_day >= 204 and time_of_day < 228:
				return _state(5, "ERRANDS", "занимается покупками")
			if time_of_day >= 228 and time_of_day < 246:
				return _state(4, "LEISURE", "отдыхает в парке")
			return _state(home_place_id, "HOME", "проводит время дома")
		"EVENING_SHIFT":
			if time_of_day >= 96 and time_of_day < 126:
				return _state(4, "LEISURE", "гуляет в парке")
			if time_of_day >= 126 and time_of_day < 150:
				return _state(5, "ERRANDS", "занимается делами")
			if time_of_day >= 156 and time_of_day < 264:
				return _state(work_place_id, "WORK", "работает в вечернюю смену")
			return _state(home_place_id, "HOME", "проводит время дома")
		"FLEXIBLE":
			if time_of_day >= 90 and time_of_day < 114:
				return _state(6, "COMMUNITY", "занимается делами в общественном центре")
			if time_of_day >= 120 and time_of_day < 192:
				return _state(work_place_id, "WORK", "работает по гибкому графику")
			if time_of_day >= 192 and time_of_day < 216:
				return _state(5, "ERRANDS", "заходит в магазины")
			if time_of_day >= 216 and time_of_day < 240:
				return _state(4, "LEISURE", "встречается с людьми в парке")
			return _state(home_place_id, "HOME", "проводит время дома")
		_:
			if time_of_day >= 96 and time_of_day < 126:
				return _state(6, "JOB_SEARCH", "ищет работу в общественном центре")
			if time_of_day >= 132 and time_of_day < 156:
				return _state(2, "SOCIAL", "общается в кафе")
			if time_of_day >= 156 and time_of_day < 174:
				return _state(5, "ERRANDS", "занимается покупками")
			if time_of_day >= 174 and time_of_day < 210:
				return _state(4, "LEISURE", "проводит время в парке")
			return _state(home_place_id, "HOME", "проводит время дома")


static func _state(place_id: int, activity: String, label: String) -> Dictionary:
	return {"place_id": place_id, "activity": activity, "activity_label": label}
