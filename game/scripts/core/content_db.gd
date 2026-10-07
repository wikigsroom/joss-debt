extends RefCounted
## JSON is the single content authority. Runtime capability gates live separately.

var catalog: Dictionary
var rules: Dictionary
var achievements_catalog: Dictionary
var expansion: Dictionary
var index: Dictionary = {}
var achievement_index: Dictionary = {}

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	achievements_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	expansion = JSON.parse_string(FileAccess.get_file_as_string("res://data/expansion.json"))
	for kind in catalog:
		if catalog[kind] is Array:
			index[kind] = {}
			for row in catalog[kind]:
				index[kind][row.id] = row
	for row in achievements_catalog.get("achievements", []):
		achievement_index[row.id] = row

func row(kind: String, id: String) -> Dictionary:
	return index.get(kind, {}).get(id, {})

func rows(kind: String) -> Array:
	return catalog.get(kind, [])

func achievement_row(id: String) -> Dictionary:
	return achievement_index.get(id, {})

func achievement_rows() -> Array:
	return achievements_catalog.get("achievements", [])

func name_of(kind: String, id: String) -> String:
	return str(row(kind, id).get("name", id))
