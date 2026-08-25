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
	var players := get_nodes_in_group("player")
	var npcs := get_nodes_in_group("npc")
	if players.size() != 1:
		_fail("Expected one player, got %d" % players.size())
		return
	if npcs.size() < 6:
		_fail("Expected a populated district, got %d NPCs" % npcs.size())
		return
	if scene.get_node_or_null("WorldMap") == null:
		_fail("WorldMap node is missing")
		return
	var first_position: Vector2 = npcs[0].position
	for _index in range(30):
		await physics_frame
	if npcs[0].position.distance_to(first_position) < 0.5:
		_fail("NPC movement simulation did not advance")
		return
	print("WORLD_SCENE_OK players=%d npcs=%d moving=true" % [players.size(), npcs.size()])
	scene.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
