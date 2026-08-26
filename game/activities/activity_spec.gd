class_name ActivitySpec
extends Resource

const TAG_BITS := {
	"RECOVERY": 1,
	"SOCIAL": 2,
	"PURPOSE": 4,
	"CURIOUS": 8,
	"MONEY": 16,
	"HEALTH": 32,
	"COMMUNITY": 64,
	"WORK": 128,
}

var id: String
var label: String
var place_ids: Array[int]
var window_start: int
var window_end: int
var duration_ticks: int
var base_utility: float
var tags: Array[String]
var allowed_schedules: Array[String]
var obligation: String
var money_cost_cents: int
var stress_delta: float
var activity_delta: float
var min_participants: int
var tag_mask: int = 0
var stable_hash: int = 0


func configure(data: Dictionary) -> ActivitySpec:
	id = str(data.id)
	label = str(data.label)
	place_ids = []
	for value: Variant in data.get("place_ids", []):
		place_ids.append(int(value))
	window_start = int(data.get("window_start", 0))
	window_end = int(data.get("window_end", 288))
	duration_ticks = int(data.get("duration_ticks", 12))
	base_utility = float(data.get("base_utility", 0.5))
	tags = []
	for value: Variant in data.get("tags", []):
		tags.append(str(value))
		tag_mask = tag_mask | int(TAG_BITS.get(str(value), 0))
	allowed_schedules = []
	for value: Variant in data.get("allowed_schedules", []):
		allowed_schedules.append(str(value))
	obligation = str(data.get("obligation", "FREE"))
	money_cost_cents = int(data.get("money_cost_cents", 0))
	stress_delta = float(data.get("stress_delta", 0.0))
	activity_delta = float(data.get("activity_delta", 0.0))
	min_participants = int(data.get("min_participants", 1))
	stable_hash = id.hash()
	return self


func is_in_time_window(time_of_day: int) -> bool:
	if window_start <= window_end:
		return time_of_day >= window_start and time_of_day < window_end
	return time_of_day >= window_start or time_of_day < window_end


func allows_schedule(schedule_kind: String) -> bool:
	return allowed_schedules.is_empty() or schedule_kind in allowed_schedules
