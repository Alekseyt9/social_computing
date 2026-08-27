extends SceneTree

const SimulationWorldScript := preload("res://core/simulation_world.gd")


func _init() -> void:
	_run()


func _run() -> void:
	var world := SimulationWorldScript.new(606_101)
	var initial: Dictionary = world.get_resource_snapshot()
	if not bool(initial.money_conserved) or not bool(initial.items_conserved):
		_fail("Initial resource ledger violates conservation")
		return

	# Oleg is a barista because of his role, not a character-specific action:
	# provider role tokens give him public FOOD stock.
	var seller_id := 8
	world.introduce_people(world.player_id, seller_id)
	var buy_action := _find_action(world, seller_id, "BuyItem")
	if buy_action.is_empty() or str(buy_action.context.item_id) != "FOOD":
		_fail("Role-driven seller did not expose a computed BuyItem action")
		return
	var buyer_before: Dictionary = world.get_inventory_view(world.player_id, world.player_id)
	var seller_before: Dictionary = world.get_inventory_view(seller_id, seller_id)
	var food_before := _quantity(buyer_before, "FOOD")
	var price := int(buy_action.context.unit_price_cents)
	var buy_result: Dictionary = world.perform_social_action(
		"BuyItem", world.player_id, seller_id, buy_action.context
	)
	if not bool(buy_result.get("ok", false)) or str(buy_result.decision.decision) != "ACCEPT":
		_fail("Valid computed purchase was not accepted: %s" % buy_result)
		return
	var buyer_after: Dictionary = world.get_inventory_view(world.player_id, world.player_id)
	var seller_after: Dictionary = world.get_inventory_view(seller_id, seller_id)
	if _quantity(buyer_after, "FOOD") != food_before + 1:
		_fail("Purchased item was not transferred to buyer")
		return
	if int(buyer_after.money_cents) != int(buyer_before.money_cents) - price or (
		int(seller_after.money_cents) != int(seller_before.money_cents) + price
	):
		_fail("Atomic payment did not balance buyer and seller")
		return

	# Offering is also computed. Anna prefers a notebook from her role, so the
	# model selects that item from the player's inventory without a scripted line.
	var recipient_id := 2
	var offer_action := _find_action(world, recipient_id, "OfferItem")
	if offer_action.is_empty():
		_fail("Computed OfferItem action is missing")
		return
	var offer_result: Dictionary = world.perform_social_action(
		"OfferItem", world.player_id, recipient_id, offer_action.context
	)
	if not bool(offer_result.get("ok", false)) or str(offer_result.decision.decision) != "ACCEPT":
		_fail("Useful offered item was not accepted")
		return

	# A non-commercial request remains a real social decision. Rapport raises
	# trust through the normal relationship model until the NPC accepts the cost.
	var donor_id := 6
	world.introduce_people(world.player_id, donor_id)
	for _index in range(8):
		world.perform_social_action(
			"BuildRapport", world.player_id, donor_id,
			{"topic": "повседневные дела"}
		)
	var request_action := _find_action(world, donor_id, "RequestItem")
	if request_action.is_empty():
		_fail("Computed RequestItem action is missing")
		return
	var request_result: Dictionary = world.perform_social_action(
		"RequestItem", world.player_id, donor_id, request_action.context
	)
	if not bool(request_result.get("ok", false)) or str(request_result.decision.decision) != "ACCEPT":
		_fail("High-trust material request was not accepted by utility model")
		return

	var after_transfers: Dictionary = world.get_resource_snapshot()
	if not bool(after_transfers.money_conserved) or not bool(after_transfers.items_conserved):
		_fail("Resource transfer created or destroyed canonical value")
		return
	if after_transfers.item_totals != initial.item_totals or int(after_transfers.money_cents) != int(initial.money_cents):
		_fail("Aggregate resource totals changed after exchange")
		return

	# Command-log loading must reconstruct the exact balances and inventories.
	var restored: RefCounted = SimulationWorldScript.create_from_save_data(world.export_save_data())
	if restored == null:
		_fail("Resource exchange command log failed integrity restore")
		return
	if restored.get_resource_snapshot() != world.get_resource_snapshot() or (
		restored.get_inventory_view(world.player_id, world.player_id) != world.get_inventory_view(world.player_id, world.player_id)
	):
		_fail("Resource ledger differs after save/load replay")
		return

	# Observer safety: known people expose sale stock but never their wallet.
	var public_seller: Dictionary = world.get_inventory_view(world.player_id, seller_id)
	if int(public_seller.money_cents) != 0 or public_seller.items.is_empty():
		_fail("Observer-safe public stock view is incorrect")
		return
	print("D6_RESOURCE_EXCHANGE_OK accounts=%d money=%d checksum=%s buy=%s offer=%s request=%s" % [
		int(after_transfers.account_count), int(after_transfers.money_cents),
		str(after_transfers.checksum), str(buy_action.context.item_id),
		str(offer_action.context.item_id), str(request_action.context.item_id),
	])
	quit(0)


func _find_action(world: RefCounted, target_id: int, action_type: String) -> Dictionary:
	for action: Dictionary in world.get_available_social_actions(world.player_id, target_id):
		if str(action.type) == action_type:
			return action
	return {}


func _quantity(inventory: Dictionary, item_id: String) -> int:
	for item: Dictionary in inventory.items:
		if str(item.id) == item_id:
			return int(item.quantity)
	return 0


func _fail(message: String) -> void:
	push_error("D6_RESOURCE_EXCHANGE_FAILED %s" % message)
	quit(1)
