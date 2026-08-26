extends SceneTree

const LightScheduleScript := preload("res://agents/light_schedule.gd")
const SimulationWorldScript := preload("res://core/simulation_world.gd")
const WorldMapScript := preload("res://world/world_map.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if WorldMapScript.WORLD_SIZE.x < 2200.0 or WorldMapScript.WORLD_SIZE.y < 1300.0:
		_fail("District map was not expanded")
		return
	if WorldMapScript.BUILDINGS.size() < 8:
		_fail("Expanded district has too few destinations")
		return
	var day_work_at_start: Dictionary = LightScheduleScript.resolve_state(
		"DAY_WORK", 0, 3, 1
	)
	var day_work_after_shift: Dictionary = LightScheduleScript.resolve_state(
		"DAY_WORK", 96, 3, 1
	)
	var day_work_evening: Dictionary = LightScheduleScript.resolve_state(
		"DAY_WORK", 120, 3, 1
	)
	var day_work_night: Dictionary = LightScheduleScript.resolve_state(
		"DAY_WORK", 168, 3, 1
	)
	if int(day_work_at_start.place_id) != 1 or str(day_work_at_start.activity) != "WORK":
		_fail("Day worker did not start the playable slice at work")
		return
	if int(day_work_after_shift.place_id) != 5 or str(day_work_after_shift.activity) != "ERRANDS":
		_fail("Day worker did not run errands after work")
		return
	if int(day_work_evening.place_id) != 4 or str(day_work_evening.activity) != "LEISURE":
		_fail("Day worker did not visit the park")
		return
	if int(day_work_night.place_id) != 3 or str(day_work_night.activity) != "HOME":
		_fail("Day worker did not return home")
		return
	var unemployed_morning := LightScheduleScript.resolve_state("UNEMPLOYED", 0, 3, 2)
	if int(unemployed_morning.place_id) != 6 or str(unemployed_morning.activity) != "JOB_SEARCH":
		_fail("Unemployed schedule does not use the community center")
		return

	var world := SimulationWorldScript.new(777001)
	var initial: Dictionary = world.get_light_population_snapshot()
	world.advance(96)
	var errands: Dictionary = world.get_light_population_snapshot()
	if int(errands.location_counts.get(5, 0)) <= 0:
		_fail("No population cohort reached the shopping quarter")
		return
	world.advance(24)
	var evening: Dictionary = world.get_light_population_snapshot()
	if int(evening.location_counts.get(4, 0)) <= 0:
		_fail("No population cohort reached the park")
		return
	if not bool(evening.money_conserved) or int(evening.population) != int(initial.population):
		_fail("Schedule movement broke population conservation")
		return

	var packed_scene := load("res://Main.tscn") as PackedScene
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var crowd: Node = scene.get_node("AmbientCrowd")
	scene.world.advance(96)
	scene._update_adaptive_focus(true)
	if int(crowd.get_traveling_count()) <= 0:
		_fail("Schedule boundary teleported every visible resident instead of routing commuters")
		return
	if int(crowd.get_visible_count()) > 45:
		_fail("Commuter retention exceeded the visual budget")
		return
	print("SCHEDULE_DISTRICT_OK size=%dx%d buildings=%d shops=%d park=%d travelers=%d budget=%d" % [
		int(WorldMapScript.WORLD_SIZE.x), int(WorldMapScript.WORLD_SIZE.y),
		WorldMapScript.BUILDINGS.size(), int(errands.location_counts.get(5, 0)),
		int(evening.location_counts.get(4, 0)), crowd.get_traveling_count(),
		crowd.get_visible_count(),
	])
	scene.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
