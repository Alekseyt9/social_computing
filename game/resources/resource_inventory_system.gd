class_name ResourceInventorySystem
extends RefCounted

## Canonical ledger for money and physical items. All mutations go through one
## atomic transfer operation so aggregate quantities stay conserved.

var _definitions: Dictionary
var _accounts: Dictionary = {}
var _expected_money_cents: int = 0
var _expected_item_totals: Dictionary = {}


func _init(definitions: Dictionary) -> void:
	_definitions = definitions.duplicate(true)
	for item_id: String in _definitions:
		_expected_item_totals[item_id] = 0


func register_account(
	person_id: int,
	money_cents: int,
	items: Dictionary,
	sale_item_ids: Array = []
) -> void:
	if _accounts.has(person_id):
		return
	var normalized_items: Dictionary = {}
	for item_id: String in _definitions:
		var quantity := maxi(0, int(items.get(item_id, 0)))
		normalized_items[item_id] = quantity
		_expected_item_totals[item_id] = int(_expected_item_totals[item_id]) + quantity
	var normalized_sales: Dictionary = {}
	for value: Variant in sale_item_ids:
		var item_id := str(value)
		if _definitions.has(item_id):
			normalized_sales[item_id] = true
	var balance := maxi(0, money_cents)
	_expected_money_cents += balance
	_accounts[person_id] = {
		"money_cents": balance,
		"items": normalized_items,
		"sale_items": normalized_sales,
	}


func has_account(person_id: int) -> bool:
	return _accounts.has(person_id)


func has_item(item_id: String) -> bool:
	return _definitions.has(item_id)


func get_definition(item_id: String) -> Dictionary:
	return _definitions.get(item_id, {}).duplicate(true)


func get_balance(person_id: int) -> int:
	return int(_accounts.get(person_id, {}).get("money_cents", 0))


func get_quantity(person_id: int, item_id: String) -> int:
	return int(_accounts.get(person_id, {}).get("items", {}).get(item_id, 0))


func is_for_sale(person_id: int, item_id: String) -> bool:
	return bool(_accounts.get(person_id, {}).get("sale_items", {}).get(item_id, false))


func get_inventory_view(person_id: int, sale_only: bool = false) -> Dictionary:
	var account: Dictionary = _accounts.get(person_id, {})
	if account.is_empty():
		return {"person_id": person_id, "money_cents": 0, "items": []}
	var items: Array[Dictionary] = []
	for item_id: String in _sorted_item_ids():
		var quantity := int(account.items.get(item_id, 0))
		if quantity <= 0:
			continue
		var for_sale := bool(account.sale_items.get(item_id, false))
		if sale_only and not for_sale:
			continue
		var definition: Dictionary = _definitions[item_id]
		items.append({
			"id": item_id,
			"label": str(definition.label),
			"quantity": quantity,
			"base_price_cents": int(definition.base_price_cents),
			"tags": definition.tags.duplicate(),
			"for_sale": for_sale,
		})
	return {
		"person_id": person_id,
		"money_cents": int(account.money_cents),
		"items": items,
	}


func transfer_item(
	source_id: int,
	recipient_id: int,
	item_id: String,
	quantity: int = 1,
	payment_cents: int = 0
) -> Dictionary:
	if source_id == recipient_id or not _accounts.has(source_id) or not _accounts.has(recipient_id):
		return {"ok": false, "error": "UNKNOWN_ACCOUNT"}
	if not _definitions.has(item_id) or quantity <= 0 or payment_cents < 0:
		return {"ok": false, "error": "INVALID_TRANSFER"}
	if get_quantity(source_id, item_id) < quantity:
		return {"ok": false, "error": "INSUFFICIENT_ITEMS"}
	if get_balance(recipient_id) < payment_cents:
		return {"ok": false, "error": "INSUFFICIENT_FUNDS"}
	var source: Dictionary = _accounts[source_id]
	var recipient: Dictionary = _accounts[recipient_id]
	source.items[item_id] = int(source.items[item_id]) - quantity
	recipient.items[item_id] = int(recipient.items[item_id]) + quantity
	source.money_cents = int(source.money_cents) + payment_cents
	recipient.money_cents = int(recipient.money_cents) - payment_cents
	_accounts[source_id] = source
	_accounts[recipient_id] = recipient
	return {
		"ok": true,
		"source_id": source_id,
		"recipient_id": recipient_id,
		"item_id": item_id,
		"item_label": str(_definitions[item_id].label),
		"quantity": quantity,
		"payment_cents": payment_cents,
		"source_balance_cents": int(source.money_cents),
		"recipient_balance_cents": int(recipient.money_cents),
	}


func snapshot() -> Dictionary:
	var actual_money := 0
	var actual_items: Dictionary = {}
	for item_id: String in _definitions:
		actual_items[item_id] = 0
	var checksum := 17
	var person_ids: Array = _accounts.keys()
	person_ids.sort()
	for person_id_value: Variant in person_ids:
		var person_id := int(person_id_value)
		var account: Dictionary = _accounts[person_id]
		actual_money += int(account.money_cents)
		checksum = int((checksum * 31 + person_id * 7 + int(account.money_cents)) & 0x7fffffff)
		for item_id: String in _sorted_item_ids():
			var quantity := int(account.items.get(item_id, 0))
			actual_items[item_id] = int(actual_items[item_id]) + quantity
			checksum = int((checksum * 31 + item_id.hash() + quantity * 13) & 0x7fffffff)
	return {
		"account_count": _accounts.size(),
		"money_cents": actual_money,
		"item_totals": actual_items,
		"money_conserved": actual_money == _expected_money_cents,
		"items_conserved": actual_items == _expected_item_totals,
		"checksum": "%08x" % checksum,
	}


func _sorted_item_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id: String in _definitions:
		result.append(item_id)
	result.sort()
	return result
