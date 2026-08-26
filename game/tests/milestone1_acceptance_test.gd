extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const SocialRendererScript := preload("res://rendering/social_renderer.gd")


func _init() -> void:
	_run()


func _run() -> void:
	if not _assert_world_and_planner():
		return
	if not _assert_knowledge_map_and_conversation():
		return
	if not _assert_relationship_unlocks_access():
		return
	var routes := {
		4: "GUEST_INVITATION",
		13: "MEDIA_PASS",
		10: "CONTRACTOR_BADGE",
	}
	for issuer_id: int in routes:
		if not _complete_access_route(issuer_id, str(routes[issuer_id])):
			return
	print("MILESTONE1_OK npc=20 strategies=3 access_types=%s headless=true" % [
		str(routes.values()),
	])
	quit(0)


func _assert_world_and_planner() -> bool:
	var world := SimulationWorldScript.new(20250308)
	var state: Dictionary = world.snapshot()
	if state.npc_count != 20 or state.place_count < 3 or state.organization_count != 2:
		return _fail("MS1 world shape lost its required 20 NPC / 3+ places / 2 organizations: %s" % state)
	var report: Dictionary = world.get_goal_reachability_report()
	if not report.reachable or int(report.strategy_count) != 3:
		return _fail("Bounded Goal Solver did not find three strategies: %s" % report)
	var names: Array[String] = []
	for strategy: Dictionary in report.strategies:
		names.append(str(strategy.strategy))
		if strategy.path.size() > 6:
			return _fail("Goal Solver exceeded its bounded depth")
	for expected: String in ["PERSONAL_INVITATION", "MEDIA_ACCESS", "SERVICE_PROVIDER"]:
		if expected not in names:
			return _fail("Missing strategy %s in %s" % [expected, names])
	return true


func _assert_knowledge_map_and_conversation() -> bool:
	var world := SimulationWorldScript.new(42)
	var hidden_fact_id: int = world.get_relationship_fact_id(2, 3)
	if world.person_knows_fact(world.player_id, hidden_fact_id):
		return _fail("Player initially knows hidden Anna -> Sergey link")
	var initial_map: Dictionary = world.get_social_map_view(world.player_id)
	if _map_has_node(initial_map, "person:3"):
		return _fail("Social Map leaked hidden Sergey node")
	var refusal: Dictionary = world.perform_social_action(
		"AskAbout", world.player_id, 2, {"topic": "Aurora"}
	)
	if not refusal.ok or refusal.decision.decision != "REFUSE":
		return _fail("Expected a computed initial refusal from Anna: %s" % refusal)
	if str(refusal.decision.primary_reason.get("type", "")).is_empty():
		return _fail("Refusal has no concrete computed reason")
	var context: Dictionary = world.get_conversation_context(world.player_id, 2)
	if context.previous_acts.size() != 1 or context.emotional_tone != "TENSE":
		return _fail("Conversation state did not record the refusal: %s" % context)
	if JSON.stringify(context).contains("Sergey"):
		return _fail("Observer-safe conversation context leaked Sergey")
	if not world.reveal_fact_to(world.player_id, hidden_fact_id, 2, 0.9):
		return _fail("Could not disclose a canonical relationship fact")
	var revealed_map: Dictionary = world.get_social_map_view(world.player_id)
	if not _map_has_node(revealed_map, "person:3"):
		return _fail("Disclosed relationship did not appear on Social Map")
	var contradicted := SocialRendererScript.sanitize_output(
		"Я согласна, конечно, помогу.", refusal.communicative_act, refusal.template_response
	)
	if contradicted != refusal.template_response:
		return _fail("LLM wording overrode the simulation decision")
	var unfinished := SocialRendererScript.sanitize_output(
		"Извини, но я не могу об", refusal.communicative_act, refusal.template_response
	)
	if unfinished != refusal.template_response:
		return _fail("Truncated LLM text bypassed the local fallback")
	var metrics: Dictionary = world.get_metrics()
	if int(metrics.interactions) < 1 or world.get_recent_events(5).is_empty():
		return _fail("Key interactions were not logged or measured")
	return true


func _assert_relationship_unlocks_access() -> bool:
	var world := SimulationWorldScript.new(77)
	var actor_id: int = world.player_id
	var contact_id := 2
	var subject_id := 3
	var link_fact_id: int = world.get_relationship_fact_id(contact_id, subject_id)
	world.reveal_fact_to(actor_id, link_fact_id, contact_id, 0.9)
	var request := _find_action(world.get_available_social_actions(actor_id, contact_id), "AskIntroduction")
	if request.is_empty():
		return _fail("Disclosed relationship did not expose AskIntroduction")
	var first: Dictionary = _perform(world, actor_id, contact_id, request)
	if first.decision.decision == "ACCEPT":
		return _fail("Low-trust contact introduced the player before relationship change")
	for _index in range(30):
		_perform_type(world, actor_id, contact_id, "BuildRapport")
	var second: Dictionary = _perform(world, actor_id, contact_id, request)
	if second.decision.decision != "ACCEPT" or not world.is_person_known_to(actor_id, subject_id):
		return _fail("Improved relationship did not unlock introduction: %s" % second)
	return true


func _complete_access_route(issuer_id: int, expected_type: String) -> bool:
	var world := SimulationWorldScript.new(1000 + issuer_id)
	var actor_id: int = world.player_id
	if not world.introduce_people(actor_id, issuer_id).ok:
		return _fail("Could not meet issuer %d" % issuer_id)
	for _attempt in range(14):
		var actions: Array[Dictionary] = world.get_available_social_actions(actor_id, issuer_id)
		var request := _find_action(actions, "RequestAccess")
		if not request.is_empty():
			var result := _perform(world, actor_id, issuer_id, request)
			if result.decision.decision == "ACCEPT":
				break
		var ask := _find_action(actions, "AskAbout")
		if not ask.is_empty():
			_perform(world, actor_id, issuer_id, ask)
		_perform_type(world, actor_id, issuer_id, "BuildRapport")
	if expected_type not in world.get_aurora_access_types(actor_id):
		return _fail("Route through issuer %d did not grant %s" % [issuer_id, expected_type])
	var entry: Dictionary = world.attempt_enter_aurora(actor_id)
	if not entry.ok or str(world.get_goal_state(actor_id).stage) != "COMPLETED":
		return _fail("Credential %s did not allow entry" % expected_type)
	return true


func _map_has_node(graph: Dictionary, node_id: String) -> bool:
	for node: Dictionary in graph.nodes:
		if str(node.id) == node_id:
			return true
	return false


func _find_action(actions: Array[Dictionary], action_type: String) -> Dictionary:
	for action: Dictionary in actions:
		if str(action.get("type", "")) == action_type:
			return action
	return {}


func _perform_type(world: RefCounted, actor_id: int, target_id: int, action_type: String) -> bool:
	var action := _find_action(world.get_available_social_actions(actor_id, target_id), action_type)
	if action.is_empty():
		return false
	return bool(_perform(world, actor_id, target_id, action).get("ok", false))


func _perform(world: RefCounted, actor_id: int, target_id: int, action: Dictionary) -> Dictionary:
	return world.perform_social_action(str(action.type), actor_id, target_id, action.get("context", {}))


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
