extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const GroqClientScript := preload("res://llm/groq_client.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")


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
	if not _assert_social_rendering_pipeline():
		return

	var groq_fixture := JSON.stringify({
		"choices": [{"message": {"content": "Renderer ready"}}]
	}).to_utf8_buffer()
	var parsed: Dictionary = GroqClientScript.parse_completion_response(200, groq_fixture)
	if not parsed.ok or parsed.text != "Renderer ready":
		push_error("Groq response parsing failed: %s" % parsed)
		quit(1)
		return
	var truncated_fixture := JSON.stringify({
		"choices": [{
			"finish_reason": "length",
			"message": {"content": "Извини, но я не могу об"},
		}]
	}).to_utf8_buffer()
	var truncated: Dictionary = GroqClientScript.parse_completion_response(200, truncated_fixture)
	if truncated.ok:
		push_error("Groq parser accepted a token-truncated response")
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
	if state.place_count < 3:
		return _fail("Expected at least 3 places, got %d" % state.place_count)
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


func _assert_social_rendering_pipeline() -> bool:
	var world := SimulationWorldScript.new(42)
	var event_count_before: int = world.snapshot().event_count
	var result: Dictionary = world.perform_social_action(
		"AskAbout",
		world.player_id,
		2,
		{"topic": "Aurora"}
	)
	if not result.get("ok", false):
		return _fail("AskAbout pipeline failed: %s" % result)
	if result.decision.decision != "REFUSE":
		return _fail("Initial Anna decision should be REFUSE, got %s" % result.decision.decision)
	if result.communicative_act.act != "REFUSE_REQUEST":
		return _fail("CommunicativeAct does not preserve the simulated refusal")
	if result.template_response.strip_edges().is_empty():
		return _fail("Template renderer returned an empty response")
	if world.snapshot().event_count != event_count_before + 1:
		return _fail("Social action did not create one structured event")

	var prompt: String = SocialRendererScript.build_user_prompt(
		{"name": "Anna", "role": "designer"},
		result.communicative_act,
		{"location": "Corner Cafe"}
	)
	if prompt.contains("Sergey"):
		return _fail("LLM prompt leaked an undisclosed social connection")

	var conflicting := SocialRendererScript.sanitize_output(
		"Я согласна, конечно, помогу.",
		result.communicative_act,
		result.template_response
	)
	if conflicting != result.template_response:
		return _fail("Semantic validator accepted text contradicting REFUSE")
	var unfinished := SocialRendererScript.sanitize_output(
		"Извини, но я не могу об",
		result.communicative_act,
		result.template_response
	)
	if unfinished != result.template_response:
		return _fail("Social renderer accepted an unfinished sentence")
	var valid_refusal := "Я не готова сейчас вмешивать других людей."
	if SocialRendererScript.sanitize_output(
		valid_refusal,
		result.communicative_act,
		result.template_response
	) != valid_refusal:
		return _fail("Semantic validator rejected a valid refusal")

	var favor: Dictionary = world.perform_social_action(
		"AskFavor", world.player_id, 2, {"topic": "Aurora Party"}
	)
	if not favor.get("ok", false) or favor.decision.decision != "REFUSE":
		return _fail("AskFavor did not pass through the deterministic refusal pipeline")
	var premature_introduction: Dictionary = world.perform_social_action(
		"AskIntroduction", world.player_id, 2, {"subject_person_id": 3}
	)
	if premature_introduction.get("ok", false):
		return _fail("AskIntroduction bypassed undiscovered social knowledge")
	if premature_introduction.error != "INTRODUCTION_SUBJECT_NOT_DISCOVERED":
		return _fail("AskIntroduction failed for the wrong precondition")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
