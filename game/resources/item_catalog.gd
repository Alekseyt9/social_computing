class_name ItemCatalog
extends RefCounted

## Data-driven material vocabulary. Simulation code reasons about ids/tags and
## never branches on a particular character name.


static func definitions() -> Dictionary:
	return {
		"FOOD": {
			"id": "FOOD",
			"label": "готовая еда",
			"base_price_cents": 22_000,
			"tags": ["FOOD", "RECOVERY", "SOCIAL"],
			"provider_role_tokens": ["barista", "cafe", "catering"],
		},
		"MEDICINE": {
			"id": "MEDICINE",
			"label": "лекарство",
			"base_price_cents": 48_000,
			"tags": ["HEALTH", "RECOVERY"],
			"provider_role_tokens": ["clinic", "doctor", "medical"],
		},
		"TOOL": {
			"id": "TOOL",
			"label": "набор инструментов",
			"base_price_cents": 90_000,
			"tags": ["CRAFT", "WORK", "REPAIR"],
			"provider_role_tokens": ["engineer", "contractor", "workshop"],
		},
		"NOTEBOOK": {
			"id": "NOTEBOOK",
			"label": "блокнот",
			"base_price_cents": 18_000,
			"tags": ["STUDY", "WORK", "INFORMATION"],
			"provider_role_tokens": ["journalist", "editor", "photographer", "designer"],
		},
	}

