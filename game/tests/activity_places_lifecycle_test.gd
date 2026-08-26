extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _test_contextual_activity():
		return
	await _test_place_and_active_lifecycle()


func _test_contextual_activity() -> bool:
	var world := SimulationWorldScript.new(310031)
	world.advance(96) # 18:00: day workers perform errands in the shops.
	var agent_id := -1
	for candidate_id: int in world.get_adaptive_population_snapshot().refined_light_ids:
		if str(world.get_light_agent_view(candidate_id).current_activity) == "ERRANDS":
			agent_id = candidate_id
			break
	if agent_id == -1:
		_fail("No calculated errands activity is available")
		return false
	world.activate_light_agent_as_person(agent_id, "PLAYER_INTERACTION")
	world.introduce_people(world.player_id, agent_id)
	# At the decision boundary the NPC first travels and reserves a spot.
	# Joining becomes available only once the modeled activity reaches PERFORM.
	world.advance(4)
	var actions: Array[Dictionary] = world.get_available_social_actions(
		world.player_id, agent_id
	)
	var contextual_action: Dictionary = {}
	for action: Dictionary in actions:
		if str(action.type) == "JoinActivity":
			contextual_action = action
			break
	if contextual_action.is_empty() or str(contextual_action.context.activity) != "ERRANDS":
		_fail("Dialogue actions did not reflect the NPC's current calculated activity")
		return false
	var total_money_before := int(world.get_light_population_snapshot().total_money_cents)
	var agent_money_before := int(world.get_light_agent_view(agent_id).money_cents)
	var relationship_before := world.get_relationship_state(agent_id, world.player_id)
	var resources_before := float(world.get_need_profile(agent_id).scores.RESOURCES)
	var result: Dictionary = world.perform_social_action(
		"JoinActivity", world.player_id, agent_id, contextual_action.context
	)
	if not result.ok or str(result.decision.decision) != "ACCEPT":
		_fail("Contextual activity was not resolved by DecisionEngine: %s" % result)
		return false
	var shared_effect: Dictionary = {}
	for effect: Dictionary in result.effects:
		if str(effect.type) == "ACTIVITY_SHARED":
			shared_effect = effect
			break
	if shared_effect.is_empty() or int(shared_effect.money_delta_cents) >= 0:
		_fail("Shopping activity produced no modeled spending effect: %s" % result.effects)
		return false
	var total_money_after := int(world.get_light_population_snapshot().total_money_cents)
	var agent_money_after := int(world.get_light_agent_view(agent_id).money_cents)
	var relationship_after := world.get_relationship_state(agent_id, world.player_id)
	var resources_after := float(world.get_need_profile(agent_id).scores.RESOURCES)
	if total_money_before != total_money_after or agent_money_after >= agent_money_before:
		_fail("Contextual spending broke conservation or did not change the participant")
		return false
	if float(relationship_after.trust) <= float(relationship_before.trust) or (
		resources_after >= resources_before
	):
		_fail("Shared activity did not affect relationship and modeled needs")
		return false
	return true


func _test_place_and_active_lifecycle() -> void:
	var packed_scene := load("res://Main.tscn") as PackedScene
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._enter_place(2)
	await process_frame
	if int(scene._current_interior.id) != 2 or scene._world_map.visible or (
		not scene._interior_map.visible
	):
		_fail("Cafe entrance did not switch to a playable interior")
		return
	if scene.world.get_current_place_id(scene.world.player_id) != 2:
		_fail("Cafe entry was not recorded in canonical world state")
		return
	var crowd: Node = scene.get_node("AmbientCrowd")
	if int(crowd.get_visible_count()) <= 0:
		_fail("Cafe interior contains no schedule-selected visitors")
		return
	var agent_id := -1
	var destination_place_id := -1
	var destination_activity := ""
	for candidate_id: int in crowd.get_visible_citizen_ids():
		var future: Dictionary = scene.world.get_light_agent_schedule_state(
			candidate_id, int(scene.world.tick) + 96
		)
		if (
			str(scene.world.get_light_agent_view(candidate_id).schedule_kind) == "DAY_WORK"
			and int(future.place_id) in [5, 6, 7, 8]
		):
			agent_id = candidate_id
			destination_place_id = int(future.place_id)
			destination_activity = str(future.activity)
			break
	if agent_id == -1:
		_fail("Cafe interior has no day worker for lifecycle test")
		return
	var activation: Dictionary = scene.world.activate_light_agent_as_person(
		agent_id, "PLAYER_INTERACTION"
	)
	if not activation.ok:
		_fail("Could not promote an interior visitor")
		return
	crowd.sync_from_simulation()
	scene._sync_active_adaptive_npcs()
	await process_frame
	if scene.get_active_adaptive_npc_count() != 1:
		_fail("Persistent person was not materialized as ActiveNPC inside cafe")
		return
	var stable_name: String = scene.world.get_person_name(agent_id)
	scene.world.advance(96) # Utility model selects the worker's next valid activity.
	scene._update_adaptive_focus(true)
	await process_frame
	if scene.get_active_adaptive_npc_count() != 0 or not scene.world.has_person(agent_id):
		_fail("Offscreen ActiveNPC did not dematerialize while retaining identity")
		return
	scene._exit_place()
	scene._enter_place(destination_place_id)
	await process_frame
	if scene.get_active_adaptive_npc_count() != 1 or (
		scene.world.get_person_name(agent_id) != stable_name
	):
		_fail("PersistentNPC did not rematerialize at its scheduled destination")
		return
	if scene.world.get_light_agent_tier(agent_id) != "PERSISTENT_NPC":
		_fail("Active lifecycle changed the canonical adaptive tier")
		return
	if scene.world.get_current_place_id(scene.world.player_id) != destination_place_id:
		_fail("Computed destination entry was not recorded in canonical world state")
		return
	print("ACTIVITY_PLACES_OK context=%s destination=%d money_conserved=true interiors=5 active_to_persistent_to_active=true person=%d" % [
		destination_activity, destination_place_id, agent_id,
	])
	scene.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
