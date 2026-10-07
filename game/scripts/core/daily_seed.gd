extends RefCounted
## Date-keyed challenge identity. It is local and deterministic; no network clock or service is required.
const VERSION := 1

static func date_dict(date_value: Dictionary = {}) -> Dictionary:
	if not date_value.is_empty(): return date_value
	return Time.get_date_dict_from_system()

static func key(date_value: Dictionary = {}) -> String:
	var date = date_dict(date_value)
	return "%04d-%02d-%02d" % [int(date.get("year", 1970)), int(date.get("month", 1)), int(date.get("day", 1))]

static func seed_for(date_value: Dictionary = {}) -> int:
	var date = date_dict(date_value)
	var raw = "%d-%d-%d-v%d" % [int(date.get("year", 1970)), int(date.get("month", 1)), int(date.get("day", 1)), VERSION]
	return posmod(raw.hash(), 2147483646) + 1

static func title(date_value: Dictionary = {}) -> String:
	return "每日种子 · " + key(date_value)

static func pool_version() -> String:
	return "initial-v1"
