class_name ConversationModel
extends RefCounted

## Bounded dialogue state owned by the simulation. It stores references to
## canonical facts; observer-facing queries decide which summaries are safe.

var participant_ids: Array[int]
var active_topics: Array[String] = []
var recently_mentioned_fact_ids: Array[int] = []
var emotional_tone: String = "NEUTRAL"
var previous_acts: Array[Dictionary] = []


func _init(first_person_id: int, second_person_id: int) -> void:
	participant_ids = [first_person_id, second_person_id]


func record(
	action_type: String,
	act: Dictionary,
	fact_ids: Array[int],
	tone: String
) -> void:
	var topic := str(act.get("topic", "")).strip_edges()
	if not topic.is_empty():
		active_topics.erase(topic)
		active_topics.push_front(topic)
		if active_topics.size() > 4:
			active_topics.resize(4)
	for fact_id: int in fact_ids:
		recently_mentioned_fact_ids.erase(fact_id)
		recently_mentioned_fact_ids.push_front(fact_id)
	if recently_mentioned_fact_ids.size() > 8:
		recently_mentioned_fact_ids.resize(8)
	emotional_tone = tone
	previous_acts.append({
		"action_type": action_type,
		"act": str(act.get("act", "")),
		"decision": str(act.get("decision", "")),
		"topic": topic,
	})
	if previous_acts.size() > 6:
		previous_acts.pop_front()
