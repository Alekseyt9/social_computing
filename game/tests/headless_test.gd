extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var first := SimulationWorldScript.new(42)
	var second := SimulationWorldScript.new(42)

	first.advance(15)
	var first_result: Dictionary = first.advance(45)
	var second_result: Dictionary = second.advance(60)

	if first_result != second_result:
		push_error("Determinism test failed: %s != %s" % [first_result, second_result])
		quit(1)
		return

	var different_seed: Dictionary = SimulationWorldScript.new(43).advance(60)
	if first_result.checksum == different_seed.checksum:
		push_error("Different seeds produced the same checksum")
		quit(1)
		return

	var scenario_world := SimulationWorldScript.new(42)
	if not _assert_world_shape(scenario_world):
		return
	if not _assert_knowledge_isolation(scenario_world):
		return

	var groq_fixture := JSON.stringify({
		"choices": [{"message": {"content": "Renderer ready"}}]
	}).to_utf8_buffer()
	var parsed: Dictionary = GroqClientScript.parse_completion_response(200, groq_fixture)
	if not parsed.ok or parsed.text != "Renderer ready":
		push_error("Groq response parsing failed: %s" % parsed)
		quit(1)
		return

	print("SMOKE_TEST_OK tick=%d checksum=%s" % [
		first_result.tick,
		first_result.checksum,
	])
	quit(0)


func _assert_world_shape(world: RefCounted) -> bool:
	var state: Dictionary = world.snapshot()
	if state.npc_count != 20:
		return _fail("Expected 20 NPC, got %d" % state.npc_count)
	if state.place_count != 3:
		return _fail("Expected 3 places, got %d" % state.place_count)
	if state.organization_count != 2:
		return _fail("Expected 2 organizations, got %d" % state.organization_count)
	if not world.has_person(21):
		return _fail("Persistent NPC id 21 is missing")
	return true


func _assert_knowledge_isolation(world: RefCounted) -> bool:
	var anna_sergey_fact: int = world.get_relationship_fact_id(2, 3)
	var sergey_maria_fact: int = world.get_relationship_fact_id(3, 4)

	if not world.has_relationship(2, 3) or not world.has_relationship(3, 4):
		return _fail("Canonical social route is missing from world truth")
	if world.person_knows_fact(world.player_id, anna_sergey_fact):
		return _fail("Player can see the hidden Anna -> Sergey relationship")
	if world.person_knows_fact(world.player_id, sergey_maria_fact):
		return _fail("Player can see the hidden Sergey -> Maria relationship")
	if not world.person_knows_fact(2, anna_sergey_fact):
		return _fail("Anna does not know her own connection to Sergey")
	if not world.person_knows_fact(3, sergey_maria_fact):
		return _fail("Sergey does not know his own connection to Maria")

	var initial_view: Dictionary = world.get_observer_view(world.player_id)
	if initial_view.known_relationships.size() != 1:
		return _fail("Player should initially see exactly one relationship")
	if initial_view.known_contact_names != ["Anna"]:
		return _fail("Player should initially know only Anna")

	if not world.reveal_fact_to(world.player_id, anna_sergey_fact, 2, 0.9):
		return _fail("Could not reveal an existing fact to the player")
	var revealed_view: Dictionary = world.get_observer_view(world.player_id)
	if revealed_view.known_relationships.size() != 2:
		return _fail("Revealed relationship did not enter the player view")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
