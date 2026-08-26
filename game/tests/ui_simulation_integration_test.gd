extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://Main.tscn") as PackedScene
	if packed_scene == null:
		_fail("Could not load Main.tscn")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	for required_path: String in [
		"HUD/DistrictPulse", "HUD/NewsFeed", "HUD/ConsequenceToast",
		"HUD/SaveLoadMenu", "HUD/StartMenu", "HUD/SocialJournal",
		"HUD/DistrictMinimapPanel/MinimapContent/DistrictMinimap", "AmbientCrowd", "PlaceInterior",
	]:
		if scene.get_node_or_null(required_path) == null:
			_fail("Player-facing UI node is missing: %s" % required_path)
			return
	if not scene._start_menu_overlay.visible or scene.player.input_enabled:
		_fail("Start menu does not pause the game before a new/load choice")
		return
	scene._start_new_game()
	if scene._start_menu_overlay.visible or not scene.player.input_enabled:
		_fail("New Game did not enter the playable world")
		return
	scene._toggle_journal()
	if not scene._journal_overlay.visible or not scene._journal_text.text.contains("районную ярмарку"):
		_fail("Social journal does not expose computed goals and consequences")
		return
	scene._toggle_journal()
	scene._set_time_paused(true)
	if scene.player.input_enabled:
		_fail("Explicit time pause did not freeze player input")
		return
	scene._set_time_paused(false)
	var crowd: Node = scene.get_node("AmbientCrowd")
	if int(crowd.get_visible_count()) <= 0 or int(crowd.get_visible_count()) > 45:
		_fail("Ambient adaptive crowd did not respect its visual budget")
		return
	var ambient_citizen: Dictionary = crowd.get_nearest_citizen(Vector2(900, 600), 5000.0)
	if ambient_citizen.is_empty():
		_fail("Ambient crowd exposes no nearby interactive citizen")
		return
	var ambient_id := int(ambient_citizen.agent_id)
	scene._nearby_light_citizen = ambient_citizen
	scene._activate_nearby_light_citizen()
	await process_frame
	if not scene.world.has_person(ambient_id) or not scene._npc_by_id.has(ambient_id):
		_fail("Ambient citizen was not materialized into a visible persistent NPC")
		return
	if scene.world.get_light_agent_tier(ambient_id) != "PERSISTENT_NPC" or crowd.has_citizen(ambient_id):
		_fail("Interactive citizen is duplicated across ambient and persistent layers")
		return
	scene._close_dialogue()
	var world: RefCounted = scene.world
	var pulse: Dictionary = world.get_district_pulse_view(world.player_id)
	if str(pulse.overall).is_empty() or pulse.signals.size() != 4:
		_fail("District pulse has no qualitative player-facing signals")
		return
	var initial_feed: Array[Dictionary] = world.get_player_news_feed(world.player_id, 6)
	if JSON.stringify(initial_feed).contains("Sergey"):
		_fail("Player news feed leaked a hidden relationship")
		return
	world.advance(72)
	var undisclosed_feed: String = JSON.stringify(world.get_player_news_feed(world.player_id, 12))
	if undisclosed_feed.contains("охват"):
		_fail("Population rumor appeared before an NPC disclosed it")
		return
	var action: Dictionary = world.perform_social_action(
		"BuildRapport", world.player_id, 2, {"topic": "район"}
	)
	if not action.ok:
		_fail("Could not create a player-visible social consequence")
		return
	var updated_feed: Array[Dictionary] = world.get_player_news_feed(world.player_id, 8)
	var saw_conversation := false
	for item: Dictionary in updated_feed:
		if str(item.category) == "SOCIAL":
			saw_conversation = true
			break
	if not saw_conversation:
		_fail("Resolved player action did not enter the news feed")
		return
	print("UI_SIMULATION_OK pulse=4 feed=%d crowd=%d interactive_id=%d hidden_leaks=false" % [
		updated_feed.size(), crowd.get_visible_count(), ambient_id,
	])
	scene.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
