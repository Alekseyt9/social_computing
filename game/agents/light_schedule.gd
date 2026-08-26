class_name LightSchedule
extends RefCounted

const DAY_TICKS := 288


static func resolve_place(
	schedule_kind: String,
	tick: int,
	home_place_id: int,
	work_place_id: int
) -> int:
	var time_of_day := tick % DAY_TICKS
	match schedule_kind:
		"DAY_WORK":
			return work_place_id if time_of_day >= 96 and time_of_day < 204 else home_place_id
		"EVENING_SHIFT":
			return work_place_id if time_of_day >= 156 and time_of_day < 264 else home_place_id
		"FLEXIBLE":
			return work_place_id if time_of_day >= 120 and time_of_day < 192 else home_place_id
		_:
			# Unemployed agents still visit the cafe during the afternoon.
			return 2 if time_of_day >= 132 and time_of_day < 168 else home_place_id
