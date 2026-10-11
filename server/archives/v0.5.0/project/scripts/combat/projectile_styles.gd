extends RefCounted
## Visual signatures are deterministic content. Radius and rendered core agree.
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/projectile_profiles.json"))

static func enemy(source: Dictionary) -> Dictionary:
	return catalog.get("profiles", {}).get(str(source.get("id", "")), {}).duplicate(true)

static func radius(profile: Dictionary, original: float) -> float:
	return clampf(original * float(profile.get("radius_scale", 1)), 3.5, 16)

static func preset(profile: Dictionary, line: bool = false) -> String:
	var family = str(profile.get("family", "ink"))
	if line: return family + "_" + ["beam_lance", "beam_tether", "beam_wave", "beam_fork"][int(profile.get("ribs", 3)) % 4]
	return family + "_" + ["blast", "ring", "vortex", "field"][int(profile.get("orbit", 0)) % 4]
