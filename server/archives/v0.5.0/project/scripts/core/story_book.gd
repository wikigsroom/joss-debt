extends RefCounted
## Stable localization IDs; reading does not grant combat or account rewards.
var content: Dictionary

func _init() -> void:
	content = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.zh_CN.json"))

func available(page: Dictionary, profile: Dictionary) -> bool:
	var requirement = str(page.requires)
	if requirement.is_empty(): return true
	if requirement == "personal": return int(profile.personal[page.character].stage) >= 3
	if requirement.begins_with("ending:"): return profile.endings.has(requirement.trim_prefix("ending:"))
	return profile.bosses.has(requirement)

func pages(profile: Dictionary, character: String = "") -> Array:
	return content.pages.filter(func(page): return available(page, profile) and (character.is_empty() or page.character == character))

func npc(id: String, index: int = 0) -> String:
	var lines = content.npc_lines.get(id, [])
	return str(lines[posmod(index, lines.size())]) if not lines.is_empty() else ""
