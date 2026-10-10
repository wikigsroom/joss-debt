extends RefCounted
## Lazy atlas textures keep the active chapter small; the paper-puppet pivots are shared.
const COUNTS = {"character": {"idle": 6, "run": 6, "cast": 6, "dash": 6, "hurt": 6, "death": 6},
	"enemy": {"idle": 3, "move": 4, "tell": 3, "attack": 6, "hurt": 6, "death": 5},
	"boss": {"idle": 3, "move": 8, "attack_a": 6, "attack_b": 6, "attack_c": 6, "phase": 3, "hurt": 6, "death": 6}, "npc": {"idle": 3, "talk": 3}}
const CHARACTER_FPS = {"idle": 6, "run": 12, "cast": 18, "dash": 30, "hurt": 18, "death": 10}
const FPS = {"idle": 5, "run": 12, "move": 10, "cast": 12, "dash": 15, "hurt": 16, "death": 10,
	"tell": 10, "attack": 12, "attack_a": 10, "attack_b": 12, "attack_c": 14, "phase": 8, "talk": 6}
var strips: Dictionary = {}
var frames: Dictionary = {}
var creature_actions: Dictionary = {}

func _init() -> void:
	var path = "res://assets/creature-actions.json"
	if FileAccess.file_exists(path):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
		if manifest is Dictionary: creature_actions = manifest.get("actors", {})

func has_creature_action(id: String, state: String) -> bool:
	return creature_actions.get(id, {}).get("states", {}).has(state)

func texture(id: String, kind: String, state: String, elapsed: float, direction: String = "down", frame_override: int = -1) -> Texture2D:
	var character_kind = kind in ["character", "weapon_body", "weapon_hand"]
	# Summoned doubles keep the boss's art even though their combat kind is enemy.
	if not character_kind and id.begins_with("b"): kind = "boss"
	var folder = {"character": "characters", "weapon_body": "weapon-bodies/animation", "weapon_hand": "weapon-bodies/hands", "enemy": "enemy-animation", "boss": "boss-animation", "npc": "npc-animation"}.get(kind, "enemy-animation")
	if id.begins_with("x"): folder = "elite-animation"
	if id == "sigil": folder = "sigil-animation"
	if id.begins_with("b") and state == "attack": state = "attack_a"
	var path = "res://assets/%s/%s/%s.png" % [folder, id, state]
	if not strips.has(path):
		if not ResourceLoader.exists(path): return null
		strips[path] = load(path)
	var frame_size = 96 if character_kind else (256 if kind == "boss" else 128)
	var count = maxi(1, int(strips[path].get_width() / frame_size))
	var drawn_action = has_creature_action(id, state)
	var fps = float(CHARACTER_FPS.get(state, 12) if character_kind else FPS.get(state, 12))
	if drawn_action: fps = float(creature_actions[id].states[state].fps)
	var index = maxi(0, int(elapsed * fps))
	var column = index % count if state in ["idle", "run", "move", "talk"] else mini(index, count - 1)
	if frame_override >= 0: column = clampi(frame_override, 0, count - 1)
	var row = maxi(0, ["down", "left", "right", "up"].find(direction)) if character_kind or drawn_action else 0
	# A malformed manifest must never sample pixels beyond the real texture.
	if (row + 1) * frame_size > strips[path].get_height(): return null
	var key = "%s:%d:%d" % [path, column, row]
	if not frames.has(key):
		var frame = AtlasTexture.new()
		frame.atlas = strips[path]
		frame.region = Rect2(column * frame_size, row * frame_size, frame_size, frame_size)
		frames[key] = frame
	return frames[key]

static func frame_index(kind: String, state: String, elapsed: float) -> int:
	var count = int(COUNTS[kind][state])
	var column = maxi(0, int(elapsed * (CHARACTER_FPS[state] if kind == "character" else FPS[state])))
	return column % count if state in ["idle", "run", "move", "talk"] else mini(column, count - 1)

func clear() -> void:
	frames.clear()
	strips.clear()
