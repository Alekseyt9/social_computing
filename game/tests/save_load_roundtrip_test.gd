extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")
const SaveGameServiceScript := preload("res://core/save_game_service.gd")
const TEST_DIRECTORY := "user://test_saves_roundtrip"


func _init() -> void:
	_run()


func _run() -> void:
	_cleanup()
	var world := SimulationWorldScript.new(909090)
	world.update_adaptive_focus(2, [], 60)
	world.advance(96)
	var agent_id := -1
	for candidate_id: int in world.get_adaptive_population_snapshot().refined_light_ids:
		if str(world.get_light_agent_view(candidate_id).current_activity) == "ERRANDS":
			agent_id = candidate_id
			break
	if agent_id == -1:
		_fail("No contextual agent for save round-trip")
		return
	world.activate_light_agent_as_person(agent_id, "PLAYER_INTERACTION")
	world.introduce_people(world.player_id, agent_id)
	world.advance(4) # Travel/reservation complete; the activity is now interactable.
	var action: Dictionary = {}
	for candidate: Dictionary in world.get_available_social_actions(world.player_id, agent_id):
		if str(candidate.type) == "JoinActivity":
			action = candidate
			break
	if action.is_empty():
		_fail("Contextual activity never reached its perform phase")
		return
	var action_result: Dictionary = world.perform_social_action(
		"JoinActivity", world.player_id, agent_id, action.context
	)
	if not action_result.ok:
		_fail("Could not create social state for save round-trip")
		return
	world.visit_public_place(world.player_id, 5)
	world.apply_district_field_shock({"fear_delta": 0.07, "stress_delta": 0.04})
	world.advance(14 * 288)
	world.get_persistent_background_history(agent_id, world.player_id)
	var view := {
		"player": {"x": 3111.0, "y": 412.0},
		"outdoor_return": {"x": 1370.0, "y": 1025.0},
		"interior_place_id": 5,
		"story_npc_positions": [],
		"simulation_accumulator": 0.35,
	}
	var saved: Dictionary = SaveGameServiceScript.save_slot(
		1, world.export_save_data(), view, TEST_DIRECTORY
	)
	if not saved.ok or not FileAccess.file_exists(str(saved.path)):
		_fail("Save file was not written atomically: %s" % saved)
		return
	var overwritten: Dictionary = SaveGameServiceScript.save_slot(
		1, world.export_save_data(), view, TEST_DIRECTORY
	)
	if not overwritten.ok:
		_fail("Existing save slot could not be replaced safely: %s" % overwritten)
		return
	var autosaved: Dictionary = SaveGameServiceScript.save_slot(
		SaveGameServiceScript.AUTO_SAVE_SLOT, world.export_save_data(), view, TEST_DIRECTORY
	)
	if not autosaved.ok or SaveGameServiceScript.get_latest_save(TEST_DIRECTORY).is_empty():
		_fail("Autosave/latest-save discovery failed")
		return
	var loaded: Dictionary = SaveGameServiceScript.load_slot(1, TEST_DIRECTORY)
	if not loaded.ok or int(loaded.view.interior_place_id) != 5:
		_fail("Save envelope/view state did not load: %s" % loaded)
		return
	var restored: RefCounted = SimulationWorldScript.create_from_save_data(loaded.world)
	if restored == null:
		_fail("World command log failed integrity-checked restore")
		return
	if restored.snapshot() != world.snapshot():
		_fail("Restored canonical snapshot differs from saved world")
		return
	if restored.get_person_name(agent_id) != world.get_person_name(agent_id) or (
		restored.get_relationship_state(agent_id, world.player_id) != world.get_relationship_state(agent_id, world.player_id)
	):
		_fail("Persistent identity or relationship was lost after load")
		return
	if restored.get_persistent_history_profile(agent_id) != world.get_persistent_history_profile(agent_id):
		_fail("Lazy history did not survive save/load")
		return
	if restored.get_current_place_id(world.player_id) != 5:
		_fail("Current canonical place did not survive save/load")
		return
	var corrupted: Dictionary = loaded.world.duplicate(true)
	corrupted.integrity["checksum"] = "corrupted"
	if SimulationWorldScript.create_from_save_data(corrupted) != null:
		_fail("Integrity check accepted corrupted save metadata")
		return
	var command_count: int = loaded.world.commands.size()
	_cleanup()
	print("SAVE_LOAD_OK slot=1 commands=%d tick=%d person=%d interior=5 checksum=%s" % [
		command_count, restored.tick, agent_id, str(restored.snapshot().checksum),
	])
	quit(0)


func _cleanup() -> void:
	var slot_path := ProjectSettings.globalize_path("%s/slot_1.json" % TEST_DIRECTORY)
	var temp_path := slot_path + ".tmp"
	var backup_path := slot_path + ".bak"
	var autosave_path := ProjectSettings.globalize_path("%s/autosave.json" % TEST_DIRECTORY)
	if FileAccess.file_exists(slot_path):
		DirAccess.remove_absolute(slot_path)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(autosave_path):
		DirAccess.remove_absolute(autosave_path)
	var directory_path := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(directory_path):
		DirAccess.remove_absolute(directory_path)


func _fail(message: String) -> void:
	_cleanup()
	push_error(message)
	quit(1)
