extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var world := SimulationWorldScript.new(271828)
	var initial: Dictionary = world.get_adaptive_population_snapshot()
	if not _assert_conservation(initial, "initial"):
		return
	if int(initial.aggregate_count) != 1140 or int(initial.light_agent_count) != 60:
		_fail("Unexpected initial adaptive split: %s" % initial)
		return
	if int(initial.story_persistent_count) != 20:
		_fail("Story persistent NPC layer is missing from adaptive report")
		return

	var anchor_id := 10_150
	var identity_before: Dictionary = world.get_light_agent_view(anchor_id)
	var local_refinement: Dictionary = world.refine_light_neighborhood(anchor_id, 1, 40)
	if not local_refinement.ok or world.get_light_agent_tier(anchor_id) != "LIGHT_AGENT":
		_fail("Local neighborhood refinement failed: %s" % local_refinement)
		return
	var locally_refined: Dictionary = world.get_adaptive_population_snapshot()
	if int(locally_refined.light_agent_count) <= 1 or int(locally_refined.light_agent_count) > 40:
		_fail("Neighborhood refinement ignored its bounds: %s" % locally_refined)
		return
	if not _assert_conservation(locally_refined, "local refinement"):
		return

	var promotion: Dictionary = world.promote_light_agent_to_persistent(
		anchor_id, "PLAYER_INTERACTION"
	)
	if not promotion.ok or world.get_light_agent_tier(anchor_id) != "PERSISTENT_NPC":
		_fail("LightAgent -> PersistentNPC promotion failed: %s" % promotion)
		return
	var promoted: Dictionary = world.get_adaptive_population_snapshot()
	if int(promoted.promoted_persistent_count) != 1:
		_fail("Promoted persistent agent is not represented exactly once")
		return
	if not _assert_conservation(promoted, "promotion"):
		return

	# Fully refine the connected sparse graph. The promoted agent remains in its
	# own tier and all other residents become LightAgents.
	var full_refinement: Dictionary = world.refine_all_light_agents()
	if not full_refinement.ok:
		_fail("Full refinement failed")
		return
	var fully_refined: Dictionary = world.get_adaptive_population_snapshot()
	if int(fully_refined.aggregate_count) != 0 or (
		int(fully_refined.light_agent_count) + int(fully_refined.promoted_persistent_count) != 1200
	):
		_fail("Aggregate -> LightAgent refinement did not materialize the population: %s" % fully_refined)
		return
	if not _assert_conservation(fully_refined, "full refinement"):
		return
	var full_steps_before: Dictionary = world.get_light_population_snapshot()
	world.advance(72)
	var full_steps_after: Dictionary = world.get_light_population_snapshot()
	var full_detailed_delta := int(full_steps_after.detailed_agent_steps) - int(full_steps_before.detailed_agent_steps)
	var full_aggregate_delta := int(full_steps_after.aggregate_agent_steps) - int(full_steps_before.aggregate_agent_steps)
	if full_detailed_delta < 1200 * 6 or full_aggregate_delta != 0:
		_fail("Fully refined population did not use detailed cadence")
		return

	# Refocusing automatically coarsens agents outside the new neighborhood.
	var refocus: Dictionary = world.refine_light_neighborhood(10_500, 0, 1)
	if not refocus.ok:
		_fail("Refocus/coarsening failed")
		return
	var coarsened: Dictionary = world.get_adaptive_population_snapshot()
	if int(coarsened.aggregate_count) != 1198 or int(coarsened.light_agent_count) != 1:
		_fail("LightAgent -> Aggregate coarsening returned wrong counts: %s" % coarsened)
		return
	if not _assert_conservation(coarsened, "coarsening"):
		return
	var coarse_steps_before: Dictionary = world.get_light_population_snapshot()
	world.advance(72)
	var coarse_steps_after: Dictionary = world.get_light_population_snapshot()
	var coarse_detailed_delta := int(coarse_steps_after.detailed_agent_steps) - int(coarse_steps_before.detailed_agent_steps)
	var coarse_aggregate_delta := int(coarse_steps_after.aggregate_agent_steps) - int(coarse_steps_before.aggregate_agent_steps)
	if coarse_aggregate_delta <= 0 or coarse_detailed_delta >= full_detailed_delta / 10:
		_fail("Coarsened population did not switch to low-frequency batch cadence")
		return

	world.advance(10 * 288 - 144)
	var after_days: Dictionary = world.get_adaptive_population_snapshot()
	if not _assert_conservation(after_days, "ten-day evolution"):
		return
	var identity_after: Dictionary = world.get_light_agent_view(anchor_id)
	if int(identity_before.id) != int(identity_after.id) or (
		int(identity_before.household_id) != int(identity_after.household_id)
	):
		_fail("Identity changed while the agent crossed adaptive tiers")
		return
	var adaptive_errors: Array[String] = world.validate_adaptive_population()
	if not adaptive_errors.is_empty():
		_fail("Adaptive validation failed after evolution: %s" % adaptive_errors)
		return

	var released: Dictionary = world.release_adaptive_persistent(anchor_id, true)
	if not released.ok or world.get_light_agent_tier(anchor_id) != "LIGHT_AGENT":
		_fail("PersistentNPC -> LightAgent release failed: %s" % released)
		return
	var final_coarsen: Dictionary = world.coarsen_light_agent(anchor_id)
	if not final_coarsen.ok or world.get_light_agent_tier(anchor_id) != "AGGREGATE":
		_fail("Released agent could not return to Aggregate tier")
		return
	var final_state: Dictionary = world.get_adaptive_population_snapshot()
	if not _assert_conservation(final_state, "final release"):
		return
	print("MILESTONE3_FOUNDATION_OK population=1200 aggregate=%d light=%d adaptive_persistent=%d story_persistent=20 transitions=%d conservation=true" % [
		final_state.aggregate_count,
		final_state.light_agent_count,
		final_state.promoted_persistent_count,
		final_state.transition_count,
	])
	quit(0)


func _assert_conservation(state: Dictionary, stage: String) -> bool:
	if not bool(state.conservation.all):
		_fail("Conservation failed during %s: %s" % [stage, state.conservation])
		return false
	var totals: Dictionary = state.tier_totals
	var represented := (
		int(totals.AGGREGATE.count)
		+ int(totals.LIGHT_AGENT.count)
		+ int(totals.PERSISTENT_NPC.count)
	)
	if represented != 1200:
		_fail("Tier totals represent %d agents during %s" % [represented, stage])
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
